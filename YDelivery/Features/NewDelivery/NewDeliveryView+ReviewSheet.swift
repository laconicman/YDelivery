import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension NewDeliveryView {
    /// The confirmation the irreversible action owes (board `5f`, finding 2): route,
    /// price and class restated in full, and one Confirm. When something still blocks
    /// ordering, the sheet states every bound *and* keeps the Order button — disabled,
    /// not absent, so the sheet never reads as a dead end; the placed state
    /// acknowledges itself — bounce and haptic, no confetti, money just moved
    /// (DesignSystem → "Motion").
    struct ReviewSheet: View {
        /// One stop, restated.
        struct Stop: Identifiable {
            let id: UUID
            let badge: PointBadge.Role
            let address: String
            let contact: String
        }

        /// How the reprice after a stale-requirements refusal stands — the refusal
        /// proved the held offer's payload dead, so the strip refetches and the
        /// sheet reports the outcome instead of offering a blind retry.
        nonisolated enum Reprice: Hashable {
            /// No quote was invalidated — an ordinary failure.
            case none
            /// Prices are being re-asked; there is nothing to re-confirm yet.
            case inFlight
            /// The fresh quote moved — the re-confirm's consent is the numeral.
            case moved(was: String, now: String)
            /// Fresh requirements, same price — nothing to disclose.
            case unchanged
            /// The reprice itself failed — its retry re-reads, never re-sends.
            case failed(String)
        }

        let stops: [Stop]
        let itemLines: [String]
        let optionsLine: String
        let whenLine: String
        let tariffName: String
        let priceText: String?
        let blockers: [Model.Blocker]
        let ordering: Model.Ordering
        var reprice: Reprice = .none
        /// Re-asks the prices when the reprice itself failed — a read, not a write.
        var retryPrices: () -> Void = {}
        let recordWarning: String?
        let confirm: () -> Void
        let done: () -> Void
        /// A blocker tapped — each bound is a door to the place that resolves it,
        /// never a dead end (the device drive's discoverability finding). The root
        /// routes the destination once this sheet has let go.
        var resolveBlocker: (Model.Blocker) -> Void = { _ in }
        /// Leaving an unresolved acceptance. Deliberately *not* `done`: nothing has been
        /// confirmed or recorded, so the draft, its idempotency token and its claim
        /// context all have to survive — retiring the draft here would let the next
        /// attempt mint a fresh token and dispatch a second courier (review, PR #22).
        var unresolvedDone: () -> Void = {}
        /// Asks what became of an acceptance whose answer was lost. A read, never a write.
        var reconcile: () -> Void = {}
        /// Writes a placed order to history again after the first attempt failed.
        var retryRecording: () -> Void = {}

        @Environment(\.dismiss) private var dismiss
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        /// Bumped once when the placed mark appears — `.bounce` is a discrete effect and
        /// fires on change, and Reduce Motion keeps the haptic while skipping the bump.
        @State private var placedBounce = 0

        var body: some View {
            NavigationStack {
                List {
                    if !blockers.isEmpty {
                        Section("Before ordering") {
                            ForEach(blockers) { blocker in
                                Button {
                                    resolveBlocker(blocker)
                                } label: {
                                    HStack(spacing: Layout.Spacing.gutter) {
                                        Notice(.bound, blocker.message)
                                        Spacer()
                                        // The door reads as a door — the chevron is
                                        // the summary row's own trailing convention.
                                        Image(systemSymbol: .chevronForward)
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .font(.subheadline)
                                .accessibilityHint(Text(blocker.destination.doorHint))
                                // The same lock as Back and the dismiss gesture:
                                // while an order run is in flight or has landed,
                                // `placeOrder` writes history from these very
                                // points — a door that opened the editable draft
                                // underneath would let the run record a route the
                                // courier was never given. The rows stay; the
                                // door just won't open.
                                .disabled(!doorsOpen)
                            }
                            // Blocked is still a button — disabled, not absent, and
                            // here beside the bounds rather than a screen-height
                            // below them. A missing CTA reads as a dead sheet; a
                            // greyed one says these rows are what's left between
                            // the sender and the order. Only while ordering has not
                            // begun, though: blockers can stay non-empty past
                            // placement, and a placed or unresolved order must not
                            // sit under a disabled Order action it no longer owns.
                            if ordering == .idle || ordering == .queued {
                                Button(action: confirm) {
                                    Text(priceText.map { "Order for \($0)" } ?? "Order")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(true)
                            }
                        }
                    }

                    Section("Route") {
                        ForEach(stops) { stop in
                            HStack(alignment: .top, spacing: Layout.Spacing.gutter) {
                                PointBadge(role: stop.badge)
                                VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                                    Text(stop.address)
                                    Text(stop.contact)
                                        .font(.footnote)
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    }

                    if !itemLines.isEmpty {
                        Section("Parcel") {
                            ForEach(itemLines, id: \.self) { line in
                                Text(line)
                                    .font(.subheadline)
                            }
                        }
                    }

                    Section {
                        LabeledContent("Options", value: optionsLine)
                        LabeledContent("When", value: whenLine)
                        if let priceText {
                            LabeledContent {
                                Text(priceText)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            } label: {
                                Text(tariffName)
                            }
                        }
                    }

                    footerSection
                }
                .navigationTitle("Review the order")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        // Gesture dismissal is already disabled while busy; Back was the
                        // way around it. Edits made during creation or acceptance would
                        // change the points this run later writes into history, so history
                        // would describe a route the courier was never given (review,
                        // PR #22).
                        if ordering != .placed, !isBusy {
                            Button("Back") { dismiss() }
                        }
                    }
                }
                .interactiveDismissDisabled(isBusy)
            }
            .presentationDetents([.large])
            // «Заказ создан»: the one irreversible action confirms itself — success
            // haptic always, bounce only when motion is welcome.
            .sensoryFeedback(.success, trigger: ordering == .placed) { _, isPlaced in isPlaced }
        }

        private var isBusy: Bool {
            ordering == .creating || ordering == .estimating || ordering == .accepting
        }

        /// Doors open only while the run hasn't started — or after it failed,
        /// where editing is the recovery. A queued or placed run, an unresolved
        /// acceptance: the draft stays read-only behind the sheet.
        private var doorsOpen: Bool {
            switch ordering {
            case .idle, .failed: true
            default: false
            }
        }

        @ViewBuilder
        private var footerSection: some View {
            // Borderless for the plain buttons: an automatic-styled button makes
            // its whole `List` row the target, and these rows are words a sender
            // reads before deciding — a tap on the refusal or on the moved price
            // must not be the «Try again» (the draft card's add-row, same ruling).
            // The prominent buttons keep their own style.
            Section {
                switch ordering {
                case .idle, .queued:
                    if blockers.isEmpty {
                        Button(action: confirm) {
                            Text(priceText.map { "Order for \($0)" } ?? "Order")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                case .creating, .estimating, .accepting:
                    HStack(spacing: Layout.Spacing.unit) {
                        ProgressView()
                        Text(phaseWords)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                case .placed:
                    VStack(spacing: Layout.Spacing.unit) {
                        Image(systemSymbol: .checkmarkCircleFill)
                            .font(.largeTitle)
                            // The searching token: the order is placed and the hunt is
                            // on — the same green every surface will use for it.
                            .foregroundStyle(OrderStatus.searching.color)
                            .symbolEffect(.bounce, value: placedBounce)
                            .onAppear {
                                if !reduceMotion { placedBounce += 1 }
                            }
                        Text("Order placed — finding a courier")
                            .font(.headline)
                        if let recordWarning {
                            // The wire succeeded and the disk did not — an uncertain
                            // memory, not a refused action: warning, not error.
                            Notice(.warning, recordWarning)
                                .font(.footnote)
                            // The order exists; this draft holds the only copy of it that
                            // has not been written down. Done would retire the draft and
                            // take that copy with it, so the offer here is to write it
                            // again rather than to leave (review, PR #22).
                            Button("Save it again", action: retryRecording)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity)
                            Button(action: unresolvedDone) {
                                Text("Leave it for now")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)
                        } else {
                            Button(action: done) {
                                Text("Done")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                    .frame(maxWidth: .infinity)
                case .failed(let reason):
                    // A definite refusal — the error role: retrying re-asks.
                    VStack(alignment: .leading, spacing: Layout.Spacing.unit) {
                        Notice(.error, reason.namingKnownRequirements)
                            .font(.subheadline)
                        switch reprice {
                        case .inFlight:
                            // The stale payload is already being re-priced — a retry
                            // pressed now would replay nothing new, so it stays away.
                            HStack(spacing: Layout.Spacing.unit) {
                                ProgressView()
                                Text("Re-pricing the run — the provider's requirements moved.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        case .moved(let was, let now):
                            // The re-confirm's consent: the price it will pay is said
                            // in numbers, where the decision is made.
                            Notice(.bound, "The price moved — was \(was), now \(now).")
                                .font(.footnote)
                            Button("Try again", action: confirm)
                        case .unchanged:
                            Text("Requirements re-checked — the price stands.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Try again", action: confirm)
                        case .failed(let repriceReason):
                            // The reprice is a read — its failure stays a warning
                            // with its own retry, never a second order attempt.
                            Notice(.warning, "Re-pricing failed — \(repriceReason)")
                                .font(.footnote)
                            Button("Check prices again", action: retryPrices)
                        case .none:
                            Button("Try again", action: confirm)
                        }
                    }
                case .unresolved(let reason, _):
                    // No retry here on purpose: acceptance was attempted, so ordering
                    // again could buy a second delivery. The honest next step is to look
                    // at what exists before doing anything (review, PR #22).
                    VStack(alignment: .leading, spacing: Layout.Spacing.unit) {
                        // The answer was lost, not refused — uncertain is warning's
                        // seat, never error's.
                        Notice(.warning, reason)
                            .font(.subheadline)
                        Text("Check Deliveries before ordering again — this one may have gone through.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        // Reads only — it cannot create and cannot accept — so pressing
                        // it is always safe, which is what makes it the first offer here
                        // rather than a second «Try again» (review, PR #22).
                        Button("Check again", action: reconcile)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                        Button(action: unresolvedDone) {
                            Text("Close")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                    }
                }
            } footer: {
                if blockers.isEmpty, ordering == .idle || ordering == .queued {
                    Text("Money moves and a courier is dispatched — cancelling later can cost the call-out fee.")
                }
            }
            .buttonStyle(.borderless)
        }

        private var phaseWords: LocalizedStringKey {
            switch ordering {
            case .creating: "Placing the order…"
            case .estimating: "The provider is pricing the run…"
            case .accepting: "Confirming — money moves now…"
            default: ""
            }
        }
    }
}

#Preview("Ready to confirm") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.ReviewSheet(
            stops: [
                .init(id: UUID(), badge: .start, address: "Москва, ул Москворечье, 6", contact: "Иван Петров · +7 912 345-67-89"),
                .init(id: UUID(), badge: .end, address: "Москва, Каширское шоссе, 52", contact: "Анна Сидорова · +7 998 765-43-21"),
            ],
            itemLines: ["Комплект учебников — 5 pcs · 2 kg · 2 500 ₽"],
            optionsLine: "pro courier · to the door",
            whenLine: "as soon as possible",
            tariffName: "Express",
            priceText: "1 190 ₽",
            blockers: [],
            ordering: .idle,
            recordWarning: nil,
            confirm: {},
            done: {}
        )
    }
}

nonisolated extension String {
    /// The provider's refusal beside the app's own term — «От двери до двери» is
    /// this draft's «to the door» option (C2: the provider's phrase and the
    /// sender's vocabulary name the same switch). Only that phrase earns the
    /// annotation: a bare «двер»/"door" — a door code, a до-двери address
    /// detail — is not the option. Unrecognized refusals pass through verbatim.
    var namingKnownRequirements: String {
        let lowered = lowercased()
        guard lowered.contains("от двери до двери")
                || lowered.contains("door to door")
                || lowered.contains("door_to_door") else { return self }
        return String(localized: "\(self) — the «to the door» option in your draft.")
    }
}

private extension NewDeliveryView.Model.Blocker.Destination {
    /// What the tap does, for the rotor — a bound's door says where it goes.
    var doorHint: LocalizedStringKey {
        switch self {
        case .point, .contact: "Opens this stop's editor."
        case .item, .newItem: "Opens the parcel editor."
        case .fieldsSchema: "Reads your fields again."
        case .field: "Back to the draft — the field waits there."
        case .offer: "Back to the draft — the delivery classes wait there."
        }
    }
}

#Preview("Blocked — every bound stated") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.ReviewSheet(
            stops: [
                .init(id: UUID(), badge: .start, address: "Москва, ул Москворечье, 6", contact: "Иван Петров · +7 912 345-67-89"),
                .init(id: UUID(), badge: .end, address: "Москва, Каширское шоссе, 52", contact: ""),
            ],
            itemLines: [],
            optionsLine: "to the door",
            whenLine: "as soon as possible",
            tariffName: "Courier",
            priceText: "749 ₽",
            blockers: [
                .init(id: "contact", message: "The courier calls ahead — every stop needs a person with a phone.",
                      destination: .contact(UUID())),
                .init(id: "items", message: "Say what's inside — the parcel is insured by its declared value.",
                      destination: .newItem),
            ],
            ordering: .idle,
            recordWarning: nil,
            confirm: {},
            done: {}
        )
    }
}

#Preview("Placed") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.ReviewSheet(
            stops: [
                .init(id: UUID(), badge: .start, address: "Москва, ул Москворечье, 6", contact: "Иван Петров"),
                .init(id: UUID(), badge: .end, address: "Москва, Каширское шоссе, 52", contact: "Анна Сидорова"),
            ],
            itemLines: ["Ноутбук — 1 pcs · 60 000 ₽"],
            optionsLine: "to the door",
            whenLine: "as soon as possible",
            tariffName: "Express",
            priceText: "1 190 ₽",
            blockers: [],
            ordering: .placed,
            recordWarning: nil,
            confirm: {},
            done: {}
        )
    }
}

#Preview("Failed — a refused write") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.ReviewSheet(
            stops: [
                .init(id: UUID(), badge: .start, address: "Москва, ул Москворечье, 6", contact: "Иван Петров"),
                .init(id: UUID(), badge: .end, address: "Москва, Каширское шоссе, 52", contact: "Анна Сидорова"),
            ],
            itemLines: ["Ноутбук — 1 pcs · 60 000 ₽"],
            optionsLine: "to the door",
            whenLine: "as soon as possible",
            tariffName: "Express",
            priceText: "1 190 ₽",
            blockers: [],
            ordering: .failed("The provider refused the offer — the door-to-door option changed."),
            recordWarning: nil,
            confirm: {},
            done: {}
        )
    }
}

#Preview("Unresolved — the answer was lost") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.ReviewSheet(
            stops: [
                .init(id: UUID(), badge: .start, address: "Москва, ул Москворечье, 6", contact: "Иван Петров"),
                .init(id: UUID(), badge: .end, address: "Москва, Каширское шоссе, 52", contact: "Анна Сидорова"),
            ],
            itemLines: ["Ноутбук — 1 pcs · 60 000 ₽"],
            optionsLine: "to the door",
            whenLine: "as soon as possible",
            tariffName: "Express",
            priceText: "1 190 ₽",
            blockers: [],
            ordering: .unresolved(
                reason: "No answer came back for the acceptance — the provider may have taken the order.",
                claimID: "claim-preview"
            ),
            recordWarning: nil,
            confirm: {},
            done: {}
        )
    }
}

#Preview("Failed — requirements moved, price followed") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.ReviewSheet(
            stops: [
                .init(id: UUID(), badge: .start, address: "Москва, ул Москворечье, 6", contact: "Иван Петров"),
                .init(id: UUID(), badge: .end, address: "Москва, Каширское шоссе, 52", contact: "Анна Сидорова"),
            ],
            itemLines: ["Ноутбук — 1 pcs · 60 000 ₽"],
            optionsLine: "to the door",
            whenLine: "as soon as possible",
            tariffName: "Express",
            priceText: "1 240 ₽",
            blockers: [],
            ordering: .failed("The door-to-door option changed."),
            reprice: .moved(was: "1 190 ₽", now: "1 240 ₽"),
            recordWarning: nil,
            confirm: {},
            done: {}
        )
    }
}

#Preview("Failed — still re-pricing") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.ReviewSheet(
            stops: [
                .init(id: UUID(), badge: .start, address: "Москва, ул Москворечье, 6", contact: "Иван Петров"),
                .init(id: UUID(), badge: .end, address: "Москва, Каширское шоссе, 52", contact: "Анна Сидорова"),
            ],
            itemLines: ["Ноутбук — 1 pcs · 60 000 ₽"],
            optionsLine: "to the door",
            whenLine: "as soon as possible",
            tariffName: "Express",
            priceText: nil,
            blockers: [],
            ordering: .failed("The door-to-door option changed."),
            reprice: .inFlight,
            recordWarning: nil,
            confirm: {},
            done: {}
        )
    }
}

#Preview("Placed — history refused the write") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NewDeliveryView.ReviewSheet(
            stops: [
                .init(id: UUID(), badge: .start, address: "Москва, ул Москворечье, 6", contact: "Иван Петров"),
                .init(id: UUID(), badge: .end, address: "Москва, Каширское шоссе, 52", contact: "Анна Сидорова"),
            ],
            itemLines: ["Ноутбук — 1 pcs · 60 000 ₽"],
            optionsLine: "to the door",
            whenLine: "as soon as possible",
            tariffName: "Express",
            priceText: "1 190 ₽",
            blockers: [],
            ordering: .placed,
            recordWarning: "The order was placed, but saving it to history failed.",
            confirm: {},
            done: {}
        )
    }
}
