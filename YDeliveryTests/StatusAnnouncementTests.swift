import Foundation
import Testing
import UserNotifications
import YDeliveryKit
@testable import YDelivery

/// The board-5c surface, pinned: which wire words earn a banner, what the
/// banner says, and the threading rules — one thread per order, a new status
/// posts new, the same status replaces, a terminal clears the rest, and the
/// horizon keeps backfill off the lock screen.
@Suite("Status announcements")
@MainActor
struct StatusAnnouncementTests {

    private func order(id: UUID = UUID()) -> Order {
        Order(
            id: id,
            created: .now,
            status: .active,
            route: [
                RoutePoint(latitude: 55.6, longitude: 37.6, address: "Откуда"),
                RoutePoint(latitude: 55.7, longitude: 37.7, address: "Куда, 1"),
            ],
            claimID: "claim-1"
        )
    }

    // MARK: The vocabulary — push only what needs action

    @Test("The actionable set is exactly the sender's moments")
    func actionableVocabulary() {
        // Courier assigned — news, not urgency.
        #expect(StatusAnnouncement.content(for: "performer_found") ==
                .init(body: "A courier took the order",
                      isTerminal: false, isTimeSensitive: false))
        // A courier waiting at a door breaks through Focus — somebody must act.
        #expect(StatusAnnouncement.content(for: "pickup_arrived")?.isTimeSensitive == true)
        #expect(StatusAnnouncement.content(for: "delivery_arrived")?.isTimeSensitive == true)
        // Delivered is the ending — terminal, but not an interruption.
        #expect(StatusAnnouncement.content(for: "delivered") ==
                .init(body: "Delivered", isTerminal: true, isTimeSensitive: false))
        #expect(StatusAnnouncement.content(for: "delivered_finish")?.isTerminal == true)
    }

    @Test("Every provider-side ending banners — failures, cancels, returns")
    func endingsAnnounce() {
        for status in ["failed", "cancelled", "cancelled_with_payment",
                       "cancelled_by_taxi", "cancelled_with_items_on_hands",
                       "returned", "returned_finish"] {
            let content = StatusAnnouncement.content(for: status)
            #expect(content?.isTerminal == true, "\(status) ends the story")
            #expect(content?.isTimeSensitive == true,
                    "\(status) is an ending the sender must handle — it interrupts")
        }
        // performer_not_found is a failure the order survives — the sender can
        // retry — so it interrupts but does not clear the thread.
        let content = StatusAnnouncement.content(for: "performer_not_found")
        #expect(content?.isTimeSensitive == true)
        #expect(content?.isTerminal == false)
    }

    @Test("Routine progress stays silent — the row updates, the lock screen doesn't")
    func routineProgressIsSilent() {
        for status in ["new", "estimating", "accepted", "performer_lookup",
                       "performer_draft", "pickuped", "ready_for_pickup_confirmation",
                       "ready_for_delivery_confirmation", "returning", "return_arrived",
                       "ready_for_return_confirmation", "ready_for_approval",
                       "estimating_failed", "pay_waiting"] {
            #expect(StatusAnnouncement.content(for: status) == nil,
                    "\(status) is the list's job, not the lock screen's")
        }
    }

    // MARK: Request building — the threading rules

    @Test("One thread per order; a new status is a new banner, the same one replaces")
    func requestThreadingRules() throws {
        let orderID = UUID()
        let request = try #require(NotificationController.request(
            for: "delivery_arrived", order: order(id: orderID),
            title: "Order №4417", at: .now))

        #expect(request.content.threadIdentifier == orderID.uuidString,
                "banners stack under their order")
        #expect(request.identifier == "\(orderID.uuidString)‖delivery_arrived",
                "status-keyed: a repeat replaces, a new status posts beside it")
        #expect(request.content.title == "Order №4417")
        #expect(request.content.userInfo["orderID"] as? String == orderID.uuidString,
                "the tap-through carries the row's id")
        #expect(request.content.interruptionLevel == .timeSensitive)
        #expect(request.trigger == nil, "posted, not scheduled")
    }

    @Test("A status with nothing to say builds no request")
    func unmappedStatusBuildsNothing() {
        #expect(NotificationController.request(
            for: "pickuped", order: order(), title: "Order №1", at: .now) == nil)
    }

    @Test("An event older than a day is history, not a banner")
    func horizonSuppressesBackfill() {
        let twoDaysAgo = Date.now.addingTimeInterval(-2 * 24 * 3600)
        #expect(NotificationController.request(
            for: "delivered", order: order(), title: "Order №1",
            at: twoDaysAgo) == nil,
                "a fresh install's first sync must not banner two years of deliveries")
        #expect(NotificationController.request(
            for: "delivered", order: order(), title: "Order №1",
            at: twoDaysAgo, now: twoDaysAgo) != nil,
                "the same event in its own window still banners")
    }

    // MARK: Titles — the sender's order number

    @Test("The order-number carrier's value is the title's name")
    func orderNumberNamesTheTitle() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = StoreController(database: AppDatabase(
            directory: directory, providerAccountRef: "test:unattributed",
            containerIdentifier: "iCloud.test"))
        await store.refresh()

        let definition = CustomFieldDefinition(
            name: "Заказ", carrier: .orderNumber, position: 0)
        try await store.saveField(definition)
        let placed = order()
        try await store.record(placed, customFields: [
            OrderCustomField(orderID: placed.id, fieldRef: definition.id,
                             name: "Заказ", value: "4417",
                             carrier: definition.carrier)
        ])

        #expect(store.orderNumber(for: placed.id) == "4417")
        #expect(store.orderNumber(for: UUID()) == nil,
                "an order without the field has no number — the address falls back")
    }
}
