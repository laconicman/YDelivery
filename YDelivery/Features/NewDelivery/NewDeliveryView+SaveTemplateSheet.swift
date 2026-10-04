import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension NewDeliveryView {
    /// Keeping a parcel as a library template: a name for the chip — the goods
    /// are already described in the form or the row this sheet was opened from;
    /// it only asks what to call the template (seeded with the item's name).
    ///
    /// The sheet owns the write rather than firing it at dismissal — same
    /// discipline as `PointPickerView.SavePlaceSheet` — so a store that cannot
    /// keep the template says so here, with the name still typed and Save still
    /// available.
    struct SaveTemplateSheet: View {
        /// The goods the template remembers — the footer, so the sender names
        /// the entry against what it actually holds.
        let item: ParcelItem
        let save: (String) async throws -> Void

        @State private var name: String
        @State private var isSaving = false
        @State private var failure: String?
        @Environment(\.dismiss) private var dismiss

        init(item: ParcelItem, save: @escaping (String) async throws -> Void) {
            self.item = item
            self.save = save
            _name = State(initialValue: item.name)
        }

        /// One definition of the name — the `SavePlaceSheet` rule: what
        /// validation accepts and what gets stored cannot disagree.
        private var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("Name — “Комплект учебников”", text: $name)
                    } footer: {
                        Text(item.summary)
                    }

                    if let failure {
                        Section {
                            Notice(.error, failure)
                        } footer: {
                            Text("The template was not kept. Try again, or close and carry on — the item is still in the draft.")
                        }
                    }
                }
                .navigationTitle("Save as a template")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("Save", action: attemptSave)
                                .disabled(trimmedName.isEmpty)
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }

        /// Dismissal is the *success* path only — owned by the sheet, which stays
        /// presented for its whole life.
        private func attemptSave() {
            isSaving = true
            failure = nil
            Task {
                do {
                    try await save(trimmedName)
                    dismiss()
                } catch {
                    failure = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

#Preview("Naming the template") {
    Color.clear.sheet(isPresented: .constant(true)) {
        var item = ParcelItem()
        item.name = "Комплект учебников"
        item.quantity = 5
        item.weightKg = 12
        item.size = ParcelItem.Size(lengthCm: 30, widthCm: 21, heightCm: 8)
        return NewDeliveryView.SaveTemplateSheet(item: item, save: { _ in })
    }
}

#Preview("The store could not keep it") {
    Color.clear.sheet(isPresented: .constant(true)) {
        var item = ParcelItem()
        item.name = "Учебники"
        item.quantity = 5
        return NewDeliveryView.SaveTemplateSheet(
            item: item, save: { _ in throw StoreController.StoreUnavailable() })
    }
}
