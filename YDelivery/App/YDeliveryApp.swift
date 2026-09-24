import SwiftUI
import YDeliveryKit

/// The composition root, and nothing else: shared controllers are created here once and
/// injected into the tree (`swiftui-app-structure`). The sync engine is wired to the two
/// it spans — it reads the session, writes the store, and views never see either wire.
@main
struct YDeliveryApp: App {
    @State private var session: ClientController
    @State private var store: StoreController
    @State private var sync: ClaimsSyncController
    /// Owned by the composition root for the app's lifetime (rule 6) — a one-shot
    /// start, retained so a future surface can observe or retry it.
    @State private var syncTask: Task<Void, Never>?

    init() {
        let session = ClientController()
        // One database, both consumers — orders/places on one side, the sync cursor
        // on the other. Sharing the instance shares the queue, not just the file.
        let database = AppDatabase.inAppGroup(
            id: AppGroup.id,
            providerAccountRef: SyncIdentity.providerAccountRef,
            containerIdentifier: SyncIdentity.cloudKitContainer)
        let store = StoreController(database: database)
        let sync = ClaimsSyncController(session: session, store: store, database: database)
        // The identity boundary, wired at composition: a sign-out + sign-in inside
        // one poll interval is invisible to sampling — the hook fires inside the
        // transition itself (review, PR #35).
        session.onIdentityChange = { [weak sync] in sync?.resetIdentityState() }
        // CloudKit sync starts at launch, entitlement or not — `startSync` probes and
        // degrades to a logged, stored failure rather than a CKContainer trap.
        _syncTask = State(initialValue: Task { await database?.startSync() })
        _session = State(initialValue: session)
        _store = State(initialValue: store)
        _sync = State(initialValue: sync)
        #if DEBUG
        Task { await Self.seedFieldsIfFlagged(store) }
        #endif
    }

    #if DEBUG
    /// `--uitest-fields`: seed a «Ваши поля» schema through the real save path —
    /// the same write the settings editor performs — so screenshot tests can see
    /// the draft's section and the editor's list (board `4b`). Idempotent: a
    /// configured store is left alone, so repeated launches don't accumulate rows.
    private static func seedFieldsIfFlagged(_ store: StoreController) async {
        guard ProcessInfo.processInfo.arguments.contains("--uitest-fields") else { return }
        await store.refresh()
        guard store.fieldDefinitions.isEmpty else { return }
        try? await store.saveField(CustomFieldDefinition(
            name: "Заказ", isOptional: false, carrier: .orderNumber, position: 0))
        try? await store.saveField(CustomFieldDefinition(
            name: "Тип груза", kind: .choice, choices: ["Документы", "Коробка"],
            isOptional: true, isShownByDefault: false, position: 1))
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(store)
                .environment(sync)
        }
    }
}
