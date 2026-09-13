import PhoneNumberKit
import PhoneNumberKitUI
import SwiftUI

/// The phone box, specialized: as-you-type formatting, the country behind a flag, and
/// an example placeholder — the field users know worldwide, because its metadata *is*
/// Google's libphonenumber (author, 2026-09-09). Entry UX only: what the number is
/// worth is `dialable`'s question, asked beside the field, never inside it.
///
/// Our own representable rather than the package's: the stock one constructs the field
/// with `PhoneNumberTextField()`, whose default init makes a private
/// `PhoneNumberUtility` — one metadata load *per field*. This one hands every field the
/// shared `PhoneFormat.utility`, so entry and validation also agree on one parser
/// (review, PR #25).
struct PhoneField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> PhoneNumberTextField {
        let field = PhoneNumberTextField(frame: .zero, utility: PhoneFormat.utility)
        field.withFlag = true
        field.withExamplePlaceholder = true
        field.withDefaultPickerUI = true
        // Autofill offers the sender's own number — they are always copying
        // from somewhere (DesignSystem → "Field taxonomy").
        field.textContentType = .telephoneNumber
        field.setContentHuggingPriority(.defaultHigh, for: .vertical)
        // Two channels, deliberately: keyboard edits arrive as `.editingChanged`, but
        // the flag picker sets `text` programmatically, and that setter posts only
        // the notification — one channel alone saves a stale number after a country
        // switch (review, PR #26).
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange),
            for: .editingChanged
        )
        context.coordinator.observeProgrammaticChanges(of: field)
        return field
    }

    func updateUIView(_ field: PhoneNumberTextField, context: Context) {
        context.coordinator.text = $text
        if field.text != text { field.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject {
        var text: Binding<String>
        /// `nonisolated(unsafe)` so the nonisolated deinit may hand it back;
        /// `removeObserver` is documented thread-safe.
        private nonisolated(unsafe) var programmaticChanges: (any NSObjectProtocol)?

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func textDidChange(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }

        func observeProgrammaticChanges(of field: PhoneNumberTextField) {
            programmaticChanges = NotificationCenter.default.addObserver(
                forName: UITextField.textDidChangeNotification,
                object: field,
                queue: .main
            ) { [weak self] note in
                // Delivered on the main queue; only the String crosses into the
                // isolation assumption — nothing non-Sendable is captured or sent.
                let text = (note.object as? UITextField)?.text ?? ""
                MainActor.assumeIsolated {
                    guard let self, self.text.wrappedValue != text else { return }
                    self.text.wrappedValue = text
                }
            }
        }

        deinit {
            if let programmaticChanges {
                NotificationCenter.default.removeObserver(programmaticChanges)
            }
        }
    }
}

/// One shared parser: creating `PhoneNumberUtility` loads the metadata, so it is paid
/// for once, not per keystroke. `nonisolated` — parsing is pure and reusable, and the
/// target's MainActor default would otherwise pin it (review, PR #26; the same rule
/// REVIEW.md carries for model extensions).
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

nonisolated extension Contact {
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
