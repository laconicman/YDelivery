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
        Self.recentPoints(in: orders, saved: savedPlaces)
    }

    /// Pure and `nonisolated` so the derivation is testable without a controller.
    /// Orders arrive newest-first from the store; the cap keeps the empty-query list
    /// one screen tall (board `2a`).
    ///
    /// Saved places are excluded rather than repeated. Chips and recents are one list
    /// on board `2a`, and a place the sender has named is the same memory with more in
    /// it — offering it again as an anonymous clock row is the "two rows" this
    /// derivation already refuses between recents (review, PR #18).
    nonisolated static func recentPoints(
        in orders: [Order],
        saved: [SavedPlace] = [],
        limit: Int = 8
    ) -> [RoutePoint] {
        var seen = Set(saved.map { addressKey($0.point.address) })
        var recents: [RoutePoint] = []
        for point in orders.flatMap(\.route) {
            let key = addressKey(point.address)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            recents.append(point)
            if recents.count == limit { break }
        }
        return recents
    }

    /// One spelling of "the same address", so the two things that dedupe against each
    /// other agree on what same means.
    private nonisolated static func addressKey(_ address: String) -> String {
        address.lowercased().trimmingCharacters(in: .whitespaces)
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

    /// Keeps a place and republishes the set.
    ///
    /// This one throws rather than absorbing into ``storeError``, because unlike a refresh
    /// it has a caller standing in front of the sender: the naming sheet, which can stay
    /// open, say what went wrong, and offer the write again. A bookmark that did not
    /// persist must never look like one that did (review, PR #18). The error is a filled
    /// `LocalizedError`, so the sheet renders it as it arrives.
    func save(_ place: SavedPlace) async throws {
        guard let placeStore else { throw StoreUnavailable() }
        try await Self.write(place, to: placeStore)
        savedPlaces = try await Self.readPlaces(placeStore)
        // That re-read succeeded, so whatever the last refresh recorded is stale news.
        storeError = nil
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
