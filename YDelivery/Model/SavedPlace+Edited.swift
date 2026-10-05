import YDeliveryKit

// `nonisolated` for the same reason as the sibling seam files: the project's
// MainActor default would otherwise pin this pure rewrite (REVIEW.md's
// extension-isolation rule).

nonisolated extension SavedPlace {
    /// The same place, re-described: a new name and kind, the door details and the
    /// person replaced whole — the coordinates, the address, the id and the pin
    /// kept. Empty parts and an empty contact become absence the way a fresh save
    /// stores them (`RoutePoint.init(_:contact:)`), and the phone lands in E.164
    /// when it parses (`Contact.storable`).
    func edited(name: String, kind: Kind, parts: AddressParts, contact: Contact) -> SavedPlace {
        var picked = PickedPlace(point)
        picked.parts = parts
        return SavedPlace(id: id, name: name, kind: kind, point: RoutePoint(picked, contact: contact), pinned: pinned)
    }
}
