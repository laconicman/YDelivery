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
/// it (review, PR #44).
/// Orders with no claim yet, and activities whose order vanished (an account
/// switch wiped them), are swept the same way.
@Observable @MainActor
final class LiveActivityController {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "YDelivery", category: "live-activity")

    /// Board `5a`: «Вручено» is final but lingers — four minutes on the lock
    /// screen, then it dismisses itself.
    nonisolated static let deliveredLinger: TimeInterval = 4 * 60

    /// What one reconcile pass does with an order — the board `5a` rules as a
    /// pure decision the tests can hold still, so the ActivityKit plumbing in
    /// `reconcile` stays unbranched.
    nonisolated enum Disposition: Equatable {
        /// Live — the card starts if absent, updates when the state moved.
        case updating
        /// Final — write the last card and end it. `linger` is the board's
        /// delivered-only courtesy: four minutes, then it dismisses itself.
        /// Cancelled ends `.default` — it stays until tapped.
        case ending(linger: Bool)
        /// No card at all — a draft has no provider existence, a claim-less
        /// order none yet.
        case none

        init(status: OrderStatus, hasClaim: Bool) {
            guard hasClaim else { self = .none; return }
            switch status {
            case .searching, .active, .attention: self = .updating
            case .done: self = .ending(linger: true)
            case .cancelled: self = .ending(linger: false)
            case .draft: self = .none
            }
        }
    }

    /// Reconcile the store's truth against what the Lock Screen is showing.
    /// Called on every `store.orders` republication — the write funnel means
    /// sync merges, placement, and cancels all arrive through the one hook.
    /// `orderNumber` resolves the sender's own number — the surface's identity
    /// is «4417», never the vendor's claim id (board `5a`).
    func reconcile(orders: [Order], orderNumber: (Order.ID) -> String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let live = Activity<DeliveryActivityAttributes>.activities
        for order in orders {
            let activity = live.first { $0.attributes.orderID == order.id }
            switch Disposition(status: order.status, hasClaim: order.claimID != nil) {
            case .updating:
                let state = contentState(for: order, orderNumber: orderNumber)
                if let activity {
                    guard activity.content.state != state else { continue }
                    nonisolated(unsafe) let activity = activity
                    Task { await activity.update(.init(state: state, staleDate: nil)) }
                } else {
                    start(order: order, state: state)
                }
            case .ending(let linger):
                if let activity {
                    let final = contentState(for: order, orderNumber: orderNumber)
                    let dismissal: ActivityUIDismissalPolicy = linger
                        ? .after(.now.addingTimeInterval(Self.deliveredLinger))
                        : .default
                    nonisolated(unsafe) let activity = activity
                    Task { await activity.end(.init(state: final, staleDate: nil),
                                              dismissalPolicy: dismissal) }
                }
            case .none:
                break  // never provider-visible — no card to write
            }
        }
        // An activity whose order is gone — wiped with the account, deleted —
        // ends quietly rather than posing as a live delivery.
        let known = Set(orders.map(\.id))
        for orphan in live where !known.contains(orphan.attributes.orderID) {
            nonisolated(unsafe) let orphan = orphan
            Task { await orphan.end(dismissalPolicy: .immediate) }
        }
    }

    private func start(order: Order,
                       state: DeliveryActivityAttributes.ContentState) {
        do {
            _ = try Activity.request(
                attributes: DeliveryActivityAttributes(orderID: order.id),
                content: .init(state: state, staleDate: nil),
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
            destinationAddress: order.route.last?.compactAddress ?? "",
            courierName: order.courierName,
            courierVehicle: order.courierVehicle,
            providerStatus: order.providerStatus,
            etaAt: order.etaAt,
            providerObservedAt: order.providerObservedAt,
            destinationPhone: order.route.last?.contactPhone
        )
    }
}
