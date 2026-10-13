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

Membership in a share **rides the `CKShare` participant list** — the grant, which
`UICloudSharingController`/`CloudSharingView` already manages — and, since 2026-10-06, is
*also* a signed, append-only `memberships` table the owner's device mirrors from the
share (<doc:TechDebt> YD-45; "Epoch 2" below). The share stays the only grant; the table
is the record of it, so roles (receiver, dispatcher, courier) have a home and a future
host has nothing to reconstruct from CloudKit. No `Collaborator` entity with fields of
its own exists — a membership row is a party reference, a role and a stamp.

## The shared hierarchy — root `Order`

The order is the share root: the one thing a sender chooses to show a collaborator. Its
row is deliberately minimal — identity and creation, nothing else — because everything
with an author or a lifecycle hangs below it.

```
Order ─────────────────────────── share root, 0 FK — projection
 ├─ RouteStop          orderID → Order          1 FK ✓ shared — projection
 ├─ OrderItem          orderID → Order          1 FK ✓ shared — projection
 │    (pickupStopRef, dropoffStopRef — values, NOT FKs)
 ├─ OrderProviderState orderID → Order (PK=FK)  1 FK ✓ shared, 1:1 — projection
 ├─ OrderOptions       orderID → Order (PK=FK)  1 FK ✓ shared, 1:1 — projection
 ├─ OrderEvent         orderID → Order          1 FK ✓ shared, append-only, signed
 │    (today's ProviderEvent, renamed at the epoch; legRef — value → Leg.ref, the logical leg)
 ├─ OrderMessage       orderID → Order          1 FK ✓ shared, append-only, signed
 │    (attachmentRef — value, NOT an FK)
 ├─ OrderAttachment    orderID → Order          1 FK ✓ shared, append-only, signed
 │    └─ AttachmentBlob attachmentID → (PK=FK)  1 FK ✓ shared transitively (CKAsset, dataHash on the parent)
 ├─ ParticipantKey     orderID → Order          1 FK ✓ shared, append-only, self-signed   (epoch 2)
 ├─ Membership         orderID → Order          1 FK ✓ shared, append-only, signed        (epoch 2)
 ├─ OrderRating        orderID → Order          1 FK ✓ shared, append-only, signed        (epoch 2)
 └─ Leg                orderID → Order          1 FK ✓ shared, append-only, signed        (Stage 2, later)
      (providerAccountRef or courierPartyRef — values, exactly one set; fromStopRef, toStopRef → RouteStop.id)
```

*Signed* means the row carries `authorRef`, `signingKeyID` and `signature` over its
frozen column list, written once by the device that wrote the row (<doc:Collaboration> →
"The canonical payload"); *projection* means the row is merged per field by the engine
and checked against the signed facts at read ("Derived integrity", below). The four
tables marked *epoch 2* and the Stage 2 `Leg` are designed, not yet in the DDL
("Epoch 2", below).

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
flattens to `building`/`entrance`/`floor`/`apartment`/`intercom` (the wire's own
`building` slot — строение/корпус — is a *part*, not a door detail), and the contact flattens to
`contactGivenName`/`contactFamilyName`/`contactPhone`/`contactPhoneExtension` — plus
`contactName`, the formatted whole the wire speaks, deliberately duplicated (name parsing
is lossy; both forms are kept, as `RoutePoint` already does).

| Column | Type | Note |
|---|---|---|
| `id` | UUID PK | Stable identity — reorders never renumber it. **Not what the writer does today:** `insertStops` derives it from the position index (`UUIDv5(orderChild ‖ orderID ‖ "stop" ‖ index)`), so a reorder *is* a renumbering — <doc:TechDebt> YD-40; the epoch mints it on the model (`RoutePoint.id`) at placement |
| `orderID` | UUID FK → `Order` | The one FK |
| `position` | Int | Travel order; mutable on reorder. Items reference stops by `id`, never by position, so reordering never breaks journeys |
| `role` | TEXT | `pickup` / `dropoff` / `return` — the sender's vocabulary |
| `latitude`, `longitude` | Double | |
| `address` | TEXT | The courier-readable whole |
| `building`, `entrance`, `floor`, `apartment`, `intercom` | TEXT? | AddressParts, flattened |
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

### `ProviderEvent` → `OrderEvent` — the history feed, every writer's, signed

Append-only; conflicts impossible by construction. Columns: `id` UUID PK, `orderID` FK,
`providerEventID` INTEGER? — the journal's own `operation_id`, monotonic and unique per
order — plus `at`, `kind`, `providerStatus`, `detail`?, `source`
(`journal`/`search`/`claimCard`). **Renamed at the epoch** (decided 2026-10-06): the
table becomes `orderEvents` and the model `OrderEvent`, because with `placed`, `legRef`
and non-owner writers it stopped being the provider's feed — a rename on a live container
would orphan a record type; on a fresh one it costs nothing. Stage 1 adds `legRef`
(value → the logical leg `legs.ref`; NULL = the order's only leg), `providerRevision`
(the wire's `revision` — the journal event's own, and the claim card's `revision`, not
its `version` or `user_request_revision`, required by the wire on both — part of a
sighting's identity and the derived verdicts' tie-break within one family),
`routeDigest`, and the signing triple
`authorRef`/`signingKeyID`/`signature`; `kind` gains `placed` and `source` gains `app` —
the ordering flow's own fact, written when the claim is accepted, with the agreed
claimID, tariff, price and currency in `detail` and the digest of the route as sent,
stamped with the `updated_ts` and `revision` of the last claim card the flow read before
accepting — provider time, never the device's clock (third round).
Every row is signed over its frozen column list by the device that wrote it
(<doc:Collaboration> → "The canonical payload").

Dedup is **identity, not a constraint** — and it has to be: `SyncEngine` rejects every
non-PK unique index on a synchronized table at init (`SchemaError.uniquenessConstraint`
— verified live in the spike, <doc:Spike>). So `ProviderEvent.id` is *derived*, not
random: `UUIDv5(orderID ‖ providerEventID)` for journal events — replaying a page
re-produces the same key on the device that wrote it. (Until 2026-10-08 this sentence
went on: "and two devices recording the same event produce one `CKRecord` that merges
rather than colliding" — under signing that merge is the corruption the doctrine's
rule 1 names, so at the epoch the key carries the writer and the *trail* merges the two
rows at read, below.) Synthesized sightings (`search`/
claim-card rows carry no provider id) derive their key from
`(orderID, providerStatus, source)` and are written `INSERT OR IGNORE` — the first
observation's `at` stands and a re-sight changes nothing; one row per observed state.
(*Corrected 2026-10-06:* this sentence used to say a re-sight "upserts `at`", a
behaviour `recordProviderEvent` never had — and immutability is exactly what signing
needs, so the code was right and the sentence was wrong.) *Amended 2026-10-08, review of
#135:* at the epoch both derivations gain inputs. A sighting keys on
`orderID ‖ providerRevision ‖ providerStatus ‖ routeDigest ‖ keyID` —
`recordOrder` rewrites the stops from any card whose stamp is not older, status
unchanged or not, and a second sighting dropped under the old key would leave the
refreshed stops answering to a stale signed digest; and a claim can return to an earlier
status at a later revision (an edit at `ready_for_approval` sends it back to
`estimating`), which under a key without the revision would collide with the first
sighting and vanish (third round). So one row per observed revision — a card read and
a search read of one revision are one observation, whichever lands first — and a retry
of one revision is a no-op. A journal row keys on
`orderID ‖ providerEventID ‖ keyID` — every owner device ingests the journal itself, and
two devices minting one id for one operation would have their signatures merged column
by column into a row that verifies for neither (<doc:Collaboration> → rule 1). The
trail dedupes by fact at read ("Epoch 2" → identity, below). This is the activity
timeline the 3e card reads, and what "members see each other's activity" means for
provider truth.

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
| `authorHint` | TEXT? | Display name cache, self-asserted — real posts write it NULL, only previews and fixtures fill it (<doc:TechDebt> YD-43); the name a reader shows resolves from the identity authority at render |
| `authorRef`, `signingKeyID`, `signature` | TEXT? | Stage 1 of the epoch: the writer's `partyRef` and its signature over the frozen column list — `authorHint` is not signed (<doc:Collaboration> → "The canonical payload") |

`receptionConfirmed` is the deliberate shape of "the receiver marks it arrived": a
human-authored event in the stream, **never** a write to provider state — the two are
different truths and the UI says so («Ирина отметила: получено» alongside, not instead
of, the provider's `delivered`). When the provider confirms delivery, `ProviderEvent`
records it on its own authority.

### `OrderAttachment` + `AttachmentBlob` — parcel photos

Metadata row (`id`, `orderID`, `createdAt`, `kind`, `caption`, `byteSize`, `authorHint` —
and, from Stage 1 of the epoch, `dataHash` = `hex(SHA-256(data))`, signed with the row so
a blob swapped under the same attachment id fails the attachment's verdict, plus
`authorRef`/`signingKeyID`/`signature`; <doc:TechDebt> YD-42) with the payload in a 1:1
`AttachmentBlob` child (`attachmentID` PK+FK, `data` BLOB — the asset itself is not
signed; the hash is what binds it).
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
| `SavedPlace` | `id` UUID PK | `name`, `kind`, `pinned`, + the RouteStop column set minus `orderID`/`position`/`role` | 0 (it's never a share root — sharing is per-order) |
| `ParcelTemplate` | `id` UUID PK | `name` (the library's label — free to differ from the goods'), `pinned` | 0 — the sender's vocabulary, never a share member; instances on an order stay `OrderItem` |
| `ParcelTemplateItem` | `id` UUID PK | `templateID` → `ParcelTemplate`, `position`, `name`, `quantity`, `weightKg`, `cost`, `currency`, `sizeLengthCm`/`sizeWidthCm`/`sizeHeightCm` | 1 — the child tier that gives a template bundle room; v1 writes exactly one item (a UI convention, not a schema invariant), and deletes sweep children explicitly because `PRAGMA foreign_keys` stays off |
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
| `OrderDraft` | `id` UUID PK | The parked New Delivery draft (YD-16) — an un-placed order has no provider existence, so it is *not* an `Order` row and survives the identity boundary. Carries the options set, `due`, `comment` and the remembered `chosenTariff`; children (`DraftStop`, `DraftItem`, `DraftCustomField`) mirror the shared shape so promoting a draft to an order is a mechanical copy — a `DraftStop` with NULL point columns is an added-but-unfilled hole, which *is* draft state. Named `OrderDraft`, not `Draft`: `@Table` synthesizes a `.Draft` nested type on every model, and a table literally named `Draft` collides inside the macro (spike-verified) |

The wire log stays a **file**, not a table: it is PII-bearing diagnostic output (YD-12)
with rotation semantics files already give it, and it must never sync.

## The `*Ref` convention — the schema's central compromise

A shared child may carry **exactly one** declared foreign key. Wherever a second
relationship is needed inside the shared hierarchy, it is stored as a plain column of the
referenced key's type — no `REFERENCES` clause — named `*Ref` to mark it:

- `OrderItem.pickupStopRef` / `dropoffStopRef` → `RouteStop.id` (an item's journey ends)
- `OrderMessage.attachmentRef` → `OrderAttachment.id` (a photo message's payload)
- `Order.providerAccountRef` → `ProviderAccount.key` (the root can't have FKs at all)
- `OrderEvent.legRef` → `Leg.ref`, the *logical* leg (`orderID ‖ fromStopRef ‖
  toStopRef`, by stable stop ids), never a row id (an event's leg; NULL = the order's only leg). Any `*Ref` that names a leg —
  this one, and `OrderRating.subjectRef` for a `leg` subject — resolves to `Leg.ref`: the
  convention's one exception, because a leg's rows are per writer
- `Leg.fromStopRef` / `toStopRef` → `RouteStop.id`; `Leg.providerAccountRef` →
  `ProviderAccount.key` or `Leg.courierPartyRef` → a party, exactly one of the two set
- `OrderRating.subjectRef` → a leg, a party, a stop or a provider account, as
  `subjectKind` says
- `authorRef`, `partyRef`, `courierPartyRef` → a **party**, which is not a table at all on
  CloudKit: the identity authority resolves it ("`partyRef`", below)

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
| `Order`, `RouteStop`, `OrderItem`, `OrderOptions`, `OrderCustomField` | Owner UI (order definition) — unsigned projections | via share |
| `OrderProviderState` | Owner sync only — an unsigned projection, checked against the signed events at read | via share |
| `OrderEvent` (today's `ProviderEvent`) | Owner sync (`legRef` NULL) and the ordering flow (`placed`); a courier for its own leg, later — signed | via share |
| `OrderMessage`, `OrderAttachment`, `OrderRating` | Read-write participants — append-only, signed | via share |
| `ParticipantKey` | Each device, its own row — self-signed, bound by the authority's stamp | via share |
| `Membership`, `Leg` | Owner — signed | via share |
| Private tier | Owner | never |
| Device tier | This device | never |

Since 2026-10-06 the table is a *matrix of entitlement judged at read*, not a promise
about what CloudKit lets a participant write: who may write which row kind for which leg
is in <doc:Collaboration> → "Verdicts and entitlement", and a correctly signed row by a
party outside it renders as *not entitled*, never as valid.

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
   until the owner's next sync overwrite — and the window until that overwrite, which
   this paragraph once treated as the whole exposure, is what the derived verdict closes
   (2026-10-06): a mirror that disagrees with the latest *signed* event renders as such
   the moment it is read ("Derived integrity", below). Since `CKRecord` system fields
   expose `lastModifiedUserRecordID`, a later hardening pass could have reads distrust
   provider rows the owner didn't write — noted as available then, **designed now**: the
   events are signed facts, the mirror is checked against them, and the server-stamped
   *creator* is the trust anchor for every key row (<doc:Collaboration> → "Sign facts,
   derive state").

One residual the layers don't remove, stated plainly: within the read-write set,
"append-only" is convention too — record-level permissions cannot distinguish "add a
row" from "edit a row", so a collaborator *can* rewrite an existing message. The
mitigation is audit, not enforcement: `lastModifiedUserRecordID` exposes who touched
what, and an owner who sees history rewritten has a social and administrative answer
(remove the participant), not a technical one. With signed facts (2026-10-06) the audit
gets a verdict: a rewritten message fails its author's signature and renders *invalid*
beside the bubble — rendered, never refused; the answer stays social. Shared editing trust is granted per
participant; the audit trail is what makes that grant accountable.

## Conflict semantics

`CKSyncEngine` merges at record-field granularity, last-writer-wins — verified upstream
on 2026-10-06: each column carries its own `userModificationTime`, so two devices editing
different columns of one row both win, and the merged row was written by nobody in full
(<doc:Collaboration> → "The facts that reshaped the design"). The schema is shaped so
that policy suffices: append-only tables (`ProviderEvent`, `OrderMessage`,
`OrderAttachment`) can't conflict; the mirror has one writer; the root's mutable surface
is one denormalized `lastActivityAt`. The same grain is why a signature lives only on
append-only rows and the mirror's integrity is derived, never signed ("Derived
integrity", below). A colliding *insert* is merged the same way — `serverRecordChanged`
runs the per-field upsert and overwrites the loser's local row — so "can't conflict"
holds only while no two writers can mint one id: a signed table's derived ids carry the
writer, and the fact is deduped at read ("Epoch 2" → identity; amended 2026-10-08). The only true last-writer-wins exposure is
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

## Primary keys — no `ON CONFLICT REPLACE` on shared tables (2026-10-06)

The DDL at Kit 0.4.15 declares `ON CONFLICT REPLACE` on the primary keys of `orders`,
`routeStops`, `orderItems`, `orderCustomFields`, `orderMessages` and `orderAttachments`
(and across the private and device tiers); `providerEvents` does not. A colliding plain
`INSERT` therefore silently rewrites the existing row — which under signing means a
signed row can be replaced wholesale by anyone who can insert, and which `sqlite-data`
never sees as an edit: SQLite's REPLACE fires no delete trigger without
`recursive_triggers` and never bumps `userModificationTime` (YD-34's finding). The rule
from here: **a shared primary key carries no conflict clause, and every writer states
its policy in the statement** — `INSERT OR IGNORE` for facts (a retry re-inserts the
same caller-held id and is a no-op), an explicit upsert for projections (YD-34's write
discipline). The epoch drops the clause from every shared table; until then a writer on
a signed table states `OR IGNORE`, which SQLite lets override the column's clause. The
private and device tiers keep theirs where a writer relies on it (`saveDraft`'s
wholesale rewrite), stated per table. <doc:TechDebt> YD-41.

## `partyRef` — the only person reference (2026-10-06)

Every reference to a person — an author, a subject, a member, a courier — is a
`partyRef`: an opaque UUID stored as lowercase TEXT like every other id, under the
`*Ref` convention (a value, never a `REFERENCES` clause, never a type the schema could
mistake for a table's own key). Two distinctions carry the design: a **party** (who is
accountable) versus a **device** (what holds a key), and a party's **reference** (the
`partyRef` every row uses) versus its **identities** (the credentials an authority
accepts for it: a CloudKit user record today; Apple, Google, email and phone on a server
tomorrow). Rows know only references; authorities know identities (<doc:Design> →
"Parties, not CloudKit names" for the rejected alternatives).

**How a `partyRef` is minted.** In CloudKit mode, deterministically on every device:
`UUIDv5(DerivedNamespace.party ‖ "cloudkit" ‖ userRecordName)`, so two devices derive the
same reference for the same iCloud user with no server in between. A server later stores
that very UUID as the party's id and records `("cloudkit", userRecordName)` as one of its
identities, beside `("apple", sub)`, `("google", sub)`, `("email", address)`,
`("phone", e164)` — nothing in the order tables moves (<doc:Collaboration> → "Ready for
an independent host"). User record names are container-scoped, so a new container mints
new references; local history has none yet, which is one more reason to do the epoch now.

The device learns its own reference from the authority (`CKContainer.userRecordID()`
once sync starts) and caches it in a device-tier `localIdentity` table (`authority`
TEXT PK — `cloudkit:<container>` · `server:<host>` — `subject`, `partyRef`,
`fetchedAt`). Until it is known, rows carry `authorRef = NULL` and the device's key row
carries `partyRef = NULL`; the authority's stamp fills the gap for readers after the
first sync. No CloudKit vocabulary — `CKCurrentUserDefaultName`, record names, `CKShare`
participants — reaches a row or a model; it lives inside the identity authority adapter
alone. The derivation above runs inside that adapter too: a `partyRef` is
CloudKit-derived in CloudKit mode, and no row or model can tell.

## Derived integrity — projections checked against the facts (2026-10-06)

The projections (`orders`, `orderProviderStates`, `orderOptions`, `orderItems`,
`routeStops`, `orderCustomFields`) keep their writers, their merge rules and no
signature columns. Their integrity is a verdict computed at read from the signed events,
never a column:

- **`mirrorIntegrity(orderID:)`** compares `orderProviderStates.providerStatus` with the
  `providerStatus` of the latest *verified* status-bearing event and yields
  `.consistent` / `.disagrees(expected:)` / `.noSignedHistory`. "Latest" is one total
  order over the rows that read verified *and* entitled — a member's validly signed
  event loses on entitlement before it can compete — and it is one lexicographic key:
  by `at`, the provider's clock on journal rows and sightings alike; on a tie, by family —
  journal beats a claim read (card or search, one claim `revision`) beats `placed`; then,
  within one family, the higher `providerRevision`; then the smallest id. Timestamp first because
  it is the order the mirror's own writer gates on, so an honest write never reads as
  tampering; revision only within one family, where it is one counter (third round,
  2026-10-08: comparing by revision when both rows carried one and by `at` otherwise
  could cycle through a third row). One expected value, never a set to match any of — a
  set let a forged rollback to an older, equally stamped verified status pass as
  consistent (second round). The residuals come from the provider's clocks and none
  lets a forgery pass: two disagreeing rows at one exact stamp, where the mirror's last
  arrival can differ per device; incompatible revisions at one stamp, where the mirror
  and the verdict agree on the journal row; and today's batch stamp, which can write a
  card's content under a newer event's stamp — a writer defect, <doc:TechDebt> YD-46. The
  verdicts check status and route only: price, tariff and the courier fields on the
  mirror stay unsigned projection data with no verdict of their own. A mirror row rewritten out of band disagrees with the
  signed history; a legitimate newer event makes it consistent again.
- **`routeIntegrity(orderID:)`** hashes the stored stops' sender-authored columns —
  every `RouteStop` column but the id and the `visit*` provider truth, in `position`
  order — and compares with the `routeDigest` carried by the latest verified
  digest-bearing event: `placed`, written by the ordering flow over the route as sent,
  and every `sighting`, over the route as the provider reported it, under the same
  total order — one expected digest. A stop
  address rewritten out of band mismatches; a fresh sighting carrying the new route
  restores consistency, and because a sighting's identity carries its revision and its
  digest, a route the provider corrected under an unchanged status *is* a fresh sighting
  (amended 2026-10-08, reviews of #135). The digest's encoding is the canonical payload's
  (<doc:Collaboration>).

Both read the trail deduped by fact — rows agreeing on the fact columns collapsed to one
entry per `(orderID, providerEventID)` and per `(orderID, providerRevision,
providerStatus, routeDigest)`, disagreeing ones kept apart with their verdicts — since each writer's row
is its own record ("Epoch 2" → identity, below). Both are one event scan per order on demand, never on the list
read, and neither touches the projection tables' write paths. The order detail renders a disagreement as one line
under the provider block — "the recorded status differs from the signed history", "the
route differs from what was signed" — in the feedback role, never as a refusal.

## Freshness — the timestamps every surface needs

`providerObservedAt` (last provider sighting), `mirroredAt` (last owner write),
`lastActivityAt` (list ordering), plus `createdAt`/`lastModifiedBy` system fields on every
shared row. Shared surfaces render "status as of `providerObservedAt`" — staleness is
displayed, never hidden (author's decision).

**Storage is REAL unix-epoch seconds, and the models must say so.** `Date`'s default
`QueryBindable`/`QueryDecodable` is ISO-8601 *text* — an engine read of any `Date` column
stored as a number decode-fails, and the failure is not cosmetic: the record provider
reports the row missing and the pending change is *removed*, so a date-carrying row
silently never syncs (found implementing the share seam, `sqlite-data` 1.12.0). Every
`Date`/`Date?` column on every `@Table` therefore declares
`@Column(as: Date.UnixEpochSecondsRepresentation.self)` — the Kit's own representation
binding `.double(timeIntervalSince1970)`, matching the DDL's REAL columns and the hand
SQL's epoch reads exactly. The package's `Date.UnixTimeRepresentation` binds *integer*
seconds — wrong affinity and precision for this schema.

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
- The share extension rides the same contract (board `5d`, landed): `saved-places.json`
  exports the «Откуда» row's input after each healthy places read, and `shared-draft.json`
  is the one-shot slot the extension writes and the app consumes — claimed by rename, so
  a share arriving mid-consume can never be removed by the read it raced (Kit PR #11).

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
- **Draft syncing**: the draft tier is implemented and device-local today
  (YD-16); whether parked drafts sync privately stays a product call — a draft
  has no provider existence to share, and the sender's other device restoring
  mid-draft is convenience, not correctness.
- **Read-only participants posting messages**: today message-posting = read-write
  grant. A "comment but don't touch attachments" tier doesn't exist in CloudKit; if it
  is ever needed it is app-enforced convention on top of read-write.
- **Tags on the library lists**: `ParcelTemplate`/`ParcelTemplateItem` and `pinned` on
  both lists **landed** (Kit 0.4.7, additive DDL — see the private-tier table above).
  What stays open is *shared* tags: a tag vocabulary a team shares is the workspace-root
  question above; private tags wait until someone names a use pin doesn't cover.
- **Signed provider state** — the 2026-09-29 bullet, kept as history: `signature BLOB` +
  `signingKeyID` on `OrderProviderState` and `ProviderEvent`; Curve25519 over a canonical
  serialisation; the owner's private key in the iCloud Keychain, so the owner's devices
  sign and everyone verifies (<doc:Collaboration> → "Where this landed", 5). Superseded
  2026-10-05 in one respect — keys are rows of a shared, append-only `participantKeys`
  table, not `ownerSigningKey` on the root, so that couriers and other writers can
  publish theirs too — and **2026-10-06 in four more** (<doc:Collaboration> → "Sign
  facts, derive state"; "Epoch 2" below): the mirror is *not* signed, it is a projection
  merged per field and checked against the signed events at read; the signature column
  is base64 `TEXT`, never a BLOB (a BLOB becomes a `CKAsset` per row); the curve is P-256
  in the Secure Enclave, one key per device, never synchronised; and rows written before
  the columns exist read as *legacy*, quietly, while NULL signatures on an order that has
  key rows read as *unsigned*, warned. The two sentences that hold: *who* wrote a row is
  already free from CloudKit's system fields — now the trust anchor itself — and the
  signature answers *whether a key entitled to write it did*, which permissions cannot.
  No longer deferred: it is Stage 1 of the epoch.
- **Accountless couriers and support staff**: out of this design's reach — a private
  `CKShare` requires an iCloud account per participant, and an App Clip changes the
  install experience, not the identity requirement (Devin Review, second round — an
  earlier draft of this section promised otherwise and was wrong). If accountless
  identities ever become a requirement, the answer is a separate authenticated relay,
  not CloudKit — a different feature, not a flag on this one.

## The development schema, verified (2026-10)

`--ckschema-seed` (DEBUG only) opens an **isolated** `AppDatabase` in
`Application Support/ckschema-seed/` — removed and recreated per run, provider
account `yandex:ckschema-seed`, same CloudKit container — writes one fully
populated row per synchronized table, flushes, then deletes every seeded row
children-first and flushes again so the tombstones ship. The real store's
`startSync()` is skipped on a seed launch, so nothing the seed writes can sit
in the sender's data (the earlier store-sharing seed is the YD-26 class).
`--ckschema-seed-clean` reopens that directory and deletes by the deterministic
ids, for a run that died between flushes.

`xcrun cktool export-schema --environment development` after a run on a
development-signed device confirms **all sixteen** custom record types exist
with every declared column present as a field — NULL columns never become
fields, so presence is proof the write carried a value:

- **Shared tier:** `orders` (5), `routeStops` (20 — all `AddressParts`,
  `contact*` and `visit*` fields), `orderItems` (12 — both `*StopRef` value
  references), `orderProviderStates` (16 — `corpClientID`/`dueAt`/`finishedAt`/
  `providerDetail` included), `orderOptions` (7), `orderCustomFields` (6),
  `providerEvents` (8), `orderMessages` (7 — `attachmentRef`, `authorHint`),
  `orderAttachments` (7), `attachmentBlobs` (`data` lands as a CKAsset plus its
  `data_hash`).
- **Private tier:** `providerAccounts` (6), `orderPrivateStates` (5 —
  `archivedAt` included),
  `savedPlaces` (16 — `pinned` included), `customFieldDefinitions` (8),
  `parcelTemplates` (3 — `id`, `name`, `pinned`), `parcelTemplateItems`
  (11 — `templateID` and every parcel measure).
- **Device tier produces no record types by design:** `syncStates`,
  `pendingDiscoveries`, `pendingAcceptances`, `orderDrafts`, `draftStops`,
  `draftItems`, `draftCustomFields` are not registered with the engine.

Every child record carries `parent` to `orders` via its single declared FK;
`*Ref` columns are plain string fields, matching the value-reference convention.
Each row also carries `sqlitedata_icloud_userModificationTime` plus a per-field
companion — the substrate's LWW bookkeeping — which is expected, not seed noise.

Earlier seed runs surfaced two findings, both fixed: issued provisioning
profiles encode `icloud-services` as the wildcard string `"*"`, which the
entitlement gate false-rejected (Kit fix), and `building` existed in the DDL
but not in the `@Table` descriptors, so it could never serialize (Kit fix).

The seeded order is `.cancelled` under claim `ckschema-seed-claim`: a run that
dies between flushes can never read as a live delivery or start a Live
Activity, and the clean flag takes the residue back. Because the directory is
fresh, every write is a first INSERT — no prior tombstone exists under the
deterministic keys, so the YD-34 swallow never fires and no resurrection
UPDATEs remain. The production exposure this guarded against is discharged for
the Kit's writers (0.4.13): synced tables are written by upsert + prune, never
delete-then-reinsert or `INSERT OR REPLACE` (<doc:TechDebt> **YD-34** — the
item stays open only as a regression watch for future raw writes).

Nothing here promotes anything: the schema lives in **development**, and
"Deploy Schema Changes" in CloudKit Console remains a deliberate, separate act.

The inventory above is epoch 1's, and stays as the record of what was deployed there.
The epoch below seeds its new container from scratch — the seed inventory becomes the
new catalogue of record types, one fully populated row per table and every column — and
deploys it once.

## Epoch 2 — a fresh container, a fresh file, one import (decided 2026-10-06)

The production CloudKit schema is deployed but carries no real users — two TestFlight
testers (owner, 2026-10-06). Production schemas are additive: record types and fields
deploy forward and the console does not take them back, so "drop and redesign" means a
new container identifier, not a cleaned one — cheap now, expensive the day there is a
user. That unlocks a schema **epoch**, and the owner chose it (decision 1, 2026-10-06):
the schema is organised the way it should be rather than the way it happened, which is
this file's own founding sentence.

The epoch is: a new CloudKit container identifier (`SyncIdentity.cloudKitContainer` and
the entitlement), a new local file (`ydelivery-2.sqlite`), and a one-time import of the
old file's orders, places, templates, field definitions, drafts and sync state through
the typed writers — orders arrive as *legacy* rows with no key rows, which is the truth.
The old container is abandoned, not cleaned; the old file is marked in place and never
destroyed (the migration's own rule, above). What the epoch changes beyond "additive":

- `providerEvents` becomes `orderEvents` (and `ProviderEvent` becomes `OrderEvent`):
  with `placed`, `legRef` and non-owner writers it stopped being the provider's feed. A
  rename on a live container would orphan a record type; on a fresh one it costs nothing.
- No `ON CONFLICT REPLACE` on any shared primary key ("Primary keys", above). The
  private and device tiers keep theirs where a writer relies on it (`saveDraft`'s
  wholesale rewrite), stated per table.
- Stops get stable ids on the model (<doc:TechDebt> YD-40): `RoutePoint.id`, written as
  `routeStops.id`, minted at placement; the index-derived id stays only as the import's
  fallback.
- `partyRef` columns everywhere a person is referenced, from day one; `memberships` and
  `participantKeys` exist before the first synced row.
- The development schema is seeded from scratch and deployed once; the seed inventory
  becomes the new catalogue of record types.

**The additive alternative**, priced and not chosen: the same tables and columns as
additive migrations on the existing container; `providerEvents` keeps its name
(`OrderEvent` can still be the Swift name over the old table name); the REPLACE clauses
stay and every signed writer states `OR IGNORE`; stop ids arrive later as an optional
column. Everything in the doctrine holds either way. The cost of the alternative is
carried forever in two names and one footgun.

**The container, the bundle id and the app record.** The container is the only
identifier that changes. A container is an entitlement value and a CloudKit namespace,
nothing more; an app may list several, and the app record, the bundle id, the App Group
and the Keychain access group all stay. Name it `iCloud.com.learnable.YDelivery.v2`:
epochs are small integers, never semantic versions, because an epoch is a wipe and
nothing else about it is comparable. Containers cannot be deleted from a developer
account; the old one simply stops being opened and may stay listed in the entitlement
during the transition. The Console's "reset environment" applies to development only,
which is fine: the new container's development schema is seeded fresh and deployed once.
*Not a new app, not a new bundle id:* a new bundle id is a new App Store Connect record —
the listing work of #88 redone, new TestFlight groups, and every identifier-bound thing
(App Group, Keychain access group, push topic) re-registered, for nothing the container
does not already give. Apple does not ban two listings, but Guideline 4.3 can reject a
duplicate, and the old record would be deleted anyway, so the question answers itself.
macOS later rides the same bundle id and the same record as a universal purchase; a
separate Mac bundle id is only for a Mac app sold separately, which is not the plan.

The three laws stand: a root has zero FKs, a shared child has exactly one, FK-ness is a
DDL fact. Synced tables use plain `TEXT PRIMARY KEY NOT NULL` with no conflict clause
and `ON DELETE CASCADE` on their one FK (`sqlite-data` rejects `RESTRICT`/`NO ACTION`
on single-FK tables). Every reference to a person is a `partyRef`.

**Identity on signed tables** (amended 2026-10-08, review of #135). A signed row's id
belongs to one writer: a caller-held id is held by the device that minted it, and a
*derived* id carries the writer's key id among its inputs — `orderID ‖ providerEventID ‖
keyID` for a journal row, `orderID ‖ providerRevision ‖ providerStatus ‖ routeDigest ‖
keyID` for a sighting, `orderID ‖ partyRef ‖ keyID` for a share-mirrored membership; a
decision a later one can supersede — a role or leg assignment, a rating, a message —
holds a caller-held id per decision instead, or the second decision would collide with
the first (<doc:Collaboration> → rule 1). Two devices that record the same fact
therefore write two rows, never one CloudKit record: the engine merges a colliding
insert column by column and overwrites the loser's local row with the result, which
would put one device's signature beside the other's key id and read *invalid* for a fact
both wrote honestly (<doc:Collaboration> → "The facts that reshaped the design", 6).
Only observations fold — two decisions with identical content are two decisions. The
*fact* is deduped at read, like list ordering: rows that agree on the fact — the frozen
column list minus `id` and `authorRef`, plus the party the verdict resolves in place of
the raw `authorRef` (a pre-identity row signs NULL there, a later row the UUID, and both
resolve to the same owner; third round); writer identity (`id`, `signingKeyID`,
`signature`) is left out, since it differs by construction between two honest devices
(second round, 2026-10-08) — collapse to one entry per `(orderID, providerEventID)`, per
`(orderID, providerRevision, providerStatus, routeDigest)` (a sighting's `source` is
provenance, left out like writer identity) — the verified one when any is, else the
earliest stamp, then the smallest id, so every device derives the same answer — while
rows that share a key but disagree, or come from a different party, stay apart, each
with its own verdict: nothing is hidden, and a verified row beside an invalid twin is
the forgery made visible. A decision's rows are a different operation, *selection*, not
dedupe (fourth round, 2026-10-08): membership rows group by party and leg rows by `ref`,
every row stays as the decision's history, and the read selects the effective one — the
latest verified owner-written row — without collapsing the others. Dedupe merges rows
that record one fact into one entry; selection picks which of several decisions is in
force and keeps them all. The cost is one row per owner device for each journal
operation, and a trail read that collapses them; the alternative — one record per
operation with signatures as a side table — would have moved the signature out of the
statement that binds the values, which rule 3 forbids. Derived ids use the Kit's
existing derivation, components joined with `|` under a per-kind namespace; every
component is a UUID, a hex digest, a key id, a status word, a binding kind or an
integer, none of which can contain the separator. Projections keep today's
device-independent ids (`routeStops`, `orderCustomFields`, the discovered order's
`(providerAccountRef, claimID)`): they are *meant* to merge.

### Stage 1 — keys, memberships, ratings, the signed columns (epoch 2 spelling)

```sql
CREATE TABLE IF NOT EXISTS "participantKeys" (
  "id" TEXT PRIMARY KEY NOT NULL,                      -- UUIDv5(participantKey ‖ orderID ‖ keyID ‖ bindingKind): one binding statement
  "orderID" TEXT NOT NULL REFERENCES "orders"("id") ON DELETE CASCADE,
  "partyRef" TEXT,                                     -- the writer's party; NULL until the device knows itself
  "keyID" TEXT NOT NULL,                               -- p256.v2.<16 hex>
  "publicKey" TEXT NOT NULL,                           -- base64 X9.63, 65 bytes
  "bindingKind" TEXT NOT NULL,                         -- cloudkit · server
  "bindingProof" TEXT,                                 -- NULL for cloudkit (the proof is the server stamp)
  "bindingKeyID" TEXT,                                 -- which server key attested, server mode only
  "boundAt" REAL,                                      -- the attestation's own time, server mode only
  "addedAt" REAL NOT NULL,
  "signature" TEXT                                     -- self-signed over every column above; signingKeyID is keyID
) STRICT;

CREATE TABLE IF NOT EXISTS "memberships" (
  "id" TEXT PRIMARY KEY NOT NULL,                      -- mirrored row: UUIDv5(membership ‖ orderID ‖ partyRef ‖ keyID); an assignment: caller-held
  "orderID" TEXT NOT NULL REFERENCES "orders"("id") ON DELETE CASCADE,
  "partyRef" TEXT NOT NULL,
  "role" TEXT NOT NULL,                                -- participant · receiver · dispatcher · courier · removed
  "addedAt" REAL NOT NULL,
  "authorRef" TEXT, "signingKeyID" TEXT, "signature" TEXT   -- owner-written
) STRICT;

CREATE TABLE IF NOT EXISTS "orderEvents" (             -- today's providerEvents, renamed
  "id" TEXT PRIMARY KEY NOT NULL,                      -- journal: UUIDv5(providerEvent ‖ orderID ‖ providerEventID ‖ keyID)
                                                       -- sighting: UUIDv5(providerEvent ‖ orderID ‖ providerRevision ‖ providerStatus ‖ routeDigest ‖ keyID)
  "orderID" TEXT NOT NULL REFERENCES "orders"("id") ON DELETE CASCADE,
  "legRef" TEXT,                                       -- value → legs.ref, the logical leg; NULL = the order's only leg
  "providerEventID" INTEGER,
  "providerRevision" INTEGER,                          -- the wire's revision: the journal event's own, the claim card's `revision` (not `version`)
  "at" REAL NOT NULL,
  "kind" TEXT NOT NULL,                                -- status_changed · price_changed · sighting · placed
  "providerStatus" TEXT, "detail" TEXT, "source" TEXT NOT NULL,   -- journal · search · card · app
  "routeDigest" TEXT,
  "authorRef" TEXT, "signingKeyID" TEXT, "signature" TEXT
) STRICT;

CREATE TABLE IF NOT EXISTS "orderRatings" (
  "id" TEXT PRIMARY KEY NOT NULL,                      -- caller-held UUID (retry = same id, INSERT OR IGNORE)
  "orderID" TEXT NOT NULL REFERENCES "orders"("id") ON DELETE CASCADE,
  "legRef" TEXT,
  "authorRef" TEXT,
  "subjectKind" TEXT NOT NULL,                         -- leg · party · stop · provider
  "subjectRef" TEXT NOT NULL,                          -- leg ref (the logical leg) · partyRef · stop id · providerAccountRef
  "subjectLabel" TEXT,                                 -- display snapshot: «Сергей · м 234 ор 77», a place name
  "score" INTEGER NOT NULL,                            -- 1…5, checked at the write boundary
  "comment" TEXT,
  "at" REAL NOT NULL,
  "signingKeyID" TEXT, "signature" TEXT
) STRICT;

-- orderMessages: + authorRef, signingKeyID, signature (authorHint kept as a display cache)
-- orderAttachments: + dataHash, authorRef, signingKeyID, signature
-- routeStops: "id" minted by the writer, no REPLACE clause

-- device tier (never registered with SyncEngine):
CREATE TABLE IF NOT EXISTS "localIdentity" (
  "authority" TEXT PRIMARY KEY NOT NULL,               -- cloudkit:<container> · server:<host>
  "subject" TEXT NOT NULL,                             -- the user record name, or the server's party id
  "partyRef" TEXT NOT NULL,
  "fetchedAt" REAL NOT NULL
) STRICT;
```

Registered with the engine: `participantKeys`, `memberships`, `orderRatings` join
`tables:`. `DerivedNamespace` gains `party`, `participantKey`, `membership`, and later
`leg`. The schema seed writes one fully populated row per table and every column, because
NULL columns never become CloudKit fields.

**`memberships` — the share's mirror and the server's source.** The owner's device
writes an `INSERT OR IGNORE` signed `participant` row for every accepted share
participant without one, after each sync pass, under the derived id above — two owner
devices reconciling the same share each write their own row, both valid, same role. A
role *assignment* by the owner — receiver, dispatcher, courier — is a new row under a
caller-held id (amended 2026-10-08, review of #135: a derived `orderID ‖ partyRef` id
would have made every later assignment collide with the first row and vanish under
`INSERT OR IGNORE`); a retry re-inserts the same caller-held id. Only rows that read
*verified* as the owner's count: a membership row anyone else appends is *notEntitled*
and changes nobody's verdict. The effective role of a party is the latest such row by
`addedAt` — on an exact tie `removed` dominates, then the smallest id, so every device
derives the same answer and a hash-settled tie between two live roles is named as the
residual it is, settled for good by the owner's next assignment; earlier rows stay as
the role's history. When the share no
longer lists a party, the reconcile appends a `removed` row (same review: an append-only
table with no way to say "no longer" would have kept a removed participant's `member`
entitlement forever), and entitlement is judged *as of the row* — the party's effective
role at the row's own stamp — so what a member wrote while a member stays verified and
anything dated after the removal reads *notEntitled* (<doc:Collaboration> → "Verdicts
and entitlement"). The reconcile sees the removal because the `CKShare` is a record in
the shared zone: a fetched change to it refreshes the root's cached share (`cacheShare`
in the engine's fetched-changes path), so running after each sync pass — in the app,
beside the journal pass's existing owner-side drains, which already re-prove the
identity generation per iteration — is enough; a removed participant is absent from
the decoded share's `participants` or carries `acceptanceStatus == .removed`. Whether a
participant *leaving* arrives the same way as the owner removing one is on the
open-verifications list. Roles live here and in `legs`, never on `participantKeys`,
never in a writer's claim. Before the owner's device has reconciled a row, a party the
authority lists as a participant counts as a member; a membership row's role wins over
the share's binary participant status. So a participant the owner's device has not yet
mirrored — a courier invited while the owner is offline — still reads as a member
through the share, and the verdict never degrades to a generic warning for want of a
row; only a role beyond *participant* waits for the owner's device, as a leg assignment
does anyway. On the host the table imports as is (<doc:Collaboration> → "Ready for an
independent host"). <doc:TechDebt> YD-45.

**`orderRatings` — a fact, not a message kind.** A rating is a human statement in the
order's stream — attributable, appendable, revisable by posting again — but its storage
is a table: it is *aggregated* (per courier, per place, per sender), it has a structured
*subject*, and messages' free text should stay free text. The chat *renders* it as an
event row by merging the two streams by time; "only the last counts" is a read-time
derivation — the effective rating per (author, subject) is the row with the latest `at`,
earlier rows stay as history (<doc:Vision> → "Players, trust and reputation" for who
rates whom and where ratings aggregate). The id is caller-held so a retry is the same row.
Entitlement for a rating needs no join to anything mutable: every member may post one,
and the row carries its author, subject and leg itself. The table is created, seeded and
deployed at the epoch with the rest of Stage 1 — one development schema, one production
deploy — and its writer, its reads and the UX land in the ratings phase (<doc:Roadmap> →
T2), so no second schema deploy stands between the two (clarified 2026-10-08, review of
#135).

### Stage 2 — legs (when a second provider or the courier edition starts)

```sql
CREATE TABLE IF NOT EXISTS "legs" (
  "id" TEXT PRIMARY KEY NOT NULL,                      -- caller-held, one per assignment (a retry reuses it): the row its signature covers
  "ref" TEXT NOT NULL,                                 -- UUIDv5(leg ‖ orderID ‖ fromStopRef ‖ toStopRef): the logical leg every legRef names; rows group by it
  "orderID" TEXT NOT NULL REFERENCES "orders"("id") ON DELETE CASCADE,
  "position" INTEGER NOT NULL,                         -- travel order of legs
  "kind" TEXT NOT NULL,                                -- platform · courier
  "providerAccountRef" TEXT,                           -- platform legs: "yandex:<corp>"
  "courierPartyRef" TEXT,                              -- courier legs: the assignee; exactly one of the two is set
  "fromStopRef" TEXT NOT NULL, "toStopRef" TEXT NOT NULL,   -- values → routeStops.id
  "assignedAt" REAL NOT NULL,
  "authorRef" TEXT, "signingKeyID" TEXT, "signature" TEXT
) STRICT;
```

A leg row is an *assignment fact*, written once by the owner. Status, price and courier
per leg are projections computed at read from that leg's events (`orderEvents.legRef`);
`orderProviderStates` stays the order-level projection the list reads. A dock is not a
stop role: it is the stop that is `toStopRef` of leg *n* and `fromStopRef` of leg *n+1*.
Existing orders get an implicit leg 0 (events with NULL `legRef`). Two columns for the
carrier instead of one mixed-type `providerRef`, so a server with real foreign keys can
constrain each. A leg has two identities (second round, 2026-10-08): `ref`, the logical
leg `UUIDv5(leg ‖ orderID ‖ fromStopRef ‖ toStopRef)` that every `legRef` — an event's,
a rating's — names and that two owner devices derive alike, keyed by its endpoints'
stable stop ids rather than its position, which a restructured route can renumber (third
round, the same reason items reference stops by id); and `id`, one assignment's row,
which its signature covers — caller-held and minted per assignment (third round,
2026-10-08: a derived `orderID ‖ position ‖ keyID` made a device's reassignment of a
position collide with its first assignment and vanish, leaving the previous courier
assigned). Leg rows group by `ref` and are *selected*, never deduped — each assignment
stays as history, since only observations fold (rule 1): the effective assignment is the
latest verified owner-written row by `assignedAt`, ties by the smallest id — named as
the residual it is, like a membership tie — earlier rows the assignment's history; a
courier's entitlement follows the effective assignment as of the event's own stamp, the
rule memberships use. Two owner devices assigning one leg offline is a conflict the
selection makes visible — both rows shown, the effective one marked — never an event
that lost its leg: an event names the logical leg, so no row's demotion can orphan it.
(The earlier wording let `legRef` name a row id and collapsed legs by position, which
would have dropped the row some events pointed at.)

### What is deliberately not changed

- `orderProviderStates`, `routeStops` (beyond its id), `orderItems`, `orderOptions`,
  `orderCustomFields`: same writers, same merge rules, no signature columns. Their
  integrity is derived ("Derived integrity", above).
- The private and device tiers: unsigned. The owner is the only writer and nothing there
  is shared.
- The sighting dedupe: kept as `INSERT OR IGNORE`, with the provider's revision, the
  route digest and the writer's key joining its key (identity, above), because
  immutability is what signing needs and a later revision is a new fact, not a refresh
  of the old one.
- The widget snapshot contract, the wire log as a file, the share grant model, read-only
  by default.

### What the epoch discharges

YD-40 (stop ids minted on the model) and YD-41 (no REPLACE on shared keys) at the epoch
itself; YD-42 (`dataHash`) and the Kit's half of YD-43 (`authorRef`) with the signed
columns; the Kit's half of YD-45 (`memberships`) with its table. The app's halves —
names resolved through the authority, the membership reconcile after each sync pass —
land with the app's adoption (<doc:Roadmap> → "Next — the trust layer").

## Direction — legs and participants: what not to cement (2026-10-05)

The owner's direction (<doc:Vision> → "Direction — many providers, docked legs,
independent couriers") does not change the schema today. It changes what a new column
may assume. Three rules for every schema PR from here:

1. **Provider-specific state goes on the mirror, never on `Order`.** `OrderProviderState`
   is 1:1 today; per-leg state arrives later as a *projection of that leg's events* at
   read (Stage 2 above, 2026-10-06 — not the `LegState` row per leg this rule first
   named), and the order-level mirror stays what the list reads; a column added to
   `Order` because "there is only one claim" is the thing the migration would have to
   unpick. `claimID`, `tariff`, `price`, courier fields stay on the mirror.
2. **Events name their writer.** `ProviderEvent` is "owner-written" today; a courier's
   leg will have events the courier writes. New event columns must not assume the owner —
   an `authorRef` (the `*Ref` convention: a `partyRef`, not a user record id), a `legRef`,
   and the signing columns (<doc:Collaboration>) are the shape. **Landing in Stage 1 of
   the epoch** (2026-10-06) — until the columns exist, nothing should read "the owner
   wrote this" from the table alone.
3. **A stop may be a dock.** `RouteStop.role` is `pickup`/`dropoff`/`return` from the
   sender's point of view; a dock is not a fourth role but a leg boundary — the stop where
   leg *n* ends and leg *n+1* begins, whatever the sender calls it (a `return` stop can be
   a dock too: the parcel comes back to the sender through a hand-over). Keep `role` the
   sender's word and let legs carry their own stop references later — do not add a `role`
   value that bakes the two-leg case into the sender's route.

Identity, for the record: `providerAccountRef` is the Yandex account's name for the
owner and stays that; a courier is a **share participant** (a CloudKit user the owner
granted), so their identity rides the share and a `memberships` row, never a provider
account. The private tier is the owner's and stays unshared; a courier's own private
notes would be their own database's private tier — the courier edition is a participant,
not a second owner. It is the same app with a member's view: it holds a device key like
any other install, publishes it into the shares it is invited to, and writes its leg's
events under `legRef`; entitlement comes from the owner's `legs` row naming it — no
second store, no second schema.

Known schema work that respects these rules and is next: the epoch and its Stage 1
tables (above) — the participant key table is designed, and the signing columns ride it.
`OrderPrivateState.archivedAt`
has already landed — 0.4.14, the archive's home on the private tier, the seed carrying
it (<doc:Design>).

## See Also

- <doc:Collaboration> — the stack research and grant model this schema implements
- <doc:Design> — the persistence decision this settles
- <doc:Roadmap> — where the migration sits in the phase order
- <doc:TechDebt> — YD-5, YD-12, YD-13, whose discharges this design carries; YD-40 to
  YD-45, which the epoch and its Stage 1 carry
