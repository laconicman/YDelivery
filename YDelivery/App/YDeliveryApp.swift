import SwiftUI

/// The composition root, and nothing else: shared controllers are created here once and
/// injected into the tree (`swiftui-app-structure`).
@main
struct YDeliveryApp: App {
    @State private var session = ClientController()
    @State private var store = StoreController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(store)
        }
    }
}
