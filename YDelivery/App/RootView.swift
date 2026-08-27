import SwiftUI

/// The app's top-level structure: one tab per standing concern. The New Delivery tab
/// arrives with its flow (Roadmap → Phase 1); an empty placeholder tab would be a broken
/// window, not a promise.
struct RootView: View {
    var body: some View {
        TabView {
            DeliveriesView()
                .tabItem { Label("Deliveries", systemImage: "shippingbox") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootView()
        .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
}
