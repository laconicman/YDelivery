# Roadmap

Priority order. Rationale lives in <doc:Design>; the capability map with API dependencies is
<doc:Vision>; what is wrong today is <doc:TechDebt>.

## Now — Phase 1: a delivery can be ordered

### The shell and composition root

Tab structure (Deliveries · New Delivery · Settings), controllers created in `@main` and
injected, Keychain-backed auth state rendered rather than crashed on. Every view lands with
a running `#Preview`.

### New-delivery flow

Pick points on a map (`MKLocalSearchCompleter` autocomplete + pin drop + reverse geocoding),
parcel details, offer cards from `offers/calculate`, then create → accept, with the cancel
price (`cancel-info`) shown before any cancel. The generated types stay behind the
controllers (<doc:Design>).

## Next — Phase 2: history that stays true

### The order store and journal sync

SwiftData store as the single source of truth; `claims/journal` cursor sync applying status
events; `claims/search` backfill. **Package first:** `journal` and `search` operations do
not exist in `YandexDeliveryExpressAPI` 0.2.0 — spec + tests land there, tagged, before the
app feature starts.

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

## See Also

- <doc:Vision>
- <doc:Design>
- <doc:TechDebt>
