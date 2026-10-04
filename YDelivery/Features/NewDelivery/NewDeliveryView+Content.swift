import MapKit
import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension NewDeliveryView {
    /// Pure presentation of the fixed-card shell (board `1b`): the map above, the route
    /// card below, both fully readable without a gesture. Plain values in, intents out
    /// (R1/R2); the badges make the route list the map's legend (board `2c`).
    struct Content: View {
        /// One route row, reduced to what it renders.
        struct Row: Identifiable {
            let id: UUID
            let badge: PointBadge.Role
            let address: String?
            let placeholder: LocalizedStringKey
            let contactSummary: String?
            let contactInvitation: LocalizedStringKey
            /// Roles this row may switch to — empty for the pinned pickup row.
            let availableRoles: [NewDeliveryView.Model.Role]
            /// The address names no building — unusual enough for a courier that
            /// the row says so (author, 2026-09-18).
            var addressWarning: String? = nil
            /// What the parcel does at this door — the counted sentence Round 5
            /// (#45–46) gives both the row and the map callout.
            var parcelActions: String? = nil
            let isDeletable: Bool
            let isMovable: Bool
        }

        /// A chosen point on the map — what the marker renders, and what its callout
        /// card reads (board `4a`): the pin carries the card's fields so tapping it
        /// needs no second lookup.
        struct Pin: Identifiable, Hashable {
            let id: UUID
            let latitude: Double
            let longitude: Double
            let badge: PointBadge.Role
            /// The card's verb («забрать») — the sender's role word, not the badge's.
            let role: Model.Role
            /// One-based position in the route — «первая точка».
            let visitOrdinal: Int
            let address: String
            let parts: AddressParts?
            let contactSummary: String?
            let contactPhone: String?
            /// Pieces leaving at / arriving at this stop — the callout's parcel
            /// line (board `4a`). Zero means nothing moves here and the card
            /// draws no line.
            let parcelsLeaving: Int
            let parcelsArriving: Int
        }

        /// One «Ваши поля» row, reduced to what it renders (board `4b`).
        struct FieldRow: Identifiable {
            let id: UUID
            let name: String
            let kind: CustomFieldDefinition.Kind
            let choices: [String]
            /// Whether the order may leave without it — `false` pins the required
            /// hint beside the field (the blocker explains where it's asked, not
            /// only on the review sheet).
            let isOptional: Bool
            let value: String
        }

        /// One parcel item, reduced to its row.
        struct ItemRow: Identifiable {
            let id: UUID
            let name: String
            let summary: String
            /// Filled when the item is known not to fit the selected class — the row
            /// carries the warning words, never color alone.
            let misfit: String?
            /// The item's own route in the stops' words — «A → B» — whenever the
            /// route has middles (YD-6).
            var journey: String? = nil
        }

        /// A parcel template, reduced to its chip — the library's *use* path
        /// (the Library tab is the curate path). Pinned entries lead.
        struct TemplateChip: Identifiable, Hashable {
            let id: UUID
            let name: String
        }

        let rows: [Row]
        let pins: [Pin]
        let estimate: NewDeliveryView.Model.Estimate
        let offers: NewDeliveryView.Model.Offers
        let selectedOfferID: Offer.ID?
        let itemRows: [ItemRow]
        /// «Ваши поля» — the schema reduced to rows on the root's side of the
        /// seam: `fieldRows` draw now, `hiddenFieldRows` feed the «Add field»
        /// menu. Empty means no schema configured — unless `fieldsError` says the
        /// schema could not be read at all, which the section renders instead of
        /// impersonating "nothing configured" (review, PR #42).
        let fieldRows: [FieldRow]
        let hiddenFieldRows: [FieldRow]
        let fieldsError: String?
        let retryFields: () -> Void
        let optionsSummary: String
        let whenSummary: String
        let commentSummary: String?
        /// The CTA's words, or `nil` when the bar has no place on screen — derived on the
        /// root's side of the seam with everything else (R5; review, PR #22).
        var orderBarTitle: String? = nil
        let canSwap: Bool
        let canReorder: Bool
        let pick: (UUID) -> Void
        let editContact: (UUID) -> Void
        /// The callout's «Сохранить как место» — nil-offered when the store can't
        /// take one, so the card never shows a button that cannot run (board `4a`:
        /// an action that exists nowhere else never lives on the callout anyway).
        let savePlace: (UUID) -> Void
        let canSavePlace: Bool
        let setRole: (UUID, NewDeliveryView.Model.Role) -> Void
        let swapEnds: () -> Void
        let addStop: () -> Void
        let removeRows: (IndexSet) -> Void
        let moveRows: (IndexSet, Int) -> Void
        let retryEstimate: () -> Void
        let selectOffer: (Offer.ID) -> Void
        let retryOffers: () -> Void
        let openExplainer: () -> Void
        let addItem: () -> Void
        let editItem: (UUID) -> Void
        let removeItems: (IndexSet) -> Void
        /// The library's chips, and its seam: `templatesError` filled means the
        /// templates could not be *read* — which must never draw as an empty
        /// library (the `fieldsError` rule, one channel over). Defaulted so
        /// previews of the parcel rows stay terse.
        var templateChips: [TemplateChip] = []
        var templatesError: String? = nil
        var retryTemplates: () -> Void = {}
        var applyTemplate: (TemplateChip.ID) -> Void = { _ in }
        /// The item row's second door to «Save as template» — the naming sheet
        /// opens at the root. `nil` when the store cannot keep one, so the row
        /// never shows a menu item that cannot run (the `savePlace` rule).
        var saveTemplateItem: ((UUID) -> Void)? = nil
        /// A blocker's field door, landed: the root sets the row to bring into
        /// view; `onScrolled` clears it so the next door to the same row still
        /// reads as a change. Plain value + closure, like every other input.
        var scrollTarget: ScrollAnchor? = nil
        var onScrolled: () -> Void = {}
        /// Where a bound's door lands on the draft card — a row id, or the strip
        /// itself for the class bound (review, PR #104). Rows answer to their
        /// subject's raw id; `.tariffStrip` answers to its constant. The view's
        /// own type: presentation state stays out of the model (REVIEW.md).
        enum ScrollAnchor: Hashable {
            case field(UUID)
            case item(UUID)
            case stop(UUID)
            case tariffStrip

            var id: AnyHashable {
                switch self {
                case .field(let id), .item(let id), .stop(let id): id
                case .tariffStrip: "tariffStrip"
                }
            }
        }
        /// The strip's order — a binding because the sort menu edits it, persisted
        /// on the root's side (`@AppStorage`). `priceRefreshNote` is the one-shot
        /// footnote after a TTL re-price; nil is the common case.
        var sort: Binding<OfferSort> = .constant(.fastest)
        var priceRefreshNote: String? = nil
        let setFieldValue: (UUID, String) -> Void
        let revealField: (UUID) -> Void
        let editOptions: (NewDeliveryView.OptionsEditor.Focus) -> Void

        @State private var camera: MapCameraPosition = .automatic
        @State private var editMode: EditMode = .inactive
        /// The «Add field» chooser — presentation state only, like `editMode`.
        @State private var pickingField = false
        @State private var pickingTemplate = false
        /// The open callout's pin — the pin↔row agreement (board `4a`): the card,
        /// the mark, and the highlighted row all read this one id.
        @State private var calloutPin: UUID?

        let openReview: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                RouteMap(
                    pins: pins,
                    legs: estimateLegs,
                    camera: $camera,
                    selection: $calloutPin,
                    canSavePlace: canSavePlace,
                    pick: pick,
                    savePlace: savePlace
                )
                    // An inset, not an overlay: the map's automatic framing then keeps
                    // every mark clear of the bar instead of hiding the end pin under it.
                    .safeAreaInset(edge: .bottom) {
                        EstimateBar(estimate: estimate, retry: retryEstimate)
                            .padding(.horizontal, Layout.Spacing.edge)
                            .padding(.bottom, Layout.Spacing.cards)
                    }
                    .containerRelativeFrame(.vertical) { length, _ in length * Self.mapShare }
                routeCard
            }
            .safeAreaInset(edge: .bottom) {
                OrderBar(title: orderBarTitle, openReview: openReview)
            }
        }

        /// The board's proportion: the map above, the card fully readable below (`1b`).
        private static let mapShare: CGFloat = 1.0 / 3.0

        private var estimateLegs: [[RouteEstimate.Coordinate]] {
            if case .ready(let estimate) = estimate { estimate.legs } else { [] }
        }

        /// One summary line per group, expanding to typed rows — the draft reads in
        /// three seconds; density lives one tap down (DesignSystem → field rule 1).
        private func summaryRow(symbol: SFSymbol, title: LocalizedStringKey, value: String) -> some View {
            HStack(alignment: .top, spacing: Layout.Spacing.gutter) {
                Image(systemSymbol: symbol)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                    Text(title)
                    Text(value)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Image(systemSymbol: .chevronForward)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }

        /// One schema field as an editor: a text field or a choice picker — the
        /// definition types it, the row renders it. A required field wears a
        /// persistent `required` caption beside the name (the schema rows' own
        /// "… · required · …" precedent; an asterisk reads as punctuation, not
        /// words, to VoiceOver), and the `bound` line lives *here* while the field
        /// is actually blocking (board `4b`: the blocker explains beside the
        /// field, not only on review) — an answered field is quiet
        /// (DesignSystemSemantics → bounds).
        struct SchemaFieldRow: View {
            let row: FieldRow
            let setFieldValue: (UUID, String) -> Void

            @Environment(\.accessibilityReduceMotion) private var reduceMotion
            /// The field shake's phase counter — incremented per transition into
            /// unmet, so each new offense replays the nudge.
            @State private var shakes = 0

            private var value: Binding<String> {
                Binding(get: { row.value }, set: { setFieldValue(row.id, $0) })
            }
            /// A required field holding only whitespace is the bound the order
            /// blocks on.
            private var unmet: Bool {
                !row.isOptional && row.value.trimmingCharacters(in: .whitespaces).isEmpty
            }

            var body: some View {
                VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                    Group {
                        switch row.kind {
                        case .text:
                            HStack(spacing: Layout.Spacing.unit) {
                                TextField(row.name, text: value)
                                requiredCaption
                            }
                        case .choice:
                            Picker(selection: value) {
                                if row.isOptional {
                                    // Clearing *is* an answer for an optional field.
                                    Text("None").tag("")
                                } else if row.value.isEmpty {
                                    // The unset seat — a prompt, never an offered
                                    // answer: it leaves the option list once a real
                                    // choice lands (a required field can't un-answer).
                                    Text("Not set").tag("")
                                }
                                ForEach(row.choices, id: \.self) { choice in
                                    Text(choice).tag(choice)
                                }
                            } label: {
                                HStack(spacing: Layout.Spacing.unit) {
                                    Text(row.name) // the schema's own words, verbatim
                                    requiredCaption
                                }
                            }
                        }
                    }
                    // Motion row 7: the nudge sits beside the input — the bound
                    // line itself must not move.
                    .modifier(FieldShake(phase: CGFloat(shakes)))
                    if unmet {
                        Notice(.bound, "Required — the order doesn't leave without it.")
                            .font(.footnote)
                    }
                }
                .onChange(of: unmet) { _, nowUnmet in
                    // Motion row 7: the ~2-frame nudge sits beside the input, and
                    // only on the transition into unmet — a fresh draft's
                    // already-empty fields don't rattle. Reduce Motion skips it:
                    // the bound line's glyph + words carry the meaning still.
                    if nowUnmet, !reduceMotion {
                        withAnimation(.easeOut(duration: 0.3)) { shakes += 1 }
                    }
                }
            }

            private var requiredCaption: some View {
                Group {
                    if !row.isOptional {
                        Text("required")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }

        /// Motion row 7's field shake: a ~2-frame horizontal nudge beside the
        /// input as a bound lands — never for wire failures.
        private struct FieldShake: GeometryEffect {
            var phase: CGFloat
            var animatableData: CGFloat {
                get { phase }
                set { phase = newValue }
            }

            /// A nudge, not a vibration — one decaying pass, 6 pt at the most.
            private static let distance: CGFloat = 6

            func effectValue(size: CGSize) -> ProjectionTransform {
                // The fractional pass only — repeated clears replay the same
                // nudge rather than magnifying it or drifting sideways.
                let progress = phase - floor(phase)
                return ProjectionTransform(CGAffineTransform(
                    translationX: sin(progress * .pi * 3) * Self.distance * (1 - progress),
                    y: 0))
            }
        }

        private var routeCard: some View {
            ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(rows) { row in
                        PointRow(
                            row: row,
                            pick: { pick(row.id) },
                            editContact: { editContact(row.id) },
                            setRole: { setRole(row.id, $0) },
                            // The pin↔row agreement in reverse: the row opens the
                            // same card the pin does, so list and VoiceOver users
                            // reach everything the callout holds (board `4a`).
                            showCallout: pins.contains(where: { $0.id == row.id })
                                ? { calloutPin = row.id } : nil,
                            savePlace: canSavePlace && pins.contains(where: { $0.id == row.id })
                                ? { savePlace(row.id) } : nil
                        )
                        // The open callout's row stays highlighted — «строка в
                        // списке подсвечена, пока открыта выноска» (board `4a`).
                        .listRowBackground(
                            Color.accentColor.opacity(
                                calloutPin == row.id ? RouteLine.selectionTint : 0
                            )
                        )
                        .deleteDisabled(!row.isDeletable)
                        .moveDisabled(!row.isMovable)
                        // A bound's door scrolls to its row — every row answers
                        // to its subject's id.
                        .id(row.id)
                    }
                    .onDelete(perform: removeRows)
                    .onMove(perform: moveRows)

                    actions
                        .frame(maxWidth: .infinity)
                        // The action strip is part of the route card, not a row —
                        // a card-colored row below it read as «the last row of a
                        // missing List» (device drive, 2026-10). Clear background
                        // and no separator anchor it to the section instead.
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    // The card's stops read under a title — without one the last
                    // row floated, attached to nothing (device drive, 2026-10).
                    Text("Route")
                } footer: {
                    if offers == .idle {
                        // Prices follow the route alone — an empty parcel rides the
                        // wire as a placeholder item, so the only precondition left
                        // is a complete route (live evidence, 2026-09-22). A bound,
                        // stated where the decision is.
                        Notice(.bound, "Prices appear when the route is complete.")
                    }
                }

                if offers != .idle {
                    Section {
                        VStack(alignment: .leading, spacing: Layout.Spacing.tight) {
                            TariffStrip(
                                offers: offers,
                                selectedID: selectedOfferID,
                                select: selectOffer,
                                retry: retryOffers
                            )
                            // The TTL re-price's one line — said once, under the
                            // fresh cards; only beside a `.ready` strip (review,
                            // PR #117 — a failed re-price or a sign-out must not
                            // keep wearing it).
                            if let priceRefreshNote, case .ready = offers {
                                Text(priceRefreshNote)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listRowInsets(EdgeInsets(
                            top: Layout.Spacing.tight,
                            leading: Layout.Spacing.gutter,
                            bottom: Layout.Spacing.tight,
                            trailing: Layout.Spacing.gutter
                        ))
                        .listRowBackground(Color.clear)
                    } header: {
                        HStack {
                            Text("Delivery options")
                            Spacer()
                            // Same-class offers differ only by their windows —
                            // the order is part of the answer (board `1b`).
                            Menu {
                                Picker("Sort", selection: sort) {
                                    ForEach(OfferSort.allCases, id: \.self) { option in
                                        Text(option.words).tag(option)
                                    }
                                }
                            } label: {
                                Label(sort.wrappedValue.words, systemSymbol: .arrowUpArrowDown)
                                    .font(.footnote)
                            }
                            Button(action: openExplainer) {
                                Image(systemSymbol: .infoCircle)
                            }
                            .font(.body)
                            .accessibilityLabel(Text("About the delivery classes"))
                        }
                    }
                    // The class bound's door lands here — the strip is the row
                    // that answers it.
                    .id("tariffStrip")
                }

                Section {
                    if let templatesError {
                        // A failed read stays quiet — glyph + words + the in-place
                        // retry, never the error hue (the `EstimateBar` convention).
                        VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                            Label(templatesError, systemSymbol: .exclamationmarkTriangle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Retry", action: retryTemplates)
                                .font(.footnote)
                        }
                    }
                    ForEach(itemRows) { item in
                        Button {
                            editItem(item.id)
                        } label: {
                            HStack(alignment: .top, spacing: Layout.Spacing.gutter) {
                                Image(systemSymbol: .shippingbox)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                                    Text(item.name)
                                    Text(item.summary)
                                        .font(.footnote)
                                        .foregroundStyle(Color.secondary)
                                    if let journey = item.journey {
                                        Text(journey) // stops' own words — wraps
                                            .font(.footnote)
                                            .foregroundStyle(Color.secondary)
                                    }
                                    if let misfit = item.misfit {
                                        Label(misfit, systemSymbol: .exclamationmarkTriangle)
                                            .font(.footnote)
                                            .foregroundStyle(Color.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .contextMenu {
                            // The second door to «Save as template» — the first
                            // lives in the item editor itself (the library doc).
                            if let saveTemplateItem {
                                Button {
                                    saveTemplateItem(item.id)
                                } label: {
                                    Label("Save as a template", systemSymbol: .shippingbox)
                                }
                            }
                        }
                    }
                    .onDelete(perform: removeItems)

                    // Both add-doors in one row — the library's entrance used to
                    // squat as a chips row of its own. Each label degrades to its
                    // short form on its own (ViewThatFits per button).
                    HStack {
                        Button(action: addItem) {
                            ViewThatFits(in: .horizontal) {
                                Label("Add an item", systemSymbol: .plus)
                                Label("Add", systemSymbol: .plus)
                            }
                        }
                        if !templateChips.isEmpty {
                            Spacer()
                            Button { pickingTemplate = true } label: {
                                ViewThatFits(in: .horizontal) {
                                    Label("Add from library", systemSymbol: .shippingbox)
                                    Label("Library", systemSymbol: .shippingbox)
                                }
                            }
                            // A dialog like «Add field», not a Menu — the dialog is
                            // the one synthesized taps (UI tests, VoiceOver) can open.
                            .confirmationDialog(
                                "Add from library", isPresented: $pickingTemplate,
                                titleVisibility: .visible
                            ) {
                                ForEach(templateChips) { chip in
                                    Button(chip.name) { applyTemplate(chip.id) }
                                }
                            }
                        }
                    }
                } header: {
                    // «What's inside», not «Parcel»: several items ride one order,
                    // and the singular read as a bound that does not exist (author,
                    // 2026-09-14).
                    Text("What's inside")
                } footer: {
                    // The wire requires ≥1 item (live-verified) — the bound states
                    // itself in the section footer, not first on the review sheet
                    // (DesignSystemSemantics → placement rules 3–4). The insurance
                    // sentence moved to the item editor's Value section, which is
                    // the field it explains.
                    if itemRows.isEmpty {
                        Notice(.bound, "At least one item — the order needs a parcel to carry.")
                    }
                }

                // Its own section, per board `4b` — the sender's schema, not a row
                // mixed into the order's mechanics. Absent entirely when no fields
                // are configured: nothing asks for fields nobody defined. A schema
                // that failed to *read* still draws — as the error and its retry.
                if fieldsError != nil || !fieldRows.isEmpty || !hiddenFieldRows.isEmpty {
                    Section {
                        if let fieldsError {
                            // Same read-failure convention as the templates row.
                            VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                                Label(fieldsError, systemSymbol: .exclamationmarkTriangle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button("Retry", action: retryFields)
                                    .font(.footnote)
                            }
                        }
                        ForEach(fieldRows) { row in
                            SchemaFieldRow(row: row, setFieldValue: setFieldValue)
                                .id(row.id)
                        }
                        if !hiddenFieldRows.isEmpty {
                            // A confirmationDialog, not a Menu: the choice is one
                            // of a few named fields — and a Menu inside List never
                            // opens under synthesized taps, so the dialog is also
                            // the version the UI tests can drive.
                            Button {
                                pickingField = true
                            } label: {
                                Label("Add field", systemSymbol: .plus)
                            }
                            .confirmationDialog(
                                "Add field", isPresented: $pickingField,
                                titleVisibility: .visible
                            ) {
                                ForEach(hiddenFieldRows) { row in
                                    Button(row.name) { revealField(row.id) }
                                }
                            }
                        }
                    } header: {
                        Text("Your fields")
                    } footer: {
                        Text("Configured in Settings — they ride the order to history and, where marked, to the courier's paperwork.")
                    }
                }

                Section {
                    // One entrance; the editor opens in canonical order. The When and
                    // Note rows are commented out, not redesigned again: three summary
                    // rows into one shuffling editor made things worse, as the review
                    // said and the author confirmed (Devin, r3999795256; author,
                    // 2026-09-14 — "just comment out those rows"). Their sections
                    // remain reachable inside Options.
                    Button { editOptions(.options) } label: {
                        summaryRow(symbol: .gearshape, title: "Options", value: optionsSummary)
                    }
                    // Button { editOptions(.when) } label: {
                    //     summaryRow(symbol: .clock, title: "When", value: whenSummary)
                    // }
                    // Button { editOptions(.note) } label: {
                    //     summaryRow(
                    //         symbol: .pencilLine,
                    //         title: "Note for the courier",
                    //         value: commentSummary ?? String(localized: "not set")
                    //     )
                    // }
                }
                .buttonStyle(.plain)
            }
            .environment(\.editMode, $editMode)
            .onChange(of: rows.count) {
                // Deleting down to the founding pair hides the Reorder control while
                // edit mode is on — leave it too, or the list is trapped editing with
                // no exit (review, PR #17).
                if rows.count <= 2 { editMode = .inactive }
            }
            .onChange(of: scrollTarget) { _, target in
                // A field door lands on its row — the sheet let go, the card
                // brings the field to center so the bound is seen where it is
                // answered.
                guard let target else { return }
                withAnimation { proxy.scrollTo(target.id, anchor: .center) }
                onScrolled()
            }
            }
        }

        /// Row actions sit apart so a thumb cannot confuse them.
        private static let actionSpacing: CGFloat = 24

        /// The card's own affordances (board `2b`): two points swap; three or more
        /// reorder. Swap stays visible but disabled while an end is empty — unavailable
        /// affordances state themselves rather than vanish (DesignSystem → field rules).
        private var actions: some View {
            HStack(spacing: Self.actionSpacing) {
                if rows.count == 2 {
                    Button(action: swapEnds) {
                        Label("Swap", systemSymbol: .arrowUpArrowDown)
                    }
                    .disabled(!canSwap)
                }
                Button(action: addStop) {
                    Label("Add stop", systemSymbol: .plus)
                }
                if canReorder {
                    Button {
                        withAnimation { editMode = editMode == .active ? .inactive : .active }
                    } label: {
                        Label(
                            editMode == .active ? "Done reordering" : "Reorder",
                            systemSymbol: .arrowUpAndDownTextHorizontal
                        )
                    }
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
            .labelStyle(.titleAndIcon)
        }
    }
}

// MARK: - Route map

extension NewDeliveryView.Content {
    /// The map above the card: chosen points as `2c` marks, the estimated path between
    /// them. An accelerator, never the only route — everything on it is reachable
    /// through the rows below (handoff §8). Tapping a mark opens its callout card
    /// over the map's top edge; the same selection keeps the row highlighted below.
    struct RouteMap: View {
        let pins: [Pin]
        let legs: [[RouteEstimate.Coordinate]]
        @Binding var camera: MapCameraPosition
        /// The open callout — shared with the route rows so pin and row agree.
        @Binding var selection: UUID?
        let canSavePlace: Bool
        let pick: (UUID) -> Void
        let savePlace: (UUID) -> Void

        private static let routeLineWidth: CGFloat = 5
        private static let markShadowRadius: CGFloat = 1.5
        private static let markShadowDrop: CGFloat = 1
        /// A selected mark grows, anchored at its tip — the coordinate stays put.
        private static let selectedScale: CGFloat = 1.3

        var body: some View {
            Map(position: $camera) {
                ForEach(Array(legs.enumerated()), id: \.offset) { _, leg in
                    MapPolyline(coordinates: leg.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    })
                    .stroke(.tint, style: StrokeStyle(lineWidth: Self.routeLineWidth, lineCap: .round))
                }
                ForEach(pins) { pin in
                    Annotation(
                        coordinate: CLLocationCoordinate2D(
                            latitude: pin.latitude,
                            longitude: pin.longitude
                        ),
                        // The teardrop's tip is the coordinate; round marks sit on it.
                        anchor: pin.badge.mapAnchor
                    ) {
                        Button {
                            selection = selection == pin.id ? nil : pin.id
                        } label: {
                            PointBadge(role: pin.badge)
                                .shadow(radius: Self.markShadowRadius, y: Self.markShadowDrop)
                                .scaleEffect(
                                    selection == pin.id ? Self.selectedScale : 1,
                                    anchor: pin.badge.mapAnchor
                                )
                        }
                        .accessibilityLabel(Text(pin.badge.words))
                    } label: {
                        EmptyView()
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if let selection, let pin = pins.first(where: { $0.id == selection }) {
                    callout(for: pin)
                }
            }
            .onAppear {
                if pins.isEmpty { camera = .region(.moscow) }
            }
            .onChange(of: pins) { old, pins in
                // A *geographic* edit reframes the map to the new route — search
                // results and added stops arrive from off-screen and deserve the
                // camera. A contact or parcel edit changes the payload without
                // moving a mark; stealing the sender's zoom for it is rude
                // (review, PR #45).
                let moved = !old.elementsEqual(pins) {
                    $0.id == $1.id && $0.latitude == $1.latitude && $0.longitude == $1.longitude
                }
                if moved { camera = .automatic }
                // The deleted or un-placed point keeps no callout — a card for a pin
                // that no longer exists is a ghost.
                if let selection, !pins.contains(where: { $0.id == selection }) {
                    self.selection = nil
                }
            }
        }

        /// The draft's card (board `4a`): the door chips, the person, and the two
        /// point actions — edit and save-as-place. Tapping the card body is the
        /// same edit the button spells out (the board's tap rule); it opens the
        /// picker and lets the callout go.
        private func callout(for pin: Pin) -> some View {
            PointCallout.Card(
                title: pin.address,
                subtitle: Text(pin.role.calloutVerb) + Text(" · ") + Text("stop \(pin.visitOrdinal)"),
                close: { selection = nil },
                open: {
                    selection = nil
                    pick(pin.id)
                }
            ) {
                PointCallout.DoorChips(parts: pin.parts)
                PointCallout.ContactRow(
                    summary: pin.contactSummary,
                    phone: pin.contactPhone
                )
                PointCallout.ParcelRow(
                    leaving: pin.parcelsLeaving,
                    arriving: pin.parcelsArriving
                )
                HStack(spacing: Self.actionSpacing) {
                    Button("Edit point") {
                        selection = nil
                        pick(pin.id)
                    }
                    if canSavePlace {
                        Button("Save as place") { savePlace(pin.id) }
                    }
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }
        }

        /// The card's two actions sit apart so a thumb cannot confuse them — the
        /// same spacing the route card's action row uses.
        private static let actionSpacing: CGFloat = 24
    }
}

// MARK: - Estimate bar

extension NewDeliveryView.Content {
    /// The route's numbers, on the map's bottom edge: information, never the CTA
    /// (decision #13). Every state keeps the same height — a failure that collapses the
    /// layout would punish exactly the moment that needs calm. Failure is a retry, not
    /// attention (DesignSystem → the `statusAttention` rule).
    struct EstimateBar: View {
        let estimate: NewDeliveryView.Model.Estimate
        let retry: () -> Void

        var body: some View {
            if estimate != .idle {
                HStack(spacing: Layout.Spacing.chip) {
                    switch estimate {
                    case .idle:
                        EmptyView()
                    case .calculating:
                        ProgressView()
                            .controlSize(.small)
                        Text("Estimating the route…")
                            .foregroundStyle(.secondary)
                    case .ready(let estimate):
                        Image(systemSymbol: .arrowTurnUpRight)
                            .foregroundStyle(.secondary)
                        Text(estimate.summary)
                            .fontWeight(.semibold)
                        Text("route estimate")
                            .foregroundStyle(.secondary)
                    case .failed:
                        Image(systemSymbol: .exclamationmarkTriangle)
                            .foregroundStyle(.secondary)
                        Text("Couldn't estimate the route")
                        Button("Retry", action: retry)
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, Layout.Spacing.gutter)
                .frame(minHeight: Layout.MinHeight.bar)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Layout.Radius.bar))
            }
        }
    }
}

// MARK: - Order bar

extension NewDeliveryView.Content {
    /// The one CTA (board `1b`): named and priced once a class is chosen, visibly
    /// waiting otherwise — never confused with the estimate bar above, which informs and
    /// never acts (decision #13). Ordering itself happens behind the review sheet.
    /// The one CTA. Plain values only: it renders a title, and knows nothing about
    /// offer states — the root view reduces those, since deriving them here coupled
    /// the bar to the model's `Offers` (R1; review, PR #22). Never disabled: a blocked
    /// order's title is «Review the order», an enabled door to what is owed (the
    /// drive's dead-CTA finding); the review sheet's confirm button is the gate.
    struct OrderBar: View {
        /// Absent while the bar has no place on screen at all — no route, no prices asked.
        let title: String?
        let openReview: () -> Void

        var body: some View {
            if let title {
                Button(action: openReview) {
                    Text(title)
                }
                .primaryAction()
                .padding(.horizontal, Layout.Spacing.edge)
                .padding(.vertical, Layout.Spacing.unit)
            }
        }
    }
}

// MARK: - Tariff strip

extension NewDeliveryView.Content {
    /// The delivery classes as one horizontal strip (board `1b`, decision #2): an honest
    /// waiting state, a failure that keeps the strip's place, and a signed-out state
    /// that invites rather than errors. The selected card expands to state its bounds —
    /// constraints replace hints (DesignSystem → "Field taxonomy").
    struct TariffStrip: View {
        let offers: NewDeliveryView.Model.Offers
        let selectedID: Offer.ID?
        let select: (Offer.ID) -> Void
        let retry: () -> Void

        var body: some View {
            switch offers {
            case .idle:
                EmptyView()
            case .loading:
                VStack(alignment: .leading, spacing: Layout.Spacing.chip) {
                    HStack(spacing: Layout.Spacing.cards) {
                        ForEach(TariffClass.placeholders, id: \.self) { tariff in
                            TariffCard(
                                emoji: tariff.emoji,
                                name: tariff.words,
                                window: "by 00:00",
                                pickupWindow: nil,
                                limits: nil,
                                priceText: "999 ₽",
                                isSelected: false,
                                select: {}
                            )
                            .redacted(reason: .placeholder)
                        }
                    }
                    Text("Calculating prices…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .ready(let offers) where offers.isEmpty:
                // A successful answer with nothing in it is not a blank strip: the
                // provider priced the route and offered no class for it, which the sender
                // can act on by changing the route or the parcel (review, PR #20).
                HStack(spacing: 8) {
                    Image(systemSymbol: .questionmarkCircle)
                        .foregroundStyle(.secondary)
                    Text("No delivery classes for this route yet")
                    Button("Retry", action: retry)
                }
                .font(.subheadline)
                .frame(minHeight: 88)
            case .ready(let offers):
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Layout.Spacing.cards) {
                        ForEach(offers) { offer in
                            TariffCard(
                                emoji: offer.tariff.emoji,
                                name: offer.tariff.words,
                                window: offer.deliveryByText,
                                pickupWindow: offer.id == selectedID ? offer.pickupByText : nil,
                                limits: offer.id == selectedID ? offer.tariff.limitsSummary : nil,
                                priceText: offer.priceText,
                                isSelected: offer.id == selectedID,
                                select: { select(offer.id) }
                            )
                        }
                    }
                }
            case .failed(let reason):
                HStack(spacing: 8) {
                    Image(systemSymbol: .exclamationmarkTriangle)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Couldn't get prices")
                        Text(reason)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Button("Retry", action: retry)
                }
                .font(.subheadline)
                .frame(minHeight: Layout.MinHeight.strip)
            case .signedOut:
                Text("Add your Yandex Delivery token in Settings to see prices. The route and parcel can be drafted meanwhile.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: Layout.MinHeight.strip)
            }
        }
    }

    /// One class card: emoji and name always; the bounds only when selected — the
    /// expert's compressed strip stays scannable (board `1b`, decision #4).
    struct TariffCard: View {
        let emoji: String
        let name: String
        /// «by 11:45» — the delivery end, the card's second line. Absent when the
        /// wire sent no window.
        let window: String?
        /// «pickup by 11:09» — the selected card's collection end.
        let pickupWindow: String?
        let limits: String?
        let priceText: String
        let isSelected: Bool
        let select: () -> Void

        /// The selected card holds room for its bounds line; the rest compress (board
        /// `1b`). Component-local measures, named rather than inlined.
        private static let selectedMinWidth: CGFloat = 150
        private static let compactMinWidth: CGFloat = 96
        private static let selectionStroke: CGFloat = 2
        private static let hairlineStroke: CGFloat = 0.5

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Button(action: select) {
                VStack(alignment: .leading, spacing: Layout.Spacing.tight) {
                    Text(emoji)
                        .font(.title2)
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let window {
                        Text(window)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    if let pickupWindow {
                        Text(pickupWindow)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let limits {
                        Text(limits)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(priceText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        // «Цены пришли»: the number lands in a strip already being read
                        // (DesignSystem → "Motion"); Reduce Motion gets the instant swap.
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }
                .padding(Layout.Spacing.gutter)
                .frame(minWidth: isSelected ? Self.selectedMinWidth : Self.compactMinWidth, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Layout.Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.Radius.card)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color(.separator),
                            lineWidth: isSelected ? Self.selectionStroke : Self.hairlineStroke
                        )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "\(name), \(window.map { "\($0), " } ?? "")\(priceText)\(pickupWindow.map { ", \($0)" } ?? "")\(limits.map { ", \($0)" } ?? "")"))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

private extension TariffClass {
    /// The skeletons the waiting strip draws — the known classes, redacted.
    static let placeholders: [TariffClass] = [.courier, .express, .cargo]
}

// MARK: - Point row

extension NewDeliveryView.Content {
    /// One stop: the mark, the address (or the invitation to choose one), and the
    /// collapsed contact line (decision #5 — contacts live on the draft, one row per
    /// point). Address and contact are separate targets; the row never truncates an
    /// address (handoff §8 — a wrong address is a failed delivery).
    struct PointRow: View {
        let row: Row
        let pick: () -> Void
        let editContact: () -> Void
        let setRole: (NewDeliveryView.Model.Role) -> Void
        /// The pin's card, opened from the row — the callout is never a
        /// touch-only surface, so a placed row carries a rotor action to it
        /// (board `4a`; review, PR #45). `nil` while the point has no pin.
        var showCallout: (() -> Void)? = nil
        /// «Сохранить как место» on the list's side — a callout action that
        /// exists nowhere else is a bug, so the long-press menu repeats it
        /// (board `4a`). `nil` when the point isn't placed or places can't take it.
        var savePlace: (() -> Void)? = nil

        var body: some View {
            HStack(alignment: .top, spacing: Layout.Spacing.gutter) {
                PointBadge(role: row.badge)
                VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                    Button(action: pick) {
                        Group {
                            if let address = row.address {
                                Text(address) // user data, never a localization key
                                    .foregroundStyle(.primary)
                            } else {
                                Text(row.placeholder)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if let warning = row.addressWarning {
                        Label(warning, systemSymbol: .exclamationmarkTriangle)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }

                    Button(action: editContact) {
                        VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                            if let contactSummary = row.contactSummary {
                                // Concrete `Color.secondary`: the hierarchical style
                                // would resolve against the button's tint and read
                                // as blue.
                                Text(contactSummary)
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondary)
                            } else {
                                Label(row.contactInvitation, systemSymbol: .plus)
                                    .font(.footnote)
                                // Steering, not a gate: prices don't ask who's at
                                // the door — only the order does (author,
                                // 2026-09-18). Fillable upfront all the same.
                                Text("Only the order asks — prices don't.")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.borderless)

                    if let parcelActions = row.parcelActions {
                        Label(parcelActions, systemSymbol: .shippingbox)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .contextMenu {
                ForEach(row.availableRoles, id: \.self) { role in
                    Button {
                        setRole(role)
                    } label: {
                        Label(role.menuLabel, systemSymbol: role.menuSymbol)
                    }
                }
                if let savePlace {
                    Button {
                        savePlace()
                    } label: {
                        Label("Save as place", systemSymbol: .bookmark)
                    }
                }
            }
            .accessibilityActions {
                if let showCallout {
                    Button("Show on map", action: showCallout)
                }
            }
        }
    }
}

extension NewDeliveryView.Model.Role {
    /// The callout header's verb — what the courier does at this door (board `4a`'s
    /// «забрать · первая точка»).
    var calloutVerb: LocalizedStringKey {
        switch self {
        case .pickup: "Pick up"
        case .dropoff: "Deliver"
        case .return: "Return"
        }
    }

    /// The context-menu verb for switching a stop to this role.
    var menuLabel: LocalizedStringKey {
        switch self {
        case .pickup: "Make this the pickup"
        case .dropoff: "Deliver here"
        case .return: "Return leftovers here"
        }
    }

    var menuSymbol: SFSymbol {
        switch self {
        case .pickup: .shippingbox
        case .dropoff: .house
        case .return: .arrowUturnBackward
        }
    }

    /// The empty contact line's invitation, whole — composing it from parts would break
    /// under localization.
    var contactInvitation: LocalizedStringKey {
        switch self {
        case .pickup: "Who hands over — name and phone"
        case .dropoff: "Who receives — name and phone"
        case .return: "Who takes the return — name and phone"
        }
    }
}

extension PointBadge.Role {
    /// The `2c` mapping from a draft row to its mark: the route starts with the ring and
    /// ends with the teardrop; stops between are numbered by position, so the numbers
    /// survive reordering; a return point keeps its own mark wherever it sits.
    init(role: NewDeliveryView.Model.Role, index: Int, isLast: Bool) {
        switch role {
        case .pickup where index == 0: self = .start
        case .pickup: self = .stop(number: index + 1)
        case .return: self = .returnPoint
        case .dropoff where isLast: self = .end
        case .dropoff: self = .stop(number: index + 1)
        }
    }
}

private extension MKCoordinateRegion {
    /// The fallback frame for an empty draft — the picker uses the same anchor.
    static let moscow = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173),
        span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
    )
}

// MARK: - Previews

#Preview("Empty draft") {
    NewDeliveryView.Content(
        rows: [
            .init(
                id: UUID(),
                badge: .start,
                address: nil,
                placeholder: "Where to pick up?",
                contactSummary: nil,
                contactInvitation: "Who hands over — name and phone",
                availableRoles: [],
                isDeletable: false,
                isMovable: false
            ),
            .init(
                id: UUID(),
                badge: .end,
                address: nil,
                placeholder: "Where to deliver?",
                contactSummary: nil,
                contactInvitation: "Who receives — name and phone",
                availableRoles: [],
                isDeletable: false,
                isMovable: true
            ),
        ],
        pins: [],
        estimate: .idle,
        offers: .idle,
        selectedOfferID: nil,
        itemRows: [],
        fieldRows: [],
        hiddenFieldRows: [],
        fieldsError: nil,
        retryFields: {},
        optionsSummary: "to the door",
        whenSummary: "as soon as possible",
        commentSummary: nil,
        canSwap: false,
        canReorder: false,
        pick: { _ in },
        editContact: { _ in },
        savePlace: { _ in },
        canSavePlace: true,
        setRole: { _, _ in },
        swapEnds: {},
        addStop: {},
        removeRows: { _ in },
        moveRows: { _, _ in },
        retryEstimate: {},
        selectOffer: { _ in },
        retryOffers: {},
        openExplainer: {},
        addItem: {},
        editItem: { _ in },
        removeItems: { _ in },
        setFieldValue: { _, _ in },
        revealField: { _ in },
        editOptions: { _ in },
        openReview: {}
    )
}

#Preview("Route complete") {
    let start = UUID()
    let end = UUID()
    return NewDeliveryView.Content(
        rows: [
            .init(
                id: start,
                badge: .start,
                address: "Москва, ул Москворечье, 6",
                placeholder: "Where to pick up?",
                contactSummary: "Иван Петров · +7 912 345-67-89",
                contactInvitation: "Who hands over — name and phone",
                availableRoles: [],
                parcelActions: "picks up Комплект учебников",
                isDeletable: false,
                isMovable: false
            ),
            .init(
                id: end,
                badge: .end,
                address: "Москва, Каширское шоссе, 52",
                placeholder: "Where to deliver?",
                contactSummary: nil,
                contactInvitation: "Who receives — name and phone",
                availableRoles: [],
                parcelActions: "hands over Комплект учебников",
                isDeletable: false,
                isMovable: true
            ),
        ],
        pins: [
            .init(id: start, latitude: 55.646068, longitude: 37.668176, badge: .start,
                  role: .pickup, visitOrdinal: 1,
                  address: "Москва, ул Москворечье, 6",
                  parts: .init(entrance: "А", floor: "3", apartment: "301", intercom: "301К"),
                  contactSummary: "Иван Петров · +7 912 345-67-89",
                  contactPhone: "+79123456789",
                  parcelsLeaving: 2, parcelsArriving: 0),
            .init(id: end, latitude: 55.652212, longitude: 37.648210, badge: .end,
                  role: .dropoff, visitOrdinal: 2,
                  address: "Москва, Каширское шоссе, 52",
                  parts: nil, contactSummary: nil, contactPhone: nil,
                  parcelsLeaving: 0, parcelsArriving: 2),
        ],
        estimate: .ready(RouteEstimate(distanceMeters: 12400, legs: [])),
        offers: .ready([
            Offer(tariff: .courier, price: 749, currency: "RUB", pickupInterval: nil, deliveryInterval: nil, payload: "offer-1"),
            Offer(tariff: .express, price: 1190, currency: "RUB", pickupInterval: nil, deliveryInterval: nil, payload: "offer-2"),
            Offer(tariff: .cargo, price: 3400, currency: "RUB", pickupInterval: nil, deliveryInterval: nil, payload: "offer-3"),
        ]),
        selectedOfferID: "offer-2",
        itemRows: [
            .init(
                id: UUID(),
                name: "Комплект учебников",
                summary: "5 pcs · 2 kg · 25 × 18 × 15 cm · 2 500 ₽",
                misfit: nil,
                journey: "Москва, ул Москворечье, 6 → Москва, Каширское шоссе, 52"
            ),
        ],
        fieldRows: [
            .init(id: UUID(), name: "Заказ", kind: .text, choices: [],
                  isOptional: false, value: "4417"),
            .init(id: UUID(), name: "Тип груза", kind: .choice,
                  choices: ["Документы", "Коробка"], isOptional: true, value: ""),
        ],
        hiddenFieldRows: [
            .init(id: UUID(), name: "Накладная", kind: .text, choices: [],
                  isOptional: true, value: ""),
        ],
        fieldsError: nil,
        retryFields: {},
        optionsSummary: "pro courier · to the door",
        whenSummary: "as soon as possible",
        commentSummary: nil,
        canSwap: true,
        canReorder: false,
        pick: { _ in },
        editContact: { _ in },
        savePlace: { _ in },
        canSavePlace: true,
        setRole: { _, _ in },
        swapEnds: {},
        addStop: {},
        removeRows: { _ in },
        moveRows: { _, _ in },
        retryEstimate: {},
        selectOffer: { _ in },
        retryOffers: {},
        openExplainer: {},
        addItem: {},
        editItem: { _ in },
        removeItems: { _ in },
        // The library's chips — pinned leads; the row menu is the second door
        // to «Save as template».
        templateChips: [
            .init(id: UUID(), name: "Учебники"),
            .init(id: UUID(), name: "Документы"),
        ],
        saveTemplateItem: { _ in },
        setFieldValue: { _, _ in },
        revealField: { _ in },
        editOptions: { _ in },
        openReview: {}
    )
}

#Preview("Tariff strip: waiting, priced, failed, signed out") {
    List {
        NewDeliveryView.Content.TariffStrip(
            offers: .loading, selectedID: nil, select: { _ in }, retry: {}
        )
        NewDeliveryView.Content.TariffStrip(
            offers: .ready([
                Offer(tariff: .courier, price: 749, currency: "RUB", pickupInterval: nil, deliveryInterval: nil, payload: "offer-1"),
                Offer(tariff: .express, price: 1190, currency: "RUB", pickupInterval: nil, deliveryInterval: nil, payload: "offer-2"),
                Offer(tariff: .cargo, price: 3400, currency: "RUB", pickupInterval: nil, deliveryInterval: nil, payload: "offer-3"),
            ]),
            selectedID: "offer-1",
            select: { _ in },
            retry: {}
        )
        NewDeliveryView.Content.TariffStrip(
            offers: .ready([]), selectedID: nil, select: { _ in }, retry: {}
        )
        NewDeliveryView.Content.TariffStrip(
            offers: .failed("Parse error: missing required field 'items'"), selectedID: nil, select: { _ in }, retry: {}
        )
        NewDeliveryView.Content.TariffStrip(
            offers: .signedOut, selectedID: nil, select: { _ in }, retry: {}
        )
    }
}

#Preview("Estimate bar: every state keeps its height") {
    VStack(spacing: 12) {
        NewDeliveryView.Content.EstimateBar(estimate: .calculating, retry: {})
        NewDeliveryView.Content.EstimateBar(
            estimate: .ready(RouteEstimate(distanceMeters: 12400, legs: [])),
            retry: {}
        )
        NewDeliveryView.Content.EstimateBar(estimate: .failed, retry: {})
    }
    .padding()
}

#Preview("Route map: pins framed") {
    @Previewable @State var camera = MapCameraPosition.automatic
    @Previewable @State var selection: UUID?
    NewDeliveryView.Content.RouteMap(
        pins: [
            .init(id: UUID(), latitude: 55.646068, longitude: 37.668176, badge: .start,
                  role: .pickup, visitOrdinal: 1,
                  address: "Москва, ул Москворечье, 6",
                  parts: .init(entrance: "А", floor: "3", apartment: "301", intercom: "301К"),
                  contactSummary: "Иван Петров · +7 912 345-67-89",
                  contactPhone: "+79123456789",
                  parcelsLeaving: 3, parcelsArriving: 0),
            .init(id: UUID(), latitude: 55.749917, longitude: 37.593450, badge: .stop(number: 2),
                  role: .dropoff, visitOrdinal: 2,
                  address: "Москва, Арбат, 10",
                  parts: nil, contactSummary: nil, contactPhone: nil,
                  parcelsLeaving: 0, parcelsArriving: 1),
            .init(id: UUID(), latitude: 55.652212, longitude: 37.648210, badge: .end,
                  role: .dropoff, visitOrdinal: 3,
                  address: "Москва, Каширское шоссе, 52",
                  parts: .init(entrance: "2", apartment: "15"),
                  contactSummary: "Анна Сидорова · +7 998 765-43-21",
                  contactPhone: "+79987654321",
                  parcelsLeaving: 0, parcelsArriving: 2),
        ],
        legs: [[
            .init(latitude: 55.646068, longitude: 37.668176),
            .init(latitude: 55.700000, longitude: 37.630000),
            .init(latitude: 55.749917, longitude: 37.593450),
        ]],
        camera: $camera,
        selection: $selection,
        canSavePlace: true,
        pick: { _ in },
        savePlace: { _ in }
    )
}

#Preview("Tariff card: selected shows its bounds, unselected stays scannable") {
    HStack(alignment: .top, spacing: Layout.Spacing.gutter) {
        NewDeliveryView.Content.TariffCard(
            emoji: "🛵",
            name: "Courier",
            window: "by 11:45",
            pickupWindow: "pickup by 11:09",
            limits: "Up to 10 kg · 80 × 50 × 50 cm",
            priceText: "749 ₽",
            isSelected: true,
            select: {}
        )
        NewDeliveryView.Content.TariffCard(
            emoji: "🚚",
            name: "Cargo",
            window: "by 15:00",
            pickupWindow: nil,
            limits: nil,
            priceText: "3 480 ₽",
            isSelected: false,
            select: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Field rows: required unmet, choice unset, answered quiet") {
    List {
        Section("Your fields") {
            NewDeliveryView.Content.SchemaFieldRow(
                row: .init(id: UUID(), name: "Заказ", kind: .text, choices: [],
                           isOptional: false, value: ""),
                setFieldValue: { _, _ in }
            )
            NewDeliveryView.Content.SchemaFieldRow(
                row: .init(id: UUID(), name: "Тип груза", kind: .choice,
                           choices: ["Документы", "Коробка"], isOptional: false, value: ""),
                setFieldValue: { _, _ in }
            )
            NewDeliveryView.Content.SchemaFieldRow(
                row: .init(id: UUID(), name: "Тип груза", kind: .choice,
                           choices: ["Документы", "Коробка"], isOptional: true, value: ""),
                setFieldValue: { _, _ in }
            )
            NewDeliveryView.Content.SchemaFieldRow(
                row: .init(id: UUID(), name: "Заказ", kind: .text, choices: [],
                           isOptional: false, value: "4417"),
                setFieldValue: { _, _ in }
            )
        }
    }
}

#Preview("Point rows: empty, warned, with the parcel's verbs") {
    List {
        NewDeliveryView.Content.PointRow(
            row: .init(
                id: UUID(),
                badge: .stop(number: 2),
                address: nil,
                placeholder: "Where to deliver?",
                contactSummary: nil,
                contactInvitation: "Who receives — name and phone",
                availableRoles: [.return],
                isDeletable: true,
                isMovable: true
            ),
            pick: {},
            editContact: {},
            setRole: { _ in }
        )
        NewDeliveryView.Content.PointRow(
            row: .init(
                id: UUID(),
                badge: .stop(number: 3),
                address: "Москва, Красная площадь",
                placeholder: "Where to deliver?",
                contactSummary: nil,
                contactInvitation: "Who receives — name and phone",
                availableRoles: [.return],
                addressWarning: "No building number — the courier may have trouble finding the door.",
                isDeletable: true,
                isMovable: true
            ),
            pick: {},
            editContact: {},
            setRole: { _ in }
        )
        NewDeliveryView.Content.PointRow(
            row: .init(
                id: UUID(),
                badge: .end,
                address: "Москва, Каширское шоссе, 52",
                placeholder: "Where to deliver?",
                contactSummary: "Анна Сидорова · +7 998 765-43-21",
                contactInvitation: "Who receives — name and phone",
                availableRoles: [],
                parcelActions: "hands over Комплект учебников and Документы",
                isDeletable: true,
                isMovable: true
            ),
            pick: {},
            editContact: {},
            setRole: { _ in }
        )
    }
}

#Preview("Order bar: hidden while no prices were asked") {
    NewDeliveryView.Content.OrderBar(title: nil, openReview: {})
}

#Preview("Order bar: blocked — names its destination") {
    NewDeliveryView.Content.OrderBar(title: "Review the order", openReview: {})
}

#Preview("Order bar: ready") {
    NewDeliveryView.Content.OrderBar(title: "Order Express · 1 190 ₽", openReview: {})
}
