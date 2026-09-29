import SwiftUI
import YDeliveryKit

/// Root view of the Deliveries screen: connects the store's memory and the session to
/// the content. Composing happens above this screen — the intent is forwarded up to
/// `RootView`, which owns the draft and the sheet.
struct DeliveriesView: View {
    @Environment(ClientController.self) private var session
    @Environment(StoreController.self) private var store
    @Environment(ClaimsSyncController.self) private var sync
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

    var body: some View {
        NavigationStack(path: $path) {
            Content(
                isSignedIn: session.isSignedIn,
                sections: Model.sections(of: store.orders, fields: store.fields(for:)),
                expandedID: model.expandedID,
                trail: model.trail,
                historyUnavailable: store.historyUnavailable,
                syncError: sync.lastError?.localizedDescription,
                refresh: { await sync.syncNow() },
                compose: compose,
                repeatOrder: { id, reversed in
                    guard let order = store.orders.first(where: { $0.id == id }) else { return }
                    repeatOrder(order, reversed)
                },
                toggleTrail: { id in
                    model.toggleTrail(of: id) { try await store.providerEvents(for: id) }
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
        private var loading: Task<Void, Never>?

        /// Open the trail of `id`, or close it if it is the one already open. A read
        /// that fails reads as empty — the row then says the provider has reported
        /// nothing yet, which for a claimless order is also the truth.
        func toggleTrail(of id: UUID, using fetch: @escaping () async throws -> [ProviderEvent]) {
            loading?.cancel()
            guard expandedID != id else {
                expandedID = nil
                trail = nil
                return
            }
            expandedID = id
            trail = nil
            loading = Task {
                let fetched = (try? await fetch()) ?? []
                guard !Task.isCancelled, expandedID == id else { return }
                trail = fetched
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
            createdText: order.created.formatted(date: .abbreviated, time: .shortened),
            destinationText: destination?.compactAddress ?? origin?.compactAddress ?? "",
            originText: hasOrigin ? origin?.compactAddress : nil,
            middleStops: hasOrigin ? max(0, (destinationIndex ?? 0) - 1) : 0,
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
