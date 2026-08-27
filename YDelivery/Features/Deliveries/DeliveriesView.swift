import SwiftUI

/// Root view of the Deliveries screen: connects content to the session controller and will
/// own navigation once orders exist (Roadmap → Phase 2 gives this screen its store).
struct DeliveriesView: View {
    @Environment(ClientController.self) private var session

    var body: some View {
        NavigationStack {
            Content(isSignedIn: session.isSignedIn)
                .navigationTitle("Deliveries")
        }
    }
}

#Preview {
    DeliveriesView()
        .environment(ClientController(tokenStore: TokenStore(service: "preview.YDelivery")))
}
