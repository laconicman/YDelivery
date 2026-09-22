import Foundation

// `nonisolated` is load-bearing, not decoration: an extension does not inherit it from the
// type it extends, so under this target's MainActor default isolation an unannotated
// extension would pin pure formatting to the main actor — and the failure is a runtime
// SIGTRAP from a nonisolated caller, not a compile error (REVIEW.md; MapLink, 2026-08-30).

nonisolated extension PickedPlace {
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

    /// Whether the address line names no building — a bare street or a landmark is
    /// unusual enough for a courier that the point rows warn about it (author,
    /// 2026-09-18). The wire carries the house number inside `fullname`, never a
    /// field of its own, so the digit heuristic is all the string offers; a bare
    /// pin (no address) is honest by itself and earns no warning.
    var lacksBuilding: Bool {
        !address.isEmpty && address.rangeOfCharacter(from: .decimalDigits) == nil
    }

    private func formatted(_ degrees: Double) -> String {
        degrees.formatted(
            .number.precision(.fractionLength(5)).locale(Locale(identifier: "en_US_POSIX"))
        )
    }
}
