import SwiftUI

extension NewDeliveryView {
    /// Options, timing, and the courier's note (board `3d`): every bounded control
    /// states its bound where a hint would go, and unavailable options render disabled
    /// with their reason rather than vanishing — the vocabulary stays learnable
    /// (DesignSystem → field rules; §4 interdependencies, enforced here, never
    /// discovered via API errors).
    struct OptionsEditor: View {
        /// Where the sheet opens. Three summary rows share this editor, and one tap
        /// down must land on what was tapped — "density lives one tap down" is a
        /// promise about the destination, not just the distance (DesignSystem → field
        /// rule 1; author, 2026-09-09).
        enum Focus: String, Identifiable, CaseIterable {
            case options, when, note
            var id: String { rawValue }
        }

        let focus: Focus
        let selectedTariff: TariffClass?
        let save: (DeliveryOptions) -> Void

        @State private var options: DeliveryOptions
        @State private var isScheduled: Bool
        /// One window for the life of this sheet. The range the picker offers and the
        /// value a fresh schedule starts at must come from the same `Date.now`, or the
        /// initial value can sit microseconds outside its own range; `@State` also keeps
        /// it from drifting forward on every body re-evaluation (review, PR #21).
        @State private var dueWindow: ClosedRange<Date>
        @FocusState private var noteIsFocused: Bool
        @Environment(\.dismiss) private var dismiss

        init(
            focus: Focus = .options,
            options: DeliveryOptions,
            selectedTariff: TariffClass?,
            save: @escaping (DeliveryOptions) -> Void
        ) {
            self.focus = focus
            self.selectedTariff = selectedTariff
            self.save = save
            // A parked draft can outlive its own pickup time; opening the editor on a
            // lapsed schedule would hand `DatePicker` a selection outside its own range.
            // Lapsed first — then clamped into the class's window, so `DatePicker` never
            // opens on a selection outside its own range (a cargo date is legal for cargo
            // and out of range for a courier).
            var settled = options.effective()
            if let due = settled.due {
                let window = DeliveryOptions.dueWindow(for: selectedTariff)
                settled.due = min(max(due, window.lowerBound), window.upperBound)
            }
            _options = State(initialValue: settled)
            _isScheduled = State(initialValue: settled.due != nil)
            _dueWindow = State(initialValue: DeliveryOptions.dueWindow(for: selectedTariff))
        }

        private var thermobagAllowed: Bool { selectedTariff == .courier }
        private var loadersAllowed: Bool { selectedTariff == .cargo }

        /// The tapped section leads; the rest follow in their canonical order. Landing
        /// by *ordering* ends three rounds of scroll arithmetic (review, PR #26): a
        /// 480-point runway stranded tall iPads, a 0.85 share still missed Note, and a
        /// full-height margin let the whole form scroll into blankness. Ordering has
        /// none of those failure modes — no runway, nothing to clamp, every option
        /// still reachable below, and no scroll to branch for Reduce Motion.
        private var sectionOrder: [Focus] {
            [focus] + Focus.allCases.filter { $0 != focus }
        }

        var body: some View {
            NavigationStack {
                Form {
                    ForEach(sectionOrder) { section(for: $0) }
                }
                .onAppear {
                    // The note landing means "start typing": focusing raises the
                    // keyboard, and the system keeps the field in view thereafter.
                    if focus == .note { noteIsFocused = true }
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
                    options.setScheduled(isScheduled, within: dueWindow)
                }
            }
        }

        /// One group per entrance. `.options` brings the loaders along — they are not
        /// an entrance of their own, and they stay behind the options wherever the
        /// options land in the order.
        @ViewBuilder
        private func section(for focus: Focus) -> some View {
            switch focus {
            case .options:
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
            case .when:
                Section {
                    Toggle("Scheduled pickup", isOn: $isScheduled)
                    if isScheduled {
                        DatePicker(
                            "Courier arrives",
                            selection: dueBinding,
                            in: dueWindow
                        )
                    }
                } footer: {
                    Text(dueBoundWords)
                }
            case .note:
                Section("Note for the courier") {
                    TextField("How to find you, what to mind…", text: $options.comment, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($noteIsFocused)
                }
            }
        }

        /// The bound this picker actually offers, stated rather than hinted — and it
        /// depends on the class, so it cannot be a fixed sentence (review, PR #21).
        private var dueBoundWords: LocalizedStringKey {
            let hours = Int(dueWindow.upperBound.timeIntervalSince(dueWindow.lowerBound) / 3600)
            return hours >= 24
                ? "From an hour ahead, up to \(hours / 24) days out."
                : "From an hour ahead, up to \(hours + 1) hours out."
        }

        private var dueBinding: Binding<Date> {
            Binding(
                get: { options.due ?? dueWindow.lowerBound },
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

#Preview("Opened on the note — the tapped row is the landing") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.OptionsEditor(
            focus: .note,
            options: DeliveryOptions(),
            selectedTariff: .courier,
            save: { _ in }
        )
    }
}
