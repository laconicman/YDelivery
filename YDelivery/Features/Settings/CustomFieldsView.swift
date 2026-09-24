import SwiftUI
import YDeliveryKit

/// «Ваши поля» — the sender's field schema (board `4b`). One list, own screen:
/// fields are organization-level settings, not per-order chores. Every draft
/// draws them pre-typed; completed history is searchable by their values.
struct CustomFieldsView: View {
    @Environment(StoreController.self) private var store
    /// The field being edited — item-sheet identity is the definition's own id;
    /// a fresh draft carries a fresh one.
    @State private var editing: CustomFieldDefinition?
    /// A save refusal rendered where it happened — the store refuses a second
    /// claimant on a carrier slot, and the sheet says so rather than dropping it.
    @State private var saveError: String?

    var body: some View {
        List {
            if let fieldsError = store.fieldsError {
                Text(fieldsError.localizedDescription)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.fieldDefinitions) { field in
                Button {
                    editing = field
                } label: {
                    LabeledContent {
                        Text(field.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(field.name)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets {
                    Task { await store.deleteField(store.fieldDefinitions[index].id) }
                }
            }
            .onMove { offsets, destination in
                var fields = store.fieldDefinitions
                fields.move(fromOffsets: offsets, toOffset: destination)
                for (position, var field) in fields.enumerated() {
                    field.position = position
                    Task { try? await store.saveField(field) }
                }
            }

            if store.fieldDefinitions.isEmpty && store.fieldsError == nil {
                Text("No fields yet — add «Заказ» or «Накладная» and every draft will ask for them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Your fields")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = CustomFieldDefinition(
                        name: "", position: store.fieldDefinitions.count)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing, onDismiss: { saveError = nil }) { field in
            FieldEditor(
                field: field,
                takenCarriers: Set(store.fieldDefinitions.compactMap {
                    $0.id == field.id ? nil : $0.carrier
                }.filter { $0 != .none }),
                save: { edited in
                    do {
                        try await store.saveField(edited)
                        editing = nil
                    } catch {
                        saveError = error.localizedDescription
                    }
                },
                saveError: saveError
            )
        }
    }
}

private nonisolated extension CustomFieldDefinition {
    /// The row's second line — kind plus whichever flags are on. Compact, so the
    /// list reads like the schema it is.
    var subtitle: String {
        var parts: [String] = [kind == .text
            ? String(localized: "Text") : String(localized: "Choice")]
        if !isOptional { parts.append(String(localized: "required")) }
        if !isShownByDefault { parts.append(String(localized: "behind Add field")) }
        if carrier != .none { parts.append(carrier.title) }
        return parts.joined(separator: " · ")
    }
}

nonisolated extension CustomFieldDefinition.Carrier {
    /// The carrier named for the settings picker — the role, not the wire key.
    var title: String {
        switch self {
        case .none: String(localized: "App only")
        case .claimDocument: String(localized: "Claim document")
        case .orderNumber: String(localized: "Order number")
        case .itemTag: String(localized: "Item tag")
        }
    }
}

/// One definition's editor — a sheet because a field is a thing with several
/// facets (name, type, options, flags, carrier), not a row tweak.
private struct FieldEditor: View {
    let takenCarriers: Set<CustomFieldDefinition.Carrier>
    let save: (CustomFieldDefinition) async -> Void
    let saveError: String?

    @State private var field: CustomFieldDefinition
    /// The choice list edited as one newline-joined string — the cheapest honest
    /// shape for a handful of options.
    @State private var choicesText: String
    @Environment(\.dismiss) private var dismiss

    init(field: CustomFieldDefinition,
         takenCarriers: Set<CustomFieldDefinition.Carrier>,
         save: @escaping (CustomFieldDefinition) async -> Void,
         saveError: String?) {
        _field = State(initialValue: field)
        _choicesText = State(initialValue: field.choices.joined(separator: "\n"))
        self.takenCarriers = takenCarriers
        self.save = save
        self.saveError = saveError
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name — «Заказ», «Платёж», «Накладная»", text: $field.name)
                }

                Section {
                    Picker("Type", selection: $field.kind) {
                        Text("Text").tag(CustomFieldDefinition.Kind.text)
                        Text("Choice").tag(CustomFieldDefinition.Kind.choice)
                    }
                    if field.kind == .choice {
                        TextField("One option per line", text: $choicesText, axis: .vertical)
                    }
                }

                Section {
                    Toggle("Optional", isOn: $field.isOptional)
                    Toggle("Shown by default", isOn: $field.isShownByDefault)
                        .disabled(!field.isOptional)
                } footer: {
                    if !field.isOptional {
                        // The invariant, said where it's enforced: a required
                        // field the sender cannot see is a trap — the order would
                        // block on a value nothing asked for.
                        Text("Required fields always show by default — a hidden required field would block ordering on a value nobody sees.")
                    } else {
                        Text("Fields not shown by default wait behind «Add field» in the draft.")
                    }
                }

                Section {
                    Picker("Rides to the courier as", selection: $field.carrier) {
                        ForEach(CustomFieldDefinition.Carrier.allCases, id: \.self) { carrier in
                            // One claimant per slot — a taken carrier says so in
                            // the list rather than failing at Save (the store
                            // refuses too, as the last line).
                            Text(takenCarriers.contains(carrier)
                                 ? "\(carrier.title) — taken" : carrier.title)
                                .tag(carrier)
                        }
                    }
                } footer: {
                    switch field.carrier {
                    case .none:
                        Text("Kept on the order — searchable history, nothing rides to the provider.")
                    case .claimDocument:
                        Text("Sent once per claim — the accompanying document on the paperwork.")
                    case .orderNumber:
                        Text("Sent on every destination — your own order number, and the provider-side search key.")
                    case .itemTag:
                        Text("Sent on every item — the short external tag per parcel.")
                    }
                }

                if let saveError {
                    Section {
                        Text(saveError).foregroundStyle(.red)
                    }
                }
            }
            // The editor holds the same invariant the store normalizes: unchecking
            // Optional forces Shown on, so a hidden-required trap can't be typed.
            .onChange(of: field.isOptional) {
                if !field.isOptional { field.isShownByDefault = true }
            }
            .navigationTitle("Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        field.choices = choicesText
                            .split(separator: "\n")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        Task { await save(field) }
                    }
                    .disabled(field.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview("Field editor") {
    FieldEditor(
        field: CustomFieldDefinition(name: "Заказ", isOptional: false,
                                     carrier: .orderNumber),
        takenCarriers: [.claimDocument],
        save: { _ in },
        saveError: nil
    )
}

#Preview {
    let store = StoreController(database: nil)
    NavigationStack {
        CustomFieldsView()
            .environment(store)
    }
}
