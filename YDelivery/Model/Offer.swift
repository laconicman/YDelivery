import Foundation

/// A priced way to run the route — one card of the tariff strip. App vocabulary only:
/// the wire's `CalculatedOffer` stops at the controller boundary, and its `payload` (the
/// capability token `claims/create` will spend) rides along opaquely.
nonisolated struct Offer: Hashable, Sendable, Identifiable {
    var tariff: TariffClass
    /// What actually leaves the account — the with-VAT total. The strip shows one price,
    /// and the honest one is the one that gets paid.
    var price: Decimal
    var currency: String
    var pickupInterval: ClosedRange<Date>?
    var deliveryInterval: ClosedRange<Date>?
    /// The offer token for `claims/create`. Short-lived; never rendered.
    var payload: String

    var id: String { payload }
}

/// The provider's delivery classes, in the sender's words — courier, car, van; never the
/// vendor's spelling past the controller.
nonisolated enum TariffClass: Hashable, Sendable {
    case courier
    case express
    case cargo
    /// A class this app does not know yet — rendered by its wire name rather than
    /// dropped, so new provider vocabulary stays visible (the demo's lesson: advisory
    /// vocabulary grows without announcement).
    case other(String)
}

nonisolated extension TariffClass {
    var words: String {
        switch self {
        case .courier: String(localized: "Courier")
        case .express: String(localized: "Express")
        case .cargo: String(localized: "Cargo van")
        case .other(let name): name
        }
    }

    var emoji: String {
        switch self {
        case .courier: "🛵"
        case .express: "🚗"
        case .cargo: "🚚"
        case .other: "📦"
        }
    }

    /// One line of what the class is, for the beginner explainer (board `3a`).
    var explanation: String? {
        switch self {
        case .courier: String(localized: "On foot or a scooter")
        case .express: String(localized: "A passenger car")
        case .cargo: String(localized: "A van, loaders available")
        case .other: nil
        }
    }

    /// The class's bounds, stated as the helper text — constraints replace hints
    /// (DesignSystem → "Field taxonomy").
    ///
    /// **Static copy, v1** (author, 2026-08-30): the `tariffs` operation that would make
    /// these live per-city data is not in `YandexDeliveryExpressAPI` 0.2.0 — the need is
    /// recorded in the package's Roadmap, and these lines follow the provider's published
    /// defaults until then.
    var limits: [String] {
        switch self {
        case .courier: [
            String(localized: "Up to 10 kg"),
            String(localized: "80 × 50 × 50 cm"),
        ]
        case .express: [
            String(localized: "Up to 20 kg"),
            String(localized: "100 × 60 × 50 cm"),
        ]
        case .cargo: [
            String(localized: "Up to 300 kg · 170 × 96 × 90 cm"),
            String(localized: "Loaders — one or two"),
        ]
        case .other: []
        }
    }

    /// The selected card's one constraint line (board `1b`).
    var limitsSummary: String? {
        limits.isEmpty ? nil : limits.joined(separator: " · ")
    }
}

nonisolated extension Offer {
    /// «1 190 ₽» — the strip's number, localized. Formatting lives here, not in a view
    /// body (R5).
    var priceText: String {
        price.formatted(.currency(code: currency).precision(.fractionLength(0...2)))
    }
}

/// Thrown by the offers fetch when no session exists — the strip renders a sign-in
/// invitation, not a failure. Model-layer type so the draft model never learns the
/// controller's shape. `LocalizedError` with a filled description, like every error
/// here that could ever surface (author's standing preference).
/// The answer carried offers and none of them could be read — the strip shows its failed
/// state, with a retry, rather than an empty one with nothing to press.
nonisolated struct OffersUnreadable: LocalizedError, Hashable {
    var errorDescription: String? {
        String(localized: "The prices came back in a form this app could not read.")
    }
}

nonisolated struct OffersUnavailable: LocalizedError, Hashable {
    var errorDescription: String? {
        String(localized: "Sign in with your Yandex Delivery token to see prices.")
    }
}

/// One stop of the route, reduced to what an offers request needs.
nonisolated struct OfferWaypoint: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var address: String
}
