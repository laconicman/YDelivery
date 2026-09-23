# The sqlite-data compile spike — preserved (2026-09-25)

The scratch package whose results <doc:Collaboration> → "What the upstream pass
verified" reports — kept in-repo so the contracts the stack decision rests on stay
reproducible (a review finding worth absorbing: an absent spike is an unverifiable
claim). This is the file verbatim from `/tmp/sd-spike` on the day it compiled; the
model shapes track <doc:Schema> — when the contract moves, this file moves with it and
is re-verified, or it stops being evidence (a review finding, same lesson).

## What it proves

- `@Table` models for the contract's full shape set compile under Swift 6: the zero-FK
  `Order` root; single-FK children (`RouteStop`, `OrderItem`, `ProviderEvent`,
  `OrderMessage`, `OrderAttachment`); the FK-as-PK one-to-one rows
  (`OrderProviderState`, `OrderOptions`, `AttachmentBlob`); the `*Ref` columns as plain
  `UUID?` (never `SomeTable.ID` — an `.ID`-typed column is what invites an FK
  declaration, and a second FK ejects a child from the share); private-tier and
  device-tier tables.
- `SyncEngine(for:tables:privateTables:)` accepts the two-tier table split.
- `SyncEngine.share(record:configure:)` returns `SharedRecord`, the `configure`
  closure receives the `CKShare` (title set, `publicPermission = .none` reachable);
  `unshare(record:)` exists and compiles.
- `acceptShare(metadata:)` takes a `CKShare.Metadata` — the scene-delegate handoff.
- `CloudSharingView` exists — gated `#if canImport(UIKit)` (iOS/tvOS only); the macOS
  scratch target proved the gate, not an absence. The app is iOS-only: satisfied.
- `isSynchronizing`/`isSendingChanges`/`isFetchingChanges` and manual
  `fetchChanges`/`sendChanges`/`syncChanges` are all present.

A detail the schema relies on, verified in the package source rather than compiled:
FK-ness is `PRAGMA foreign_key_list` on the created table — user-written DDL. A column
without `REFERENCES` is never an FK, whatever its Swift type; the `UUID?` convention
for `*Ref` columns keeps the intent legible rather than load-bearing.

## How to reproduce

```sh
mkdir /tmp/sd-spike && cd /tmp/sd-spike
swift package init --type executable
# write Package.swift and Sources/spike/main.swift as below
swift build
```

`swift build` against `pointfreeco/sqlite-data` `1.12.0` completed clean — every call
below compiled and linked (~10s on this machine). The version is pinned by `from:` +
`Package.resolved`, not by memory.

## `Package.swift`

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "spike",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.12.0")
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

// Owner-written event feed. providerEventID = journal operation_id.
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

// Device tier: never registered with the SyncEngine.
@Table
nonisolated struct SyncState {
    @Column(primaryKey: true)
    var providerAccountRef: String
    var journalCursor: String?
    var historyBackfilled = false
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

// MARK: - API surface checks

func checkSyncEngineInit() throws {
    @Dependency(\.defaultDatabase) var database
    let engine = try SyncEngine(
        for: database,
        tables: Order.self, OrderProviderState.self, OrderOptions.self,
            RouteStop.self, OrderItem.self, ProviderEvent.self,
            OrderMessage.self, OrderAttachment.self, AttachmentBlob.self,
        privateTables: ProviderAccount.self, OrderPrivateState.self, SavedPlace.self
    )
    _ = engine
}

func checkShareAPI() async throws {
    @Dependency(\.defaultSyncEngine) var syncEngine
    let order = Order(id: UUID())

    // share(root:) → SharedRecord, configure closure receives CKShare
    let shared = try await syncEngine.share(record: order) { share in
        share[CKShare.SystemFieldKey.title] = "Delivery"
        share.publicPermission = .none
    }

    // CloudSharingView wraps UICloudSharingController — iOS only by design.
    #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
    _ = CloudSharingView(sharedRecord: shared)
    #else
    _ = shared.share.url
    #endif

    try await syncEngine.unshare(record: order)

    // acceptance path takes CKShare.Metadata
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

print("spike compiles")
```

## What it does not prove

Compile-verified signatures are not runtime behavior. The open items it cannot touch —
end-to-end share acceptance, App Clip entry, the two-tokens-one-`corp_client_id` wire
test — stand in <doc:Collaboration> → "Open verifications".

## See Also

- <doc:Collaboration> — the research this spike serves
- <doc:Schema> — the schema the verified shapes implement
