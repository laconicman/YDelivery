import PhoneNumberKit

/// One shared parser: creating `PhoneNumberUtility` loads the metadata, so it is paid
/// for once, not per keystroke. `nonisolated` — parsing is pure and reusable, and the
/// target's MainActor default would otherwise pin it (review, PR #26; the same rule
/// REVIEW.md carries for model extensions).
///
/// Lives with the model, not the field: `Contact.storable` reads it, and a model
/// type depending on a feature file inverts the layer direction (review, PR #30).
nonisolated enum PhoneFormat {
    /// `nonisolated(unsafe)`: upstream's 5.0 added `Sendable` to its value types but
    /// not (yet) to `PhoneNumberUtility`, which after its init-time metadata load is
    /// used read-only here — shared by the fields' formatting and this parser. The
    /// marker is the boundary to revisit when upstream conforms, not a suppression
    /// to copy (review, PR #26).
    nonisolated(unsafe) static let utility = PhoneNumberUtility()

    /// The wire form of a number the courier can actually dial — E.164, no spaces to
    /// mis-copy — or `nil` while the digits do not amount to one.
    static func dialable(_ raw: String) -> String? {
        guard let parsed = try? utility.parse(raw) else { return nil }
        return utility.format(parsed, toType: .e164)
    }
}
