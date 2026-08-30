import Foundation

/// Who stands at the door of a route point: the name the courier asks for and the phone
/// they call. The extension is its own field, never folded into the number — no free-text
/// number ever means two things (DesignSystem → "Field taxonomy", rule 3).
nonisolated struct Contact: Hashable, Sendable {
    var name = ""
    var phone = ""
    var phoneExtension = ""

    /// Nothing worth keeping: an all-empty contact is "no contact", not a blank card.
    var isEmpty: Bool {
        name.isEmpty && phone.isEmpty && phoneExtension.isEmpty
    }
}

extension Contact {
    /// The collapsed row's one line: «Иван Петров · +7 912 345-67-89, ext. 12». Display
    /// formatting lives here, not in a view body (R5).
    var summary: String {
        let phonePart = phoneExtension.isEmpty
            ? phone
            : phone.isEmpty ? "" : String(localized: "\(phone), ext. \(phoneExtension)")
        return [name, phonePart].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
