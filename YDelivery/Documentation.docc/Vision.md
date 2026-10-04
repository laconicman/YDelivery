# Vision

What this app is for, what a provider integration makes possible, and which capabilities
earn a place — grounded in the first integration's actual method catalog (Yandex Delivery
Express, checked 2026-08-27) and in what the established couriers' apps
(Borzo/Dostavista, Yandex Go's own client) teach users to expect.

## The product in one paragraph

A person or a small business opens the app, puts two pins on a map (or picks a saved
address), sees priced offers with time windows, confirms, and then *watches the delivery
happen*: courier on the map, ETA per point, status timeline, a call button, a share-tracking
link. History is local and durable; statuses keep updating; repeating last week's warehouse
run is one tap. Nothing in that sentence requires the user to know what a "claim" is.

## Capability map

What the first integrated provider — Yandex Delivery's Express API — offers, mapped to
user-facing features. "In package" = present in `YandexDeliveryExpressAPI`. A second
integration earns its own column when it lands; the feature column must stay readable
without knowing which provider is behind it.

| Feature | API surface | In package | Phase |
|---|---|---|---|
| Priced offers before ordering | `offers/calculate`; `check-price`, `tariffs` | calculate ✅, rest ❌ | 1 |
| Order lifecycle (create → accept → cancel with price) | `claims/create` `info` `accept` `cancel-info` `cancel` | ✅ | 1 |
| **Local order history, statuses kept fresh** | `claims/search` (backfill), **`claims/journal`** (cursor feed — the sync primitive) | ✅ (0.3.0) | 2 |
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

- Mimic a provider's branding, name, or iconography — every integration is unofficial and
  visibly so.
- Cover Yandex's separate next-day/warehouse (НДД) API family, or a second provider.
  Different contract, different package; out of scope until a real user needs it.
- Expose raw API vocabulary (claims, offers/calculate) in the UI. The demo exists for that.

## Positioning — where the value actually sits (2026-09-29)

Written after the Phase-3 surfaces landed, from the review that walked them on a
seeded device. The capability map above says what the API *allows*; this section says
what the app *is worth*, to whom, and what it must never claim.

> **Repositioned 2026-10-02.** The product is a **general-purpose delivery app**, not a
> Yandex client. Providers are integrations behind one boundary — the first is Yandex
> Delivery Express, and the analysis below stays accurate for that integration's market.
> What changes: the app's identity is what it does for a sender (map ordering, durable
> history, the sender's library, shared tracking, signed records), not whose courier it
> dispatches. Listing copy should lead with delivery and name providers as integrations,
> not as the product.

### The gap the app fills

Yandex Delivery's Express API is a **B2B contract meant for backends**: a token lives in
the business cabinet's «Ваш профиль», addresses are accepted **only as coordinates**
(geocoding is the integrator's job), there is **no test environment** — integrations are
proven on real, paid orders, a test cabinet exists only by asking a personal manager —
and status reaches the client only by polling a cursor feed. *Provenance:* the first
three are quoted from Yandex's integration page
(`dostavka.yandex.ru/integrations/api/`) as excerpted by a search engine on 2026-09-29 —
the page itself would not serve a non-browser fetch, so they await a reader's
confirmation against the live page; the polling fact is the package's own
(`WorkingWithYandex`). The official surfaces around that contract are a desktop web
cabinet and the consumer Yandex Go app, which is a different contract at a different
price.

So a small sender who holds a business token and wants to order **from a phone, at
business terms** has two options today: run or rent a backend and build a front against
it, or type coordinates into the web cabinet. This app is the third: the whole client on
the device. Token in the Keychain, journal polled on-device, iCloud as the
quasi-backend for sync and sharing, nothing in between the sender and the provider. **Zero
infrastructure is the feature, not a shortcut** — no account with us, no server holding
addresses and phone numbers, nothing to keep running.

### Who it is for

1. **The occasional business sender** — an ИП, a self-employed maker, a studio, a small
   shop: 2–30 parcels a week inside one city, a business cabinet already open, someone
   who today opens a laptop to send a parcel. The primary audience; every Phase 1–3
   decision was made for this person.
2. **The dispatcher-of-one and their recipients** — the sender is not the person at the
   door. The private share and the per-order chat exist for this: a recipient or a
   colleague follows the delivery, confirms receipt, leaves a photo — **without a Yandex
   login**, because the grant and the token are independent axes (<doc:Collaboration>).
3. **Developers integrating the Express API** — the packages, not the app, serve them:
   `YandexDeliveryExpressAPI` is the only Swift client in the open, and this app is its
   reference consumer. Keep the two audiences on two surfaces; a store listing that
   courts both dilutes both.

### What it can honestly claim today

| Claim | Backed by |
|---|---|
| Order from a map, not from coordinates | pick-on-map, autocomplete, saved places, recents, link/coordinate paste (<doc:LinkGrammars>) |
| See the price before you commit | `offers/calculate` → tariff strip, review sheet, per-draft idempotency |
| Every order you sent, on every device you own, searchable | local + private CloudKit sync; search over addresses and «Ваши поля» |
| Know when the courier arrived without opening the app | journal poll + `BGAppRefreshTask`, status notifications, Live Activity, two widgets |
| **The page you never refresh.** The web cabinet shows what it showed when you loaded it; the app polls the feed while open, wakes on the system's schedule while closed, and *tells* you — a local notification per status change, a Lock Screen card that follows the courier. Best-effort by nature, still strictly more than a browser tab (author, 2026-09-29) | `ClaimsSyncController` 30 s poll + `handleAppRefresh`/`scheduleAppRefresh` chain, `NotificationController`, `LiveActivityController` |
| Repeat last week's run in one tap | «Повторить»/«Наоборот», saved places, order numbers |
| Share a delivery without sharing your account | `CKShare` per order, read-only or read-write, per-order chat with photos and «получено» |
| Cancel with the price shown | `cancel-info` → `cancel`, the fee stated before the tap |

### What it must not claim yet

- **Courier on the map, ETA per stop, call the courier, tracking link** — the API has
  them; the package does not (Later). The journal carries no coordinates.
- **Live updates while the app is closed** — background refresh is best-effort and
  system-scheduled; real push needs the relay (Later). Say "notifies", never "real-time".
  The honest comparison with the cabinet is *a page you refresh* versus *an app that
  refreshes itself and tells you*; whether the cabinet offers e-mail or SMS alerts of its
  own is **[unverified]** — do not claim it has none.
- **Edit after sending, returns, scheduled windows** beyond `due` — not in the package.
- **A free trial** — Yandex has no sandbox; the first order a new user places costs
  money. The app can only make that first order *safe* (price on the sheet, a
  cancellation that shows its fee), not free.
- **Android, web, Mac** — iOS-first is a decision (<doc:Design> → "iOS-only"), not an
  omission to apologize for.

### Unique selling proposition — three candidates

The wording is not settled; each sentence below is true today and each leads with a
different audience. Author's call.

- **A.** «Ваш бизнес-кабинет Яндекс Доставки — в кармане. Без бэкенда, без интегратора.»
  Leads with the gap; narrowest and most honest; growth is capped by cabinet holders who
  know a token exists.
- **B.** «Отправляйте по бизнес-тарифу с карты, а не из таблицы.» Leads with the
  map-first ordering — the single biggest UX distance from the raw API and from the web
  cabinet; broader, but onboarding must teach "get your token from the cabinet", because
  no signup can happen in the app.
- **C.** «Доставка, за которой можно следить вместе — без общего аккаунта.» Leads with
  sharing and chat; the most distinctive, and the one that needs the device-verified
  sharing path first (<doc:Collaboration> → open verifications).

Recommendation as of this writing: **A for the listing's first line, B for the
screenshots, C for the second version** — once acceptance has been walked on real
devices. All three wordings predate the 2026-10-02 repositioning and lead with the
provider; under the general-purpose framing the provider's name moves to the subtitle —
"supports Yandex Delivery business accounts" — while the unofficial-client disclaimer
stays (<doc:Design> → "Unofficial, visibly").

### App Store presentation — what a listing needs from this codebase

- **Name and subtitle.** `YDelivery` — a delivery-first title; the subtitle names the
  integration and must fit the App Store's 30-character limit (*"Yandex Delivery —
  unofficial"*, 28).
  Nominative use of the provider's name is the honest description; no logos,
  no color mimicry (trademark hygiene, and App Review 5.2.1 reads third-party names
  case by case — the disclaimer in the subtitle is the argument).
- **Category.** Business primary, Utilities secondary. Not Shopping, not Travel.
- **Screenshots, in order.** The draft card over the map; the tariff strip with prices;
  the Deliveries list; the Live Activity / Dynamic Island; a shared order's chat. The
  `--uitest-three-stop-draft`, `--uitest-fields` and `--uitest-history` launch flags
  render seeded states for the draft, the fields and the history/detail/chat screens
  (`DraftScreenshotTests`, `FieldsScreenshotTests`, `HistoryScreenshotTests`); the tariff
  strip and the Live Activity still need a seed of their own.
- **App Review.** Guideline 2.1 requires the reviewer to exercise the app, and Yandex has
  no self-serve sandbox: a *test cabinet* exists, but only by asking a personal manager —
  the API package's live tests ran on one, so it is real, and it is not something a
  listing can assume every reviewer session will have. Three honest paths: (1) a test
  cabinet's token, if granted — the best case, and worth the ask before submission;
  (2) a real business token whose orders are cancelled in the free window — money at risk
  if a reviewer accepts and forgets; (3) ship a **Demo mode** — the seeded store behind a
  Settings switch, read-only, clearly labelled — which also answers the prospective user
  with no token yet. The seed exists (`--uitest-history`, PR #61); the switch is a slice.
  **(3) is the recommendation, with (1) attempted alongside.**
- **Privacy labels.** Addresses, names and phone numbers go to Yandex (the service being
  ordered) and to the user's own iCloud private database (sync, sharing). No analytics, no
  third-party SDKs that phone home. The wire log leaves the device only by the user's
  explicit share (YD-12). Data linked to the user: contact info, precise location; used
  for app functionality only.
- **Payments.** Delivery is paid to Yandex on the user's business account — a service
  consumed outside the app, so no In-App Purchase question arises (3.1.3(e)). Whether the
  *app* charges is a separate decision, below.

### Monetization — options, not a pick

| Model | Fits when | Cost |
|---|---|---|
| Free, source open | the packages are the product for developers; the app earns goodwill and bug reports | no revenue; supports nothing but itself |
| One-time price | a utility for people who already pay Yandex; no server to fund | a paywall in front of a token most users do not yet have — the Demo mode softens it |
| Subscription | only once a relay exists (push, shared-order pages) — a running cost to justify one | premature before the backend question below is answered |

### The backend question — a staged answer

The author's framing is right: the *clean* architecture is a backend of ours plus an app
against it, and the backend-less app looks like a shortcut. It is a shortcut **only for
what a backend would add**, and today that list is short and priced:

1. **Now — nothing between the sender and the provider.** Privacy, zero ops, no accounts.
   This is the version that can earn its first users, and every piece of it survives the
   next two steps unchanged.
2. **Next — a stateless relay.** Yandex's webhook → APNs, a Cloudflare Worker holding no
   user data, unlocking background Live Activity updates (<doc:Roadmap> → Later). It adds
   no account and no database; it is the one thing iCloud structurally cannot do.
3. **Later, only if recipients without iPhones matter — a shared-order page.** The first
   thing that needs a real backend with state, and the point where the SQL-shaped schema
   pays: <doc:Schema> ports to server SQL unchanged (<doc:Design> → "iOS-only",
   revisited 2026-09-26).

The app "as scaffolded" is therefore not a compromise against the clean approach; it is
the clean approach's first stage, and the stages are ordered by what each unlocks. The
risk is not architectural, it is **market size**: Express token holders who would adopt
an unofficial iOS client are few. Two things widen it without a backend — the Demo mode
(anyone can look), and the share/App Clip path (recipients arrive through senders). Both
are in reach of the current codebase.

## See Also

- <doc:Design>
- <doc:Roadmap>
- <doc:TechDebt>
