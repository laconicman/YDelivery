import Foundation

/// One thing the courier carries — the rows of «What's inside» (board `3d`). Typed
/// fields with units owned by the field: centimetres and kilograms here, metres on the
/// wire, and the conversion happens only at the controller boundary.
nonisolated struct ParcelItem: Hashable, Sendable, Identifiable {
    let id: UUID
    var name = ""
    var quantity = 1
    var weightKg: Double?
    /// Declared value — what the insurance covers; the footer says so (board `3d`).
    var cost: Decimal?
    /// ISO 4217, from the wire's three: a picker, not a text field (handoff §9.5,
    /// author 2026-08-30).
    var currency = "RUB"
    var size: Size?
    /// Where this item boards and leaves, when the route has more than two stops.
    /// `nil` reads as the route's ends — the common case is everything from A to B
    /// (handoff §9.3).
    var pickupPointID: UUID?
    var dropoffPointID: UUID?

    init(id: UUID = UUID()) {
        self.id = id
    }

    /// Centimetres in the UI — a sender measures a box with a tape, not in metres.
    nonisolated struct Size: Hashable, Sendable {
        var lengthCm: Double
        var widthCm: Double
        var heightCm: Double
    }

    var isBlank: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty
            && weightKg == nil && cost == nil && size == nil
    }
}

nonisolated extension ParcelItem {
    /// The collapsed row's one line: «5 pcs · 2 kg · 25 × 18 × 15 cm · 2 500 ₽» —
    /// display formatting lives here, not in a view body (R5).
    var summary: String {
        var parts: [String] = [String(localized: "\(quantity) pcs")]
        if let weightKg {
            parts.append(
                Measurement<UnitMass>(value: weightKg, unit: .kilograms)
                    .formatted(.measurement(width: .abbreviated, usage: .asProvided))
            )
        }
        if let size {
            parts.append(size.summary)
        }
        if let cost {
            parts.append(cost.formatted(.currency(code: currency).precision(.fractionLength(0...2))))
        }
        return parts.joined(separator: " · ")
    }
}

nonisolated extension ParcelItem.Size {
    var summary: String {
        Dimensions.centimeters([lengthCm, widthCm, heightCm])
    }
}

nonisolated extension TariffClass {
    /// Whether the item's declared weight and box fit this class's bounds. Missing
    /// numbers pass — absence is "not stated", and the provider's courier judges at the
    /// door; the UI hint warns only about what is *known* not to fit. The box may be
    /// rotated, so sorted sides compare against sorted bounds.
    /// Whether this class can carry the whole parcel: every box through the door, and
    /// the load under the weight limit *together*. Judging rows one at a time called ten
    /// five-kilo boxes a courier job (review, PR #21).
    func fitsParcel(_ items: [ParcelItem]) -> Bool {
        weightWithin(items) && items.allSatisfy(fitsOneBox)
    }

    /// One row's own verdict, for the warning that row carries.
    func fits(_ item: ParcelItem) -> Bool {
        fitsOneBox(item) && weightWithin([item])
    }

    /// Sides only — genuinely per-row, since rotating one box says nothing about the next.
    func fitsOneBox(_ item: ParcelItem) -> Bool {
        guard let maxSideCm = maxSidesCm, let size = item.size else { return true }
        let sides = [size.lengthCm, size.widthCm, size.heightCm].sorted(by: >)
        for (side, bound) in zip(sides, maxSideCm) where side > bound {
            return false
        }
        return true
    }

    /// `quantity` multiplies the row's weight. The wire documents `weight` as the weight
    /// of the item beside a separate `quantity`, so per-unit is the reading — and it is a
    /// reading rather than a measurement; package TD-21 covers what is unverified here.
    private func weightWithin(_ items: [ParcelItem]) -> Bool {
        guard let maxWeightKg else { return true }
        let total = items.reduce(0.0) { $0 + ($1.weightKg ?? 0) * Double($1.quantity) }
        return total <= maxWeightKg
    }
}

nonisolated extension TariffClass {
    /// What this class has to say about a box: that it fits and up to what, or that it
    /// does not and what to do. Formatting on the formatted type rather than in a view
    /// body (R5) — the editor declares structure and renders this (review, PR #21).
    func fitWords(for item: ParcelItem) -> String? {
        guard let sides = maxSidesCm else { return nil }
        let bounds = Dimensions.centimeters(sides)
        return fits(item)
            ? String(localized: "Fits \(words): up to \(bounds).")
            : String(localized: "Doesn't fit \(words) — its bound is \(bounds). Pick a larger class, or it may be refused at the door.")
    }
}
