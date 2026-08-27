import Foundation

extension PickedPlace {
    /// What a row or a marker calls this place when the user has not named it: the address
    /// when present, otherwise the coordinates to five decimals (≈1 m) — honest about being
    /// a bare pin, and precise enough to recognize on a map. A confirmed place must never
    /// render blank or masquerade as unchosen.
    ///
    /// Coordinates format with a fixed POSIX locale: under a comma-decimal locale (Russian
    /// included) the decimal mark would collide with the pair separator —
    /// `55,75580, 37,61730` — and the convention for raw coordinates is the dot anyway.
    var displayAddress: String {
        address.isEmpty ? "\(formatted(latitude)), \(formatted(longitude))" : address
    }

    private func formatted(_ degrees: Double) -> String {
        degrees.formatted(
            .number.precision(.fractionLength(5)).locale(Locale(identifier: "en_US_POSIX"))
        )
    }
}
