import Foundation

/// Who stands at the door of a route point: the name the courier asks for and the phone
/// they call. The name is explicit components — given and family — concatenated only
/// through `PersonNameComponents`, never by hand-joined strings; the wire and the store
/// speak one full-name string, this type owns the split (author's standing preference,
/// 2026-09-06). The extension is its own field, never folded into the number — no
/// free-text number ever means two things (DesignSystem → "Field taxonomy", rule 3).
nonisolated struct Contact: Hashable, Sendable {
    var givenName = ""
    var familyName = ""
    var phone = ""
    var phoneExtension = ""

    /// Nothing worth keeping: an all-empty contact is "no contact", not a blank card.
    var isEmpty: Bool {
        givenName.isEmpty && familyName.isEmpty && phone.isEmpty && phoneExtension.isEmpty
    }

    /// What deserves storing: the phone normalized to its wire form (E.164 — the
    /// claim schema's pattern `^\+[1-9]\d{1,14}$` accepts nothing else, so a
    /// formatted number saved verbatim would fail at claim time, review, PR #29),
    /// and an extension without a phone is noise the courier cannot dial, so it
    /// does not survive saving — and what remains may then be nothing at all. One
    /// home for both rules, so a stored contact always renders a non-blank summary
    /// (review, PR #17).
    var storable: Contact? {
        var contact = withDialablePhone()
        if contact.phone.isEmpty {
            contact.phoneExtension = ""
        }
        return contact.isEmpty ? nil : contact
    }
}

nonisolated extension Contact {
    /// The one full-name string the store and the wire speak — assembled by the
    /// components formatter, so name order stays the locale's decision, not ours.
    var fullName: String {
        var components = PersonNameComponents()
        components.givenName = givenName.isEmpty ? nil : givenName
        components.familyName = familyName.isEmpty ? nil : familyName
        return components.formatted()
    }

    /// A stored or wire full name, split back into components — through the name
    /// formatter's parser, which is script-aware where the strict parse strategy is not
    /// (it refuses «Иван Петров»). What it cannot read at all stays whole in the given
    /// name — a courier can still ask for it.
    init(fullName: String, phone: String = "", phoneExtension: String = "") {
        let components = PersonNameComponentsFormatter().personNameComponents(from: fullName)
        self.init(
            givenName: components?.givenName ?? fullName,
            familyName: components?.familyName ?? "",
            phone: phone,
            phoneExtension: phoneExtension
        )
    }

    /// The contact as the order should carry it: the phone in E.164 when it parses,
    /// verbatim when it does not — never silently dropped, the blockers say the rest.
    /// A member of the type itself: `storable` depends on it, and a model type
    /// borrowing its normalization from a feature file would invert the layers
    /// (review, PR #30).
    func withDialablePhone() -> Contact {
        var contact = self
        contact.phone = PhoneFormat.dialable(phone) ?? phone
        return contact
    }

    /// The collapsed row's one line: «Иван Петров · +7 912 345-67-89, ext. 12». Display
    /// formatting lives here, not in a view body (R5). `nonisolated` explicitly: an
    /// extension does not inherit it from the type, and the project's default isolation
    /// would otherwise pin this pure formatting to the main actor.
    var summary: String {
        let phonePart = phoneExtension.isEmpty
            ? phone
            : phone.isEmpty ? "" : String(localized: "\(phone), ext. \(phoneExtension)")
        return [fullName, phonePart].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
