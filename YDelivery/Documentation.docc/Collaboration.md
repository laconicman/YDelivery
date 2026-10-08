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
authoritatively (since 2026-10-06 the events are signed facts and the mirror is checked
against them at read — "Sign facts, derive state", below) — and since CloudKit
permissions are per-record, a read-write participant *can* technically touch them, so
the boundary holds by layering:
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
`sqlite-data` 1.12.0 (MIT, actively maintained, iOS 16 floor — under our iOS 17). The
spike's package and source are preserved in-repo at <doc:Spike> — the claims below are
reproducible, not remembered:

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
5. **Provider state is signed by the device that wrote it (author's idea, 2026-09-29).**
   The write boundary above holds by layering — read-only grants, an append-only
   participant surface, owner overwrite — but nothing lets a reader *check* that a mirror
   row is the owner's. A signature does, cheaply:
   - **What is signed.** The owner's sync, when it writes `OrderProviderState` or a
     `ProviderEvent`, signs a canonical serialisation of the row (sorted keys, the
     `UnixEpochSecondsRepresentation` doubles as stored) and stores the signature in a new
     owner-written column, `signature BLOB`, plus a `signingKeyID`. Participants never
     write these tables, so the column costs them nothing.
   - **Which key.** CryptoKit `Curve25519.Signing`; the private key lives in the
     **iCloud Keychain** (`kSecAttrSynchronizable`), so every device of the owner's account
     holds it and no participant ever does; the public key rides on the `Order` root
     (owner-written) as `ownerSigningKey`. HMAC would be cheaper but leaves participants
     unable to verify without the secret — the asymmetric key is what makes the check
     public.
   - **Who verifies.** Every reader, on read: the owner's other devices confirm their own
     records were not rewritten by a read-write participant; a participant confirms the
     mirror it relays came from the owner's key. A row that fails renders as *unverified
     provider state* beside its «as of» stamp — visible, never hidden, never a crash. The
     forgery boundary <doc:Schema> reserves for `lastModifiedUserRecordID` becomes a
     signature check instead — stronger, and independent of CloudKit's system fields.
   - **What it does not do.** It does not stop a read-write participant from *writing* a
     mirror row (CloudKit permissions are per record); it makes the write detectable. A
     participant who rewrites the `Order` root's public key can forge — so the key is
     also pinned locally on first sight (TOFU), and a changed key is itself a warning.

   Decision: **sign the two owner-written tables; verify on read; render, never refuse.**
   The author's own framing — "maybe excessive given the permissions, but cheap" — is the
   right weight: two columns, one Keychain item, one verify per row read. Sequenced after
   the device pass of share acceptance, since verification needs two accounts to test.

   *Kept as the origin (2026-10-06).* Three of its mechanisms did not survive the
   generalisation of 2026-10-05 and the design pass after it: the mirror is a projection
   merged per field and cannot carry a row signature; the key is per device and never in
   the iCloud Keychain; and the trust anchor is the authority's stamp on a key row, not a
   first-sight pin. What survived is the shape — sign at write, verify at read, render
   and never refuse — and the point: a reader can *check*.

### Sign facts, derive state (2026-10-06)

The owner's direction (<doc:Vision>) added writers to the shared hierarchy who are not
the owner: an independent courier granted a leg writes that leg's events. On 2026-10-05
the 2026-09-29 design — one owner key on the `Order` root, two owner-written tables
signed — was generalised into "every writer signs, not only the owner", recorded so the
first implementation (the parked PRs Kit #36 / app #92) would be reshaped rather than
shipped and migrated. Read on 2026-10-06 against the upstream facts verified that day
(below), the generalisation was **right in intent and wrong in two mechanisms**, and the
design pass of that date — read by the owner as the design review the generalisation
sequenced, every decision recorded — replaces it. What it got right stands and is
restated here: a key per writer, published as rows where readers already look; every
signed row names its key; entitlement is role × leg; verification stays read-time and
never refuses; the verdict is never persisted into the row or into Codable JSON. What it
got wrong: trust pinned per participant on first sight with a chain of key rows — the
chain was itself the first draft's review fix against a participant adding a fresh key
that claims to be the owner's, and the authority's stamp is the stronger answer to that
attack: it makes a pin unnecessary and a chain a hole, since whoever re-pins blesses the
forgery; owner keys in the iCloud Keychain (two offline devices split, and a Secure
Enclave key cannot synchronise at all); a write that could not be signed "re-signed on
the next successful write of that row" (re-signing stored bytes legitimises whatever is
stored, tampered or not); and signatures on the mirror, which CloudKit merges per field.
The four read-side lessons from the review of #92 stand as written and are carried below.

The one sentence: **signatures live on append-only rows that one writer creates once;
mutable rows are projections, and a reader checks a projection against the signed facts
it should reflect.** The existing design was already shaped this way — the event feed is
the provider's history, the mirror is a cache of its latest word — and the doctrine makes
it the rule. The schema it lands in is <doc:Schema> → "Epoch 2"; the phases are
<doc:Roadmap> → "Next — the trust layer"; the two load-bearing choices and their
rejected alternatives are <doc:Design> → "Parties, not CloudKit names" and "P-256 in the
Secure Enclave"; the players, the ratings and the registry are <doc:Vision> → "Players,
trust and reputation".

#### The facts that reshaped the design

Verified on 2026-10-06 (the sixth on 2026-10-08), each with the pin that settles it.

1. **`sqlite-data` merges conflicts per field, last writer wins per column.** Each column
   carries its own `userModificationTime`; two devices editing different columns of one
   row both win (`MergeConflictTests.serverAndClientEditDifferentFields`,
   `CloudKit+StructuredQueries.swift` L285–342; DeepWiki index `6390b5c0`, 2026-09-14 —
   [the sqlite-data conversation](https://deepwiki.com/search/i-am-designing-per-writer-reco_1776fc78-3d2c-46cb-bf85-a17d357b729c?mode=deep)).
   A signature over a whole row therefore breaks under legitimate concurrent writes by
   the owner's own two phones: `recordProviderEvent` updates three mirror columns,
   `recordOrder` rewrites the row, and the merged row matches neither writer's signed
   snapshot. The mirror and the stops' visit columns cannot carry row signatures. Rows
   that are written once and never updated can.
2. **CloudKit stamps every record with its creator, and `sqlite-data` keeps that stamp
   locally.** `SyncMetadata.lastKnownServerRecord` archives the system fields — creator
   and last-modifier user record IDs — on every fetched change and every acknowledged
   save (`SyncMetadata.swift` L83–95; `SyncEngine.swift` L1663, L1979, L1226); a
   participant's insert into a single-FK child lands in the shared zone with `parent`
   set and the server names the participant as creator (`Triggers.swift`,
   `SyncEngine.swift` L1212–1232). This is a trust anchor nobody in the share can forge,
   and it is already on disk. The parked design pinned keys on first sight because it did
   not use it. On a server of our own the same role is played by the server's
   attestation of a key binding ("Ready for an independent host", below).
3. **The DDL's primary keys declare `ON CONFLICT REPLACE`** on `orders`, `routeStops`,
   `orderItems`, `orderCustomFields`, `orderMessages` and `orderAttachments`
   (`YDeliveryKit/Sources/YDeliveryData/Persistence/DDL.swift` at 0.4.15;
   `providerEvents` does not). A colliding plain `INSERT` silently rewrites the existing
   row, which under signing means a signed row can be replaced wholesale by anyone who
   can insert. The epoch drops the clause from every shared table; until then every
   writer on a signed table states its conflict policy in the statement
   (`INSERT OR IGNORE`), which SQLite lets override the column's clause (<doc:TechDebt>
   YD-41).
4. **The production CloudKit schema is deployed but carries no real users** (owner,
   2026-10-06: two TestFlight testers). Production schemas are additive — record types
   and fields deploy forward; the console does not take them back — so "drop and
   redesign" means a new container identifier, not a cleaned one. With two testers and a
   local import that is cheap now and expensive the day there is a user. This is what
   made the schema epoch the recommendation, and the owner's decision (<doc:Schema> →
   "Epoch 2").
5. **The Secure Enclave signs P-256 and nothing else.**
   `SecureEnclave.P256.Signing.PrivateKey` is available from iOS 13; its private key
   never leaves the hardware, and its `dataRepresentation` is an opaque blob only that
   device can use (Apple's CryptoKit documentation, fetched 2026-10-06). Ed25519 has no
   hardware home on Apple platforms. That decides the curve.
6. **A colliding insert is merged per field too.** Two devices that insert the same
   primary key offline do not get "server wins" or "client wins": the save fails with
   `serverRecordChanged`, the engine runs `upsertFromServerRecord` — the same per-column
   `userModificationTime` merge as a fetched change — overwrites the loser's local row
   with the result, and re-queues the save (`SyncEngine.swift` L1685–L1689,
   L1958–L1982; `CloudKit+StructuredQueries.swift` L154–L168; the same conversation,
   continued 2026-10-08). A derived id that two writers can both mint — the journal
   event id the Kit derives today — therefore cannot carry a signature: the merged row
   can hold one device's signature and the other's key. Found by Devin's review of #135;
   it gives rule 1 its identity clause.

Two more passes sit under this section. The Kit side of the parked branch was reviewed
prospectively against the indexed Kit in
[the Kit review conversation](https://deepwiki.com/search/prospective-design-review-agai_e8495602-4cc8-4491-85b8-168fd54eaf28?mode=deep),
and the app's write sites were enumerated in
[the app writer inventory](https://deepwiki.com/search/enumerate-every-call-site-in-t_9f6bb4a5-845c-4d8f-a72b-08c092fc6fb7?mode=deep):
real posts write `authorHint` nil, only previews and fixtures fill it, and the app has no
raw `queue.write` outside the seeds. One caveat on the record: DeepWiki's Kit index
predates Kit #41 and still describes the route rewrite as delete-then-reinsert; the
design is written against the local 0.4.15 source, where stops upsert and prune.

#### The eight rules

1. **Signed tables are append-only and never updated after insert:** `orderEvents`
   (today's `providerEvents`), `orderMessages`, `orderAttachments`, `orderRatings`,
   `participantKeys`, `memberships`, and later `legs`. Retries re-insert the same id
   with `INSERT OR IGNORE`; a conflicting insert is a no-op, never a replace. **A signed
   row's identity belongs to one writer** (amended 2026-10-08, review of #135): a
   caller-held id is held by the device that minted it, and a *derived* id — a journal
   event, a sighting, a share-mirrored membership, a leg — carries the writer's key id
   among its inputs, so two devices that record the same fact write two rows rather
   than one CloudKit record. The engine merges a colliding insert column by column —
   `serverRecordChanged` runs the same per-field `upsertFromServerRecord` as a fetched
   change, and the loser's local row is overwritten with the result — which would leave
   one device's signature beside the other's key id and read *invalid* for a fact both
   wrote honestly. Dedupe of the *fact* is a read-time derivation, like list ordering:
   the trail collapses `orderEvents` by `(orderID, providerEventID)`, and sightings by
   `(orderID, providerRevision, providerStatus, routeDigest)` — but only rows that
   *agree on the fact*: the frozen column list minus `id` (and, for a sighting, minus
   `source`: a card read and a search read of one revision are one observation), plus
   the party the row's verdict names (the binding's, so a row written before its device
   knew its party still folds once its key row is bound, and stands apart as
   *unverifiable* until then), with writer identity (`id`, `signingKeyID`, `signature`)
   left out of the comparison, since it differs by construction between two honest
   devices while each row is still verified on its own (amended 2026-10-08, second
   round: comparing the *signed* columns could never match, because the writer-specific
   `id` heads every list). One entry per fact, the verified one when any is, else the
   earliest `at`, then the smallest id, so every device derives the same answer. Rows
   that share a key but disagree on the fact, or come from a different party, are not
   collapsed: each renders with its own verdict (rule 6 — nothing is hidden), and a
   verified row beside an invalid or not-entitled twin is the forgery made visible, not
   a duplicate. UI identity follows the chosen representative on each device; devices
   need not pick the same row, only the same fact.
2. **Unsigned projections:** the `orders` root, `orderProviderStates`, `orderOptions`,
   `orderItems`, `routeStops`, `orderCustomFields`. They keep today's writers and today's
   merge behaviour. Their integrity is a *derived verdict*: the mirror's `providerStatus`
   must equal the latest verified status-bearing event; the stored route must hash to the
   digest carried by the latest verified digest-bearing event.
3. **Every writer signs exactly the values it binds,** in the same statement, in the same
   transaction, from the same argument list. No write ever re-reads stored bytes to sign
   them, and no write signs rows it did not author. A write that cannot sign (key
   unavailable at that moment) inserts with NULL signature columns; the row reads
   *unsigned* forever, which is the truth and renders as such.
4. **Keys are per device and are published as rows** in the order they write into. Trust
   is resolved from the authority's binding on the key row, not from a pin and not from a
   chain.
5. **Verdicts are read-time values beside the model, never fields on it** — never
   persisted, never in Codable output: reads hand back `Attested<T>`.
6. **Verification never refuses, drops, or hides.** A failed verdict renders as a warning
   row in the design system's feedback roles beside the data it concerns, naming the
   writer when the authority discloses a name.
7. **Entitlement is judged at read, not enforced at write.** CloudKit permissions are per
   share, not per table; a read-write participant can insert an order event. Such a row
   verifies as a correctly signed row by a party who may not write that row kind, and
   renders that way. On a server the same rule is enforced at upload as well; the
   read-side verdict stays as the second layer.
8. **No CloudKit vocabulary in rows or models.** `CKCurrentUserDefaultName`, record names,
   `CKShare` participants exist only inside the identity authority adapter. Rows carry
   `partyRef`; models carry `Party`.

#### What each rule gives up, and what was rejected

The owner asked for the rules most worth a second look to be explained before accepting
them (decision 3, 2026-10-06); the explanations are the record.

- **Sign facts, not the rows that change (rules 1 and 2).** A signature goes only on rows
  that are written once and never edited: an event, a message, a rating, a key row, a
  membership. The rows that keep changing — the order's current-status row and the stops'
  visit columns — carry no signature. A reader who wants to know whether the current
  status is honest looks at the latest *signed* event and compares; a reader who wants to
  know whether the route is intact compares the stored stops with the digest in the
  latest signed event. *Why:* CloudKit, through `sqlite-data`, merges a row column by
  column — when a phone and an iPad update different columns of the same row, both
  changes survive and the row that results was written by nobody in full. A signature
  over that whole row fails although nobody cheated, and the parked PR's answer,
  re-signing everything on every merge, is exactly what turned a forged row into a
  "verified" one. *What is given up:* a forged edit of the status row is not caught by a
  signature on that row; it is caught by the mismatch with the signed history, which is
  where the truth already lives — the same protection, one step indirect. *Rejected:*
  signing mutable rows with re-signing on merge (the parked design); per-column
  signatures (sixteen signatures per row, and the mirror is still a cache).
- **A key per device, nothing synchronised (rule 4).** Each phone and Mac has its own
  signing key, generated on the device, never copied anywhere; the owner's three devices
  are three keys of one party, all trusted, and a reader sees "the owner" for each.
  *Why:* a single owner key kept in the iCloud Keychain splits when two devices create it
  offline, and then they fight forever (the parked PR's red finding); a Secure Enclave key
  cannot be copied by design, so "one key everywhere" is not even available once the key
  lives in hardware. *What is given up:* nothing a user sees — a new device signs under a
  new key from its first write, and old history stays valid under the old keys.
- **No "first key wins" pinning (rule 4).** A reader does not remember the first key it
  saw for an order and warn when another appears; it trusts a key because the authority
  stamped the key row with the account that created it — CloudKit's server now, our
  server later. *Why:* pinning is the tool for a world without an authority. With one, a
  pin only adds false alarms (the owner's second phone reads as "key changed") and one
  real hole (whoever re-pins blesses the forgery). The stamp is unforgeable by anyone
  inside the share and is already cached on every device, so offline reads keep working.
  *What is given up:* protection against the authority itself lying. On CloudKit that is
  Apple; on the host that is us — and the device-side signature still makes our own
  tampering visible to anyone who holds the original rows.
- **The entitlement matrix (rule 7).** A written-down table of who may write which kind
  of row: the owner anything; members the chat, photos and ratings; a courier the events
  of its own leg. A row signed correctly by someone outside the matrix renders as
  "written by a participant who may not write this". *Why:* CloudKit grants write access
  per share, not per table, so a receiver *can* insert a "delivered" event; without the
  matrix that forgery would read as a perfectly valid signed row. On the host the same
  table is enforced at upload. *What is given up:* flexibility not yet needed — a new
  role is one row in the table and one case in the switch.
- **Parties, not emails, in rows (rule 8)** — <doc:Design> → "Parties, not CloudKit
  names" carries the explanation and the rejected alternatives.

#### Keys — what we sign with, custody, publication, trust

- **Algorithm: ECDSA, P-256, SHA-256** (CryptoKit `P256.Signing`; swift-crypto on
  Linux). Signatures are the 64-byte raw `r ‖ s` form, base64 in a TEXT column. Public
  keys are the 65-byte X9.63 uncompressed point, base64, so any verifier on any platform
  reconstructs them without a vendor format.
  `keyID = "p256.v2." ‖ hex(SHA-256(x963PublicKey)[0..<8])`: the algorithm and the
  payload version are legible from the column alone, and a future algorithm is a new
  prefix, not a migration.
- **Why not Ed25519.** The first draft chose it (the parked branch's choice). It verifies
  everywhere too, but it has no hardware custody on Apple devices. Deterministic
  signatures, Ed25519's one practical advantage, buy nothing here: a signature is
  verified, never compared (<doc:Design> → "P-256 in the Secure Enclave", with what the
  other platforms have).
- **Custody.** One keypair per device. Where `SecureEnclave.isAvailable`:
  `SecureEnclave.P256.Signing.PrivateKey(accessControl:)` with `.privateKeyUsage` and
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, no biometric gate (background sync
  signs), its `dataRepresentation` stored in a generic-password Keychain item in the App
  Group access group (it survives an app transfer — <doc:Design>). Elsewhere —
  simulator, test hosts, old hardware — a software `P256.Signing.PrivateKey` whose raw
  representation sits in the same item with `kSecAttrSynchronizable = false` stated
  explicitly. Get-or-create; a transient Keychain failure yields "no key for this write";
  the store caches only a resolved key and asks again next time. Previews and tests use
  an ephemeral in-memory key, so signing is never "off", only sometimes unpersisted.
- **Signing is always on** (owner's decision 9, 2026-10-06). Every build signs every fact
  row, including previews, tests and the simulator, which use an ephemeral key that lives
  only in memory. The point is the meaning of a missing signature: with signing always
  on, "unsigned" can only mean a write bypassed the Kit's path or a device could not reach
  its key, both worth a warning. With an opt-out flag, "unsigned" could also mean "this
  build chose not to", and every warning would be ambiguous forever. The cost is zero for
  users and one line for tests: a store built without an access group signs with an
  ephemeral key, whose rows read as "mine" on that device and "not yet verifiable"
  anywhere else — correct for fixtures that never sync.
- **Identity.** The device learns its own `partyRef` from the authority (CloudKit:
  `CKContainer.userRecordID()` once sync starts, derived as <doc:Schema> → "`partyRef`"
  says, cached in the device-tier `localIdentity` table). Until known, rows carry
  `authorRef = NULL` and the key row carries `partyRef = NULL`; the authority's stamp
  fills the gap for readers after the first sync.
- **Publication.** A `participantKeys` row per (order, device key), id derived from
  `orderID ‖ keyID`, inserted with `INSERT OR IGNORE` inside the first signed write of
  that device into that order. Self-signed over *every* column it carries — the public
  key and the binding fields alike (amended 2026-10-08, review of #135: a
  self-signature that skipped `bindingProof` and `bindingKeyID` would let a participant
  rewrite the evidence a row claims without touching its signature) — so a rewrite of
  `publicKey`, of the proof or of the key that attested it is detectable. The row names
  its binding: `bindingKind = "cloudkit"` (the proof is the server stamp in sync
  metadata; the proof columns are NULL and signed as NULL) or, later, `"server"` with
  `bindingProof` holding the server's signature over `(partyRef, keyID, publicKey,
  boundAt)`, `bindingKeyID` naming the server key that signed it, and `boundAt` the
  attestation's own time. A `server`-bound row whose proof is missing, or verifies under
  no pinned server key, is *invalid*, not *unverifiable*: the row claims evidence it does
  not carry.
- **Trust.** The identity authority answers one question per key row: *which party does
  your binding name?* CloudKit: the creator stamp resolves to a party (a real record
  name, or `__defaultOwner__` on a device whose own party is known); server: the
  attestation verifies under a pinned server key. The row's own `partyRef`, when present,
  must agree; a disagreement is *invalid*. A key row with no binding yet is
  *unverifiable* for everyone except the device that holds the private key, which
  recognises its own fingerprint.
- **Multiple keys per party.** Expected: each of the owner's phones has one. All are
  trusted independently. No "key changed" warning exists.
- **Rotation, loss, revocation.** A new device, or a device whose Keychain was reset,
  publishes a new key row at its next write. Old signatures stay valid under the old key
  row. Revocation is a later additive row kind (`revokedAt` signed by another trusted
  key of the same party, or attested by the server) and is not built now.
- **Privacy.** Party references are opaque; participants already see each other in the
  share. Names come from the authority at render time and are never stored in signed
  rows (`authorHint` on messages stays a display cache, written NULL by real posts as
  today — <doc:TechDebt> YD-43).

The flow, end to end: a device keypair in the Secure Enclave signs the bound values → an
append-only row (`authorRef`, `signingKeyID`, `signature`) and a self-signed
`participantKeys` row → the binding authority stamps both (CloudKit now, a server
attestation later) → the local evidence (`SyncMetadata`, or the attestation column) →
the identity authority adapter resolves the key row to a party → entitlement by role,
table and leg → an attested verdict beside the row → a `Notice` warning, never a refusal.

#### Verdicts and entitlement

```swift
public enum Verdict: Hashable, Sendable {
    /// The signature verifies under a key row whose binding names `author`,
    /// and `author` may write this row kind for this leg.
    case verified(author: Party)
    /// Written before signing existed for this order: NULL signature and no
    /// participantKeys row for the order. Quiet.
    case legacy
    /// NULL signature on an order that has key rows: a write that bypassed the
    /// signing path, or a device that could not reach its key. Warned.
    case unsigned
    /// A signature is present and does not verify, or `authorRef` disagrees
    /// with the key row's binding. Warned.
    case invalid
    /// The named key row is missing, or its binding names a different party
    /// than it claims. Warned.
    case untrustedKey
    /// The key row has no binding yet and is not this device's. Quiet,
    /// labelled "not yet verifiable".
    case unverifiable
    /// Correct signature by a trusted key whose party may not write this row
    /// kind (a participant's order event, a courier's event on another leg).
    case notEntitled(author: Party)
}

public struct Attested<Value>: Sendable where Value: Sendable {
    public var value: Value
    public var verdict: Verdict
}

public struct Party: Hashable, Sendable {
    public var ref: UUID?                  // partyRef; nil only for legacy/unsigned
    public var displayName: String?        // from the authority, when disclosed
    public var role: Role                  // owner · member(kind) · courier(legRef) · unknown
}

/// The seam that keeps CloudKit out of the rows. One implementation now.
public protocol IdentityAuthority: Sendable {
    var localParty: UUID? { get }
    func binding(of keyRow: ParticipantKeyRow) -> KeyBinding   // .party(UUID) · .mine · .none · .conflict
    func members(of orderID: UUID) -> [Member]                 // ref, role, permission, displayName?
}
```

| Row kind | Owner | Member (receiver, dispatcher, participant) | Courier assigned to leg L |
|---|---|---|---|
| `orderEvents` with `legRef` NULL (the order's platform leg, and `placed`) | entitled | notEntitled | notEntitled |
| `orderEvents` with `legRef` = L | entitled | notEntitled | entitled |
| `orderMessages`, `orderAttachments`, `orderRatings` | entitled | entitled | entitled |
| `memberships`, `legs` | entitled | notEntitled | notEntitled |
| `participantKeys` | only the party the binding names (self-publication) | only the party the binding names | only the party the binding names |

Role resolution: the owner is the party the authority names as the order's owner (the
share's owner in CloudKit mode; whoever the device is on a private order); a member is a
party whose *effective* membership row names a role other than `removed`, or, before
the owner's device has reconciled one, a party the authority lists as a participant; a
courier is a member whom the *effective* `legs` row for a leg names as
`courierPartyRef` (<doc:Schema> → "Stage 2": a leg is a logical identity its rows fold
by). Only membership
rows that themselves read *verified* as the owner's count for roles — a row anyone else
appends, a `removed` for the owner included, is *notEntitled*, rendered as such, and
changes nobody's verdict. The effective row is the latest by `addedAt`; on an exact tie
`removed` dominates, then the smallest id — deterministic, and named for what it is: a
tie between two live roles from two owner devices is settled by hash, like the
custom-field carrier conflict in <doc:Schema>, and the owner's next assignment settles
it for good. **Entitlement is judged as of the row**
(amended 2026-10-08, review of #135): the role that counts for a row is the party's
effective role at the row's own stamp — the latest membership row whose `addedAt` is not
after the row's `at`, `sentAt` or `createdAt` — so a message posted while a member stays
*verified* after the owner removes that member, and anything dated after the owner's
`removed` row reads *notEntitled*. A removed participant cannot upload in any case — the
engine's `permissionFailure` path takes server truth or deletes the local row — so the
rule governs what was written before the removal and whatever a stale share cache might
still let through. A row's stamp is its writer's claim, as every offline-first write is:
a writer whose role was reduced could date a row into its former role. The server's
modification date in the sync metadata bounds the claim — when it is later than the role
change, the row renders verified, entitled as of its stamp, and flagged "arrived after
the role changed", never hidden; on the host, where upload is the arbiter, the server
refuses it instead. `participantKeys` carries no role: roles come from `memberships` and
`legs`, never from a writer's claim.

**Derived verdicts for projections.** `mirrorIntegrity(orderID:)` compares
`orderProviderStates.providerStatus` with the `providerStatus` of the latest *verified*
status-bearing event and yields `.consistent` / `.disagrees(expected:)` /
`.noSignedHistory`; `routeIntegrity(orderID:)` hashes the stored stops' sender-authored
columns (below) and compares with the `routeDigest` on the latest verified
digest-bearing event. "Latest" is one total order, the same for both, over the rows that
read *verified* — a forged row fails verification, and a member's row fails entitlement,
before either can compete, so a forged `providerRevision` competes with nothing. The
order is one lexicographic key over every candidate: by `at`, the provider's own clock on
journal rows and sightings alike; on a tie, by family — a journal row beats a claim read
(a card or a search row, which carry the same claim `revision`) beats the app's own
`placed` (among digest-bearing rows the journal never competes: it carries no route);
then, within one family, the higher `providerRevision`; a residual tie is settled by the
smallest id. Each component is
totally ordered and compared only after the ones before it are equal, so the order is
transitive and every device picks the same winner.

How it got here. The second round (2026-10-08) replaced "the mirror is consistent if it
matches any equally stamped status" — a set a read-write participant could roll the
mirror back into — with a total order, and put `revision` first where both rows carried
one, falling back to `at` otherwise. The third round showed that rule is not transitive:
a row with revision 1 at `at` 300, a row with revision 2 at 100 and an unversioned row at
200 beat one another in a cycle, and a sort over them has no stable winner. The key is
now timestamp-first for a reason that does not depend on the open question about
`revision`: it is the order the projection's own writer uses. `recordOrder` skips a card
only when the stored observation is strictly newer, and the mirror update after an event
applies when the stored stamp is not later — so within one sync pass, where the mirror is
stamped with the batch's latest provider stamp, an event at that stamp lands after the
card's write, which is the journal-beats-claim-read tie rule. A verdict that ordered
differently would read an honest write as tampering. `revision` compares rows of one family only, where it
is one counter; if the open verification shows the journal's and the card's revisions
are one counter, the writer's gate and the verdict move to revision-first together, never
one without the other. Nor is the order CloudKit's server timestamp, the natural
"server time" of a hosted database: `modificationDate` in the sync metadata records when
a device uploaded, and a device that was offline for an hour would make an old provider
fact look newest — <doc:Design>'s rule that provider time is the freshness clock. The
server stamp is the right bound on a writer's own claimed time (role resolution, above),
not the order of the provider's facts.

Exactly one event is the expected value; a projection that matches any other reads
*disagrees*, so a forged rollback cannot pass as consistent. Two residuals, both false
positives on honest data — the safe direction — and both named because the provider
documents `updated_ts` only as "last update" and the package records no guarantee that
two reads at one stamp agree. An exact tie of `at` between rows that disagree: the mirror
keeps the last arrival, which can differ per device, while the verdict keeps the order's
winner, so one device may show the disagreement line and another not, with nothing in the
signed trail to tell them apart. And a sync pass stamps the mirror with the latest
provider stamp among its events and cards, which can run ahead of the content it holds
only if a card and an event disagree about the clock — the one-counter question again. Both verdicts read the trail deduped by fact (rule 1). Neither
touches the projection tables' write paths (<doc:Schema> → "Derived integrity").

#### The canonical payload

The parked branch's encoding stays; its source changes. Both the writer and the verifier
call one function over an array of `DatabaseValue`: the writer builds them through
`AppDatabase.args` (which already lowercases UUIDs to TEXT and binds dates as REAL epoch
seconds) and binds the same array; the verifier maps `row[column]` to `DatabaseValue`.
Same bytes by construction — and the same bytes a Postgres-backed verifier produces from
the same typed columns. The branch re-read stored bytes after the write, which is what
let a replayed `INSERT OR IGNORE` sign a forged stored row (Devin's security finding 3 on
Kit #36).

```
payload = "YDX2" ‖ table ‖ 0x00 ‖ ( column ‖ 0x00 ‖ tag ‖ value )*  for column in signedColumns[table]
tags:  0 NULL · 1 TEXT (u32 big-endian length, UTF-8) · 2 INTEGER (i64 big-endian)
       3 REAL (IEEE-754 bit pattern, big-endian) · 4 BLOB (u32 length, bytes)
signature    = ECDSA-P256-SHA256(payload), 64-byte raw r‖s, base64
signingKeyID = "p256.v2." ‖ hex(SHA-256(x963PublicKey)[0..<8])      // v2 = the YDX2 column lists below
```

| Table | Signed columns, in this order (frozen for v2) |
|---|---|
| `participantKeys` | id, orderID, partyRef, keyID, publicKey, bindingKind, bindingProof, bindingKeyID, boundAt, addedAt |
| `memberships` | id, orderID, partyRef, role, addedAt, authorRef |
| `orderEvents` | id, orderID, legRef, providerEventID, providerRevision, at, kind, providerStatus, detail, source, routeDigest, authorRef |
| `orderMessages` | id, orderID, sentAt, kind, text, attachmentRef, authorRef (not `authorHint`: a display cache) |
| `orderAttachments` | id, orderID, kind, caption, byteSize, createdAt, dataHash, authorRef |
| `orderRatings` | id, orderID, legRef, authorRef, subjectKind, subjectRef, subjectLabel, score, comment, at |
| `legs` (later) | id, ref, orderID, position, kind, providerAccountRef, courierPartyRef, fromStopRef, toStopRef, assignedAt, authorRef |

Adding a column to a signed table is a new payload version (`YDX3`, `p256.v3.`); rows
keep verifying under the version their key id names. `dataHash` is
`hex(SHA-256(attachmentBlobs.data))`, so a blob swapped under the same attachment id
fails the attachment's verdict (the blob itself is a `CKAsset` and is not signed —
<doc:TechDebt> YD-42).

**`routeDigest`** = `hex(SHA-256(payload))` where the payload encodes, per stop in
`position` order, the sender-authored columns: position, role, latitude, longitude,
address, building, entrance, floor, apartment, intercom, contactName,
contactGivenName, contactFamilyName, contactPhone, contactPhoneExtension. Visit columns
are provider truth and excluded; stop ids are identity, not content, and excluded. It is
carried by two event kinds: `placed` (a Stage 1 kind — today's code emits journal rows
and sightings only — written by the ordering flow with `source = "app"` when the claim
is accepted; `detail` is JSON with claimID, tariff, price, currency as agreed) and every `sighting` (the route as the provider reported it, so a point the API
"invents" is simply the newer verified fact, per the package's *WorkingWithYandex*). A
sighting's identity carries its revision and its digest — `orderID ‖ providerRevision ‖
providerStatus ‖ routeDigest ‖ the writer's key id` (amended 2026-10-08, reviews of
#135): the Kit's
`recordOrder` rewrites the stops from any card that is not older, status unchanged or
not, so under the earlier identity `orderID ‖ status ‖ source` a corrected address would
have refreshed the stops while the second sighting was dropped, and the route would
have disagreed with a stale digest for a change nobody made. Now a changed route is a
new signed sighting, an identical re-sight stays a no-op, and the stops always have a
signed digest to answer to. The revision joined the identity in the third round: a
claim can return to an earlier status — Yandex documents the loop where a claim edited at
`ready_for_approval` goes back to `estimating` — and with the same route a later
revision's sighting collided with the first one's and vanished, so an older journal
status could win the order while the mirror showed the newer card. The wire requires
`revision` on every claim card, search row and journal event, so after the epoch every
provider row carries it; a retry of one revision keeps one id, and a new revision is a
new fact even when nothing else changed. `source` left the identity in the same pass: a
card read and a search read return the same claim response, so one revision seen both
ways is one observation, and the first read to see it writes the row. Only the app's
`placed` has no revision — the accept response carries `version`, not `revision` — and
`placed` is its own family, ranked last, keyed by its writer. The journal never carries a route — its change types are
`status_changed` and `price_changed`, as <doc:Design> → "Claims sync" already records
("its events carry no coordinates or routes"), and the package records no signal for a
corrected route — so a route reaches the store only through a card or a search read,
which is why the sighting, not the journal row, carries the digest.

#### What this does not do

- It does not stop a read-write participant from writing anything; it makes every write
  attributable and every forged provider row visible as such. On a host, the server
  additionally refuses such writes at upload.
- It does not authenticate couriers without an iCloud account while CloudKit is the
  backend.
- It does not protect against the device's own compromise (a stolen unlocked phone signs
  as its owner; the Secure Enclave keeps the key from being copied, not from being used).
- It does not give a courier a portable reputation by itself (<doc:Vision> → "Players,
  trust and reputation").
- It does not sign the private tier or the drafts.

#### Read-side lessons from the review of #92

The 2026-10-04 round, four findings, answered in place and carried here rather than
coded — the draft is parked; they stand under this design, and the app's adoption
implements them. Attribution is a property of the *share*: a private order has one
writer, so the controller's lookup returns no names for it (`orderIsShared` is the seam)
and no screen can show what another hides — the draft gated the detail and not the
trail. A lazily fetched name publishes under the same lineage guard as the row it
decorates — the trail's `generation`/`expandedID` check (`main` since #109) and the
detail model's `generation` — where the draft's `loadAuthorship` assigned after its
await unguarded. The detail destination is id-keyed and resolves the live row from
`store.orders` (since #32), so a verdict follows the row; the lookup beside it must be
keyed too (`.task(id:)` on the row's stamp), not fired once on appear.

#### Sequencing

The owner read the design as the review and recorded the decisions on 2026-10-06;
<doc:Roadmap> → "Next — the trust layer" carries the phases. The doctrine lands as a
documentation PR before any Kit code; then the schema epoch (a Kit minor, then an app
PR); then the Kit's trust layer in three small patches — signing primitives and key
custody, then `participantKeys` and `memberships` with the identity authority, then
signed facts and derived integrity — each tagged and reviewed on its own; the ratings
table; the app's adoption, gated on the two-device pass the earlier draft lacked (two
devices, two accounts: a participant's rewritten order event shows as written by a
participant, with the name the share discloses, and a tampered stored event shows
"signature does not match"); the rating UX; legs later. The two parked PRs are the
quarry, not the plan — closed, not rebased: the branch is 54 commits behind and the
design it implements is replaced in four load-bearing places; the branches stay until
the primitives have been salvaged.

## Ready for an independent host (2026-10-06)

The owner will ship on iCloud and later move to a host of their own, leaning to
server-side Swift. The design goal is that the move is a migration of *transport and
authority*, never of the rows. What below is already true after the epoch's Stage 1, and
what the server adds; the product's statement of it is the backend question's fourth
stage in <doc:Vision>.

**The identity layer on the server (new there, not here).**

```
parties     (id UUID PK, createdAt)
identities  (provider TEXT, subject TEXT, partyRef UUID → parties, verifiedAt, PRIMARY KEY (provider, subject))
            -- ("cloudkit", userRecordName) rows carry the UUID the devices already derived,
            -- so every authorRef/subjectRef/memberships.partyRef written on iCloud stays valid.
            -- ("apple", sub) · ("google", sub) · ("email", address) · ("phone", e164) are added by sign-in.
deviceKeys  (keyID TEXT PK, partyRef, publicKey, boundAt, attestation)   -- the server's own copy of participantKeys bindings
memberships (orderID, partyRef, role, permission, addedAt)              -- imported from the devices' signed rows
```

Email is an *identity* row and the login handle, not the party id: it changes, people
hold several, Sign in with Apple may hand a relay address, and a primary key that is PII
would leak into every shared and public row (<doc:Design> → "Parties, not CloudKit
names"). Display names come from the party's profile, resolved at render as the share's
identities are today.

**Sign in with Apple.** Not needed while CloudKit is the backend; CloudKit's identity is
the iCloud account and the share is the grant. On the host, the first sign-in method can
be any of the four; the day Google (or any third-party) sign-in is offered, Sign in with
Apple is mandatory (App Review 4.8). The earlier answer — "CloudKit already gives us the
identity" — was right for now and silent about later; the structure that makes "later"
cheap is `partyRef` plus the authority adapter, nothing else.

**Two tiers or three.** Two-tier — clients against a hosted Postgres with row-level
security — is viable with signed append-only facts: the database can enforce membership
and reject malformed rows, and signatures travel unchanged. What it cannot do is attest
key bindings, run invites and push, verify signatures in a trigger without extensions, or
moderate a registry. Those are application logic, so the honest target is three-tier:
Postgres, a Swift application server, the iOS app and later a web client. Vapor is the
mature choice; Hummingbird is the lighter one. Kitura is not a candidate: IBM stepped
back in 2020 and the community fork has had little activity since. The schema ports to
Postgres with the `*Ref` value columns promoted to real foreign keys where the one-FK
rule no longer binds.

**What migrates, device by device.**

1. The person signs in to the host (any identity). The device also presents its
   CloudKit-derived `partyRef` and user record name from `localIdentity`; the server
   records the `cloudkit` identity under the same party, so nothing the device wrote on
   iCloud changes author.
2. The device registers its key: the server attests `(partyRef, keyID, publicKey,
   boundAt)` under its own P-256 key; the device rewrites nothing, it appends — future
   `participantKeys` rows carry `bindingKind = "server"` with the proof. Old
   `cloudkit`-bound rows are accepted by the server on the uploading owner's word, marked
   as such, and stay verifiable by signature.
3. The device uploads its shared-tier rows (orders it owns, rows of shares it is in), its
   private tier, and its `memberships` rows; the server dedupes by UUID and verifies every
   signature it can, refusing none of the legacy ones but labelling them. Membership for
   orders whose owner has not migrated yet is reconstructed when the owner does.
4. Sync switches to the host. CloudKit stays readable for a grace period, then is turned
   off. The widget snapshot, the wire log, the drafts: untouched.

**Signing as the second layer on a protected database, priced.** The owner asked whether
row signing stays once a server stands between the parties, and what it costs. It stays.

| What it costs | What it buys on a host |
|---|---|
| Compute: ECDSA P-256 sign and verify are each on the order of 0.1 ms on a phone; a Secure Enclave sign is a few ms. A busy order has tens of rows. | Tamper evidence against the operator, a compromised server, a migration bug, a mistaken moderator edit: history that was signed on a device cannot be rewritten by anyone else without showing. |
| Storage: 64 bytes of signature plus about 24 of key id per row; 65 bytes per public key row. | Non-repudiation: a courier's "delivered" and a receiver's rating are provably theirs, which is what a dispute between strangers needs. |
| Discipline: frozen column lists per payload version; a canonical encoding shared by Swift on device and on server; key lifecycle (new device, lost device, revocation later). | Offline-first stays honest: rows signed offline are verified at upload, and the server can refuse rather than merely flag. |
| UI: verdicts rendered somewhere (already designed). | Portability of trust: a row's evidence travels with the row; a registry (<doc:Vision>) needs no second mechanism. |

Verdict: keep it. The costs are paid once, now, while the app has no users to migrate;
the benefits only grow when a server stands between the parties. The server verifies
CryptoKit's signatures unchanged: swift-crypto's
`P256.Signing.PublicKey.isValidSignature(_:for:)` hashes with SHA-256 through
BoringSSL, `ECDSASignature.rawRepresentation` is the same 64-byte `r ‖ s`, public keys
accept the same `x963Representation`, and nothing Secure-Enclave-specific leaks into the
signature bytes (swift-crypto `Sources/Crypto/Signatures/ECDSA.swift` L52–57, L81–104,
L182–203; `NISTCurvesKeys_boring.swift` L394–440; DeepWiki index `04119961`,
2025-04-17 — old, but these formats are stable —
[the swift-crypto conversation](https://deepwiki.com/search/on-linux-a-vapor-server-does-s_71737751-7e59-4088-9b34-10fa0afba80f?mode=deep)).

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

From the trust design (2026-10-06), each with the check that settles it:

- **Which record name the stamp carries for the current user's own records** —
  `__defaultOwner__`, i.e. `CKCurrentUserDefaultName`, versus the real user record name —
  on the owner's device in the private database and on a participant's device in the
  shared database. The design handles both; the two-device pass records the observed
  values.
- **Whether a production CloudKit schema can shed record types or fields.** The design
  assumes it cannot (additive only), which is why the epoch is a new container; if the
  console does allow it, the epoch still holds and only the container identifier stays.
  Owner to check in CloudKit Console.
- **Whether `sqlite-data` refreshes the root's cached `CKShare` when a participant
  accepts**, which the membership reconcile depends on. A prospective DeepWiki ask with
  the Kit's key-and-membership PR, and the two-device pass.
- **Whether the engine's `.test` dependency context lets a unit test place a `CKRecord`
  with system fields into `SyncMetadata`.** If not, party resolution is factored into a
  pure function and tested there; the device pass covers the rest.
- **Whether a second iCloud account exists for the device pass** — the share-acceptance
  item above needs it too.
- **Whether a journal event's `revision` and the claim card's `revision` are one
  counter.** Until it is settled, the derived verdicts compare revisions only between
  rows of one family (journal rows with journal rows, card and search rows together); if it is one counter, the mirror's freshness gate and the verdicts
  can move to revision-first together. The package's live capture matched once (the
  terminal event's revision equalled the claim's), and nothing documents it — nor whether the card's `version` is a second counter or an alias of
  `revision`. A journal page and the same claim's card, compared, settle both.

## See Also

- <doc:Schema> — the relational design this research produced
- <doc:Spike> — the preserved compile spike behind the verified claims
- <doc:Design> — the reopened persistence decision this research feeds
- <doc:Roadmap> — the spike this research endorses
- <doc:Vision> — where collaboration sits in the capability map
