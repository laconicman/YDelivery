import BackgroundTasks
import OSLog
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
        let session = ClientController(tokenStore: Self.tokenStore())
        // One database, both consumers — orders/places on one side, the sync cursor
        // on the other. Sharing the instance shares the queue, not just the file.
        let database = Self.database()
        let store = StoreController(database: database, republishing: Self.republication())
        let notifications = NotificationController(store: store)
        let sync = ClaimsSyncController(session: session, store: store,
                                        database: database, notifications: notifications)
        let activities = LiveActivityController(
            reconciles: !(Self.isHistoryFixture || Self.isCloudKitSeed))
        // The identity boundary, wired at composition: a sign-out + sign-in inside
        // one poll interval is invisible to sampling — the hook fires inside the
        // transition itself (review, PR #35).
        session.onIdentityChange = { [weak sync] in sync?.resetIdentityState() }
        // The background-refresh registration must complete before launch finishes;
        // the handler is the journal pass — the feed's cheap delta, not the
        // membership re-ask. `.main`, not `nil`: written here, the closure is
        // MainActor-isolated, and Swift 6 checks that on entry — `nil` delivers
        // it on BackgroundTasks' own queue and the check traps (TestFlight 1.0 (1),
        // `_swift_task_checkIsolatedSwift`; Design, "Background refresh is
        // delivered on the main queue"; untested by CI — YD-33).
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: ClaimsSyncController.refreshTaskIdentifier,
            using: .main
        ) { [weak sync, weak store, weak activities] task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            // The scheduler retains this closure for the app's lifetime —
            // a weak capture keeps the registration from pinning the
            // controller should this init ever run more than once (review,
            // PR #43).
            if let sync {
                // The cards move in the wake that learned the news, and the
                // task completes only once their calls landed — a delivered
                // order must not keep an «en route» card until the next launch.
                sync.handleAppRefresh(refresh) {
                    guard let store, let activities else { return }
                    activities.reconcile(with: store)
                    await activities.settle()
                }
            } else { task.setTaskCompleted(success: false) }
        }
        // CloudKit sync starts at launch, entitlement or not — `startSync` probes and
        // degrades to a logged, stored failure rather than a CKContainer trap.
        // Except the schema-seed launches: those drive their own isolated store
        // and the real one must never sync its rows.
        _syncTask = State(initialValue: Task {
            guard !Self.isCloudKitSeed, !Self.isCloudKitSeedClean else { return }
            await database?.startSync()
        })
        _session = State(initialValue: session)
        _store = State(initialValue: store)
        _sync = State(initialValue: sync)
        _notifications = State(initialValue: notifications)
        _activities = State(initialValue: activities)
        // The share-acceptance bridge — the delegates are UIKit-instantiated,
        // so the database reaches them through this property, not an init.
        // It goes through the store, not the database: accepting also re-reads
        // the store so the just-joined order renders without waiting for the
        // next refresh (review, PR #56).
        appDelegate.acceptShare = { try await store.acceptShare(metadata: $0) }
        #if DEBUG
        Task {
            await Self.seedFieldsIfFlagged(store)
            await Self.seedTemplatesIfFlagged(store)
            await Self.seedPlacesIfFlagged(store)
            await Self.seedHistoryIfFlagged(store, database: database)
            await Self.seedCloudKitSchemaIfFlagged()
            await Self.cleanCloudKitSeedIfFlagged()
        }
        #endif
    }

    /// `--uitest-history` is a hermetic launch: the screenshot pass starts from an
    /// empty store on every run, must never sync fixtures into a signed-in
    /// account, must never pull a real account's orders into the fixture, and must
    /// leave the device's real widget snapshot, Spotlight index, places file and
    /// Live Activities untouched (review, PR #61). Four seams, each read once here.
    private static var isHistoryFixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--uitest-history")
        #else
        false
        #endif
    }

    /// `--uitest-offers` prices the tariff strip from a fixture instead of the
    /// provider — the listing's second screenshot needs a priced strip, and no
    /// seeded launch has a session to quote one with. The strip still does its
    /// own work; only the answer's source is the fixture (`Offer.listingStrip`).
    static var isOffersFixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--uitest-offers")
        #else
        false
        #endif
    }

    /// The App Group database — or, for the fixture launch, a throwaway one in a
    /// fresh directory with a container that resolves to nothing (`startSync`
    /// degrades to a logged failure, as it does on any unentitled install). The
    /// `--ckschema-seed` launch keeps the real store too — the seed drives its
    /// own isolated database, so the store below is constructed but never
    /// started (see the launch `syncTask`).
    private static func database() -> AppDatabase? {
        guard !isHistoryFixture else {
            return AppDatabase(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true),
                providerAccountRef: SyncIdentity.providerAccountRef,
                containerIdentifier: "iCloud.uitest")
        }
        return AppDatabase.inAppGroup(
            id: AppGroup.id,
            providerAccountRef: SyncIdentity.providerAccountRef,
            containerIdentifier: SyncIdentity.cloudKitContainer)
    }

    /// The fixture launch reads a Keychain service no sign-in ever writes, so the
    /// session starts signed out and the sync engine never calls the provider —
    /// a saved token would otherwise pull the account's real orders into the
    /// fixture store. The schema seed shares the service for the same reason,
    /// minus the pull: a signed-out session can never touch the provider API,
    /// which a schema-population run has no business paying against.
    private static func tokenStore() -> TokenStore {
        isHistoryFixture || isCloudKitSeed
            ? TokenStore(service: "uitest.YDelivery") : TokenStore()
    }

    /// The fixture store publishes nowhere — its reads must not reach the
    /// system surfaces that belong to the real history. The schema seed
    /// publishes nowhere either: its order exists to create CloudKit record
    /// types, not to pose as history on the owner's widget or Spotlight.
    private static func republication() -> StoreController.Republication {
        isHistoryFixture || isCloudKitSeed ? .none : .systemSurfaces
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

    /// `--uitest-templates`: seed one parcel template through the real save path —
    /// the write «Save as a template» performs — so the draft's «Add from library»
    /// door exists for the UI test that drives it. Idempotent by the fixture's name,
    /// not by the store being empty: a simulator that already holds other templates
    /// still gets this one, and repeated launches don't accumulate it (review, PR #131).
    private static func seedTemplatesIfFlagged(_ store: StoreController) async {
        guard ProcessInfo.processInfo.arguments.contains("--uitest-templates") else { return }
        await store.refresh()
        let name = "Папка с документами"
        guard !store.parcelTemplates.contains(where: { $0.name == name }) else { return }
        var item = ParcelItem()
        item.name = name
        item.cost = 1000
        try? await store.saveTemplate(item, name: name)
    }

    /// `--uitest-places`: seed one saved place through the real save path — the
    /// write «Save as a place» performs — so the Library's Places list has a row
    /// whose tap the UI test can drive into the place editor. Idempotent by the
    /// fixture's name, not by the store being empty (review, #131). Like the
    /// other `--uitest-*` seeds it writes the real simulator store — YD-26 names
    /// that residue.
    private static func seedPlacesIfFlagged(_ store: StoreController) async {
        guard ProcessInfo.processInfo.arguments.contains("--uitest-places") else { return }
        await store.refresh()
        let name = "Склад на Невском"
        guard !store.savedPlaces.contains(where: { $0.name == name }) else { return }
        try? await store.save(SavedPlace(
            name: name, kind: .warehouse,
            point: RoutePoint(latitude: 59.9343, longitude: 30.3351,
                              address: "Санкт-Петербург, Невский проспект, 100",
                              contactName: "Иван Петров",
                              contactGivenName: "Иван", contactFamilyName: "Петров",
                              contactPhone: "+79123456789")))
    }

    /// `--uitest-history`: seed a history the Deliveries screen can show — five
    /// orders across the status vocabulary, a provider-event trail on the live one,
    /// and a chat on the finished one — through the same Kit writes the sync engine
    /// and the chat screen perform. The store is the throwaway one `database()`
    /// minted for this flag, so every launch seeds from empty; a write that fails
    /// is logged, not swallowed — a screenshot over a half-seeded store would lie.
    private static func seedHistoryIfFlagged(
        _ store: StoreController, database: AppDatabase?
    ) async {
        guard isHistoryFixture, let database else { return }
        let logger = Logger(subsystem: "YDelivery", category: "uitest-seed")
        func seed(_ what: String, _ write: () async throws -> Void) async {
            do { try await write() } catch { logger.error("seed failed — \(what): \(error)") }
        }
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
        // Its own route, not `previewSearching`'s: that fixture shares the live
        // order's addresses, and the screenshot pass tells rows apart by them.
        let searching = Order(
            created: .init(timeIntervalSince1970: 1_799_995_000),
            status: .searching,
            route: [
                RoutePoint(latitude: 55.7008, longitude: 37.5806, address: "Москва, Ленинский проспект, 40", contactName: "Марина"),
                RoutePoint(latitude: 55.6772, longitude: 37.5619, address: "Москва, Профсоюзная, 7", contactName: "Дмитрий Орлов", contactPhone: "+79261234567"),
            ],
            price: "640", currency: "RUB", tariff: "express", claimID: "claim-preview-5",
            providerStatus: "performer_lookup",
            providerObservedAt: .init(timeIntervalSince1970: 1_799_995_600))
        let cancelled = Order(
            created: .init(timeIntervalSince1970: 1_799_000_000),
            status: .cancelled,
            route: [
                RoutePoint(latitude: 55.7887, longitude: 37.6016, address: "Москва, Новослободская, 3"),
                RoutePoint(latitude: 55.7658, longitude: 37.5946, address: "Москва, Тверская-Ямская, 12"),
            ],
            price: "1240", currency: "RUB", tariff: "courier", claimID: "claim-preview-4")
        for order in [live, searching, attention, done, cancelled] {
            await seed("order \(order.id)") { try await store.record(order) }
        }
        // The live order's provider trail — the words the journal keeps.
        let t0 = live.created.timeIntervalSince1970
        let trail: [(Int64, String, TimeInterval)] = [
            (1, "new", 0), (2, "estimating", 40), (3, "ready_for_approval", 95),
            (4, "accepted", 130), (5, "performer_lookup", 131), (6, "performer_found", 420),
            (7, "pickup_arrived", 1_150), (8, "pickuped", 1_200), (9, "delivery_arrived", 2_300),
        ]
        for (id, status, offset) in trail {
            await seed("event \(status)") {
                _ = try database.recordProviderEvent(ProviderEvent(
                    orderID: live.id, providerEventID: id,
                    at: .init(timeIntervalSince1970: t0 + offset),
                    kind: "status", providerStatus: status, source: "journal"))
            }
        }
        // The finished order's chat — a participant's word and their confirmation.
        await seed("chat text") {
            try database.postMessage(OrderMessage(
                orderID: done.id, sentAt: done.created.addingTimeInterval(3_600),
                kind: OrderMessage.Kind.text, text: "Курьер у ворот, встречаю",
                authorHint: "Ирина"))
        }
        await seed("chat confirmation") {
            try database.postMessage(OrderMessage(
                orderID: done.id, sentAt: done.created.addingTimeInterval(3_900),
                kind: OrderMessage.Kind.receptionConfirmed, authorHint: "Ирина"))
        }
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
