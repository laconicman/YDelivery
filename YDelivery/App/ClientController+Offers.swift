import Foundation
import YandexDeliveryExpressAPI

// The offers call, and the two mappings around it. Generated types live and die inside
// this file (CLAUDE.md rule 1): the draft model hands in `OfferWaypoint`s and gets back
// `Offer`s, and neither side ever sees `Components.Schemas.*`.

extension ClientController {
    /// Priced ways to run the route, the parcel and options counted in. Throws
    /// ``OffersUnavailable`` when signed out — the strip renders an invitation, not an
    /// error — and rethrows transport/decoding failures for the strip's failed state.
    func offers(for request: OfferRequest) async throws -> [Offer] {
        guard let client else { throw OffersUnavailable() }
        let response = try await client.calculateOffers(
            .init(
                // The provider answers in the market's language; the strip renders the
                // app's own words, so the header stays fixed rather than tracking locale.
                headers: .init(acceptLanguage: .ru),
                body: .json(Self.offersRequest(for: request))
            )
        )
        return try Self.offers(from: response)
    }

    /// The response read the honest way. `.ok` on a documented refusal throws an
    /// accessor error and buries the provider's `{code, message}` body — the strip
    /// then renders "the operation couldn't be completed" where the wire had said
    /// exactly what it refused (review, PR #31). Switch, decode the message, and let
    /// transport/decoding failures keep throwing as they are.
    nonisolated static func offers(
        from response: Operations.CalculateOffers.Output
    ) throws -> [Offer] {
        switch response {
        case .ok(let ok):
            let wire = try ok.body.json.offers
            let offers = wire.compactMap(Offer.init)
            // Dropping one unreadable price is right; dropping *every* one and calling the
            // result an empty success is not. That renders a blank strip with nothing to
            // retry, which reads as "no offers for this route" when it is actually a parsing
            // problem (review, PR #20). An answer we could not read is a failure.
            guard offers.isEmpty == wire.isEmpty else { throw OffersUnreadable() }
            return offers
        case .badRequest(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .unauthorized(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .conflict(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .tooManyRequests(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .internalServerError(let error):
            throw ProviderRefusal(message: (try? error.body.json.message))
        case .undocumented(let statusCode, _):
            throw ProviderRefusal(message: nil, status: statusCode)
        }
    }

    /// The request, built flat. **Coordinates are `[longitude, latitude]` on the wire**,
    /// and **item sizes are metres** where the sender typed centimetres — the two silent
    /// unit traps of handoff §4, each pinned by a test. Item point ids resolve against
    /// the same one-based visit order the route points carry.
    nonisolated static func offersRequest(
        for request: OfferRequest
    ) -> Components.Schemas.OffersCalculateRequest {
        // `nil` means the route's ends, and by `OfferRequest`'s initializer it is the
        // *only* thing it can mean — every surviving id resolves.
        let pointID: (UUID?, _ fallback: Int) -> Int64 = { id, fallback in
            Int64(id.flatMap { candidate in
                request.waypoints.firstIndex { $0.pointID == candidate }.map { $0 + 1 }
            } ?? fallback)
        }
        return .init(
            routePoints: request.waypoints.enumerated().map { index, waypoint in
                .init(
                    id: Int64(index + 1),
                    fullname: waypoint.address,
                    coordinates: [waypoint.longitude, waypoint.latitude]
                )
            },
            // The wire demands at least one item row even though the document calls
            // `items` optional — live evidence 2026-09-22: omitting it earns
            // «missing required field 'items'», sending [] earns «incorrect size,
            // must be 1 <= 0». So an empty parcel prices as a placeholder — one
            // thing going end to end, nothing declared about it — which is exactly
            // the preliminary quote the sender is asking the route for. The spec's
            // optional marker is drift, filed on the package side.
            items: request.items.isEmpty
                ? [.init(
                    quantity: 1,
                    pickupPoint: 1,
                    dropoffPoint: Int64(request.waypoints.count)
                )]
                : request.items.map { item in
                    .init(
                        quantity: item.quantity,
                        pickupPoint: pointID(item.pickupPointID, 1),
                        dropoffPoint: pointID(item.dropoffPointID, request.waypoints.count),
                        size: item.size.map {
                            .init(
                                length: $0.lengthCm / 100,
                                width: $0.widthCm / 100,
                                height: $0.heightCm / 100
                            )
                        },
                        weight: item.weightKg
                    )
                },
            requirements: Self.requirements(for: request.options)
        )
    }

    /// Only what departs from the provider's defaults goes on the wire; all-default
    /// options send no container at all.
    ///
    /// `due` is priced, not merely recorded: a scheduled pickup is what the provider
    /// searches for, and quoting it as immediate returns a price for a different job
    /// (review, PR #21). It counts toward the container being non-empty for the same
    /// reason — a due-only request must keep its `requirements`.
    private nonisolated static func requirements(
        for options: DeliveryOptions
    ) -> Components.Schemas.OfferRequirements? {
        let requirements = Components.Schemas.OfferRequirements(
            cargoLoaders: options.loaders > 0 ? options.loaders : nil,
            cargoOptions: options.thermobag ? [.thermobag] : nil,
            due: options.due,
            proCourier: options.proCourier ? true : nil,
            skipDoorToDoor: options.toDoor ? nil : true
        )
        let isEmpty = requirements.cargoLoaders == nil
            && requirements.cargoOptions == nil
            && requirements.due == nil
            && requirements.proCourier == nil
            && requirements.skipDoorToDoor == nil
        return isEmpty ? nil : requirements
    }
}

/// Everything an offers request needs, in app vocabulary — assembled by the draft,
/// mapped here.
nonisolated struct OfferRequest: Hashable, Sendable {
    var waypoints: [RequestWaypoint]
    private(set) var items: [ParcelItem]
    var options: DeliveryOptions

    /// Item stops are normalised against these waypoints on the way in: an id naming no
    /// waypoint here becomes `nil`. That is what lets the mapping below read `nil` as
    /// exactly one thing — "the route's ends", the documented default — rather than as
    /// either that *or* a stop that has since been deleted. Collapsing those two is how
    /// an item silently changes where it travels (review, PR #21).
    ///
    /// The draft repairs its own items when a stop goes, so this should never have work
    /// to do. It is here because the mapping's correctness should not depend on that:
    /// the boundary type makes the ambiguous state unrepresentable instead.
    init(waypoints: [RequestWaypoint], items: [ParcelItem], options: DeliveryOptions) {
        self.waypoints = waypoints
        self.options = options
        let live = Set(waypoints.map(\.pointID))
        self.items = items.map { item in
            var item = item
            if let id = item.pickupPointID, !live.contains(id) { item.pickupPointID = nil }
            if let id = item.dropoffPointID, !live.contains(id) { item.dropoffPointID = nil }
            return item
        }
    }

    /// A waypoint that remembers which draft point it was, so items can name their
    /// boarding and leaving stops.
    nonisolated struct RequestWaypoint: Hashable, Sendable {
        var pointID: UUID
        var latitude: Double
        var longitude: Double
        var address: String
    }
}

nonisolated extension Offer {
    /// One wire offer, read into the app's vocabulary. The with-VAT total is the price —
    /// the one that gets paid — parsed from the wire's decimal string; an unparseable
    /// price drops the offer rather than showing a number that might be wrong.
    init?(_ offer: Components.Schemas.CalculatedOffer) {
        guard let price = Decimal(string: offer.price.totalPriceWithVat, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        self.init(
            tariff: TariffClass(offer.taxiClass),
            price: price,
            currency: offer.price.currency.rawValue,
            pickupInterval: ClosedRange(saneFrom: offer.pickupInterval.from, to: offer.pickupInterval.to),
            deliveryInterval: ClosedRange(saneFrom: offer.deliveryInterval.from, to: offer.deliveryInterval.to),
            payload: offer.payload
        )
    }
}

nonisolated extension TariffClass {
    init(_ wire: Components.Schemas.TaxiClass) {
        self = switch wire {
        case .courier: .courier
        case .express: .express
        case .cargo: .cargo
        default: .other(wire.rawValue)
        }
    }
}

private nonisolated extension ClosedRange<Date> {
    /// The wire has produced intervals whose ends misbehave; a range that would trap on
    /// `from > to` becomes absence instead — the card simply shows no window.
    init?(saneFrom from: Date, to: Date) {
        guard from <= to else { return nil }
        self = from...to
    }
}
