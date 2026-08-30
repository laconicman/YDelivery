# Roadmap

Priority order. Rationale lives in <doc:Design>; the capability map with API dependencies is
<doc:Vision>; what is wrong today is <doc:TechDebt>. Since 2026-08-30 the phasing follows
the design handoff's build order (`DESIGN-HANDOFF.md` §7, transient at the repo root) —
each phase ends somewhere shippable.

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

## Now — design Phase 2: the draft screen (boards `1b`, `2a`, `2c`, `3a`, `3d`)

- Fixed route card: map above, rows with `pointStart`/`pointEnd` badges per
  <doc:DesignSystem>, collapsed contact rows, swap, add point.
- Picker grows saved chips, recents-with-contacts, choose-on-map confirm-pin with address
  parts, and the paste affordance per <doc:LinkGrammars>.
- Estimate bar (information, never the CTA) with its failure state — `MKDirections`
  distance/time, replaced by provider figures when offers land.
- Tariff strip with waiting/failed states; vertical beginner explainer auto-opening until
  the first successful order.
- Parcel and options with constraint-as-hint and the §4 interdependencies enforced in the
  UI, never discovered via API errors.
- Review sheet before ordering — the one irreversible action acknowledges itself.
- Start from the user's position: When-In-Use with the considerate acquisition UX
  (`NetworkObserverSample` pattern); explicit start city in Settings as fallback.

*Done when:* a sender completes a real order without typing an address twice, and every
bounded field states its bound.

### In parallel: the persistence and sharing research

**Do not brace into implementing** (author, 2026-08-28). The store must carry the CloudKit
ambitions: private sync, and an organization sharing one Yandex token whose employees see,
create, and edit orders by role — plausibly a shared record zone. SwiftData's CloudKit sync
has no sharing story; `NSPersistentCloudKitContainer` does (<doc:Design> — reopened). Schema
first (relational discipline — Codd, not vibes; the LearnWords sessions record how a rushed
CloudKit schema went), stack second, provider-plurality in the schema from day one. One
more input since 2026-08-30: the container stays **exclusive to this app** and its design
assumes a possible account transfer (<doc:Design> → "Surviving an account transfer").

## Then — design Phase 3: while closed (boards `5a`–`5d`, `4b`)

- **Journal sync first, package first:** `journal` and `search` operations do not exist in
  `YandexDeliveryExpressAPI` 0.2.0 — spec + tests land there, tagged, before the app
  feature. The journal carries **no coordinates** (verified 2026-08-30, <doc:Vision>):
  status/price events plus `current_point_id`, which is exactly enough for stop-granularity
  progress on every closed-app surface.
- Custom fields: settings schema, two flags, own draft section, Spotlight indexing.
- Live Activity (seven states, failures never auto-dismiss), started locally on order
  creation, updated by polling — the push relay stays a Later item.
- Two widgets (waiting · working), three App Intents, notification thread rules with
  parcel-photo attachments, share-in extension.
- Local notifications + `BGAppRefreshTask` from journal events.

*Done when:* a sender learns their courier arrived without opening the app.

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
