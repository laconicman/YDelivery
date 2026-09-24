import Foundation

/// The two identifiers the shared substrate needs this app to name — the Kit takes
/// both by parameter (its rule 2: nothing in the package binds one app). They live
/// together because they serve one job: telling sync whose position and whose
/// CloudKit container this device's store answers to.
nonisolated enum SyncIdentity {
    /// The `syncStates`/`pendingDiscoveries` key this device reads and writes until a
    /// credential's `corpClientID` is learned — the schema keys on
    /// `"yandex:<corpClientID>"`, and today's sync runs unattributed, same as migrated
    /// orders. Reconciliation re-keys when the account surfaces.
    static let providerAccountRef = "yandex:unattributed"

    /// The CloudKit container the shared/private tiers sync through — matches the
    /// entitlement in `YDelivery.entitlements`.
    static let cloudKitContainer = "iCloud.com.learnable.YDelivery"
}
