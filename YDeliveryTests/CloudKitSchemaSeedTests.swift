#if DEBUG
import Foundation
import Testing
@testable import YDelivery

/// The schema seed's clean pass deletes only what a seed run wrote — the
/// isolated store shares the container's zones, so an unqualified
/// `DELETE FROM <table>` would ship tombstones for the owner's genuine
/// records (Devin review, PR #90 round 4). These tests pin the rule down at
/// the statement list: every delete is `WHERE`-qualified, and the table list
/// covers every synced table the seed writes — a table added to the seed
/// without a matching qualified delete fails loudly here, not on someone's
/// history.
@Suite("CloudKit schema seed deletions")
struct CloudKitSchemaSeedTests {
    private let deletions = YDeliveryApp.seedDeletions(
        orderID: UUID(), placeID: UUID(), templateID: UUID(), fieldID: UUID(),
        accountKey: "yandex:ckschema-seed")

    @Test("Every delete is WHERE-qualified — none is a bare DELETE FROM <table>")
    func everyDeleteIsQualified() {
        let bare = try! Regex("(?i)^\\s*DELETE\\s+FROM\\s+\"\\w+\"\\s*\\.?\\s*$")
        for deletion in deletions {
            #expect(deletion.sql.contains("WHERE"),
                    "\(deletion.table) has no qualifier: \(deletion.sql)")
            #expect(deletion.sql.firstMatch(of: bare) == nil,
                    "\(deletion.table) is row-blind: \(deletion.sql)")
        }
    }

    @Test("The statement list covers every synced table the seed writes")
    func coversEverySeededTable() {
        let seededTables: Set<String> = [
            "orders", "routeStops", "orderItems", "orderProviderStates",
            "orderOptions", "orderCustomFields", "providerEvents",
            "orderMessages", "orderAttachments", "attachmentBlobs",
            "orderPrivateStates", "savedPlaces", "customFieldDefinitions",
            "parcelTemplates", "parcelTemplateItems", "providerAccounts",
        ]
        #expect(Set(deletions.map(\.table)) == seededTables)
    }

    @Test("Children delete before roots — CloudKit validates references per batch")
    func childrenFlushBeforeRoots() {
        let phases = deletions.map(\.parent)
        if let firstParent = phases.firstIndex(of: true) {
            #expect(phases[..<firstParent].allSatisfy { !$0 },
                    "a child delete must never follow a root delete")
        }
    }
}
#endif
