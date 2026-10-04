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

    @Test("A decision row names which wait it is — refused claims stop wearing «Not delivered»")
    func attentionRowNamesItsWait() {
        // The drive's litter: claims created, priced, refused at acceptance —
        // «failed» provider-side though nothing was ever dispatched.
        let refused = DeliveriesView.Content.Row(
            order: order(status: .attention, created: 1, addresses: ["A, 1", "B, 2"],
                         providerStatus: "failed"),
            fieldValues: [])
        #expect(refused.statusDetail == "Ended before delivery")

        let parked = DeliveriesView.Content.Row(
            order: order(status: .attention, created: 1, addresses: ["A, 1", "B, 2"],
                         providerStatus: "pay_waiting"),
            fieldValues: [])
        #expect(parked.statusDetail == "Waiting for payment")

        let unphrased = DeliveriesView.Content.Row(
            order: order(status: .attention, created: 1, addresses: ["A, 1", "B, 2"]),
            fieldValues: [])
        #expect(unphrased.statusDetail == nil, "no wire word — the chip stands alone, never invented words")

        let active = DeliveriesView.Content.Row(
            order: order(status: .active, created: 1, addresses: ["A, 1", "B, 2"],
                         providerStatus: "pickuped"),
            fieldValues: [])
        #expect(active.statusDetail == nil, "other statuses' chips already tell the whole truth")
    }

    @Test("One trail open at a time — opening a second closes the first, opening the same closes it")
    func oneOpenTrail() async {
        let model = DeliveriesView.Model()
        let a = UUID(), b = UUID()
        let event = ProviderEvent(orderID: a, providerEventID: 1, at: .now, kind: "status",
                                  providerStatus: "pickuped", source: "journal")
        model.toggleTrail(of: a) { [event] }
        for _ in 0..<50 where model.expandedID == nil { await Task.yield() }
        #expect(model.expandedID == a)
        #expect(model.trail == [event],
                "one publish: the trail arrives with the expansion, no asking phase")
        model.toggleTrail(of: b) { [] }
        for _ in 0..<50 where model.expandedID == a { await Task.yield() }
        #expect(model.expandedID == b)
        #expect(model.trail == [], "the new row opens on its own read")
        model.toggleTrail(of: b) { [] }
        await Task.yield()
        #expect(model.expandedID == nil)
    }

    @Test("A failed trail read is an error row — never «nothing reported», never a stuck spinner")
    func failedTrailReadsAsError() async {
        let model = DeliveriesView.Model()
        let id = UUID()
        model.toggleTrail(of: id) { throw StoreController.StoreUnavailable() }
        for _ in 0..<50 where model.trailError == nil { await Task.yield() }
        #expect(model.expandedID == id, "the row still opens — wearing the error")
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
        for _ in 0..<50 where model.expandedID == nil { await Task.yield() }
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

    @Test("A republish while another row is opening re-reads the open row, never the pending one")
    func republishKeepsPendingAndShownApart() async {
        let model = DeliveriesView.Model()
        let a = UUID(), b = UUID()
        func event(_ id: Int64, order: UUID) -> ProviderEvent {
            ProviderEvent(orderID: order, providerEventID: id, at: .now, kind: "status",
                          providerStatus: "pickuped", source: "journal")
        }
        let counter = Counter()
        // A is open with its first read; every later read is the republished one.
        model.toggleTrail(of: a) {
            counter.n += 1
            return counter.n == 1 ? [event(1, order: a)] : [event(1, order: a), event(2, order: a)]
        }
        for _ in 0..<50 where model.expandedID == nil { await Task.yield() }
        #expect(model.expandedID == a)
        // B's open starts but its read is held — the pending state in the report.
        let gate = Gate()
        model.toggleTrail(of: b) {
            await gate.wait()
            return [event(9, order: b)]
        }
        await Task.yield()
        // A sync tick lands while B is in flight: it must re-read A with A's own
        // fetch, leave B pending, and not be cancelled by B's open.
        model.refreshTrail()
        for _ in 0..<50 where model.trail?.count != 2 { await Task.yield() }
        #expect(model.expandedID == a, "B has not committed — the shown row is still A")
        #expect(model.trail?.map(\.providerEventID) == [1, 2],
                "A's fetch answered the republish, not B's")
        await gate.release()
        for _ in 0..<50 where model.expandedID != b { await Task.yield() }
        #expect(model.expandedID == b)
        #expect(model.trail?.map(\.providerEventID) == [9],
                "the pending open lands as its own row with its own events")
    }

    @Test("A second tap on a still-opening row cancels only that open — the shown row stays")
    func pendingCancelLeavesCommittedAlone() async {
        let model = DeliveriesView.Model()
        let a = UUID(), b = UUID()
        func event(_ id: Int64, order: UUID) -> ProviderEvent {
            ProviderEvent(orderID: order, providerEventID: id, at: .now, kind: "status",
                          providerStatus: "pickuped", source: "journal")
        }
        model.toggleTrail(of: a) { [event(1, order: a)] }
        for _ in 0..<50 where model.expandedID == nil { await Task.yield() }
        #expect(model.expandedID == a)
        // B's open is in flight, its read held — a second tap on B.
        let gate = Gate()
        model.toggleTrail(of: b) {
            await gate.wait()
            return [event(9, order: b)]
        }
        await Task.yield()
        model.toggleTrail(of: b) { [event(7, order: b)] }
        #expect(model.expandedID == a,
                "the committed row never moved — only B's pending open died")
        #expect(model.trail?.map(\.providerEventID) == [1],
                "A's trail is intact, not cleared with B's cancel")
        // The dead fetch must never publish, even released.
        await gate.release()
        for _ in 0..<20 { await Task.yield() }
        #expect(model.expandedID == a)
        #expect(model.trail?.map(\.providerEventID) == [1])
        #expect(model.trailError == nil)
    }

    @Test("A republish re-read that outlives a reopen never overwrites the newer trail")
    func staleRefreshDrops() async {
        let model = DeliveriesView.Model()
        let a = UUID(), b = UUID()
        func event(_ id: Int64, order: UUID) -> ProviderEvent {
            ProviderEvent(orderID: order, providerEventID: id, at: .now, kind: "status",
                          providerStatus: "pickuped", source: "journal")
        }
        let counter = Counter()
        let gate = Gate()
        // A's reads: the open, the held republish re-read (a stale [1]), the
        // re-open's fresh read ([1, 2]).
        let aFetch: () async throws -> [ProviderEvent] = {
            counter.n += 1
            switch counter.n {
            case 1: return [event(1, order: a)]
            case 2:
                await gate.wait()
                return [event(1, order: a)]
            default: return [event(1, order: a), event(2, order: a)]
            }
        }
        model.toggleTrail(of: a, using: aFetch)
        for _ in 0..<50 where model.expandedID == nil { await Task.yield() }
        #expect(model.trail?.map(\.providerEventID) == [1])
        model.refreshTrail()
        await Task.yield()  // the re-read is parked on the gate
        model.toggleTrail(of: b) { [event(9, order: b)] }
        for _ in 0..<50 where model.expandedID != b { await Task.yield() }
        model.toggleTrail(of: a, using: aFetch)
        for _ in 0..<50 where model.trail?.count != 2 { await Task.yield() }
        #expect(model.expandedID == a)
        #expect(model.trail?.map(\.providerEventID) == [1, 2])
        await gate.release()
        for _ in 0..<20 { await Task.yield() }
        #expect(model.trail?.map(\.providerEventID) == [1, 2],
                "the stale re-read must not overwrite the reopened trail")
        #expect(model.trailError == nil)
    }

    // MARK: The toolbar's derivation

    private func row(
        status: OrderStatus, created: TimeInterval,
        price: Decimal? = nil, haystack: String = ""
    ) -> DeliveriesView.Content.Row {
        .init(id: UUID(), status: status, statusObservedAt: nil,
              created: .init(timeIntervalSince1970: created), createdText: "",
              price: price,
              destinationText: "B", originText: nil, middleStops: 0,
              priceText: price.map { "\($0) ₽" }, route: [], searchableText: haystack)
    }

    private func sections(
        of rows: [DeliveriesView.Content.Row]
    ) -> [DeliveriesView.Content.Section] {
        [
            .init(id: .live, rows: rows.filter(\.status.isLive)),
            .init(id: .past, rows: rows.filter { !$0.status.isLive }),
        ].filter { !$0.rows.isEmpty }
    }

    @Test("Newest first keeps today's order; oldest and price reorder within their shelf")
    func sortOrdersWithinShelves() {
        let sections = sections(of: [
            row(status: .done, created: 100, price: 900),
            row(status: .cancelled, created: 300, price: nil),
            row(status: .done, created: 200, price: 1500),
        ])
        let visible = { sort in
            DeliveriesView.Model.visible(sections, query: "", sort: sort, filter: .all)
                .flatMap(\.rows)
        }
        #expect(visible(.newestFirst).map(\.status) == [.cancelled, .done, .done])
        #expect(visible(.oldestFirst).map(\.status) == [.done, .done, .cancelled])
        let byPrice = visible(.priceHighFirst)
        #expect(byPrice.map(\.price) == [1500, 900, nil],
                "no price cannot win «high first» and sorts last")
    }

    @Test("Each filter keeps only its statuses; «Everything» keeps the list whole")
    func filterAdmitsItsStatuses() {
        let sections = sections(of: [
            row(status: .active, created: 1),
            row(status: .attention, created: 2),
            row(status: .done, created: 3),
            row(status: .cancelled, created: 4),
        ])
        let statuses = { filter in
            DeliveriesView.Model.visible(sections, query: "", sort: .newestFirst, filter: filter)
                .flatMap(\.rows).map(\.status)
        }
        #expect(statuses(.all).count == 4)
        #expect(statuses(.needsDecision) == [.attention])
        #expect(statuses(.delivered) == [.done])
        #expect(statuses(.cancelled) == [.cancelled])
    }

    @Test("Filter and search compose — a hit must pass both gates")
    func filterAndSearchCompose() {
        let sections = sections(of: [
            row(status: .done, created: 1, haystack: "Арбат 10"),
            row(status: .done, created: 2, haystack: "Тверская 1"),
            row(status: .cancelled, created: 3, haystack: "Арбат 10"),
        ])
        let visible = DeliveriesView.Model.visible(
            sections, query: "арбат", sort: .newestFirst, filter: .delivered)
        #expect(visible.flatMap(\.rows).map(\.created) == [Date(timeIntervalSince1970: 1)],
                "the cancelled Арбат is filtered out, the Тверская done is searched out")
    }

    @Test("A shelf emptied by the filter leaves the list entirely")
    func emptiedShelfDrops() {
        let sections = sections(of: [
            row(status: .active, created: 1),
            row(status: .done, created: 2),
        ])
        let visible = DeliveriesView.Model.visible(
            sections, query: "", sort: .newestFirst, filter: .delivered)
        #expect(visible.map(\.id) == [.past], "the live shelf is gone, not shown empty")
    }

    private final class Counter: @unchecked Sendable { var n = 0 }

    /// A one-shot hold for a fetch under test: `wait()` parks until `release()`.
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false
        func wait() async {
            if released { return }
            await withCheckedContinuation { c in
                if released { c.resume() } else { continuation = c }
            }
        }
        func release() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }
}
