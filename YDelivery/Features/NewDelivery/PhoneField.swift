import PhoneNumberKit
import PhoneNumberKitUI
import SwiftUI

/// The phone box, specialized: as-you-type formatting, the country behind a flag, and
/// an example placeholder — the field users know worldwide, because its metadata *is*
/// Google's libphonenumber (author, 2026-09-09). Entry UX only: what the number is
/// worth is `dialable`'s question, asked beside the field, never inside it.
struct PhoneField: View {
    @Binding var text: String

    var body: some View {
        PhoneNumberTextFieldRepresentable(text: $text) { field in
            field.withFlag = true
            field.withExamplePlaceholder = true
            field.withDefaultPickerUI = true
            // Autofill offers the sender's own number — they are always copying
            // from somewhere (DesignSystem → "Field taxonomy").
            field.textContentType = .telephoneNumber
        }
    }
}

/// One shared parser: creating `PhoneNumberUtility` loads the metadata, so it is paid
/// for once, not per keystroke.
enum PhoneFormat {
    static let utility = PhoneNumberUtility()

    /// The wire form of a number the courier can actually dial — E.164, no spaces to
    /// mis-copy — or `nil` while the digits do not amount to one.
    static func dialable(_ raw: String) -> String? {
        guard let parsed = try? utility.parse(raw) else { return nil }
        return utility.format(parsed, toType: .e164)
    }
}

extension Contact {
    /// The contact as the order should carry it: the phone in E.164 when it parses,
    /// verbatim when it does not — never silently dropped, the blockers say the rest.
    func withDialablePhone() -> Contact {
        var contact = self
        contact.phone = PhoneFormat.dialable(phone) ?? phone
        return contact
    }
}

#Preview {
    @Previewable @State var phone = "+7 912 345-67-89"
    Form {
        PhoneField(text: $phone)
    }
}
