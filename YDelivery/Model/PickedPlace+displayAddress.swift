import Foundation

extension PickedPlace {
    /// What a row or a marker calls this place when the user has not named it: the address
    /// when present, otherwise the coordinates to five decimals (≈1 m) — honest about being
    /// a bare pin, and precise enough to recognize on a map. A confirmed place must never
    /// render blank or masquerade as unchosen.
    var displayAddress: String {
        address.isEmpty
            ? "\(latitude.formatted(.number.precision(.fractionLength(5)))), \(longitude.formatted(.number.precision(.fractionLength(5))))"
            : address
    }
}
