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

    var body: some View {
        NavigationStack(path: $path) {
            Content(
                isSignedIn: session.isSignedIn,
                rows: rows,
                historyUnavailable: store.historyUnavailable,
                syncError: sync.lastError?.localizedDescription,
                refresh: { await sync.syncNow() },
                compose: compose,
                repeatOrder: { id, reversed in
                    guard let order = store.orders.first(where: { $0.id == id }) else { return }
                    repeatOrder(order, reversed)
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

    /// Orders reduced to rows — bridging on the root's side of the seam. The route
    /// crosses whole now: the card draws every stop, not just the ends.
    private var rows: [Content.Row] {
        store.orders.map { order in
            Content.Row(
                id: order.id,
                status: order.status,
                route: order.route,
                dateText: order.created.formatted(date: .abbreviated, time: .shortened),
                priceText: order.priceText,
                // Search hits the route's addresses and the sender's own field
                // values — «Заказ 4417» finds its order (board `4b`).
                searchableText: (order.route.map(\.address)
                    + store.fields(for: order.id).map(\.value))
                    .joined(separator: " ")
            )
        }
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
