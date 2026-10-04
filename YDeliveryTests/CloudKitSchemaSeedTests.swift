#if DEBUG
import Foundation
import GRDB
import Testing
import YDeliveryKit
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

    /// The isolation claim, proven on a real `AppDatabase`: the seed's rows go,
    /// a neighbour's stay. Two orders stand side by side — one under the seed's
    /// deterministic ids, one a stranger — with children in every table the
    /// seed writes, and `runSeedDeletions` must take back exactly one side.
    @Test("Seed rows are deleted, a neighbour's rows stay — on a real database")
    func deletionsTakeOnlySeedRows() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SeedDeletions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let database = AppDatabase(
            directory: directory, providerAccountRef: "yandex:ckschema-seed",
            containerIdentifier: "iCloud.test")

        // The seed's deterministic roots (the same derivation the seed runs)
        // beside a stranger's.
        func seedID(_ part: String) -> UUID {
            UUID.derived(namespace: UUID.DerivedNamespace.orderChild,
                         "ckschema-seed", part)
        }
        let orderID = seedID("order"), otherOrder = UUID()
        let orderPK = orderID.uuidString.lowercased()
        let t0 = Date(timeIntervalSince1970: 1_780_000_000)

        func order(_ id: UUID, _ address: String) -> Order {
            Order(id: id, created: t0, status: .cancelled,
                  route: [RoutePoint(latitude: 55.7, longitude: 37.6,
                                     address: address, role: .pickup),
                          RoutePoint(latitude: 55.8, longitude: 37.7,
                                     address: address + " Б")],
                  price: "1.00", currency: "RUB",
                  claimID: "c-" + id.uuidString)
        }
        for (order, field) in [(order(orderID, "Seed A"), seedID("field")),
                               (order(otherOrder, "Other A"), UUID())] {
            try database.recordOrder(
                order, customFields: [OrderCustomField(
                    orderID: order.id, fieldRef: field,
                    name: "f", value: "v")], providerObservedAt: t0)
            _ = try database.recordProviderEvent(ProviderEvent(
                orderID: order.id, providerEventID: 1, at: t0,
                kind: "status", providerStatus: "accepted", source: "journal"))
            try database.postMessage(OrderMessage(
                id: UUID(), orderID: order.id, sentAt: t0,
                kind: OrderMessage.Kind.text, text: "hi", authorHint: "T"))
            _ = try database.postPhotoMessage(
                orderID: order.id, data: Data([0x89, 0x50]),
                sentAt: t0, caption: "p", authorHint: "T")
        }
        try database.savePlace(SavedPlace(
            id: seedID("place"), name: "seed place", kind: .warehouse,
            point: RoutePoint(latitude: 1, longitude: 1, address: "seed"),
            pinned: true))
        try database.savePlace(SavedPlace(
            id: UUID(), name: "other place", kind: .warehouse,
            point: RoutePoint(latitude: 2, longitude: 2, address: "other")))
        try database.saveParcelTemplate(ParcelTemplate(
            id: seedID("template"), name: "seed t",
            items: [ParcelTemplate.Item(name: "i", quantity: 1, currency: "RUB")]))
        try database.saveParcelTemplate(ParcelTemplate(
            id: UUID(), name: "other t",
            items: [ParcelTemplate.Item(name: "i", quantity: 1, currency: "RUB")]))
        try database.saveFieldDefinition(CustomFieldDefinition(
            id: seedID("field"), name: "seed f"))
        try database.saveFieldDefinition(CustomFieldDefinition(
            id: UUID(), name: "other f"))

        // The rows no typed write reaches — the same minimal shape the seed
        // inserts, for both orders and both accounts.
        try await database.queue.write { db in
            for uuid in [orderID, otherOrder] {
                let pk = uuid.uuidString.lowercased()
                let pickupStopPK = UUID.derived(
                    namespace: UUID.DerivedNamespace.orderChild,
                    uuid.uuidString, "stop", "0"
                ).uuidString.lowercased()
                let dropoffStopPK = UUID.derived(
                    namespace: UUID.DerivedNamespace.orderChild,
                    uuid.uuidString, "stop", "1"
                ).uuidString.lowercased()
                try db.execute(sql: """
                    INSERT INTO "orderItems"
                      ("id", "orderID", "name", "quantity", "weightKg",
                       "cost", "currency", "sizeLengthCm", "sizeWidthCm",
                       "sizeHeightCm", "pickupStopRef", "dropoffStopRef")
                    VALUES (?, ?, 'i', 1, 0.5, '1.00',
                            'RUB', 10.0, 10.0, 5.0, ?, ?)
                    """, arguments: [
                        UUID().uuidString.lowercased(), pk,
                        pickupStopPK, dropoffStopPK])
                try db.execute(sql: """
                    INSERT INTO "orderOptions"
                      ("orderID", "proCourier", "toDoor", "thermobag",
                       "loaders", "due", "comment")
                    VALUES (?, 1, 0, 1, 2, ?, 'c')
                    """, arguments: [pk, t0.timeIntervalSince1970])
                try db.execute(sql: """
                    INSERT INTO "orderPrivateStates"
                      ("orderID", "personalNote", "pinned",
                       "lastSeenActivityAt")
                    VALUES (?, 'n', 1, ?)
                    """, arguments: [pk, t0.timeIntervalSince1970])
            }
            try db.execute(sql: """
                INSERT INTO "providerAccounts"
                  ("key", "provider", "corpClientID", "displayLabel",
                   "firstSeenAt", "lastSeenAt")
                VALUES (?, 'yandex', 'x', 'A', ?, ?)
                """, arguments: [
                    "yandex:ckschema-seed",
                    t0.timeIntervalSince1970, t0.timeIntervalSince1970])
            try db.execute(sql: """
                INSERT INTO "providerAccounts"
                  ("key", "provider", "corpClientID", "displayLabel",
                   "firstSeenAt", "lastSeenAt")
                VALUES (?, 'yandex', 'x', 'B', ?, ?)
                """, arguments: [
                    "yandex:other",
                    t0.timeIntervalSince1970, t0.timeIntervalSince1970])
        }

        _ = try await YDeliveryApp.runSeedDeletions(database: database, parent: false)
        _ = try await YDeliveryApp.runSeedDeletions(database: database, parent: true)

        func count(_ sql: String, _ arguments: [String] = []) async throws -> Int {
            try await database.queue.read { db in
                try Int.fetchOne(db, sql: sql,
                                 arguments: StatementArguments(arguments)) ?? 0
            }
        }

        // The seed's side is gone — every table, every qualifier.
        for table in ["routeStops", "orderItems", "orderProviderStates",
                      "orderOptions", "orderCustomFields", "providerEvents",
                      "orderMessages", "orderAttachments", "orderPrivateStates"] {
            #expect(try await count("""
                SELECT COUNT(*) FROM "\(table)" WHERE "orderID" = ?
                """, [orderPK]) == 0, "\(table) kept a seed row")
        }
        #expect(try await count("""
            SELECT COUNT(*) FROM "attachmentBlobs" WHERE "attachmentID" IN (
              SELECT "id" FROM "orderAttachments" WHERE "orderID" = ?)
            """, [orderPK]) == 0)
        #expect(try await count("""
            SELECT COUNT(*) FROM "orders" WHERE "id" = ?
            """, [orderPK]) == 0)
        #expect(try await count("""
            SELECT COUNT(*) FROM "providerAccounts" WHERE "key" = ?
            """, ["yandex:ckschema-seed"]) == 0)
        #expect(try await count("""
            SELECT COUNT(*) FROM "parcelTemplateItems" WHERE "templateID" = ?
            """, [seedID("template").uuidString.lowercased()]) == 0)
        #expect(try await count("""
            SELECT COUNT(*) FROM "parcelTemplates" WHERE "id" = ?
            """, [seedID("template").uuidString.lowercased()]) == 0)
        #expect(try await count("""
            SELECT COUNT(*) FROM "savedPlaces" WHERE "id" = ?
            """, [seedID("place").uuidString.lowercased()]) == 0)
        #expect(try await count("""
            SELECT COUNT(*) FROM "customFieldDefinitions" WHERE "id" = ?
            """, [seedID("field").uuidString.lowercased()]) == 0)

        // The neighbour's side stands whole — one order, two stops, one of
        // each child, two messages, one account, one place, one template.
        let expected: [String: Int] = [
            "orders": 1, "routeStops": 2, "orderItems": 1,
            "orderProviderStates": 1, "orderOptions": 1,
            "orderCustomFields": 1, "providerEvents": 1,
            "orderMessages": 2, "orderAttachments": 1, "attachmentBlobs": 1,
            "orderPrivateStates": 1, "savedPlaces": 1,
            "customFieldDefinitions": 1, "parcelTemplates": 1,
            "parcelTemplateItems": 1, "providerAccounts": 1,
        ]
        for (table, want) in expected {
            #expect(try await count("SELECT COUNT(*) FROM \"\(table)\"") == want,
                    "\(table) lost rows it never owned")
        }
    }
}
#endif
