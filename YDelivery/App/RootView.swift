import CoreSpotlight
import SFSafeSymbols
import SwiftUI
import YDeliveryKit

/// The app's top-level structure: one tab per standing *place*, and the New Delivery flow
/// presented modally — it is a verb, not a peer location (Design → "The tab bar goes").
///
/// The draft lives here, above the sheet, so dismissing the flow parks it: navigation can
/// no longer destroy a draft, which is what made the third tab wrong.
struct RootView: View {
    @State private var draft = RootView.initialDraft()
    @State private var isComposing = RootView.opensComposing
    /// Which tab is up — a Spotlight result steers it to Deliveries.
    @State private var selectedTab = Tab.deliveries
    /// An order a Spotlight result asked for, retained until the store's first
    /// read can answer whether it's still in history — a cold start delivers the
    /// activity before `refresh()` lands (review, PR #42).
    @State private var pendingOrderID: UUID?
    @Environment(StoreController.self) private var store
    @Environment(ClaimsSyncController.self) private var sync
    @Environment(NotificationController.self) private var notifications
    @Environment(\.scenePhase) private var scenePhase

    enum Tab { case deliveries, settings }

    #if DEBUG
    /// UI-test seeding: a three-stop draft with real-length addresses, opened on the
    /// compose sheet — so screenshots exercise the layouts senders actually see
    /// (author, 2026-09-14: verify visually, not only by test count). Seeded as the
    /// @State *initial values* — an onAppear hook raced the sheet's first build and
    /// seeded flakily. DEBUG-only; release builds compile the plain initials.
    private static var opensComposing: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-three-stop-draft")
    }

    private static func initialDraft() -> NewDeliveryView.Model {
        let model = NewDeliveryView.Model()
        guard opensComposing else { return model }
        model.setPlace(
            PickedPlace(latitude: 55.7517, longitude: 37.6176,
                        address: "Москва, Николоямская улица, 49с1, подъезд 3"),
            for: model.points[0].id
        )
        model.setContact(Contact(givenName: "Иван", familyName: "Петров", phone: "+79123456789"), for: model.points[0].id)
        _ = model.addStop()
        model.setPlace(
            PickedPlace(latitude: 55.7601, longitude: 37.6492,
                        address: "Москва, Земляной Вал, 27с2, вход со двора, домофон 12"),
            for: model.points[1].id
        )
        model.setContact(Contact(givenName: "Анна", familyName: "Сидорова", phone: "+79987654321"), for: model.points[1].id)
        model.setPlace(
            PickedPlace(latitude: 55.7887, longitude: 37.6064,
                        address: "Москва, Новослободская улица, 73с1, офис 214"),
            for: model.points[2].id
        )
        var item = ParcelItem()
        item.name = "Ноутбук в чехле"
        item.cost = 60000
        model.setItem(item)
        return model
    }
    #else
    private static var opensComposing: Bool { false }
    private static func initialDraft() -> NewDeliveryView.Model { NewDeliveryView.Model() }
    #endif

    var body: some View {
        TabView(selection: $selectedTab) {
            DeliveriesView(
                compose: { isComposing = true },
                repeatOrder: { order, reversed in
                    // A repeat is a new draft, not a mutation of the parked one —
                    // whatever was half-composed is replaced, same as compose's
                    // `placed` reset mints a fresh idempotency token. The order's
                    // field values ride too — «Заказ 4417» is part of the repeat.
                    draft = NewDeliveryView.Model(
                        repeating: order, reversed: reversed,
                        fields: store.fields(for: order.id))
                    isComposing = true
                },
                pendingOrderID: $pendingOrderID
            )
                .tabItem { Label("Deliveries", systemSymbol: .shippingbox) }
                .tag(Tab.deliveries)
            SettingsView()
                .tabItem { Label("Settings", systemSymbol: .gearshape) }
                .tag(Tab.settings)
        }
        // A Spotlight result carries the order id — DeliveriesView pushes the row
        // once the store's read can confirm it's still in history.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String)
                .flatMap(UUID.init(uuidString:)) {
                pendingOrderID = id
                selectedTab = .deliveries
            }
        }
        // A tapped banner is the same ask as a Spotlight result: find the row
        // once the store can confirm it's still in history.
        .onChange(of: notifications.requestedOrderID) {
            if let id = notifications.consumeRequest() {
                pendingOrderID = id
                selectedTab = .deliveries
            }
        }
        // Leaving the foreground is when the refresh chain gets armed — the
        // system decides when it actually wakes the journal pass.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { sync.scheduleAppRefresh() }
        }
        .sheet(isPresented: $isComposing) {
            NewDeliveryView(
                draft: draft,
                placed: {
                    // The order lives in history now; the draft's job is done. A fresh
                    // model also mints a fresh idempotency token for the next run.
                    isComposing = false
                    draft = NewDeliveryView.Model()
                }
            )
        }
    }
}

#Preview {
    let session = ClientController(tokenStore: TokenStore(service: "preview.YDelivery"))
    let store = StoreController(database: nil)
    RootView()
        .environment(session)
        .environment(store)
        .environment(ClaimsSyncController(session: session, store: store, database: nil))
        .environment(NotificationController(store: store))
}
