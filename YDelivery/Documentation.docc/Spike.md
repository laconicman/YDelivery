# The sqlite-data compile spike — preserved (2026-09-25)

The scratch package whose results <doc:Collaboration> → "What the upstream pass
verified" reports — kept in-repo so the contracts the stack decision rests on stay
reproducible (a review finding worth absorbing: an absent spike is an unverifiable
claim). This is the file verbatim from `/tmp/sd-spike` on the day it compiled.

## What it proves

- `@Table` models with the schema's shapes: a zero-FK root, single-FK children, an
  FK-as-PK one-to-one blob row, and a private table — all compile under Swift 6.
- `SyncEngine(for:tables:privateTables:)` accepts the two-tier table split.
- `SyncEngine.share(record:configure:)` returns `SharedRecord`, the `configure`
  closure receives the `CKShare` (title set, `publicPermission = .none` reachable).
- `acceptShare(metadata:)` takes a `CKShare.Metadata` — the scene-delegate handoff.
- `CloudSharingView` exists — gated `#if canImport(UIKit)` (iOS/tvOS only); the macOS
  scratch target proved the gate, not an absence. The app is iOS-only: satisfied.
- `isSynchronizing`/`isSendingChanges`/`isFetchingChanges` and manual
  `fetchChanges`/`sendChanges`/`syncChanges` are all present.

## How to reproduce

```sh
mkdir /tmp/sd-spike && cd /tmp/sd-spike
swift package init --type executable
# write Package.swift and Sources/spike/main.swift as below
swift build
```

`swift build` against `pointfreeco/sqlite-data` `1.12.0` completed clean — every call
below compiled and linked (9.44s on this machine). The version is pinned by `from:` +
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

// MARK: - Draft schema shapes, exercising the real macro surface

@Table
nonisolated struct Order: Identifiable {
    let id: UUID
    var createdAt: Date = .init(timeIntervalSince1970: 0)
    var status = ""
    var claimID: String?
    var providerAccountID: String?
    var price: String?
    var currency: String?
    var tariff: String?
    var finishedAt: Date?
    var statusDetail: String?
    var externalRef: String?
}

// Single-FK child — the parent edge, shareable.
@Table
nonisolated struct RoutePoint: Identifiable {
    let id: UUID
    var orderID: Order.ID
    var position = 0
    var kind = ""
    var latitude = 0.0
    var longitude = 0.0
    var address = ""
    var entrance: String?
    var contactGivenName: String?
    var contactPhone: String?
}

// Journey endpoints as *positions*, not FKs — the one-FK share rule.
@Table
nonisolated struct ParcelItem: Identifiable {
    let id: UUID
    var orderID: Order.ID
    var name = ""
    var weightKg: Double?
    var pickupOrdinal = 0
    var dropOrdinal = 0
}

// Attachment + blob split, per the asset-table pattern.
@Table
nonisolated struct Attachment: Identifiable {
    let id: UUID
    var orderID: Order.ID
    var kind = ""
    var createdAt: Date = .init(timeIntervalSince1970: 0)
}

@Table
nonisolated struct AttachmentBlob {
    @Column(primaryKey: true)
    var attachmentID: Attachment.ID
    var data = Data()
}

// Participant-writable collaborative rows.
@Table
nonisolated struct OrderNote: Identifiable {
    let id: UUID
    var orderID: Order.ID
    var authorLabel: String?
    var text = ""
    var createdAt: Date = .init(timeIntervalSince1970: 0)
}

// Synced-but-never-shared.
@Table
nonisolated struct ProviderAccount: Identifiable {
    let id: UUID
    var corpClientID: String?
    var label: String?
}

// Device-only: never registered with the SyncEngine.
@Table
nonisolated struct DeviceSyncState {
    @Column(primaryKey: true)
    var id: Int
    var journalCursor: String?
    var historyBackfilled = false
    var pendingClaimIDsJSON = "[]"
}

// MARK: - API surface checks

func checkSyncEngineInit() throws {
    @Dependency(\.defaultDatabase) var database
    let engine = try SyncEngine(
        for: database,
        tables: Order.self, RoutePoint.self, ParcelItem.self,
            Attachment.self, AttachmentBlob.self, OrderNote.self,
        privateTables: ProviderAccount.self
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
