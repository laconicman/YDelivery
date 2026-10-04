import CloudKit
import Foundation
import GRDB
import OSLog
import SQLiteData
import UIKit
import YDeliveryKit

extension YDeliveryApp {
    /// Whether this launch was asked to seed the CloudKit development schema —
    /// `--ckschema-seed`. Read at composition like ``isHistoryFixture``: in a
    /// release build the flag does not exist and this is always false.
    static var isCloudKitSeed: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ckschema-seed")
        #else
        false
        #endif
    }

    /// Whether this launch was asked to take the seed's rows back —
    /// `--ckschema-seed-clean`. Same DEBUG-only reading.
    static var isCloudKitSeedClean: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ckschema-seed-clean")
        #else
        false
        #endif
    }

    #if DEBUG
    /// The seed's own store: a throwaway `AppDatabase` under Application
    /// Support, emptied-and-removed at the start of every run — never the App
    /// Group store.
    /// Writes through it still reach the real *container* (the sync engine
    /// takes `SyncIdentity.cloudKitContainer`), so the record types land where
    /// "Deploy Schema Changes" promotes from; the rows themselves are deleted
    /// before the run ends, and a crashed run's leftovers belong to an account
    /// ref (`yandex:ckschema-seed`) no real order carries, sitting in a store
    /// the app never opens — the TestFlight incident's seed-order-in-history
    /// shape cannot recur (YD-26's class).
    private static var seedDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ckschema-seed", isDirectory: true)
    }

    private static func seedDatabase(fresh: Bool) -> AppDatabase {
        if fresh {
            try? FileManager.default.removeItem(at: seedDirectory)
        }
        return AppDatabase(
            directory: seedDirectory,
            providerAccountRef: "yandex:ckschema-seed",
            containerIdentifier: SyncIdentity.cloudKitContainer)
    }

    /// `--ckschema-seed`: populate the container's *development* schema by
    /// committing one fully-populated row to every table `SyncEngine` syncs —
    /// CloudKit creates record types lazily, on the first write of a record of
    /// that type, and a column that is NULL on every written record never
    /// becomes a record field — then deleting those rows again, so the schema
    /// stays while no seed litter remains on the wire. The first `sendChanges`
    /// is load-bearing: record types register on upload.
    ///
    /// A fresh isolated database means every write is a first INSERT — the
    /// sqlite-data re-insert swallow (YD-34) needs a prior tombstone under the
    /// same key, so no resurrection pass is needed or wanted.
    ///
    /// Verify with: `xcrun cktool export-schema --team-id WEJF495R4D
    /// --container-id iCloud.com.learnable.YDelivery --environment development`.
    static func seedCloudKitSchemaIfFlagged() async {
        guard isCloudKitSeed else { return }
        let logger = Logger(subsystem: "YDelivery", category: "ckschema-seed")
        if FileManager.default.fileExists(atPath: seedDirectory.path) {
            // Orphans before the wipe: an interrupted run may have uploaded
            // rows whose ids only the leftover store knows — photo and
            // attachment ids are *not* derived — so its rows are emptied and
            // their tombstones shipped *before* the directory is removed and
            // the fresh one is cut.
            print("ckschema-seed leftover store — taking its rows back first")
            await emptyExistingSeedStore(logger: logger)
            try? FileManager.default.removeItem(at: seedDirectory)
        }
        let database = seedDatabase(fresh: true)
        // A controller over the seed store gives the typed save paths without
        // touching the app's real store (which never starts sync on this
        // launch — see `YDeliveryApp.init`).
        let store = StoreController(database: database, republishing: .none)
        func seed(_ what: String, _ write: () async throws -> Void) async {
            do { try await write() }
            catch {
                logger.error("seed failed — \(what): \(error)")
                print("ckschema-seed failed — \(what): \(error)")
            }
        }
        print("ckschema-seed start")

        // The engine's per-table tracking triggers install at *construction*,
        // and `startSync` performs it — so it must precede the writes: a row
        // committed before construction persists locally yet leaves no
        // CloudKit footprint.
        await database.startSync()

        // Everything downstream is silent without an iCloud account — the
        // substrate's startTask returns at its accountStatus guard and
        // sendChanges then has no engines to push through — so the probe prints
        // before the writes, not after they fail invisibly. rawValue: 0
        // couldNotDetermine · 1 available · 2 restricted · 3 noAccount ·
        // 4 temporarilyUnavailable.
        let container = CKContainer(identifier: SyncIdentity.cloudKitContainer)
        let status = try? await container.accountStatus()
        print("ckschema-seed accountStatus=\(status?.rawValue ?? -1) isRunning=\((try? database.syncEngine.isRunning) ?? false)")
        print("ckschema-seed entitled=\(database.iCloudEntitled) syncStartFailure=\(database.syncStartFailure?.localizedDescription ?? "none")")

        // Derived ids: the clean pass and any retried run name the same rows.
        let t0 = Date(timeIntervalSince1970: 1_780_000_000)
        func seedID(_ part: String) -> UUID {
            UUID.derived(namespace: UUID.DerivedNamespace.orderChild,
                         "ckschema-seed", part)
        }
        let orderID = seedID("order")
        let orderPK = orderID.uuidString.lowercased()

        // Typed writes cover the bulk of the synced tables; the seeded order
        // populates `orders`, `routeStops` (address parts, contacts and
        // provider visits included), `orderProviderStates` and, through
        // `customFields`, `orderCustomFields`. `.cancelled` on purpose: a run
        // that dies between the flushes leaves a terminal row, never a live
        // delivery — and a terminal order never starts a Live Activity.
        let order = Order(
            id: orderID, created: t0, status: .cancelled,
            route: [
                RoutePoint(
                    latitude: 55.7558, longitude: 37.6173,
                    address: "Москва, Никольская, 10 (schema seed)",
                    addressParts: AddressParts(
                        building: "1", entrance: "2", floor: "3",
                        apartment: "4", intercom: "5"),
                    contactName: "Seed Sender",
                    contactGivenName: "Seed", contactFamilyName: "Sender",
                    contactPhone: "+70000000001", contactPhoneExtension: "11",
                    visit: RoutePoint.Visit(
                        status: .visited, visitedAt: t0 + 300,
                        expectedAt: t0 + 240),
                    role: .pickup),
                RoutePoint(
                    latitude: 55.7422, longitude: 37.6156,
                    address: "Москва, Пятницкая, 25 (schema seed)",
                    contactName: "Seed Receiver",
                    contactGivenName: "Seed", contactFamilyName: "Receiver",
                    contactPhone: "+70000000002", contactPhoneExtension: "22",
                    visit: RoutePoint.Visit(
                        status: .pending, expectedAt: t0 + 900),
                    role: .dropoff),
            ],
            price: "1.00", currency: "RUB", tariff: "express",
            claimID: "ckschema-seed-claim",
            courierName: "Seed Courier", courierVehicle: "seed 000 xx 77",
            etaMinutes: 7, providerStatus: "performer_found",
            providerObservedAt: t0)
        let definition = CustomFieldDefinition(
            id: seedID("field"),
            name: "Schema seed", kind: .choice,
            choices: ["seed-a", "seed-b"],
            isOptional: true, isShownByDefault: true,
            carrier: .none, position: 0)

        await seed("customFieldDefinitions") {
            try await store.saveField(definition)
        }
        await seed("orders, routeStops, orderProviderStates, orderCustomFields") {
            // `providerObservedAt` is load-bearing twice over: it is the
            // mirror's as-of stamp, and an *un*stamped recordOrder strips stop
            // visits — leaving visitStatus/visitedAt/expectedVisitAt NULL and
            // the record short three fields.
            try await store.record(
                order, customFields: [OrderCustomField(
                    orderID: orderID, fieldRef: definition.id,
                    name: definition.name, value: "seed-a",
                    carrier: definition.carrier)],
                providerObservedAt: order.providerObservedAt)
        }
        // `providerDetail` is the one orderProviderStates column recordOrder
        // never writes — the event detail is its only typed source.
        await seed("providerEvents") {
            _ = try database.recordProviderEvent(ProviderEvent(
                orderID: orderID, providerEventID: 1, at: t0 + 120,
                kind: "status", providerStatus: "performer_found",
                detail: "schema seed detail", source: "journal"))
        }
        await seed("orderMessages") {
            try database.postMessage(OrderMessage(
                id: seedID("message"), orderID: orderID, sentAt: t0 + 600,
                kind: OrderMessage.Kind.text,
                text: "schema seed message", authorHint: "Seed"))
        }
        // A photo post covers what the text one cannot: `attachmentRef` on the
        // message, `orderAttachments`, and the blob that lands as a CKAsset.
        await seed("orderAttachments, attachmentBlobs") {
            // AppDatabase directly — StoreController's funnel drops
            // `authorHint`, and the schema wants the column populated.
            try database.postPhotoMessage(
                orderID: orderID, data: Self.seedPNG(),
                caption: "schema seed photo", authorHint: "Seed")
        }
        await seed("savedPlaces") {
            try await store.save(SavedPlace(
                id: seedID("place"),
                name: "Schema seed place", kind: .warehouse,
                point: RoutePoint(
                    latitude: 55.75, longitude: 37.62,
                    address: "Москва, Схемная, 1 (schema seed)",
                    addressParts: AddressParts(
                        building: "1", entrance: "1", floor: "1",
                        apartment: "1", intercom: "1"),
                    contactName: "Seed Place",
                    contactGivenName: "Seed", contactFamilyName: "Place",
                    contactPhone: "+70000000003",
                    contactPhoneExtension: "9"),
                pinned: true))
        }
        // The sender's library (doc:Roadmap): `saveParcelTemplate` upserts the
        // root and rewrites `parcelTemplateItems` wholesale, so one typed write
        // populates both synced tables.
        await seed("parcelTemplates, parcelTemplateItems") {
            try database.saveParcelTemplate(ParcelTemplate(
                id: seedID("template"),
                name: "Schema seed template", pinned: true,
                items: [ParcelTemplate.Item(
                    id: seedID("templateItem"),
                    name: "schema seed parcel", quantity: 2,
                    weightKg: 0.5, cost: "1.00", currency: "RUB",
                    sizeLengthCm: 10.0, sizeWidthCm: 10.0,
                    sizeHeightCm: 5.0)]))
        }

        // Four synced tables no typed write reaches — `orderOptions`,
        // `orderItems`, `orderPrivateStates` and `providerAccounts` are
        // reservations awaiting their features — plus the providerState columns
        // only the future claims-merge writes (`corpClientID`, `dueAt`,
        // `finishedAt`). Raw SQL on the same `queue` is the same channel the
        // engine's triggers observe; for these rows it is the only door there
        // is. STRICT-TEXT ids go in as lowercase uuid strings — the convention
        // `AppDatabase.args` enforces for the handwritten SQL it keeps internal.
        await seed("orderOptions, orderItems, orderPrivateStates, providerAccounts") {
            try database.queue.write { db in
                // The stop ids `insertStops` derives for this order's route —
                // the journey ends name real rows, not dangling references.
                let pickupStopPK = UUID.derived(
                    namespace: UUID.DerivedNamespace.orderChild,
                    orderID.uuidString, "stop", "0"
                ).uuidString.lowercased()
                let dropoffStopPK = UUID.derived(
                    namespace: UUID.DerivedNamespace.orderChild,
                    orderID.uuidString, "stop", "1"
                ).uuidString.lowercased()
                try db.execute(sql: """
                    INSERT OR REPLACE INTO "orderOptions"
                      ("orderID", "proCourier", "toDoor", "thermobag",
                       "loaders", "due", "comment")
                    VALUES (?, 1, 0, 1, 2, ?, 'schema seed')
                    """, arguments: [orderPK, t0.timeIntervalSince1970 + 3_600])
                try db.execute(sql: """
                    INSERT OR REPLACE INTO "orderItems"
                      ("id", "orderID", "name", "quantity", "weightKg",
                       "cost", "currency", "sizeLengthCm", "sizeWidthCm",
                       "sizeHeightCm", "pickupStopRef", "dropoffStopRef")
                    VALUES (?, ?, 'schema seed parcel', 1, 0.5, '1.00',
                            'RUB', 10.0, 10.0, 5.0, ?, ?)
                    """, arguments: [
                        seedID("item").uuidString.lowercased(), orderPK,
                        pickupStopPK, dropoffStopPK])
                try db.execute(sql: """
                    INSERT OR REPLACE INTO "orderPrivateStates"
                      ("orderID", "personalNote", "pinned",
                       "lastSeenActivityAt")
                    VALUES (?, 'schema seed note', 1, ?)
                    """, arguments: [orderPK, t0.timeIntervalSince1970 + 600])
                try db.execute(sql: """
                    INSERT OR REPLACE INTO "providerAccounts"
                      ("key", "provider", "corpClientID", "displayLabel",
                       "firstSeenAt", "lastSeenAt")
                    VALUES (?, 'yandex', 'ckschema-seed', 'Schema seed', ?, ?)
                    """, arguments: [
                        "yandex:ckschema-seed",
                        t0.timeIntervalSince1970, t0.timeIntervalSince1970])
                try db.execute(sql: """
                    UPDATE "orderProviderStates" SET
                      "corpClientID" = 'ckschema-seed',
                      "dueAt" = ?, "finishedAt" = ?
                    WHERE "orderID" = ?
                    """, arguments: [
                        t0.timeIntervalSince1970 + 3_600,
                        t0.timeIntervalSince1970 + 7_200, orderPK])
            }
        }

        // Local truth check — the seed's own columns as the store holds them,
        // so a schema miss can be blamed on upload or on the write, not guessed.
        let buildings = (try? await database.queue.read { db in
            try String.fetchAll(db, sql: """
                SELECT "building" FROM "routeStops" WHERE "building" IS NOT NULL
                UNION SELECT "building" FROM "savedPlaces"
                WHERE "building" IS NOT NULL
                """)
        }) ?? []
        print("ckschema-seed buildings=\(buildings)")

        // The push — sendChanges() is the manual flush the share seam already
        // uses; an absent iCloud account lands here as a thrown error the log
        // names, not a silence.
        func flush(_ tag: String) async {
            do {
                try await database.syncEngine.sendChanges()
                let running = try database.syncEngine.isRunning
                logger.log("schema seed \(tag) — order \(orderID)")
                print("ckschema-seed \(tag) — order \(orderID) isRunning=\(running)")
            } catch {
                logger.error("schema seed \(tag) failed: \(error)")
                print("ckschema-seed \(tag) failed: \(error)")
            }
        }
        await flush("flushed")

        // Upload proof, the `reachedCloud` read: `lastKnownServerRecord` set is
        // the engine's own "iCloud holds this record". The root order for the
        // shared tier, a private-state row for the private zone.
        func reachedCloud(recordType: String, primaryKey: String) -> Bool {
            (try? database.queue.read { db in
                try Bool.fetchOne(db, sql: """
                    SELECT "lastKnownServerRecord" IS NOT NULL
                    FROM "sqlitedata_icloud_metadata"
                    WHERE "recordPrimaryKey" = ? AND "recordType" = ?
                    """, arguments: [primaryKey, recordType]) ?? false
            }) ?? false
        }
        print("ckschema-seed reachedCloud order=\(reachedCloud(recordType: "orders", primaryKey: orderPK)) privateState=\(reachedCloud(recordType: "orderPrivateStates", primaryKey: orderPK))")

        // The schema is registered; the rows go home. Children first, and in
        // their own flush: CloudKit validates references per record, so the
        // `orders` delete must land after its children are already gone —
        // one batched operation loses the tombstone to a reference violation.
        await seed("delete the seed's children") {
            try await Self.deleteSeedRows(database: database, parents: false)
        }
        await flush("children deleted")
        await seed("delete the seed's roots") {
            try await Self.deleteSeedRows(database: database, parents: true)
        }
        await flush("deleted")
        print("ckschema-seed done")
    }

    /// The deterministic root ids every qualifier below names — the same
    /// `seedID` derivations the writes use, so a clean pass reaches the seed's
    /// own rows and nothing else.
    private static var seedRoots: (order: UUID, place: UUID, template: UUID,
                                   field: UUID, accountKey: String) {
        func id(_ part: String) -> UUID {
            UUID.derived(namespace: UUID.DerivedNamespace.orderChild,
                         "ckschema-seed", part)
        }
        return (id("order"), id("place"), id("template"), id("field"),
                "yandex:ckschema-seed")
    }

    /// Every delete a clean pass is allowed to run — *every statement carries a
    /// `WHERE` naming the seed's deterministic root id or a child column
    /// hanging under it*. Unqualified deletes are forbidden here: the isolated
    /// store shares the container's zones, so anything sync fetched — a
    /// `fetchChanges()` call or `startSync`'s own pull — is *in this database*,
    /// and a bare `DELETE FROM <table>` would ship a tombstone for an owner's
    /// genuine record (Devin review, PR #90 round 4). Photo/attachment orphans
    /// need no row-blindness — their non-deterministic ids still hang under
    /// the seed's `orderID`. `parent` marks the two flush phases: children go
    /// first because CloudKit validates `parent` references per batch.
    nonisolated static func seedDeletions(
        orderID: UUID, placeID: UUID, templateID: UUID, fieldID: UUID,
        accountKey: String
    ) -> [(table: String, sql: String, arguments: [String], parent: Bool)] {
        let orderPK = orderID.uuidString.lowercased()
        let byOrder = "DELETE FROM \"%@\" WHERE \"orderID\" = ?"
        return [
            // The blob keys off the attachment, whose `orderID` qualifies it.
            ("attachmentBlobs", """
                DELETE FROM "attachmentBlobs" WHERE "attachmentID" IN (
                  SELECT "id" FROM "orderAttachments" WHERE "orderID" = ?)
                """, [orderPK], false),
            ("routeStops", String(format: byOrder, "routeStops"), [orderPK], false),
            ("orderItems", String(format: byOrder, "orderItems"), [orderPK], false),
            ("orderProviderStates", String(format: byOrder, "orderProviderStates"), [orderPK], false),
            ("orderOptions", String(format: byOrder, "orderOptions"), [orderPK], false),
            ("orderCustomFields", String(format: byOrder, "orderCustomFields"), [orderPK], false),
            ("providerEvents", String(format: byOrder, "providerEvents"), [orderPK], false),
            ("orderMessages", String(format: byOrder, "orderMessages"), [orderPK], false),
            ("orderAttachments", String(format: byOrder, "orderAttachments"), [orderPK], false),
            ("orderPrivateStates", String(format: byOrder, "orderPrivateStates"), [orderPK], false),
            ("parcelTemplateItems", """
                DELETE FROM "parcelTemplateItems" WHERE "templateID" = ?
                """, [templateID.uuidString.lowercased()], false),
            // Roots — same rule, their own ids.
            ("orders", """
                DELETE FROM "orders" WHERE "id" = ? AND "provider" = ?
                """, [orderPK, "yandex"], true),
            ("parcelTemplates", """
                DELETE FROM "parcelTemplates" WHERE "id" = ?
                """, [templateID.uuidString.lowercased()], true),
            ("savedPlaces", """
                DELETE FROM "savedPlaces" WHERE "id" = ?
                """, [placeID.uuidString.lowercased()], true),
            ("customFieldDefinitions", """
                DELETE FROM "customFieldDefinitions" WHERE "id" = ?
                """, [fieldID.uuidString.lowercased()], true),
            ("providerAccounts", """
                DELETE FROM "providerAccounts" WHERE "key" = ?
                """, [accountKey], true),
        ]
    }

    /// Runs one phase of ``seedDeletions`` — children or roots — through raw
    /// SQL on `queue`, the same channel the engine's triggers observe. Returns
    /// the deleted row count per table (`changesCount`).
    private static func runSeedDeletions(
        database: AppDatabase, parent: Bool
    ) async throws -> [String: Int] {
        let roots = seedRoots
        let deletions = seedDeletions(
            orderID: roots.order, placeID: roots.place,
            templateID: roots.template, fieldID: roots.field,
            accountKey: roots.accountKey
        ).filter { $0.parent == parent }
        return try await database.queue.write { db in
            var counts: [String: Int] = [:]
            for deletion in deletions {
                try db.execute(
                    sql: deletion.sql,
                    arguments: StatementArguments(deletion.arguments))
                let deleted = db.changesCount
                if deleted > 0 { counts[deletion.table] = deleted }
            }
            return counts
        }
    }

    /// Every row a seed run wrote, removed — the seed's own take-back pass at
    /// the end of a run. Same qualified statements as the clean pass (a delete
    /// in this file is *never* unqualified — see ``seedDeletions``); the caller
    /// flushes between children and roots.
    private static func deleteSeedRows(database: AppDatabase, parents: Bool) async throws {
        _ = try await runSeedDeletions(database: database, parent: parents)
    }

    /// `--ckschema-seed-clean`: take back the rows of a seed run that died
    /// mid-flight — or of an older seed revision that left them — without
    /// rewriting anything. Opens the isolated directory if a run left one and
    /// ships tombstones for the seed's own rows only.
    static func cleanCloudKitSeedIfFlagged() async {
        guard isCloudKitSeedClean else { return }
        let logger = Logger(subsystem: "YDelivery", category: "ckschema-seed")
        guard FileManager.default.fileExists(atPath: seedDirectory.path) else {
            print("ckschema-seed clean: no seed store — nothing to take back")
            return
        }
        await emptyExistingSeedStore(logger: logger)
    }

    /// The clean pass proper — shared by `--ckschema-seed-clean` and the head
    /// of a seed run that finds a leftover store. Assumes `seedDirectory`
    /// exists. Never fetches: the isolated store shares the container's zones,
    /// so a pull would install the owner's *real* rows here — and any delete
    /// that followed could only be made safe by staying qualified, which is
    /// why ``seedDeletions`` is the only statement list this file runs (Devin
    /// review, PR #90 round 4). With no fetch, deletes bind to the record
    /// versions this store last knew, which is the correct basis anyway.
    private static func emptyExistingSeedStore(logger: Logger) async {
        let database = seedDatabase(fresh: false)
        await database.startSync()
        do {
            var counts = try await runSeedDeletions(database: database, parent: false)
            try await database.syncEngine.sendChanges()
            counts.merge(
                try await runSeedDeletions(database: database, parent: true)) { $1 }
            try await database.syncEngine.sendChanges()
            let detail = counts.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            print("ckschema-seed clean deleted \(detail.isEmpty ? "nothing" : detail)")
            print("ckschema-seed clean done")
        } catch {
            logger.error("seed clean failed: \(error)")
            print("ckschema-seed clean failed: \(error)")
        }
    }

    /// A 1×1 PNG rendered, not literal bytes — decodable by construction. The
    /// attachment's bytes are opaque to the schema (a BLOB column becomes a
    /// CKAsset on the wire), but a real image keeps the seeded chat row
    /// renderable.
    private static func seedPNG() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).pngData { context in
            UIColor.systemGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
    #endif
}
