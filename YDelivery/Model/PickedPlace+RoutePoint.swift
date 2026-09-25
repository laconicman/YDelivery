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
    /// Components first — they are the stored truth; rows written before components
    /// existed fall back to parsing their single string (Latin splits; Cyrillic stays
    /// whole in the given name, since Foundation's parser refuses it — still a name a
    /// courier can ask for).
    init?(at point: RoutePoint) {
        let contact: Contact = if point.contactGivenName != nil || point.contactFamilyName != nil {
            Contact(
                givenName: point.contactGivenName ?? "",
                familyName: point.contactFamilyName ?? "",
                phone: point.contactPhone ?? "",
                phoneExtension: point.contactPhoneExtension ?? ""
            )
        } else {
            Contact(
                fullName: point.contactName ?? "",
                phone: point.contactPhone ?? "",
                phoneExtension: point.contactPhoneExtension ?? ""
            )
        }
        guard let storable = contact.storable else { return nil }
        self = storable
    }
}

nonisolated extension RoutePoint {
    /// A chosen place — and who meets the courier — as the substrate remembers it.
    /// Empty strings become absence: the file stores what exists, not blank fields.
    /// `role` stays `nil` for places and recents — a route seat is a fact of the
    /// order, not of the door — and the draft names it where it knows it.
    init(_ place: PickedPlace, contact: Contact? = nil, role: Role? = nil) {
        let contact = contact?.storable
        self.init(
            latitude: place.latitude,
            longitude: place.longitude,
            address: place.address,
            addressParts: place.parts.flatMap { $0.isEmpty ? nil : $0 },
            // Both spellings: the formatted whole for the wire and legacy readers, the
            // components as the splittable truth.
            contactName: contact.flatMap { $0.fullName.isEmpty ? nil : $0.fullName },
            contactGivenName: contact.flatMap { $0.givenName.isEmpty ? nil : $0.givenName },
            contactFamilyName: contact.flatMap { $0.familyName.isEmpty ? nil : $0.familyName },
            contactPhone: contact.flatMap { $0.phone.isEmpty ? nil : $0.phone },
            contactPhoneExtension: contact.flatMap { $0.phoneExtension.isEmpty ? nil : $0.phoneExtension },
            role: role
        )
    }
}
