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
        #expect(controller.storeError == nil)
    }

    @Test("Saving a place persists and republishes")
    func savePersists() async throws {
        let controller = controller
        await controller.save(
            SavedPlace(name: "Склад", kind: .warehouse, point: RoutePoint(latitude: 59, longitude: 30, address: "Невский, 100"))
        )

        #expect(controller.savedPlaces.map(\.name) == ["Склад"])
        #expect(try SavedPlaceStore(directory: directory).read().count == 1)
    }

    @Test("No container is a rendered state: saving reports, never crashes")
    func unavailableStoreReports() async {
        let controller = StoreController(orderStore: nil, placeStore: nil)
        #expect(!controller.canSavePlaces)

        await controller.save(
            SavedPlace(name: "Дом", kind: .home, point: RoutePoint(latitude: 55, longitude: 37, address: "Дом"))
        )
        #expect(controller.storeError is StoreController.StoreUnavailable)

        await controller.refresh()
        #expect(controller.orders.isEmpty)
    }
}
