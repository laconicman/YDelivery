import SwiftUI
import YDeliveryKit

extension NewDeliveryView {
    /// One item, expanded to typed rows (board `3d`): units belong to the fields —
    /// kilograms and centimetres in the UI, metres only on the wire — currency is a
    /// picker, and the item's own route appears only when there are stops to choose.
    /// The fit line states the selected class's bound in place of a hint.
    ///
    /// Seeding `@State` from the initializer is deliberate: a sheet is recreated per
    /// presentation, so "first value wins" is the wanted editing semantics.
    struct ItemEditor: View {
        /// A stop an item can board or leave at, reduced to a menu line.
        struct Stop: Identifiable, Hashable {
            let id: UUID
            let label: String
        }

        let stops: [Stop]
        let selectedTariff: TariffClass?
        let save: (ParcelItem) -> Void

        @State private var item: ParcelItem
        @State private var hasSize: Bool
        @Environment(\.dismiss) private var dismiss

        init(
            item: ParcelItem,
            stops: [Stop],
            selectedTariff: TariffClass?,
            save: @escaping (ParcelItem) -> Void
        ) {
            self.stops = stops
            self.selectedTariff = selectedTariff
            self.save = save
            _item = State(initialValue: item)
            _hasSize = State(initialValue: item.size != nil)
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $item.name)
                        Stepper(value: $item.quantity, in: 1...99) {
                            LabeledContent("Quantity", value: item.quantity.formatted())
                        }
                        LabeledContent("Weight") {
                            // One explicit row: LabeledContent alone wraps the unit
                            // under the label once the field claims its width.
                            HStack(spacing: Layout.Spacing.tight) {
                                TextField("—", value: $item.weightKg, format: .number.precision(.fractionLength(0...2)))
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
                                Picker("Currency", selection: $item.currency) {
                                    // The wire's three (ISO 4217); a picker, not a text
                                    // field — no free-text number ever means two things.
                                    Text(verbatim: "₽ RUB").tag("RUB")
                                    Text(verbatim: "$ USD").tag("USD")
                                    Text(verbatim: "€ EUR").tag("EUR")
                                }
                                .labelsHidden()
                                .fixedSize()
                            }
                        }
                    }

                    Section {
                        Toggle("State the size", isOn: $hasSize)
                        if hasSize {
                            SizeFields(size: sizeBinding)
                        }
                    } footer: {
                        fitFooter
                    }

                    if stops.count > 2 {
                        Section("The item's own route") {
                            stopPicker("Pick up at", selection: $item.pickupPointID, fallback: stops.first)
                            stopPicker("Hand over at", selection: $item.dropoffPointID, fallback: stops.last)
                        }
                    }
                }
                .navigationTitle("Item")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            save(item)
                            dismiss()
                        }
                    }
                }
                .onChange(of: hasSize) {
                    if !hasSize { item.size = nil }
                }
            }
        }

        /// The bound, stated where a hint would go: what fits the selected class — or
        /// that it does not (DesignSystem → field rule 2).
        @ViewBuilder
        private var fitFooter: some View {
            if let tariff = selectedTariff, let sides = tariff.maxSidesCm {
                let bounds = Dimensions.centimeters(sides)
                if tariff.fits(item) {
                    Text("Fits \(tariff.words): up to \(bounds).")
                } else {
                    Text("Doesn't fit \(tariff.words) — its bound is \(bounds). Pick a larger class, or it may be refused at the door.")
                }
            }
        }

        private var sizeBinding: Binding<ParcelItem.Size> {
            Binding(
                get: { item.size ?? ParcelItem.Size(lengthCm: 0, widthCm: 0, heightCm: 0) },
                set: { item.size = $0 }
            )
        }

        private func stopPicker(
            _ title: LocalizedStringKey,
            selection: Binding<UUID?>,
            fallback: Stop?
        ) -> some View {
            Picker(title, selection: selection) {
                ForEach(stops) { stop in
                    Text(stop.label).tag(UUID?.some(stop.id))
                }
            }
            // `nil` reads as the route's ends — surfaced as the fallback's label.
            .overlay(alignment: .trailing) {
                if selection.wrappedValue == nil, let fallback {
                    Text(fallback.label)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

extension NewDeliveryView.ItemEditor {
    /// Length, width, height — three fields, one unit, stated once.
    struct SizeFields: View {
        @Binding var size: ParcelItem.Size

        var body: some View {
            HStack(spacing: Layout.Spacing.unit) {
                sizeField("Length", value: $size.lengthCm)
                sizeField("Width", value: $size.widthCm)
                sizeField("Height", value: $size.heightCm)
                Text("cm")
                    .foregroundStyle(.secondary)
            }
        }

        private func sizeField(_ prompt: LocalizedStringKey, value: Binding<Double>) -> some View {
            TextField(prompt, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .padding(.vertical, Layout.Spacing.chip)
                .padding(.horizontal, Layout.Spacing.unit)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Layout.Radius.field))
        }
    }
}

#Preview("New item") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.ItemEditor(
            item: ParcelItem(),
            stops: [],
            selectedTariff: .courier,
            save: { _ in }
        )
    }
}

#Preview("Doesn't fit the selected class") {
    var item = ParcelItem()
    item.name = "Комплект учебников"
    item.quantity = 5
    item.weightKg = 12
    item.size = ParcelItem.Size(lengthCm: 90, widthCm: 40, heightCm: 30)
    return Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.ItemEditor(
            item: item,
            stops: [
                .init(id: UUID(), label: "Невский проспект, 100"),
                .init(id: UUID(), label: "Арбат, 10"),
                .init(id: UUID(), label: "Каширское шоссе, 52"),
            ],
            selectedTariff: .courier,
            save: { _ in }
        )
    }
}
