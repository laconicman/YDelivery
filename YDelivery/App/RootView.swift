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
    /// A repeat link that arrived before the store's first read — held, not
    /// dropped: the widget's snapshot outlives the app's memory, so a cold
    /// start must wait for the truth before saying an order isn't there
    /// (review, PR #44).
    @State private var pendingLink: DeepLink?
    @Environment(StoreController.self) private var store
    @Environment(ClaimsSyncController.self) private var sync
    @Environment(NotificationController.self) private var notifications
    @Environment(LiveActivityController.self) private var activities
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
        // once the store can confirm it's still in history. `initial: true`
        // because the delegate can answer before this view exists — a banner
        // tapped on a terminated app has already set the request by the time
        // the observer mounts (review, PR #43).
        .onChange(of: notifications.requestedOrderID, initial: true) {
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
        // Every order write — sync merge, placement, cancel — republishes this
        // list through the one funnel, so this is the one hook the Live
        // Activities need. `orderFields` rides too: the sender's number is a
        // card field, and a rename must reach a live card without waiting on
        // an order change. The widgets' half of a republish — the snapshot
        // render and the timeline reload — lives in the store itself, where
        // the file write can be sequenced before the reload ask.
        .onChange(of: store.orders, initial: true) { republishSurfaces() }
        .onChange(of: store.orderFields) { republishSurfaces() }
        // `hasLoaded` is its own trigger: an unread store reconciles nothing,
        // and the first read must also fire the pass that applies a parked
        // deep link and sweeps orphaned cards. Places publish in a second
        // pass — a repeat-by-place link re-parks until *that* read lands.
        .onChange(of: store.hasLoaded, initial: true) { republishSurfaces() }
        .onChange(of: store.hasLoadedPlaces, initial: true) { republishSurfaces() }
        // A widget, Live Activity or App Intent asks in URLs — the one channel
        // an extension has into the app's controllers (board `5b`/`5d`).
        .onOpenURL { url in
            if let link = DeepLink(url: url) { apply(link) }
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

    /// Reconcile Live Activities once the store has actually read — an unread
    /// store is not an empty one, and reconciling against `[]` would sweep
    /// every restored card as an orphan (review, PR #44). The same gate
    /// applies a deep link parked waiting on that read.
    private func republishSurfaces() {
        guard store.hasLoaded else { return }
        activities.reconcile(orders: store.orders,
                             orderNumber: store.orderNumber(for:))
        if let link = pendingLink {
            pendingLink = nil
            apply(link)
        }
    }

    /// What a `DeepLink` asks the app to do, mapped onto the same seams the
    /// list's own buttons use — a repeat is a fresh draft, never a mutation of
    /// the parked one. A link naming something the store no longer has is
    /// dropped: the widget's snapshot is older than the app's truth, and
    /// opening an empty draft would only pretend otherwise. Before the first
    /// read that rule can't run — a repeat is parked in `pendingLink` until
    /// the store can answer, rather than being mistaken for a miss.
    private func apply(_ link: DeepLink) {
        switch link {
        case .order(let id):
            pendingOrderID = id
            selectedTab = .deliveries
        case .compose:
            draft = NewDeliveryView.Model()
            isComposing = true
        case .repeatOrder(let id):
            guard store.hasLoaded else { pendingLink = link; return }
            guard let order = store.orders.first(where: { $0.id == id }) else { return }
            draft = NewDeliveryView.Model(
                repeating: order, fields: store.fields(for: order.id))
            isComposing = true
        case .repeatPlace(let id):
            // A saved place is a *destination* — the draft's last row takes the
            // point and whoever answers its door; the pickup stays the sender's
            // to fill, because a place remembers no origin.
            guard store.hasLoadedPlaces else { pendingLink = link; return }
            guard let place = store.savedPlaces.first(where: { $0.id == id }) else { return }
            let model = NewDeliveryView.Model()
            guard let destination = model.points.last?.id else { return }
            model.setPlace(PickedPlace(place.point), for: destination)
            model.setContact(Contact(at: place.point), for: destination)
            draft = model
            isComposing = true
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
        .environment(LiveActivityController())
}
