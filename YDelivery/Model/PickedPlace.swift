import YDeliveryKit

/// A route point the user has chosen: coordinates plus the human-readable address that will
/// eventually feed a delivery request.
///
/// Plain doubles rather than `CLLocationCoordinate2D` keep the model layer free of framework
/// imports and give `Hashable` for free — views convert at the edge. The app-model side of
/// CLAUDE.md rule 1: features trade in types like this, never in generated schemas.
nonisolated struct PickedPlace: Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    /// Editable before submission: reverse geocoding proposes it, the user corrects it —
    /// the API's `fullname` is what the courier ultimately reads.
    var address: String

    /// How to get to the door once at the building — filled on the picker's refine
    /// stage, carried through the draft to the wire.
    var parts: AddressParts?
}
