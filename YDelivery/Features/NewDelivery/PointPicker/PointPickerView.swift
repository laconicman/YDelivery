import SwiftUI

/// Root view of the point-picker sheet: search or tap the map, confirm one place.
///
/// Seeding `@State` from the initializer is deliberate here — a sheet is recreated per
/// presentation, so "first value wins" is exactly the wanted semantics for editing an
/// already-chosen place.
struct PointPickerView: View {
    let prompt: LocalizedStringKey
    let confirm: (PickedPlace) -> Void

    @State private var model: Model
    @Environment(\.dismiss) private var dismiss

    init(
        prompt: LocalizedStringKey,
        initialPlace: PickedPlace? = nil,
        confirm: @escaping (PickedPlace) -> Void
    ) {
        self.prompt = prompt
        self.confirm = confirm
        _model = State(initialValue: Model(initialPlace: initialPlace))
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Content(
                pin: model.pin,
                pinAddress: $model.pinAddress,
                isResolving: model.isResolving,
                errorText: model.lookupErrorText,
                onTap: { model.dropPin(latitude: $0, longitude: $1) },
                onVisibleRegionChange: { model.visibleRegion = $0 }
            )
            .navigationTitle(prompt)
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.streamSuggestions() }
            .searchable(text: $model.searchText, prompt: "Search address or place")
            .searchSuggestions {
                ForEach(model.suggestions) { suggestion in
                    Button {
                        model.select(suggestion)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(suggestion.title)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        if let place = model.pin {
                            confirm(place)
                            dismiss()
                        }
                    }
                    .disabled(model.pin == nil || model.isResolving)
                }
            }
        }
    }
}

#Preview("Fresh") {
    PointPickerView(prompt: "Where to pick up?", confirm: { _ in })
}

#Preview("Editing a chosen place") {
    PointPickerView(
        prompt: "Where to deliver?",
        initialPlace: PickedPlace(
            latitude: 55.646068,
            longitude: 37.668176,
            address: "Москва, Каширское шоссе, 52"
        ),
        confirm: { _ in }
    )
}
