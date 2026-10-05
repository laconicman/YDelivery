# Roadmap

Priority order. Rationale lives in <doc:Design>; the capability map with API dependencies is
<doc:Vision>; what is wrong today is <doc:TechDebt>. Since 2026-08-30 the phasing follows
the 2026-08 design session's build order (its transient handoff folded in here and into
<doc:Design> on 2026-09-06) — each phase ends somewhere shippable.

## Done

The shell and composition root (tabs, injected controllers, Keychain auth as rendered
state — PR #1) and route picking (search / tap-to-pin / editable resolved address — PR #2).
Every view carries a running `#Preview`.

**Design Phase 1 — structure (PRs #6–#10, 2026-08-30):** two tabs and the modal draft
flow whose draft survives dismissal (`RootView` owns it, above the sheet); the project
generated from `project.yml` (YD-4); `YDeliveryKit` with the <doc:DesignSystem> color set
and `StatusChip`; the provisional order store — one substrate for recents, saved places
and repeat — born in the App Group so a widget target could read it the day it exists
(its *stack* still awaits the Phase-2 research below); `textContentType` on the one field
missing it; SFSafeSymbols across the app (YD-3). Nothing looks new, by design.

**Design Phase 2 — the draft screen (PRs #17–#22, 2026-09-06):** the whole ordering loop,
in six stacked slices. The fixed card (map above, `2c` badges, collapsed contacts, swap,
reorder, a real return-point flow); the two-stage picker (saved chips → done with the
contact aboard, recents that show the person, confirm-pin with typed address parts, the
<doc:LinkGrammars> paste affordance behind the system `PasteButton`, considerate
When-In-Use location with the Settings start-city fallback); the estimate bar
(information, never the CTA, failure at held height); the tariff strip with its four
honest states and the vertical `3a` explainer, priced by `offers/calculate` through the
controller boundary; parcel and options with every §4 interdependency enforced and
renormalized in the UI; and the review sheet — bounds stated as sentences when ordering
is blocked, one owned create → watch → accept run behind a per-draft idempotency token,
the placed order recorded to the store and acknowledged with the searching-green check.
The wire's silent traps are pinned by tests: lon,lat; centimetres to metres; POSIX money;
the phone extension in its own field; person names as stored components, because
Foundation's parser refuses «Иван Петров» (<doc:Design>). Three review rounds hardened
pricing staleness into vocabulary — `chosenTariff`, `effective()`, `pricedRequest` — and
gave acceptance an `unresolved` state with a read-only way back. 157 tests in 15 suites.
*The phase's done-when held:* a real order with no address typed twice, every bounded
field stating its bound.

**Archive a finished order (2026-10-05):** `archivedAt` on `orderPrivateStates`
(Kit 0.4.14), the seed carries it, participants unaffected — shelved deliveries
hide behind the «Archived» filter (<doc:Design> → "History is kept, not deleted").

## Now — design Phase 3: while closed (boards `5a`–`5d`, `4b`)

- **Journal sync — landed (hybrid):** `journal` and `search` shipped in
  `YandexDeliveryExpressAPI` 0.3.0 after live-wire verification. The app consumes the
  pair as one engine (<doc:Design> → "Claims sync"): search reconciles membership —
  `active`/`delayed` every pass, `finished` once ever — while the journal keeps known
  claims fresh on a 30-second poll, cursor persisted per account. The feed carries
  **no coordinates** (verified 2026-08-30, <doc:Vision>): status/price events plus
  `current_point_id`, exactly enough for stop-granularity progress. What it already
  discharged: the full status vocabulary (YD-7), history rows that move, discovered
  claims becoming cancellable rows, and the unresolved-acceptance window (YD-5 — a
  claim the flow lost track of is found by search on the next pass; the remaining
  sliver is persisting the pending id for an *immediate* reconcile, now easy).
- **The `3e` history card — landed:** rows draw the whole route via `RouteLine`
  (handoff §6's last unbuilt component, `YDeliveryKit` 0.1.2), and the swipe pair
  «Повторить»/«Наоборот» opens a pre-filled draft — route and contacts ride back,
  the class is what the strip re-offers. The saved-place editor rides the chips'
  context menu: rename/retype reuse the naming sheet, delete asks once and forgets.
  Items, options and schedule never reached `Order`, so the repeat prices and packs
  fresh — that gap is YD-15's neighbor, not this card's scope.
- Custom fields: settings schema, two flags, own draft section, Spotlight indexing.
- Live Activity (seven states, failures never auto-dismiss), started locally on order
  creation, updated by polling — the push relay stays a Later item.
- Two widgets (waiting · working), three App Intents, notification thread rules —
  landed (PRs #43–44). Parcel-photo attachments stay open.
- **Share-in / share-out — landed:** the share extension (board `5d`) turns a chat
  address or a Maps place into a parked draft through `shared-draft.json` — a
  one-shot App Group slot, claimed by rename on consume, with the extension never
  opening the database. Its «Откуда» row reads `saved-places.json`, published
  after each healthy places read. Outbound, the order detail's ShareLink hands
  the recipient-facing *text* — status, order №, destination and contact, the
  ETA under the callout's own rule — not an app link.
- **The `4a` map callout — landed:** both maps open the one card — the draft's
  carries the door chips, the contact, and «Изменить точку»/«Сохранить как место»
  (both reusing the flows they name); the live order's carries the courier's
  per-stop account (`visit_status`/`visited_at` mirrored onto `routeStops` in
  `YDeliveryKit` 0.3.3) plus the provider's as-of stamp. Pin, card and route row
  share one selection — the row tap is the VoiceOver path to the same content,
  so the map is never the only route to anything. Per-point comments and the
  parcel line defer: the app collects neither (`address.comment` stays on the
  wire unread, `orderItems` has no writer).
- Local notifications + `BGAppRefreshTask` from journal events; a `BGProcessingTask`
  full replay gated on unmetered Wi-Fi + charger; CloudKit silent notifications as a
  cross-device wake-up once the shared-zone research lands — a trigger for our own
  reconcile, not provider push (Yandex's webhooks cannot reach CloudKit, <doc:Design>).
- When the package ships `tariffs`: swap the strip's and explainer's static bounds for
  live per-geo `supported_requirements`.
- Tariff cards tell when, not only how much — the provider's pickup/delivery windows on
  every card, Fastest/Cheapest sort, and a re-price when the ten-minute `offer_ttl`
  lapses (same-class offers differ only by their windows: YD-32).
- Deliveries toolbar: sort (newest / oldest / price) and show (all / needs a decision /
  delivered / cancelled) as one Menu — the archive filter follows the Kit column
  (Design → History is kept, not deleted).

*Done when:* a sender learns their courier arrived without opening the app.

**Review pass, 2026-09-29 (screenshots over a seeded store — `--uitest-history`, PR #61):**
the done-when holds *in code* — advanced-status banners, the Live Activity, and a
`BGAppRefreshTask` chain that is best-effort and system-scheduled, so "learns without
opening the app" means *notified when iOS grants the wake*, never *live*; the device pass
that shows a real banner on a real lock screen is still owed with the rest of the open
verifications. What the walk found is filed, not folded in here — the
Deliveries list's next shape ([#62](https://github.com/laconicman/YDelivery/issues/62):
collapsed rows, an expandable timeline over the provider trail that `providerEvents`
already stores and nothing yet reads, sections so the activity sort stops looking
broken); a `staleDate` on the Live Activity so a card the poll stopped feeding says so
([#63](https://github.com/laconicman/YDelivery/issues/63)); a recipient-facing surface
for a failed share acceptance ([#64](https://github.com/laconicman/YDelivery/issues/64));
YD-13's re-key on the learned `corp_client_id`, now that the schema it waited for has
landed ([#65](https://github.com/laconicman/YDelivery/issues/65)); and the standing
question of live observation versus the chat model's epoch counters
([#67](https://github.com/laconicman/YDelivery/issues/67)) — a <doc:Design> entry either
way. Two Kit patches fell out of the walk itself: `RouteLine` rows swallowed taps in the
history list (0.4.1) and `AppDatabase` reported a missing directory as an unreadable
store (0.4.2). The list redesign is the recommended next slice; the author's three
calls are in the issue.

### In parallel: the persistence and sharing research

**Research landed 2026-09-24 — spike endorsed, implementation still gated on the spike's
checklist** (<doc:Collaboration>). The sharing model is settled before the stack: private
`CKShare` hierarchies rooted at an order — invite-URL, per-participant read/write, no
public records — because collaborators need not share an org or a credential. The
grant and the provider token are independent axes: participant writes reach only an
append-only stream (per-order chat, attachments), provider-mirrored rows stay
owner-written projections, and every shared surface shows the timestamp of the state
it presents.
Share URLs open the app or an **App Clip** for pure consumers. Schema first (relational
discipline — Codd, not vibes; the LearnWords sessions record how a rushed CloudKit schema
went), provider-plurality in the schema from day one; the container stays **exclusive to
this app** with an account transfer assumed possible (<doc:Design> → "Surviving an
account transfer").

Stack direction, recorded 2026-09-24 and **spike-verified 2026-09-25**: `sqlite-data`
1.12.0 — the only candidate covering private sync *and* the `CKShare` surface in one
stack while keeping value-type models and an explicit SQL schema; the compile spike
verified `@Table`, `SyncEngine(tables:privateTables:)`, `share`/`unshare`/`acceptShare`,
and `CloudSharingView` (results in <doc:Collaboration> → "What the upstream pass
verified"). `NSPersistentCloudKitContainer` is the fallback, raw `CKSyncEngine` the
control-maximizing third. SwiftData stays the standing preference the day it gains a
sharing surface — re-check each WWDC (still private-only, verified 2026-09-23).

**Schema landed 2026-09-25 — <doc:Schema> is the contract the migration implements**:
`Order` as the share root, single-FK children below it, `*Ref` value references where
the one-FK rule forbids a second constraint, and the provider mirror / event feed /
collaborative tables carrying the authority split in the schema itself. **The share
door landed 2026-09-25** — `shareOrder`/`unshareOrder`/`orderIsShared`/`acceptShare`
on `AppDatabase` (YDeliveryKit 0.3.14), the order-detail affordance, `CloudSharingView`,
and the scene-delegate acceptance path — with one contract fix found wiring it: every
`Date` column declares `UnixEpochSecondsRepresentation`, or the engine decodes rows as
missing and they silently never sync (<doc:Schema> → Freshness). **The chat door
followed** (0.3.15): `postMessage`/`postPhotoMessage`/`messages`/`attachmentData`,
the order detail's Chat row, and `OrderChatView` — text, photos, and
`receptionConfirmed` riding one append-only stream, with the contract's
`MAX`/`COALESCE` list ordering now real in `readOrders`. What remains is
device work, not design — the live verifications (share acceptance end-to-end, the
corp-visibility wire test) stand open in <doc:Collaboration>.

- Diagnostics: one shareable file — events beside wire exchanges, a launch header
  record (Design → The rest of the app is not in the file).

## Landed — the sender's library (author's idea, weighed 2026-09-29; shipped 2026-10-02)

Shipped per option (b): Kit 0.4.7 carries `parcelTemplates`/`parcelTemplateItems` and
`pinned` on both lists; the draft's chips, «Save as a template» and place pin/unpin
landed in #93; the Library tab in #94. The one upgrade made while building: the table
became a **root+child pair** (`parcelTemplateItems.position` from day one) so a future
bundle is a UI widening, not a migration fork — `items.count == 1` is a UI convention,
not a schema invariant. The Library's place editor and the row doors followed in
(#TBD) — rows open their editors on tap, and a place is re-described whole except
its point. The weighing below stays as the design's record.

An entrepreneur sends the same goods to the same doors. Today the app remembers **places**
(`SavedPlace`, private tier — synced to the owner's devices, never shared; chips in the
picker, a naming sheet, `saved-places.json` for the share extension) and remembers
**nothing about parcels**: `ParcelItem` exists only as a row *on* an order or a draft, so
every run re-types the parcel form. The idea: two reusable lists — places and parcels —
with a pin, and in the long run tags and a favourite mark.

What the schema already says (<doc:Schema>, DeepWiki pass on the refreshed index):

- **Parcels need one new table**, `ParcelTemplate`, in the **private tier** beside
  `SavedPlace` and `CustomFieldDefinition` — the sender's vocabulary syncs across their
  devices and never rides inside a per-order share; the *instance* on an order stays the
  shared `OrderItem`. Same split custom fields already use (schema private, values shared).
- **Pin is a column**, `pinned`, on both lists — `OrderPrivateState.pinned` is the
  precedent; pinned entries lead the pickers.
- **Shared tags do not fit the private tier.** A tag vocabulary a *team* shares needs a
  share root above the order — the `Workspace` re-rooting Schema lists as deferred. Tags
  therefore start private (the sender's own), and "shared" waits on the workspace
  question with everything else that needs it.
- **Favourite ≈ pin.** One flag, not two, until someone can say what a favourite does
  that a pinned entry does not.

**The tab question — author's call.** <doc:Design> retired the third tab because «New
Delivery» is a verb; the library is a noun, so a tab does not contradict that decision — but
two more tabs for two lists is a four-tab bar over a two-screen app.

- (a) **Two tabs**, Places and Parcels — most discoverable, heaviest bar.
- (b) **One «Library» tab**, segmented Places | Parcels — a noun screen the sender visits
  to *maintain* the nomenclature; the *use* path stays the pickers inside the draft.
- (c) **No tab** — pickers inside the draft (places already; parcels new), management
  under Settings.

Recommendation: **(b)**. The pickers are where the lists earn their keep on every order; a
single library tab is where they are curated, pinned and pruned. (a) if the lists grow
past what one segmented screen scans; (c) is what the app has today for places, and the
parcel form's re-typing is the evidence it is not enough.

**Slicing.** Kit: `ParcelTemplate` row + `SavedPlace.pinned`/`ParcelTemplate.pinned`
(private tier, additive DDL — patch). App: a parcel picker in the draft's parcel section
(chips like the places', pinned first, «Save as template» from a filled form), then the
Library tab. Search reaches both lists. Two evenings.

## Later — design Phase 4 and beyond

- Regular width: sidebar + detail, map inside detail, shortcut set, focus order — decide
  the multiple-drafts model (handoff §9.4) before building windows.
- **Tracking on the map**: moving courier marker via `performer-position` polling
  (foreground-only until a relay exists), per-point ETA (`points-eta`), call
  (`driver-voiceforwarding`), ShareLink (`tracking-links`). Package first, same rule.
- **Push relay** (Cloudflare Worker or edgepush; webhook `callback_url` must end `?`/`&`) —
  its own repo, evaluated with DeepWiki before adoption; unlocks background Live Activity
  updates.
- **Per-stop arrival windows on the order detail** — `expected_visit_interval` on
  the points answers when the courier reaches each door; display only, the field
  already rides the wire. (The tariff cards' windows themselves moved to Now.)
- Handoff codes, proof of delivery, edit/return, `delivery-methods` windows.
- A Mac target if the product earns one.
- **Extract the map components into a public SPM** once the destination design has shipped —
  point picker, pin taxonomy, link-paste geocoding. The demo repo becomes the second
  consumer (its own roadmap wants maps); before that, extraction is speculation.
- **Many providers, docked legs, independent couriers** (owner direction, 2026-10-05 —
  <doc:Vision>): a second provider as its own package behind the controller boundary;
  legs under one order with docks between them (`LegState` per leg, events per leg);
  the courier edition as a share participant granted a leg. Schema rules to respect
  meanwhile in <doc:Schema> → "Direction — legs and participants".
- **Signing for every writer** (<doc:Collaboration> → "Generalised 2026-10-05"):
  `participantKeys` as an append-only shared table, `signingKeyID`/`signature` on the
  mirror and the events, read-time verdicts that never refuse. Supersedes the owner-only
  draft (Kit #36 / #92, parked as the quarry).

### Deferred, deliberately (no stubs)

Scan-to-fill (board `6a`) — manual entry stays a complete path, so its absence carries no UI
debt. Inbound tracking — record-keeping only, and only if honest about not being live.

## See Also

- <doc:Vision>
- <doc:Design>
- <doc:TechDebt>
- <doc:Collaboration>
