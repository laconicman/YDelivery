import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

/// The recipient-facing share text (board `5d`) — what the order detail's
/// share row hands the system sheet. Semantic facts, not the rendered
/// paragraph: which lines exist for which order, never the joined string.
@Suite("Recipient share text")
struct RecipientShareTextTests {
    private func order(
        status: OrderStatus = .active,
        visit: RoutePoint.PointVisitStatus? = .pending,
        etaMinutes: Int? = nil,
        observedAt: Date? = nil
    ) -> Order {
        Order(
            created: .init(timeIntervalSince1970: 1_800_000_000),
            status: status,
            route: [
                RoutePoint(
                    latitude: 55.64, longitude: 37.66,
                    address: "Москва, ул Москворечье, 6",
                    contactName: "Иван"),
                RoutePoint(
                    latitude: 55.65, longitude: 37.64,
                    address: "Москва, Каширское шоссе, 52",
                    contactName: "Анна Сидорова",
                    contactPhone: "+79987654321",
                    visit: visit.map { .init(status: $0) }),
            ],
            etaMinutes: etaMinutes,
            providerObservedAt: observedAt
        )
    }

    @Test("Number, destination and contact all land in the text")
    func namesTheOrderAndTheDoor() {
        let text = RecipientShareText.text(for: order(), orderNumber: "4417")
        #expect(text.contains("№4417"))
        #expect(text.contains("Каширское шоссе, 52"),
                "the destination goes compact — the constant city sheds")
        #expect(text.contains("Анна Сидорова"))
        #expect(text.contains("+79987654321"))
    }

    @Test("No order number, no dangling separator")
    func missingNumberJustDrops() {
        let text = RecipientShareText.text(for: order(), orderNumber: nil)
        #expect(!text.contains("№"))
        #expect(!text.hasPrefix("·"))
    }

    @Test("ETA rides only while the last stop is still ahead")
    func etaFollowsTheCalloutRule() {
        let ahead = order(visit: .pending, etaMinutes: 14)
        #expect(RecipientShareText.text(for: ahead, orderNumber: nil)
            .contains("~14 min"))

        let arrived = order(visit: .arrived, etaMinutes: 14)
        #expect(RecipientShareText.text(for: arrived, orderNumber: nil)
            .contains("~14 min"), "arrived is still ahead — the courier is there")

        let done = order(status: .done, visit: .visited, etaMinutes: 14)
        #expect(!RecipientShareText.text(for: done, orderNumber: nil)
            .contains("min"), "a visited destination promises nothing")
    }

    @Test("The provider's clock speaks as a time when it's aboard")
    func etaAtBeatsMinutes() {
        let observed = Date(timeIntervalSince1970: 1_800_000_000)
        let text = RecipientShareText.text(
            for: order(visit: .pending, etaMinutes: 30, observedAt: observed),
            orderNumber: nil)
        let expected = Date(timeIntervalSince1970: 1_800_001_800)
        #expect(text.contains(expected.formatted(date: .omitted, time: .shortened)))
        #expect(!text.contains("~30 min"), "the absolute time is the better promise")
    }
}
