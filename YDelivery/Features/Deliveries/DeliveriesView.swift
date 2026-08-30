import SwiftUI

/// Root view of the Deliveries screen: connects content to the session controller and will
/// own navigation once orders exist (Roadmap → Phase 2 gives this screen its store).
/// Composing happens above this screen — the intent is forwarded up to `RootView`,
/// which owns the draft and the sheet.
struct DeliveriesView: View {
    @Environment(ClientController.self) private var session
    let compose: () -> Void

    var body: some View {
        NavigationStack {
            Content(isSignedIn: session.isSignedIn, compose: compose)
                .navigationTitle("Deliveries")
        }
    }
}

#Preview {
    DeliveriesView(compose: {})
        .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
}
