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

        /// Trailing scroll room so the When and Note sections can reach the top on any
        /// sheet height. Proportional to the *container*, not a fixed count: a constant
        /// sized for a phone left When stranded mid-sheet on a tall iPad, where the
        /// content after it is a fraction of the viewport (review, PR #26, edited ask).
        /// The share is the viewport minus the smallest trailing content a landing
        /// section can have below it (When's toggle row + the note section, well under
        /// a seventh of any supported sheet).
        private static let landingRunwayShare: CGFloat = 0.85

        var body: some View {
            NavigationStack {
                GeometryReader { container in
                ScrollViewReader { proxy in
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
                        .id(Focus.options)

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
                                    in: dueWindow
                                )
                            }
                        } footer: {
                            Text(dueBoundWords)
                        }
                        .id(Focus.when)

                        Section("Note for the courier") {
                            TextField("How to find you, what to mind…", text: $options.comment, axis: .vertical)
                                .lineLimit(2...5)
                                .focused($noteIsFocused)
                        }
                        .id(Focus.note)
                    }
                    // Landing needs range: `scrollTo` clamps to content bounds, and a
                    // form shorter than its viewport cannot bring a later section to the
                    // top at all (review, PR #26). The runway exists only for the two
                    // later landings — entering at Options keeps the form's honest end —
                    // and scales with the container, so a tall iPad sheet grants the
                    // same landing a phone does (review, PR #26, edited ask).
                    .contentMargins(
                        .bottom,
                        focus == .options ? 0 : container.size.height * Self.landingRunwayShare,
                        for: .scrollContent
                    )
                    .task {
                        // Landing, not travel: positioned before the sheet is read, so
                        // no scroll animation to branch for motion. `.task` runs after
                        // the first layout pass — `onAppear` fired before the Form knew
                        // its bounds, and the clamp ate the scroll (review, PR #26).
                        proxy.scrollTo(focus, anchor: .top)
                        // The note landing means "start typing": focusing raises the
                        // keyboard, and the system keeps the field in view thereafter.
                        if focus == .note { noteIsFocused = true }
                    }
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
                    options.setScheduled(isScheduled, within: dueWindow)
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
