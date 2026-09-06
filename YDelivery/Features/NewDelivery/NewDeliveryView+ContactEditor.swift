import SwiftUI

extension NewDeliveryView {
    /// The collapsed contact row, expanded: who stands at this point's door. Three typed
    /// fields — the extension is its own field, never folded into the number
    /// (DesignSystem → "Field taxonomy"). A sender is always copying from somewhere, so
    /// every field states its content type for autofill.
    ///
    /// Seeding `@State` from the initializer is deliberate: a sheet is recreated per
    /// presentation, so "first value wins" is exactly the wanted semantics for editing.
    struct ContactEditor: View {
        let title: LocalizedStringKey
        let save: (Contact) -> Void

        @State private var contact: Contact
        @Environment(\.dismiss) private var dismiss

        init(title: LocalizedStringKey, contact: Contact, save: @escaping (Contact) -> Void) {
            self.title = title
            self.save = save
            _contact = State(initialValue: contact)
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        // Explicit components, concatenated only by the name formatter
                        // (author's standing preference) — and each field autofills from
                        // its own content type.
                        TextField("Given name", text: $contact.givenName)
                            .textContentType(.givenName)
                        TextField("Family name", text: $contact.familyName)
                            .textContentType(.familyName)
                        TextField("Phone", text: $contact.phone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                        // No `textContentType`: UIKit has no content type for a dial
                        // extension — the number pad is all the system can offer here.
                        TextField("Extension", text: $contact.phoneExtension)
                            .keyboardType(.numberPad)
                    } footer: {
                        Text("The courier calls this number on arrival. Clear the fields to remove the contact.")
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            save(contact)
                            dismiss()
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

#Preview("New contact") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.ContactEditor(
            title: "Who hands over",
            contact: Contact(),
            save: { _ in }
        )
    }
}

#Preview("Editing, extension included") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.ContactEditor(
            title: "Who receives",
            contact: Contact(givenName: "Менеджер склада", phone: "+7 495 123-45-67", phoneExtension: "123"),
            save: { _ in }
        )
    }
}
