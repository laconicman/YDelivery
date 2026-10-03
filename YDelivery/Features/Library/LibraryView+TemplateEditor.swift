import SwiftUI
import YDeliveryKit

extension LibraryView {
    /// The template's own sheet — the library's *name* (what the draft's chip
    /// and this list call it) plus one item's fields: the draft's `ItemEditor`
    /// minus the journey section and the tariff fit footer, because a template
    /// remembers no route (task doc: the editor writes exactly one item, and
    /// `items.count == 1` is a UI convention, not a schema invariant).
    struct ParcelTemplateEditor: View {
        /// The template being reshaped — `nil` authors a new one, so the «+»
        /// and the row's Edit are the same door.
        let template: ParcelTemplate?
        /// The async write — the root forwards `StoreController.save`.
        let save: (ParcelTemplate) async throws -> Void

        @State private var name: String
        @State private var item: ParcelItem
        @State private var hasSize: Bool
        /// A write that failed keeps the sheet up with its reason beside the
        /// fields — SavePlaceSheet's discipline.
        @State private var failure: String?
        @State private var isSaving = false
        @Environment(\.dismiss) private var dismiss

        init(template: ParcelTemplate? = nil,
             save: @escaping (ParcelTemplate) async throws -> Void) {
            self.template = template
            self.save = save
            _name = State(initialValue: template?.name ?? "")
            let firstItem = template?.items.first.map(ParcelItem.init(templateItem:)) ?? ParcelItem()
            _item = State(initialValue: firstItem)
            _hasSize = State(initialValue: firstItem.size != nil)
        }

        /// Save's bound — the library needs a name to say the entry with, and
        /// the stated fields follow the item editor's bounds: a stated size is
        /// three positive sides, a stated weight or value more than nothing.
        private var isStatable: Bool {
            if name.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            if hasSize && !sizeIsStated { return false }
            if let weight = item.weightKg, weight <= 0 { return false }
            if let cost = item.cost, cost <= 0 { return false }
            return item.quantity >= 1
        }

        private var sizeIsStated: Bool {
            guard let size = item.size else { return false }
            return size.lengthCm > 0 && size.widthCm > 0 && size.heightCm > 0
        }

        private var sizeBinding: Binding<ParcelItem.Size> {
            Binding(
                get: { item.size ?? ParcelItem.Size(lengthCm: 0, widthCm: 0, heightCm: 0) },
                set: { item.size = $0 }
            )
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $name)
                    } header: {
                        Text("Library entry")
                    } footer: {
                        Text("The name a draft's chips and this list call it — free to differ from what's inside.")
                    }
                    Section("What's inside") {
                        TextField("Name", text: $item.name)
                        Stepper("Quantity: \(item.quantity)", value: $item.quantity, in: 1...999)
                        LabeledContent("Weight") {
                            HStack(spacing: Layout.Spacing.tight) {
                                TextField("—", value: $item.weightKg, format: .number.precision(.fractionLength(0...1)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                Text("kg")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent("Value") {
                            HStack(spacing: Layout.Spacing.tight) {
                                TextField("—", value: $item.cost, format: .number.precision(.fractionLength(0...2)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                NewDeliveryView.ItemEditor.CurrencyPicker(currency: $item.currency)
                            }
                        }
                    }
                    Section {
                        Toggle("State the size", isOn: $hasSize)
                        if hasSize {
                            NewDeliveryView.ItemEditor.SizeFields(size: sizeBinding)
                        }
                    }
                    if let failure {
                        Section {
                            Notice(.error, failure)
                                .font(.footnote)
                        }
                    }
                }
                .navigationTitle(template == nil ? "New template" : "Edit template")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveAndDismiss() }
                            .disabled(!isStatable || isSaving)
                    }
                }
                .onChange(of: hasSize) { _, on in
                    // Same rule as the draft's editor (PR #21): the toggle writes
                    // the state it claims — on materialises a stated size, off
                    // clears it.
                    item.size = on
                        ? (item.size ?? ParcelItem.Size(lengthCm: 0, widthCm: 0, heightCm: 0))
                        : nil
                }
            }
        }

        /// The sheet owns its write: Save awaits the save, dismisses only on
        /// success, and a thrown error stays beside the fields with the sender's
        /// words intact.
        private func saveAndDismiss() {
            isSaving = true
            let template = ParcelTemplate(
                id: template?.id ?? UUID(),
                name: name.trimmingCharacters(in: .whitespaces),
                pinned: template?.pinned ?? false,
                items: [item.templateItem]
            )
            Task {
                do {
                    try await save(template)
                    dismiss()
                } catch {
                    failure = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

#Preview("New") {
    Color.clear.sheet(isPresented: .constant(true)) {
        LibraryView.ParcelTemplateEditor { _ in }
    }
}

#Preview("Editing") {
    let template = ParcelTemplate(
        name: "Keyboard", pinned: true,
        items: [ParcelTemplate.Item(name: "Mechanical keyboard", quantity: 1,
                                    weightKg: 0.9, cost: "4500", currency: "RUB",
                                    sizeLengthCm: 45, sizeWidthCm: 15, sizeHeightCm: 3)])
    Color.clear.sheet(isPresented: .constant(true)) {
        LibraryView.ParcelTemplateEditor(template: template) { _ in }
    }
}

#Preview("The store could not keep it") {
    Color.clear.sheet(isPresented: .constant(true)) {
        LibraryView.ParcelTemplateEditor { _ in
            throw StoreController.StoreUnavailable()
        }
    }
}
