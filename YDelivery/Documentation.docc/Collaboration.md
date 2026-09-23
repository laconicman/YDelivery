# Collaboration and sharing — research (2026-09-24)

How orders, activity, and future parcel photos reach people other than their creator —
privately, on purpose, and without making the provider credential a permission system.
This file holds the research behind the persistence-stack lean recorded in <doc:Design>
and the spike endorsed in <doc:Roadmap>. It is a decision record, not an implementation.

## Three truths

The architecture separates three kinds of truth, and the separation is the whole design:

- **Provider truth** — the Yandex claim: status, price, route, performer. Only the token
  holder for that `corp_client_id` can accept, cancel, or edit it. App-level grants can
  never widen this; they were never meant to.
- **Local truth** — what a device persisted and can render offline: the order store, the
  sync cursor, the pending queue.
- **Shared truth** — app-owned collaboration data: which orders are visible to whom,
  photos, and the per-order chat stream. This layer contains *no provider authority*.

The consequence the author intuited ("we barely should rely on the same auth token") is
that the token and the grant are independent axes: the Yandex token gates *provider
operations*; CloudKit participation gates *app data*. A collaborator who never
authenticated with Yandex can still legitimately read — and, where granted, post to — a
shared order's stream.

## The grant mechanism is CKShare

[CKShare](https://developer.apple.com/documentation/cloudkit/ckshare) is the platform's
private-sharing primitive, and its shape happens to match this product's needs closely:

- **Two granularities.** A share wraps either an entire custom record zone, or a *record
  hierarchy rooted at one record* — children inferred **only** through each record's
  `parent` property, never through custom reference fields. For this app the natural root
  is an `Order`; route points, attachments, and the chat hang below it. You share one
  delivery, not a database.
- **Private by construction.** `publicPermission = .none` makes the share invite-only:
  every participant needs an iCloud account, and a share caps at **100 participants**.
  Nothing in this design touches the public database — `CKSyncEngine` refuses to sync it
  anyway.
- **Notes-style flows are the built-in path.** Once saved, a share carries a `url` the
  owner distributes any way they like; a recipient who taps it has their participation
  processed by the system automatically (`CKSharingSupported` must be set in
  `Info.plist`). `UICloudSharingController` — wrappable for SwiftUI — is the free sheet
  for listing participants and setting each one's read-only / read-write permission.
  `allowsAccessRequests` yields Notes' "request access" flow for people who hold the link
  uninvited; `blockedIdentities` gives owners a block list.
- **Lifecycle is handled.** Removing a participant revokes their access; a participant
  deleting the share removes only themselves. A record can take part in exactly one
  share (`alreadyShared` on the second attempt), and only the owner can delete a shared
  hierarchy's root — which deletes the share with it.

This is the grant mechanism the question asked about: per-record, invite-based,
cross-organization by nature — a participant does not need to share an org, a token, or
even *have* provider credentials. A dispatcher who only tracks, a partner org's agent,
the sender's own second device — all the same mechanism.

## The write boundary

Participants' writes reach **an append-only feedback stream, not fields** — the shared
hierarchy exposes a per-order chat (`OrderMessage`: text, photos, structured kinds like
`receptionConfirmed`) and attachment payloads; there is no participant-writable field
surface to edit, which is the point. Provider-mirrored rows (`OrderProviderState`,
`ProviderEvent`) are owner-written projections the owner's journal sync overwrites
authoritatively — and since CloudKit permissions are per-record, a read-write
participant *can* technically touch them, so the boundary holds by layering:
read-only-by-default grants (locally enforced via `writePermissionError`), append-only
writable surface, and owner-overwrite authority. The full accounting lives in
<doc:Schema> → "The forgery boundary" — Devin Review caught the soft version of this
claim on the first draft, and the author's own concern agreed.

Because a participant's view of provider state is therefore a *relay* — fresh only as
the owner's last sync — the product decision stands (author, 2026-09-24): **every shared
surface shows the timestamp of the state it presents** ("status as of …"), so a
secondary consumer can see staleness instead of mistaking it for liveness.

## The organization question — possibly free, unverified

The original framing ("members of one organization see each other's claims") may not
need app-level sharing at all: `corp_client_id` is derived *from the token* server-side,
so if Yandex issues each org member a token mapping to one `corp_client_id`,
`claims/search` under any member's token may already return the org's whole claim set —
provider-side visibility, free. One test credential cannot answer this; it is listed
under open verifications. If it holds, app sharing is still required for attachments
and for the cross-org case — it just shrinks to those.

## Parcel photos and other app-owned attachments

Photos the provider API cannot accept live in the shared truth as **child records of the
order hierarchy** (`parent: orderRecord`, so they inherit the share automatically) with
payloads stored as `CKAsset` — record fields cap at 1 MB, assets stream and cache
separately. Deleting the order deletes the hierarchy; nothing is public and nothing is
sent to Yandex. Attachments should be their own record type/table so their lifecycle
(retention, eviction, retry) never entangles the order row itself.

## Silent notifications and the relay path

[CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine) (iOS 17,
the floor) auto-discovers or creates a `CKDatabaseSubscription` and converts
remote-change pushes into silent notifications that schedule fetches — the "something
changed → wake me" mechanism working across a user's own devices *and* shared zones.
Multiple engines may run in one process (one private, one shared), manual
`fetchChanges`/`sendChanges` back pull-to-refresh, transient errors retry themselves,
and the engine persists an opaque state blob — the same shape our journal cursor store
already proved. The boundary is unchanged and now sharper: **CloudKit can only report
CloudKit changes.** Yandex events still enter through the owner-side journal poll; the
push relay remains its own Later deliverable (<doc:Design>).

## The stack survey — four candidates

| Stack | Sharing surface | Honest cost |
|---|---|---|
| `NSPersistentCloudKitContainer` | Native `CKShare`, Apple's proven path | Replaces the model layer with Core Data |
| NSPCK + SwiftData coexistence | Via the NSPCK half | A fragile seam; least needed now that a fourth path exists |
| Raw `CKSyncEngine` + file store | Hand-rolled zones, share lifecycle | Most code, most control — viable as a shared-slice add-on |
| **`sqlite-data`** (Point-Free) | `SyncEngine.share` / `acceptShare` / `CloudSharingView` — a real `CKShare` wrapper over `CKSyncEngine` | One dependency covering private sync *and* sharing, keeping plain-struct models and an explicit SQL schema |

`sqlite-data` is the discovery of this research: it is the only candidate that unifies
private multi-device sync and `CKShare` collaboration in one stack while preserving the
app's value-type model style and demanding the explicit, migration-managed schema the
relational discipline calls for. That it rides `CKSyncEngine` rather than hand-rolled
`CKOperation` graphs matters too — the modern engine's scheduling, subscription, and
state-serialization machinery comes with it (author's noted preference, 2026-09-24). Its constraints line up with the design rather than
fighting it: only root records are directly shareable (we share the order hierarchy
anyway), one-to-many descendants follow the root, many-to-many sharing is unsupported
(not needed — membership rides the share's participant list), and `privateTables` —
verified — sync to the owner's private database while remaining unshareable, which is
exactly the tier "follows my devices, reaches nobody else" wants. Tombstones
(`_isDeleted`) make deletes propagate honestly. The caution the author voiced — keeping
pace with Point-Free's uncommon abstractions — is real and priced into the spike below.

### What the upstream pass verified (2026-09-25)

The open-verifications checklist below is now mostly closed, by a compile spike against
`sqlite-data` 1.12.0 (MIT, actively maintained, iOS 16 floor — under our iOS 17):

- **`Data` → `CKAsset` is automatic.** Every BLOB column becomes a `CKAsset` on the
  wire; the package's own guidance is to keep megabyte payloads in a dedicated table
  behind the metadata row. Parcel photos get the asset path for free.
- **Shareability is a schema fact.** The engine reads `PRAGMA foreign_key_list`:
  zero declared FKs makes a root shareable, exactly one lets a child join the share
  (directly or transitively), two or more excludes the row. A UUID held in a plain
  column — no `REFERENCES` — is *not* an FK, which is what legitimizes the schema's
  `*Ref` convention (<doc:Schema>).
- **The API surface exists as described.** `SyncEngine.share(record:configure:)`
  returns `SharedRecord` (or `unshare(record:)`), `acceptShare(metadata:)` takes a
  `CKShare.Metadata` from the scene-delegate handoff, and `CloudSharingView` compiles —
  gated to UIKit platforms, which the app satisfies. One precondition worth knowing:
  `share` throws `recordMetadataNotFound` until the record has synced to iCloud at
  least once — an offline-created order cannot be shared until its first upload lands.
- **Read-only is enforced locally.** A participant write against a read-only grant
  throws `DatabaseError` matching `SyncEngine.writePermissionError` — the permission
  boundary is real code, not politeness.
- **The dependency footprint is real:** ~9 Point-Free packages ride along (GRDB,
  StructuredQueries, the concurrency/dependency utilities). Accepted deliberately —
  this is the "keeping pace with Point-Free" cost, priced in.
- **Extensions do not share the live database.** GRDB's own App Group guidance is
  "prefer not to" — a suspended process holding the SQLite lock is a watchdog kill
  (0xDEAD10CC), Data Protection gates locked-device reads, and cross-process
  observation doesn't fire. The widget contract is therefore an app-rendered snapshot
  file, not shared DB access (<doc:Schema> → "The widget contract").

## Where this landed

Author direction, recorded 2026-09-24:

1. **Spike `sqlite-data` first** — a try, not a marriage. `NSPersistentCloudKitContainer`
   remains the incumbent fallback if the spike fails its checklist.
2. **Share links are the distribution** — a `CKShare` URL opens the app, and an
   **App Clip** is the endorsed consumer surface for participants who will never
   install the full app (the link *is* the invitation).
3. **Staleness is displayed, not hidden** — every shared surface carries the timestamp
   of the state it presents (the write boundary above).
4. **Public sharing stays off** — `publicPermission = .none`, no public-database
   records; organization claims ride provider-side visibility where it exists.

## Open verifications before committing

Closed by the spike, recorded above: `Data`→`CKAsset`, the API surface, floor/license/
maturity, the permission enforcement, and the App Group answer. What remains open needs
a device, a second credential, or both:

- Whether two tokens mapping to one `corp_client_id` see the same claim set — the
  free-org-visibility wire test; needs a second credential.
- Share acceptance end-to-end on real devices: the URL handoff into
  `acceptShare`, the App Clip entry path, participant removal, and offline-writes
  that sync late.
- Whether the journal's owner-side writes batch cleanly into shared-record updates
  without a write per event — an instrumentation question once the stack lands.

## See Also

- <doc:Schema> — the relational design this research produced
- <doc:Design> — the reopened persistence decision this research feeds
- <doc:Roadmap> — the spike this research endorses
- <doc:Vision> — where collaboration sits in the capability map
