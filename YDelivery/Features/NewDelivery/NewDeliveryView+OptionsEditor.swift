import SwiftUI

extension NewDeliveryView {
    /// Options, timing, and the courier's note (board `3d`): every bounded control
    /// states its bound where a hint would go, and unavailable options render disabled
    /// with their reason rather than vanishing — the vocabulary stays learnable
    /// (DesignSystem → field rules; §4 interdependencies, enforced here, never
    /// discovered via API errors).
    struct OptionsEditor: View {
        let selectedTariff: TariffClass?
        let save: (DeliveryOptions) -> Void

        @State private var options: DeliveryOptions
        @State private var isScheduled: Bool
        @Environment(\.dismiss) private var dismiss

        init(options: DeliveryOptions, selectedTariff: TariffClass?, save: @escaping (DeliveryOptions) -> Void) {
            self.selectedTariff = selectedTariff
            self.save = save
            _options = State(initialValue: options)
            _isScheduled = State(initialValue: options.due != nil)
        }

        private var thermobagAllowed: Bool { selectedTariff == .courier }
        private var loadersAllowed: Bool { selectedTariff == .cargo }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        Toggle("Pro courier", isOn: $options.proCourier)
                        Toggle("To the door", isOn: $options.toDoor)
                        Toggle("Thermal bag", isOn: $options.thermobag)
                            .disabled(!thermobagAllowed)
                    } footer: {
                        // The reason, not a hint — and only when it declines.
                        if !thermobagAllowed {
                            Text("A thermal bag rides only with the courier class.")
                        }
                    }

                    Section {
                        Stepper(
                            value: $options.loaders,
                            in: DeliveryOptions.loadersRange
                        ) {
                            LabeledContent("Loaders", value: options.loaders.formatted())
                        }
                        .disabled(!loadersAllowed)
                    } footer: {
                        Text(
                            loadersAllowed
                                ? "One or two — the cargo van's bound."
                                : "Loaders ride only in the cargo van — one or two there."
                        )
                    }

                    Section {
                        Toggle("Scheduled pickup", isOn: $isScheduled)
                        if isScheduled {
                            DatePicker(
                                "Courier arrives",
                                selection: dueBinding,
                                in: DeliveryOptions.dueWindow()
                            )
                        }
                    } footer: {
                        Text("From an hour ahead up to thirty days.")
                    }

                    Section("Note for the courier") {
                        TextField("How to find you, what to mind…", text: $options.comment, axis: .vertical)
                            .lineLimit(2...5)
                    }
                }
                .navigationTitle("Options")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            save(options)
                            dismiss()
                        }
                    }
                }
                .onChange(of: isScheduled) {
                    if !isScheduled { options.due = nil }
                }
            }
        }

        private var dueBinding: Binding<Date> {
            Binding(
                get: { options.due ?? DeliveryOptions.dueWindow().lowerBound },
                set: { options.due = $0 }
            )
        }
    }
}

#Preview("Courier selected — loaders decline with their reason") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.OptionsEditor(
            options: DeliveryOptions(),
            selectedTariff: .courier,
            save: { _ in }
        )
    }
}

#Preview("Cargo selected — loaders live, thermobag declines") {
    var options = DeliveryOptions()
    options.loaders = 2
    options.due = DeliveryOptions.dueWindow().lowerBound.addingTimeInterval(7200)
    return Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.OptionsEditor(
            options: options,
            selectedTariff: .cargo,
            save: { _ in }
        )
    }
}
