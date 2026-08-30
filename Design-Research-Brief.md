# Design research brief — YDelivery's destination & ordering experience

**For:** a design-research session (Claude Design or equivalent).
**From:** the implementation session, after the first shipped slice (route picking) and the
author's review of it.
**Transient:** consumed into `YDelivery/Documentation.docc/` (Vision/Design) once answered,
then deleted — the sibling repos' `HANDOFF.md` convention.

## What exists, so you design against reality

An iOS 17+, Swift 6 SwiftUI app over the Yandex Delivery Express (B2B Cargo) API. Shipped
today: a two-end route draft; a picker sheet with `MKLocalSearchCompleter` autocomplete,
tap-to-pin + reverse geocode, editable resolved address; Keychain auth. Direction docs live
in `YDelivery/Documentation.docc/` (read `Vision.md` first — the capability map bounds what
the API can do). The API's own vocabulary (claims, offers) must never surface in UI copy.

## The design questions, in priority order

### 1. The destination interface of a great courier app

Design the end-to-end "set the route" experience benchmarked against the best taxi/nav apps
(Yandex Go, Uber, Bolt, 2GIS, Яндекс.Карты). Reference screenshots in
`design/ref/`:

- `2gis-search-home.png` — search sheet over the map: saved-place chips (Home/Work +
  bookmarks) directly under the field.
- `2gis-route-transport-tabs.png` — the **Проезд** pattern we want re-phrased: from/to
  fields with colored end-dots and drag handles, and a one-row strip of transport
  pictograms. Re-read that strip as **tariff classes** (courier / express / cargo sizes…):
  minimal estate, instant switching, price implications visible.

Deliverables: flows + states for (a) a laconic expert mode — the pictogram strip; (b) an
explicit beginner mode — cards that explain each tariff/option (loaders, thermobag, door-to-
door) with constraints surfaced; and the rule for when the app shows which.

### 2. Route list as a first-class object

Multi-point routes (API supports A→B1…BN): reordering by drag, swapping ends, insert/remove
mid-points. Pin taxonomy on the map AND in lists — start / intermediate / end must read at a
glance; warehouse, pickup-point ("self-delivery"), door-to-door, drop-in/drop-out get
distinct pictograms/badges/colors. Propose the visual system (shapes + SF Symbols + color
tokens), including color-blind legibility.

### 3. Getting coordinates every way users actually have them

- Free-text address → coordinates (autocomplete exists; design the fallout states).
- **A pasted link**: Yandex Maps / Google Maps / 2GIS point URLs, and raw `geo:`/coordinate
  strings — different providers, different formats. Design the paste affordance ("looks like
  a map link — use this point?") and the failure copy. (Implementation will parse
  coordinates from URLs; itemize which forms the design promises.)
- Saved places (Home/Work/warehouses) and **recents**: recents must resurface inside new
  searches (клок-badged rows as in 2GIS), and saved warehouses/pickup points must appear
  both as map pins and as badged rows in the suggestion list.

### 4. Route preview before price

After both ends exist and before offers are requested: show the route polyline
(`MKDirections` estimate), distance, and rough drive time — the "am I about to price the
right trip?" check. Design where this lives (picker? draft screen? both?) and its
loading/error states.

### 5. Location permission, the considerate way

The map should start from the user's position when allowed, an explicit setting otherwise.
`NetworkObserverSample` (this machine,
`/Users/paul/Documents/Code/Network/NetworkObserverSample/docs/`) holds our house pattern
for permission acquisition UX — pre-permission explainer, denial as a rendered state, no
prompt-on-launch ambush. Adapt it for When-In-Use location.

## Constraints the design must respect

- iOS 17 floor; SwiftUI-native components; semantic colors/typography only (Dynamic Type to
  accessibility sizes — the NetworkObserver handoff response documents how mockups failed
  there; design AT `accessibility-extra-large`, not just default).
- Unofficial app: no Yandex branding, name, or iconography.
- Yandex is the only provider **today**; nothing in the IA may hard-code "the one
  provider" (a provider column exists in history, tariff strips are per-provider data).
- Every screen must be previewable from literals — content views take plain values.

## What to return

Frames or structured prose per question, states included (empty/loading/error/accessibility-
XL), plus the SF Symbol + color-token proposals for the pin taxonomy. Answers land in
`Vision.md`/`Design.md`; anything cut, say why so the register can record the rejection.
