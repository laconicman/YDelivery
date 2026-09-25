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
        /// A stop an item can board or leave at — the full address, never reduced
        /// to a menu line an address cannot fit (author, 2026-09-14; Round 5,
        /// decision #51 rejected inline trailing-value pickers for exactly this).
        struct Stop: Identifiable, Hashable {
            let id: UUID
            let label: String
            let role: NewDeliveryView.Model.Role
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
                            // Two rows, each pushing a chooser of full-width stop
                            // rows — addresses wrap, never truncate (Round 5,
                            // decisions #51–#52; the inline menu pickers could not
                            // fit an address and showed two labels fighting for one
                            // trailing slot).
                            journeyRow(
                                "Picked up at",
                                stop: stops[effectivePickupIndex],
                                isRouteDefault: item.pickupPointID == nil
                            ) {
                                StopChooser(
                                    title: "Where it boards",
                                    stops: stops,
                                    selectedIndex: effectivePickupIndex,
                                    unavailable: { index in
                                        index >= effectiveHandoverIndex
                                            ? String(localized: "At or after the hand-over — a box can't board there.")
                                            : nil
                                    },
                                    choose: { index in
                                        // A default endpoint is a position: the route's
                                        // start stores as nil, so reordering keeps it
                                        // at the start (review, PR #21).
                                        item.pickupPointID = index == 0 ? nil : stops[index].id
                                    }
                                )
                            }
                            journeyRow(
                                "Handed over at",
                                stop: stops[effectiveHandoverIndex],
                                isRouteDefault: item.dropoffPointID == nil
                            ) {
                                StopChooser(
                                    title: "Where it leaves",
                                    stops: stops,
                                    selectedIndex: effectiveHandoverIndex,
                                    unavailable: { index in
                                        index <= effectivePickupIndex
                                            ? String(localized: "At or before the pickup — it hasn't boarded yet.")
                                            : nil
                                    },
                                    choose: { index in
                                        // The default stores as nil so it tracks
                                        // the destination through reordering —
                                        // a return leg picked deliberately is a
                                        // real choice and stores its id.
                                        item.dropoffPointID =
                                            index == defaultHandoverIndex ? nil : stops[index].id
                                    }
                                )
                            }
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
                        // A stated size of nothing is not a size: three positive sides,
                        // or the toggle is off (review, PR #21).
                        .disabled(!itemIsStatable)
                    }
                }
                .onChange(of: hasSize) {
                    // The toggle must *write* the state it claims in both directions. On
                    // it showed a fabricated zero size through the binding and stored
                    // nothing, so Save omitted the dimensions unless a field happened to
                    // be edited (review, PR #21).
                    item.size = hasSize
                        ? (item.size ?? ParcelItem.Size(lengthCm: 0, widthCm: 0, heightCm: 0))
                        : nil
                }
            }
        }

        /// The bound, stated where a hint would go: what fits the selected class — or
        /// that it does not (DesignSystem → field rule 2).
        @ViewBuilder
        private var fitFooter: some View {
            if let words = selectedTariff?.fitWords(for: item) {
                Text(words)
            }
        }

        /// The bounds this editor will not let a sender leave with: a stated size means
        /// three positive sides, a stated weight or value means more than nothing, and a
        /// count is at least one. Blank throughout is still fine — that removes the item.
        private var itemIsStatable: Bool {
            if item.isBlank { return true }
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

        /// Each end offers only the stops the other end leaves possible: a box cannot be
        /// handed over before it is collected, nor at the door it was collected from.
        /// Offering the whole list let a sender describe a journey the provider refuses
        /// (review, PR #21) — and an unavailable choice should not be reachable to begin
        /// with, which is the picker's version of "constraints replace hints".
        /// A default endpoint is a *position*, not an absence of one: `nil` pickup means
        /// the route's start and `nil` handover means its end. Reading them as "no
        /// constraint" let the other picker offer that very stop back, so a sender on the
        /// defaults could still choose an equal or reversed pair (review, PR #21).
        private var effectivePickupIndex: Int {
            item.pickupPointID.flatMap { id in stops.firstIndex { $0.id == id } } ?? 0
        }

        private var effectiveHandoverIndex: Int {
            item.dropoffPointID.flatMap { id in stops.firstIndex { $0.id == id } }
                ?? defaultHandoverIndex
        }

        /// The route's delivery end — the last non-return stop. `nil` handover
        /// means "the parcel's destination", not the array's last seat: a
        /// return leg rides last but is the way back (YD-15).
        private var defaultHandoverIndex: Int {
            stops.lastIndex { $0.role != .return } ?? max(stops.count - 1, 0)
        }

        /// One end of the journey as its own row: the caption above, the full
        /// address below it with room to wrap — a chevron away from the chooser.
        private func journeyRow(
            _ title: LocalizedStringKey,
            stop: Stop,
            isRouteDefault: Bool,
            @ViewBuilder chooser: @escaping () -> StopChooser
        ) -> some View {
            NavigationLink {
                chooser()
            } label: {
                VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                    HStack(spacing: Layout.Spacing.chip) {
                        Text(title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if isRouteDefault {
                            Text("the route's \(stop.id == stops.first?.id ? String(localized: "start") : String(localized: "end"))")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(stop.label) // user data — wraps, never truncates
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
}

extension NewDeliveryView.ItemEditor {
    /// The chooser: every stop of the route as a full-width row — the sender picks
    /// from the same vocabulary the route card shows, and a stop the journey cannot
    /// use is disabled *with its reason*, never hidden (Round 5, decision #52;
    /// DesignSystem → field rule 2).
    struct StopChooser: View {
        let title: LocalizedStringKey
        let stops: [NewDeliveryView.ItemEditor.Stop]
        let selectedIndex: Int
        let unavailable: (Int) -> String?
        let choose: (Int) -> Void

        @Environment(\.dismiss) private var dismiss

        var body: some View {
            List {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    let reason = unavailable(index)
                    Button {
                        choose(index)
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                                Text(stop.label) // wraps in full
                                    .multilineTextAlignment(.leading)
                                if let reason {
                                    Text(reason)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if index == selectedIndex {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(reason != nil)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
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
                .init(id: UUID(), label: "Невский проспект, 100", role: .pickup),
                .init(id: UUID(), label: "Арбат, 10", role: .dropoff),
                .init(id: UUID(), label: "Каширское шоссе, 52", role: .dropoff),
            ],
            selectedTariff: .courier,
            save: { _ in }
        )
    }
}

#Preview("Stop chooser — the impossible stop, disabled under its reason") {
    NavigationStack {
        NewDeliveryView.ItemEditor.StopChooser(
            title: "Where it boards",
            stops: [
                .init(id: UUID(), label: "Невский проспект, 100", role: .pickup),
                .init(id: UUID(), label: "Москва, Каширское шоссе, 52, корпус 3, подъезд 2 — со двора", role: .dropoff),
                .init(id: UUID(), label: "Арбат, 10", role: .dropoff),
            ],
            selectedIndex: 0,
            unavailable: { index in
                index >= 2 ? String(localized: "At or after the hand-over — a box can't board there.") : nil
            },
            choose: { _ in }
        )
    }
}

#Preview("Size fields — empty and stated") {
    @Previewable @State var empty = ParcelItem.Size(lengthCm: 0, widthCm: 0, heightCm: 0)
    @Previewable @State var stated = ParcelItem.Size(lengthCm: 40, widthCm: 30, heightCm: 25)
    Form {
        Section("Nothing stated yet") {
            NewDeliveryView.ItemEditor.SizeFields(size: $empty)
        }
        Section("A box the courier can take") {
            NewDeliveryView.ItemEditor.SizeFields(size: $stated)
        }
    }
}
