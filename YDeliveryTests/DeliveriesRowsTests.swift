import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

/// The history list's derivation — rows from orders, the two shelves, the search
/// haystack, and the model's one-open-trail rule. Presentation stays untested (rule 9).
@Suite("Deliveries rows")
@MainActor
struct DeliveriesRowsTests {
    private func order(
        status: OrderStatus, created: TimeInterval, addresses: [String],
        contacts: [String?]? = nil, providerStatus: String? = nil
    ) -> Order {
        Order(
            created: .init(timeIntervalSince1970: created), status: status,
            route: addresses.enumerated().map { index, address in
                RoutePoint(latitude: 55, longitude: 37, address: address,
                           contactName: contacts?[index] ?? nil)
            },
            price: "1200", currency: "RUB", claimID: "c",
            providerStatus: providerStatus,
            providerObservedAt: providerStatus == nil ? nil : .init(timeIntervalSince1970: created + 600))
    }

    @Test("Live orders and history are two shelves, each newest order first")
    func shelvesSplitAndSort() {
        let sections = DeliveriesView.Model.sections(of: [
            order(status: .done, created: 100, addresses: ["A, 1", "B, 2"]),
            order(status: .active, created: 300, addresses: ["A, 1", "B, 2"]),
            order(status: .searching, created: 500, addresses: ["A, 1", "B, 2"]),
            order(status: .cancelled, created: 200, addresses: ["A, 1", "B, 2"]),
            order(status: .attention, created: 400, addresses: ["A, 1", "B, 2"]),
        ], fields: { _ in [] })
        #expect(sections.map(\.id) == [.live, .past])
        #expect(sections[0].rows.map(\.status) == [.searching, .attention, .active], "newest first, attention is live")
        #expect(sections[1].rows.map(\.status) == [.cancelled, .done])
    }

    @Test("An empty shelf leaves the list — no «History» heading over nothing")
    func emptyShelfDrops() {
        let sections = DeliveriesView.Model.sections(
            of: [order(status: .active, created: 1, addresses: ["A, 1", "B, 2"])], fields: { _ in [] })
        #expect(sections.map(\.id) == [.live])
    }

    @Test("The row reads from → to, compacted, with the middles counted")
    func rowRoute() {
        let row = DeliveriesView.Content.Row(
            order: order(status: .active, created: 1, addresses: [
                "Москва, ул Москворечье, 6", "Москва, Тверская, 1", "Москва, Арбат, 10", "Москва, Каширское шоссе, 52",
            ]),
            fieldValues: [])
        #expect(row.originText == "ул Москворечье, 6")
        #expect(row.destinationText == "Каширское шоссе, 52")
        #expect(row.middleStops == 2)
    }

    @Test("A single-point claim shows that point as the destination and no origin")
    func rowSinglePoint() {
        let row = DeliveriesView.Content.Row(
            order: order(status: .searching, created: 1, addresses: ["Москва, Тверская, 1"]),
            fieldValues: [])
        #expect(row.destinationText == "Тверская, 1")
        #expect(row.originText == nil)
        #expect(row.middleStops == 0)
    }

    @Test("The status's as-of time rides with the status; the created date leads")
    func rowTimes() {
        let row = DeliveriesView.Content.Row(
            order: order(status: .active, created: 1_800_000_000, addresses: ["A, 1", "B, 2"],
                         providerStatus: "pickuped"),
            fieldValues: [])
        #expect(row.statusObservedAt == Date(timeIntervalSince1970: 1_800_000_600))
        #expect(!row.createdText.isEmpty)
    }

    @Test("Search reaches addresses, people, the status words, the provider's phrase and field values")
    func searchHaystack() {
        let row = DeliveriesView.Content.Row(
            order: order(status: .active, created: 1, addresses: ["Москва, Арбат, 10", "Москва, Тверская, 1"],
                         contacts: ["Иван Петров", nil], providerStatus: "pickuped"),
            fieldValues: ["Заказ 4417"])
        for needle in ["Арбат", "Иван", "Courier on the way", "Picked up", "4417"] {
            #expect(row.searchableText.localizedCaseInsensitiveContains(needle), "\(needle) must be searchable")
        }
    }

    @Test("One trail open at a time — opening a second closes the first, opening the same closes it")
    func oneOpenTrail() async {
        let model = DeliveriesView.Model()
        let a = UUID(), b = UUID()
        let event = ProviderEvent(orderID: a, providerEventID: 1, at: .now, kind: "status",
                                  providerStatus: "pickuped", source: "journal")
        model.toggleTrail(of: a) { [event] }
        #expect(model.expandedID == a)
        #expect(model.trail == nil, "asking, not empty, until the read lands")
        for _ in 0..<50 where model.trail == nil { await Task.yield() }
        #expect(model.trail == [event])
        model.toggleTrail(of: b) { [] }
        #expect(model.expandedID == b)
        #expect(model.trail == nil, "the new row's read starts from asking")
        model.toggleTrail(of: b) { [] }
        #expect(model.expandedID == nil)
    }

    @Test("A failed trail read is an error row — never «nothing reported», never a stuck spinner")
    func failedTrailReadsAsError() async {
        let model = DeliveriesView.Model()
        let id = UUID()
        model.toggleTrail(of: id) { throw StoreController.StoreUnavailable() }
        for _ in 0..<50 where model.trailError == nil { await Task.yield() }
        #expect(model.trail == nil)
        #expect(model.trailError != nil)
    }

    @Test("A store republication re-reads the open trail in place — a failed re-read keeps the shown one")
    func republicationRefreshesOpenTrail() async {
        let model = DeliveriesView.Model()
        let id = UUID()
        let first = ProviderEvent(orderID: id, providerEventID: 1, at: .now, kind: "status",
                                  providerStatus: "pickuped", source: "journal")
        let second = ProviderEvent(orderID: id, providerEventID: 2, at: .now, kind: "status",
                                   providerStatus: "delivery_arrived", source: "journal")
        let store = Counter()
        model.toggleTrail(of: id) {
            store.n += 1
            switch store.n {
            case 1: return [first]
            case 2: return [first, second]
            default: throw StoreController.StoreUnavailable()
            }
        }
        for _ in 0..<50 where model.trail == nil { await Task.yield() }
        #expect(model.trail == [first])
        model.refreshTrail()
        for _ in 0..<50 where model.trail?.count != 2 { await Task.yield() }
        #expect(model.trail == [first, second], "the sync's new event reaches the open row")
        model.refreshTrail()
        for _ in 0..<50 where store.n < 3 { await Task.yield() }
        await Task.yield()
        #expect(model.trail == [first, second], "a failed re-read leaves the trail on screen")
        #expect(model.trailError == nil, "…and does not dress it as an error")
        #expect(DeliveriesView.Model().trail == nil)
        _ = DeliveriesView.Model().refreshTrail()
    }

    private final class Counter: @unchecked Sendable { var n = 0 }
}
