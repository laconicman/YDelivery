import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

/// What remains app-side after the substrate moved to YDeliveryKit: the checks that
/// only the app's own identity can exercise — the entitlement probe reads
/// `Bundle.main`'s real profile, and the profile fixture asserts *this* app's
/// container constant. Substrate behavior (schema, tiers, migration, round-trips)
/// is covered by the Kit's own suite at the module boundary.
@Suite("Persistence — app identity")
struct PersistenceTests {
    private let directory: URL

    init() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The gate must pass on every host we ship or test on — on the simulator there
    /// is no embedded profile, which reads as *proceed* (the xcent is generated from
    /// YDelivery.entitlements, so it cannot drift inside this repo).
    @Test("The entitlement gate passes on this host")
    func iCloudEntitlementGatePasses() {
        let database = AppDatabase(
            directory: directory,
            providerAccountRef: SyncIdentity.providerAccountRef,
            containerIdentifier: SyncIdentity.cloudKitContainer)
        #expect(database.iCloudEntitled)
    }

    /// The profile check with the app's own container — the consumer supplies the
    /// identifier; this pins that `SyncIdentity` names the entitled one.
    @Test("The provisioning-profile check reads CloudKit service and container")
    func profileCheckReadsCloudKit() {
        let container = SyncIdentity.cloudKitContainer
        let good: [String: Any] = ["Entitlements": [
            "com.apple.developer.icloud-services": ["CloudKit", "CloudDocuments"],
            "com.apple.developer.icloud-container-identifiers": [container],
        ]]
        #expect(AppDatabase.profileAllowsCloudKit(good, containerIdentifier: container))
        #expect(!AppDatabase.profileAllowsCloudKit(
            ["Entitlements": [:]], containerIdentifier: container),
                "a profile without iCloud must fail the gate")
        #expect(!AppDatabase.profileAllowsCloudKit(["Entitlements": [
            "com.apple.developer.icloud-services": ["CloudKit"],
            "com.apple.developer.icloud-container-identifiers": ["iCloud.other.App"],
        ]], containerIdentifier: container), "a foreign container must fail the gate")
    }
}
