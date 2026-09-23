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

    /// The most recent failure reading *orders* — *could not look* must never render
    /// as *nothing there*. Places carry their own channel below: a place save that
    /// succeeds says nothing about whether history is readable, so it must not be able
    /// to clear this (review, PR #18 post-merge).
    private(set) var ordersError: (any Error)?
    /// The most recent failure reading *saved places* — the chips' side of the seam.
    private(set) var placesError: (any Error)?

    /// Whether the store has been read through at least once, successfully. Until it
    /// has, an empty ``orders`` means *not looked yet*, not *nothing there* — and a
    /// first-run surface that reads emptiness as "this sender is new" would greet a
    /// returning one (review, PR #20).
    private(set) var hasLoaded = false

    private let orderStore: OrderStore?
    private let placeStore: SavedPlaceStore?

    init(
        orderStore: OrderStore? = .inAppGroup(id: AppGroup.id),
        placeStore: SavedPlaceStore? = .inAppGroup(id: AppGroup.id)
    ) {
        self.orderStore = orderStore
        self.placeStore = placeStore
    }

    /// Whether keeping a place can work at all — the save affordance renders disabled
    /// with its reason when the container is unresolvable, rather than vanishing.
    var canSavePlaces: Bool { placeStore != nil }

    /// Why there is no history to show, when there is none for a reason. A read that
    /// failed and a container that never resolved are different causes with the same
    /// symptom — an empty list — and both must be told apart from "you have not sent
    /// anything yet" (review, PR #18). `nil` when the store is healthy, whether or not
    /// it holds anything.
    var historyUnavailable: String? {
        if let ordersError { return ordersError.localizedDescription }
        if orderStore == nil, placeStore == nil { return StoreUnavailable().localizedDescription }
        return nil
    }

    /// Why the picker's memory — chips *and* recents — may be missing pieces. The
    /// picker draws on both files (recents from orders, chips from places), so either
    /// error deserves a word there; the deliveries list stays keyed to orders alone.
    /// Without this, a failed place read left chips silently absent while
    /// ``historyUnavailable`` reported health (review, PR #28).
    var pickerMemoryUnavailable: String? {
        if let error = ordersError ?? placesError { return error.localizedDescription }
        if orderStore == nil, placeStore == nil { return StoreUnavailable().localizedDescription }
        return nil
    }

    /// Whether the sender has ever actually placed an order. The beginner's explainer
    /// runs "until the first successful order" (Roadmap, handoff §7) — and a draft is
    /// precisely an order that was never placed, so counting rows would retire the
    /// explainer for someone who has only ever started one (review, PR #20).
    ///
    /// «Successful» means **accepted by the system**, settled by the author 2026-09-06:
    /// a placed order is part of history whatever becomes of it afterwards, and whether it
    /// was later cancelled or failed to deliver is a question about its status, not about
    /// whether the sender has ordered before. So a cancelled or undelivered order still
    /// counts — they went through the strip and chose a class, which is the vocabulary
    /// this teaches.
    var hasPlacedAnOrder: Bool {
        orders.contains { $0.status != .draft }
    }

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
        var seen = Set(saved.map { destinationKey($0.point) })
        var recents: [RoutePoint] = []
        for point in orders.flatMap(\.route) {
            guard !point.address.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard seen.insert(destinationKey(point)).inserted else { continue }
            recents.append(point)
            if recents.count == limit { break }
        }
        return recents
    }

    /// What makes two remembered points *the same delivery destination*, so the two
    /// things that deduplicate against each other agree on what "same" means.
    ///
    /// The address alone is not enough. Flat 12 and flat 46 of one building share a
    /// street address and are different doors with different people behind them; keeping
    /// only the newest would offer a recent that restores the wrong apartment and the
    /// wrong contact (review, PR #18). The door details and the coordinates are part of
    /// the identity for exactly that reason.
    /// Internal rather than private: the picker's rows identify themselves by the same
    /// key, so what deduplicates a list and what selects from it cannot disagree.
    nonisolated static func destinationKey(_ point: RoutePoint) -> String {
        let address = point.address.lowercased().trimmingCharacters(in: .whitespaces)
        let parts = point.addressParts.map {
            "\($0.entrance)|\($0.floor)|\($0.apartment)|\($0.intercom)".lowercased()
        } ?? ""
        // Five decimals is about a metre — enough to separate two entrances of one
        // building, coarse enough that the same pin re-read stays one memory.
        let coordinates = String(
            format: "%.5f,%.5f", point.latitude, point.longitude
        )
        return "\(address)#\(parts)#\(coordinates)"
    }

    /// Reads both files off the main actor and publishes the result here — each file
    /// onto its own error channel, so one side's failure is never mistaken for the
    /// other's emptiness.
    func refresh() async {
        if let orderStore {
            do {
                // Sorted at publish, not trusted to the file: `record(_:)` writes
                // prepend-only, so a sync pass persisting several changed orders
                // would otherwise reverse their order in the list (Phase 3).
                orders = try await Self.readOrders(orderStore).sorted { $0.created > $1.created }
                ordersError = nil
                hasLoaded = true
            } catch {
                ordersError = error
            }
        } else {
            hasLoaded = true
        }
        if let placeStore {
            do {
                savedPlaces = try await Self.readPlaces(placeStore)
                placesError = nil
            } catch {
                placesError = error
            }
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
        do {
            savedPlaces = try await Self.readPlaces(placeStore)
            // That re-read succeeded, so whatever the last refresh recorded about
            // *places* is stale news. Orders were not looked at: their error, if any,
            // stands — a successful bookmark must not dress an unreadable history as
            // an empty one (review, PR #18 post-merge).
            placesError = nil
        } catch {
            // The write held but the confirming read did not: the sheet gets the
            // thrown error to render, and the channel records it — otherwise closing
            // the sheet exposed stale chips as healthy memory (review, PR #28, same
            // truth as record()'s: the write and the read report different facts).
            placesError = error
            throw error
        }
    }

    /// Records a placed order and republishes history. Throws — an order that was
    /// *placed* but not *remembered* is a state the sender must see, not a silent gap
    /// in the list.
    func record(_ order: Order) async throws {
        guard let orderStore else { throw StoreUnavailable() }
        try await Self.write(order, to: orderStore)
        // The write held; if the confirming read stumbles, the order still leads the
        // list rather than vanishing until the next refresh — but the write and the
        // read report different facts, and only the read may clear the error: a
        // partial fallback list dressed as healthy history omits orders silently
        // (review, PR #28).
        do {
            orders = try await Self.readOrders(orderStore).sorted { $0.created > $1.created }
            ordersError = nil
        } catch {
            orders = Self.upserting(order, into: orders)
            ordersError = error
        }
    }

    /// The fallback merge when the confirming read fails: the written order kept,
    /// minus any stale copy of itself — recording an *update* (a just-cancelled
    /// order) must not leave its previous status riding along as a second row
    /// (review, PR #32). Sorted like the publish path: an update to an *older*
    /// order must not jump the queue just because it led the write.
    nonisolated static func upserting(_ order: Order, into orders: [Order]) -> [Order] {
        ([order] + orders.filter { $0.id != order.id }).sorted { $0.created > $1.created }
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
    private static func readPlaces(_ store: SavedPlaceStore) async throws -> [SavedPlace] {
        try store.read()
    }

    @concurrent
    private static func write(_ place: SavedPlace, to store: SavedPlaceStore) async throws {
        // Dedupe against the *file*, not the controller's memory: the retry that this
        // guards against exists precisely because a read failed, so memory may not
        // know about the copy already written (review, PR #18 post-merge). Same
        // destination — same `destinationKey` the chips deduplicate recents by —
        // means the write adopts the stored identity and the Kit's save upserts.
        var place = place
        if let existing = (try? store.read())?.first(where: {
            destinationKey($0.point) == destinationKey(place.point)
        }) {
            place.id = existing.id
        }
        try store.save(place)
    }

    @concurrent
    private static func readOrders(_ store: OrderStore) async throws -> [Order] {
        try store.read()
    }

    @concurrent
    private static func write(_ order: Order, to store: OrderStore) async throws {
        try store.record(order)
    }
}
