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
    /// field of its own, so the string is all there is to read — conservatively:
    /// a comma component can be a house only by its last word, because digits
    /// mid-component name streets («улица 8 Марта»), postal codes lead, and the
    /// sender may append directions after the number («…, 10, вход со двора» —
    /// review, PR #30). A bare pin (no address) is honest by itself and earns no
    /// warning.
    var lacksBuilding: Bool {
        !address.isEmpty && !namesAHouseNumber
    }

    /// The `fullname` convention the geocoder composes: the house is a component
    /// whose last word is number-shaped — `52`, `15А`, `49с1`, `3/1`, «строение 2».
    /// A pure digit run longer than five is a postal code, not a door; trailing
    /// digits exist only behind a letter, else «123456» passes as «digits plus
    /// padding». And the number must not be a way-in detail — «подъезд 3» describes
    /// the entrance, not the building (review, PR #30, twice over). The
    /// imprecision that remains is priced into the warning's wording — advisory,
    /// never a gate.
    private var namesAHouseNumber: Bool {
        address.split(separator: ",").contains { component in
            let words = component.split(separator: " ")
            guard let last = words.last,
                  !words.dropLast().contains(where: { Self.detailLabels.contains(Self.normalized($0)) })
            else { return false }
            return last.wholeMatch(
                of: /\d{1,5}([\/]\d{1,3})?([A-Za-zА-Яа-я]\d{0,3})?/
            ) != nil
        }
    }

    /// Labels that make a number describe the way in, not the building — «этаж 3»,
    /// «квартира 5», «офис 214» can ride a building-less address just as well as a
    /// numbered one. Building labels («дом», «строение», «корпус») stay countable:
    /// they qualify a house, not a door.
    private static let detailLabels: Set<String> = [
        "подъезд", "парадная", "этаж", "эт", "квартира", "кв", "офис", "домофон",
        "лифт", "секция", "помещение", "пом", "комната", "комн", "кабинет", "каб",
        "вход", "въезд", "налево", "направо",
    ]

    private static func normalized(_ word: Substring) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    private func formatted(_ degrees: Double) -> String {
        degrees.formatted(
            .number.precision(.fractionLength(5)).locale(Locale(identifier: "en_US_POSIX"))
        )
    }
}
