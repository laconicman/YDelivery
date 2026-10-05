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
    /// The wire's `description` — the variant within a class (`express_30min_longer`
    /// and kin). Kept opaque and never rendered raw: same-class offers differ only
    /// by it and their windows, and the windows are what the card says.
    var variant: String? = nil
    /// `offer_ttl` — past it the payload cannot be spent, so it is the strip's
    /// re-price deadline.
    var validUntil: Date? = nil
    /// `price.surge_ratio` — the demand multiplier the price already reflects.
    var surgeRatio: Double? = nil
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
    /// `sdd_long` — same-day delivery on a longer run.
    case sddLong
    /// `superexpress_d2d` — the vendor's «Быстрее»: door to door in minimum time.
    case superexpressD2D
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
        case .sddLong: String(localized: "Same-day")
        case .superexpressD2D: String(localized: "Super-express")
        case .other(let name): name
        }
    }

    var emoji: String {
        switch self {
        case .courier: "🛵"
        case .express: "🚗"
        case .cargo: "🚚"
        case .sddLong: "🛣️"
        case .superexpressD2D: "⚡️"
        case .other: "📦"
        }
    }

    /// One line of what the class is, for the beginner explainer (board `3a`).
    var explanation: String? {
        switch self {
        case .courier: String(localized: "On foot or a scooter")
        case .express: String(localized: "A passenger car")
        case .cargo: String(localized: "A van, loaders available")
        case .sddLong: String(localized: "A longer run, still within the day")
        case .superexpressD2D: String(localized: "Door to door in the least time")
        case .other: nil
        }
    }

    /// The class's bounds as numbers, so fit checks and display derive from one truth.
    ///
    /// **Static data, v1** (author, 2026-08-30): the `tariffs` operation that would make
    /// these live per-city data is not in `YandexDeliveryExpressAPI` 0.2.0 — the need is
    /// recorded in the package's Roadmap, and these values follow the provider's
    /// published defaults (its `ItemSize` note; cargo = the small body) until then.
    var maxWeightKg: Double? {
        switch self {
        case .courier: 10
        case .express: 20
        case .cargo: 300
        case .sddLong, .superexpressD2D, .other: nil
        }
    }

    /// Longest-to-shortest side bounds in centimetres.
    var maxSidesCm: [Double]? {
        switch self {
        case .courier: [80, 50, 50]
        case .express: [100, 60, 50]
        case .cargo: [170, 96, 90]
        case .sddLong, .superexpressD2D, .other: nil
        }
    }

    /// The class's bounds, stated as the helper text — constraints replace hints
    /// (DesignSystem → "Field taxonomy").
    var limits: [String] {
        var lines: [String] = []
        if let maxWeightKg {
            lines.append(String(localized: "Up to \(maxWeightKg.formatted(.number)) kg"))
        }
        if let maxSidesCm {
            lines.append(Dimensions.centimeters(maxSidesCm))
        }
        if self == .cargo {
            lines.append(String(localized: "Loaders — one or two"))
        }
        return lines
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

    /// «by 11:45» — the delivery end, the card's second line. A window ending on
    /// another day names it («by Oct 5, 11:45») rather than reading as today.
    var deliveryByText: String? {
        deliveryInterval.map { String(localized: "by \(Self.windowEnd($0.upperBound))") }
    }

    /// «pickup by 11:09» — the same words for the collection end, on the selected card.
    var pickupByText: String? {
        pickupInterval.map { String(localized: "pickup by \(Self.windowEnd($0.upperBound))") }
    }

    /// The payload stops being spendable at `offer_ttl`; absent means the wire said
    /// nothing, so nothing expires.
    func isExpired(at now: Date = .now) -> Bool {
        validUntil.map { $0 <= now } ?? false
    }

    /// The window's tail in the reader's calendar — hour:minute same-day, day and
    /// month added otherwise. Separated from the wording so tests pin the calendar.
    static func windowEnd(_ end: Date, calendar: Calendar = .current) -> String {
        let style: Date.FormatStyle = calendar.isDateInToday(end)
            ? .dateTime.hour().minute()
            : .dateTime.day().month(.abbreviated).hour().minute()
        return end.formatted(style)
    }
}

/// The strip's ordering — what the header menu offers. The raw value persists under
/// `tariffSort` in `@AppStorage`.
nonisolated enum OfferSort: String, CaseIterable, Codable, Sendable {
    case fastest
    case cheapest

    var words: String {
        switch self {
        case .fastest: String(localized: "Fastest")
        case .cheapest: String(localized: "Cheapest")
        }
    }
}

nonisolated extension Array where Element == Offer {
    /// Same-class offers differ only by their windows (the drive's wire log: four
    /// couriers, four delivery ends), so the order the strip draws is the answer.
    /// A windowless offer sorts last — it cannot promise a time.
    func sorted(by sort: OfferSort) -> [Offer] {
        switch sort {
        case .fastest:
            sorted { lhs, rhs in
                switch (lhs.deliveryInterval?.upperBound, rhs.deliveryInterval?.upperBound) {
                case (let left?, let right?):
                    left == right ? lhs.price < rhs.price : left < right
                case (nil, _?): false
                case (_?, nil): true
                case (nil, nil): lhs.price < rhs.price
                }
            }
        case .cheapest:
            sorted { lhs, rhs in
                lhs.price == rhs.price
                    ? (lhs.deliveryInterval?.upperBound ?? .distantFuture)
                        < (rhs.deliveryInterval?.upperBound ?? .distantFuture)
                    : lhs.price < rhs.price
            }
        }
    }
}

#if DEBUG
extension Offer {
    /// The `--uitest-offers` strip — what the provider might answer for a short
    /// city run, priced like the #Preview fixture plus a superexpress card, which
    /// renders by its wire name until the tariff lands in `TariffClass`. Payloads
    /// are opaque stand-ins; nothing spends them, the same way no fixture launch
    /// could place the order anyway.
    static var listingStrip: [Offer] {
        let now = Date.now
        return [
            Offer(tariff: .courier, price: 749, currency: "RUB",
                  pickupInterval: now + 15 * 60 ... now + 30 * 60,
                  deliveryInterval: now + 50 * 60 ... now + 80 * 60,
                  variant: "express", validUntil: now + 10 * 60, surgeRatio: 1.1,
                  payload: "uitest-courier"),
            Offer(tariff: .express, price: 1190, currency: "RUB",
                  pickupInterval: now + 10 * 60 ... now + 25 * 60,
                  deliveryInterval: now + 40 * 60 ... now + 70 * 60,
                  variant: "express", validUntil: now + 10 * 60, surgeRatio: 1.0,
                  payload: "uitest-express"),
            Offer(tariff: .other("superexpress_d2d"), price: 1890, currency: "RUB",
                  pickupInterval: now + 5 * 60 ... now + 15 * 60,
                  deliveryInterval: now + 25 * 60 ... now + 45 * 60,
                  variant: "2_hours_delivery", validUntil: now + 10 * 60, surgeRatio: 1.2,
                  payload: "uitest-faster"),
            Offer(tariff: .cargo, price: 3400, currency: "RUB",
                  pickupInterval: now + 30 * 60 ... now + 60 * 60,
                  deliveryInterval: now + 90 * 60 ... now + 150 * 60,
                  variant: "cargo", validUntil: now + 10 * 60, surgeRatio: 1.0,
                  payload: "uitest-cargo"),
        ]
    }
}
#endif

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

/// A documented refusal with the provider's own `{code, message}` body inside.
/// The generated `.ok` accessor throws away that body — «missing required field
/// 'items'» became a nameless accessor error (review, PR #31) — so callers switch
/// on the response and hand the decoded message here instead.
nonisolated struct ProviderRefusal: LocalizedError, Hashable {
    let message: String?
    /// The HTTP status, set on every documented case; `isDefinitive` reads it.
    var status: Int?

    /// The request was validated and declined — nothing executed. 5xx,
    /// throttles and unknown statuses prove nothing about the payload: a 429
    /// is rate-limiting, not a refusal of the request's content, so it is not
    /// definitive either (review, PR #107).
    var isDefinitive: Bool {
        status.map { (400..<500).contains($0) && $0 != 429 } ?? false
    }

    var errorDescription: String? {
        if let message, !message.isEmpty { return message }
        if let status { return String(localized: "The provider answered \(status).") }
        return String(localized: "The provider refused the request.")
    }
}

/// The chosen class has no spelling in the wire enum this build carries. Thrown
/// before anything is sent, so nothing was created and nothing was charged; the
/// create never swaps in another class instead.
nonisolated struct UnsendableTariff: LocalizedError, Hashable {
    let tariff: TariffClass

    var errorDescription: String? {
        String(localized: "This version of the app can't order «\(tariff.words)» yet. Choose another class, or update the app.")
    }
}


