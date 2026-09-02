import Foundation
import YandexDeliveryExpressAPI

// The offers call, and the two mappings around it. Generated types live and die inside
// this file (CLAUDE.md rule 1): the draft model hands in `OfferWaypoint`s and gets back
// `Offer`s, and neither side ever sees `Components.Schemas.*`.

extension ClientController {
    /// Priced ways to run the route. Throws ``OffersUnavailable`` when signed out — the
    /// strip renders an invitation, not an error — and rethrows transport/decoding
    /// failures for the strip's failed state.
    func offers(for waypoints: [OfferWaypoint]) async throws -> [Offer] {
        guard let client else { throw OffersUnavailable() }
        let response = try await client.calculateOffers(
            .init(
                // The provider answers in the market's language; the strip renders the
                // app's own words, so the header stays fixed rather than tracking locale.
                headers: .init(acceptLanguage: .ru),
                body: .json(Self.offersRequest(for: waypoints))
            )
        )
        return try response.ok.body.json.offers.compactMap(Offer.init)
    }

    /// The request, built flat. **Coordinates are `[longitude, latitude]` on the wire** —
    /// the one ordering bug that yields a plausible wrong answer instead of an error
    /// (handoff §4), which is why this mapping is a pure function with a test pinning
    /// the order.
    nonisolated static func offersRequest(
        for waypoints: [OfferWaypoint]
    ) -> Components.Schemas.OffersCalculateRequest {
        .init(
            routePoints: waypoints.enumerated().map { index, waypoint in
                .init(
                    id: Int64(index + 1),
                    fullname: waypoint.address,
                    coordinates: [waypoint.longitude, waypoint.latitude]
                )
            }
        )
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
