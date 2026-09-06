import Foundation
import MapKit
import Observation
// SwiftUI supplies `remove(atOffsets:)` / `move(fromOffsets:toOffset:)` — the exact
// semantics `onDelete`/`onMove` hand this model; reimplementing them here would be the
// riskier kind of purity.
import SwiftUI

extension NewDeliveryView {
    /// The flow's draft: the ordered route and what each stop carries. Owned by
    /// `RootView`, one level above the sheet that renders it (R7: one owner, as low as
    /// the lifetime allows) — dismissing the flow parks the draft, because navigation
    /// must never destroy one (Design → "The tab bar goes").
    ///
    /// Invariants this type enforces, so views cannot break them: the route keeps at
    /// least its two founding rows; the first point is the pickup; at most one return
    /// point exists and it stays last (what could not be handed over goes back at the
    /// end of the run); a swap is offered only when it exchanges two filled ends.
    @Observable @MainActor
    final class Model {
        /// One stop of the draft, before it earns a place in an order. Identity is
        /// minted when the sender adds the row and is stable for its whole life (R8) —
        /// reordering moves the row, never renames it.
        nonisolated struct Point: Identifiable, Hashable, Sendable {
            let id: UUID
            var role: Role
            var place: PickedPlace?
            var contact: Contact?

            init(role: Role, place: PickedPlace? = nil, contact: Contact? = nil) {
                id = UUID()
                self.role = role
                self.place = place
                self.contact = contact
            }
        }

        /// What happens at the door — the sender's vocabulary (забрать · доставить ·
        /// вернуть), mapped to the wire's point types only at the controller boundary.
        nonisolated enum Role: Hashable, Sendable {
            case pickup
            case dropoff
            case `return`
        }

        /// The whole route's distance and time, from the map's own routing — the states
        /// of the estimate bar (board `1b`). Failure keeps its place: the bar renders
        /// it at the same height rather than collapsing the layout (decision #13).
        enum Estimate: Hashable {
            /// No complete route to estimate — the bar is absent, not empty.
            case idle
            case calculating
            case ready(RouteEstimate)
            case failed
        }

        /// Waypoints in travel order → an estimate. Defaults to `MKDirections`, one
        /// request per leg; injected so the state machine tests offline.
        typealias RouteEstimator =
            @Sendable (_ waypoints: [RouteEstimate.Coordinate]) async throws -> RouteEstimate

        /// The tariff strip's states (board `1b`): waiting is a drawn state, failure
        /// keeps the strip's place, and signed-out is an invitation — never an error.
        enum Offers: Hashable {
            /// No complete route — the strip is absent, not empty.
            case idle
            case loading
            case ready([Offer])
            case failed
            /// No session: prices need a token; drafting never did.
            case signedOut
        }

        private(set) var points: [Point]
        private(set) var estimate: Estimate = .idle
        private(set) var offers: Offers = .idle

        /// What the courier carries (board `3d`). Empty is a valid draft — the provider
        /// then prices against the class's maximum dimensions.
        private(set) var items: [ParcelItem] = []
        var options = DeliveryOptions()

        /// The card the order button will spend — auto-selected to the first offer when
        /// prices land, switchable by tapping the strip. Changing class renormalizes the
        /// options that are bound to one (§4): a thermal bag cannot leave with anything
        /// but a courier, loaders only ride the cargo van — enforced here, never
        /// discovered via API errors.
        var selectedOfferID: Offer.ID? {
            didSet { normalizeOptions() }
        }

        private func normalizeOptions() {
            guard let tariff = selectedOffer?.tariff else { return }
            if tariff != .courier { options.thermobag = false }
            if tariff != .cargo { options.loaders = 0 }
        }

        private let estimateRoute: RouteEstimator

        init(estimateRoute: @escaping RouteEstimator = Model.mkDirectionsEstimator) {
            points = [Point(role: .pickup), Point(role: .dropoff)]
            self.estimateRoute = estimateRoute
        }

        /// Every stop chosen, nothing pending — the gate for everything downstream
        /// (estimate, offers, creation). An added-but-empty stop is a hole in the
        /// route, not an extra.
        var isRouteComplete: Bool {
            points.count >= 2 && points.allSatisfy { $0.place != nil }
        }

        /// Swapping is the two-point affordance: with more points the order is edited by
        /// reordering, and with an end empty a swap would just *move* the address, which
        /// reads as data loss.
        var canSwap: Bool {
            points.count == 2 && isRouteComplete
        }

        /// From three points on, reordering replaces swapping (board `2b`).
        var canReorder: Bool {
            points.count > 2
        }

        var hasReturnPoint: Bool {
            points.contains { $0.role == .return }
        }

        func point(withID id: Point.ID) -> Point? {
            points.first { $0.id == id }
        }

        /// Roles a stop may switch to. The first row is the route's start and never
        /// changes; the return role is offered while no return point exists — and never
        /// to the route's only delivery, because a route that delivers nothing is not a
        /// route (review, PR #17); a return point may step back to being a delivery.
        func availableRoles(for id: Point.ID) -> [Role] {
            guard let index = points.firstIndex(where: { $0.id == id }), index > 0 else {
                return []
            }
            return switch points[index].role {
            case .pickup: [.dropoff]
            case .dropoff: hasReturnPoint || dropoffCount < 2 ? [] : [.return]
            case .return: [.dropoff]
            }
        }

        private var dropoffCount: Int {
            points.count { $0.role == .dropoff }
        }

        /// Exchanges what stands at the two ends — places and the people at the door.
        /// Roles and row identities stay put: the route still starts with a pickup, and
        /// SwiftUI sees the same rows with exchanged content, not new rows.
        func swapEnds() {
            guard canSwap, var first = points.first, var second = points.last else { return }
            (first.place, second.place) = (second.place, first.place)
            (first.contact, second.contact) = (second.contact, first.contact)
            // `canSwap` means exactly two points, so first and last are the whole route.
            points = [first, second]
        }

        /// Adds an unfilled drop-off and returns its id so the caller can open the
        /// picker for it in the same gesture. New stops join before any return point —
        /// the return stays last.
        @discardableResult
        func addStop() -> Point.ID {
            let stop = Point(role: .dropoff)
            let index = points.firstIndex { $0.role == .return } ?? points.endIndex
            points.insert(stop, at: index)
            return stop.id
        }

        /// Removes stops. The pickup row is the route's start and stays; the route never
        /// shrinks below two rows — an A→B draft with a row missing is not a route —
        /// and the last delivery cannot be removed out from beside a return point
        /// (review, PR #17: pickup → return delivers nothing).
        func removePoints(at offsets: IndexSet) {
            guard !offsets.contains(0), points.count - offsets.count >= 2 else { return }
            let remaining = points.indices
                .filter { !offsets.contains($0) }
                .map { points[$0] }
            guard remaining.contains(where: { $0.role == .dropoff }) else { return }
            points = remaining
            repairItemJourneys()
        }

        /// An item names the stop it boards and the stop it leaves at. Two edits can make
        /// that pair untrue: deleting a named stop leaves the name pointing at nothing,
        /// and reordering can put the handover *before* the pickup. Both are repaired
        /// here, because both mean the same thing downstream — a journey the sender did
        /// not describe (review, PR #21).
        ///
        /// Forgetting is the honest repair: `nil` genuinely means the route's ends, which
        /// is the common case and what the item editor offers by default. Keeping a
        /// dangling or reversed id and resolving it later would be the silent version of
        /// the same thing.
        private func repairItemJourneys() {
            let order = Dictionary(uniqueKeysWithValues: points.enumerated().map { ($1.id, $0) })
            for index in items.indices {
                if let id = items[index].pickupPointID, order[id] == nil {
                    items[index].pickupPointID = nil
                }
                if let id = items[index].dropoffPointID, order[id] == nil {
                    items[index].dropoffPointID = nil
                }
                // A box cannot be handed over before it is collected, nor at the door it
                // was collected from. The handover is the half that gives way, since the
                // pickup is where the parcel physically is.
                if let pickup = items[index].pickupPointID.flatMap({ order[$0] }),
                   let dropoff = items[index].dropoffPointID.flatMap({ order[$0] }),
                   dropoff <= pickup {
                    items[index].dropoffPointID = nil
                }
            }
        }

        /// Reorders stops. The pickup is pinned first and the return last; a move that
        /// would unseat either is clamped rather than half-applied.
        func movePoints(from source: IndexSet, to destination: Int) {
            let lowerBound = 1
            let upperBound = hasReturnPoint ? points.count - 1 : points.count
            guard source.allSatisfy({ $0 >= lowerBound && $0 < upperBound }) else { return }
            let clamped = min(max(destination, lowerBound), upperBound)
            points.move(fromOffsets: source, toOffset: clamped)
            repairItemJourneys()
        }

        func setPlace(_ place: PickedPlace, for id: Point.ID) {
            guard let index = points.firstIndex(where: { $0.id == id }) else { return }
            points[index].place = place
        }

        /// A pasted route link fills both ends in one action (decision #9): the pickup
        /// and the last delivery. Contacts stay put — a link knows places, not people.
        func fillEnds(from: PickedPlace, to: PickedPlace) {
            points[0].place = from
            if let index = points.lastIndex(where: { $0.role == .dropoff }) {
                points[index].place = to
            }
        }

        /// Stores what ``Contact/storable`` says deserves keeping — an emptied card
        /// returns the row's invitation rather than a blank line.
        func setContact(_ contact: Contact?, for id: Point.ID) {
            guard let index = points.firstIndex(where: { $0.id == id }) else { return }
            points[index].contact = contact.flatMap(\.storable)
        }

        // MARK: Estimate

        /// The route as coordinates, in travel order — what the estimate answers to.
        /// The root view re-runs the calculation whenever this changes (`.task(id:)`),
        /// so an edited route cancels the stale estimate structurally.
        var routeWaypoints: [RouteEstimate.Coordinate] {
            guard isRouteComplete else { return [] }
            return points.compactMap { point in
                point.place.map { RouteEstimate.Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
            }
        }

        /// Estimates the current route, publishing every state the bar renders. An
        /// incomplete route clears to `.idle` — no bar, not a stale number. Cancellation
        /// (a route edit mid-flight) leaves the state to the next run.
        func calculateEstimate() async {
            let waypoints = routeWaypoints
            guard waypoints.count >= 2 else {
                estimate = .idle
                return
            }
            estimate = .calculating
            do {
                let result = try await estimateRoute(waypoints)
                guard !Task.isCancelled else { return }
                estimate = .ready(result)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                estimate = .failed
            }
        }

        // MARK: Parcel

        func item(withID id: ParcelItem.ID) -> ParcelItem? {
            items.first { $0.id == id }
        }

        /// A blank card saves as nothing — the «Add an item» invitation returns. The
        /// journey is repaired on the way in as well: the editor's pickers now decline
        /// an impossible pair, and the model does not depend on them to.
        func setItem(_ item: ParcelItem) {
            defer { repairItemJourneys() }
            guard let index = items.firstIndex(where: { $0.id == item.id }) else {
                if !item.isBlank { items.append(item) }
                return
            }
            if item.isBlank {
                items.remove(at: index)
            } else {
                items[index] = item
            }
        }

        func removeItems(at offsets: IndexSet) {
            items.remove(atOffsets: offsets)
        }

        /// The heaviest reading of the parcel against a class's bounds — what the strip
        /// and the explainer warn with (board `3a`: the mismatch note).
        func itemsThatDontFit(_ tariff: TariffClass) -> [ParcelItem] {
            items.filter { !tariff.fits($0) }
        }

        // MARK: Offers

        /// Everything pricing answers to — route, parcel, options. Also the re-price
        /// trigger: the root's `.task(id:)` watches this, so an edit to any of the three
        /// cancels the stale run.
        var pricingInputs: OfferRequest? {
            guard isRouteComplete else { return nil }
            let waypoints = points.compactMap { point in
                point.place.map {
                    OfferRequest.RequestWaypoint(
                        pointID: point.id,
                        latitude: $0.latitude,
                        longitude: $0.longitude,
                        address: $0.address
                    )
                }
            }
            // The note the courier reads is carried to claim creation, never to pricing —
            // the offers request has nowhere to put it. Leaving it in the identity made
            // every keystroke in that field re-fetch identical offers (review, PR #21).
            var priced = options.lapsedScheduleCleared(for: selectedOffer?.tariff)
            priced.comment = ""
            return OfferRequest(waypoints: waypoints, items: items, options: priced)
        }

        /// Loads priced offers through the caller's fetch — the root view hands in the
        /// session controller's call, so this model never learns the transport. The
        /// selection survives a reload when the same offer returns; otherwise the first
        /// offer is selected, so the strip always has an answer for the order button.
        func loadOffers(
            _ fetch: (OfferRequest) async throws -> [Offer]
        ) async {
            guard let request = pricingInputs else {
                offers = .idle
                selectedOfferID = nil
                return
            }
            // Captured before the state leaves `.ready`: `selectedOffer` reads through
            // `offers`, so asking after `.loading` would always answer nil.
            let chosenTariff = selectedOffer?.tariff
            offers = .loading
            do {
                let loaded = try await fetch(request)
                guard !Task.isCancelled else { return }
                // Payloads are short-lived, so matching the selection by id alone moved
                // the sender to the first class on every recalculation — and the `didSet`
                // then renormalised away the options bound to the class they had chosen
                // (review, PR #21). The *class* is what they picked; the payload is only
                // what gets spent.
                offers = .ready(loaded)
                if !loaded.contains(where: { $0.id == selectedOfferID }) {
                    let sameClass = chosenTariff.flatMap { tariff in
                        loaded.first { $0.tariff == tariff }
                    }
                    selectedOfferID = (sameClass ?? loaded.first)?.id
                }
            } catch is CancellationError {
            } catch is OffersUnavailable {
                guard !Task.isCancelled else { return }
                offers = .signedOut
                selectedOfferID = nil
            } catch {
                guard !Task.isCancelled else { return }
                offers = .failed
            }
        }

        var selectedOffer: Offer? {
            guard case .ready(let offers) = offers else { return nil }
            return offers.first { $0.id == selectedOfferID }
        }

        /// Changes what happens at a stop's door. ``availableRoles(for:)`` is the single
        /// source of truth for what a stop may become, so a role it does not offer is
        /// refused here too — the pinned pickup keeps its role, a second return is
        /// declined, and the route's only delivery stays a delivery (review, PR #17).
        /// Becoming the return moves the stop to the end of the run; leaving the role
        /// also leaves the pinned seat.
        func setRole(_ role: Role, for id: Point.ID) {
            guard let index = points.firstIndex(where: { $0.id == id }),
                  availableRoles(for: id).contains(role)
            else { return }
            points[index].role = role
            if role == .return {
                points.append(points.remove(at: index))
            }
        }
    }
}

// MARK: - Live seam

extension NewDeliveryView.Model {
    /// `MKDirections`, one request per leg, summed — the map's honest guess until
    /// provider figures replace it (decision #14). Any leg without a route fails the
    /// whole estimate: a number covering half the route would be a lie.
    nonisolated static let mkDirectionsEstimator: RouteEstimator = { waypoints in
        var distance: Double = 0
        var time: TimeInterval = 0
        var legs: [[RouteEstimate.Coordinate]] = []
        for (from, to) in zip(waypoints, waypoints.dropFirst()) {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(
                coordinate: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude)
            ))
            request.destination = MKMapItem(placemark: MKPlacemark(
                coordinate: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)
            ))
            request.transportType = .automobile
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { throw NoRouteFound() }
            distance += route.distance
            time += route.expectedTravelTime
            legs.append(route.polyline.coordinateRun)
        }
        return RouteEstimate(distanceMeters: distance, travelTime: time, legs: legs)
    }

    nonisolated struct NoRouteFound: LocalizedError {
        var errorDescription: String? {
            String(localized: "No drivable route between these points.")
        }
    }
}

private nonisolated extension MKPolyline {
    /// The polyline's points as plain values — what crosses back to the main actor.
    var coordinateRun: [RouteEstimate.Coordinate] {
        var coordinates = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(),
            count: pointCount
        )
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates.map { RouteEstimate.Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
