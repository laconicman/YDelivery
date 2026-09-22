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
        // switch (review, PR #26; verified against upstream source, DeepWiki
        // 2026-09-14: the setter posts and never sends the control event). Two
        // upstream boundaries, named: `setTextUnformatted` mutates with *neither*
        // signal (nothing here calls it; a future caller would go unobserved), and
        // a country picked while the field is not first responder clears the text
        // upstream — the binding mirrors that clear faithfully rather than fighting it.
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

#Preview {
    @Previewable @State var phone = "+7 912 345-67-89"
    Form {
        PhoneField(text: $phone)
    }
}
