import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension DeliveriesView {
    /// Pure presentation: the orders the device remembers on two shelves — what is
    /// happening and what happened — or one of two genuinely different empty states,
    /// so the branch is structure rather than show/hide of the same view (R9). The
    /// screen's one standing action — the prominent compose button (Design → "The
    /// tab bar goes") — stays available signed-out: a route can be drafted before a
    /// token exists; only pricing and ordering need the session. It steps aside while
    /// the sender searches: a search is a read (author, 2026-09-29).
    struct Content: View {
        /// The two shelves. Live orders first — the ones that can still change.
        struct Section: Identifiable {
            enum Shelf { case live, past }
            let id: Shelf
            let rows: [Row]
        }

        /// One remembered order, reduced to its row. The row leads with *when it was
        /// ordered*; the status carries its own *as of* — the two times never share
        /// a line, so neither is mistaken for the other (author, 2026-09-29).
        struct Row: Identifiable {
            let id: UUID
            let status: OrderStatus
            /// The provider's as-of stamp — sits with the status, never with the date.
            let statusObservedAt: Date?
            let createdText: String
            /// Where the parcel goes — the last drop-off (YD-15), compacted.
            let destinationText: String
            /// Where it left from, when the route has a distinct origin; `nil` for a
            /// thin synced claim with a single point.
            let originText: String?
            /// Stops between origin and destination — «+2» on the line, drawn in
            /// full only when the row expands.
            let middleStops: Int
            let priceText: String?
            /// The whole route — the expanded row's `RouteLine`, contacts and door
            /// chips included (board `3e`).
            let route: [RoutePoint]
            /// What typing in the search field can hit — addresses, contacts, the
            /// status in the sender's words, and «Ваши поля» values, precomputed on
            /// the root's side (board `4b`).
            var searchableText: String = ""
        }

        let isSignedIn: Bool
        let sections: [Section]
        /// The row whose provider trail is open, if any — one at a time.
        var expandedID: UUID? = nil
        /// The open row's trail: `nil` while the read is in flight.
        var trail: [ProviderEvent]? = nil
        /// Why the open row's trail could not be read — rendered instead of the
        /// trail, never as «nothing reported».
        var trailError: String? = nil
        /// Why history is missing, when it is missing for a reason rather than because
        /// nothing was sent. An unreadable store rendered as "No deliveries yet", which
        /// tells a sender with a year of orders that they have none (review, PR #22).
        var historyUnavailable: String? = nil
        /// Why the rows may be stale — a sync failure renders beside history, never
        /// instead of it: what the device remembers is still worth reading.
        var syncError: String? = nil
        /// The pull-to-refresh ask — the root forwards it to the sync engine.
        var refresh: () async -> Void = {}
        let compose: () -> Void
        /// «Повторить»/«Наоборот» — the row's order id and whether the route runs
        /// backwards; the root turns it into a pre-filled draft (board `3e`).
        var repeatOrder: (Row.ID, _ reversed: Bool) -> Void = { _, _ in }
        /// Open or close a row's provider trail — the status line's tap.
        var toggleTrail: (Row.ID) -> Void = { _ in }

        @State private var searchText = ""
        @State private var isSearchPresented = false

        private var rows: [Row] { sections.flatMap(\.rows) }

        /// The typed filter — addresses, people, status words and field values,
        /// case-insensitive. A shelf with no hits leaves the list.
        private var visibleSections: [Section] {
            let query = searchText.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return sections }
            return sections
                .map { Section(id: $0.id, rows: $0.rows.filter {
                    $0.searchableText.localizedCaseInsensitiveContains(query)
                }) }
                .filter { !$0.rows.isEmpty }
        }

        var body: some View {
            Group {
                if !rows.isEmpty {
                    List {
                        ForEach(visibleSections) { section in
                            SwiftUI.Section {
                                ForEach(section.rows) { row in
                                    NavigationLink(value: row.id) {
                                        OrderRow(
                                            row: row,
                                            isExpanded: expandedID == row.id,
                                            trail: expandedID == row.id ? trail : nil,
                                            trailError: expandedID == row.id ? trailError : nil,
                                            toggleTrail: { toggleTrail(row.id) }
                                        )
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button {
                                            repeatOrder(row.id, false)
                                        } label: {
                                            Label("Repeat", systemSymbol: .arrowClockwise)
                                        }
                                        Button {
                                            repeatOrder(row.id, true)
                                        } label: {
                                            Label("Reverse", systemSymbol: .arrowUturnLeft)
                                        }
                                        .tint(.gray)
                                    }
                                }
                            } header: {
                                Text(section.id.title)
                            }
                        }
                        if let syncError {
                            Text(syncError)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .refreshable { await refresh() }
                    .searchable(text: $searchText, isPresented: $isSearchPresented,
                                prompt: "Address, person, status or your field")
                    .animation(.default, value: expandedID)
                } else if let historyUnavailable {
                    // Checked before the empty states: *could not look* is not *nothing
                    // there*, and only this branch knows the difference.
                    ContentUnavailableView {
                        Label("Deliveries can't be read", systemSymbol: .exclamationmarkTriangle)
                    } description: {
                        Text(historyUnavailable)
                    }
                } else if !isSignedIn {
                    ContentUnavailableView {
                        Label("Sign in to start", systemSymbol: .key)
                    } description: {
                        Text("Add your Yandex Delivery OAuth token in Settings.")
                    }
                } else if let syncError {
                    // The wire version of the branch above: a failed first sync on an
                    // empty store must not wear the "No deliveries yet" face — *could
                    // not check* is not *nothing there* (review, PR #35).
                    ContentUnavailableView {
                        Label("Deliveries can't be checked", systemSymbol: .exclamationmarkTriangle)
                    } description: {
                        Text(syncError)
                    } actions: {
                        Button("Try again") { Task { await refresh() } }
                    }
                } else {
                    ContentUnavailableView {
                        Label("No deliveries yet", systemSymbol: .shippingbox)
                    } description: {
                        Text("Orders you create will appear here, and stay here.")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isSearchPresented {
                    Button(action: compose) {
                        Label("New Delivery", systemSymbol: .plus)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                    .padding(.bottom, Layout.Spacing.unit)
                }
            }
        }
    }
}

extension DeliveriesView.Content.Section.Shelf {
    /// The shelf's heading — the sender's words for the split, not the status names.
    var title: LocalizedStringKey {
        switch self {
        case .live: "In progress"
        case .past: "History"
        }
    }
}

extension DeliveriesView.Content {
    /// The history row, collapsed: the order date and the price on the first line,
    /// the route as «from → to» on the second, the status — with its own as-of time —
    /// on the third. Three lines, eight rows to a screen, and what differs between
    /// orders is what the eye lands on. The status line is the trail's door: tapping
    /// it opens the provider's account of this order in place; the rest of the row
    /// still opens the order (review, 2026-09-29 — the row's centre used to open
    /// nothing at all).
    struct OrderRow: View {
        let row: Row
        let isExpanded: Bool
        /// The trail while this row is open — `nil` still loading, `[]` nothing
        /// reported; ignored while collapsed.
        let trail: [ProviderEvent]?
        /// A read that failed — its own row, so a storage error never reads as a
        /// fact about the provider's history.
        var trailError: String? = nil
        let toggleTrail: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Layout.Spacing.chip) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.createdText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let priceText = row.priceText {
                        Text(priceText)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                routeLine
                statusLine
                if isExpanded {
                    expandedBody
                }
            }
            .padding(.vertical, Layout.Spacing.tight)
        }

        /// «from → to», the destination in the primary weight, middles counted.
        /// When the line is short of room the *origin* gives way — the destination
        /// is the fact the row exists to show, so it keeps its whole name.
        private var routeLine: some View {
            HStack(spacing: Layout.Spacing.tight) {
                if let origin = row.originText {
                    Text(origin)
                        .foregroundStyle(.secondary)
                        .truncationMode(.tail)
                    Text(Self.routeArrow)
                        .foregroundStyle(.tertiary)
                    if row.middleStops > 0 {
                        Text("+\(row.middleStops)")
                            .foregroundStyle(.secondary)
                        Text(Self.routeArrow)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(row.destinationText)
                    .fontWeight(.medium)
                    .layoutPriority(1)
            }
            .font(.subheadline)
            .lineLimit(1)
        }

        /// The status chip with its as-of time and the disclosure mark. A tap
        /// gesture on the line, not a `Button`: inside a `List` row that is itself a
        /// `NavigationLink`, a button — even borderless — competes with the row
        /// for the whole cell and fires on row taps; a gesture claims only the
        /// pixels under the pill (exactly the behaviour `RouteLine` had to *lose*,
        /// Kit #27, and here the small footprint is what makes it right). Taps
        /// anywhere else on the row still follow the link.
        private var statusLine: some View {
            HStack(spacing: Layout.Spacing.unit) {
                StatusChip(status: row.status)
                if let at = row.statusObservedAt {
                    Text(at, format: .dateTime.hour().minute())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Image(systemSymbol: .chevronDown)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleTrail)
            // VoiceOver: one element that says the status and its time, acts as a
            // button, and tells what the tap does.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? Text("Hides status history") : Text("Shows status history"))
            .accessibilityAction(named: Text("Toggle status history"), toggleTrail)
        }

        /// The whole route with its people, then the provider's trail — what the
        /// collapsed row summarised, in full. Loading and nothing-reported are
        /// different rows (R9).
        @ViewBuilder
        private var expandedBody: some View {
            RouteLine(points: row.route)
                .font(.subheadline)
                .padding(.top, Layout.Spacing.tight)
            if let trailError {
                Label(trailError, systemSymbol: .exclamationmarkTriangle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let trail {
                if trail.isEmpty {
                    Text("The provider has not reported on this order yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    StatusTimeline(events: trail)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }

        private static let routeArrow = "→"
    }
}

#if DEBUG
private extension DeliveriesView.Content.Row {
    static func fixture(
        status: OrderStatus, created: String, origin: String?, destination: String,
        middles: Int = 0, price: String?, observed: Date? = nil,
        route: [RoutePoint] = []
    ) -> Self {
        .init(id: UUID(), status: status, statusObservedAt: observed, createdText: created,
              destinationText: destination, originText: origin, middleStops: middles,
              priceText: price, route: route)
    }
}

private let previewRoute = [
    RoutePoint(latitude: 55.7137, longitude: 37.6323, address: "Москва, ул Москворечье, 6",
               contactName: "Иван Петров", contactPhone: "+79123456789"),
    RoutePoint(latitude: 55.7133, longitude: 37.5856, address: "Москва, Каширское шоссе, 52",
               contactName: "Анна Сидорова"),
]

private let previewSections: [DeliveriesView.Content.Section] = [
    .init(id: .live, rows: [
        .fixture(status: .active, created: "15 Jan, 11:00", origin: "ул Москворечье, 6",
                 destination: "Каширское шоссе, 52", price: "1 767,78 ₽",
                 observed: .init(timeIntervalSince1970: 1_800_002_400), route: previewRoute),
        .fixture(status: .searching, created: "15 Jan, 10:12", origin: "Невский проспект, 100",
                 destination: "Арбат, 10", middles: 1, price: "3 400 ₽"),
        .fixture(status: .attention, created: "14 Jan, 07:13", origin: "Никольская, 10",
                 destination: "Пятницкая, 25", price: "890 ₽",
                 observed: .init(timeIntervalSince1970: 1_799_950_000)),
    ]),
    .init(id: .past, rows: [
        .fixture(status: .done, created: "4 Sep", origin: "Тверская, 1", destination: "Арбат, 10",
                 price: "3 400 ₽"),
        .fixture(status: .cancelled, created: "3 Jan, 21:13", origin: "Новослободская, 3",
                 destination: "Тверская-Ямская, 12", price: "1 240 ₽"),
    ]),
]

#Preview("Two shelves") {
    NavigationStack {
        DeliveriesView.Content(isSignedIn: true, sections: previewSections, compose: {})
    }
}

#Preview("A row opened — trail loaded") {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let live = previewSections[0].rows[0]
    NavigationStack {
        DeliveriesView.Content(
            isSignedIn: true, sections: previewSections, expandedID: live.id,
            trail: [
                ProviderEvent(orderID: live.id, providerEventID: 1, at: t0, kind: "status", providerStatus: "accepted", source: "journal"),
                ProviderEvent(orderID: live.id, providerEventID: 2, at: t0 + 420, kind: "status", providerStatus: "performer_found", source: "journal"),
                ProviderEvent(orderID: live.id, providerEventID: 3, at: t0 + 1_200, kind: "status", providerStatus: "pickuped", source: "journal"),
            ],
            compose: {})
    }
}

#Preview("A row opened — trail loading") {
    NavigationStack {
        DeliveriesView.Content(
            isSignedIn: true, sections: previewSections,
            expandedID: previewSections[1].rows[0].id, trail: nil, compose: {})
    }
}

#Preview("A row opened — the read failed") {
    NavigationStack {
        DeliveriesView.Content(
            isSignedIn: true, sections: previewSections,
            expandedID: previewSections[0].rows[2].id, trail: nil,
            trailError: "Shared storage is unavailable on this install.", compose: {})
    }
}

#Preview("A row opened — nothing reported") {
    NavigationStack {
        DeliveriesView.Content(
            isSignedIn: true, sections: previewSections,
            expandedID: previewSections[0].rows[1].id, trail: [], compose: {})
    }
}

#Preview("Signed in, empty") {
    DeliveriesView.Content(isSignedIn: true, sections: [], compose: {})
}

#Preview("Sync failed, empty") {
    DeliveriesView.Content(
        isSignedIn: true, sections: [],
        syncError: "The provider could not be reached.", compose: {})
}

#Preview("Signed out") {
    DeliveriesView.Content(isSignedIn: false, sections: [], compose: {})
}
#endif
