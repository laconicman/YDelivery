import Foundation
import YDeliveryKit

/// The extension's half of the app's identity — the App Group it reads the
/// snapshot through. The value is the app's own (`AppGroup` in the app
/// target), duplicated because an extension cannot import the app.
nonisolated enum WidgetIdentity {
    static let appGroupID = "group.com.learnable.YDelivery"
}

/// The deep-link scheme the app answers — `DeepLink` in the app target is the
/// grammar's home; the extension only writes the URLs.
nonisolated enum WidgetLink {
    static func order(_ id: UUID) -> URL {
        URL(string: "ydelivery://order/\(id.uuidString)")!
    }
    static var compose: URL {
        URL(string: "ydelivery://compose")!
    }
    static func repeatOrder(_ id: UUID) -> URL {
        URL(string: "ydelivery://repeat?order=\(id.uuidString)")!
    }
}

/// What the surfaces read: the app's rendered snapshot, never the database —
/// the schema doc's widget contract. The live store stays unshared because a
/// suspended process holding a SQLite lock is a watchdog termination, and a
/// fully-protected file cannot be read from the Lock Screen at all. An
/// absent or unreadable snapshot is an empty surface, not a crash.
enum WidgetStore {
    static func load() -> DeliverySnapshot? {
        DeliverySnapshotStore.read(inAppGroup: WidgetIdentity.appGroupID)
    }
}
