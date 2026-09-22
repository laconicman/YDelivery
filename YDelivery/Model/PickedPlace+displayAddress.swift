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

    /// The `fullname` convention the geocoder composes, modeled rather than
    /// pattern-matched: every number-shaped word (`52`, `15А`, `49с1`, `3/1`) takes
    /// its role from the label nearest before it — «дом»/«строение»/«корпус» make
    /// it the building, «подъезд»/«этаж»/«квартира» make it the way in, and a bare
    /// number counts only as a component's last word, so «улица 8 Марта»'s 8 is
    /// nobody's house while «вход со двора дом 10» still names one (review, PR #30,
    /// three times over). A pure run longer than five digits is a postal code.
    /// The imprecision that remains is priced into the warning's wording —
    /// advisory, never a gate.
    private var namesAHouseNumber: Bool {
        address.split(separator: ",").contains { component in
            let words = component.split(separator: " ")
            return words.indices.contains { index in
                guard Self.isHouseToken(words[index]) else { return false }
                guard let governing = words[..<index]
                    .map(Self.labelForm)
                    .last(where: Self.isLabel)
                else { return index == words.count - 1 }
                return Self.buildingLabels.contains(governing)
            }
        }
    }

    /// Labels that make a number describe the way in, not the building — «этаж 3»,
    /// «квартира 5», «офис 214» can ride a building-less address just as well as a
    /// numbered one.
    private static let detailLabels: Set<String> = [
        "подъезд", "парадная", "этаж", "эт", "эт.", "квартира", "кв", "кв.",
        "офис", "домофон", "лифт", "секция", "помещение", "пом", "пом.",
        "комната", "комн", "комн.", "кабинет", "каб", "каб.",
        "вход", "въезд", "налево", "направо",
    ]

    /// Labels that turn a number into the building itself — they qualify a house,
    /// not a door, and they overrule an earlier detail word (review, PR #30).
    /// Single-letter forms exist only dotted: «к.» is корпус while bare «к» is the
    /// preposition *to*, and stripping the dot is how «вход к шлагбауму 2» once
    /// named a barrier a building (review, same round).
    private static let buildingLabels: Set<String> = [
        "дом", "д.", "д", "строение", "стр.", "стр", "корпус", "корп.", "корп", "к.",
        "владение", "вл.", "вл", "литера", "лит.", "лит", "здание", "зд.", "зд",
    ]

    private static func isLabel(_ word: String) -> Bool {
        detailLabels.contains(word) || buildingLabels.contains(word)
    }

    /// A number-shaped word: digits, an optional fraction, an optional letter with
    /// its own trailing digits — `52`, `15А`, `49с1`, `3/1`. Edge punctuation is
    /// irrelevant to a number, so it is stripped whole («10.» at a line's end).
    private static func isHouseToken(_ word: Substring) -> Bool {
        word.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .wholeMatch(of: /\d{1,5}([\/]\d{1,3})?([A-Za-zА-Яа-я]\d{0,3})?/) != nil
    }

    /// Edge punctuation stripped *except* the dot — the dot is what makes «к.» an
    /// abbreviation rather than a preposition, so label matching keeps it.
    private static func labelForm(_ word: Substring) -> String {
        word.lowercased().trimmingCharacters(
            in: CharacterSet.punctuationCharacters.subtracting(.init(charactersIn: "."))
        )
    }

    private func formatted(_ degrees: Double) -> String {
        degrees.formatted(
            .number.precision(.fractionLength(5)).locale(Locale(identifier: "en_US_POSIX"))
        )
    }
}
