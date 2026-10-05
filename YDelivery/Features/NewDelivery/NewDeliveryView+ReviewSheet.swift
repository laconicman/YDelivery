import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension NewDeliveryView {
    /// The confirmation the irreversible action owes (board `5f`, finding 2): route,
    /// price and class restated in full, and one Confirm. The sheet is the
    /// consent-and-run surface only — it no longer lists bounds (the card's rows
    /// state those, and the blocked bar lands on them); `blockers` remains purely
    /// as a guard for a bound that arrived *after* opening — a stale schema read,
    /// an expired quote — where the confirm disables beside the reason
    /// (DesignSystem → "The gateway"). The placed state acknowledges itself —
    /// bounce and haptic, no confetti, money just moved (DesignSystem → "Motion").
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
                .navigationTitle("Checkout")
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

        @ViewBuilder
        private var footerSection: some View {
            Section {
                switch ordering {
                case .idle, .queued:
                    // A bound that arrived after the sheet opened — a stale
                    // schema read, an expired quote — is stated above the dead
                    // confirm, and Back is the way out: the bound's door is the
                    // card's row, not a second remediation surface here
                    // (DesignSystem → "The gateway").
                    if let first = blockers.first {
                        Notice(.bound, Text(first.message))
                            .font(.subheadline)
                    }
                    Button(action: confirm) {
                        Text(priceText.map { "Order for \($0)" } ?? "Order")
                            .font(.headline)
                    }
                    .primaryAction()
                    .disabled(!blockers.isEmpty)
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
                                .primaryAction()
                            Button("Leave it for now", action: unresolvedDone)
                                .secondaryAction()
                        } else {
                            Button("Done", action: done)
                                .primaryAction()
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
                            Notice(.bound, Text("The price moved — was \(was), now \(now)."))
                                .font(.footnote)
                            Button("Try again", action: confirm)
                                .primaryAction()
                        case .unchanged:
                            Text("Requirements re-checked — the price stands.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Try again", action: confirm)
                                .primaryAction()
                        case .failed(let repriceReason):
                            // The reprice is a read — its failure stays a warning
                            // with its own retry, never a second order attempt.
                            Notice(.warning, Text("Re-pricing failed — \(repriceReason)"))
                                .font(.footnote)
                            Button("Check prices again", action: retryPrices)
                                .secondaryAction()
                        case .none:
                            Button("Try again", action: confirm)
                                .primaryAction()
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
                            .primaryAction()
                        Button("Close", action: unresolvedDone)
                            .secondaryAction()
                    }
                }
            } footer: {
                if blockers.isEmpty, ordering == .idle || ordering == .queued {
                    Text("Money moves and a courier is dispatched — cancelling later can cost the call-out fee.")
                }
            }
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

#Preview("A bound arrived after opening") {
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
                .init(id: "fieldSchemaStale",
                      message: "Your fields changed but could not be re-read — try again before ordering.",
                      step: "Re-read your fields",
                      destination: .fieldsSchema),
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
