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

    var body: some View {
        NavigationStack {
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
                priceText: order.priceText
            )
        }
    }
}

#Preview {
    let session = ClientController(tokenStore: TokenStore(service: "preview.YDelivery"))
    let store = StoreController(database: nil)
    DeliveriesView(compose: {}, repeatOrder: { _, _ in })
        .environment(session)
        .environment(store)
        .environment(ClaimsSyncController(session: session, store: store, database: nil))
}
