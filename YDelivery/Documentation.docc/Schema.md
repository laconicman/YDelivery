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
 ├─ OrderOptions       orderID → Order (PK=FK)  1 FK ✓ shared, 1:1
 ├─ ProviderEvent      orderID → Order          1 FK ✓ shared
 ├─ OrderMessage       orderID → Order          1 FK ✓ shared, append-only
 │    (attachmentRef — value, NOT an FK)
 └─ OrderAttachment    orderID → Order          1 FK ✓ shared
      └─ AttachmentBlob attachmentID → (PK=FK)  1 FK ✓ shared transitively
```

### `Order` — the root

| Column | Type | Note |
|---|---|---|
| `id` | UUID PK | |
| `createdAt` | Date | Local creation — meaningful offline history before any provider ack |
| `providerAccountRef` | TEXT? | **Value, not FK** — matches `ProviderAccount.key` on the private side. Cannot be an FK: the root must have none. NULL = *unattributed* — a row whose provider account isn't recorded (legacy imports, see Migration) |
| `provider` | TEXT | `"yandex"` today; provider plurality is a column, not a schema version |
| `lastActivityAt` | Date | Owner-maintained *provider-activity* marker — denormalized, stated as such. List ordering is derived, not stored (below) |

No `claimID` here — the provider mirror carries it (below), keeping every provider-derived
fact in one owner-written row.

### Order identity — deterministic for discovered, random for created

An order created on this device gets a random UUID — there is no provider fact to key
on yet. An order *discovered* from a provider feed derives its id from
`(providerAccountRef, claimID)` — same derivation everywhere — so two devices finding
the same claim before either syncs produce the **same** `Order.id`, and CloudKit
merges them into one record instead of keeping duplicate roots (Devin Review, PR #36 —
random ids would preserve both). The residual window — a locally created order whose
claimID arrives while a discovered twin already exists on another device — is the
merge rule: `claimID` joins them, the locally created row wins (it carries the
sender's intent), the twin's mirror facts fold in, the twin is deleted.

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

### `OrderOptions` — how the run should go (1:1)

Every repeatable `DeliveryOptions` field, owner-written like the rest of the order's
definition (Devin Review caught their absence, PR #36 — repeat silently dropped loaders
and courier instructions without this row). PK is the FK again: one order, one options
row.

| Column | Type | Note |
|---|---|---|
| `orderID` | UUID PK + FK → `Order` | |
| `proCourier` | Bool | «Профи» — experienced couriers only |
| `toDoor` | Bool | Door-to-door; the wire speaks its negation |
| `thermobag` | Bool | Courier-class only |
| `loaders` | Int | Cargo-class only, 0–2 |
| `due` | Date? | Requested pickup time; nil = ASAP. The *request* — the mirror's `dueAt` is what the provider echoed; usually equal, legitimately different |
| `comment` | TEXT | Free text the courier reads — shared deliberately: a collaborator covering the door needs it |

All order-level, matching the app's model: loaders ride the whole run, not a stop.
Per-stop data that does exist — contacts, address parts — lives on `RouteStop`. If the
wire ever offers per-point options they become `RouteStop` columns, not this row.

### `ProviderEvent` — the history feed (owner-written)

Append-only; conflicts impossible by construction. Columns: `id` UUID PK, `orderID` FK,
`providerEventID` INTEGER? — the journal's own `operation_id`, monotonic and unique per
order — plus `at`, `kind`, `providerStatus`, `detail`?, `source`
(`journal`/`search`/`claimCard`).

Dedup is **identity, not a constraint** — and it has to be: `SyncEngine` rejects every
non-PK unique index on a synchronized table at init (`SchemaError.uniquenessConstraint`
— verified live in the spike, <doc:Spike>). So `ProviderEvent.id` is *derived*, not
random: `UUIDv5(orderID ‖ providerEventID)` for journal events — replaying a page
re-produces the same key, and two devices recording the same event produce one
`CKRecord` that merges rather than colliding. Synthesized sightings (`search`/
claim-card rows carry no provider id) derive their key from
`(orderID, providerStatus, source)` and upsert on re-sight — `at` keeps the latest
observation; one row per observed state. This is the activity timeline the 3e card
reads, and what "members see each other's activity" means for provider truth.

### `OrderMessage` — the chat, and the only participant-writable stream

Participant feedback is a **chat thread on the order**, not field edits (author's
simplification, 2026-09-25, absorbing Devin's forgery finding on the first draft):
sender, receiver, support, even the courier — whoever holds the share — post messages;
nobody edits anything. Append-only is both the social contract and the design: there is
no participant-writable history table, only a stream where every row has an author.

| Column | Type | Note |
|---|---|---|
| `id` | UUID PK | |
| `orderID` | UUID FK → `Order` | The one FK |
| `sentAt` | Date | |
| `kind` | TEXT | `text` · `photo` · `receptionConfirmed` — structured kinds render as human events («Ирина подтвердила получение»), never as provider status |
| `text` | TEXT? | |
| `attachmentRef` | UUID? | **Value** → `OrderAttachment.id` — a photo message carries its payload |
| `authorHint` | TEXT? | Display name cache; `createdBy`/`lastModifiedBy` system fields carry the real attribution |

`receptionConfirmed` is the deliberate shape of "the receiver marks it arrived": a
human-authored event in the stream, **never** a write to provider state — the two are
different truths and the UI says so («Ирина отметила: получено» alongside, not instead
of, the provider's `delivered`). When the provider confirms delivery, `ProviderEvent`
records it on its own authority.

### `OrderAttachment` + `AttachmentBlob` — parcel photos

Metadata row (`id`, `orderID`, `createdAt`, `kind`, `caption`, `byteSize`, `authorHint`)
with the payload in a 1:1 `AttachmentBlob` child (`attachmentID` PK+FK, `data` BLOB).
`sqlite-data` turns BLOB columns into `CKAsset` automatically, and the package's own
guidance is exactly this split — keep megabytes out of the metadata row so list queries
never drag image data. Participants may add photos (a receiver documenting condition is
the product story); blobs inherit the share transitively through the single-FK chain.

No `OrderTag` — the same one-FK arithmetic that forbids join tables would force a shared
tag vocabulary to denormalize per-order (the package's own prescribed refactor), and the
chat stream covers the collaborative need tags were standing in for. If a real tagging
feature ever lands it starts private, not shared.

### `OrderCustomField` — the sender's own fields on the order

Board `4b`: an org names its own fields («Заказ», «Накладная», «SKU») and answers them
per order. The **value** is shared — a collaborator sees «Заказ 4417» on the order
detail; the **schema** that named it is the sender's private config (below). The row
denormalizes `name` alongside `fieldRef` for exactly the reason `OrderAttachment` keeps
`authorHint`: deleting a field definition must not rewrite history — the order's
snapshot keeps the label it was placed under.

| Column | Type | Note |
|---|---|---|
| `id` | UUID PK | **Derived** — `UUIDv5(orderCustomField ‖ orderID ‖ fieldRef)`: one value per field per order by construction, and a copied `OrderCustomField` re-derives against the target order, so a repeat can never collide with the source row (review, Kit PR #5) |
| `orderID` | UUID FK → `Order` | The one FK |
| `fieldRef` | UUID | **Value** → `CustomFieldDefinition.id` — a deleted definition leaves an orphaned ref that renders via `name` |
| `name` | TEXT | The label the order was placed under |
| `value` | TEXT | The sender's answer |

`recordOrder` treats `customFields` as tri-state in effect: `nil` means *leave the
values standing* (a status-only sync update must not erase the sender's answers);
non-nil replaces wholesale (a repeat's corrected set). Carrier mapping happens at the
controller boundary — `shipping_document` (claim), `external_order_id` (destination
stop, also a `claims/search` filter), `extra_id` (item) — verified against generated
`Types.swift`, board `4b`'s three slots.

## The private tier — synced, never shared

| Table | Key | Columns of note | FKs |
|---|---|---|---|
| `ProviderAccount` | `key` TEXT PK (`"yandex:<corpClientID>"`) | `provider`, `corpClientID`, `displayLabel`, `firstSeenAt`, `lastSeenAt` | none needed — orders reference it by value |
| `OrderPrivateState` | `orderID` PK + FK → `Order` | `personalNote`, `pinned`, `lastSeenActivityAt` (unread bookkeeping) | 1 — legal: private tables aren't shared, the no-FK rule doesn't apply |
| `SavedPlace` | `id` UUID PK | `name`, `kind`, + the RouteStop column set minus `orderID`/`position`/`role` | 0 (it's never a share root — sharing is per-order) |
| `CustomFieldDefinition` | `id` UUID PK | `name`, `kind` (`text`/`choice`), `choicesJSON`, `isOptional`, `isShownByDefault` (required ⇒ shown, enforced on write), `carrier`, `position` | 0 — the schema is the sender's vocabulary; the *values* ride shared on `OrderCustomField` |

`carrier` is exclusive by write transaction — one field may claim each wire slot, and the
check runs inside the same `queue.write` as the upsert so concurrent saves can't split
it (review, Kit PR #5). The residual is cross-device: two devices could each author a
different field onto the same carrier and CloudKit would keep both rows. The schema
cannot express the exclusion (a secondary UNIQUE is the banned shape), so the draft
resolves it at read: the first field in `position` order owns the carrier, later ones
render as local-only until the sender reassigns one. Documented rather than invented —
this is a joint decision pending the author's eye.

`ProviderAccount` stores **identity, never secrets** — the OAuth token stays in the
Keychain, keyed by `key` (repo rule 8). `Order.providerAccountRef` points here *by value*:
orders survive account removal as orphans with an honest "provider link lost" state, and
account transfer is a re-key, not a migration.

## The device tier — this hardware only

| Table | Key | Columns of note |
|---|---|---|
| `SyncState` | `providerAccountRef` TEXT PK | `journalCursor`, `historyBackfilled`, plus attempt bookkeeping — the journal cursor is per-device by correctness: two devices sharing one cursor would consume each other's events, while the *results* (order rows) already converge through CloudKit |
| `PendingDiscovery` | `id` UUID PK + `UNIQUE(providerAccountRef, claimID)` | The discovery-retry queue — a feed reported a claim whose card fetch failed; retried until the card lands. Today's `pendingClaimIDs` migrates here. Distinct from acceptance: this device saw the claim exists, it never tried to create it. A secondary UNIQUE is legal *here* precisely because the table is never synchronized — the `uniquenessConstraint` ban governs `tables:`/`privateTables:` only |
| `PendingAcceptance` | `id` UUID PK | `providerAccountRef`, `claimID?`, `orderRef`?, `createdAt`, `lastCheckedAt`, `state` — the durable home for YD-5's unresolved *acceptance*: we POSTed, the answer was lost, the claim may exist provider-side; reconciled on launch against `claims/search`. Today's store holds no such attempts — it starts empty, which is precisely the gap YD-5 names |
| `OrderDraft` | `id` UUID PK | Provisional — an un-placed order has no provider existence, so it is *not* an `Order` row. Children (`DraftStop`, `DraftItem`) mirror the shared shape so promoting a draft to an order is a mechanical copy. Named `OrderDraft`, not `Draft`: `@Table` synthesizes a `.Draft` nested type on every model, and a table literally named `Draft` collides inside the macro (spike-verified) |

The wire log stays a **file**, not a table: it is PII-bearing diagnostic output (YD-12)
with rotation semantics files already give it, and it must never sync.

## The `*Ref` convention — the schema's central compromise

A shared child may carry **exactly one** declared foreign key. Wherever a second
relationship is needed inside the shared hierarchy, it is stored as a plain column of the
referenced key's type — no `REFERENCES` clause — named `*Ref` to mark it:

- `OrderItem.pickupStopRef` / `dropoffStopRef` → `RouteStop.id` (an item's journey ends)
- `OrderMessage.attachmentRef` → `OrderAttachment.id` (a photo message's payload)
- `Order.providerAccountRef` → `ProviderAccount.key` (the root can't have FKs at all)

The convention has a type-level signature: `*Ref` columns are declared `UUID?`/`TEXT?`,
**never `SomeTable.ID`** — an `.ID`-typed column is what an FK declaration gets written
for, and legibility here is load-bearing. The same rule shapes the DDL: `*Ref` columns
carry no `REFERENCES` clause.

The price is stated honestly: the database does not enforce these references. Integrity
moves to the write boundary — the controller validates a `stopRef` against the order's
stops at write time, and an `attachmentRef` against the *same order's* attachments at
message-post time (the reference is by id alone, so "same order" is a rule the writer
checks, not a join the reader trusts). Dangling refs read as "unknown" rather than
crashing. This is
the same trade the package prescribes for many-to-many (denormalize rather than join),
extended to intra-hierarchy references. Queries still join by value — only enforcement
moves.

## Authority — who writes what

| Table | Writer | Participant read |
|---|---|---|
| `Order`, `RouteStop`, `OrderItem`, `OrderOptions` | Owner UI (order definition) | via share |
| `OrderProviderState`, `ProviderEvent` | Owner sync only | via share |
| `OrderMessage`, `OrderAttachment` | Read-write participants — append-only | via share |
| Private tier | Owner | never |
| Device tier | This device | never |

### The forgery boundary — the finding that reshaped the write surface

CloudKit permissions are per-record: a read-write participant *can* technically write
any row in the shared hierarchy, including the provider mirror — Devin Review flagged
exactly this on the first draft (PR #36), and the author had the same concern
independently. The original draft's "convention, not constraint" answer was honest but
thin; the chat model is the real fix, and it works on three levels:

1. **The writable surface shrank to append-only streams.** Messages and attachments are
   rows a participant *adds*, never history they *edit* — a forged row here is just a
   fake message, attributable through `createdBy`, legible as human chatter, and
   worthless as provider impersonation because nothing in it can masquerade as a status.
2. **Grant discipline does the rest.** The default share for a consumer is
   **read-only** — locally enforced (`SyncEngine.writePermissionError`), no trust
   required. Read-write is reserved for collaborators who actually post.
3. **The owner remains the authority of last resort.** A forged mirror row lives only
   until the owner's next sync overwrite; and since `CKRecord` system fields expose
   `lastModifiedUserRecordID`, a later hardening pass can have reads distrust provider
   rows the owner didn't write — noted as available, not yet designed.

One residual the layers don't remove, stated plainly: within the read-write set,
"append-only" is convention too — record-level permissions cannot distinguish "add a
row" from "edit a row", so a collaborator *can* rewrite an existing message. The
mitigation is audit, not enforcement: `lastModifiedUserRecordID` exposes who touched
what, and an owner who sees history rewritten has a social and administrative answer
(remove the participant), not a technical one. Shared editing trust is granted per
participant; the audit trail is what makes that grant accountable.

## Conflict semantics

`CKSyncEngine` merges at record-field granularity, last-writer-wins. The schema is shaped
so that policy suffices: append-only tables (`ProviderEvent`, `OrderMessage`,
`OrderAttachment`) can't conflict; the mirror has one writer; the root's mutable surface
is one denormalized `lastActivityAt`. The only true last-writer-wins exposure is
participants editing each other's message/attachment rows — the append-only convention
says they shouldn't, and `lastModifiedBy` preserves the audit trail if they do.

**List ordering is derived, never written.** `lastActivityAt` marks provider-side
activity and stays owner-written; participants can't touch it without breaking the
authority matrix. But shared lists must still surface a participant's message — so the
sort key is computed at read as the greatest of three candidate timestamps, each
NULL-safe on its own: `MAX(lastActivityAt, COALESCE(MAX(m.sentAt), epoch),
COALESCE(MAX(a.createdAt), epoch))`. SQLite's scalar `MAX` propagates NULL — an order
with messages but no attachments would otherwise sort to NULL rather than its real
latest activity (Devin Review, PR #36); coalescing each child aggregate to the epoch
means "no such activity" simply never wins. Ordering is a presentation derivation,
which needs no write authority at all.

## Freshness — the timestamps every surface needs

`providerObservedAt` (last provider sighting), `mirroredAt` (last owner write),
`lastActivityAt` (list ordering), plus `createdAt`/`lastModifiedBy` system fields on every
shared row. Shared surfaces render "status as of `providerObservedAt`" — staleness is
displayed, never hidden (author's decision).

## Migration — the JSON stores into tables

The substrate's rule applies: **bytes are never destroyed**. First launch under the new
stack:

1. `orders.json` → `Order` + `RouteStop`×n + `OrderProviderState` (`claimID`, `status`,
   `price`, `currency`, `tariff`; `providerObservedAt` = NULL — the file has one mtime
   for the whole array, so stamping it on every row would fabricate freshness for
   orders not observed since (Devin Review, PR #36); `mirroredAt` = migration time).
   Legacy rows lack items/options — the columns are nullable, and the 3e card renders
   their absence honestly.
2. `claims-sync.json` → `SyncState` row + `PendingDiscovery` rows from
   `pendingClaimIDs` — the discovery-retry queue, not acceptance attempts;
   `PendingAcceptance` has nothing to migrate yet.
3. `places.json` → `SavedPlace` rows.
4. Each source file is renamed `*.migrated-<timestamp>.json` **in place** after a verified
   import — kept, not deleted. Retries are safe by key derivation, not by marker order:
   legacy route stops/items carry no ids, so a migrated child id is derived —
   `UUIDv5(orderID ‖ childKind ‖ index)` — the same mechanism as event/order identity.
   `INSERT OR IGNORE` by PK then makes a partial migration idempotent even if the process
   dies in the commit→rename window: the re-import reproduces identical keys and the
   second pass writes nothing (Devin Review, PR #36 — fresh random child ids would have
   duplicated every stop).
5. `providerAccountRef` is seeded **NULL — unattributed** — on every imported row. The
   legacy store is deliberately shared across identities and records no owner, so
   inventing one misattributes history: a device where Alice ordered, signed out, and
   Bob ordered would stamp both rows Bob's, letting his sync overwrite her mirror or a
   scoped delete take both (Devin Review, PR #36). Unattributed rows are display-only
   history — excluded from provider-sync writes and from account-scoped deletion until
   reconciliation, which is the match itself: the sync already joins by `claimID`, so
   the first write that finds an unattributed row under a credential sets its ref in
   the same transaction. An order no active credential ever surfaces stays local
   history forever — the honest reading of "this device saw it".

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
  `OrderOptions`, and the event feed are all present — the card reads, it does
  not stretch the schema.
- **«Повторить» / «Наоборот»**: an order now carries everything a repeat refills —
  stops with contacts and address parts, items with sizes and values, tariff.

## Deliberate deviations, priced

- `*Ref` value references (above) — enforcement moved to the write boundary.
- `providerDetail` JSON — provider-exotic display fields without columns; a hatch, not a
  habit. If a field inside it is ever *queried* or *branched on*, it earns a column.
- `contactName` + components both stored — the wire and legacy rows speak one string;
  parsing is lossy. Redundancy for fidelity, documented at `RoutePoint` already.
- `lastActivityAt` on the root — a maintained aggregate of *provider-side* activity.
  Visible ordering derives from it plus child timestamps at read; the column exists
  so the owner's sync can record activity without walking the event feed.
- No `NOT NULL` dogma on provider fields — a claimID is legitimately absent until the
  provider assigns it; nulls mean "not yet", which is a state, not a defect.

## Deferred and open

- **Workspace sharing** (a whole org's orders under one share): the one-share-per-record
  rule makes it exclusive with per-order sharing, and the free-org-visibility wire test
  (<doc:Collaboration>) may make it unnecessary. If it is ever needed, the migration
  path is re-rooting — `Workspace` as root, `Order` demoted to single-FK child — which
  this schema is shaped to permit.
- **Draft persistence**: `OrderDraft` is specified provisionally; whether parked drafts
  sync privately or stay device-local is a product call, not yet made.
- **Read-only participants posting messages**: today message-posting = read-write
  grant. A "comment but don't touch attachments" tier doesn't exist in CloudKit; if it
  is ever needed it is app-enforced convention on top of read-write.
- **Accountless couriers and support staff**: out of this design's reach — a private
  `CKShare` requires an iCloud account per participant, and an App Clip changes the
  install experience, not the identity requirement (Devin Review, second round — an
  earlier draft of this section promised otherwise and was wrong). If accountless
  identities ever become a requirement, the answer is a separate authenticated relay,
  not CloudKit — a different feature, not a flag on this one.

## See Also

- <doc:Collaboration> — the stack research and grant model this schema implements
- <doc:Design> — the persistence decision this settles
- <doc:Roadmap> — where the migration sits in the phase order
- <doc:TechDebt> — YD-5, YD-12, YD-13, whose discharges this design carries
