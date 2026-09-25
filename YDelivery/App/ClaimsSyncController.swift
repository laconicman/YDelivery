import BackgroundTasks
import Foundation
import Observation
import OSLog
import YandexDeliveryExpressAPI
import YDeliveryKit

/// The marker a resumed pass throws when the identity generation moved under it —
/// its writes are dropped at the guards and the catch is swallowed: abandonment
/// by a newer identity is not a failure worth a footnote (review, PR #35).
private struct SyncSuperseded: Error {}

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
    /// search error it knows nothing about (review, PR #35). Timestamps, not a
    /// fixed union order, pick the view's line: an older refusal must not mask
    /// the failure that happened last.
    private var searchError: (error: any Error, at: Date)?
    private var journalError: (error: any Error, at: Date)?
    /// The most recent sync failure — rendered beside history that may be stale.
    var lastError: (any Error)? {
        switch (searchError, journalError) {
        case let (search?, journal?): search.at > journal.at ? search.error : journal.error
        case let (search?, nil): search.error
        case let (nil, journal?): journal.error
        case (nil, nil): nil
        }
    }
    /// When a pass last completed — either feed; the union error above carries
    /// the "but this half is stale" signal the timestamp alone cannot.
    private(set) var lastSyncedAt: Date?
    private(set) var isSyncing = false

    private let session: ClientController
    private let store: StoreController
    private let database: AppDatabase?
    /// The lock-screen surface feed events drive — optional so previews and
    /// tests can stand the controller up without a notification center.
    private let notifications: NotificationController?
    /// The standing loop — owned, and cancelled in `deinit` per rule 6's
    /// convention. `nonisolated` is what makes that possible (a `deinit` cannot
    /// reach a MainActor member; `@ObservationIgnored` keeps the macro from
    /// stamping it onto generated storage), and the weak capture is the second
    /// belt: a dead owner's task ends at the next hop even if cancel doesn't.
    @ObservationIgnored private nonisolated(unsafe) var loop: Task<Void, Never>?
    private var wasSignedIn = false
    /// Bumped at every identity boundary. A pass captures it on entry and proves
    /// it again before every write — a suspended pass holding the previous
    /// credential resumes into a cleared file, and only the check keeps its
    /// response from repopulating the old account's state (review, PR #35).
    private var identityGeneration = 0

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "YDelivery", category: "claims-sync")

    /// Set when the identity-boundary wipe threw: the account key is shared, so a
    /// stale row would otherwise answer for the *next* credential — its cursor,
    /// its backfill flag, its pending claims. While set, reads use an in-memory
    /// fresh state and every pass retries the deletion first (review, PR #38).
    private var needsStateReset = false
    /// The generation the last tick saw. Compared, never a boolean sample: a
    /// sign-out *and* a sign-in inside one interval still reads as changed,
    /// and a mid-tick bump is not consumed by the tick's own bookkeeping.
    private var lastSeenGeneration = -1

    /// The journal's poll cadence — cheap rows of what changed.
    private static let pollInterval: Duration = .seconds(30)
    /// Membership is re-asked every ~10 minutes of steady ticking; the feed fills
    /// the seconds between.
    private static let reconcileEveryTicks = 20
    /// The runaway-stop both feeds share — a pass that outlives this many pages is
    /// chasing its own tail, not syncing.
    private static let maxPages = 20
    /// How long a lost acceptance stays worth asking about — the provider answers
    /// a real claim within days; past this, the row lapses to audit instead of
    /// polling forever (YD-5).
    private static let acceptanceWindow: TimeInterval = 7 * 24 * 3600

    /// The background-refresh task's identifier — must match
    /// `BGTaskSchedulerPermittedIdentifiers` in the generated Info.plist.
    nonisolated static let refreshTaskIdentifier = "com.learnable.YDelivery.claims-refresh"
    /// How soon after backgrounding the app asks to sync again — a hint to the
    /// system scheduler, not a timer: iOS grants refresh windows by usage and
    /// battery, and delivers them when it decides.
    private nonisolated static let refreshLeadTime: TimeInterval = 15 * 60

    init(
        session: ClientController,
        store: StoreController,
        database: AppDatabase? = .inAppGroup(
            id: AppGroup.id,
            providerAccountRef: SyncIdentity.providerAccountRef,
            containerIdentifier: SyncIdentity.cloudKitContainer),
        notifications: NotificationController? = nil
    ) {
        self.session = session
        self.store = store
        self.database = database
        self.notifications = notifications
        loop = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                if let self { await self.tick(ticks) } else { return }
                ticks += 1
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    deinit { loop?.cancel() }

    /// The visible-sync affordance — the list's appear and its pull-to-refresh ask
    /// for both halves: membership first (it discovers), then the delta catch-up.
    func syncNow() async {
        await syncSearch()
        await syncJournal()
    }

    /// The delta pass: journal events applied to known claims, whole cards fetched
    /// for claims history never recorded. The cursor persists only *after* the
    /// page's events land — a crash mid-page replays, and replay is safe because
    /// every event sets an absolute state. Returns whether the pass completed —
    /// the background-refresh handler reports it to `BGTask` so a failed pass
    /// doesn't read as success to the scheduler; a skipped pass (signed out,
    /// already running) is vacuously true.
    @discardableResult
    func syncJournal() async -> Bool {
        // One pass at a time — a manual pull landing on a running tick is a no-op,
        // not a doubled feed. Idempotency makes the skip free.
        guard session.isSignedIn, !isSyncing else { return true }
        isSyncing = true
        defer { isSyncing = false }
        let identity = identityGeneration
        await store.refresh()
        do {
            try await drainPendingAcceptances(identity: identity)
            try await drainPendingDiscovery(identity: identity)
            try await journalPasses(from: syncState().cursor, identity: identity)
            lastSyncedAt = .now
            journalError = nil
            return true
        } catch is JournalCursorInvalid {
            // The position rotted — restart it and nothing else: the pending
            // queue and the backfill flag are the account's, not the cursor's,
            // so the wipe that clears *them* belongs to the identity boundary.
            var state = syncState()
            state.cursor = nil
            try? writeSyncState(state, identity: identity)
            do {
                try await journalPasses(from: nil, identity: identity)
                lastSyncedAt = .now
                journalError = nil
                return true
            } catch is SyncSuperseded {
                return true
            } catch {
                journalError = (error, .now)
                return false
            }
        } catch is SyncSuperseded {
            // The identity moved mid-pass — its writes were dropped at the
            // guards, and the new account's own passes start fresh.
            return true
        } catch {
            journalError = (error, .now)
            return false
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
        let identity = identityGeneration
        await store.refresh()
        do {
            var state = syncState()
            var states: [Components.Schemas.SearchClaimState] = [.active, .delayed]
            if !state.historyBackfilled { states.append(.finished) }
            var truncated = false
            for searchState in states {
                var cursor: String?
                for _ in 0..<Self.maxPages {
                    let page = try await session.searchPage(state: searchState, cursor: cursor)
                    let merged = ClaimsSync.merging(page.claims, into: store.orders)
                    try await persistChanged(merged,
                                             stamps: ClaimsSync.stamps(of: page.claims),
                                             identity: identity)
                    try await recordSightings(page.claims, among: merged,
                                              source: "search", identity: identity)
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
                    try writeSyncState(state, identity: identity)
                }
            }
            if truncated { throw SyncIncomplete() }
            lastSyncedAt = .now
            searchError = nil
        } catch is SyncSuperseded {
        } catch {
            searchError = (error, .now)
        }
    }

    /// Page after page of the feed, applying then persisting — the cursor's write
    /// follows the page's events, never precedes them.
    private func journalPasses(from start: String?, identity: Int) async throws {
        var cursor = start
        for _ in 0..<Self.maxPages {
            let page = try await session.journalPage(cursor: cursor)
            try await applyJournal(page.events, identity: identity)
            var state = syncState()
            state.cursor = page.cursor
            try writeSyncState(state, identity: identity)
            cursor = page.cursor
            if page.events.isEmpty { break }
        }
    }

    /// One page of events: statuses and prices onto known claims, then the
    /// feed-discovered cards merged in. A card that refuses to be fetched does
    /// not spoil the page — but it is *not* forgotten: the cursor advances past
    /// these events, so the claim joins the persisted pending queue the next
    /// pass drains (review, PR #35).
    private func applyJournal(_ events: [Components.Schemas.JournalEvent],
                              identity: Int) async throws {
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
        // Provider-side as-of stamps — an event's own `updatedTs`, a card's
        // own. The mirror's freshness follows the provider's clock, never the
        // read's: a stale page can't rewind what a newer event already saw.
        var stamps = ClaimsSync.stamps(of: discovered)
        for event in events {
            stamps[event.claimId] = max(stamps[event.claimId] ?? .distantPast,
                                        event.updatedTs)
        }
        try await persistChanged(orders, stamps: stamps, identity: identity)
        // The feed's own rows land after the merge so a just-discovered
        // claim's events record against its new row.
        try await recordJournal(events, among: orders, identity: identity)
        try await recordSightings(discovered, among: orders,
                                  source: "card", identity: identity)
        if !missed.isEmpty {
            var state = syncState()
            state.pendingClaimIDs = Array(Set(state.pendingClaimIDs ?? []).union(missed)).sorted()
            try writeSyncState(state, identity: identity)
        }
    }

    /// The ordering flow's lost answer, persisted before the screen can forget
    /// it — `Ordering.unresolved` without this dies with the draft (YD-5). A
    /// signed-out session notes nothing: the boundary's wipe takes the row
    /// anyway, and an unsigned app has no credential to reconcile it with.
    func noteUnresolvedAcceptance(claimID: String) {
        guard session.isSignedIn else { return }
        do {
            try database?.noteUnresolvedAcceptance(claimID: claimID)
        } catch {
            Self.logger.error(
                "Pending-acceptance note failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The acceptance queue's drain — the surviving sliver of YD-5. Every tick
    /// asks after a claim the flow lost the answer to, until it materializes
    /// (resolved into the order it becomes), outlives the window (lapsed — the
    /// poll stops, the audit row stays), or the account signs out (the identity
    /// wipe takes it). A claim history already knows resolves by presence:
    /// whichever pass landed it, the owed answer is paid.
    private func drainPendingAcceptances(identity: Int) async throws {
        // `flushOwedReset` before the read: while a boundary wipe is still owed the
        // queue may belong to the previous credential — no row is trustworthy yet
        // (review, PR #47).
        guard let database, flushOwedReset() else { return }
        let horizon = Date.now.addingTimeInterval(-Self.acceptanceWindow)
        var discovered: [Components.Schemas.ClaimResponse] = []
        for acceptance in database.pendingAcceptances() {
            guard identity == identityGeneration else { throw SyncSuperseded() }
            if let known = store.orders.first(where: { $0.claimID == acceptance.claimID }) {
                try database.markPendingAcceptance(
                    acceptance, as: .resolved(orderID: known.id))
            } else if acceptance.createdAt < horizon {
                try database.markPendingAcceptance(acceptance, as: .lapsed)
            } else if let card = try? await session.claimCard(id: acceptance.claimID) {
                discovered.append(card)
            } else {
                try database.markPendingAcceptance(acceptance, as: .checked)
            }
        }
        guard !discovered.isEmpty else { return }
        let merged = ClaimsSync.merging(discovered, into: store.orders)
        try await persistChanged(merged, stamps: ClaimsSync.stamps(of: discovered),
                                 identity: identity)
        // `card`, like the discovery drain's: a card fetch is one source whichever
        // queue asked for it — a distinct value would mint a second sighting row
        // for the same provider fact.
        try await recordSightings(discovered, among: merged,
                                  source: "card", identity: identity)
        for acceptance in database.pendingAcceptances()
        where discovered.contains(where: { $0.id == acceptance.claimID }) {
            guard identity == identityGeneration else { throw SyncSuperseded() }
            guard let order = merged.first(where: { $0.claimID == acceptance.claimID })
            else { continue }
            try database.markPendingAcceptance(
                acceptance, as: .resolved(orderID: order.id))
        }
    }

    /// Retries the claims whose card fetch failed under an earlier cursor — the
    /// pending queue is the only memory of them once the feed moved on. Entries
    /// resolved by any pass (this drain or a search) drop out; entries still
    /// refusing stay for the next tick.
    private func drainPendingDiscovery(identity: Int) async throws {
        guard database != nil else { return }
        var state = syncState()
        let pending = state.pendingClaimIDs ?? []
        let unknown = pending.filter { id in !store.orders.contains { $0.claimID == id } }
        guard !unknown.isEmpty else {
            if !pending.isEmpty {
                state.pendingClaimIDs = []
                try? writeSyncState(state, identity: identity)
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
        let merged = ClaimsSync.merging(discovered, into: store.orders)
        try await persistChanged(merged, stamps: ClaimsSync.stamps(of: discovered),
                                 identity: identity)
        try await recordSightings(discovered, among: merged,
                                  source: "card", identity: identity)
        state.pendingClaimIDs = stillPending
        try writeSyncState(state, identity: identity)
    }

    /// Writes the rows a merge actually changed — never re-persisting untouched
    /// history, so a no-op page writes nothing. Each write re-proves the identity:
    /// a switch mid-loop must not let the old account's rows into the file.
    /// `stamps` keys provider-side as-of time by claimID — the claim's or event's
    /// own `updatedTs`, so the mirror's freshness is provider truth, not the
    /// read's clock (Kit: the column only moves forward).
    private func persistChanged(_ merged: [Order], stamps: [String: Date],
                                identity: Int) async throws {
        for order in merged where store.orders.first(where: { $0.id == order.id }) != order {
            guard identity == identityGeneration else { throw SyncSuperseded() }
            // TODO(YD-13): the record still suspends — a boundary inside it lands
            // one row late; bounded while the store is not per-account.
            try await store.record(order,
                                   providerObservedAt: order.claimID.flatMap { stamps[$0] })
        }
    }

    /// The feed's own history rows — one `ProviderEvent` per journal entry.
    /// `statusAdvanced` is the announce gate: only a genuinely new provider
    /// word banners, so a replayed page, a stale arrival, or a status the
    /// mirror already holds stays silent (Kit PR #7). A write failure throws
    /// the whole page: the cursor has not moved yet, so the next pass replays
    /// and the dedupe key makes the retry a merge, never a second row
    /// (review, PR #43 — a swallowed failure would lose the event for good).
    private func recordJournal(_ events: [Components.Schemas.JournalEvent],
                               among orders: [Order], identity: Int) async throws {
        for event in events {
            guard identity == identityGeneration else { throw SyncSuperseded() }
            guard let order = orders.first(where: { $0.claimID == event.claimId }) else {
                continue
            }
            let providerEvent = ClaimsSync.providerEvent(event, orderID: order.id)
            guard (try database?.recordProviderEvent(providerEvent))?.statusAdvanced == true
            else { continue }
            await notifications?.announce(providerEvent, for: order)
        }
    }

    /// The id-less half of the feed: every claim a pass sighted records a
    /// `ProviderEvent` keyed `orderID ‖ status ‖ source`. The hundredth
    /// sighting of the same status merges into its first row yet still
    /// freshens the mirror's stamp — and a status the journal never reported
    /// (a feed gap) still announces through this backstop. Failures throw like
    /// `recordJournal`'s: the pass fails and replays rather than losing the
    /// sighting permanently (review, PR #43).
    private func recordSightings(_ claims: [Components.Schemas.ClaimResponse],
                                 among orders: [Order],
                                 source: String, identity: Int) async throws {
        for claim in claims {
            guard identity == identityGeneration else { throw SyncSuperseded() }
            guard let order = orders.first(where: { $0.claimID == claim.id }) else {
                continue
            }
            let sighting = ClaimsSync.sighting(of: claim, orderID: order.id, source: source)
            guard (try database?.recordProviderEvent(sighting))?.statusAdvanced == true
            else { continue }
            await notifications?.announce(sighting, for: order)
        }
    }

    /// The background-refresh half: iOS wakes the app briefly, one journal pass
    /// is the whole job — the feed's cheap delta, not the membership re-ask.
    /// The next request is armed *first*, so a run killed mid-pass still
    /// leaves a wake-up queued behind it. `nonisolated`: the launch handler
    /// runs on a system background queue (`nil` in `register`), and everything
    /// here — `BGTaskScheduler`, the `Task` spawn — is already off-actor safe;
    /// the journal pass itself hops to MainActor at the `await`.
    nonisolated func handleAppRefresh(_ task: BGAppRefreshTask) {
        scheduleAppRefresh()
        // BGTask predates Sendable — its completion/expiry API is thread-safe
        // by contract (the object lives to be driven from the queue the system
        // delivers it on), so the unchecked marker is honest, not a workaround.
        nonisolated(unsafe) let task = task
        let work = Task { @MainActor [weak self] in
            let completed = await self?.syncJournal() ?? true
            task.setTaskCompleted(success: completed && !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// Queues the next background wake — a hint, not a timer: iOS grants
    /// refresh windows by usage and battery. Called when the app backgrounds
    /// and re-armed inside each refresh run, so the chain survives a kill.
    /// `nonisolated`: `BGTaskScheduler` is thread-safe — the launch handler and
    /// the `.background` scene change call this from different executors.
    nonisolated func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = .now.addingTimeInterval(Self.refreshLeadTime)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The state file's only write path inside a pass: the identity is proved
    /// *after* every suspension and *before* the bytes land, because a cleared
    /// file must not be resurrected by a response the old credential fetched
    /// (review, PR #35).
    private func writeSyncState(_ state: SyncState, identity: Int) throws {
        guard identity == identityGeneration else { throw SyncSuperseded() }
        try database?.writeSyncState(state)
    }

    /// An owed boundary wipe, retried before any account-bound read — the account
    /// key is shared, so while `needsStateReset` stands stored rows would answer
    /// for the *next* credential (review, PR #38). Returns whether reads may
    /// proceed; a failed retry leaves the flag standing for the next pass.
    private func flushOwedReset() -> Bool {
        guard needsStateReset else { return true }
        do {
            try database?.clearSyncState()
            needsStateReset = false
            return true
        } catch {
            Self.logger.error(
                "Sync-state reset retry failed; reading fresh for this pass: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The stored position — unless a boundary wipe is still owed, in which case
    /// the read goes fresh in memory (the retry lives in `flushOwedReset`).
    private func syncState() -> SyncState {
        guard flushOwedReset() else {
            return SyncState(cursor: nil, historyBackfilled: false)
        }
        return database?.readSyncState() ?? SyncState(cursor: nil, historyBackfilled: false)
    }

    /// Everything bound to one account's identity, forgotten at the boundary —
    /// called synchronously from `ClientController.onIdentityChange`, which fires
    /// inside `signIn`/`signOut` themselves: the exact moment a 30-second tick
    /// cannot see (a sign-out *and* a sign-in inside one interval, review PR #35).
    /// The tick's own edge calls it too, as the fallback when the hook is unwired.
    func resetIdentityState() {
        identityGeneration += 1
        do {
            try database?.clearSyncState()
            needsStateReset = false
        } catch {
            needsStateReset = true
            Self.logger.error(
                "Identity-boundary state wipe failed; retrying before the next pass: \(error.localizedDescription, privacy: .public)")
        }
        searchError = nil
        journalError = nil
        lastSyncedAt = nil
        // The next tick must see this as a fresh sign-in — an out-and-in inside
        // one interval would otherwise keep `wasSignedIn` true and wait ~10
        // minutes for the reconcile tick to run search (review, PR #35).
        wasSignedIn = false
    }

    /// One standing-loop iteration — signed-in ticks sync, signed-out ticks idle.
    /// The sign-out edge wipes the sync state: the same identity boundary as the
    /// wire log's, so a new token never inherits this account's position.
    private func tick(_ count: Int) async {
        let signedIn = session.isSignedIn
        // Sampled at the top, not the end: a boundary crossing mid-tick bumps the
        // generation — writing the post-change value here would consume it and
        // silence the new account's membership pass until the reconcile counter
        // (review, PR #35).
        let generation = identityGeneration
        if wasSignedIn, !signedIn { resetIdentityState() }
        if signedIn {
            if generation != lastSeenGeneration || count % Self.reconcileEveryTicks == 0 {
                await syncSearch()
            }
            await syncJournal()
        }
        lastSeenGeneration = generation
        wasSignedIn = signedIn
    }
}
