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
        // One database, both consumers — orders/places on one side, the sync cursor
        // on the other. Sharing the instance shares the queue, not just the file.
        let database = AppDatabase.inAppGroup(id: AppGroup.id)
        let store = StoreController(database: database)
        let sync = ClaimsSyncController(session: session, store: store, database: database)
        // The identity boundary, wired at composition: a sign-out + sign-in inside
        // one poll interval is invisible to sampling — the hook fires inside the
        // transition itself (review, PR #35).
        session.onIdentityChange = { [weak sync] in sync?.resetIdentityState() }
        // CloudKit sync starts at launch, entitlement or not — `startSync` probes and
        // degrades to a logged, stored failure rather than a CKContainer trap.
        if let database { Task { await database.startSync() } }
        _session = State(initialValue: session)
        _store = State(initialValue: store)
        _sync = State(initialValue: sync)
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
