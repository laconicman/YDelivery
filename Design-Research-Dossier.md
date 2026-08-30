# Design research dossier — destination & ordering UX for YDelivery

**Status: transient.** This document answers the research half of `Design-Research-Brief.md`.
It is consumed by the visual-design session (Claude Design) together with that brief; its
conclusions land in `YDelivery/Documentation.docc/` (`Vision.md`/`Design.md`) once the design
lands, and this file is then deleted — the sibling repos' `HANDOFF.md` convention.

**Method.** Findings come from vendor documentation, product help pages, recorded flow
teardowns (Page Flows, Mobbin), design case studies, and the two reference screenshots in
`YDelivery/Documentation.docc/Resources/` (`2gis-search-home.png`, `2gis-route-transport-tabs.png`).
Every factual claim cites its source URL. Where a claim rests only on the screenshots or on
general product knowledge, it is marked *(observed)*. Checked 2026-02.

**Constraints repeated from the brief, so nothing below is read as optional:** iOS 17 floor,
SwiftUI-native, semantic colors/type only, design at `accessibility-extra-large` (the
NetworkObserver handoff response documents how fixed-size mockups failed both directions:
`/Users/paul/Documents/Code/Network/NetworkObserverSample/docs/DesignHandoffResponse.md`),
unofficial app — no Yandex branding, and nothing in the IA may hard-code the single provider.
API vocabulary (claims, offers) never appears in UI copy.

---

> **Merged 2026-08-30:** the design session's answers and additions (§6–§13, plus answers to
> every open question in §1.5, §2.3, §3.4, §4, §5) are appended below as **Part II**. Where
> Part I asks a question, Part II's answer wins. §3.2's grammar table has moved to the
> permanent <doc:LinkGrammars> spec; the four specs that outlive this dossier live in
> <doc:DesignSystem>.


## 1 · The destination interface (brief §1)

### 1.1 Per-app findings

**Yandex Go (taxi).** Destination-first: the field asks where *to*, not where from; pickup is
inferred from GPS and corrected afterwards. Since the 2023 redesign the super-app home is a
services grid and the taxi flow is an isolated scenario with its own screen
(https://www.ixbt.com/news/2023/07/04/zakaz-vsego-ponovomu-jandeks-pererabotal-jandeks-go-ubrav-kartu-s-glavnogo-jekrana.html,
https://kod.ru/6958). The app predicts likely destinations from ride habits (day of week,
time, frequency) and pre-fills them as one-tap suggestions — after launch, users picked
suggested addresses 15% more often; it also generates AI pickup hints for the driver
("арка с чёрными воротами") instead of free-text comments
(https://dar-nebes.ru/news-12201-yandeks-go-teper-predlagaet-podskazat-kuda-podehat-voditelyu.html).
Price and ETA are shown for the whole route before ordering (https://go.yandex/en_tr/).
Delivery inside Go reuses the taxi shell: choose «Доставка», enter addresses and contacts
per point, add options such as «До двери» (door-to-door)
(https://dostavka.yandex.ru/hand-delivery/).

**Uber.** "Where to?" is a question, not a form label; the map keeps ~70% of the screen and
carries pickup-anxiety/liveness/wrong-pin-spotting duties
(https://www.reversebits.tech/blog/ubers-mobile-app-a-ui-ux-breakdown-no-one-talks-about/).
Recorded flow: Home → Search location → Set destination → Select ride → Confirm pickup area →
Trip booked (https://pageflows.com/post/ios/booking-a-ride/uber/). Pin adjustment: "Edit"
next to pickup → type a new address **or drag the pin within a gray circle**; one adjustment
allowed, then Confirm (https://www.uber.com/do/en/ride/how-it-works/change-location/). A UX
case study notes the "Confirm pickup point" step appears *inconsistently* (usually only
after drop-off is set, when pickup was auto-detected) and argues for moving it earlier —
i.e., the confirm-pin step is valuable but its placement is contested
(https://medium.com/@raveenaamarasiriwardena/solving-what-stops-the-ride-a-ux-case-study-focused-on-clarity-trust-and-user-experience-c4c98395f60e).

**Uber Connect / Package (courier mode inside the rider app).** The parcel flow is the ride
flow: enter the package destination in "Where to?", pick "Connect" from the vehicle-option
list, agree to terms + confirm no prohibited items, then select precise pickup and drop-off
points and share tracking with the recipient
(https://help.uber.com/de-DE/riders/article/package-delivery-faq?nodeId=8fa2306b-c14d-4f0b-9395-4c4523a81e85).
Constraints (≤20 kg, fits in a trunk, sealed) are stated as eligibility text at selection
time, not as a wizard. Uber's B2B delivery API guidance for partner UIs: collect pickup +
drop-off first (ideally refined via a pickup-refinement flow), then show each product with
name, image, ETA and fare (https://developer.uber.com/docs/guest-rides/guest-ride-api-build-guide/pulling-product-estimates).

**Bolt.** Same three-beat structure, fewer screens: Home → Set destination → Select type →
Confirm booking (https://pageflows.com/post/ios/booking-transport/bolt/). Notably Bolt keeps
an explicit **Edit route** screen reachable from type selection — you can revise stops
without abandoning the sheet (https://pageflows.com/post/ios/general-browsing/bolt/).

**2GIS.** Route entry is a dedicated «Проезд» button beside the search bar, or "Проехать"
from any place card; then transport type; then route variants; adjusting a built route is
done by dragging a point on the map
(https://help.2gis.ru/question/kak-postroit-marshrut-proezda-na-obshchestvennom-transporte-ili-avtomobile).
The home dashboard puts the search field on top with Home/Work buttons and ML "smart
suggestions" (most-visited places with travel time) directly beside them
(https://dostavili.2gis.ru/public/0522/mobile/, https://dostavili.2gis.ru/public/0522/smart-route/).
The two repo screenshots show the concrete pattern to re-phrase *(observed)*:
`2gis-search-home.png` — search sheet over the map, Home/Work chips + bookmarks right under
the field, suggestion rows below; `2gis-route-transport-tabs.png` — from/to fields with
colored end-dots and per-row drag handles, and a single-row strip of transport pictograms
above the fields.

**Yandex Maps.** From/to fields in a route card; a swap control between them; «Добавить
точку» adds intermediates; rows reorder by drag; deleting a row rebuilds the route
(https://yandex.ru/support/maps/ru/concept/rout). Long-press on the map offers «Отсюда» /
«Сюда» (https://yandex.kz/support/m-maps/ru/start-building-route). The taxi layer accepts up
to 20 intermediate points (https://yandex.com/support/m-maps/en/taxi).

**Google Maps.** Directions accept up to 9 stops besides start; stops reorder by drag
(https://support.google.com/maps/answer/144339). Search-first; map-pin adjustment exists
only as "drop a pin then use it", not as a confirm step.

**Citymapper.** "Get Me Somewhere" as the single entry; Home/Work/Places chips for
recognition-over-recall (https://ixd.prattsi.org/2026/02/design-critique-citymapper-ios-app/);
'Pick from Map' is offered *inside* the search sheet as a first-class alternative to typing
(https://citymapper.com/news/1371/better-search).

**Borzo (ex-Dostavista).** Courier-native counter-example: the order is a **form of address
rows** (a points list with contact person per point), not a map conversation; the map is
secondary. The 2017–2019 redesign that reduced form steps measurably lifted order completion
(https://0r8it.com/case/borzo-delivery). Vehicle type (bike/car/truck) is a delivery option,
and the app advertises auto-built optimal multi-point routes
(https://apps.apple.com/us/app/borzo-courier-delivery-app/id1530403049,
https://borzodelivery.com/in/business-api/doc).

### 1.2 The search-vs-map order, synthesized

Consensus order across taxi apps: **(1) text/suggestion entry first** (destination is usually
known by name), **(2) map-pin refinement second** (pickup is where GPS + reverse geocode need
human confirmation), **(3) map-first entry as an explicit escape hatch** ("Pick from map" /
long-press) rather than the default. Courier apps (Borzo) skew form-first because senders
often paste addresses they were given. YDelivery already has the picker sheet with
autocomplete + tap-to-pin; the missing pieces are the saved-place chips row, recents in
suggestions (§3.3), and a confirm-pin ("уточните точку") state with a draggable/centered pin
and the resolved address in an editable pill — Uber's gray-circle constraint does not apply
(couriers go anywhere), but its "one clear Confirm" does.

### 1.3 Tariff/class selectors — expert strip vs beginner cards

**Yandex Go** presents tariff classes as a compact horizontally scrolling row of cards
(vehicle pictogram + name + price) above the order button; tapping the ruble icon after
selecting tariff + route opens a **price-detail sheet** (base fare, surge, options) — the
"what am I paying for" explainer is a second-level surface, not inline
(https://yandex.ru/company/news/03-03-12-204, https://t-j.ru/news/yandex-price-details/).
**Uber** does the same shape: bottom sheet listing products, each row = image + name + ETA +
price; swiping up expands the full list; a "Faster" badge marks the lowest-ETA product
(https://help.uber.com/en/riders/article/selecting-a-vehicle-option-for-your-ride?nodeId=53d5ef29-0fa5-4252-a48c-43ff244ce6ce).
Selecting a card expands it in place (taller card, bigger vehicle art, CTA text morphs) —
detail-on-selection instead of a separate mode (https://60fps.design/shots/uber-ride-picker-card-morph-interaction).

**Courier tariff vocabulary to map onto that strip** (from the provider's own tariff
catalog — these arrive as *data*, names included, via the tariffs/offers surface;
https://yandex.ru/support/delivery-profile/ru/api/express/faq):

| Tariff (`taxi_class`) | Weight | Max dimensions (L×W×H) | Options |
|---|---|---|---|
| Курьер `courier` | ≤ 10 kg | 0.80 × 0.50 × 0.50 m | `thermobag`, `auto_courier` |
| Экспресс `express` | ≤ 20 kg | 1.00 × 0.60 × 0.50 m | — |
| Грузовой `cargo` + size `van`/`lcv_m`/`lcv_l` | 300 / 700 / 1400 kg | 1.70×0.96×0.90 / 2.60×1.30×1.50 / 3.80×1.80×1.80 m | `cargo_loaders` 1–2 |

The tariffs endpoint returns per-geo `supported_requirements` with localized titles and
descriptions (e.g. "170 см в длину, 100 в ширину, 90 в высоту") — the beginner-mode card
copy can be provider data, not hardcoded strings
(https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs).
Door-to-door («До двери») is a delivery option in the same family
(https://dostavka.yandex.ru/hand-delivery/).

### 1.4 Recommendation for this app

- **Route card = the 2GIS «Проезд» pattern re-phrased**: from/to rows with colored end-dots
  and drag handles; a one-row **tariff strip** (pictogram + short name + price once priced)
  where 2GIS puts transport tabs. Strip content is per-provider data (provider column
  exists in history; nothing hardcodes "the one provider").
- **Two modes, one rule.** Expert mode = the strip (selected item shows name+price; others
  compress to pictogram+price). Beginner mode = a details sheet opened from an ⓘ on the
  strip or by long-press on a class: one card per tariff with weight/dimensions limits,
  option toggles (loaders count, thermobag, door-to-door), constraint warnings. **Rule:**
  the sheet auto-opens the first N times a user meets the strip (or until first successful
  order), after that the strip is default and the sheet stays one tap away. Uber's
  expand-on-select morph is the middle ground worth drawing.
- **Search-first entry with map escape hatch**: picker sheet opens on the keyboard with
  saved-place chips (Home/Work/warehouses) under the field (2GIS home pattern), suggestion
  list below, and a "Choose on map" row (Citymapper's 'Pick from Map'). Tap-to-pin already
  exists; add the **confirm-pin state**: centered pin, reverse-geocoded address in an
  editable pill, single Confirm button (Uber's mechanic, without the radius constraint).
- **States to draw** (per house rules, all previewable from literals): empty (no saved
  places yet), autocomplete loading, no-results (offer "use as plain address" + map pick),
  reverse-geocode failed (coordinates shown as text, editable), offline.

### 1.5 Open questions for the visual designer

1. Does the tariff strip live on the route card (2GIS position, above fields) or as a bottom
   sheet after both ends exist (Uber/Bolt position)? The screenshots argue for the former;
   pricing-latency argues for the latter.
2. Beginner cards: one horizontal paged card per tariff (Uber-like) or a vertical list with
   disclosure (Borzo-like form)? At `accessibility-extra-large` a vertical list is safer —
   specify the reflow ladder, not a breakpoint (see DesignHandoffResponse §2.1).
3. Where do per-point contact fields (name/phone — the API requires them per point) enter
   the flow without turning the picker into Borzo's long form?

---

## 2 · Route list & pin taxonomy (brief §2)

### 2.1 Conventions found

- **Yandex Maps**: waypoints are labeled with Latin letters **A, B, C…** on map placemarks;
  via-points (pass-through, no stop) are visually distinct smaller dots
  (https://yandex.ru/dev/jsapi-v2-1/doc/ru/v2-1/dg/concepts/router/about).
- **Google Maps** (Routes API default): waypoint markers lettered A, B, C; Google's own
  sample styles origin green, intermediates blue-with-numbers, destination distinct — i.e.
  even Google re-styles letters into **numbers for intermediates** when routes grow
  (https://developers.google.com/maps/documentation/javascript/routes/routes-markers).
- **Google Maps consumer app**: origin = small solid circle, destination = red teardrop pin,
  intermediate stops = small numbered circles *(observed)*.
- **Apple Maps**: current-location blue dot; destination red pin; no public multi-stop
  taxonomy beyond numbered stops in multi-stop routing *(observed)*.
- **2GIS reference screenshot**: from/to rows carry **colored end-dots** (origin vs
  destination differ by color), drag handles per row *(observed — the pattern the brief
  asks to keep)*.
- **Delivery/PUDO context**: Russian users distinguish **ПВЗ** (staffed pickup point) from
  **постамат** (locker) — different capabilities (fitting room/returns vs 24/7 code
  access), so they deserve different glyphs, not one "pickup" icon
  (https://vc.ru/top_obzor/3019544-punkty-vydachi-zakazov-vidy-i-kak-imi-polzovatsya).

### 2.2 Proposed visual system (shapes + SF Symbols + color tokens)

Principle: **role is encoded by shape + glyph first, color second** — color-blind users must
be able to read the route from shape alone. The Okabe-Ito palette is the standard
color-blind-safe categorical set; its guidance: avoid red+green as the only pair, prefer the
high-contrast quartet orange/sky-blue/blue/vermillion, never rely on color alone
(https://sci-draw.com/figure-accessibility-kit, https://vizcept.com/blog/okabe-ito-palette-guide).

| Role | Map shape | SF Symbol (verify in SF Symbols app for iOS 17 minimums) | Color token (asset catalog, resolves to system colors) | List badge |
|---|---|---|---|---|
| Start (A) | small filled circle | `a.circle.fill` (or plain dot) | `PinStart` → `.green` | green dot |
| Intermediate stop *n* | numbered circle | `1.circle.fill` … `50.circle.fill` | `PinMid` → `.gray`/secondary | gray numbered dot |
| End (B) | teardrop pin | `mappin.circle.fill` / `flag.checkered` | `PinEnd` → `.red` | red pin glyph |
| Warehouse (saved source) | rounded square | `building.2.fill` or `shippingbox.fill` | `PlaceWarehouse` → `.brown` | badge on row |
| Pickup point (ПВЗ, staffed) | rounded square | `storefront.fill` (SF 5 / iOS 17) | `PlacePickup` → `.indigo` | badge on row |
| Locker (постамат) | rounded square | `cabinet.fill` | `PlaceLocker` → `.purple` | badge on row |
| Door-to-door option | — (option, not place) | `door.left.hand.open` | inherits tariff | option chip |
| Home / Work saved | chip | `house.fill` / `briefcase.fill` | accent | chip |
| Recent | row leading icon | `clock` / `clock.arrow.circlepath` | secondary | clock badge |
| Saved/bookmarked | row leading icon | `star.fill` or `bookmark.fill` | accent | star badge |

Notes for the designer:

- **Green start / red end is the market convention** (taxi apps, the 2GIS screenshot's
  colored dots) but it is exactly the protanopia/deuteranopia collision pair. It stays
  acceptable **only because** shape (dot vs pin), glyph (A vs B / flag), and lightness
  differ; if any of those are dropped, switch the pair to Okabe-Ito blue `#0072B2` /
  vermillion `#D55E00` equivalents (https://sci-draw.com/figure-accessibility-kit). Tokens,
  not literals: `PinStart`/`PinEnd` in the asset catalog with dark-mode variants.
- **Letters for ends, numbers for the middle** matches both Yandex (letters) and Google's
  restyling practice (numbers) while keeping A→B reading for the common two-point case;
  numbered intermediates survive reordering better than a full alphabet (B2…B9 would
  re-letter confusingly on drag).
- Reordering UI: rows with `line.3.horizontal` drag handles (2GIS screenshot), swap-ends
  button `arrow.up.arrow.down` between from/to (Yandex Maps has the same control:
  https://yandex.ru/support/maps/ru/concept/rout), insert `plus.circle.fill` / remove
  `minus.circle.fill` in edit mode. Map pins and list rows must use the *same* glyph+color
  pairs so the list is the legend.
- Multi-stop ceiling for UI stress-testing: Google allows 9 stops, Yandex Maps taxi 20
  (https://support.google.com/maps/answer/144339, https://yandex.com/support/m-maps/en/taxi);
  the API's `route_points[]` is N-point. Design list rows for 2 (common), 5 (plausible),
  10+ (degenerate — the list scrolls, the map clusters).

### 2.3 Open questions

1. Do warehouse/ПВЗ/locker markers appear on the *picker* map always, or only when the
   suggestion list surfaces them (map noise vs discoverability)?
2. Should the end pin be a flag (`flag.checkered` reads "finish" without color) or a pin
   (map-native)? Pick one; don't mix per screen.
3. At accessibility sizes, numbered circles in rows grow — confirm the row layout ladder
   (number + one-line address → number above address) per the handoff-response method.

---

## 3 · Coordinates every way users have them (brief §3)

### 3.1 Free text → coordinates (exists; design the fallout)

`MKLocalSearchCompleter` autocomplete is shipped. Fallout states to draw: (a) zero
completions → offer verbatim-geocode attempt + "Choose on map"; (b) geocode returns a
*different-looking* address → show both, user picks; (c) geocode fails/offline → error row
with retry, never a dead end; (d) resolved-but-imprecise (street-level only) → nudge into
the confirm-pin state from §1.4.

### 3.2 Pasted links & raw coordinates — moved to the permanent spec

The full grammar table (Yandex/Google/2GIS/Apple/`geo:`/raw forms, with per-provider
coordinate order and offline-vs-network flags) now lives in
`YDelivery/Documentation.docc/LinkGrammars.md` — it is parser specification, not design
research, and it outlives this transient document.

What stays here is the design consequence: **the paste affordance always shows the resolved
point (mini-map or address) for human verification before it joins the route** — providers
disagree on lon/lat order and both values are ≤ 90 in western Russia, so a silent swap
produces a plausible pin in the wrong sea. And per iOS pasteboard privacy, paste is a
button, never an ambient scan.

### 3.3 Recents & suggestions blending

- **2GIS**: recents appear as clock-badged rows inside the search sheet, mixed under saved
  chips *(observed — `2gis-search-home.png`)*; its home screen additionally computes "smart
  suggestions" (habitual places, with travel time) from route history
  (https://dostavili.2gis.ru/public/0522/smart-route/).
- **Google Maps**: past searches resurface inside autocomplete when history is on; a
  dedicated Recents surface groups them by geographic area; saving recents into lists is
  offered in bulk (https://support.google.com/maps/answer/3092445,
  https://support.google.com/websearch/answer/17024959).
- **Yandex Go**: prediction goes further — likely destinations are pre-filled from habit
  patterns before typing (https://dar-nebes.ru/news-12201-yandeks-go-teper-predlagaet-podskazat-kuda-podehat-voditelyu.html).

**Recommendation.** In the picker: (row 0) saved-place chips (Home/Work + warehouses);
(rows 1–3, empty query) up to **3 recents** clock-badged; as the query grows, recents that
prefix/fuzzy-match stay pinned above live completions, clock badge distinguishing them;
saved places that match rank above recents (star/warehouse badge). **Dedup rule:** a recent
that equals a saved place renders once, as the saved place (its badge wins); two recents
within ~50 m and same normalized title collapse to the newest. Recents store: last ~10 per
role (pickup vs drop-off may differ; a warehouse is a habitual *source*), pruned FIFO —
counts are a designer decision, these are defaults to react to. Everything local (SwiftData),
no account — mirrors the app's local-history stance in `Vision.md`.

### 3.4 Open questions

1. Does the paste affordance live as a row atop suggestions (recommended — no modality) or
   as a banner over the map? Draw the declined state (user said no — don't re-offer the same
   URL in the same session).
2. Route-links (`rtext`, `/directions/`) carry two+ points — offer "fill both ends" as one
   action or two separate suggestions?
3. Recents row content: address-only, or address + "when" (relative timestamp)? 2GIS shows
   plain rows; Google groups by area. At accessibility sizes a second line is costly.

---

## 4 · Route preview before price (brief §4)

**Precedents.** Taxi apps universally render the polyline + ETA + price *before* commit:
Yandex Go — "enter destination, see fare and estimated route time upfront"
(https://go.yandex/en_tr/); Uber — upfront price and route on the confirm screen
(https://www.uber.com/gt/en/ride/how-it-works/upfront-pricing/); 2GIS builds route variants
with times before any navigation starts (https://help.2gis.ru/question/kak-postroit-marshrut-proezda-na-obshchestvennom-transporte-ili-avtomobile).
The pattern's job in a courier app is subtly different: the user is *not* riding — the
preview answers "am I about to price the right trip?" (right ends, sane distance), not
"which lane will I take".

**Recommendation.** As soon as both ends resolve (and on every reorder/edit), the draft
screen's map shows an `MKDirections`-computed polyline with distance + rough drive time in a
compact info bar — clearly styled as an *estimate* (secondary label "оценка маршрута", no
price yet, so it cannot be confused with the provider's offer). It lives on the **draft
screen** (the route's home); the picker keeps only its confirm-pin map. States: computing
(shimmer on the info bar, map already framing both pins), failed (info bar renders "не
удалось оценить маршрут" + retry — pins and ordering still work; MKDirections failure must
not block pricing), degenerate (A≈B → warn), multi-point (sum of legs; polyline segments
alternate emphasis so leg boundaries read). Semantic colors; polyline uses the accent tint,
not a hardcoded blue.

**Open questions.** (1) Does the info bar double as the CTA row ("Посмотреть цены" appears
inside it once the estimate lands)? (2) On estimate failure, does the CTA move up or stay
anchored (layout-shift vs dead space)? (3) Show the MKDirections time at all once real
offers (with provider ETAs) arrive, or replace it?

---

## 5 · Location permission, the considerate way (brief §5)

**The house pattern** (from `NetworkObserverSample` — `PermissionService` +
`PermissionsView`; see `docs/DesignHandoffResponse.md` and the code): permission state is a
first-class rendered state, not an alert cascade. The decision tree lives in one controller:
`.notDetermined` → show the in-app explainer, then request; `.denied/.restricted` → **do not
re-prompt** (nothing is left to prompt for), render the denial with an "Open Settings"
button deep-linking via `UIApplication.openSettingsURLString`; `.authorized` → just work.
Status rows show the live state with explicit labels; an orange explainer band states *why*
the permission matters and what "denied" costs, honestly.

**Platform guidance to cite in the design.** Apple HIG (Privacy): request only in context —
"wait to request permission until people actually use an app feature that requires access";
"avoid requesting permission at launch unless the data or resource is required for your app
to function"; purpose strings must be specific, sentence-case, with a period
(https://developer.apple.com/design/human-interface-guidelines/privacy). Pre-permission
explainer screens roughly double grant rates versus cold prompts (industry measurements:
https://github.com/pproenca/dot-skills/blob/HEAD/skills/.experimental/ios-hig/references/ux-permissions.md).
A priming screen must have a neutral Continue (never a fake "Allow", no system-alert
mimicry). Also available: `LocationButton` (CoreLocationUI, iOS 15+) grants one-shot
When-In-Use access from a system-drawn button without a standing prompt — the zero-ambush
option for "start the map at my position"
(https://appofweb.com/blog/best-practices-for-accessing-and-handling-user-permissions-for-ios-apps).

**Adaptation for YDelivery (When-In-Use only; no Always, no background).**

1. **Never prompt on launch.** The map opens on the last-used region or the user's city
   (an explicit setting), pins work without location — location is a convenience here,
   not a dependency; a courier order can be composed entirely for *other* people's
   addresses.
2. **First ask happens at a location-shaped intent**: tapping the locate-me control or
   choosing "От моего местоположения". Before the system alert, one lightweight inline
   explainer (not a full-screen interstitial — this is a map app, the benefit is nearly
   self-evident; HIG's navigation-app example applies): one sentence + Continue/Not now.
3. **Denied is a rendered state**: the locate-me control shows a slashed variant
   (`location.slash`), tapping it presents the explainer with "Открыть Настройки"
   (Settings deep link) — exactly the `PermissionService` tree. No dead taps, no repeated
   system alerts.
4. **Purpose string** (`NSLocationWhenInUseUsageDescription`), Russian-first, specific:
   «Показывает вашу позицию на карте и подставляет её как точку отправления.» — names both
   uses, nothing else.
5. **Consider `LocationButton`** for the picker's "use my location" row: one-shot access,
   no permission debt. Open question below.
6. States to draw: not-determined (pre-explainer), prompt-in-flight, authorized
   (locate-me active), denied (slashed control + Settings path), reduced-accuracy
   (approximate location — the pin lands in a ~1 km blob; offer the confirm-pin step and,
   only if the user insists on precision, `requestTemporaryFullAccuracyAuthorization`).

**Open questions.** (1) `LocationButton` has styling constraints (system-drawn, limited
theming) — acceptable inside the picker sheet, or does the house style demand a custom row
(then it's the standard prompt flow)? (2) Does the reduced-accuracy state deserve its own
copy, or does the confirm-pin step silently absorb it? (3) Where does the "start city"
setting live for the never-granted cohort — Settings screen only, or inline on first map
open?

---

## Designer's checklist (one page)

**Destination flow**
- [ ] Picker: search-first; saved chips row (Home/Work/warehouses) under the field; recents
      clock-badged in suggestions; "Choose on map" row always present.
- [ ] Confirm-pin state: centered pin + editable resolved-address pill + single Confirm.
- [ ] Route card: from/to rows, colored end-dots, drag handles, swap control, add/remove
      intermediates (design for 2 / 5 / 10+ points).
- [ ] Tariff strip: one row, per-provider data, pictogram + name + price; beginner cards
      sheet with limits/options (loaders, thermobag, door-to-door) from provider text;
      auto-open rule for new users; never API vocabulary in copy.

**Pins & lists**
- [ ] Role = shape + glyph first, color reinforces: A-dot green / numbered gray middles /
      B-pin red (or Okabe-Ito blue/vermillion if any shape cue is dropped).
- [ ] Distinct glyphs: warehouse `building.2.fill`/`shippingbox.fill`, ПВЗ
      `storefront.fill`, locker `cabinet.fill`; same pairs on map and in rows; tokens in
      the asset catalog, no color literals; verify symbol iOS-17 availability.

**Links & coordinates**
- [ ] Paste affordance = suggestion row with resolved point preview; grammars per the §3.2
      table; short links show an expanding state and an offline failure; declined offers
      don't repeat.
- [ ] Never trust coordinate order — host+param decides; always human-verify via preview.

**Route preview**
- [ ] Draft screen: polyline + distance + rough time, marked as estimate; loading /
      failed / degenerate states; failure never blocks pricing.

**Permissions**
- [ ] No launch prompt; ask at locate-me intent with inline explainer; denial = rendered
      state with Settings deep link; purpose string names both uses; consider
      `LocationButton`; draw the reduced-accuracy state.

**Process**
- [ ] Every screen: empty/loading/error + `accessibility-extra-large` frame; specify reflow
      as a ranked ladder, not breakpoints; Reduce Motion variant for any animation; every
      content view previewable from literals.


---

# Part II — design-session answers & additions (merged 2026-08-30)

**How to use this.** Everything below is keyed to the existing section numbers of
`Design-Research-Dossier.md` and is meant to be merged into it (I can read the linked repo
but not write to it). Two kinds of content: **answers** that close the dossier's open
questions, and **§6**, a new section the dossier is missing entirely — the field taxonomy,
which `YandexDeliveryExpressDemo` makes visible and the research half did not account for.

Artefacts this refers to, all in the design project:

| File | What it holds |
|---|---|
| `YDelivery — Shipped Today.dc.html` | Baseline: ten frames recreated from the shipped `#Preview`s |
| `Round 1 - Route & Ordering.dc.html` | `1a` map-first shell, `1b` fixed-card shell |
| `Round 1 - Picker & Points.dc.html` | `2a` picker (8 states), `2b` multi-point ladder, `2c` pin/badge spec |
| `Round 1 - Tariffs, Fields & XL.dc.html` | `3a`/`3b`/`3c` beginner explainer, `3d` parcel & options, `3e` saved place & history, `3f` accessibility-XL |
| `Round 2 - Callouts, Custom Fields & Motion.dc.html` | `4a` map callouts, `4b` custom fields, `4c` motion spec |
| `Round 3 - System Surfaces.dc.html` | `5a` Live Activity & Dynamic Island, `5b` widgets, `5c` notifications, `5d` intents/Spotlight/sharing, `5e` shared components, `5f` HIG audit |
| `Positioning.md` | Purpose, audience, promotional prose |

---

## Answers to §1.5 — the destination interface

**Q1 — where does the tariff strip live?** Both, and the split is not a compromise: the
strip's *position* and the *moment price arrives* are separate decisions, and the dossier
conflated them. Draw the strip on the route card (2GIS position, `1b`) and let it hold a
waiting state; the Uber position (`1a`) is the same strip further down a sheet that grows.
The recommendation is **`1b`, the fixed card** — for a reason the dossier could not have
known before the demo was read: filled point rows are two lines (address + contact), route
lists reach 5 and 10 points, and a bottom sheet that must be dragged to read the route is
the wrong shell for that. `1a` remains the better shell if the app ever becomes
courier-hailing rather than parcel-sending.

**Q2 — beginner cards, paged or vertical?** Vertical list (`3a`). `3f` is the argument: at
`accessibility-extra-large` the horizontal strip cannot survive and becomes a vertical list
anyway, so a paged-card explainer (`3b`) would need a second layout to fall back to. `3c`,
expand-in-strip, is worth keeping as the *expert* affordance — it answers "what am I
paying for" without a second surface — but it is not the beginner mode. Proposed rule,
unchanged from the dossier apart from being specific: the sheet auto-opens until the first
successful order, then lives behind the ⓘ, and `3c` handles the in-place case forever after.

**Q3 — where do contacts enter?** On the draft screen, as a collapsed row under each point
(`1a`, `1b`, `2b`). Empty renders as an action ("Кто отдаёт — имя и телефон"), filled
renders as a value line with Изменить. The picker stays a picker. One addition the demo
forces: a saved place *carries* its contact (`3e`), so choosing «Склад на Невском» fills the
contact row too, and the common case has no contact step at all.

## Answers to §2.3 — pins and lists

**Q1 — do warehouse/ПВЗ/locker markers show on the picker map?** Only when the suggestion
list surfaces them, plus saved places always. A map of every locker in Moscow is noise in an
app whose job is sending, not finding.

**Q2 — flag or pin for the end?** Pin (`mappin.circle.fill`), per `2c`. A checkered flag
reads as "finish line" — right for navigation, wrong for a place where a human takes a
parcel from a courier.

**Q3 — numbered circles at accessibility sizes.** `3f` ladder: the number keeps its size and
the row grows; address and contact stack; three lines are permitted before truncation.
Truncating an address is never acceptable — a wrong address is a failed delivery.

## Answers to §3.4 — links and coordinates

**Q1 — row or banner?** Row atop suggestions, with a mini-map preview of the resolved point
(`2a`, frame 4). Declined offers do not reappear for the same URL in the same session; the
row is a paste **button**, never an ambient pasteboard scan.

**Q2 — route links with two ends?** One action, "заполнить обе точки", with the two
resolved addresses listed inside the row so the user sees what will be filled. Two separate
suggestions would let someone fill the destination from a route link and silently keep a
stale origin.

**Q3 — recents: timestamp or not?** Not by default. `2a` shows the second line spent on
something more useful: the saved contact, when there is one. Relative time appears only when
it disambiguates two recents with the same title ("был вчера").

## Answers to §4 — route preview

**Q1 — is the info bar the CTA?** No. Keep them apart: the estimate is information, the CTA
is commitment, and merging them makes a failed estimate look like a broken order button.

**Q2 — on estimate failure, does the CTA move?** No. The bar keeps its height and renders
the failure plus Повторить (`1b`, frame 3). Pricing is unaffected; the bar failing must
never look like the order failing.

**Q3 — keep the MKDirections time once real offers arrive?** Replace it. Two times on one
screen, one from Apple and one from the provider, is a bug report waiting to be filed.

## Answers to §5 — permissions

**Q1 — `LocationButton`?** Use the custom row plus the standard flow (`2a`, frame 7). The
picker's "Моё местоположение" row must sit in a list with "Выбрать на карте" and the saved
chips; a system-drawn button cannot match that row's metrics at accessibility sizes.

**Q2 — does reduced accuracy get its own copy?** Yes, one line, because the failure is
silent otherwise: the pin lands plausibly but a kilometre out (`2a`, frame 8).

**Q3 — where does the start city live?** Settings, plus a one-time inline prompt on first
map open for the never-granted cohort.

---

## §6 (new) — What an order actually carries

The dossier treats a point as an address plus a contact. `YandexDeliveryExpressDemo` shows
that is roughly a third of it. This section exists so the visual design is sized for the
real field set rather than discovering it during implementation.

### 6.1 The fields, by group

| Group | Fields | Constraint the UI must carry |
|---|---|---|
| Address | `fullname`, `country`, `city`, `street`, `building`, `porch`, `sfloor`, `sflat`, `doorCode`, `comment`, `coordinates` | `coordinates` is **lon,lat** on the wire; everything else free text. Порч/этаж/квартира are what makes a delivery succeed and are invisible on a map |
| Contact (per point) | `name`, `phone`, `email`, `phoneAdditionalCode` | Phone formats and needs a national mask; extension is a separate field, not part of the number |
| Point | `pointId`, `visitOrder`, `_type` (`source` / `destination` / `return`), `externalOrderId`, `skipConfirmation` | Type is a first-class role — the return point in `2b` is not decoration |
| Item | `title`, `quantity`, `weight`, `costValue`, `costCurrency`, `extraId`, `size{length,width,height}`, `pickupPoint`, `dropoffPoint` | Cost is a decimal **string** with currency; size is in **metres** on the wire and must be centimetres in the UI; each item maps to a pickup and a dropoff point, so items depend on the route existing |
| Requirements | `taxiClass`, `cargoOptions[]`, `cargoType` (`van`/`lcv_m`/`lcv_l`), `cargoLoaders`, `proCourier`, `skipDoorToDoor`, `due` | Interdependent: loaders 0–2 **and only with `cargo`** (the live API answers `409 estimating.too_many_loaders`), `cargoType` only with `cargo`, thermobag only with `courier`, `due` inside a window (the demo uses +1 h … +30 d) |
| Order | `comment`, `shippingDocument` | Free text |

### 6.2 The design consequence

Three rules, drawn in `3d`:

1. **One summary line per group, expanding to typed rows.** The draft screen must stay
   readable in three seconds; the density lives one tap down. This is the difference between
   the demo (every field visible, which is right for a demo) and the app (every field
   *reachable*).
2. **Constraints replace hints.** Where a field is bounded, the bound is the helper text —
   «Грузчиков можно позвать только в „Грузовой" — там от 1 до 2», «От часа вперёд и до
   30 дней». An unavailable option renders disabled with its reason rather than vanishing,
   so the vocabulary stays learnable.
3. **Units belong to the field, never to the user.** Centimetres and kilograms in the UI,
   metres on the wire; currency is a picker; the phone extension is its own field. No
   free-text number ever means two things.

### 6.3 Saved places and history carry data, not coordinates

Your note, and it changes the IA. A saved place (`3e`) stores the whole point: address
parts, default contact, default role in the route, default options. History (`3e`, second
frame) stores the whole order, so «Повторить» refills route, contacts, items and options in
one tap, and «Наоборот» is the swapped variant. Both are local, per `Vision.md`.

Two consequences worth stating out loud before implementation:

- The picker's job shrinks. For habitual senders the common path is chip → done, with no
  typing and no contact step, which is the strongest argument for putting saved chips above
  the suggestion list rather than inside it.
- `Vision.md`'s history phase and this are the same feature. Recents, saved places and
  repeat-order all read one local store of completed points and orders; designing them as
  three surfaces would triple the work and split the truth.

---

## Proposed changes to the dossier's own structure

You invited these. Four, in order of confidence:

1. **Add §6 above** — the dossier's biggest gap is that it researched the *destination*
   interface thoroughly and the *order* barely, so the field set never got sized.
2. **§3.2's grammar table should not live in this document.** It is parser specification,
   not design research: it will outlive the design session, it belongs next to the code that
   honours it, and the dossier is marked transient and meant for deletion. Suggest moving it
   to the package repo as `LinkGrammars.md`, leaving a one-paragraph summary plus the design
   consequence (always human-verify the resolved point) behind.
3. **Split §2.2's table into a token spec.** Same reasoning: `2c` is the version the asset
   catalog is built from, and it should land in `Design.md` rather than evaporating with the
   dossier.
4. **The checklist should carry state.** It is written as unchecked boxes with no owner;
   after this round most of the destination-flow items have a drawn answer and a frame id.
   Suggest a third column — frame reference — so the checklist becomes the handoff index.

---

## Open questions back to you

1. `1b` (fixed card) is my recommendation over `1a`. Does the map deserve a third of the
   screen at all on a screen whose job is filling a form, or should the map appear only in
   the picker and the estimate be text on the draft screen?
2. The return point (`_type: return`) is drawn as a role in `2b`. Is returning the undelivered
   remainder a real flow for your senders, or an API capability that need not surface in v1?
3. Items map to pickup/dropoff points individually. `3d` hides that behind two rows because
   the common case is "everything from A to B" — is that right, or do your multi-point users
   genuinely split items across stops?
4. Currency: the demo offers a picker. Is anything other than ₽ real here, or should it be a
   fixed label until proven otherwise?

---

# Round 2–3 additions

## §7 (new) — What the app is for

See `Positioning.md` for the full prose. The load-bearing conclusion, because it should
settle arguments later: **the unit of work is the order, not the parcel.** The API is
written for shops with integration teams; the people who can actually use it are usually one
person with a phone. Three claims the app can keep — the full tariff range rather than the
consumer subset, orders that outlive the vendor's short history window, and the sender's own
identifiers on every order.

This has a direct design consequence, which is why it belongs in the dossier and not only in
a marketing file: **the sender's order number outranks the vendor's claim id on every
surface** — Live Activity, widget, notification title, Spotlight. It is the string they are
matching against a customer chat.

## §2.3 Q2 — revised: no letters

A and B are withdrawn. They were map-app shorthand carried over without a reason: they mean
nothing, they collide with numbered intermediates, and they need localizing thought at
accessibility sizes. Start is a concentric ring (`smallcircle.filled.circle`), end keeps the
teardrop (`mappin.circle.fill`). Where a row must state the action rather than the position,
`shippingbox.fill` / `house.fill`. Shape and glyph still carry the role; colour only
reinforces. Verify every symbol name in the SF Symbols app against the iOS 17 floor.

## §8 (new) — The map as a second surface

MapKit's rich annotations resolve a tension §1.4 left open. Division of labour:

- The **row** answers *is this the right place* — address, contact, two lines, forever.
- The **callout** answers *what happens when the courier arrives* — entrance, floor, flat,
  door code, comment, contact with a call button, what is going to this stop, and in a live
  order a per-stop timeline with times.

This is what lets the fixed-card shell (`1b`) survive filled rows and long routes without
growing to three lines. The standard callout is too cramped for four chips and a timeline, so
it is an `Annotation` with a custom card. Two rules: tapping a pin highlights the
corresponding row, and a callout is **never the only route to anything** — VoiceOver reaches
the same content through the row's disclosure.

Courier information does **not** go in a compressed row. One courier per order means there is
room for a proper card: name, vehicle with plate, call and message, and the arrival line.

## §9 (new) — Custom fields

Which identifiers matter differs between organizations and is identical inside one, so the
schema is a **setting**, not a per-order chore. Define «Заказ», «Платёж», «Накладная» once;
every draft shows them pre-typed and validated; history is searchable by their values with
the match highlighted in the field where it was found.

Two flags per field:

- `isOptional` — whether the order can leave without it. A required field blocks ordering and
  says so beside the field, never in an alert.
- `isShownByDefault` — whether it sits in the section from the start or waits behind
  «Добавить поле». This is what stops a ten-field schema becoming a ten-row wall for the
  eight orders in ten that need three of them.

Required implies shown: the pair cannot express «обязательное, но скрытое», and the editor
should say so rather than allow it. **«Ваши поля» is a section of its own**, not rows mixed
into the order form.

Three fields can ride along to the carrier (`extraId`, `externalOrderId`,
`shippingDocument`) and become findable in their support; the rest stay local. The UI says
which, once, quietly. Field type drives keyboard and validation — text, number, sum, date,
choice, link.

## §10 (new) — Motion

One rule: **animation reports a state change the user did not cause, or confirms one they
did — never decorates a static screen.** The full table is `4c`. Summary: variable-colour
for the indeterminate «ищем курьера» wait; `.replace` content transition on status change;
`.numericText()` for price landing; `.bounce` on point confirmed and order created;
interpolated coordinate for the courier marker; shake only where the error sits beside the
input. Every row has a Reduce Motion branch, and no celebration effects — the event being
marked is that money moved.

**On Pow:** two effects are worth taking (`.shake`, a price-change effect), both about twenty
lines to write. Recommendation is to skip the dependency and keep the vocabulary in the app
where the Reduce Motion branch is visible in the same file.

**On the deployment target:** everything above exists at **iOS 17**; motion alone does not
justify raising the floor. iOS 18 would add `breathe` — the honest "waiting, nothing is
wrong" idiom — and MapKit's place-detail presentation. Hold at 17 until something structural
wants more.

## §11 (new) — The app is mostly used while closed

Ordering takes ninety seconds; waiting takes forty minutes, and those forty minutes are spent
on the Lock Screen. This section is the one the destination research implied and never drew.
Detail in `5a`–`5d`.

**Live Activity.** A delivery has a definite start, a definite end and a monotonic status —
exactly the shape the surface is for. Content priority: where is it now, when will it be
there, who to call. Seven states, two of them final and only one of which auto-dismisses:
failures stay until tapped, because they are what the sender must act on. No live map — a
dashed remainder plus an ETA carries the same information for none of the battery. Note the
constraint: **push-to-start and ActivityKit updates need a server the app does not have**, so
the activity starts locally on order creation and updates when the app polls. Show «в 9:41»
rather than a ticking timer, to avoid implying precision that isn't there.

**Widgets.** Two jobs. *Waiting* — the active delivery, so the Home Screen answers "where is
it". *Working* — repeat a saved route, opening a pre-filled draft. A widget tap must never
move money, and the empty state offers «Повторить» rather than "no orders".

**Notifications.** While an activity is on screen, routine progress needs no push. Push only
for: courier assigned, courier at the door, delivered, and the two failures. Order number in
every title. Group by order via `threadIdentifier` so five events don't become five banners;
failed delivery is `.timeSensitive`, delivered is not. The expanded view is a content
extension with a route snapshot and actions — call, return to me — so the sender need not
open the app.

**Ways in.** The Share Sheet answers §3.4 better than any paste affordance: senders receive
addresses in chats, so sharing a place or an address into the app opens a draft with that
point filled. Three App Intents, not thirty: «где моя доставка», «повторить доставку в …»,
«отправить по заказу …». Spotlight indexes completed orders by custom-field value, so typing
«4417» finds the delivery — the payoff of §9 that lives entirely outside the app.

**Sharing outward.** The recipient wants to know where their parcel is, and today that is
manual retyping. Share plain text, not an app link — the recipient installs nothing.

## §12 (new) — The shared component set

Widgets and Live Activities cannot import the app target, so anything shared lives in a local
package below both. Membership test: *does it render from plain values with no controller, no
network, no environment?* Five pass, and they are the five that appear on every surface:
`StatusChip`, `RouteLine`, `PointBadge`, `ETALabel`, `OrderIdentity`.

Three consequences worth deciding before implementation, not after:

1. Each takes a `size` of compact / regular / expanded rather than reading Dynamic Type
   directly — a widget cannot grow, so it must shrink content instead.
2. The asset catalog moves into the same package, or the widget's green drifts from the
   app's. Widgets render on unpredictable backgrounds: every token needs light and dark, and
   none may depend on the app's material.
3. **The order store belongs in an App Group from day one.** Widgets read it directly, and
   retrofitting this after the Keychain and history exist is the expensive version of the
   decision.

## §13 (new) — HIG audit

Six findings, ordered by cost to fix later. Full text in `5f`. The two structural ones:

1. **The tab bar is wrong.** «New Delivery» is an action, and tabs are for peer locations,
   not verbs — it also means a tab switch destroys the draft. Proposal: two tabs (Доставки,
   Настройки) with a prominent «Новая доставка» on the list, presenting the flow modally. It
   follows the compose idiom and makes the draft's lifetime legible.
2. **Ordering is irreversible and nothing acknowledges it.** Money moves and a courier is
   dispatched. It needs a review sheet restating route, price and tariff — which is also the
   natural home for the required-custom-field check from §9.

Then: contact fields must declare `textContentType` and offer the Contacts picker, since a
sender is always copying details from somewhere; offline is a normal condition rather than an
error, so history and saved places must be fully readable without network and a draft must
survive being written in a basement; the map needs a VoiceOver *equivalent* rather than a
label; and the small standard wins — swipe actions on history rows, context menu on a saved
place, `.searchable` on Доставки, and the regular-width layout where the fixed card becomes
map-left / card-right.

## Open questions from rounds 2–3

1. **Does the API's journal feed actually carry courier coordinates?** The moving marker in
   `4a` and the route progress in `5a` both assume it does. If it only carries status
   transitions, both become status-only and the design still works — but I should know before
   drawing more of it.
2. **Is the tab-bar change welcome?** It touches shipped structure (`RootView`), so it is a
   recommendation rather than an edit.
3. **Inbound tracking** — the "orders coming to me" idea. It cannot be live, only
   record-keeping. Worth a round, or park it?
4. **iPad.** Worth designing the regular-width layout in this session, or is iPhone the whole
   product for now?
