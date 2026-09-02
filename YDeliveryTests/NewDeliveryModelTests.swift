import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

@Suite("New delivery draft")
@MainActor
struct NewDeliveryModelTests {
    private let office = PickedPlace(latitude: 55.7558, longitude: 37.6173, address: "Офис")
    private let home = PickedPlace(latitude: 55.6460, longitude: 37.6681, address: "Дом")
    private let shop = PickedPlace(latitude: 55.7499, longitude: 37.5934, address: "Магазин")
    private let ivan = Contact(name: "Иван Петров", phone: "+7 912 345-67-89")

    /// A draft with its two founding rows filled — the common A→B case.
    private func filledDraft() -> NewDeliveryView.Model {
        let model = NewDeliveryView.Model()
        model.setPlace(office, for: model.points[0].id)
        model.setPlace(home, for: model.points[1].id)
        return model
    }

    @Test("A draft is born as an unfilled pickup and drop-off")
    func foundingRows() {
        let model = NewDeliveryView.Model()
        #expect(model.points.map(\.role) == [.pickup, .dropoff])
        #expect(model.points.allSatisfy { $0.place == nil })
        #expect(!model.isRouteComplete)
    }

    @Test("The route completes only when every stop is chosen")
    func routeCompleteness() {
        let model = NewDeliveryView.Model()
        model.setPlace(office, for: model.points[0].id)
        #expect(!model.isRouteComplete)

        model.setPlace(home, for: model.points[1].id)
        #expect(model.isRouteComplete)

        model.addStop()
        #expect(!model.isRouteComplete, "an added-but-empty stop is a hole in the route, not an extra")
    }

    @Test("Swapping exchanges places and contacts, and is only offered when it exchanges")
    func swapExchanges() {
        let model = NewDeliveryView.Model()
        model.setPlace(office, for: model.points[0].id)
        model.setContact(ivan, for: model.points[0].id)
        #expect(!model.canSwap, "with one end empty a swap would read as data loss")

        model.setPlace(home, for: model.points[1].id)
        #expect(model.canSwap)

        model.swapEnds()
        #expect(model.points[0].place == home)
        #expect(model.points[1].place == office)
        #expect(model.points[1].contact == ivan, "the person at the door travels with the address")
        #expect(model.points.map(\.role) == [.pickup, .dropoff], "the route still starts with a pickup")
    }

    @Test("From three points, reordering replaces swapping")
    func reorderReplacesSwap() {
        let model = filledDraft()
        #expect(model.canSwap)
        #expect(!model.canReorder)

        model.addStop()
        #expect(!model.canSwap)
        #expect(model.canReorder)
    }

    @Test("An added stop joins before the return point — the return stays last")
    func addedStopRespectsReturn() {
        let model = filledDraft()
        let returnStop = model.addStop()
        model.setRole(.return, for: returnStop)

        let added = model.addStop()
        #expect(model.points.last?.role == .return)
        #expect(model.points.firstIndex { $0.id == added } == model.points.count - 2)
    }

    @Test("Becoming the return moves the stop to the end of the run")
    func returnMovesLast() {
        let model = filledDraft()
        let middle = model.addStop()
        model.setPlace(shop, for: middle)
        model.movePoints(from: IndexSet(integer: 2), to: 1)
        #expect(model.points[1].id == middle)

        model.setRole(.return, for: middle)
        #expect(model.points.last?.id == middle)
        #expect(model.points.last?.role == .return)
    }

    @Test("The route's only delivery can never become the return")
    func soleDeliveryStaysDelivery() {
        let model = filledDraft()
        #expect(model.availableRoles(for: model.points[1].id) == [],
                "pickup → return delivers nothing (review, PR #17)")
    }

    @Test("The last delivery cannot be removed out from beside a return")
    func lastDeliveryCannotBeRemoved() {
        let model = filledDraft()
        let stop = model.addStop()
        model.setPlace(shop, for: stop)
        model.setRole(.return, for: stop)

        model.removePoints(at: IndexSet(integer: 1))
        #expect(model.points.map(\.role) == [.pickup, .dropoff, .return],
                "removing the sole delivery would leave a route that delivers nothing")
    }

    @Test("An extension without a phone does not survive saving")
    func extensionAloneIsNoise() {
        let model = filledDraft()
        let id = model.points[0].id

        model.setContact(Contact(phoneExtension: "123"), for: id)
        #expect(model.points[0].contact == nil, "nothing dialable, nothing kept")

        model.setContact(Contact(name: "Иван", phoneExtension: "123"), for: id)
        #expect(model.points[0].contact == Contact(name: "Иван"),
                "the name survives; the undialable extension does not")
    }

    @Test("Only one return point can exist")
    func singleReturn() {
        let model = filledDraft()
        let first = model.addStop()
        let second = model.addStop()
        model.setRole(.return, for: first)
        model.setRole(.return, for: second)

        #expect(model.points.filter { $0.role == .return }.count == 1)
        #expect(model.availableRoles(for: second) == [], "a second return is not offered while one exists")
        #expect(model.availableRoles(for: first) == [.dropoff], "the return may step back to a delivery")
    }

    @Test("The first row is the route's start: no roles offered, never movable, never removed")
    func pickupIsPinned() {
        let model = filledDraft()
        model.addStop()
        let pickupID = model.points[0].id

        #expect(model.availableRoles(for: pickupID) == [])

        model.movePoints(from: IndexSet(integer: 0), to: 2)
        #expect(model.points[0].id == pickupID, "the pickup cannot be dragged off the start")

        model.removePoints(at: IndexSet(integer: 0))
        #expect(model.points[0].id == pickupID)
    }

    @Test("The founding pair cannot shrink; added stops can be removed")
    func removalKeepsTheFoundingPair() {
        let model = filledDraft()
        model.removePoints(at: IndexSet(integer: 1))
        #expect(model.points.count == 2, "an A→B draft with a row missing is not a route")

        model.addStop()
        model.removePoints(at: IndexSet(integer: 2))
        #expect(model.points.count == 2)
    }

    @Test("An all-empty contact stores as none — the row's invitation returns")
    func emptyContactIsNoContact() {
        let model = filledDraft()
        let id = model.points[0].id
        model.setContact(ivan, for: id)
        #expect(model.points[0].contact == ivan)

        model.setContact(Contact(), for: id)
        #expect(model.points[0].contact == nil)
    }

    @Test("Reordering keeps identities — a moved stop is the same stop")
    func reorderKeepsIdentity() {
        let model = filledDraft()
        let added = model.addStop()
        model.setPlace(shop, for: added)

        model.movePoints(from: IndexSet(integer: 2), to: 1)
        #expect(model.points[1].id == added)
        #expect(model.points[1].place == shop)
    }
}

@Suite("Route badges")
@MainActor
struct RouteBadgeMappingTests {
    @Test("Two points read A→B: ring and teardrop")
    func twoPointReading() {
        #expect(PointBadge.Role(role: .pickup, index: 0, isLast: false) == .start)
        #expect(PointBadge.Role(role: .dropoff, index: 1, isLast: true) == .end)
    }

    @Test("Stops between are numbered by position, so numbers survive reordering")
    func intermediatesAreNumbered() {
        #expect(PointBadge.Role(role: .dropoff, index: 1, isLast: false) == .stop(number: 2))
        #expect(PointBadge.Role(role: .dropoff, index: 3, isLast: false) == .stop(number: 4))
    }

    @Test("A return point keeps its own mark wherever it sits")
    func returnKeepsItsMark() {
        #expect(PointBadge.Role(role: .return, index: 4, isLast: true) == .returnPoint)
    }

    @Test("With a return closing the run, the last delivery stays a numbered stop")
    func lastDeliveryBeforeReturnIsNumbered() {
        // Board 2b, the five-point ladder: ring · 2 · 3 · 4 · return.
        #expect(PointBadge.Role(role: .dropoff, index: 3, isLast: false) == .stop(number: 4))
    }
}
