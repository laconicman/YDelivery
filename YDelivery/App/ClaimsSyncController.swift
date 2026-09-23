import Foundation
import Observation
import YandexDeliveryExpressAPI
import YDeliveryKit

/// Keeps the claims list truthful — the hybrid sync of Phase 3 (Design → "Claims
/// sync"). `claims/search` answers *what exists*: active and delayed claims every
/// pass, finished history once ever. `claims/journal` answers *what changed*,
/// polled between reconciliations. The store stays the list's only source: rows
/// render what the device remembers, and sync writes what the provider says.
///
/// The poll lives in a controller, not a view — a map or detail pushed over the
/// list must not freeze courier progress (CLAUDE.md rule 6; journal sync is the
/// settled example). Every pass is idempotent: events set absolute states and
/// merges key on `claimID`, so a re-run, a double fire, or a replayed page costs
/// requests, never correctness. Failures land in ``lastError`` — stale-but-readable
/// is a state to show, never a crash.
@Observable @MainActor
final class ClaimsSyncController {
    /// Each feed keeps its own failure — a journal success must not clear the
    /// search error it knows nothing about (review, PR #35). The view reads the
    /// union: whichever pass failed most recently is the staleness to show.
    private var searchError: (any Error)?
    private var journalError: (any Error)?
    /// The most recent sync failure — rendered beside history that may be stale.
    var lastError: (any Error)? { searchError ?? journalError }
    /// When a pass last completed — either feed; the union error above carries
    /// the "but this half is stale" signal the timestamp alone cannot.
    private(set) var lastSyncedAt: Date?
    private(set) var isSyncing = false

    private let session: ClientController
    private let store: StoreController
    private let syncStore: SyncStateStore?
    /// The standing loop — a weak capture whose `if let` strengthens only for one
    /// tick: a dead owner's task ends at the next hop, which is why no `deinit`
    /// cancel is needed (the `logObservation` precedent).
    private var loop: Task<Void, Never>?
    private var wasSignedIn = false

    /// The journal's poll cadence — cheap rows of what changed.
    private static let pollInterval: Duration = .seconds(30)
    /// Membership is re-asked every ~10 minutes of steady ticking; the feed fills
    /// the seconds between.
    private static let reconcileEveryTicks = 20
    /// The runaway-stop both feeds share — a pass that outlives this many pages is
    /// chasing its own tail, not syncing.
    private static let maxPages = 20

    init(
        session: ClientController,
        store: StoreController,
        syncStore: SyncStateStore? = .inAppGroup(id: AppGroup.id)
    ) {
        self.session = session
        self.store = store
        self.syncStore = syncStore
        loop = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                if let self { await self.tick(ticks) } else { return }
                ticks += 1
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    /// The visible-sync affordance — the list's appear and its pull-to-refresh ask
    /// for both halves: membership first (it discovers), then the delta catch-up.
    func syncNow() async {
        await syncSearch()
        await syncJournal()
    }

    /// The delta pass: journal events applied to known claims, whole cards fetched
    /// for claims history never recorded. The cursor persists only *after* the
    /// page's events land — a crash mid-page replays, and replay is safe because
    /// every event sets an absolute state.
    func syncJournal() async {
        // One pass at a time — a manual pull landing on a running tick is a no-op,
        // not a doubled feed. Idempotency makes the skip free.
        guard session.isSignedIn, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await store.refresh()
        do {
            try await drainPendingDiscovery()
            try await journalPasses(from: syncStore?.read().cursor)
            lastSyncedAt = .now
            journalError = nil
        } catch is JournalCursorInvalid {
            // The position rotted — restart it and nothing else: the pending
            // queue and the backfill flag are the account's, not the cursor's,
            // so the wipe that clears *them* belongs to the identity boundary.
            if var state = syncStore?.read() {
                state.cursor = nil
                try? syncStore?.write(state)
            }
            do {
                try await journalPasses(from: nil)
                lastSyncedAt = .now
                journalError = nil
            } catch {
                journalError = error
            }
        } catch {
            journalError = error
        }
    }

    /// The membership pass: `active` and `delayed` every time — the claims that can
    /// still move — `finished` once ever, the deep backfill recorded in the sync
    /// store so it never repeats. A claim created on another device, by support,
    /// or before install is exactly what search exists to find (the reason the
    /// journal alone is not enough: it only reports claims that *change*).
    func syncSearch() async {
        guard session.isSignedIn, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await store.refresh()
        do {
            var state = syncStore?.read() ?? .init(cursor: nil, historyBackfilled: false)
            var states: [Components.Schemas.SearchClaimState] = [.active, .delayed]
            if !state.historyBackfilled { states.append(.finished) }
            var truncated = false
            for searchState in states {
                var cursor: String?
                for _ in 0..<Self.maxPages {
                    let page = try await session.searchPage(state: searchState, cursor: cursor)
                    try await persistChanged(ClaimsSync.merging(page.claims, into: store.orders))
                    cursor = page.cursor
                    if cursor == nil { break }
                }
                // A live cursor after the last page means membership beyond the
                // cap — real claims the pass never reached. `finished` above all
                // must not stamp its flag: backfilled means *all of it*, and a
                // truncated pass is not all of it (review, PR #35).
                if cursor != nil {
                    truncated = true
                } else if searchState == .finished {
                    state.historyBackfilled = true
                    try syncStore?.write(state)
                }
            }
            if truncated { throw SyncIncomplete() }
            lastSyncedAt = .now
            searchError = nil
        } catch {
            searchError = error
        }
    }

    /// Page after page of the feed, applying then persisting — the cursor's write
    /// follows the page's events, never precedes them.
    private func journalPasses(from start: String?) async throws {
        var cursor = start
        for _ in 0..<Self.maxPages {
            let page = try await session.journalPage(cursor: cursor)
            try await applyJournal(page.events)
            if var state = syncStore?.read() {
                state.cursor = page.cursor
                try syncStore?.write(state)
            }
            cursor = page.cursor
            if page.events.isEmpty { break }
        }
    }

    /// One page of events: statuses and prices onto known claims, then the
    /// feed-discovered cards merged in. A card that refuses to be fetched does
    /// not spoil the page — but it is *not* forgotten: the cursor advances past
    /// these events, so the claim joins the persisted pending queue the next
    /// pass drains (review, PR #35).
    private func applyJournal(_ events: [Components.Schemas.JournalEvent]) async throws {
        var orders = store.orders
        for event in events {
            orders = ClaimsSync.applying(event, to: orders)
        }
        var discovered: [Components.Schemas.ClaimResponse] = []
        var missed: [String] = []
        for id in ClaimsSync.missingClaimIDs(in: events, among: orders) {
            if let card = try? await session.claimCard(id: id) {
                discovered.append(card)
            } else {
                missed.append(id)
            }
        }
        orders = ClaimsSync.merging(discovered, into: orders)
        try await persistChanged(orders)
        if !missed.isEmpty, var state = syncStore?.read() {
            state.pendingClaimIDs = Array(Set(state.pendingClaimIDs ?? []).union(missed)).sorted()
            try syncStore?.write(state)
        }
    }

    /// Retries the claims whose card fetch failed under an earlier cursor — the
    /// pending queue is the only memory of them once the feed moved on. Entries
    /// resolved by any pass (this drain or a search) drop out; entries still
    /// refusing stay for the next tick.
    private func drainPendingDiscovery() async throws {
        guard let syncStore else { return }
        var state = syncStore.read()
        let pending = state.pendingClaimIDs ?? []
        let unknown = pending.filter { id in !store.orders.contains { $0.claimID == id } }
        guard !unknown.isEmpty else {
            if !pending.isEmpty {
                state.pendingClaimIDs = []
                try? syncStore.write(state)
            }
            return
        }
        var discovered: [Components.Schemas.ClaimResponse] = []
        var stillPending: [String] = []
        for id in unknown {
            if let card = try? await session.claimCard(id: id) {
                discovered.append(card)
            } else {
                stillPending.append(id)
            }
        }
        try await persistChanged(ClaimsSync.merging(discovered, into: store.orders))
        state.pendingClaimIDs = stillPending
        try syncStore.write(state)
    }

    /// Writes the rows a merge actually changed — never re-persisting untouched
    /// history, so a no-op page writes nothing.
    private func persistChanged(_ merged: [Order]) async throws {
        for order in merged where store.orders.first(where: { $0.id == order.id }) != order {
            try await store.record(order)
        }
    }

    /// Everything bound to one account's identity, forgotten at the boundary —
    /// called synchronously from `ClientController.onIdentityChange`, which fires
    /// inside `signIn`/`signOut` themselves: the exact moment a 30-second tick
    /// cannot see (a sign-out *and* a sign-in inside one interval, review PR #35).
    /// The tick's own edge calls it too, as the fallback when the hook is unwired.
    func resetIdentityState() {
        syncStore?.clear()
        searchError = nil
        journalError = nil
        lastSyncedAt = nil
    }

    /// One standing-loop iteration — signed-in ticks sync, signed-out ticks idle.
    /// The sign-out edge wipes the sync state: the same identity boundary as the
    /// wire log's, so a new token never inherits this account's position.
    private func tick(_ count: Int) async {
        let signedIn = session.isSignedIn
        if wasSignedIn, !signedIn { resetIdentityState() }
        if signedIn {
            if !wasSignedIn || count % Self.reconcileEveryTicks == 0 {
                await syncSearch()
            }
            await syncJournal()
        }
        wasSignedIn = signedIn
    }
}
