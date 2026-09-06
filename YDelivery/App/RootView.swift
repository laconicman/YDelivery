import SFSafeSymbols
import SwiftUI

/// The app's top-level structure: one tab per standing *place*, and the New Delivery flow
/// presented modally — it is a verb, not a peer location (Design → "The tab bar goes").
///
/// The draft lives here, above the sheet, so dismissing the flow parks it: navigation can
/// no longer destroy a draft, which is what made the third tab wrong.
struct RootView: View {
    @State private var draft = NewDeliveryView.Model()
    @State private var isComposing = false

    var body: some View {
        TabView {
            DeliveriesView(compose: { isComposing = true })
                .tabItem { Label("Deliveries", systemSymbol: .shippingbox) }
            SettingsView()
                .tabItem { Label("Settings", systemSymbol: .gearshape) }
        }
        .sheet(isPresented: $isComposing) {
            NewDeliveryView(draft: draft)
        }
    }
}

#Preview {
    RootView()
        .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
        .environment(StoreController(orderStore: nil, placeStore: nil))
}
