import SwiftUI
import YDeliveryKit

/// Root view of the Deliveries screen: connects the store's memory and the session to
/// the content. Composing happens above this screen — the intent is forwarded up to
/// `RootView`, which owns the draft and the sheet.
struct DeliveriesView: View {
    @Environment(ClientController.self) private var session
    @Environment(StoreController.self) private var store
    let compose: () -> Void

    var body: some View {
        NavigationStack {
            Content(
                isSignedIn: session.isSignedIn,
                rows: rows,
                historyUnavailable: store.historyUnavailable,
                compose: compose
            )
                .navigationTitle("Deliveries")
                .task { await store.refresh() }
        }
    }

    /// Orders reduced to rows — bridging on the root's side of the seam. Price restores
    /// through the wire's own decimal string; the courier-facing ends read A → B even
    /// when the run had middles.
    private var rows: [Content.Row] {
        store.orders.map { order in
            Content.Row(
                id: order.id,
                status: order.status,
                from: order.route.first?.address ?? "",
                to: order.route.last?.address ?? "",
                dateText: order.created.formatted(date: .abbreviated, time: .shortened),
                priceText: order.price.flatMap { price in
                    Decimal(string: price, locale: Locale(identifier: "en_US_POSIX")).map {
                        $0.formatted(.currency(code: order.currency ?? "RUB").precision(.fractionLength(0...2)))
                    }
                }
            )
        }
    }
}

#Preview {
    DeliveriesView(compose: {})
        .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
        .environment(StoreController(orderStore: nil, placeStore: nil))
}
