import SwiftUI

/// The composition root, and nothing else: shared controllers are created here once and
/// injected into the tree (`swiftui-app-structure`). The sync engine is wired to the two
/// it spans — it reads the session, writes the store, and views never see either wire.
@main
struct YDeliveryApp: App {
    @State private var session: ClientController
    @State private var store: StoreController
    @State private var sync: ClaimsSyncController

    init() {
        let session = ClientController()
        let store = StoreController()
        _session = State(initialValue: session)
        _store = State(initialValue: store)
        _sync = State(initialValue: ClaimsSyncController(session: session, store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(store)
                .environment(sync)
        }
    }
}
