# The sqlite-data compile + schema spike — preserved (2026-09-25)

The scratch package whose results <doc:Collaboration> → "What the upstream pass
verified" reports — kept in-repo so the contracts the stack decision rests on stay
reproducible (an absent spike is an unverifiable claim). This is the file verbatim
from `/tmp/sd-spike` on the day it ran; the model shapes track <doc:Schema> — when the
contract moves, this file moves with it and is re-verified, or it stops being evidence.

## What it proves — compile level

- `@Table` models for the contract's full shape set compile under Swift 6: the zero-FK
  `Order` root; single-FK children (`RouteStop`, `OrderItem`, `ProviderEvent`,
  `OrderMessage`, `OrderAttachment`); the FK-as-PK one-to-one rows
  (`OrderProviderState`, `OrderOptions`, `AttachmentBlob`); `*Ref` columns as plain
  `UUID?` (never `SomeTable.ID` — an `.ID`-typed column invites an FK declaration, and
  a second FK ejects a child from the share); private-tier, device-tier, and draft
  tables.
- `SyncEngine(for:tables:privateTables:)` accepts the two-tier table split.
- `SyncEngine.share(record:configure:)` returns `SharedRecord`, the `configure`
  closure receives the `CKShare` (`publicPermission = .none` reachable);
  `unshare(record:)` exists.
- `acceptShare(metadata:)` takes a `CKShare.Metadata` — the scene-delegate handoff.
- `CloudSharingView` exists — gated `#if canImport(UIKit)`; the macOS scratch target
  proved the gate, not an absence. The app is iOS-only: satisfied.
- `isSynchronizing`/`isSendingChanges`/`isFetchingChanges` and manual
  `fetchChanges`/`sendChanges`/`syncChanges` are all present.
- The `check…` functions are deliberately **uncalled** — they are compile-time
  assertions that the API surface exists; calling them needs a CloudKit container,
  which is the device checklist, not this package.

## What it proves — runtime level

The executable actually **runs** schema validation: `withDependencies { .context =
.test }` swaps in `MockSyncEngineState` (no `CKContainer` — constructing one traps
without iCloud entitlements), while `setUpSyncEngine()` still runs `validateSchema()`
against the real DDL — FK graph, PK rules, and the uniqueness ban are exercised for
real. Verbatim output:

```text
database + DDL: OK
contract schema: SyncEngine accepted
uniqueness check: rejected as predicted — Could not synchronize data with iCloud.
spike done
```

- **The contract's DDL is accepted**: 9 shared tables (root 0-FK, single-FK children
  `ON DELETE CASCADE`, FK-as-PK 1:1s, `*Ref` columns with no `REFERENCES`), 3 private
  tables, device tables — `SyncEngine.init` validates all of it.
- **`UNIQUE(orderID, providerEventID)` is rejected** — `SchemaError
  .uniquenessConstraint`, exactly as Devin Review predicted (PR #36). The schema's
  answer is deterministic `ProviderEvent.id` derivation, not a secondary index.
- **`Draft` collides with the macro** — `@Table` synthesizes a `.Draft` nested type on
  every model; a table literally named `Draft` breaks inside the expansion. The
  contract's entity is `OrderDraft`. Found by this spike, not by reading.
- **No manual `attachMetadatabase`** — `SyncEngine.init` prepares its own; attaching
  one first throws `metadatabaseMismatch` (also learned the hard way here).

A detail the schema relies on, verified in source rather than compiled: FK-ness is
`PRAGMA foreign_key_list` on the created table — user-written DDL. A column without
`REFERENCES` is never an FK, whatever its Swift type; the `UUID?` convention for
`*Ref` columns keeps the intent legible rather than load-bearing.

## How to reproduce

```sh
mkdir /tmp/sd-spike && cd /tmp/sd-spike
swift package init --type executable
# write Package.swift and Sources/spike/main.swift as below
swift build && ./.build/debug/spike
```

`swift build` against `pointfreeco/sqlite-data` `1.12.0` completes clean (~10s);
running validates the schema in-process. `import Dependencies` resolves through
SQLiteData's own transitive dependency — no extra package entry needed.

## `Package.swift`

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "spike",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/sqlite-data", exact: "1.12.0")
    ],
    targets: [
        .executableTarget(
            name: "spike",
            dependencies: [.product(name: "SQLiteData", package: "sqlite-data")]
        )
    ]
)
```

## `Sources/spike/main.swift`

```swift
import CloudKit
import Dependencies
import Foundation
import GRDB
import SQLiteData
import SwiftUI

// MARK: - Contract shapes (Schema.md), exercising the real macro surface

// Share root — zero FKs by construction. providerAccountRef is a VALUE column.
@Table
nonisolated struct Order: Identifiable {
    let id: UUID
    var createdAt: Date = .init(timeIntervalSince1970: 0)
    var providerAccountRef: String?
    var provider = "yandex"
    var lastActivityAt: Date = .init(timeIntervalSince1970: 0)
}

// 1:1 provider mirror — PK is the FK (FK-as-PK pattern).
@Table
nonisolated struct OrderProviderState {
    @Column(primaryKey: true)
    var orderID: Order.ID
    var claimID: String?
    var corpClientID: String?
    var status = ""
    var providerStatus: String?
    var providerDetail: String?
    var tariff: String?
    var price: String?
    var currency: String?
    var dueAt: Date?
    var finishedAt: Date?
    var providerObservedAt: Date?
    var mirroredAt: Date = .init(timeIntervalSince1970: 0)
}

// 1:1 options row — same PK=FK pattern.
@Table
nonisolated struct OrderOptions {
    @Column(primaryKey: true)
    var orderID: Order.ID
    var proCourier = false
    var toDoor = true
    var thermobag = false
    var loaders = 0
    var due: Date?
    var comment = ""
}

// Single-FK child — shareable.
@Table
nonisolated struct RouteStop: Identifiable {
    let id: UUID
    var orderID: Order.ID
    var position = 0
    var role = ""
    var latitude = 0.0
    var longitude = 0.0
    var address = ""
    var entrance: String?
    var contactGivenName: String?
    var contactPhone: String?
}

// Journey endpoints are *Ref columns: plain UUID, NOT RouteStop.ID —
// an .ID-typed column would invite an FK declaration, a second FK, and
// exclusion from the share. Value references only.
@Table
nonisolated struct OrderItem: Identifiable {
    let id: UUID
    var orderID: Order.ID
    var name = ""
    var quantity = 1
    var weightKg: Double?
    var cost: String?
    var currency = "RUB"
    var pickupStopRef: UUID?
    var dropoffStopRef: UUID?
}

// Owner-written event feed. `id` is DETERMINISTIC — derived from the journal's
// (orderID, operation_id) — so identical events on two devices are one CKRecord,
// not a dedup problem. No secondary UNIQUE: SyncEngine rejects them.
@Table
nonisolated struct ProviderEvent: Identifiable {
    let id: UUID
    var orderID: Order.ID
    var providerEventID: Int64?
    var at: Date = .init(timeIntervalSince1970: 0)
    var kind = ""
    var providerStatus: String?
    var detail: String?
    var source = ""
}

// Append-only participant stream — the chat.
@Table
nonisolated struct OrderMessage: Identifiable {
    let id: UUID
    var orderID: Order.ID
    var sentAt: Date = .init(timeIntervalSince1970: 0)
    var kind = "text"
    var text: String?
    var attachmentRef: UUID?  // value → OrderAttachment.id, same-order rule at the write boundary
    var authorHint: String?
}

// Attachment + blob split, per the asset-table pattern.
@Table
nonisolated struct OrderAttachment: Identifiable {
    let id: UUID
    var orderID: Order.ID
    var kind = "photo"
    var caption: String?
    var byteSize: Int64?
    var createdAt: Date = .init(timeIntervalSince1970: 0)
    var authorHint: String?
}

@Table
nonisolated struct AttachmentBlob {
    @Column(primaryKey: true)
    var attachmentID: OrderAttachment.ID
    var data = Data()
}

// Private tier: synced to owner's private DB, never shareable.
@Table
nonisolated struct ProviderAccount {
    @Column(primaryKey: true)
    var key: String  // "yandex:<corpClientID>"
    var provider = "yandex"
    var corpClientID: String?
    var displayLabel: String?
    var lastSeenAt: Date?
}

@Table
nonisolated struct OrderPrivateState {
    @Column(primaryKey: true)
    var orderID: Order.ID
    var personalNote: String?
    var pinned = false
    var lastSeenActivityAt: Date?
}

@Table
nonisolated struct SavedPlace: Identifiable {
    let id: UUID
    var name = ""
    var kind = "other"
}

// Device tier: never registered with the SyncEngine — so UNIQUE indexes are
// legal here (the no-secondary-unique rule governs synchronized tables only).
@Table
nonisolated struct SyncState {
    @Column(primaryKey: true)
    var providerAccountRef: String
    var journalCursor: String?
    var historyBackfilled = false
}

@Table
nonisolated struct PendingDiscovery: Identifiable {
    let id: UUID
    var providerAccountRef = ""
    var claimID = ""
    var firstSeenAt: Date = .init(timeIntervalSince1970: 0)
    var lastAttemptAt: Date?
}

@Table
nonisolated struct PendingAcceptance: Identifiable {
    let id: UUID
    var providerAccountRef = ""
    var claimID: String?
    var orderRef: UUID?
    var createdAt: Date = .init(timeIntervalSince1970: 0)
    var lastCheckedAt: Date?
    var state = "pending"
}

// Provisional draft — device-local, mirrors the shared shape for promotion.
// Named OrderDraft, not Draft: @Table synthesizes a `.Draft` nested type on
// every model, so a table literally named Draft collides inside the macro.
@Table
nonisolated struct OrderDraft: Identifiable {
    let id: UUID
    var createdAt: Date = .init(timeIntervalSince1970: 0)
}

@Table
nonisolated struct DraftStop: Identifiable {
    let id: UUID
    var draftID: OrderDraft.ID
    var position = 0
    var role = ""
}

@Table
nonisolated struct DraftItem: Identifiable {
    let id: UUID
    var draftID: OrderDraft.ID
    var name = ""
}

// MARK: - API surface checks (compile-time assertions — deliberately uncalled;
// running them needs a CloudKit container, which is the device checklist)

func checkShareAPI() async throws {
    @Dependency(\.defaultSyncEngine) var syncEngine
    let order = Order(id: UUID())

    let shared = try await syncEngine.share(record: order) { share in
        share[CKShare.SystemFieldKey.title] = "Delivery"
        share.publicPermission = .none
    }

    #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
    _ = CloudSharingView(sharedRecord: shared)
    #else
    _ = shared.share.url
    #endif

    try await syncEngine.unshare(record: order)

    let metadata: CKShare.Metadata? = nil
    if let metadata {
        try await syncEngine.acceptShare(metadata: metadata)
    }
}

func checkSyncFlags() {
    @Dependency(\.defaultSyncEngine) var syncEngine
    _ = syncEngine.isSynchronizing
    _ = syncEngine.isSendingChanges
    _ = syncEngine.isFetchingChanges
}

func checkManualSync() async throws {
    @Dependency(\.defaultSyncEngine) var syncEngine
    try await syncEngine.fetchChanges()
    try await syncEngine.sendChanges()
    try await syncEngine.syncChanges()
}

// MARK: - Runtime schema validation — the contract's DDL against SyncEngine.init

func contractDatabase(extraDDL: String = "") throws -> any DatabaseWriter {
    // No manual attachMetadatabase: SyncEngine.init prepares its own, and a
    // mismatch between the two is a startup error (verified: metadatabaseMismatch).
    let db = try DatabaseQueue(configuration: Configuration())
    try db.write { db in
        try db.execute(sql: """
            CREATE TABLE "\(Order.tableName)" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "createdAt" REAL NOT NULL,
              "providerAccountRef" TEXT,
              "provider" TEXT NOT NULL,
              "lastActivityAt" REAL NOT NULL
            ) STRICT;
            CREATE TABLE "\(OrderProviderState.tableName)" (
              "orderID" TEXT PRIMARY KEY NOT NULL
                REFERENCES "\(Order.tableName)"("id") ON DELETE CASCADE,
              "claimID" TEXT, "corpClientID" TEXT, "status" TEXT NOT NULL,
              "providerStatus" TEXT, "providerDetail" TEXT,
              "tariff" TEXT, "price" TEXT, "currency" TEXT,
              "dueAt" REAL, "finishedAt" REAL,
              "providerObservedAt" REAL, "mirroredAt" REAL NOT NULL
            ) STRICT;
            CREATE TABLE "\(OrderOptions.tableName)" (
              "orderID" TEXT PRIMARY KEY NOT NULL
                REFERENCES "\(Order.tableName)"("id") ON DELETE CASCADE,
              "proCourier" INTEGER NOT NULL, "toDoor" INTEGER NOT NULL,
              "thermobag" INTEGER NOT NULL, "loaders" INTEGER NOT NULL,
              "due" REAL, "comment" TEXT NOT NULL
            ) STRICT;
            CREATE TABLE "\(RouteStop.tableName)" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "orderID" TEXT NOT NULL
                REFERENCES "\(Order.tableName)"("id") ON DELETE CASCADE,
              "position" INTEGER NOT NULL, "role" TEXT NOT NULL,
              "latitude" REAL NOT NULL, "longitude" REAL NOT NULL,
              "address" TEXT NOT NULL, "entrance" TEXT,
              "contactGivenName" TEXT, "contactPhone" TEXT
            ) STRICT;
            CREATE TABLE "\(OrderItem.tableName)" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "orderID" TEXT NOT NULL
                REFERENCES "\(Order.tableName)"("id") ON DELETE CASCADE,
              "name" TEXT NOT NULL, "quantity" INTEGER NOT NULL,
              "weightKg" REAL, "cost" TEXT, "currency" TEXT NOT NULL,
              "pickupStopRef" TEXT, "dropoffStopRef" TEXT
            ) STRICT;
            CREATE TABLE "\(ProviderEvent.tableName)" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "orderID" TEXT NOT NULL
                REFERENCES "\(Order.tableName)"("id") ON DELETE CASCADE,
              "providerEventID" INTEGER, "at" REAL NOT NULL,
              "kind" TEXT NOT NULL, "providerStatus" TEXT,
              "detail" TEXT, "source" TEXT NOT NULL
            ) STRICT;
            CREATE TABLE "\(OrderMessage.tableName)" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "orderID" TEXT NOT NULL
                REFERENCES "\(Order.tableName)"("id") ON DELETE CASCADE,
              "sentAt" REAL NOT NULL, "kind" TEXT NOT NULL,
              "text" TEXT, "attachmentRef" TEXT, "authorHint" TEXT
            ) STRICT;
            CREATE TABLE "\(OrderAttachment.tableName)" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "orderID" TEXT NOT NULL
                REFERENCES "\(Order.tableName)"("id") ON DELETE CASCADE,
              "kind" TEXT NOT NULL, "caption" TEXT, "byteSize" INTEGER,
              "createdAt" REAL NOT NULL, "authorHint" TEXT
            ) STRICT;
            CREATE TABLE "\(AttachmentBlob.tableName)" (
              "attachmentID" TEXT PRIMARY KEY NOT NULL
                REFERENCES "\(OrderAttachment.tableName)"("id") ON DELETE CASCADE,
              "data" BLOB NOT NULL
            ) STRICT;
            CREATE TABLE "\(ProviderAccount.tableName)" (
              "key" TEXT PRIMARY KEY NOT NULL,
              "provider" TEXT NOT NULL, "corpClientID" TEXT,
              "displayLabel" TEXT, "lastSeenAt" REAL
            ) STRICT;
            CREATE TABLE "\(OrderPrivateState.tableName)" (
              "orderID" TEXT PRIMARY KEY NOT NULL
                REFERENCES "\(Order.tableName)"("id") ON DELETE CASCADE,
              "personalNote" TEXT, "pinned" INTEGER NOT NULL,
              "lastSeenActivityAt" REAL
            ) STRICT;
            CREATE TABLE "\(SavedPlace.tableName)" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "name" TEXT NOT NULL, "kind" TEXT NOT NULL
            ) STRICT;
            CREATE TABLE "\(SyncState.tableName)" (
              "providerAccountRef" TEXT PRIMARY KEY NOT NULL,
              "journalCursor" TEXT, "historyBackfilled" INTEGER NOT NULL
            ) STRICT;
            CREATE TABLE "\(PendingDiscovery.tableName)" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "providerAccountRef" TEXT NOT NULL, "claimID" TEXT NOT NULL,
              "firstSeenAt" REAL NOT NULL, "lastAttemptAt" REAL,
              UNIQUE("providerAccountRef", "claimID")
            ) STRICT;
            CREATE TABLE "\(PendingAcceptance.tableName)" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "providerAccountRef" TEXT NOT NULL, "claimID" TEXT,
              "orderRef" TEXT, "createdAt" REAL NOT NULL,
              "lastCheckedAt" REAL, "state" TEXT NOT NULL
            ) STRICT;
            CREATE TABLE "\(OrderDraft.tableName)" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "createdAt" REAL NOT NULL
            ) STRICT;
            CREATE TABLE "\(DraftStop.tableName)" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "draftID" TEXT NOT NULL
                REFERENCES "\(OrderDraft.tableName)"("id") ON DELETE CASCADE,
              "position" INTEGER NOT NULL, "role" TEXT NOT NULL
            ) STRICT;
            CREATE TABLE "\(DraftItem.tableName)" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "draftID" TEXT NOT NULL
                REFERENCES "\(OrderDraft.tableName)"("id") ON DELETE CASCADE,
              "name" TEXT NOT NULL
            ) STRICT;
            \(extraDDL)
            """)
    }
    return db
}

func checkContractSchema() throws {
    let db = try contractDatabase()
    let engine = try SyncEngine(
        for: db,
        tables: Order.self, OrderProviderState.self, OrderOptions.self,
            RouteStop.self, OrderItem.self, ProviderEvent.self,
            OrderMessage.self, OrderAttachment.self, AttachmentBlob.self,
        privateTables: ProviderAccount.self, OrderPrivateState.self, SavedPlace.self,
        containerIdentifier: "iCloud.spike",
        startImmediately: false
    )
    _ = engine
    print("contract schema: SyncEngine accepted")
}

func checkUniquenessRejected() throws {
    let db = try contractDatabase(extraDDL: """
        CREATE UNIQUE INDEX "eventDedup" ON "\(ProviderEvent.tableName)"
          ("orderID", "providerEventID");
        """)
    do {
        _ = try SyncEngine(
            for: db,
            tables: Order.self, OrderProviderState.self, OrderOptions.self,
                RouteStop.self, OrderItem.self, ProviderEvent.self,
                OrderMessage.self, OrderAttachment.self, AttachmentBlob.self,
            privateTables: ProviderAccount.self, OrderPrivateState.self, SavedPlace.self,
            containerIdentifier: "iCloud.spike",
            startImmediately: false
        )
        print("uniqueness check: engine ACCEPTED (unexpected)")
    } catch {
        print("uniqueness check: rejected as predicted — \(error.localizedDescription)")
    }
}

func report(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

// .test context → MockSyncEngineState: no CKContainer (which traps without
// iCloud entitlements), but validateSchema() still runs on the real DDL —
// FK graph, uniqueness, and PK rules are all exercised for real.
try withDependencies {
    $0.context = .test
} operation: {
    do {
        let db = try contractDatabase()
        report("database + DDL: OK")
        _ = db
    } catch {
        report("contractDatabase threw: \(error)")
        throw error
    }
    do {
        try checkContractSchema()
    } catch {
        report("checkContractSchema threw: \(error)")
        throw error
    }
    try checkUniquenessRejected()
}
report("spike done")
```

## What it does not prove

Compile-verified signatures and local schema validation are not sync behavior. The
open items it cannot touch — end-to-end share acceptance, App Clip entry, the
two-tokens-one-`corp_client_id` wire test, actual iCloud propagation — stand in
<doc:Collaboration> → "Open verifications".

## See Also

- <doc:Collaboration> — the research this spike serves
- <doc:Schema> — the schema the verified shapes implement
