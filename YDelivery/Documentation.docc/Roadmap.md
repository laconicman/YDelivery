# Roadmap

Priority order. Rationale lives in <doc:Design>; the capability map with API dependencies is
<doc:Vision>; what is wrong today is <doc:TechDebt>.

## Now — Phase 1: a delivery can be ordered

### The shell and composition root

Tab structure (Deliveries · New Delivery · Settings), controllers created in `@main` and
injected, Keychain-backed auth state rendered rather than crashed on. Every view lands with
a running `#Preview`.

### New-delivery flow

Point picking shipped (PR #2). Remaining: parcel details, offer cards from
`offers/calculate`, then create → accept, with the cancel price (`cancel-info`) shown before
any cancel. The generated types stay behind the controllers (<doc:Design>).

### Route truth before price

A route preview once both ends exist: `MKDirections` polyline, distance, rough drive time —
the "am I pricing the right trip?" check the author's review called out. Slots between
picking and offers.

### The destination experience (design-gated)

`Design-Research-Brief.md` (repo root, transient) commissions the full treatment: the 2GIS
"Проезд"-style laconic tariff strip vs an explanatory beginner mode, pin taxonomy
(start/intermediate/end; warehouse/pickup-point/door-to-door), reorderable multi-point route
list, link-paste geocoding (Yandex/Google/2GIS URLs), recents resurfacing in search, saved
places. Reference screenshots live in `Documentation.docc/Resources/`. Implementation
follows the returned design, not the other way around.

### Start from the user's position

When-In-Use location with the considerate acquisition UX from `NetworkObserverSample`
(pre-permission explainer, denial as a rendered state); explicit region setting as the
fallback. Until then the Moscow fallback stands.

## Next — Phase 2: history that stays true

### First: the persistence and sharing research

**Do not brace into implementing** (author, 2026-08-28). Phase 2's store must carry the
CloudKit ambitions: private sync, and an organization sharing one Yandex token whose
employees see, create, and edit orders by role — which smells like sharing a whole record
zone, not a row. SwiftData's CloudKit sync has no sharing story; `NSPersistentCloudKitContainer`
does (<doc:Design> — the SwiftData decision is reopened). The research task: schema first
(relational discipline — Codd, not vibes; the LearnWords sessions on this machine record how
a rushed CloudKit schema went), stack second, with provider-plurality in the schema from day
one even while Yandex is the only provider.

### The order store and journal sync

The store (per the research above) as the single source of truth; `claims/journal` cursor
sync applying status events; `claims/search` backfill. **Package first:** `journal` and
`search` operations do not exist in `YandexDeliveryExpressAPI` 0.2.0 — spec + tests land
there, tagged, before the app feature starts.

### Local notifications and background refresh

Status-change notifications from journal events; `BGAppRefreshTask` so they arrive without
the app foregrounded. Saved addresses/contacts and repeat-order land here too — the
warehouse story is a saved source point plus `external_order_id`.

## Later — Phase 3+: the delivery you can watch

- **Tracking screen**: courier position, per-point ETA, status timeline, call
  (`driver-voiceforwarding`), ShareLink (`tracking-links`). Package first, same rule.
- **Live Activity / Dynamic Island** for the active delivery.
- **Push relay** (Cloudflare Worker or edgepush; webhook `callback_url` must end `?`/`&`) —
  its own repo, evaluated with DeepWiki before adoption.
- Handoff codes, proof of delivery, edit/return, `delivery-methods` windows, widgets.
- CI (build + tests on push), a Mac target if the product earns one.
- **Extract the map components into a public SPM** once the destination design settles —
  point picker, pin taxonomy, link-paste geocoding. The demo repo becomes its second
  consumer (its own roadmap wants maps), which is exactly the Rule-of-Three moment; before
  a second consumer exists, extraction is speculation.

## See Also

- <doc:Vision>
- <doc:Design>
- <doc:TechDebt>
