# Schema — the relational design (2026-09-25)

The data model the app migrates to, designed before it is implemented. The author chose
the slow path deliberately (2026-09-25): the app has never shipped, so the schema may be
organized the way it should be rather than the way it happened. This file is the contract
the `sqlite-data` integration implements; until then it is a decision record, not code.

Ground rules, stated once: every entity gets a stated key, stated integrity, and a stated
authority; relational discipline is the default and every deviation is named and priced;
and the CloudKit sharing arithmetic — not convenience — decides where foreign keys may
live (<doc:Collaboration> for the stack research this design sits on).

## The three laws the schema must satisfy

From the verified `sqlite-data` semantics (spike, `sqlite-data` 1.12.0; the package's own
`CloudKitSharing` article):

1. **A shareable root has zero foreign keys.** `SyncEngine.share` rejects any record
   whose table declares even one.
2. **A child joins a share iff it has exactly one foreign key**, pointing at the shared
   root directly or transitively through other single-FK children. Two or more FKs and
   the row is silently *not* shared.
3. **FK-ness is a schema fact, not a type fact.** The engine reads
   `PRAGMA foreign_key_list` — a column holding another row's UUID is a foreign key only
   if the `CREATE TABLE` declares `REFERENCES`. This is what makes the `*Ref` convention
   below legal.

A fourth law from CloudKit itself: a record participates in **at most one share** — so an
order cannot sit under both a per-order share and a workspace share. The granularity
choice is exclusive, and this schema chooses per-order.

## Sync tiers

`SyncEngine.init(for:tables:privateTables:)` divides the world three ways, and the schema
is organized by which list a table lands in:

| Tier | Registration | Reaches |
|---|---|---|
| **Shared** | `tables:` | Owner's iCloud private DB; participants via `CKShare` when the root is shared |
| **Private** | `privateTables:` | Owner's iCloud private DB across their devices; never shareable |
| **Device** | not registered | This device only — no CloudKit at all |

Membership in a share is **not a table** — it rides the `CKShare` participant list, which
`UICloudSharingController`/`CloudSharingView` already manages. No `Collaborator` entity
exists by design.

## The shared hierarchy — root `Order`

The order is the share root: the one thing a sender chooses to show a collaborator. Its
row is deliberately minimal — identity and creation, nothing else — because everything
with an author or a lifecycle hangs below it.

```
Order ─────────────────────────── share root, 0 FK
 ├─ RouteStop          orderID → Order          1 FK ✓ shared
 ├─ OrderItem          orderID → Order          1 FK ✓ shared
 │    (pickupStopRef, dropoffStopRef — values, NOT FKs)
 ├─ OrderProviderState orderID → Order (PK=FK)  1 FK ✓ shared, 1:1
 ├─ ProviderEvent      orderID → Order          1 FK ✓ shared
 ├─ OrderAnnotation    orderID → Order          1 FK ✓ shared
 ├─ OrderTag           orderID → Order          1 FK ✓ shared (provisional)
 └─ OrderAttachment    orderID → Order          1 FK ✓ shared
      └─ AttachmentBlob attachmentID → (PK=FK)  1 FK ✓ shared transitively
```

### `Order` — the root

| Column | Type | Note |
|---|---|---|
| `id` | UUID PK | |
| `createdAt` | Date | Local creation — meaningful offline history before any provider ack |
| `providerAccountRef` | TEXT | **Value, not FK** — matches `ProviderAccount.key` on the private side. Cannot be an FK: the root must have none |
| `provider` | TEXT | `"yandex"` today; provider plurality is a column, not a schema version |
| `lastActivityAt` | Date | Owner-maintained list ordering — denormalized, stated as such |

No `claimID` here — the provider mirror carries it (below), keeping every provider-derived
fact in one owner-written row.

### `OrderProviderState` — the mirror (1:1)

The whole provider projection in one row, overwritten atomically when the owner's journal
sync lands. PK **is** the FK (`orderID` as primary key + `REFERENCES orders`) — the
one-to-"at most one" pattern, which is also how the row's authority reads: one order, one
provider truth, one writer.

| Column | Type | Note |
|---|---|---|
| `orderID` | UUID PK + FK → `Order` | |
| `claimID` | TEXT? | The vendor's id — nil until the provider assigns one |
| `corpClientID` | TEXT? | Which provider account this rides; visible inside the share, opaque |
| `status` | TEXT | Mapped `OrderStatus` — the six the UI speaks |
| `providerStatus` | TEXT? | The wire's own spelling, kept for detail display (the 27-status zoo) |
| `providerDetail` | TEXT? | JSON of provider fields we render but don't model — refusal reasons, «без списания» flags. A documented hatch: the provider vocabulary is unstable, and display-only fields don't earn columns |
| `tariff`, `price`, `currency` | TEXT? | Price stays the minor-precision decimal string "exactly as agreed" (the substrate's convention) |
| `dueAt`, `finishedAt` | Date? | Scheduled pickup; completion — the field the 3e card needs |
| `providerObservedAt` | Date? | When the owner's sync last *saw* this state — the "as of" stamp shared surfaces render (author's staleness decision, <doc:Collaboration>) |
| `mirroredAt` | Date | When this row was written — distinct from observed: the mirror can lag the sighting |

### `RouteStop` — the route

One row per stop in travel order. Columns are atomic (Codd): the `AddressParts` bundle
flattens to `entrance`/`floor`/`apartment`/`intercom`, and the contact flattens to
`contactGivenName`/`contactFamilyName`/`contactPhone`/`contactPhoneExtension` — plus
`contactName`, the formatted whole the wire speaks, deliberately duplicated (name parsing
is lossy; both forms are kept, as `RoutePoint` already does).

| Column | Type | Note |
|---|---|---|
| `id` | UUID PK | Stable identity — reorders never renumber it |
| `orderID` | UUID FK → `Order` | The one FK |
| `position` | Int | Travel order; mutable on reorder. Items reference stops by `id`, never by position, so reordering never breaks journeys |
| `role` | TEXT | `pickup` / `dropoff` / `return` — the sender's vocabulary |
| `latitude`, `longitude` | Double | |
| `address` | TEXT | The courier-readable whole |
| `entrance`, `floor`, `apartment`, `intercom` | TEXT? | AddressParts, flattened |
| `contactName`, `contactGivenName`, `contactFamilyName`, `contactPhone`, `contactPhoneExtension` | TEXT? | Both forms, one stop |

### `OrderItem` — the parcel contents

| Column | Type | Note |
|---|---|---|
| `id` | UUID PK | |
| `orderID` | UUID FK → `Order` | The one FK |
| `name`, `quantity` | TEXT, Int | |
| `weightKg` | Double? | Per unit, matching the wire's reading (package TD-21 flagged) |
| `cost`, `currency` | Decimal-as-TEXT?, TEXT | Declared value + ISO 4217 |
| `sizeLengthCm`, `sizeWidthCm`, `sizeHeightCm` | Double? | Atomic — the UI's centimetres, conversion at the controller boundary |
| `pickupStopRef`, `dropoffStopRef` | UUID? | **Values, not FKs** — see the `*Ref` convention. Nil reads as the route's ends |

### `ProviderEvent` — the history feed (owner-written)

Append-only; conflicts impossible by construction. `kind` + `at` + `providerStatus` +
`detail`? + `source` (`journal`/`search`/`claimCard`). This is the activity timeline the
3e card reads, and what "members see each other's activity" means for provider truth.

### `OrderAnnotation` — the collaborative feed (participant-writable)

Notes, corrections, «the entrance is 3 not 2». Append-only, `at` + `kind` + `text` +
`authorHint` (display name cached; CloudKit's `createdBy`/`lastModifiedBy` system fields
carry the real attribution for free). This is the participant-writable counterpart to
`ProviderEvent` — the write boundary expressed *in the schema*, not just in code review.

### `OrderAttachment` + `AttachmentBlob` — parcel photos

Metadata row (`id`, `orderID`, `createdAt`, `kind`, `caption`, `byteSize`, `authorHint`)
with the payload in a 1:1 `AttachmentBlob` child (`attachmentID` PK+FK, `data` BLOB).
`sqlite-data` turns BLOB columns into `CKAsset` automatically, and the package's own
guidance is exactly this split — keep megabytes out of the metadata row so list queries
never drag image data. Participants may add photos (a receiver documenting condition is
the product story); blobs inherit the share transitively through the single-FK chain.

### `OrderTag` — provisional

`orderID` + `title`, deliberately denormalized per-order rather than a many-to-many join —
the package's own refactor pattern, since join-table rows carry two FKs and can never be
shared. Tag vocabulary dedup happens in queries. Provisional: included to pin the pattern
before a real tagging feature leans on it.

## The private tier — synced, never shared

| Table | Key | Columns of note | FKs |
|---|---|---|---|
| `ProviderAccount` | `key` TEXT PK (`"yandex:<corpClientID>"`) | `provider`, `corpClientID`, `displayLabel`, `firstSeenAt`, `lastSeenAt` | none needed — orders reference it by value |
| `OrderPrivateState` | `orderID` PK + FK → `Order` | `personalNote`, `pinned`, `lastSeenActivityAt` (unread bookkeeping) | 1 — legal: private tables aren't shared, the no-FK rule doesn't apply |
| `SavedPlace` | `id` UUID PK | `name`, `kind`, + the RouteStop column set minus `orderID`/`position`/`role` | 0 (it's never a share root — sharing is per-order) |

`ProviderAccount` stores **identity, never secrets** — the OAuth token stays in the
Keychain, keyed by `key` (repo rule 8). `Order.providerAccountRef` points here *by value*:
orders survive account removal as orphans with an honest "provider link lost" state, and
account transfer is a re-key, not a migration.

## The device tier — this hardware only

| Table | Key | Columns of note |
|---|---|---|
| `SyncState` | `providerAccountRef` TEXT PK | `journalCursor`, `historyBackfilled`, plus attempt bookkeeping — the journal cursor is per-device by correctness: two devices sharing one cursor would consume each other's events, while the *results* (order rows) already converge through CloudKit |
| `PendingAcceptance` | `id` UUID PK | `providerAccountRef`, `claimID?`, `orderRef`?, `createdAt`, `lastCheckedAt`, `state` — the durable home for YD-5's unresolved acceptance: we POSTed, the answer was lost, the claim may exist provider-side; reconciled on launch against `claims/search` |
| `Draft` | `id` UUID PK | Provisional — an un-placed order has no provider existence, so it is *not* an `Order` row. Children (`DraftStop`, `DraftItem`) mirror the shared shape so promoting a draft to an order is a mechanical copy |

The wire log stays a **file**, not a table: it is PII-bearing diagnostic output (YD-12)
with rotation semantics files already give it, and it must never sync.

## The `*Ref` convention — the schema's central compromise

A shared child may carry **exactly one** declared foreign key. Wherever a second
relationship is needed inside the shared hierarchy, it is stored as a plain column of the
referenced key's type — no `REFERENCES` clause — named `*Ref` to mark it:

- `OrderItem.pickupStopRef` / `dropoffStopRef` → `RouteStop.id` (an item's journey ends)
- `Order.providerAccountRef` → `ProviderAccount.key` (the root can't have FKs at all)

The price is stated honestly: the database does not enforce these references. Integrity
moves to the write boundary — the controller validates a `stopRef` against the order's
stops at write time, and dangling refs read as "unknown" rather than crashing. This is
the same trade the package prescribes for many-to-many (denormalize rather than join),
extended to intra-hierarchy references. Queries still join by value — only enforcement
moves.

## Authority — who writes what

| Table | Writer | Participant read |
|---|---|---|
| `Order`, `RouteStop`, `OrderItem` | Owner UI (order definition) | via share |
| `OrderProviderState`, `ProviderEvent` | Owner sync only | via share |
| `OrderAnnotation`, `OrderAttachment`, `OrderTag` | Any read-write participant | via share |
| Private tier | Owner | never |
| Device tier | This device | never |

The provider-tables-are-owner-written rule is **convention, not constraint**: CloudKit
permissions are per-record, so a read-write participant *can* technically write a mirror
row. `sqlite-data` enforces read-only-ness locally (`SyncEngine.writePermissionError`),
but field-level ACLs don't exist. The design accepts this because (a) the owner's next
sync overwrites the mirror anyway, and (b) a participant without the provider credential
cannot *source* an authoritative write — the mischief is self-limiting. The schema still
separates the families so the rule is auditable at a glance.

## Conflict semantics

`CKSyncEngine` merges at record-field granularity, last-writer-wins. The schema is shaped
so that policy suffices: append-only tables (`ProviderEvent`, `OrderAnnotation`,
`OrderAttachment`) can't conflict; the mirror has one writer; the root's mutable surface
is one denormalized `lastActivityAt`. The only true last-writer-wins exposure is
participants editing each other's annotation/attachment metadata — acceptable, and
`lastModifiedBy` preserves the audit trail.

## Freshness — the timestamps every surface needs

`providerObservedAt` (last provider sighting), `mirroredAt` (last owner write),
`lastActivityAt` (list ordering), plus `createdAt`/`lastModifiedBy` system fields on every
shared row. Shared surfaces render "status as of `providerObservedAt`" — staleness is
displayed, never hidden (author's decision).

## Migration — the JSON stores into tables

The substrate's rule applies: **bytes are never destroyed**. First launch under the new
stack:

1. `orders.json` → `Order` + `RouteStop`×n + `OrderProviderState` (`claimID`, `status`,
   `price`, `currency`, `tariff`; `providerObservedAt` = file's last-write time as the
   best honest guess, `mirroredAt` = migration time). Legacy rows lack items/options —
   the columns are nullable, and the 3e card renders their absence honestly.
2. `sync-state.json` → `SyncState` row + `PendingAcceptance` rows for the pending queue.
3. `saved-places.json` → `SavedPlace` rows.
4. Each source file is renamed `*.migrated-<timestamp>.json` **in place** after a verified
   import — kept, not deleted. A failed import leaves the file untouched and re-runs;
   inserts are `INSERT OR IGNORE` by PK so re-running a partial migration is safe.
5. `providerAccountRef` is seeded from the account that owned the store at migration
   time — migration runs under an identity, which is recorded.

## The widget contract — a snapshot, not a database

The live database is **not** shared with extensions. GRDB's own guidance on App Group
databases is "prefer not to": a suspended process holding a SQLite lock is a watchdog
termination (0xDEAD10CC), Data Protection classes gate locked-device access, and
`ValueObservation` does not see other processes' writes. The contract is instead:

- The **app owns the database**. On material change it renders `deliveries-snapshot.json`
  (a small derived array: `id`, `status`, first/last stop address, `providerObservedAt`,
  `snapshotVersion`) into the App Group container and calls
  `WidgetCenter.reloadTimelines`.
- Widgets and future extensions read only the snapshot — versioned, small, rebuildable.
  The snapshot is a rendering, so its shape may change freely behind `snapshotVersion`.

## What this discharges

- **YD-5** (rest): `PendingAcceptance` is the durable home for an unresolved acceptance —
  the id survives restart, launch reconciliation matches it against `claims/search`, and
  a confirmed match promotes it into the mirror. The remaining half is now designed, not
  deferred.
- **YD-13** (in-flight write across an identity boundary): writes become
  `database.write` transactions where the account-scope check and the insert are one
  atomic unit, and account removal is a scoped delete inside the same boundary. The
  race dies structurally — there is no suspension point between check and write.
- **The 3e history card**: `finishedAt`, `providerDetail` (refusal reasons), items,
  options-bearing stops, and the event feed are all present — the card reads, it does
  not stretch the schema.
- **«Повторить» / «Наоборот»**: an order now carries everything a repeat refills —
  stops with contacts and address parts, items with sizes and values, tariff.

## Deliberate deviations, priced

- `*Ref` value references (above) — enforcement moved to the write boundary.
- `providerDetail` JSON — provider-exotic display fields without columns; a hatch, not a
  habit. If a field inside it is ever *queried* or *branched on*, it earns a column.
- `contactName` + components both stored — the wire and legacy rows speak one string;
  parsing is lossy. Redundancy for fidelity, documented at `RoutePoint` already.
- `lastActivityAt` on the root — a maintained aggregate; cheaper than ordering lists by
  `MAX(events.at)`, stated as denormalized.
- No `NOT NULL` dogma on provider fields — a claimID is legitimately absent until the
  provider assigns it; nulls mean "not yet", which is a state, not a defect.

## Deferred and open

- **Workspace sharing** (a whole org's orders under one share): the one-share-per-record
  rule makes it exclusive with per-order sharing, and the free-org-visibility wire test
  (<doc:Collaboration>) may make it unnecessary. If it is ever needed, the migration
  path is re-rooting — `Workspace` as root, `Order` demoted to single-FK child — which
  this schema is shaped to permit.
- **Draft persistence**: `Draft` is specified provisionally; whether parked drafts sync
  privately or stay device-local is a product call, not yet made.
- **Read-only participants writing annotations**: today annotation write = read-write
  grant. A "comment but don't edit" tier doesn't exist in CloudKit; if it is ever needed
  it is app-enforced convention on top of read-write.
- **Tag vocabulary normalization** if tags graduate from provisional.

## See Also

- <doc:Collaboration> — the stack research and grant model this schema implements
- <doc:Design> — the persistence decision this settles
- <doc:Roadmap> — where the migration sits in the phase order
- <doc:TechDebt> — YD-5, YD-12, YD-13, whose discharges this design carries
