import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

@Suite("Store controller")
@MainActor
struct StoreControllerTests {
    private let directory: URL

    init() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StoreControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var controller: StoreController {
        StoreController(
            orderStore: OrderStore(directory: directory),
            placeStore: SavedPlaceStore(directory: directory)
        )
    }

    private func order(created: Date, addresses: [String]) -> Order {
        Order(
            created: created,
            status: .done,
            route: addresses.enumerated().map { index, address in
                RoutePoint(
                    latitude: 55.0 + Double(index),
                    longitude: 37.0,
                    address: address,
                    contactName: index == 0 ? "Иван Петров" : nil
                )
            }
        )
    }

    @Test("Recents keep one point per address, newest first, contact included")
    func recentsDeduplicateByAddress() {
        let older = order(created: .init(timeIntervalSince1970: 1000), addresses: ["Москворечье, 6", "Арбат, 10"])
        let newer = order(created: .init(timeIntervalSince1970: 2000), addresses: ["москворечье, 6 ", "Тверская, 1"])

        // The store hands orders newest-first; the derivation must keep that reading.
        let recents = StoreController.recentPoints(in: [newer, older])

        #expect(recents.map(\.address) == ["москворечье, 6 ", "Тверская, 1", "Арбат, 10"])
        #expect(recents[0].contactName == "Иван Петров")
    }

    @Test("A place the sender named is a chip, not also an anonymous recent")
    func savedPlacesLeaveTheRecents() {
        let orders = [order(created: .now, addresses: ["Невский, 100", "Каширское шоссе, 52"])]
        let saved = [
            SavedPlace(
                name: "Склад",
                kind: .warehouse,
                // Same place, spelled the way the sender typed it into the chip.
                point: RoutePoint(latitude: 55, longitude: 37, address: "  невский, 100  ")
            )
        ]

        let recents = StoreController.recentPoints(in: orders, saved: saved)
        #expect(recents.map(\.address) == ["Каширское шоссе, 52"],
                "the chip already carries that point, with its name and its contact")
    }

    @Test("Two flats at one address are two memories — the door is part of the identity")
    func apartmentsDoNotCollapse() {
        var twelve = RoutePoint(latitude: 55.75, longitude: 37.61, address: "Тверская, 6")
        twelve.addressParts = AddressParts(apartment: "12")
        twelve.contactName = "Иван"
        var fortySix = RoutePoint(latitude: 55.75, longitude: 37.61, address: "Тверская, 6")
        fortySix.addressParts = AddressParts(apartment: "46")
        fortySix.contactName = "Анна"

        let orders = [Order(created: .now, status: .done, route: [twelve, fortySix])]
        let recents = StoreController.recentPoints(in: orders)

        #expect(recents.count == 2, "keeping the newest would restore the wrong flat and the wrong person")
        #expect(Set(recents.compactMap(\.contactName)) == ["Иван", "Анна"])
    }

    @Test("A saved place hides its own door, not the whole building")
    func savedPlaceHidesOnlyItself() {
        var saved = RoutePoint(latitude: 55.75, longitude: 37.61, address: "Тверская, 6")
        saved.addressParts = AddressParts(apartment: "12")
        var other = RoutePoint(latitude: 55.75, longitude: 37.61, address: "Тверская, 6")
        other.addressParts = AddressParts(apartment: "46")

        let recents = StoreController.recentPoints(
            in: [Order(created: .now, status: .done, route: [saved, other])],
            saved: [SavedPlace(name: "Дом", kind: .home, point: saved)]
        )

        #expect(recents.map { $0.addressParts?.apartment } == ["46"],
                "the chip covers flat 12; flat 46 is still its own memory")
    }

    @Test("No container is a stated reason, not an empty history")
    func containerlessHistoryExplainsItself() async {
        let containerless = StoreController(orderStore: nil, placeStore: nil)
        #expect(containerless.historyUnavailable != nil,
                "an empty list with no explanation reads as 'you have sent nothing'")

        let healthy = controller
        await healthy.refresh()
        #expect(healthy.historyUnavailable == nil, "empty but readable explains nothing")
    }

    @Test("Two doors at one address are two rows the picker can tell apart")
    func recentRowsIdentifyTheirDoor() {
        var twelve = RoutePoint(latitude: 55.75, longitude: 37.61, address: "Тверская, 6")
        twelve.addressParts = AddressParts(apartment: "12")
        twelve.contactName = "Иван"
        var fortySix = RoutePoint(latitude: 55.75, longitude: 37.61, address: "Тверская, 6")
        fortySix.addressParts = AddressParts(apartment: "46")
        fortySix.contactName = "Анна"

        let rows = [twelve, fortySix].map(PointPickerView.SearchContent.Recent.init)
        #expect(rows[0].id != rows[1].id,
                "one id for two doors let picking the second fill the first")

        // And the id round-trips back to the right point.
        let picked = [twelve, fortySix].first { StoreController.destinationKey($0) == rows[1].id }
        #expect(picked?.contactName == "Анна")
    }

    @Test("A draft is not an order — the explainer runs until one is actually placed")
    func onlyPlacedOrdersRetireTheExplainer() async throws {
        let controller = controller
        #expect(!controller.hasPlacedAnOrder)

        try OrderStore(directory: directory).record(
            Order(created: .now, status: .draft, route: [])
        )
        await controller.refresh()
        #expect(!controller.hasPlacedAnOrder, "a started-and-abandoned draft teaches nobody anything")

        try OrderStore(directory: directory).record(
            Order(created: .now, status: .cancelled, route: [])
        )
        await controller.refresh()
        #expect(controller.hasPlacedAnOrder,
                "placed then cancelled still means they saw the strip and chose a class")
    }

    @Test("Recording the same order twice keeps one row")
    func recordingIsIdempotent() throws {
        let store = OrderStore(directory: directory)
        let order = Order(created: .now, status: .searching, route: [], claimID: "claim-1")

        try store.record(order)
        try store.record(order)

        #expect(try store.read().count == 1,
                "a reopened draft observing its own placed order must not add a second delivery")
    }

    @Test("Recents cap at the limit — the empty-query list stays one screen tall")
    func recentsRespectLimit() {
        let orders = (0..<20).map { index in
            order(created: .init(timeIntervalSince1970: Double(index)), addresses: ["Адрес \(index)"])
        }
        #expect(StoreController.recentPoints(in: orders, limit: 8).count == 8)
    }

    @Test("Refresh publishes both files; an empty container reads as empty")
    func refreshReadsBoth() async throws {
        let controller = controller
        try OrderStore(directory: directory).record(order(created: .now, addresses: ["Москворечье, 6"]))
        try SavedPlaceStore(directory: directory).save(
            SavedPlace(name: "Дом", kind: .home, point: RoutePoint(latitude: 55, longitude: 37, address: "Дом"))
        )

        await controller.refresh()

        #expect(controller.orders.count == 1)
        #expect(controller.savedPlaces.map(\.name) == ["Дом"])
        #expect(controller.ordersError == nil)
        #expect(controller.placesError == nil)
    }

    @Test("An unread store is not an empty one — first-run surfaces wait for the read")
    func emptinessIsNotKnownBeforeTheRead() async throws {
        let controller = controller
        #expect(!controller.hasLoaded)
        #expect(controller.orders.isEmpty, "empty, but only because nobody has looked")

        await controller.refresh()
        #expect(controller.hasLoaded, "now emptiness means something")
    }

    @Test("Saving a place persists and republishes")
    func savePersists() async throws {
        let controller = controller
        try await controller.save(
            SavedPlace(name: "Склад", kind: .warehouse, point: RoutePoint(latitude: 59, longitude: 30, address: "Невский, 100"))
        )

        #expect(controller.savedPlaces.map(\.name) == ["Склад"])
        #expect(try SavedPlaceStore(directory: directory).read().count == 1)
    }

    @Test("A retried save is one chip — dedupe consults the file, not memory")
    func retriedSaveDoesNotDuplicate() async throws {
        let controller = controller
        let point = RoutePoint(latitude: 59, longitude: 30, address: "Невский, 100")
        // Two saves of the same destination under different identities — exactly what
        // a retry after a failed confirming read produces (review, PR #18 post-merge).
        try await controller.save(SavedPlace(name: "Склад", kind: .warehouse, point: point))
        try await controller.save(SavedPlace(name: "Склад (уточнил)", kind: .warehouse, point: point))

        let stored = try SavedPlaceStore(directory: directory).read()
        #expect(stored.count == 1, "same destination key — one memory, updated")
        #expect(stored.first?.name == "Склад (уточнил)")
    }

    @Test("A successful bookmark does not dress unreadable history as empty")
    func saveLeavesOrderErrorsStanding() async throws {
        // An order store whose *file cannot be read at all* — a directory squatting on
        // its path. (Malformed bytes deliberately read as empty in the Kit; this test
        // needs the read to genuinely fail.)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("orders.json"),
            withIntermediateDirectories: true
        )
        let controller = StoreController(
            orderStore: OrderStore(directory: directory),
            placeStore: SavedPlaceStore(directory: directory)
        )
        await controller.refresh()
        #expect(controller.historyUnavailable != nil)

        // ...stays reported after a place save succeeds: the save re-read *places*,
        // it learned nothing about orders (review, PR #18 post-merge).
        try await controller.save(
            SavedPlace(name: "Дом", kind: .home, point: RoutePoint(latitude: 55, longitude: 37, address: "Дом"))
        )
        #expect(controller.historyUnavailable != nil)
        #expect(controller.placesError == nil)
    }

    @Test("The picker's memory speaks when either file fails; deliveries only for orders")
    func pickerMemorySpeaksForBothChannels() async throws {
        // A place store whose file cannot be read; orders healthy.
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("places.json"),
            withIntermediateDirectories: true
        )
        let controller = StoreController(
            orderStore: OrderStore(directory: directory),
            placeStore: SavedPlaceStore(directory: directory)
        )
        await controller.refresh()
        // Chips would be silently absent without their own channel (review, PR #28).
        #expect(controller.historyUnavailable == nil)
        #expect(controller.pickerMemoryUnavailable != nil)
    }

    @Test("No container is a rendered state: saving reports, never crashes")
    func unavailableStoreReports() async throws {
        let controller = StoreController(orderStore: nil, placeStore: nil)
        #expect(!controller.canSavePlaces)

        // It throws rather than absorbing, so the sheet that asked can stay open and
        // say so — and the error arrives already worded for the sender.
        await #expect(throws: StoreController.StoreUnavailable.self) {
            try await controller.save(
                SavedPlace(name: "Дом", kind: .home, point: RoutePoint(latitude: 55, longitude: 37, address: "Дом"))
            )
        }
        #expect(!StoreController.StoreUnavailable().localizedDescription.isEmpty,
                "a disabled affordance renders this as its reason")

        await controller.refresh()
        #expect(controller.orders.isEmpty)
    }

    @Test("A saved place keeps the person at its door")
    func savedPlaceKeepsItsContact() async throws {
        let controller = controller
        let place = PickedPlace(latitude: 59, longitude: 30, address: "Невский, 100")
        let ivan = Contact(givenName: "Иван", familyName: "Петров", phone: "+7 912 345-67-89", phoneExtension: "12")

        try await controller.save(
            SavedPlace(name: "Склад", kind: .warehouse, point: RoutePoint(place, contact: ivan))
        )

        let chip = try #require(controller.savedPlaces.first)
        #expect(Contact(at: chip.point) == ivan,
                "the chip restores the whole point — picking it is chip → done, contact included")
    }
}
