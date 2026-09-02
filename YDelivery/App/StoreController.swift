import Foundation
import Observation
import YDeliveryKit

/// The app's window onto the one substrate — orders and saved places, read three ways
/// (recents, chips, and later repeat). Created once in `@main` and injected with
/// `.environment(_:)`; the stores it owns are the provisional App-Group files, so this
/// controller is also the seam the Phase-2 schema research will swap out from under the
/// UI without the UI noticing.
///
/// Being containerless (no App Group in a preview, a broken entitlement) is a state this
/// type exposes for rendering, never a crash.
@Observable @MainActor
final class StoreController {
    private(set) var orders: [Order] = []
    private(set) var savedPlaces: [SavedPlace] = []

    /// The most recent read/write failure — *could not look* must never render as
    /// *nothing there*.
    private(set) var storeError: (any Error)?

    private let orderStore: OrderStore?
    private let placeStore: SavedPlaceStore?

    init(
        orderStore: OrderStore? = .inAppGroup(),
        placeStore: SavedPlaceStore? = .inAppGroup()
    ) {
        self.orderStore = orderStore
        self.placeStore = placeStore
    }

    /// Whether keeping a place can work at all — the save affordance renders disabled
    /// with its reason when the container is unresolvable, rather than vanishing.
    var canSavePlaces: Bool { placeStore != nil }

    /// The recent points the picker offers: one per address, newest first — an address
    /// delivered to twice is one memory, not two rows (Design → one substrate).
    var recentPoints: [RoutePoint] {
        Self.recentPoints(in: orders)
    }

    /// Pure and `nonisolated` so the derivation is testable without a controller.
    /// Orders arrive newest-first from the store; the cap keeps the empty-query list
    /// one screen tall (board `2a`).
    nonisolated static func recentPoints(in orders: [Order], limit: Int = 8) -> [RoutePoint] {
        var seen = Set<String>()
        var recents: [RoutePoint] = []
        for point in orders.flatMap(\.route) {
            let key = point.address.lowercased().trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            recents.append(point)
            if recents.count == limit { break }
        }
        return recents
    }

    /// Reads both files off the main actor and publishes the result here.
    func refresh() async {
        do {
            let (orders, places) = try await Self.read(orderStore: orderStore, placeStore: placeStore)
            self.orders = orders
            savedPlaces = places
            storeError = nil
        } catch {
            storeError = error
        }
    }

    /// Keeps a place and republishes the set. Throws into ``storeError`` — history that
    /// did not persist is a state the sender must see.
    func save(_ place: SavedPlace) async {
        guard let placeStore else {
            storeError = StoreUnavailable()
            return
        }
        do {
            try await Self.write(place, to: placeStore)
            savedPlaces = try await Self.readPlaces(placeStore)
            storeError = nil
        } catch {
            storeError = error
        }
    }

    struct StoreUnavailable: LocalizedError {
        var errorDescription: String? {
            String(localized: "Shared storage is unavailable on this install.")
        }
    }

    // The stores are synchronous, coordinated file IO — `@concurrent` hops them off the
    // main actor (a plain nonisolated async function would inherit the caller's actor
    // under Approachable Concurrency).

    @concurrent
    private static func read(
        orderStore: OrderStore?,
        placeStore: SavedPlaceStore?
    ) async throws -> ([Order], [SavedPlace]) {
        (try orderStore?.read() ?? [], try placeStore?.read() ?? [])
    }

    @concurrent
    private static func readPlaces(_ store: SavedPlaceStore) async throws -> [SavedPlace] {
        try store.read()
    }

    @concurrent
    private static func write(_ place: SavedPlace, to store: SavedPlaceStore) async throws {
        try store.save(place)
    }
}
