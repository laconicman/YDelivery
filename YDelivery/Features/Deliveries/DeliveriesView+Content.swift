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
            enum Shelf { case live, past, archived }
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
            /// When the order was placed — the sorts need the value itself; the
            /// line shows `createdText`.
            let created: Date
            let createdText: String
            /// The with-VAT total as a number — «Price, high first» sorts on it;
            /// the line shows `priceText`. `nil` when the provider never priced.
            let price: Decimal?
            /// Where the parcel goes — the last drop-off (YD-15), compacted.
            let destinationText: String
            /// Where it left from, when the route has a distinct origin; `nil` for a
            /// thin synced claim with a single point.
            let originText: String?
            /// Stops between origin and destination — «+2» on the line, drawn in
            /// full only when the row expands.
            let middleStops: Int
            /// Which wait a `.attention` row is — the provider's own phrase
            /// («Waiting for your approval», «Ended before delivery»), so the
            /// collapsed chip's one word never stands in for six different
            /// decisions (the drive's D2: seven refused claims read "Not
            /// delivered" though nothing was ever dispatched). `nil` for the
            /// statuses whose chip already tells the whole truth.
            var statusDetail: String? = nil
            let priceText: String?
            /// The whole route — the expanded row's `RouteLine`, contacts and door
            /// chips included (board `3e`).
            let route: [RoutePoint]
            /// Shelved on the owner's say-so — every filter but «Archived»
            /// hides the row (Design → "History is kept, not deleted").
            var isArchived: Bool = false
            /// The shelf door opens only for a finished row — `!status.isLive`,
            /// plus an attention row whose provider word ended the claim
            /// (`Order.isTerminalAttention`), the same line the Kit draws
            /// before it would refuse.
            var canArchive: Bool = false
            /// What typing in the search field can hit — addresses, contacts, the
            /// status in the sender's words, and «Ваши поля» values, precomputed on
            /// the root's side (board `4b`).
            var searchableText: String = ""
        }

        let isSignedIn: Bool
        /// The shelves *after* the toolbar's picks and the search — the root runs
        /// `Model.visible` and hands the answer down; this view never filters.
        let sections: [Section]
        /// Whether any rows exist at all — the pick that empties the list must
        /// not wear an empty history's face, and only the root knows the count.
        var hasAnyRows = false
        /// The toolbar's sort and show picks and the typed query — bindings, so
        /// the menu writes back to the root's storage (and the storage persists).
        var sort: Binding<HistorySort> = .constant(.newestFirst)
        var filter: Binding<HistoryFilter> = .constant(.all)
        var searchText: Binding<String> = .constant("")
        /// The row whose provider trail is open, if any — one at a time.
        var expandedID: UUID? = nil
        /// The row whose trail is being read — its tap is answered with a
        /// spinner in place of the chevron while the open is pending.
        var pendingID: UUID? = nil
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
        /// Why the last archive gesture refused, when it did — a tried-and-failed
        /// action renders as a notice row, never as silence (the swipe dismissed
        /// itself before the store answered).
        var actionError: String? = nil
        /// The pull-to-refresh ask — the root forwards it to the sync engine.
        var refresh: () async -> Void = {}
        let compose: () -> Void
        /// «Повторить»/«Наоборот» — the row's order id and whether the route runs
        /// backwards; the root turns it into a pre-filled draft (board `3e`).
        var repeatOrder: (Row.ID, _ reversed: Bool) -> Void = { _, _ in }
        /// Open or close a row's provider trail — the status line's tap.
        var toggleTrail: (Row.ID) -> Void = { _ in }
        /// Shelve a finished row — no confirmation, the shelf is reversible.
        var archive: (Row.ID) -> Void = { _ in }
        /// Bring a shelved row back — the same door from the other side.
        var unarchive: (Row.ID) -> Void = { _ in }

        @State private var isSearchPresented = false

        private var rows: [Row] { sections.flatMap(\.rows) }

        /// «Повторить»/«Наоборот» — shared by the order row and its trail row:
        /// the trail is the same order's continuation, so its swipe offers the
        /// same doors.
        @ViewBuilder
        private func orderActions(for id: Row.ID) -> some View {
            Button {
                repeatOrder(id, false)
            } label: {
                Label("Repeat", systemSymbol: .arrowClockwise)
            }
            Button {
                repeatOrder(id, true)
            } label: {
                Label("Reverse", systemSymbol: .arrowUturnLeft)
            }
            .tint(.gray)
        }

        /// The shelf door, shared by the leading swipe and the context menu —
        /// Unarchive for a shelved row, Archive for a finished one, nothing for
        /// a row still moving (the Kit would refuse it anyway; the door simply
        /// isn't offered). Reversible, so no confirmation is asked.
        @ViewBuilder
        private func shelfAction(for row: Row) -> some View {
            if row.isArchived {
                Button {
                    unarchive(row.id)
                } label: {
                    Label("Unarchive", systemSymbol: .trayAndArrowUp)
                }
            } else if row.canArchive {
                Button {
                    archive(row.id)
                } label: {
                    Label("Archive", systemSymbol: .archivebox)
                }
            }
        }

        var body: some View {
            Group {
                if !rows.isEmpty {
                    List {
                        if let actionError {
                            Notice(.error, actionError)
                                .font(.footnote)
                                .listRowSeparator(.hidden)
                        }
                        ForEach(sections) { section in
                            SwiftUI.Section {
                                ForEach(section.rows) { row in
                                    let expanded = expandedID == row.id
                                    NavigationLink(value: row.id) {
                                        OrderRow(
                                            row: row,
                                            isExpanded: expanded,
                                            isOpening: expandedID != row.id && pendingID == row.id,
                                            toggleTrail: { toggleTrail(row.id) }
                                        )
                                    }
                                    // The open pair reads as one card: no line
                                    // between the order row and its trail.
                                    .listRowSeparator(expanded ? .hidden : .automatic,
                                                      edges: .bottom)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        orderActions(for: row.id)
                                    }
                                    .swipeActions(edge: .leading) {
                                        shelfAction(for: row)
                                    }
                                    .contextMenu {
                                        shelfAction(for: row)
                                    }
                                    if expanded {
                                        // The trail is a row of its own, not
                                        // extra height inside `OrderRow`: the
                                        // List animates row insertion natively
                                        // — the new cell slides in pushing the
                                        // rows below — while an in-row growth
                                        // gets its frame centre-interpolated by
                                        // the cell host and the collapsed lines
                                        // float mid-cell under the fading route
                                        // (PR #109's 60 fps captures).
                                        TrailRow(route: row.route, trail: trail,
                                                 trailError: trailError)
                                            .listRowSeparator(.hidden, edges: .top)
                                            // Same order, same doors.
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                orderActions(for: row.id)
                                            }
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
                } else if let historyUnavailable {
                    // Checked before the filtered-empty and the empty states:
                    // *could not look* outranks *nothing matched* — even when
                    // cached rows exist but the picks hid them all (review,
                    // PR #118).
                    ContentUnavailableView {
                        Label("Deliveries can't be read", systemSymbol: .exclamationmarkTriangle)
                    } description: {
                        Text(historyUnavailable)
                    }
                } else if hasAnyRows, filter.wrappedValue == .archived,
                          searchText.wrappedValue.isEmpty {
                    // The shelf, empty — its own words, not «Nothing to show»
                    // (a typed query still gets the generic no-match face).
                    ContentUnavailableView {
                        Label("Nothing archived yet", systemSymbol: .archivebox)
                    } description: {
                        Text("Finished deliveries you shelve wait here.")
                    }
                } else if hasAnyRows {
                    // Rows exist and none survive the picks — a filtered-empty
                    // state, not an empty history. Name what hid them: a typed
                    // query gets its «Clear search», a status pick its «Show
                    // everything»; both when both.
                    ContentUnavailableView {
                        Label("Nothing to show", systemSymbol: .line3HorizontalDecreaseCircle)
                    } description: {
                        if !searchText.wrappedValue.isEmpty {
                            Text("Nothing matches “\(searchText.wrappedValue)”.")
                        } else {
                            Text("Change the filter or clear the search.")
                        }
                    } actions: {
                        if !searchText.wrappedValue.isEmpty {
                            Button("Clear search") { searchText.wrappedValue = "" }
                        }
                        if filter.wrappedValue != .all {
                            Button("Show everything") { filter.wrappedValue = .all }
                        }
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
            // On the Group, not the List: a query that matches nothing must
            // keep its field — otherwise it cannot be cleared (review, PR #118).
            .searchable(text: searchText, isPresented: $isSearchPresented,
                        prompt: "Address, person, status or your field")
            .safeAreaInset(edge: .bottom) {
                if !isSearchPresented {
                    Button(action: compose) {
                        Label("New Delivery", systemSymbol: .plus)
                    }
                    .primaryAction()
                    .padding(.horizontal)
                    .padding(.bottom, Layout.Spacing.unit)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // One menu for the two list picks; the glyph fills while a
                    // status filter stands, so an active filter shows at a glance.
                    Menu {
                        Picker("Sort", selection: sort) {
                            ForEach(HistorySort.allCases, id: \.self) {
                                Text($0.words).tag($0)
                            }
                        }
                        Picker("Show", selection: filter) {
                            ForEach(HistoryFilter.allCases, id: \.self) {
                                Text($0.words).tag($0)
                            }
                        }
                    } label: {
                        Label("Sort and filter", systemSymbol: .line3HorizontalDecreaseCircle)
                            .symbolVariant(filter.wrappedValue == .all ? .none : .fill)
                    }
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
        case .archived: "Archived"
        }
    }
}

extension DeliveriesView.Content {
    /// The history row, collapsed: the order date and the price on the first line,
    /// the route as «from → to» on the second, the status — with its own as-of time —
    /// on the third. Three lines, eight rows to a screen, and what differs between
    /// orders is what the eye lands on. The status line is the trail's door: tapping
    /// it opens the provider's account of this order as the row that slides in
    /// beneath; the rest of the row still opens the order (review, 2026-09-29 —
    /// the row's centre used to open nothing at all).
    struct OrderRow: View {
        let row: Row
        /// Drives only the disclosure chevron and the a11y hint — the trail
        /// itself is a `TrailRow` emitted beside this row.
        let isExpanded: Bool
        /// The tap landed and the read is still out — the chevron swaps for a
        /// spinner so a slow trail read never leaves the tap unanswered.
        var isOpening = false
        let toggleTrail: () -> Void

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

        /// The status chip, then the trailing group — as-of stamp last but one,
        /// disclosure mark at the edge (semantics rule 7: the stamp trails).
        /// The whole line is the trail's door: a tap gesture, not a `Button`,
        /// because inside a `List` row that is itself a `NavigationLink` a button —
        /// even borderless — competes with the row for the whole cell and fires on
        /// row taps; a gesture claims only the pixels under the line (exactly the
        /// behaviour `RouteLine` had to *lose*, Kit #27). The line is deliberately
        /// full-width — a wider target than the pill alone, and the stamp's tail
        /// space is claimed by design rather than left blank (owner's call, review
        /// of PR #109). Taps anywhere else on the row still follow the link.
        private var statusLine: some View {
            HStack(spacing: Layout.Spacing.unit) {
                StatusChip(status: row.status)
                if let statusDetail = row.statusDetail {
                    Text(statusDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Layout.Spacing.unit)
                if let at = row.statusObservedAt {
                    Text(at, format: .dateTime.hour().minute())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if isOpening {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemSymbol: .chevronDown)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(reduceMotion ? nil : .default, value: isExpanded)
                }
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

        private static let routeArrow = "→"
    }

    /// The open order's provider trail as a row of its own, emitted right under
    /// its `OrderRow`. It is a row — not extra height inside the order row —
    /// because the List animates row insertion natively (the new cell slides in
    /// and pushes the rows below) while an in-row growth has its frame
    /// centre-interpolated by the cell host, leaving the collapsed lines
    /// floating mid-cell mid-animation. Plain values, no NavigationLink:
    /// tapping it does nothing — the order row above opens the order.
    struct TrailRow: View {
        let route: [RoutePoint]
        /// `nil` still loading, `[]` nothing reported.
        let trail: [ProviderEvent]?
        /// A read that failed — its own row, so a storage error never reads as a
        /// fact about the provider's history.
        var trailError: String? = nil

        /// The whole route with its people, then the provider's trail — what the
        /// collapsed row summarised, in full. Loading and nothing-reported are
        /// different rows (R9).
        var body: some View {
            VStack(alignment: .leading, spacing: Layout.Spacing.chip) {
                RouteLine(points: route)
                    .font(.subheadline)
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
            .padding(.vertical, Layout.Spacing.tight)
        }
    }
}

#if DEBUG
private extension DeliveriesView.Content.Row {
    /// Preview rows carry the same facts the real row does — a `Date` and a
    /// `Decimal` — and wear the text production would derive, so a sort or a
    /// format change shows up here first.
    static func fixture(
        status: OrderStatus, created: Date, origin: String?, destination: String,
        middles: Int = 0, price: Decimal? = nil, observed: Date? = nil,
        detail: String? = nil, route: [RoutePoint] = [], archived: Bool = false
    ) -> Self {
        .init(id: UUID(), status: status, statusObservedAt: observed,
              created: created,
              createdText: created.formatted(date: .abbreviated, time: .shortened),
              price: price,
              destinationText: destination, originText: origin, middleStops: middles,
              statusDetail: detail,
              priceText: price.map {
                  $0.formatted(.currency(code: "RUB").precision(.fractionLength(0...2)))
              },
              route: route,
              isArchived: archived, canArchive: !status.isLive)
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
        .fixture(status: .active, created: .init(timeIntervalSince1970: 1_800_039_600),
                 origin: "ул Москворечье, 6",
                 destination: "Каширское шоссе, 52", price: 1767.78,
                 observed: .init(timeIntervalSince1970: 1_800_042_000), route: previewRoute),
        .fixture(status: .searching, created: .init(timeIntervalSince1970: 1_800_036_720),
                 origin: "Невский проспект, 100",
                 destination: "Арбат, 10", middles: 1, price: 3_400),
        .fixture(status: .attention, created: .init(timeIntervalSince1970: 1_799_936_000),
                 origin: "Никольская, 10",
                 destination: "Пятницкая, 25", price: 890,
                 observed: .init(timeIntervalSince1970: 1_799_950_000),
                 detail: "Ended before delivery"),
    ]),
    .init(id: .past, rows: [
        .fixture(status: .done, created: .init(timeIntervalSince1970: 1_789_000_000),
                 origin: "Тверская, 1", destination: "Арбат, 10", price: 3_400),
        .fixture(status: .cancelled, created: .init(timeIntervalSince1970: 1_767_283_980),
                 origin: "Новослободская, 3",
                 destination: "Тверская-Ямская, 12", price: 1_240),
    ]),
]

#Preview("Two shelves") {
    NavigationStack {
        DeliveriesView.Content(isSignedIn: true, sections: previewSections,
                               hasAnyRows: true, compose: {})
    }
}

#Preview("Filtered to cancelled") {
    let cancelled = previewSections.compactMap { section -> DeliveriesView.Content.Section? in
        let rows = section.rows.filter { $0.status == .cancelled }
        return rows.isEmpty ? nil : .init(id: section.id, rows: rows)
    }
    NavigationStack {
        DeliveriesView.Content(isSignedIn: true, sections: cancelled, hasAnyRows: true,
                               filter: .constant(.cancelled), compose: {})
    }
}

#Preview("An archived row") {
    // The shelved row's doors — Unarchive on the leading edge and the menu.
    NavigationStack {
        DeliveriesView.Content(
            isSignedIn: true,
            sections: [.init(id: .archived, rows: [
                .fixture(status: .done, created: .init(timeIntervalSince1970: 1_789_000_000),
                         origin: "Тверская, 1", destination: "Арбат, 10",
                         price: 3_400, archived: true),
            ])],
            hasAnyRows: true, filter: .constant(.archived), compose: {})
    }
}

#Preview("The Archived shelf") {
    NavigationStack {
        DeliveriesView.Content(
            isSignedIn: true,
            sections: [.init(id: .archived, rows: [
                .fixture(status: .done, created: .init(timeIntervalSince1970: 1_789_000_000),
                         origin: "Тверская, 1", destination: "Арбат, 10",
                         price: 3_400, archived: true),
                .fixture(status: .cancelled, created: .init(timeIntervalSince1970: 1_767_283_980),
                         origin: "Новослободская, 3", destination: "Тверская-Ямская, 12",
                         price: 1_240, archived: true),
            ])],
            hasAnyRows: true, filter: .constant(.archived), compose: {})
    }
}

#Preview("Nothing archived yet") {
    NavigationStack {
        DeliveriesView.Content(isSignedIn: true, sections: [], hasAnyRows: true,
                               filter: .constant(.archived), compose: {})
    }
}

#Preview("Nothing to show") {
    NavigationStack {
        DeliveriesView.Content(isSignedIn: true, sections: [], hasAnyRows: true,
                               filter: .constant(.delivered), compose: {})
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

#Preview("A row opening — slow read") {
    NavigationStack {
        DeliveriesView.Content(
            isSignedIn: true, sections: previewSections,
            pendingID: previewSections[0].rows[1].id, compose: {})
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

#Preview("Trail row — loaded / failed / empty") {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let live = previewSections[0].rows[0]
    List {
        DeliveriesView.Content.TrailRow(route: live.route, trail: [
            ProviderEvent(orderID: live.id, providerEventID: 1, at: t0, kind: "status", providerStatus: "accepted", source: "journal"),
            ProviderEvent(orderID: live.id, providerEventID: 2, at: t0 + 420, kind: "status", providerStatus: "performer_found", source: "journal"),
        ])
        DeliveriesView.Content.TrailRow(
            route: live.route, trail: nil,
            trailError: "Shared storage is unavailable on this install.")
        DeliveriesView.Content.TrailRow(route: live.route, trail: [])
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
