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
    /// entitlement in `YDelivery.entitlements`. Schema epoch 2 (doc:Schema →
    /// "Epoch 2", decided 2026-10-06): the second container. The first,
    /// `iCloud.com.learnable.YDelivery`, is abandoned, never cleaned and never
    /// opened again; its store is imported into the epoch's file by the Kit on
    /// first open. Epochs are small integers, never semantic versions.
    static let cloudKitContainer = "iCloud.com.learnable.YDelivery.v2"
}
