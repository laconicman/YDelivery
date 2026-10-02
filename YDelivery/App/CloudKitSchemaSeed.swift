import CloudKit
import Foundation
import OSLog
import SQLiteData
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

    #if DEBUG
    /// `--ckschema-seed`: populate the container's *development* schema by
    /// committing one fully-populated row to every table `SyncEngine` syncs.
    /// CloudKit creates record types lazily, on the first write of a record of
    /// that type — and a column that is NULL on every written record never
    /// becomes a record field — so each seeded row fills every column its table
    /// declares. What exists in development is what CloudKit Console's "Deploy
    /// Schema Changes" can promote to production, which TestFlight and
    /// App Store builds are locked to.
    ///
    /// This is deliberately unlike the `--uitest-*` fixtures: it writes the
    /// *real* App Group store — the writes must reach the real container — and
    /// it leaves those rows behind. The launch is kept signed out (the uitest
    /// Keychain service, see `tokenStore()`) so nothing touches the provider
    /// API; CloudKit sync does not depend on it. Spotlight, the widget snapshot
    /// and Live Activity stay silent too (`republication`/`reconciles`) — a
    /// schema fixture has no business on the owner's real surfaces.
    ///
    /// Verify with: `xcrun cktool export-schema --team-id WEJF495R4D
    /// --container-id iCloud.com.learnable.YDelivery --environment development`.
    static func seedCloudKitSchemaIfFlagged(
        _ store: StoreController, database: AppDatabase?
    ) async {
        guard isCloudKitSeed, let database else { return }
        let logger = Logger(subsystem: "YDelivery", category: "ckschema-seed")
        func seed(_ what: String, _ write: () async throws -> Void) async {
            do { try await write() }
            catch {
                logger.error("seed failed — \(what): \(error)")
                print("ckschema-seed failed — \(what): \(error)")
            }
        }
        print("ckschema-seed start")

        // The engine's per-table tracking triggers install at *construction*,
        // and `startSync` performs it — idempotent, so the launch task's own
        // call is the one this lands behind either way. A row committed before
        // construction would persist locally yet leave no CloudKit footprint.
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

        // A fixed reference moment and derived ids: a repeat launch rewrites
        // the same rows instead of accumulating seed litter — the substrate's
        // own derive-and-merge convention (doc:Schema).
        let t0 = Date(timeIntervalSince1970: 1_780_000_000)
        func seedID(_ part: String) -> UUID {
            UUID.derived(namespace: UUID.DerivedNamespace.orderChild,
                         "ckschema-seed", part)
        }
        let orderID = seedID("order")
        let orderPK = orderID.uuidString.lowercased()
        /// STRICT-TEXT keys bind lowercase strings (AppDatabase.args' rule).
        func hasRow(_ sql: String, _ key: String) -> Bool {
            (try? database.queue.read { db in
                try Bool.fetchOne(db, sql: sql, arguments: [key]) ?? false
            }) ?? false
        }
        // No global "already seeded" short-circuit: every step below is
        // self-converging (upserts, derived-id dedupe, or an explicit
        // preflight), so a rerun rewrites the same values and pushes — and a
        // partial earlier run always completes the rest.

        // Typed writes cover ten of the fourteen synced tables; the seeded
        // order populates `orders`, `routeStops` (address parts, contacts and
        // provider visits included), `orderProviderStates` and, through
        // `customFields`, `orderCustomFields`.
        let order = Order(
            id: orderID, created: t0, status: .active,
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
        // postMessage/postPhotoMessage are append-only INSERTs, not upserts —
        // on a rerun after a partial seed they are preflighted so a repeat
        // launch converges instead of erroring or duplicating.
        let messageID = seedID("message")
        if !hasRow("SELECT EXISTS(SELECT 1 FROM \"orderMessages\" WHERE \"id\" = ?)",
                   messageID.uuidString.lowercased()) {
            await seed("orderMessages") {
                try database.postMessage(OrderMessage(
                    id: messageID, orderID: orderID, sentAt: t0 + 600,
                    kind: OrderMessage.Kind.text,
                    text: "schema seed message", authorHint: "Seed"))
            }
        }
        // A photo post covers what the text one cannot: `attachmentRef` on the
        // message, `orderAttachments`, and the blob that lands as a CKAsset.
        // The preflight checks authorHint, not row existence — a rerun whose
        // earlier write predates the authorHint pass posts once more and then
        // converges.
        if !hasRow("""
            SELECT EXISTS(SELECT 1 FROM "orderAttachments"
                          WHERE "orderID" = ? AND "authorHint" IS NOT NULL)
            """, orderPK) {
            await seed("orderAttachments, attachmentBlobs") {
                // AppDatabase directly — StoreController's funnel drops
                // `authorHint`, and the schema wants the column populated.
                try database.postPhotoMessage(
                    orderID: orderID, data: Data(Self.seedPNG),
                    caption: "schema seed photo", authorHint: "Seed")
            }
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
                        SyncIdentity.providerAccountRef,
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

        // Reflect the seeded order on screen — the run is a device operation,
        // so its rows should be visible in the list the launch leaves up.
        await store.refresh()

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

        // sqlite-data swallows a re-insert under an existing primary key:
        // DELETE (or REPLACE's internal delete) marks the row's SyncMetadata
        // `_isDeleted` and queues a remote delete, and the INSERT that follows
        // lands on `ON CONFLICT DO NOTHING` — no save is ever queued. The
        // seed's own writes hit that on every rerun: `recordOrder` delete+inserts
        // `routeStops`/`orderCustomFields`, and `INSERT OR REPLACE` covers
        // `savedPlaces` plus the raw-SQL tables. A plain UPDATE is the one write
        // shape that always re-marks the row save-pending — so after the first
        // flush ships the deletes, these touches resurrect the rows remotely
        // and push them through the *current* serializer (which is what lets a
        // newly declared column, e.g. `building`, finally reach the schema).
        await seed("resurrect swallowed rewrites") {
            try database.queue.write { db in
                try db.execute(sql: """
                    UPDATE "routeStops" SET "building" = "building"
                    WHERE "orderID" = ?
                    """, arguments: [orderPK])
                try db.execute(sql: """
                    UPDATE "orderCustomFields" SET "value" = "value"
                    WHERE "orderID" = ?
                    """, arguments: [orderPK])
                try db.execute(sql: """
                    UPDATE "savedPlaces" SET "building" = "building"
                    WHERE "id" = ?
                    """, arguments: [seedID("place").uuidString.lowercased()])
                try db.execute(sql: """
                    UPDATE "orderOptions" SET "comment" = "comment"
                    WHERE "orderID" = ?
                    """, arguments: [orderPK])
                try db.execute(sql: """
                    UPDATE "orderItems" SET "name" = "name"
                    WHERE "orderID" = ?
                    """, arguments: [orderPK])
                try db.execute(sql: """
                    UPDATE "orderPrivateStates" SET "personalNote" = "personalNote"
                    WHERE "orderID" = ?
                    """, arguments: [orderPK])
                try db.execute(sql: """
                    UPDATE "providerAccounts" SET "displayLabel" = "displayLabel"
                    WHERE "key" = ?
                    """, arguments: [SyncIdentity.providerAccountRef])
                try db.execute(sql: """
                    UPDATE "parcelTemplates" SET "name" = "name"
                    WHERE "id" = ?
                    """, arguments: [seedID("template").uuidString.lowercased()])
                try db.execute(sql: """
                    UPDATE "parcelTemplateItems" SET "name" = "name"
                    WHERE "templateID" = ?
                    """, arguments: [seedID("template").uuidString.lowercased()])
            }
        }
        await flush("resurrected")
    }

    /// A 1×1 PNG — the attachment's bytes are opaque to the schema (a BLOB
    /// column becomes a CKAsset on the wire), but a real image keeps the seeded
    /// chat row renderable.
    private static let seedPNG: [UInt8] = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]
    #endif
}
