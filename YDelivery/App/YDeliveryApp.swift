import BackgroundTasks
import SwiftUI
import YDeliveryKit

/// The composition root, and nothing else: shared controllers are created here once and
/// injected into the tree (`swiftui-app-structure`). The sync engine is wired to the two
/// it spans — it reads the session, writes the store, and views never see either wire.
@main
struct YDeliveryApp: App {
    /// The app delegate exists for one job: routing scene configuration so
    /// share-acceptance URLs reach `YDeliverySceneDelegate`. `acceptShare` is
    /// filled below — UIKit's own instantiation is why the database arrives
    /// as a property rather than an init parameter.
    @UIApplicationDelegateAdaptor(YDeliveryAppDelegate.self) private var appDelegate
    @State private var session: ClientController
    @State private var store: StoreController
    @State private var sync: ClaimsSyncController
    @State private var notifications: NotificationController
    @State private var activities: LiveActivityController
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
        let notifications = NotificationController(store: store)
        let sync = ClaimsSyncController(session: session, store: store,
                                        database: database, notifications: notifications)
        // The identity boundary, wired at composition: a sign-out + sign-in inside
        // one poll interval is invisible to sampling — the hook fires inside the
        // transition itself (review, PR #35).
        session.onIdentityChange = { [weak sync] in sync?.resetIdentityState() }
        // The background-refresh registration must complete before launch finishes;
        // the handler is the journal pass — the feed's cheap delta, not the
        // membership re-ask.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: ClaimsSyncController.refreshTaskIdentifier,
            using: nil
        ) { [weak sync] task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            // The scheduler retains this closure for the app's lifetime —
            // a weak capture keeps the registration from pinning the
            // controller should this init ever run more than once (review,
            // PR #43).
            if let sync { sync.handleAppRefresh(refresh) }
            else { task.setTaskCompleted(success: false) }
        }
        // CloudKit sync starts at launch, entitlement or not — `startSync` probes and
        // degrades to a logged, stored failure rather than a CKContainer trap.
        _syncTask = State(initialValue: Task { await database?.startSync() })
        _session = State(initialValue: session)
        _store = State(initialValue: store)
        _sync = State(initialValue: sync)
        _notifications = State(initialValue: notifications)
        _activities = State(initialValue: LiveActivityController())
        // The share-acceptance bridge — the delegates are UIKit-instantiated,
        // so the database reaches them through this property, not an init.
        // It goes through the store, not the database: accepting also re-reads
        // the store so the just-joined order renders without waiting for the
        // next refresh (review, PR #56).
        appDelegate.acceptShare = { try await store.acceptShare(metadata: $0) }
        #if DEBUG
        Task {
            await Self.seedFieldsIfFlagged(store)
            await Self.seedHistoryIfFlagged(store, database: database)
        }
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

    /// `--uitest-history`: seed a history the Deliveries screen can show — five
    /// orders across the status vocabulary, a provider-event trail on the live one,
    /// and a chat on the finished one — through the same Kit writes the sync engine
    /// and the chat screen perform. Idempotent on a non-empty store, like the
    /// fields seed above.
    private static func seedHistoryIfFlagged(
        _ store: StoreController, database: AppDatabase?
    ) async {
        guard ProcessInfo.processInfo.arguments.contains("--uitest-history"),
              let database else { return }
        await store.refresh()
        guard store.orders.isEmpty else { return }
        let live = Order.previewEnRoute
        let done = Order.previewDone
        let attention = Order(
            created: .init(timeIntervalSince1970: 1_799_900_000),
            status: .attention,
            route: [
                RoutePoint(latitude: 55.7539, longitude: 37.6208, address: "Москва, Никольская, 10", contactName: "Ольга"),
                RoutePoint(latitude: 55.7422, longitude: 37.6156, address: "Москва, Пятницкая, 25", contactName: "Сергей Волков"),
            ],
            price: "890", currency: "RUB", tariff: "express", claimID: "claim-preview-3",
            providerStatus: "performer_not_found")
        let cancelled = Order(
            created: .init(timeIntervalSince1970: 1_799_000_000),
            status: .cancelled,
            route: [
                RoutePoint(latitude: 55.7887, longitude: 37.6016, address: "Москва, Новослободская, 3"),
                RoutePoint(latitude: 55.7658, longitude: 37.5946, address: "Москва, Тверская-Ямская, 12"),
            ],
            price: "1240", currency: "RUB", tariff: "courier", claimID: "claim-preview-4")
        for order in [live, Order.previewSearching, attention, done, cancelled] {
            try? await store.record(order)
        }
        // The live order's provider trail — the words the journal keeps.
        let t0 = live.created.timeIntervalSince1970
        let trail: [(Int64, String, TimeInterval)] = [
            (1, "new", 0), (2, "estimating", 40), (3, "ready_for_approval", 95),
            (4, "accepted", 130), (5, "performer_lookup", 131), (6, "performer_found", 420),
            (7, "pickup_arrived", 1_150), (8, "pickuped", 1_200), (9, "delivery_arrived", 2_300),
        ]
        for (id, status, offset) in trail {
            _ = try? database.recordProviderEvent(ProviderEvent(
                orderID: live.id, providerEventID: id,
                at: .init(timeIntervalSince1970: t0 + offset),
                kind: "status", providerStatus: status, source: "journal"))
        }
        // The finished order's chat — a participant's word and their confirmation.
        try? database.postMessage(OrderMessage(
            orderID: done.id, sentAt: done.created.addingTimeInterval(3_600),
            kind: OrderMessage.Kind.text, text: "Курьер у ворот, встречаю",
            authorHint: "Ирина"))
        try? database.postMessage(OrderMessage(
            orderID: done.id, sentAt: done.created.addingTimeInterval(3_900),
            kind: OrderMessage.Kind.receptionConfirmed, authorHint: "Ирина"))
        await store.refresh()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(store)
                .environment(sync)
                .environment(notifications)
                .environment(activities)
        }
    }
}
