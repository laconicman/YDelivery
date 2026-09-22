import Foundation
import MapKit
import Observation
import YDeliveryKit
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
            /// Nothing to price yet — the route is incomplete or the parcel is empty
            /// (``pricingInputs``); the strip is absent, not empty.
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

        /// What the courier carries (board `3d`). Empty is a valid draft, and a
        /// priceable one: the wire *omits* an empty item list rather than refusing
        /// it — `items` is optional on `offers/calculate`, only a present-but-empty
        /// array violates `minItems: 1` (DeepWiki consult on the spec, 2026-09-18;
        /// author chose prices-on-geo). Placing the order still requires one
        /// (``orderBlockers``).
        private(set) var items: [ParcelItem] = []
        var options = DeliveryOptions()

        /// The card the order button will spend — auto-selected to the first offer when
        /// prices land, switchable by tapping the strip. Changing class renormalizes the
        /// options that are bound to one (§4): a thermal bag cannot leave with anything
        /// but a courier, loaders only ride the cargo van — enforced here, never
        /// discovered via API errors.
        var selectedOfferID: Offer.ID? {
            didSet {
                if let tariff = selectedOffer?.tariff { chosenTariff = tariff }
                normalizeOptions()
            }
        }

        /// The request the offers on hand were priced from. What makes a quote stale is
        /// not the clock but a difference between this and ``pricingInputs`` — and the
        /// difference has to be *measured*, because clearing a selection that was already
        /// refreshed strands the sender with no class and no refetch to restore one
        /// (review, PR #22).
        private(set) var pricedRequest: OfferRequest?

        /// The class the sender last chose, kept independently of ``offers``.
        /// `selectedOffer` reads through that state and goes nil the moment repricing
        /// starts — which is not the sender changing their mind, and everything that asks
        /// "which class is this for" got the wrong answer during a reload: the options
        /// editor clamped a multi-day cargo pickup into four hours, the item editor's
        /// bounds went blank (review, PR #21).
        private(set) var chosenTariff: TariffClass?

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
                // was collected from. A default end is a position too — `nil` pickup is
                // the route's start, `nil` handover its end — so a pair with one default
                // can be just as impossible as one with neither (review, PR #21). The
                // handover is the half that gives way, since the pickup is where the
                // parcel physically is. The defaults are `pickupIndex`/`handoverIndex`'s
                // — one home, so the rows and the repair can never disagree.
                let pickup = pickupIndex(of: items[index])
                let handover = handoverIndex(of: items[index])
                if handover <= pickup {
                    items[index].dropoffPointID = nil
                    // Clearing the handover restores the route's end; if the pickup is
                    // itself the last stop, the pair is still impossible and the pickup
                    // is what has to give.
                    if pickup >= max(points.count - 1, 0) {
                        items[index].pickupPointID = nil
                    }
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

        /// True when every box passes on its own and the parcel is still too heavy for
        /// the class — the case no per-row warning can show, because no row is at fault
        /// (review, PR #21).
        func parcelIsTooHeavy(for tariff: TariffClass) -> Bool {
            !items.isEmpty
                && items.allSatisfy { tariff.fits($0) }
                && !tariff.fitsParcel(items)
        }

        // MARK: What happens at each stop

        /// The index a journey end resolves to: a named stop, or the route's end —
        /// `nil` pickup is the start, `nil` handover the last stop. The same
        /// default ``repairItemJourneys`` and the editor's chooser already speak.
        private func pickupIndex(of item: ParcelItem) -> Int {
            item.pickupPointID.flatMap { id in points.firstIndex { $0.id == id } } ?? 0
        }

        private func handoverIndex(of item: ParcelItem) -> Int {
            item.dropoffPointID.flatMap { id in points.firstIndex { $0.id == id } }
                ?? max(points.count - 1, 0)
        }

        /// What the parcel does at one stop, as the counted sentence the point row
        /// and the map callout both render (Round 5, #45–46; author, 2026-09-18 —
        /// both directions stay visible until the layout chooses between them).
        /// `nil` when nothing happens there.
        func parcelActions(at index: Int) -> String? {
            let boarding = items.filter { pickupIndex(of: $0) == index }.map(\.displayName)
            let leaving = items.filter { handoverIndex(of: $0) == index }.map(\.displayName)
            var actions: [String] = []
            if !boarding.isEmpty {
                actions.append(String(localized: "picks up \(boarding.formatted(.list(type: .and)))"))
            }
            if !leaving.isEmpty {
                actions.append(String(localized: "hands over \(leaving.formatted(.list(type: .and)))"))
            }
            return actions.isEmpty ? nil : actions.joined(separator: " · ")
        }

        /// The item's own route in the stops' own words — «A → B». Shown only when
        /// the route has middles, where a journey can differ from the route's
        /// (YD-6).
        func journeyLine(for item: ParcelItem) -> String? {
            guard points.count > 2 else { return nil }
            guard let from = points[pickupIndex(of: item)].place?.displayAddress,
                  let to = points[handoverIndex(of: item)].place?.displayAddress
            else { return nil }
            return "\(from) → \(to)"
        }

        // MARK: Offers

        /// Everything pricing answers to — route, parcel, options. Also the re-price
        /// trigger: the root's `.task(id:)` watches this, so an edit to any of the three
        /// cancels the stale run.
        var pricingInputs: OfferRequest? {
            // Geo alone prices: the wire omits an empty item list (it used to send
            // `[]` and read the provider's `minItems` refusal as «couldn't get
            // prices» — a failure state for what was never a failure). The parcel
            // refines the quote when it exists; ordering still requires it.
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
            var priced = options.effective()
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
            offers = .loading
            do {
                let loaded = try await fetch(request)
                guard !Task.isCancelled else { return }
                // Payloads are short-lived, so matching the selection by id alone moved
                // the sender to the first class on every recalculation — and the `didSet`
                // then renormalised away the options bound to the class they had chosen
                // (review, PR #21). The *class* is what they picked; the payload is only
                // what gets spent.
                pricedRequest = request
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

        // MARK: Ordering

        /// Where the one irreversible action stands (board `5f`, finding 2). Failure is
        /// a filled sentence the sheet displays as it arrived.
        enum Ordering: Hashable {
            case idle
            /// Confirmed on the review sheet; the owned task picks it up.
            case queued
            case creating
            /// The provider is pricing the created claim; the flow watches.
            case estimating
            /// Accepting — the moment money moves.
            case accepting
            case placed
            case failed(String)
            /// Acceptance began and its outcome is unknown — the provider may already
            /// have taken the order. Never says "nothing was charged", because that
            /// cannot be known from here (review, PR #22).
            case unresolved(reason: String, claimID: String?)
        }

        private(set) var ordering: Ordering = .idle
        /// The order as recorded once accepted — what history remembers.
        private(set) var placedOrder: Order?
        /// «Placed but not remembered» — the store refused after money moved; the sheet
        /// says so instead of pretending either way.
        private(set) var recordWarning: String?

        /// The idempotency token, and the request it was minted for. The provider replays
        /// the same create for the same token, which is what makes a retry safe — and what
        /// makes an *edited* retry dangerous: after a pre-acceptance failure the sender can
        /// change the route or the parcel and press Order again, and an unrotated token
        /// would have the provider replay the earlier claim instead of creating the one
        /// they just described (review, PR #22).
        ///
        /// So it is bound to the request rather than to the draft's lifetime: kept while
        /// the request is unchanged, and rotated only when the inputs differ *and* nothing
        /// has been accepted. An unresolved acceptance keeps its token, because that
        /// claim may exist and a second token would buy a second delivery.
        private(set) var orderRequestID = UUID()
        private var tokenedRequest: OrderRequest?

        /// Everything that must be true before the confirm button exists — every bound
        /// stated as a sentence the review sheet renders (the wire would otherwise say
        /// it as a 400).
        var orderBlockers: [String] {
            var blockers: [String] = []
            if !isRouteComplete {
                blockers.append(String(localized: "Every stop needs its place on the map."))
            }
            if points.contains(where: {
                // The wire's contact is `name` *and* `phone`, both required — a
                // dialable number with nobody attached still 400s at claim time
                // (DeepWiki consult on the spec, 2026-09-18).
                let contact = $0.contact?.storable
                return (contact?.phone ?? "").isEmpty || (contact?.fullName ?? "").isEmpty
            }) {
                blockers.append(String(localized: "The courier calls ahead — every stop needs a person: a name and a phone."))
            } else if points.contains(where: {
                // The same dialability rule the editor hints with: a half-typed contact
                // may be *saved*, but an order carries only numbers the courier can
                // actually call (review, PR #25).
                PhoneFormat.dialable($0.contact?.storable?.phone ?? "") == nil
            }) {
                blockers.append(String(localized: "A phone the courier can't dial is no phone yet — finish the number."))
            }
            if items.isEmpty {
                blockers.append(String(localized: "Say what's inside — the parcel is insured by its declared value."))
            } else if items.contains(where: {
                $0.name.trimmingCharacters(in: .whitespaces).isEmpty || $0.cost == nil
            }) {
                blockers.append(String(localized: "Every item needs a name and a declared value."))
            } else if items.contains(where: { ($0.cost ?? 0) <= 0 }) {
                // A declared value is what the parcel is insured for, so zero is not a
                // value — and the bound is stated here rather than discovered as a 400
                // (review, PR #22).
                blockers.append(String(localized: "A declared value of nothing insures nothing — say what each item is worth."))
            }
            if items.contains(where: { ($0.weightKg ?? 1) <= 0 }) {
                blockers.append(String(localized: "A stated weight has to be more than zero."))
            }
            if items.contains(where: { $0.quantity < 1 }) {
                blockers.append(String(localized: "Every item needs a count of at least one."))
            }
            if selectedOffer == nil {
                blockers.append(String(localized: "Pick a delivery class once prices arrive."))
            }
            return blockers
        }

        /// The create call's payload — assembled only when nothing blocks it.
        var orderRequest: OrderRequest? {
            guard orderBlockers.isEmpty, let offer = selectedOffer else { return nil }
            let requestPoints = points.compactMap { point -> OrderRequest.Point? in
                guard let place = point.place, let contact = point.contact else { return nil }
                return OrderRequest.Point(
                    pointID: point.id,
                    latitude: place.latitude,
                    longitude: place.longitude,
                    address: place.address,
                    parts: place.parts,
                    contact: contact,
                    role: point.role
                )
            }
            return OrderRequest(
                points: requestPoints,
                items: items,
                // The same options the quote was built from. Pricing normalised a lapsed
                // schedule and this did not, so the sheet showed a price for an immediate
                // run while the create carried the expired time — a quote that could not
                // produce the order it was quoting (review, PR #22).
                options: options.effective(),
                offerPayload: offer.payload,
                tariffWireValue: offer.tariff.wireValue
            )
        }

        /// The review sheet's confirm: queue the run for the owned task. A repeat tap
        /// while anything is in flight is a no-op — the task id changing is what retries.
        func confirmOrder() {
            guard let request = orderRequest else { return }
            // The sheet renders `effective()` once and nothing re-renders it, so it can
            // sit open past the pickup time still showing it. Rather than quietly sending
            // an immediate order under a schedule the sender is reading, drop the lapsed
            // time and stop here: the «When» line changes under their finger, and the
            // next press orders what it now says (review, PR #22).
            //
            // A timer refreshing the line would also close this, at the cost of a
            // repeating render for a rare case — and it would still be a silent downgrade
            // if the lapse fell between two ticks. This closes the window outright.
            if options.scheduleHasLapsed() {
                options = options.effective()
                // Drop the quote only if it was actually bought with that schedule.
                // Pricing already answers to `effective()`, so a sheet that re-rendered
                // after the lapse has *already* repriced and holds a fresh immediate
                // offer — clearing that one would strand the sender, because
                // `pricingInputs` is unchanged and nothing would refetch (review,
                // PR #22). When the held quote was priced with a due, this render is the
                // first one past the lapse, so the task id does change and prices follow.
                if pricedRequest?.options.due != nil {
                    selectedOfferID = nil
                }
                return
            }
            switch ordering {
            case .idle, .failed:
                // Safe to rotate here and only here: `.failed` is the state that promises
                // acceptance was never attempted.
                if let tokenedRequest, tokenedRequest != request {
                    orderRequestID = UUID()
                }
                tokenedRequest = request
                ordering = .queued
            default:
                break
            }
        }

        /// Runs the queued order through create → watch → accept, publishing each phase.
        /// Steps are handed in by the root so the model never learns the transport; the
        /// clock is injectable so the poll tests offline. Cancellation (the flow closed
        /// mid-run) re-queues — reopening resumes from the confirm, not from a lie.
        func placeOrder(
            create: (OrderRequest, UUID) async throws -> PlacedClaim,
            watch: (String) async throws -> PlacedClaim,
            accept: (String, Int) async throws -> PlacedClaim,
            clock: some Clock<Duration> = ContinuousClock()
        ) async {
            guard ordering == .queued, let request = orderRequest,
                  let offer = selectedOffer
            else { return }
            // Set the moment acceptance is attempted. After that point a failure is not
            // evidence that nothing happened: the provider may have accepted and lost
            // the answer on the way back.
            var acceptAttempted = false
            // Kept so an unresolved acceptance has something to ask about later; without
            // it the flow reached a terminal state holding nothing, and the only way on
            // was a fresh draft with a fresh token (review, PR #22).
            var createdClaimID: String?
            do {
                ordering = .creating
                var claim = try await create(request, orderRequestID)
                createdClaimID = claim.id

                ordering = .estimating
                let deadline = clock.now.advanced(by: Self.estimatingPatience)
                while claim.status == .estimating {
                    guard clock.now < deadline else { throw OrderingTimedOut() }
                    try await clock.sleep(for: Self.pollInterval)
                    claim = try await watch(claim.id)
                }

                // Creation is idempotent on `orderRequestID`, so a retry can be handed
                // back a claim an earlier attempt already accepted. Only a claim actually
                // waiting for approval may be accepted; accepting one twice is how a
                // dispatched courier ends up behind a screen that says every retry failed
                // (review, PR #22).
                switch claim.status {
                case .failed:
                    throw OrderingRefused(reason: claim.failureText)
                case .searching:
                    break // already accepted, and the provider is finding a courier
                case .readyToAccept:
                    ordering = .accepting
                    acceptAttempted = true
                    claim = try await accept(claim.id, claim.version)
                    // The answer is not assumed. Anything but a claim now being worked
                    // means the acceptance did not land the way this flow believes, and
                    // guessing "placed" would record a delivery that may not exist.
                    guard claim.status == .searching else {
                        throw OrderingUnknownState(status: String(describing: claim.status))
                    }
                case .estimating:
                    throw OrderingTimedOut()
                case .other(let raw):
                    // The explicit policy for a status this app does not know: do not
                    // accept it, and do not call it placed. Say the order is in an
                    // unknown state and name it, rather than guessing in either
                    // direction (review, PR #22).
                    throw OrderingUnknownState(status: raw)
                }

                placedOrder = Order(
                    created: .now,
                    status: .searching,
                    route: points.compactMap { point in
                        point.place.map { RoutePoint($0, contact: point.contact) }
                    },
                    price: ClientController.wireDecimal(offer.price),
                    currency: offer.currency,
                    tariff: offer.tariff.wireValue,
                    claimID: claim.id
                )
                ordering = .placed
            } catch is CancellationError {
                ordering = .queued
            } catch {
                guard !Task.isCancelled else { return }
                let sentence = (error as? LocalizedError)?.errorDescription
                if acceptAttempted {
                    ordering = .unresolved(
                        reason: sentence ?? String(localized: "The order may or may not have gone through."),
                        claimID: createdClaimID
                    )
                } else {
                    ordering = .failed(
                        sentence
                            ?? String(localized: "The order didn't go through. Nothing was charged — try again.")
                    )
                }
            }
        }

        /// Asks the provider what became of an acceptance whose answer was lost. This
        /// only ever *reads*: it cannot create and cannot accept, so it is safe to press
        /// as often as the sender likes. A claim being worked means the order exists and
        /// is recorded as placed; anything else leaves the unresolved state standing,
        /// because not knowing is still the honest answer (review, PR #22).
        func reconcileUnresolved(watch: (String) async throws -> PlacedClaim) async {
            guard case .unresolved(let reason, let claimID) = ordering,
                  let claimID, let offer = selectedOffer
            else { return }
            do {
                let claim = try await watch(claimID)
                guard claim.status == .searching else { return }
                placedOrder = Order(
                    created: .now,
                    status: .searching,
                    route: points.compactMap { point in
                        point.place.map { RoutePoint($0, contact: point.contact) }
                    },
                    price: ClientController.wireDecimal(offer.price),
                    currency: offer.currency,
                    tariff: offer.tariff.wireValue,
                    claimID: claim.id
                )
                ordering = .placed
            } catch {
                // Still unknown, which is what it already said.
                ordering = .unresolved(reason: reason, claimID: claimID)
            }
        }

        /// The store refused after acceptance — say so beside the placed state.
        /// Whether the placed order has been handed to the store. Recording is a
        /// *transition*, not a property of being placed — the ordering task re-runs when
        /// a parked draft is reopened, sees `.placed` again, and would record a second
        /// time. The store is idempotent by id as well, but this is what keeps a
        /// reopened draft from shuffling its own order back to the top of history
        /// (review, PR #22).
        private(set) var placedOrderIsRecorded = false

        func notePlacedOrderRecorded() {
            placedOrderIsRecorded = true
            recordWarning = nil
        }

        func notePlacedButUnrecorded(_ error: any Error) {
            recordWarning = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "The order is placed, but couldn't be saved to history on this device.")
        }

        private static let pollInterval: Duration = .seconds(1)
        /// How long estimation may reasonably hold the sender — past it, honesty beats
        /// hope; the created claim keeps living server-side either way.
        private static let estimatingPatience: Duration = .seconds(60)

        struct OrderingTimedOut: LocalizedError {
            var errorDescription: String? {
                String(localized: "The provider is taking too long to price the run. Try again in a minute — nothing was charged.")
            }
        }

        struct OrderingRefused: LocalizedError {
            let reason: String?
            var errorDescription: String? {
                reason ?? String(localized: "The provider couldn't price this run. Check the route and the parcel — nothing was charged.")
            }
        }

        /// A claim in a status this app has no rule for. Deliberately says nothing about
        /// whether money moved, because from here that is not known.
        struct OrderingUnknownState: LocalizedError {
            let status: String
            var errorDescription: String? {
                String(localized: "The order is in a state this app doesn't recognise (\(status)). Check your deliveries before ordering again.")
            }
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
                // Becoming the return moves this stop behind the others, which can put an
                // item's handover before its pickup exactly as a drag would (review,
                // PR #21). Every path that changes visit order repairs the journeys.
                repairItemJourneys()
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
