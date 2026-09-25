import AppIntents
import UIKit
import YDeliveryKit

/// The three App Intents board `5d` allots — "three, not thirty": the surfaces
/// Siri and Shortcuts get are deliberately narrow, each answering one sentence
/// the sender actually says.
///
/// All three run inside the app's process and read the shared App Group store
/// directly — the same substrate the widget extension reads — because an
/// intent must answer even when no controller has published yet (a cold start,
/// a Siri invocation over a locked phone). The read is the same `AppDatabase`
/// the app itself opened; nothing here writes.

/// A saved place as an intent parameter — «доставку в …» names the destination
/// the sender saved, never an address Siri would have to parse.
struct SavedPlaceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Saved place")

    var id: SavedPlace.ID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let defaultQuery = SavedPlaceQuery()
}

/// Places come from the shared store — a Shortcut run over a cold app still
/// lists what the sender saved.
struct SavedPlaceQuery: EntityQuery {
    func entities(for identifiers: [SavedPlace.ID]) async throws -> [SavedPlaceEntity] {
        try await IntentStore.places()
            .filter { identifiers.contains($0.id) }
            .map(SavedPlaceEntity.init(place:))
    }

    func suggestedEntities() async throws -> [SavedPlaceEntity] {
        try await IntentStore.places().map(SavedPlaceEntity.init(place:))
    }
}

private extension SavedPlaceEntity {
    init(place: SavedPlace) {
        self.init(id: place.id, name: place.name)
    }
}

/// The one store read the intents share — opened lazily, never synced: an
/// extension-adjacent surface reads what the app last wrote and starts nothing.
enum IntentStore {
    /// The same `AppDatabase` the app opens — app group, container, and the
    /// unattributed provider ref all named by the app's own constants.
    private static func open() -> AppDatabase? {
        AppDatabase.inAppGroup(
            id: AppGroup.id,
            providerAccountRef: SyncIdentity.providerAccountRef,
            containerIdentifier: SyncIdentity.cloudKitContainer)
    }

    static func orders() async throws -> [Order] {
        guard let database = open() else { return [] }
        return try database.readOrders()
    }

    static func places() async throws -> [SavedPlace] {
        guard let database = open() else { return [] }
        return try database.readPlaces()
    }

    static func orderNumber(for orderID: Order.ID) async throws -> String? {
        try open()?.orderNumber(for: orderID)
    }
}

/// «Где моя доставка» — Siri and Spotlight read the status aloud; no UI needed
/// (board `5d`). The optional place narrows which delivery when several ride —
/// «где моя доставка на склад» — matched by the destination's coordinates:
/// the saved place and the route's last point remember the same doorway.
struct WhereIsMyDeliveryIntent: AppIntent {
    static let title: LocalizedStringResource = "Where is my delivery"
    static let description = IntentDescription(
        "Reads the live status of an active delivery — no screen needed.")

    @Parameter(title: "Place")
    var place: SavedPlaceEntity?

    /// Two coordinates this close are the same doorway — generous enough for a
    /// geocoder's re-read, tight enough to separate a warehouse from the house
    /// across the street (~100 m).
    private static let sameDoorwayDegrees = 0.001

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let orders = try await IntentStore.orders()
        var live = orders.filter { order in
            order.claimID != nil
                && [.searching, .active, .attention].contains(order.status)
        }
        if let place {
            let point = try await placePoint(place)
            live = live.filter { order in
                guard let destination = order.route.last else { return false }
                return abs(destination.latitude - point.latitude)
                        < Self.sameDoorwayDegrees
                    && abs(destination.longitude - point.longitude)
                        < Self.sameDoorwayDegrees
            }
        }
        return .result(dialog: try await dialog(for: live))
    }

    private func placePoint(_ entity: SavedPlaceEntity) async throws -> RoutePoint {
        // A place deleted between suggestion and invocation: the parameter
        // names something gone — the intent must say so, not answer for
        // everything instead.
        guard let point = try await IntentStore.places()
            .first(where: { $0.id == entity.id })?.point
        else { throw IntentError.placeVanished }
        return point
    }

    private func dialog(for live: [Order]) async throws -> IntentDialog {
        switch live.count {
        case 0:
            return IntentDialog("No active deliveries.")
        case 1:
            return IntentDialog(stringLiteral: await spokenStatus(of: live[0]))
        default:
            let numbers = try await withThrowingTaskGroup(of: String?.self) { group in
                for order in live {
                    group.addTask { try await IntentStore.orderNumber(for: order.id) }
                }
                return try await group.reduce(into: []) { $0.append($1) }
            }.compactMap { $0 }
            let list = numbers.isEmpty ? "\(live.count) orders" : numbers.joined(separator: ", ")
            return IntentDialog(stringLiteral:
                "\(live.count) deliveries are active: \(list).")
        }
    }

    /// The status as one speakable sentence — the wire word's own phrase, the
    /// courier when one is assigned, the arrival when the provider gave one.
    private func spokenStatus(of order: Order) async -> String {
        let number = try? await IntentStore.orderNumber(for: order.id)
        let title = number.map { "Order №\($0)" } ?? "Your delivery"
        var parts = [order.spokenStatus]
        if let courier = order.courierName { parts.append(courier) }
        if let eta = order.etaAt {
            parts.append("by \(eta.formatted(date: .omitted, time: .shortened))")
        }
        return "\(title) — \(parts.joined(separator: ", "))."
    }

    enum IntentError: LocalizedError {
        case placeVanished
        var errorDescription: String? {
            "That saved place no longer exists — say the delivery's destination instead."
        }
    }
}

/// «Повторить доставку в …» — opens a pre-filled draft (board `5b`/`5d`):
/// the intent's job is to *open*, never to order — money must not move from a
/// widget tap, so the hand-off is the deep link the compose sheet answers.
struct RepeatDeliveryIntent: AppIntent {
    static let title: LocalizedStringResource = "Repeat delivery to…"
    static let description = IntentDescription(
        "Opens a new draft with the destination already filled.")
    static let openAppWhenRun = true

    @Parameter(title: "Place")
    var place: SavedPlaceEntity

    func perform() async throws -> some IntentResult {
        // In-process intents can hand off through the app's own URL scheme —
        // `OpenURLIntent`/`OpensIntent` are iOS 18, above this app's floor. The
        // sync `open` hops through MainActor: its async sibling's options dict
        // is non-Sendable, and we pass none anyway.
        await MainActor.run {
            UIApplication.shared.open(DeepLink.repeatPlace(place.id))
        }
        return .result()
    }
}

/// «Отправить по заказу …» — the sender's own number is the identifier they
/// think in (board `5d`): the intent turns it into the share text the customer
/// waits for — plain words, nothing to install.
struct SendOrderIntent: AppIntent {
    static let title: LocalizedStringResource = "Send order status"
    static let description = IntentDescription(
        "Reads an order by the sender's own number and returns its status text.")

    @Parameter(title: "Order number")
    var orderNumber: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let needle = orderNumber.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "№"))
        let orders = try await IntentStore.orders()
        for order in orders {
            if try await IntentStore.orderNumber(for: order.id)
                .map({ $0.trimmingCharacters(in: .whitespaces) == needle }) == true {
                let text = await shareText(for: order)
                return .result(value: text, dialog: IntentDialog(stringLiteral: text))
            }
        }
        throw IntentError.orderNotFound(needle)
    }

    /// The share card's words (board `5d`): status first, then where and who —
    /// the text the customer pastes into a chat, so it carries the vendor's
    /// tracking link only if the provider ever gave one.
    private func shareText(for order: Order) async -> String {
        let number = (try? await IntentStore.orderNumber(for: order.id)) ?? orderNumber
        var lines = ["Заказ №\(number) — \(order.spokenStatus)"]
        var tail: [String] = []
        if let eta = order.etaAt {
            tail.append("курьер будет у вас к \(eta.formatted(date: .omitted, time: .shortened))")
        }
        if let destination = order.route.last?.compactAddress {
            tail.append(destination)
        }
        if let courier = order.courierName {
            tail.append([courier, order.courierVehicle].compactMap { $0 }.joined(separator: ", "))
        }
        lines.append(tail.joined(separator: " · "))
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    enum IntentError: LocalizedError {
        case orderNotFound(String)
        var errorDescription: String? {
            switch self {
            case .orderNotFound(let number):
                "No order answers to №\(number) — check the number on the Deliveries list."
            }
        }
    }
}

private nonisolated extension Order {
    /// The wire word's own phrase, or the collapsed status's words when the
    /// provider has said nothing yet — the Kit's `ProviderStatusPhrase` is the
    /// one vocabulary every surface speaks.
    var spokenStatus: String {
        if let word = providerStatus,
           let phrase = ProviderStatusPhrase.phrase(for: word) {
            String(localized: phrase)
        } else {
            status.fallbackPhrase
        }
    }
}

private nonisolated extension OrderStatus {
    /// The collapsed word, when the provider has said nothing yet.
    var fallbackPhrase: String {
        switch self {
        case .draft: String(localized: "draft")
        case .searching: String(localized: "looking for a courier")
        case .active: String(localized: "on its way")
        case .done: String(localized: "delivered")
        case .attention: String(localized: "needs your decision")
        case .cancelled: String(localized: "cancelled")
        }
    }
}
