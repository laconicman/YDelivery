import ActivityKit
import Foundation
import OSLog
import YDeliveryKit

/// The Lock Screen and Dynamic Island half of the claims feed (board `5a`).
/// The activity starts locally — there is no push relay, so "started on order
/// creation, updated by polling" means exactly this: every store republication
/// is reconciled against the live activities, and each order's mirrored state
/// becomes its card's `ContentState`.
///
/// The state vocabulary is the board's: `.searching` and `.active` are live and
/// update; terminal states end the activity. Delivered is the ending that
/// dismisses itself — four minutes on the lock screen, then gone — while
/// `.cancelled` keeps its final card until the sender taps it away (board
/// `5a`). `.attention` stays *live*: a parked decision can recover, and an
/// ended `.default` card lingers visibly while the recovery starts a second
/// one — the same card must carry «needs your decision» and whatever answers
/// it (review, PR #44). An *archived* order ends its card whatever the status —
/// the shelf is out of sight, and a shelved terminal-attention claim must not
/// keep a Lock Screen card it no longer earns.
/// Orders with no claim yet, and activities whose order vanished (an account
/// switch wiped them), are swept the same way.
@Observable @MainActor
final class LiveActivityController {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "YDelivery", category: "live-activity")

    /// Board `5a`: «Вручено» is final but lingers — four minutes on the lock
    /// screen, then it dismisses itself.
    nonisolated static let deliveredLinger: TimeInterval = 4 * 60

    /// How long a card stays trustworthy after the app last checked the
    /// journal. There is no push relay, so a card only moves while the app
    /// runs: the foreground journal ticks every 30 seconds, a background wake
    /// is asked for every 15 minutes and granted when iOS decides. Two missed
    /// wakes means nobody is updating the card — past this the system flags it
    /// stale (`context.isStale`) and the Lock Screen says so instead of
    /// posing as live. The clock is the app's last *check*, not the
    /// provider's `providerObservedAt`: that stamp moves only when the claim
    /// changes, and a quiet half-hour en route is a healthy card. Nor is it a
    /// search, a store write or the wall clock: only a journal read to the end
    /// of the feed vouches for every card (``ClaimsSyncController/lastJournalSyncedAt``).
    nonisolated static let staleAfter: TimeInterval = 30 * 60

    /// The last reconcile's ActivityKit calls. Each pass chains behind the
    /// one before, so an update never overtakes the end that followed it,
    /// and ``settle()`` gives a background wake something to wait on — a
    /// fire-and-forget call is lost when the app suspends straight after.
    /// Plumbing, not presentation: no view observes it.
    @ObservationIgnored private var pass: Task<Void, Never>?

    /// Whether this controller touches the Lock Screen at all. The cards belong
    /// to *the* app's history, whichever store an instance reconciles against —
    /// a fixture store's orders must neither start cards nor sweep a real
    /// device's live ones as orphans (review, PR #61), so the screenshot launch
    /// builds an inert controller.
    private let reconciles: Bool

    init(reconciles: Bool = true) {
        self.reconciles = reconciles
    }

    /// What one reconcile pass does with an order — the board `5a` rules as a
    /// pure decision the tests can hold still, so the ActivityKit plumbing in
    /// `reconcile` stays unbranched.
    nonisolated enum Disposition: Equatable {
        /// Live — the card starts if absent, updates when the state moved.
        case updating
        /// How a final card leaves. `linger` is the board's delivered-only
        /// courtesy — four minutes, then it dismisses itself; `stayUntilTapped`
        /// keeps cancelled's last card until the sender swipes it; `immediate`
        /// is the shelf's: a shelved order vanishes, nothing left to dismiss.
        enum Ending: Equatable {
            case linger, stayUntilTapped, immediate
        }
        /// Final — write the last card and end it on the given policy.
        case ending(Ending)
        /// No card at all — a draft has no provider existence, a claim-less
        /// order none yet.
        case none

        init(status: OrderStatus, hasClaim: Bool, isArchived: Bool = false) {
            // Shelved first — the archive is out of sight on every surface, so
            // a running card ends now, whatever the status underneath.
            guard !isArchived else { self = .ending(.immediate); return }
            guard hasClaim else { self = .none; return }
            switch status {
            case .searching, .active, .attention: self = .updating
            case .done: self = .ending(.linger)
            case .cancelled: self = .ending(.stayUntilTapped)
            case .draft: self = .none
            }
        }
    }

    /// When a card the journal vouched for at `checkedAt` stops being
    /// trustworthy.
    nonisolated static func staleDate(checkedAt: Date) -> Date {
        checkedAt.addingTimeInterval(staleAfter)
    }

    /// The window a card carries after this pass — as fresh as the newest
    /// read that vouches for it: the order's own provider stamp (placement's
    /// answer, a merged sighting), the journal's last check, or the window the
    /// card already has. It never shrinks: a window says "no read since", and
    /// an older read cannot unsay a newer one — a fresh card updated during a
    /// journal outage keeps its own window, not the outage's (review, PR
    /// #134). Not the journal's alone: an order placed during an outage would
    /// be born flagged. Not birth alone: a launch or a shared-database arrival
    /// starts a card from disk state of its own age. `nil` when nothing
    /// vouches at all. The journal's check vouches for the feed, not this
    /// claim — a stampless order arriving from the shared database can borrow
    /// its window — but only for one window: re-arms need a newer check.
    nonisolated static func staleDate(
        observedAt: Date?, checkedAt: Date?, shown: Date?
    ) -> Date? {
        let vouched = [observedAt, checkedAt].compactMap(\.self).map(staleDate(checkedAt:))
        return (vouched + [shown].compactMap(\.self)).max()
    }

    /// Whether a live card must be re-sent: its state moved, or the last
    /// journal check is half a window past the one that armed it — a healthy
    /// sync re-arms the card before it would ever flag, at most one extra
    /// update per card per 15 minutes. Time alone never re-arms: with no newer
    /// check behind it — a failed or skipped journal pass, a search, a store
    /// write — a card runs out its window and says so (review, PR #134).
    nonisolated static func needsUpdate(
        shown: DeliveryActivityAttributes.ContentState, shownStaleDate: Date?,
        state: DeliveryActivityAttributes.ContentState, checkedAt: Date?
    ) -> Bool {
        guard let checkedAt else { return shown != state }
        return shown != state
            || (shownStaleDate ?? .distantPast) < checkedAt.addingTimeInterval(staleAfter / 2)
    }

    /// The store-facing entry: an unread store is not an empty one, and
    /// reconciling against `[]` would sweep every restored card as an orphan
    /// (review, PR #44). Every caller — the view's republication and
    /// journal-success hooks, and the background refresh — goes through this
    /// gate. `checkedAt` is the journal's last full read, the clock every stale
    /// date runs on.
    func reconcile(with store: StoreController, checkedAt: Date?) {
        guard store.hasLoaded else { return }
        reconcile(orders: store.orders, orderNumber: store.orderNumber(for:),
                  checkedAt: checkedAt)
    }

    /// Reconcile the store's truth against what the Lock Screen is showing.
    /// Called on every `store.orders` republication — the write funnel means
    /// sync merges, placement, and cancels all arrive through the one hook.
    /// `orderNumber` resolves the sender's own number — the surface's identity
    /// is «4417», never the vendor's claim id (board `5a`).
    func reconcile(orders: [Order], orderNumber: (Order.ID) -> String?,
                   checkedAt: Date?) {
        guard reconciles, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let live = Activity<DeliveryActivityAttributes>.activities
        var changes: [(Activity<DeliveryActivityAttributes>, Change)] = []
        for order in orders {
            let activity = live.first { $0.attributes.orderID == order.id }
            switch Disposition(status: order.status, hasClaim: order.claimID != nil,
                               isArchived: order.isArchived) {
            case .updating:
                let state = contentState(for: order, orderNumber: orderNumber)
                if let activity {
                    guard Self.needsUpdate(shown: activity.content.state,
                                           shownStaleDate: activity.content.staleDate,
                                           state: state, checkedAt: checkedAt) else { continue }
                    let staleDate = Self.staleDate(
                        observedAt: order.providerObservedAt, checkedAt: checkedAt,
                        shown: activity.content.staleDate)
                    changes.append((activity, .update(state, staleDate: staleDate)))
                } else {
                    // With nothing to date it by, a new card's window opens
                    // at its birth.
                    start(order: order, state: state,
                          staleDate: Self.staleDate(
                              observedAt: order.providerObservedAt, checkedAt: checkedAt,
                              shown: nil) ?? Self.staleDate(checkedAt: .now))
                }
            case .ending(let ending):
                if let activity {
                    let final = contentState(for: order, orderNumber: orderNumber)
                    let dismissal: ActivityUIDismissalPolicy = switch ending {
                    case .linger: .after(.now.addingTimeInterval(Self.deliveredLinger))
                    case .stayUntilTapped: .default
                    case .immediate: .immediate
                    }
                    changes.append((activity, .end(final, dismissal)))
                }
            case .none:
                // An order that slipped out of provider view — claim revoked,
                // a merge edge that dropped it — still holds the card it
                // earned live. The orphan sweep can't see it (its order is
                // still listed), so `.none` must end it, not skip it
                // (review, PR #44).
                if let activity {
                    changes.append((activity, .end(nil, .immediate)))
                }
            }
        }
        // An activity whose order is gone — wiped with the account, deleted —
        // ends quietly rather than posing as a live delivery.
        let known = Set(orders.map(\.id))
        for orphan in live where !known.contains(orphan.attributes.orderID) {
            changes.append((orphan, .end(nil, .immediate)))
        }
        guard !changes.isEmpty else { return }
        // `Activity` predates Sendable; its update/end are safe from any
        // context by ActivityKit's contract — the allowance `apply(to:)`
        // takes once more at the call itself.
        nonisolated(unsafe) let pending = changes
        let prior = pass
        pass = Task {
            await prior?.value
            for (activity, change) in pending {
                await change.apply(to: activity)
            }
        }
    }

    /// Waits for the last reconcile's ActivityKit calls to land — the
    /// background refresh's last step before it reports done, so the cards
    /// move in the same wake that learned the news.
    func settle() async {
        await pass?.value
    }

    /// One ActivityKit call a reconcile pass owes.
    private enum Change {
        case update(DeliveryActivityAttributes.ContentState, staleDate: Date?)
        /// `nil` content ends on the card's last state.
        case end(DeliveryActivityAttributes.ContentState?, ActivityUIDismissalPolicy)

        func apply(to activity: Activity<DeliveryActivityAttributes>) async {
            nonisolated(unsafe) let activity = activity
            switch self {
            case .update(let state, let staleDate):
                await activity.update(.init(state: state, staleDate: staleDate))
            case .end(let state, let dismissal):
                // A final card is stale-proof: it no longer claims to be live.
                await activity.end(state.map { .init(state: $0, staleDate: nil) },
                                   dismissalPolicy: dismissal)
            }
        }
    }

    private func start(order: Order,
                       state: DeliveryActivityAttributes.ContentState,
                       staleDate: Date) {
        do {
            _ = try Activity.request(
                attributes: DeliveryActivityAttributes(orderID: order.id),
                content: .init(state: state, staleDate: staleDate),
                pushType: nil  // no relay — updates are local, from sync
            )
        } catch {
            // Activities can be declined per-app or per-delivery — a refusal is
            // a missed surface, never a failure worth surfacing to the sender.
            Self.logger.debug("Live Activity request refused: \(error)")
        }
    }

    private func contentState(
        for order: Order,
        orderNumber: (Order.ID) -> String?
    ) -> DeliveryActivityAttributes.ContentState {
        DeliveryActivityAttributes.ContentState(
            status: order.status,
            orderNumber: orderNumber(order.id),
            destinationAddress: order.destinationPoint?.compactAddress ?? "",
            courierName: order.courierName,
            courierVehicle: order.courierVehicle,
            providerStatus: order.providerStatus,
            etaAt: order.etaAt,
            providerObservedAt: order.providerObservedAt,
            destinationPhone: order.destinationPoint?.contactPhone
        )
    }
}
