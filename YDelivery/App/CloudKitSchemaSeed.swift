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
            catch { logger.error("seed failed — \(what): \(error)") }
        }

        // The engine's per-table tracking triggers install at *construction*,
        // and `startSync` performs it — idempotent, so the launch task's own
        // call is the one this lands behind either way. A row committed before
        // construction would persist locally yet leave no CloudKit footprint.
        await database.startSync()

        // A fixed reference moment and derived ids: a repeat launch rewrites
        // the same rows instead of accumulating seed litter — the substrate's
        // own derive-and-merge convention (doc:Schema).
        let t0 = Date(timeIntervalSince1970: 1_780_000_000)
        func seedID(_ part: String) -> UUID {
            UUID.derived(namespace: UUID.DerivedNamespace.orderChild,
                         "ckschema-seed", part)
        }
        let orderID = seedID("order")

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
        await seed("orderMessages") {
            try database.postMessage(OrderMessage(
                id: seedID("message"), orderID: orderID, sentAt: t0 + 600,
                kind: OrderMessage.Kind.text,
                text: "schema seed message", authorHint: "Seed"))
        }
        // A photo post covers what the text one cannot: `attachmentRef` on the
        // message, `orderAttachments`, and the blob that lands as a CKAsset.
        await seed("orderAttachments, attachmentBlobs") {
            try await store.postPhotoMessage(
                orderID: orderID, data: Data(Self.seedPNG),
                caption: "schema seed photo")
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
                    contactPhoneExtension: "9")))
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
                let orderPK = orderID.uuidString.lowercased()
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
                    VALUES (?, x'01', x'00', x'01', 2, ?, 'schema seed')
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
                    VALUES (?, 'schema seed note', x'01', ?)
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

        // Reflect the seeded order on screen — the run is a device operation,
        // so its rows should be visible in the list the launch leaves up.
        await store.refresh()

        // The push — sendChanges() is the manual flush the share seam already
        // uses; an absent iCloud account lands here as a thrown error the log
        // names, not a silence.
        do {
            try await database.syncEngine.sendChanges()
            logger.log("schema seed flushed — order \(orderID)")
        } catch {
            logger.error("schema seed flush failed: \(error)")
        }
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
