import SwiftUI

/// The app's top-level structure: one tab per standing concern.
struct RootView: View {
    var body: some View {
        TabView {
            DeliveriesView()
                .tabItem { Label("Deliveries", systemImage: "shippingbox") }
            NewDeliveryView()
                .tabItem { Label("New Delivery", systemImage: "plus.circle") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootView()
        .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
}
