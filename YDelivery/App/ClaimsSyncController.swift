import BackgroundTasks
import Foundation
import GRDB
import Observation
import OSLog
import UIKit
import YandexDeliveryExpressAPI
import YDeliveryKit

/// The marker a resumed pass throws when the identity generation moved under it —
/// its writes are dropped at the guards and the catch is swallowed: abandonment
/// by a newer identity is not a failure worth a footnote (review, PR #35).
private struct SyncSuperseded: Error {}

/// The marker a suspended pass throws instead of touching the state file —
/// caught beside `SyncSuperseded` as vacuously done: `readSyncState`'s
/// corrupt-file fallback would answer a *fresh* cursor for an interruption,
/// and replaying the feed from `nil` under a refusing queue is waste, not
/// recovery.
private struct SyncSuspended: Error {}

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
    /// When the journal was last read to the end of the feed — the one pass that
    /// vouches for every claim's current state. Search lists only what can still
    /// move, so a claim that finished between passes is the journal's alone to
    /// report: the Live Activities' stale dates run on this clock, never on
    /// ``lastSyncedAt`` (review, PR #134).
    private(set) var lastJournalSyncedAt: Date?
    private(set) var isSyncing = false

    private let session: ClientController
    private let store: StoreController
    private let database: AppDatabase?
    /// The one identity authority (built in `@main`, rule 2) — the party the feed's
    /// rows are attributed to. `nil` where the database is, and in tests that do
    /// not attribute.
    private let authority: (any IdentityAuthority)?
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

    /// Whether the queue is refusing locks — the passes' early out: a pass
    /// started suspended only replays the feed into `SQLITE_INTERRUPT`s and
    /// still counts as nothing. Written on the posts lane, read on the main
    /// actor — a stale read costs a pass the queue would refuse anyway, so
    /// `nonisolated(unsafe)` (the `loop` seam) is the honest cost.
    @ObservationIgnored private nonisolated(unsafe) static var suspended = false
    /// The active suspension era — bumped on every resume. A completion or a
    /// cleanup queued before the newer wake must not suspend over it: only an
    /// unchanged era may post suspend.
    @ObservationIgnored private nonisolated(unsafe) static var suspensionEra = 0
    /// The posts' own serial lane, off main: a `suspend` must reach the
    /// queue's observer even while a statement mid-step holds the lock on
    /// thread 0 — posted on main it would queue behind the very work it
    /// interrupts. Flag and post move together on the lane, so callers on
    /// different threads can never leave the flag disagreeing with the queue,
    /// and one lane keeps `suspend`/`resume` landing in call order.
    private nonisolated static let suspensionPosts =
        DispatchQueue(label: "YDelivery.db-suspension")

    /// `scenePhase → .background`, or a background wake ending: the queue stops
    /// taking locks *before* the freeze — an app suspended mid-lock is the kill
    /// family build 5 shipped (`RUNNINGBOARD 0xdead10cc`, three reports, all
    /// mid-read on this actor). The queue half lives in `AppDatabase`'s
    /// `observesSuspensionNotifications` wiring: the post refuses new locks and
    /// interrupts the in-flight statement so its lock lands back first (GRDB →
    /// DatabaseSharing, "How to limit the 0xDEAD10CC exception").
    nonisolated static func suspendDatabase() {
        suspensionPosts.sync {
            suspended = true
            NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
        }
    }

    /// `scenePhase → .active`, or the head of a background wake that may touch
    /// the database — GRDB's recipe names both.
    nonisolated static func resumeDatabase() {
        suspensionEra &+= 1
        suspensionPosts.sync {
            suspended = false
            NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
        }
    }

    /// The backgrounding drain's window — keeps the process awake just long
    /// enough for the detached draft write (and any in-flight access) to land
    /// before the queue stops taking locks.
    @ObservationIgnored private var suspensionWindow: UIBackgroundTaskIdentifier?
    /// The tail the window waits on — cancelled when a resume or a repeated
    /// backgrounding makes the wait moot.
    @ObservationIgnored private var suspensionDrain: Task<Void, Never>?

    /// `scenePhase → .background`: the detached draft write rides the store's
    /// serial tail — awaiting its end is the drain — inside a
    /// `beginBackgroundTask` window so the process is still awake to see the
    /// suspend land. iOS expiring the window first takes the same end:
    /// suspend, then release (the GRDB recipe's "expiration handler" seat).
    func beginSuspension() {
        suspensionDrain?.cancel()
        if let window = suspensionWindow {
            UIApplication.shared.endBackgroundTask(window)
            suspensionWindow = nil
        }
        let window = UIApplication.shared.beginBackgroundTask { [weak self] in
            // The window is spent — the freeze is next, locks go now; the hop
            // ends the window, but the post above already released the
            // in-flight lock.
            Self.suspendDatabase()
            Task { @MainActor in self?.endSuspensionWindow() }
        }
        guard window != .invalid else {
            // No grace granted — suspend at once rather than race the freeze.
            Self.suspendDatabase()
            return
        }
        suspensionWindow = window
        suspensionDrain = Task { [weak self] in
            await self?.store.drainDraftWrites()
            guard !Task.isCancelled else { return }
            self?.endSuspensionWindow()
        }
    }

    /// `scenePhase → .active`: locks serve again, and a drain still pending
    /// from the outgoing edge is moot — its window ends quietly. Notes parked
    /// while suspended land now — the queue answers again.
    func resumeFromSuspension() {
        suspensionDrain?.cancel()
        suspensionDrain = nil
        if let window = suspensionWindow {
            UIApplication.shared.endBackgroundTask(window)
            suspensionWindow = nil
        }
        Self.resumeDatabase()
        flushDeferredAcceptanceNotes()
    }

    /// The parked acceptance notes land wherever locks serve again —
    /// activation or a background wake, whichever comes first. Each stays
    /// parked only as long as the queue keeps refusing writes.
    private func flushDeferredAcceptanceNotes() {
        let deferred = deferredAcceptanceNotes
        deferredAcceptanceNotes = []
        for claimID in deferred { noteUnresolvedAcceptance(claimID: claimID) }
    }

    /// Both arrivals the window can take: drained or expired. The suspend is
    /// gated on the slot still being live — a resume or a newer backgrounding
    /// nils it first, and a cleanup queued before that must not suspend over
    /// the resumed queue.
    private func endSuspensionWindow() {
        suspensionDrain?.cancel()
        suspensionDrain = nil
        if let window = suspensionWindow {
            Self.suspendDatabase()
            UIApplication.shared.endBackgroundTask(window)
            suspensionWindow = nil
        }
    }

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
        notifications: NotificationController? = nil,
        authority: (any IdentityAuthority)? = nil
    ) {
        self.session = session
        self.store = store
        self.database = database
        self.notifications = notifications
        self.authority = authority
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
        guard session.isSignedIn, !isSyncing, !Self.suspended else { return true }
        isSyncing = true
        defer { isSyncing = false }
        let identity = identityGeneration
        await store.refresh()
        do {
            try await drainPendingAcceptances(identity: identity)
            try await drainPendingDiscovery(identity: identity)
            try await journalPasses(from: try syncState().cursor, identity: identity)
            lastJournalSyncedAt = .now
            lastSyncedAt = lastJournalSyncedAt
            journalError = nil
            await store.reconcileMemberships()
            return true
        } catch is JournalCursorInvalid {
            // The position rotted — restart it and nothing else: the pending
            // queue and the backfill flag are the account's, not the cursor's,
            // so the wipe that clears *them* belongs to the identity boundary.
            var state = (try? syncState())
                ?? SyncState(cursor: nil, historyBackfilled: false)
            state.cursor = nil
            try? writeSyncState(state, identity: identity)
            do {
                try await journalPasses(from: nil, identity: identity)
                lastJournalSyncedAt = .now
                lastSyncedAt = lastJournalSyncedAt
                journalError = nil
                await store.reconcileMemberships()
                return true
            } catch is SyncSuperseded, is SyncSuspended {
                return true
            } catch DatabaseError.SQLITE_INTERRUPT, DatabaseError.SQLITE_ABORT {
                return true
            } catch {
                journalError = (error, .now)
                return false
            }
        } catch is SyncSuperseded, is SyncSuspended {
            // The identity moved mid-pass — its writes were dropped at the
            // guards, and the new account's own passes start fresh.
            return true
        } catch DatabaseError.SQLITE_INTERRUPT, DatabaseError.SQLITE_ABORT {
            // The suspension gate closed mid-pass — vacuously done like a skip:
            // the cursor never claimed work it didn't land, so the pass after
            // resume replays honestly.
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
        guard session.isSignedIn, !isSyncing, !Self.suspended else { return }
        isSyncing = true
        defer { isSyncing = false }
        let identity = identityGeneration
        await store.refresh()
        do {
            var state = try syncState()
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
            // The share mirror rides the pass, truncated or not: membership is the
            // share's, not the provider's, and every order this device holds is
            // already in the store (doc:Collaboration, YD-45).
            await store.reconcileMemberships()
            if truncated { throw SyncIncomplete() }
            lastSyncedAt = .now
            searchError = nil
        } catch is SyncSuperseded, is SyncSuspended {
        } catch DatabaseError.SQLITE_INTERRUPT, DatabaseError.SQLITE_ABORT {
            // Suspended mid-pass — vacuous like the journal's: membership was
            // never proven, so the error state stays where it was.
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
            var state = try syncState()
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
        var discovered: [Components.Schemas.ClaimResponse] = []
        var missed: [String] = []
        for id in ClaimsSync.missingClaimIDs(in: events, among: store.orders) {
            if let card = try? await session.claimCard(id: id) {
                discovered.append(card)
            } else {
                missed.append(id)
            }
        }
        // Events and cards in the doctrine's total order, each claim stamped with
        // the provider stamp of the content it carries — never the batch's newest
        // over a card's older content (YD-46). The mirror's freshness follows the
        // provider's clock, never the read's: a stale page can't rewind what a
        // newer event already saw.
        let (orders, stamps) = ClaimsSync.folding(events, cards: discovered, into: store.orders)
        try await persistChanged(orders, stamps: stamps, identity: identity)
        // The feed's own rows land after the merge so a just-discovered
        // claim's events record against its new row.
        try await recordJournal(events, among: orders, identity: identity)
        try await recordSightings(discovered, among: orders,
                                  source: OrderEvent.Source.card, identity: identity)
        if !missed.isEmpty {
            var state = try syncState()
            state.pendingClaimIDs = Array(Set(state.pendingClaimIDs ?? []).union(missed)).sorted()
            try writeSyncState(state, identity: identity)
        }
    }

    /// Acceptance notes a suspended queue could not take — parked claim IDs,
    /// flushed on resume. Losing one is losing the whole record: the note is
    /// the only durable place the answer's claimID lives (YD-5).
    @ObservationIgnored private var deferredAcceptanceNotes: [String] = []

    /// The ordering flow's lost answer, persisted before the screen can forget
    /// it — `Ordering.unresolved` without this dies with the draft (YD-5). A
    /// signed-out session notes nothing: the boundary's wipe takes the row
    /// anyway, and an unsigned app has no credential to reconcile it with. A
    /// suspended queue parks the note for the resume flush rather than
    /// dropping it — suspension is exactly when the app may never come back
    /// to ask again.
    func noteUnresolvedAcceptance(claimID: String) {
        guard session.isSignedIn else { return }
        guard !Self.suspended else {
            deferredAcceptanceNotes.append(claimID)
            return
        }
        do {
            try database?.noteUnresolvedAcceptance(claimID: claimID)
        } catch {
            if (error as? DatabaseError)?.isInterruptionError == true {
                deferredAcceptanceNotes.append(claimID)
            } else {
                Self.logger.error(
                    "Pending-acceptance note failed: \(error.localizedDescription, privacy: .public)")
            }
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
        var state = try syncState()
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

    /// The feed's own history rows — one `OrderEvent` per journal entry.
    /// `statusAdvanced` is the announce gate: only a genuinely new provider
    /// word banners, so a replayed page, a stale arrival, or a status the
    /// mirror already holds stays silent (Kit PR #7). A write failure throws
    /// the whole page: the cursor has not moved yet, so the next pass replays
    /// and the dedupe key makes the retry a merge, never a second row
    /// (review, PR #43 — a swallowed failure would lose the event for good).
    private func recordJournal(_ events: [Components.Schemas.JournalEvent],
                               among orders: [Order], identity: Int) async throws {
        let party = authority?.localParty
        for event in events {
            guard identity == identityGeneration else { throw SyncSuperseded() }
            guard let order = orders.first(where: { $0.claimID == event.claimId }) else {
                continue
            }
            let providerEvent = ClaimsSync.providerEvent(
                event, orderID: order.id, authorRef: party)
            guard (try database?.recordEvent(providerEvent))?.statusAdvanced == true
            else { continue }
            await notifications?.announce(providerEvent, for: order)
        }
    }

    /// The id-less half of the feed: every claim a pass sighted records an
    /// `OrderEvent` keyed `orderID ‖ revision ‖ status ‖ routeDigest`
    /// (doc:Schema → "Epoch 2"). A re-sight of one revision merges into its
    /// first row yet still freshens the mirror's stamp — and a status the journal never reported
    /// (a feed gap) still announces through this backstop. Failures throw like
    /// `recordJournal`'s: the pass fails and replays rather than losing the
    /// sighting permanently (review, PR #43).
    private func recordSightings(_ claims: [Components.Schemas.ClaimResponse],
                                 among orders: [Order],
                                 source: String, identity: Int) async throws {
        let party = authority?.localParty
        for claim in claims {
            guard identity == identityGeneration else { throw SyncSuperseded() }
            guard let order = orders.first(where: { $0.claimID == claim.id }) else {
                continue
            }
            let sighting = ClaimsSync.sighting(
                of: claim, orderID: order.id, source: source, authorRef: party)
            guard (try database?.recordEvent(sighting))?.statusAdvanced == true
            else { continue }
            await notifications?.announce(sighting, for: order)
        }
    }

    /// The background-refresh half: iOS wakes the app briefly, one journal pass
    /// is the whole job — the feed's cheap delta, not the membership re-ask.
    /// The next request is armed *first*, so a run killed mid-pass still
    /// leaves a wake-up queued behind it. `nonisolated`: the launch handler is
    /// delivered on `.main` (see `register` in `YDeliveryApp`), but nothing
    /// here needs the actor — `BGTaskScheduler` and the `Task` spawn are
    /// off-actor safe, and the journal pass hops to MainActor at the `await`.
    /// `publish` runs after the pass and before completion — the surfaces that
    /// must move in this same wake (the Live Activities) are the composition
    /// root's to name; the view-side republication hooks cannot be counted on
    /// while the app is suspended between frames.
    nonisolated func handleAppRefresh(
        _ task: BGAppRefreshTask,
        publish: @escaping @MainActor () async -> Void = {}
    ) {
        scheduleAppRefresh()
        // A background wake may touch the database — GRDB's recipe resumes the
        // queue for it, then suspends again before the app refreezes.
        Self.resumeDatabase()
        let era = Self.suspensionEra
        // BGTask predates Sendable — its completion/expiry API is thread-safe
        // by contract (the object lives to be driven from the queue the system
        // delivers it on), so the unchecked marker is honest, not a workaround.
        nonisolated(unsafe) let task = task
        let work = Task { @MainActor [weak self] in
            // Parked notes first — a wake is a writable window too, and an
            // interrupted pass must not postpone them to the next activation.
            self?.flushDeferredAcceptanceNotes()
            let completed = await self?.syncJournal() ?? true
            await publish()
            // Suspend *before* completing — the freeze can land between the
            // two calls, and an obsolete wake must not suspend over an
            // activation that already resumed the queue.
            if Self.suspensionEra == era { Self.suspendDatabase() }
            task.setTaskCompleted(success: completed && !Task.isCancelled)
        }
        task.expirationHandler = {
            // The window just spent itself — the in-flight statement's lock
            // must land back before the freeze, which a cooperative cancel
            // cannot do (it is honored between statements, never inside one).
            Self.suspendDatabase()
            work.cancel()
        }
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
    /// Throws `SyncSuspended` rather than read under a refusing queue: the
    /// file's own fallback would answer a fresh cursor for an interruption,
    /// and a nil cursor replays history the saved one already proved.
    private func syncState() throws -> SyncState {
        guard !Self.suspended else { throw SyncSuspended() }
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
        lastJournalSyncedAt = nil
        // Parked notes are account-bound like the table they name — the wipe
        // takes them too.
        deferredAcceptanceNotes = []
        // The next tick must see this as a fresh sign-in — an out-and-in inside
        // one interval would otherwise keep `wasSignedIn` true and wait ~10
        // minutes for the reconcile tick to run search (review, PR #35).
        wasSignedIn = false
    }

    /// One standing-loop iteration — signed-in ticks sync, signed-out ticks idle.
    /// The sign-out edge wipes the sync state: the same identity boundary as the
    /// wire log's, so a new token never inherits this account's position.
    private func tick(_ count: Int) async {
        guard !Self.suspended else { return }
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
        } else if count % Self.reconcileEveryTicks == 0 {
            // The share is iCloud's, not the provider's: a participant who accepts
            // while the owner is signed out of the provider still gets a membership
            // row, at the membership cadence (review, PR #142). Signed in, the
            // passes above reconcile after each success.
            await store.reconcileMemberships()
        }
        lastSeenGeneration = generation
        wasSignedIn = signedIn
    }
}
