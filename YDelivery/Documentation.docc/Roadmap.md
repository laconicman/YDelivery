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
- The `3e` history card with «Повторить»/«Наоборот» replaces the minimal list —
  `RouteLine`'s first consumer (handoff §6's last unbuilt component) — and the `3e`
  saved-place editor gives the bookmark's chips a management surface.
- Custom fields: settings schema, two flags, own draft section, Spotlight indexing.
- Live Activity (seven states, failures never auto-dismiss), started locally on order
  creation, updated by polling — the push relay stays a Later item.
- Two widgets (waiting · working), three App Intents, notification thread rules with
  parcel-photo attachments, share-in extension.
- Local notifications + `BGAppRefreshTask` from journal events; a `BGProcessingTask`
  full replay gated on unmetered Wi-Fi + charger; CloudKit silent notifications as a
  cross-device wake-up once the shared-zone research lands — a trigger for our own
  reconcile, not provider push (Yandex's webhooks cannot reach CloudKit, <doc:Design>).
- When the package ships `tariffs`: swap the strip's and explainer's static bounds for
  live per-geo `supported_requirements`.

*Done when:* a sender learns their courier arrived without opening the app.

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
collaborative tables carrying the authority split in the schema itself. What remains
gated is implementation, not design — the live-device verifications (share acceptance,
the corp-visibility wire test) stand open in <doc:Collaboration>.

## Later — design Phase 4 and beyond

- Regular width: sidebar + detail, map inside detail, shortcut set, focus order — decide
  the multiple-drafts model (handoff §9.4) before building windows.
- **Tracking on the map**: moving courier marker via `performer-position` polling
  (foreground-only until a relay exists), per-point ETA (`points-eta`), call
  (`driver-voiceforwarding`), ShareLink (`tracking-links`). Package first, same rule.
- **Push relay** (Cloudflare Worker or edgepush; webhook `callback_url` must end `?`/`&`) —
  its own repo, evaluated with DeepWiki before adoption; unlocks background Live Activity
  updates.
- Handoff codes, proof of delivery, edit/return, `delivery-methods` windows.
- CI (build + tests on push); a Mac target if the product earns one.
- **Extract the map components into a public SPM** once the destination design has shipped —
  point picker, pin taxonomy, link-paste geocoding. The demo repo becomes the second
  consumer (its own roadmap wants maps); before that, extraction is speculation.

### Deferred, deliberately (no stubs)

Scan-to-fill (board `6a`) — manual entry stays a complete path, so its absence carries no UI
debt. Inbound tracking — record-keeping only, and only if honest about not being live.

## See Also

- <doc:Vision>
- <doc:Design>
- <doc:TechDebt>
- <doc:Collaboration>
