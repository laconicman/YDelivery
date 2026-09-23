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
    /// The most recent sync failure — rendered beside history that may be stale,
    /// cleared by the next pass that lands.
    private(set) var lastError: (any Error)?
    /// When a pass last completed — the list's "fresh as of" answer.
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
            try await journalPasses(from: syncStore?.read().cursor)
            lastSyncedAt = .now
            lastError = nil
        } catch is JournalCursorInvalid {
            // The position rotted or belonged to another account — the feed
            // replays from the start and events are absolute, so the retry costs
            // requests, not truth.
            syncStore?.clear()
            do {
                try await journalPasses(from: nil)
                lastSyncedAt = .now
                lastError = nil
            } catch {
                lastError = error
            }
        } catch {
            lastError = error
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
            for searchState in states {
                var cursor: String?
                for _ in 0..<Self.maxPages {
                    let page = try await session.searchPage(state: searchState, cursor: cursor)
                    try await persistChanged(ClaimsSync.merging(page.claims, into: store.orders))
                    cursor = page.cursor
                    if cursor == nil { break }
                }
                if searchState == .finished {
                    state.historyBackfilled = true
                    try syncStore?.write(state)
                }
            }
            lastSyncedAt = .now
            lastError = nil
        } catch {
            lastError = error
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
    /// feed-discovered cards merged in. A card that refuses to be fetched skips
    /// the claim — the next event or tick asks again; one bad apple must not spoil
    /// the page's other updates.
    private func applyJournal(_ events: [Components.Schemas.JournalEvent]) async throws {
        var orders = store.orders
        for event in events {
            orders = ClaimsSync.applying(event, to: orders)
        }
        var discovered: [Components.Schemas.ClaimResponse] = []
        for id in ClaimsSync.missingClaimIDs(in: events, among: store.orders) {
            if let card = try? await session.claimCard(id: id) {
                discovered.append(card)
            }
        }
        orders = ClaimsSync.merging(discovered, into: orders)
        try await persistChanged(orders)
    }

    /// Writes the rows a merge actually changed — never re-persisting untouched
    /// history, so a no-op page writes nothing.
    private func persistChanged(_ merged: [Order]) async throws {
        for order in merged where store.orders.first(where: { $0.id == order.id }) != order {
            try await store.record(order)
        }
    }

    /// One standing-loop iteration — signed-in ticks sync, signed-out ticks idle.
    /// The sign-out edge wipes the sync state: the same identity boundary as the
    /// wire log's, so a new token never inherits this account's position.
    private func tick(_ count: Int) async {
        let signedIn = session.isSignedIn
        if wasSignedIn, !signedIn { syncStore?.clear() }
        if signedIn {
            if !wasSignedIn || count % Self.reconcileEveryTicks == 0 {
                await syncSearch()
            }
            await syncJournal()
        }
        wasSignedIn = signedIn
    }
}
