import YDeliveryKit

// The seam between the app's draft vocabulary and the substrate's remembered points —
// mapping lives in the model layer, in both directions, so neither side learns the
// other's spelling (CLAUDE.md rule 1's shape, applied to the store).

nonisolated extension PickedPlace {
    /// A remembered point, back as a pickable place.
    init(_ point: RoutePoint) {
        self.init(
            latitude: point.latitude,
            longitude: point.longitude,
            address: point.address,
            parts: point.addressParts
        )
    }
}

nonisolated extension Contact {
    /// The person a remembered point keeps at its door — `nil` when it kept nobody.
    init?(at point: RoutePoint) {
        let contact = Contact(
            name: point.contactName ?? "",
            phone: point.contactPhone ?? "",
            phoneExtension: point.contactPhoneExtension ?? ""
        )
        guard let storable = contact.storable else { return nil }
        self = storable
    }
}

nonisolated extension RoutePoint {
    /// A chosen place — and who meets the courier — as the substrate remembers it.
    /// Empty strings become absence: the file stores what exists, not blank fields.
    init(_ place: PickedPlace, contact: Contact? = nil) {
        let contact = contact?.storable
        self.init(
            latitude: place.latitude,
            longitude: place.longitude,
            address: place.address,
            addressParts: place.parts.flatMap { $0.isEmpty ? nil : $0 },
            contactName: contact.flatMap { $0.name.isEmpty ? nil : $0.name },
            contactPhone: contact.flatMap { $0.phone.isEmpty ? nil : $0.phone },
            contactPhoneExtension: contact.flatMap { $0.phoneExtension.isEmpty ? nil : $0.phoneExtension }
        )
    }
}
