import Foundation
import Observation
import UserNotifications
import YDeliveryKit

/// Local notifications for the claims feed — the system surface journal sync
/// drives (board `5c`). The sync controller records each provider event and
/// calls ``announce(_:for:)`` only when the provider's word *advanced*; this
/// owns authorization, threading, replacement, and the tap-through.
///
/// Threading rules, from the board: one thread per order
/// (`threadIdentifier` = order id) so banners stack under their delivery; a
/// new status posts a *new* request keyed `orderID ‖ status` while the same
/// status again *replaces* in place — a refinement updates the banner instead
/// of stacking a twin; and a terminal banner clears the thread's earlier
/// entries, because once the story is over only the ending stays.
@Observable @MainActor
final class NotificationController: NSObject {
    /// The order a tapped banner asks for — consumed by `RootView` like the
    /// Spotlight deep-link: retained until the store can confirm the row is
    /// still in history.
    private(set) var requestedOrderID: UUID?

    private let store: StoreController
    private let center: UNUserNotificationCenter
    /// Authorization is asked once, lazily — the first announce-worthy event
    /// is the moment the permission's value is self-evident. The `Task` is
    /// retained so two near-simultaneous events share one system prompt.
    @ObservationIgnored private var authorization: Task<Bool, Never>?

    init(store: StoreController, center: UNUserNotificationCenter = .current()) {
        self.store = store
        self.center = center
        super.init()
        center.delegate = self
    }

    /// Posts the banner for a provider status that advanced — or does nothing
    /// when the word carries no announcement, or when the event is history:
    /// a banner reports news, and past the ``announcementHorizon`` it is the
    /// timeline's job, not the lock screen's (this is what keeps a fresh
    /// install's first backfill from bannering two years of deliveries).
    func announce(_ event: ProviderEvent, for order: Order) async {
        guard let providerStatus = event.providerStatus,
              let request = Self.request(
                for: providerStatus, order: order,
                title: title(for: order), at: event.at) else { return }
        _ = await ensureAuthorized()
        // A terminal banner retires the thread's earlier entries first — the
        // ending is the only banner an over-order keeps (board 5c).
        if StatusAnnouncement.content(for: providerStatus)?.isTerminal == true {
            await clearThread(of: order.id, keeping: request.identifier)
        }
        try? await center.add(request)
    }

    /// The request a status would post — pure so the threading rules are
    /// testable without a `UNUserNotificationCenter`. Nil when the word has
    /// no announcement or the event is older than the news window.
    nonisolated static func request(
        for providerStatus: String,
        order: Order,
        title: String,
        at eventTime: Date,
        now: Date = .now
    ) -> UNNotificationRequest? {
        guard let content = StatusAnnouncement.content(for: providerStatus),
              eventTime > now.addingTimeInterval(-announcementHorizon) else { return nil }
        let notification = UNMutableNotificationContent()
        notification.title = title
        notification.body = content.body
        notification.threadIdentifier = order.id.uuidString
        notification.userInfo = [orderIDKey: order.id.uuidString]
        if content.isTimeSensitive {
            notification.interruptionLevel = .timeSensitive
            notification.sound = .default
        }
        // The identifier is the thread-plus-word: posting the same status again
        // replaces its banner, posting a new status adds one.
        return UNNotificationRequest(
            identifier: "\(order.id.uuidString)‖\(providerStatus)",
            content: notification, trigger: nil)
    }

    /// Every title carries the sender's own order number (board 5c) — the
    /// «Заказ 4417» they wrote into the custom field carried to the provider.
    /// No number field in the schema falls back to where the parcel is going.
    private func title(for order: Order) -> String {
        if let number = store.orderNumber(for: order.id) {
            String(localized: "Order №\(number)")
        } else {
            order.destinationPoint?.address ?? String(localized: "Delivery")
        }
    }

    /// Removes the thread's delivered banners except the one being posted —
    /// the «order closed» rule: on a terminal event the earlier progress
    /// banners are outdated news.
    private func clearThread(of orderID: UUID, keeping identifier: String) async {
        let delivered = await center.deliveredNotifications()
        let stale = delivered
            .filter {
                $0.request.content.threadIdentifier == orderID.uuidString
                    && $0.request.identifier != identifier
            }
            .map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: stale)
    }

    private func ensureAuthorized() async -> Bool {
        if let authorization { return await authorization.value }
        let task = Task {
            await ((try? center.requestAuthorization(options: [.alert, .sound])) ?? false)
        }
        authorization = task
        return await task.value
    }

    /// Reads and clears the tap-through — `RootView`'s consume step, so the
    /// same banner can't re-navigate on the next view rebuild.
    func consumeRequest() -> UUID? {
        defer { requestedOrderID = nil }
        return requestedOrderID
    }

    /// A banner reports *news*, not history: an event older than a day belongs
    /// to the timeline. Same-day express deliveries sit well inside the window;
    /// a replayed backfill sits far outside it.
    private nonisolated static var announcementHorizon: TimeInterval { 24 * 3600 }

    private nonisolated static let orderIDKey = "orderID"
}

extension NotificationController: UNUserNotificationCenterDelegate {
    /// Banners present even with the app foregrounded — the sender may be in
    /// Settings or composing the next order while a courier arrives.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let raw = response.notification.request.content
            .userInfo[Self.orderIDKey] as? String,
              let orderID = UUID(uuidString: raw) else { return }
        await MainActor.run { requestedOrderID = orderID }
    }
}
