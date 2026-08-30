# Vision

What this app is for, what the API makes possible, and which capabilities earn a place —
grounded in the Express API's actual method catalog (checked 2026-08-27) and in what the
established couriers' apps (Borzo/Dostavista, Yandex Go's own client) teach users to expect.

## The product in one paragraph

A person or a small business opens the app, puts two pins on a map (or picks a saved
address), sees priced offers with time windows, confirms, and then *watches the delivery
happen*: courier on the map, ETA per point, status timeline, a call button, a share-tracking
link. History is local and durable; statuses keep updating; repeating last week's warehouse
run is one tap. Nothing in that sentence requires the user to know what a "claim" is.

## Capability map

What the API offers, mapped to user-facing features. "In package" = present in
`YandexDeliveryExpressAPI` 0.2.0.

| Feature | API surface | In package | Phase |
|---|---|---|---|
| Priced offers before ordering | `offers/calculate`; `check-price`, `tariffs` | calculate ✅, rest ❌ | 1 |
| Order lifecycle (create → accept → cancel with price) | `claims/create` `info` `accept` `cancel-info` `cancel` | ✅ | 1 |
| **Local order history, statuses kept fresh** | `claims/search` (backfill), **`claims/journal`** (cursor feed — the sync primitive) | ❌ | 2 |
| **Courier on the map, ETA, share link** | `claims/performer-position`, `claims/points-eta`, `claims/tracking-links` | ❌ | 3 |
| — *Division of labour, checked 2026-08-30 against [the journal reference](https://yandex.ru/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsJournal):* the journal carries **no coordinates** — only status/price events plus `current_point_id`, which gives route progress at *stop* granularity for free (Live Activity dots, background refresh). The *moving* marker requires polling `performer-position`, foreground-only until a push relay exists. | | | |
| Call the courier | `driver-voiceforwarding` | ❌ | 3 |
| Handoff codes, proof of delivery | `claims/confirmation_code`, `proof-of-delivery/info` | ❌ | 4 |
| Edit before/after confirm; initiate return | `claims/edit`, `apply-changes/*`, `claims/return` | ❌ | 4 |
| Scheduled / same-day windows | `delivery-methods` + `due` intervals | partially (`due` ✅) | 4 |
| Multi-point business runs | `route_points[]` already supports N points | ✅ shapes | 4 |

App-side capabilities with no new API dependency:

- **Pick-on-map + address autocomplete** (`MKLocalSearchCompleter`, `CLGeocoder`) — the
  single biggest UX win over coordinate-typing forms; the API wants `coordinates` +
  `fullname`, and the map supplies both. Phase 1.
- **Saved addresses & contacts, repeat order, templates** — this *is* the
  "storehouse2p / p2storehouse" story: a warehouse is a saved source point plus
  `external_order_id` for reconciliation. Local persistence. Phase 2.
- **Local notifications on status change** — rides on journal polling +
  `BGAppRefreshTask`. Phase 2.
- **Live Activity / Dynamic Island** for the active delivery (status + ETA) — the signature
  delivery-app surface; local updates while polling runs. Phase 3.
- **Widgets** (active order status), **ShareLink** for tracking URLs. Phase 3–4.

## Sync and notifications: polling first, push later

`claims/journal` is a cursor-based change feed — poll it, apply events to the local store,
persist the cursor. That gives history, status freshness, and local notifications with
**zero infrastructure**, and it is required anyway as the source of truth for status
history. Remote push needs a relay that receives Yandex's webhook (its `callback_url` is
concatenated verbatim — the URL must end in `?` or `&`) and posts to APNs; a ~200-line
Cloudflare Worker or the open-source edgepush both fit, and CloudKit cannot play this role —
it has no inbound-webhook surface. Deliberately deferred: <doc:Roadmap> → Later.

## What this app will not do

- Mimic Yandex branding, name, or iconography — unofficial means visibly unofficial.
- Cover the separate next-day/warehouse (НДД) API family. Different contract, different
  package; out of scope until a real user needs it.
- Expose raw API vocabulary (claims, offers/calculate) in the UI. The demo exists for that.

## See Also

- <doc:Design>
- <doc:Roadmap>
- <doc:TechDebt>
