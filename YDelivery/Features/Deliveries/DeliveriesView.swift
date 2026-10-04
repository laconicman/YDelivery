import SwiftUI
import YDeliveryKit

/// Root view of the Deliveries screen: connects the store's memory and the session to
/// the content. Composing happens above this screen — the intent is forwarded up to
/// `RootView`, which owns the draft and the sheet.
struct DeliveriesView: View {
    @Environment(ClientController.self) private var session
    @Environment(StoreController.self) private var store
    @Environment(ClaimsSyncController.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let compose: () -> Void
    /// «Повторить»/«Наоборот» — forwarded up beside `compose`; the order and whether
    /// the route runs backwards. `RootView` turns it into a pre-filled draft.
    let repeatOrder: (Order, _ reversed: Bool) -> Void
    /// A Spotlight result's order id, set by `RootView` (which also steers the tab
    /// here). Retained, not dropped, when it arrives ahead of the first read —
    /// the resolution below answers it once history is actually loaded.
    @Binding var pendingOrderID: UUID?

    /// The navigation path — a Spotlight result push lands here by order id
    /// (`CSSearchableItem.uniqueIdentifier` is that id).
    @State private var path: [UUID] = []
    @State private var model = Model()
    /// The typed search — read by the derivation below, owned here so the list
    /// handed down is already the answer (Content carries plain values, R5).
    @State private var searchText = ""
    /// The toolbar's sort and show picks — kept in defaults so a relaunch or a
    /// tab switch away keeps them; the enum raw values are the stored strings.
    @AppStorage("historySort") private var sort: HistorySort = .newestFirst
    @AppStorage("historyFilter") private var filter: HistoryFilter = .all

    var body: some View {
        NavigationStack(path: $path) {
            let sections = Model.sections(of: store.orders, fields: store.fields(for:))
            Content(
                isSignedIn: session.isSignedIn,
                sections: Model.visible(sections, query: searchText,
                                        sort: sort, filter: filter),
                hasAnyRows: sections.contains { !$0.rows.isEmpty },
                sort: $sort,
                filter: $filter,
                searchText: $searchText,
                expandedID: model.expandedID,
                pendingID: model.pendingID,
                trail: model.trail,
                trailError: model.trailError,
                historyUnavailable: store.historyUnavailable,
                syncError: sync.lastError?.localizedDescription,
                refresh: { await sync.syncNow() },
                compose: compose,
                repeatOrder: { id, reversed in
                    guard let order = store.orders.first(where: { $0.id == id }) else { return }
                    repeatOrder(order, reversed)
                },
                toggleTrail: { id in
                    model.toggleTrail(
                        of: id,
                        using: { try await store.providerEvents(for: id) },
                        reduceMotion: reduceMotion)
                }
            )
                .navigationTitle("Deliveries")
                .navigationDestination(for: UUID.self) { id in
                    if let order = store.orders.first(where: { $0.id == id }) {
                        OrderDetailView(order: order)
                    }
                }
                .task {
                    await store.refresh()
                    await sync.syncNow()
                }
                .onChange(of: pendingOrderID) { resolvePending() }
                .onChange(of: store.orders.map(\.id)) { resolvePending() }
                // Every order write — a sync tick that recorded events, a pull —
                // republishes `orders`; the open row's trail follows it.
                .onChange(of: store.orders) { model.refreshTrail() }
        }
    }

    /// Push the requested order once the store can confirm it — or let the request
    /// go once a completed read says the order left history since it was indexed.
    /// Before `hasLoaded` an empty list means *not looked yet*, so the request waits.
    private func resolvePending() {
        guard let id = pendingOrderID else { return }
        if store.orders.contains(where: { $0.id == id }) {
            path = [id]
            pendingOrderID = nil
        } else if store.hasLoaded {
            pendingOrderID = nil
        }
    }
}

extension DeliveriesView {
    /// The screen's async owner (rule 6): one expanded row at a time, its provider
    /// trail fetched on expand and dropped on collapse — the list never carries
    /// every order's history, only the one the sender opened.
    @Observable @MainActor
    final class Model {
        /// The row whose trail is open — one, not many: the list is a scan, and a
        /// second open trail would push the first off the screen.
        private(set) var expandedID: UUID?
        /// The open row's trail as read — `nil` while the read is in flight, empty
        /// for an order the provider never reported on: asking and nothing-there are
        /// different rows (R9).
        private(set) var trail: [ProviderEvent]?
        /// Why the trail could not be read, when it could not — a storage failure
        /// must not wear «nothing reported» (review, PR #77).
        private(set) var trailError: String?
        /// The row whose trail is being read — opening is one publish, so a tap
        /// on a still-opening row must know about it to close; published so the
        /// row can answer the wait with a spinner (review, PR #118).
        private(set) var pendingID: UUID?
        /// The pending open's task — its own handle: a republish re-read must
        /// never cancel an open in flight, nor an open cancel a re-read.
        private var opening: Task<Void, Never>?
        /// The republish re-read's task; a new tick cancels only the previous
        /// re-read, never `opening`.
        private var refreshing: Task<Void, Never>?
        /// Which expansion the screen is showing. Bumped by every publish (open
        /// commit, collapse): a `refreshing` task captures it at start and
        /// publishes only while it stands — a re-read that outlives "B opens, A
        /// reopens" must not overwrite the newer trail (review, PR #109).
        private var generation = 0
        /// The *committed* row's fetch, kept so a store republication can re-read
        /// the trail without the row being closed and reopened. Assigned only in
        /// the publish block — while another row is still opening, a republish
        /// re-reads the shown row's trail, not the pending one's (review, PR
        /// #109: holding the pending fetch here mixed B's events into A's row).
        private var fetchTrail: (() async throws -> [ProviderEvent])?

        /// Open the trail of `id`, or close it if it is the one already open —
        /// or still opening (`pendingID`), which reads the same to a sender.
        /// Expansion publishes ONCE inside `withAnimation`: `expandedID` and the
        /// trail arrive together, and because the trail is a *row of its own*
        /// the transaction animates a row insertion — the one thing the List
        /// does natively — rather than an in-row growth whose interpolated
        /// frame floated the collapsed lines mid-cell (review, PR #109 frame
        /// captures). A local SQLite read is milliseconds, so the row answering
        /// after the read is imperceptible; `nil`-while-expanded stays only for
        /// `refreshTrail`. `reduceMotion` drops the transaction — a row
        /// insertion cannot cross-fade, so under the preference the trail
        /// appears and vanishes instantly instead of sliding (the motion rule's
        /// fallback for an animation with no opacity equivalent).
        func toggleTrail(
            of id: UUID,
            using fetch: @escaping () async throws -> [ProviderEvent],
            reduceMotion: Bool = false
        ) {
            opening?.cancel()
            // A second tap on a still-opening row cancels only its own pending
            // open — the committed row's trail stays put (review, PR #109:
            // pending and expanded are the same to a sender, never to the row
            // already showing).
            if pendingID == id {
                pendingID = nil
                return
            }
            guard expandedID != id else {
                refreshing?.cancel()
                // The collapse cancelled `opening` above — drop its marker too,
                // or a third tap on that row is needed to open it (review, PR
                // #118: A open → B pending → tap A → tap B must open B).
                pendingID = nil
                withAnimation(reduceMotion ? nil : .default) {
                    generation += 1
                    expandedID = nil
                    trail = nil
                    trailError = nil
                    fetchTrail = nil
                }
                return
            }
            pendingID = id
            // The fetch rides inside the task — it is committed to `fetchTrail`
            // only when this open wins the publish.
            opening = Task {
                do {
                    let fetched = try await fetch()
                    guard !Task.isCancelled, pendingID == id else { return }
                    // The committed row changes — a re-read of the previous one
                    // is dead the moment this publish lands.
                    refreshing?.cancel()
                    withAnimation(reduceMotion ? nil : .default) {
                        generation += 1
                        pendingID = nil
                        expandedID = id
                        trail = fetched
                        trailError = nil
                        fetchTrail = fetch
                    }
                } catch {
                    guard !Task.isCancelled, pendingID == id else { return }
                    let message = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    refreshing?.cancel()
                    withAnimation(reduceMotion ? nil : .default) {
                        generation += 1
                        pendingID = nil
                        expandedID = id
                        trail = nil
                        trailError = message
                        fetchTrail = fetch
                    }
                }
            }
        }

        /// The store republished — sync recorded events, a pull refreshed — so the
        /// open row's trail is re-read in place. The trail on screen stays until the
        /// new read lands; only a success replaces it. Touches `refreshing` only:
        /// an open still in flight is the sender's tap and is left alone.
        func refreshTrail() {
            guard let id = expandedID else { return }
            read(for: id)
        }

        /// A store-republish re-read assigns plainly — a sync tick must not
        /// restart an animation on a row that is already open, and the shown
        /// trail stays on a failed re-read.
        private func read(for id: UUID) {
            guard let fetchTrail else { return }
            refreshing?.cancel()
            let generation = generation
            refreshing = Task {
                do {
                    let fetched = try await fetchTrail()
                    guard !Task.isCancelled,
                          expandedID == id, generation == self.generation else { return }
                    trail = fetched
                    trailError = nil
                } catch {
                    guard !Task.isCancelled,
                          expandedID == id, generation == self.generation else { return }
                    if trail == nil {
                        trailError = (error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription
                    }
                }
            }
        }

        /// Orders reduced to rows and split into the two shelves the sender scans
        /// differently — what is happening, and what happened. Both sort newest
        /// order first: the row leads with the creation date, so the list's order is
        /// the date's order and never reads as broken (review, 2026-09-29).
        nonisolated static func sections(
            of orders: [Order], fields: (Order.ID) -> [OrderCustomField]
        ) -> [Content.Section] {
            let rows = orders
                .sorted { $0.created > $1.created }
                .map { Content.Row(order: $0, fieldValues: fields($0.id).map(\.value)) }
            let live = rows.filter(\.status.isLive)
            let past = rows.filter { !$0.status.isLive }
            return [
                Content.Section(id: .live, rows: live),
                Content.Section(id: .past, rows: past),
            ].filter { !$0.rows.isEmpty }
        }

        /// The toolbar's list: what survives the status filter and the search,
        /// in the picked order, still on its shelves. A shelf emptied by the
        /// picks leaves the list; a price-less row cannot win «high first» and
        /// sorts last. Pure — the root computes it, Content only draws (R5).
        nonisolated static func visible(
            _ sections: [Content.Section], query: String,
            sort: HistorySort, filter: HistoryFilter
        ) -> [Content.Section] {
            let query = query.trimmingCharacters(in: .whitespaces)
            return sections.compactMap { section in
                let rows = section.rows
                    .filter { row in
                        filter.admits(row.status)
                            && (query.isEmpty
                                || row.searchableText.localizedCaseInsensitiveContains(query))
                    }
                    .sorted { lhs, rhs in
                        switch sort {
                        case .newestFirst: lhs.created > rhs.created
                        case .oldestFirst: lhs.created < rhs.created
                        case .priceHighFirst:
                            switch (lhs.price, rhs.price) {
                            case let (left?, right?):
                                left == right
                                    ? lhs.created > rhs.created
                                    : left > right
                            case (nil, _?): false
                            case (_?, nil): true
                            case (nil, nil): lhs.created > rhs.created
                            }
                        }
                    }
                return rows.isEmpty ? nil : Content.Section(id: section.id, rows: rows)
            }
        }
    }
}

extension DeliveriesView {
    /// The toolbar's orders for the shelves — persisted under `historySort`.
    nonisolated enum HistorySort: String, CaseIterable, Codable, Sendable {
        case newestFirst
        case oldestFirst
        /// Numeric amounts compared raw — the account is single-currency (RUB).
        /// A mixed-currency account would need converted values first.
        case priceHighFirst

        var words: String {
            switch self {
            case .newestFirst: String(localized: "Newest first")
            case .oldestFirst: String(localized: "Oldest first")
            case .priceHighFirst: String(localized: "Price, high first")
            }
        }
    }

    /// The toolbar's status filter — persisted under `historyFilter`.
    nonisolated enum HistoryFilter: String, CaseIterable, Codable, Sendable {
        case all
        case needsDecision
        case delivered
        case cancelled

        var words: String {
            switch self {
            case .all: String(localized: "Everything")
            case .needsDecision: String(localized: "Needs a decision")
            case .delivered: String(localized: "Delivered")
            case .cancelled: String(localized: "Cancelled")
            }
        }

        /// Does a row's status pass — `.all` admits everything.
        func admits(_ status: OrderStatus) -> Bool {
            switch self {
            case .all: true
            case .needsDecision: status == .attention
            case .delivered: status == .done
            case .cancelled: status == .cancelled
            }
        }
    }
}

extension OrderStatus {
    /// The shelf split: a status the provider is still working, or one the sender
    /// still has to answer, is *live*; delivered and cancelled are history. Drafts
    /// never reach the list.
    nonisolated var isLive: Bool {
        switch self {
        case .searching, .active, .attention, .draft: true
        case .done, .cancelled: false
        }
    }
}

extension DeliveriesView.Content.Row {
    /// The row's facts from the order — derivation on the root's side of the seam,
    /// so `Content` renders and never computes (R5). `nonisolated`: pure over
    /// value types, called from the model's nonisolated section split.
    nonisolated init(order: Order, fieldValues: [String]) {
        let destinationIndex = order.route.destinationIndex
        let destination = destinationIndex.map { order.route[$0] }
        let origin = order.route.first
        let statusPhrase = order.providerStatus.flatMap(ProviderStatusPhrase.phrase(for:))
        // A single point — a thin synced claim — is the destination and has no
        // origin to name; so is a route whose last drop-off *is* its first point.
        let hasOrigin = (destinationIndex ?? 0) > 0
        self.init(
            id: order.id,
            status: order.status,
            statusObservedAt: order.providerObservedAt,
            created: order.created,
            createdText: order.created.formatted(date: .abbreviated, time: .shortened),
            // The wire's decimal is POSIX dot — parsing it under a comma-decimal
            // locale drops the fraction (`priceText` reads it the same way).
            price: order.price.flatMap {
                Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))
            },
            destinationText: destination?.compactAddress ?? origin?.compactAddress ?? "",
            originText: hasOrigin ? origin?.compactAddress : nil,
            middleStops: hasOrigin ? max(0, (destinationIndex ?? 0) - 1) : 0,
            // The collapse holds six waits behind one chip — on those rows the
            // provider's phrase says which; everywhere else the chip suffices.
            statusDetail: order.statusDetail,
            priceText: order.priceText,
            route: order.route,
            // Search hits the route's addresses, the people at the doors, the
            // status in the sender's words, and «Ваши поля» values — «Заказ 4417»
            // finds its order (board `4b`).
            searchableText: (order.route.map(\.address)
                + order.route.compactMap(\.contactName)
                + [String(localized: order.status.words)]
                + [statusPhrase.map { String(localized: $0) }].compactMap { $0 }
                + fieldValues)
                .joined(separator: " ")
        )
    }
}

#Preview {
    let session = ClientController(tokenStore: TokenStore(service: "preview.YDelivery"))
    let store = StoreController(database: nil)
    DeliveriesView(compose: {}, repeatOrder: { _, _ in }, pendingOrderID: .constant(nil))
        .environment(session)
        .environment(store)
        .environment(ClaimsSyncController(session: session, store: store, database: nil))
}
