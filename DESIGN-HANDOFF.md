# Design handoff — destination & ordering UX

**From:** design session, August 2026
**For:** the next code session, and `Design.md`'s permanent record
**Status:** decisions are settled unless marked ⟡ open. Frame ids reference the boards listed below.

---

## 0. How to use this package

Six board files, three documents. The boards are the argument; the documents are the residue
that should outlive them.

| File | Goes to | Keep? |
|---|---|---|
| `DESIGN-HANDOFF.md` (this) | repo root, or `Documentation.docc/` | until implemented, then fold into `Design.md` |
| `Positioning.md` | repo root | permanent — it is the README's and store page's source |
| `Dossier-Update.md` | merge into `Design-Research-Dossier.md` | dies with the dossier |
| `YDelivery — Shipped Today.dc.html` | `design/` | reference: the "before" |
| `Round 1 - Route & Ordering.dc.html` | `design/` | until the draft screen ships |
| `Round 1 - Picker & Points.dc.html` | `design/` | until the picker ships |
| `Round 1 - Tariffs, Fields & XL.dc.html` | `design/` | until parcel/options ship |
| `Round 2 - Callouts, Custom Fields & Motion.dc.html` | `design/` | until custom fields ship |
| `Round 3 - System Surfaces.dc.html` | `design/` | until widgets/activity ship |
| `Round 4 - Capture, Color & Keyboard.dc.html` | `design/` | colour + keyboard parts are permanent |

Boards need `support.js` beside them to open. Download the whole design project and drop the
folder in as `design/` — that keeps every board working offline with no bundling step.

**What to lift into permanent docs, once:** the semantic colour table (§5), the pin/badge
spec (`2c`), the field taxonomy (§4), and the motion table (`4c`). Those four outlive the
boards and belong in `Design.md`.

---

## 1. Kick-off prompt for the code session

Paste this verbatim. It is written to be read before any file is opened.

> You are picking up YDelivery after a design session. Read in this order: `Positioning.md`
> for what the app is, `DESIGN-HANDOFF.md` for the decisions and the build order, then
> `Design.md` and `Vision.md` for the house rules that still apply. The `design/` folder has
> the boards; open them in a browser rather than reading their markup.
>
> Two framings to hold onto. **The unit of work is the order, not the parcel** — the sender's
> own order number outranks the vendor's claim id on every surface. And **the app is mostly
> used while it is closed** — ordering takes ninety seconds, waiting takes forty minutes, and
> those forty minutes happen on the Lock Screen.
>
> Start with Phase 1 in §7 of the handoff, which is deliberately structural and touches
> shipped code: the tab bar goes, `NewDelivery` becomes a modal flow, and the order store
> moves into an App Group. Do that before any new screen, because both later phases assume
> it. Do not start with the pretty parts.
>
> Three things are drawn but explicitly deferred — scan-to-fill (`6a`), the Live Activity
> (`5a`), and inbound tracking. Deferring them leaves no hole in the UI by design; do not
> stub them.
>
> The open questions in §9 are real. The first one — whether the journal feed carries courier
> coordinates — determines whether the moving-courier marker and route progress are buildable
> at all. Answer it from the API before implementing anything that assumes it, and if the
> answer is no, both surfaces degrade to status-only and that is a fine outcome.
>
> Where this handoff and `CLAUDE.md` disagree about code structure, `CLAUDE.md` wins; tell me
> so I can fix the handoff.

---

## 2. The three decisions that shape everything else

### 2.1 Fixed card, not a bottom sheet (`1b` over `1a`)

The map sits on top, the route card below it never moves, and both are fully readable without
a gesture.

*Rationale.* Two independent reasons converged. Yours: delivery classes must be visible
before pricing, because courier / car / truck is not a payment choice — it changes the route
that gets calculated. Mine, from reading your demo: a saved place carries a contact, so every
filled route row is two lines, and routes reach five and ten points; a sheet you must drag to
read the route is the wrong container for that. It is also the safer shell at accessibility
sizes, and the repo's own 2GIS reference argues for it.

*Rejected.* The map-first taxi shell (`1a`). It is the better shell for courier-hailing, where
the user is the one travelling. Kept on the board because if the product ever moves that way,
the argument is already written.

*Cost accepted.* Price must land in a strip that is already on screen, so the strip needs an
honest waiting state and a failure state that does not collapse the layout. Both drawn in `1b`.

### 2.2 A point carries data, not coordinates

A saved place stores address parts, a default contact, a default role in the route, and
default options. History stores the whole order, so «Повторить» refills route, contacts,
items and options in one tap.

*Rationale.* Your note, and it changes the IA rather than adding a feature. The picker's job
shrinks: for habitual senders the common path becomes chip → done, with no typing and no
contact step. It also collapses three features into one — recents, saved places and
repeat-order all read one local store of completed points and orders. Designing them as three
surfaces would triple the work and split the truth.

### 2.3 The tab bar goes

Two tabs (Доставки, Настройки) and a prominent «Новая доставка» presenting the flow modally.

*Rationale.* «New Delivery» is a verb, and tabs are for peer locations — but the practical
reason is that a tab switch currently destroys the draft, silently. The modal presentation
makes the draft's lifetime legible, and it is what makes ⌘N meaningful at regular width. You
had already avoided this pattern in the demo; this is the shipped app catching up.

*Touches shipped code:* `RootView.swift`. Hence Phase 1.

---

## 3. Decision ledger

Compact, for scanning. Every row has a frame you can look at.

| # | Decision | Frame | Alternative rejected |
|---|---|---|---|
| 1 | Fixed route card; map above | `1b` | Bottom-sheet taxi shell `1a` |
| 2 | Tariff strip on the card, waiting state included | `1b` | Sheet after both ends resolve |
| 3 | Beginner explainer = vertical list, auto-open until first order | `3a` | Paged cards `3b` (dies at XL) |
| 4 | Expand-in-strip is the *expert* affordance, kept | `3c` | — |
| 5 | Contacts on the draft screen, collapsed row per point | `1b`, `2b` | Inside the picker |
| 6 | Search-first picker, map one row away, never a mode | `2a` | Map-first picker |
| 7 | Saved chips above suggestions, not inside | `2a` | Mixed list |
| 8 | Paste = explicit button + verifiable point preview | `2a` | Ambient pasteboard scan |
| 9 | Route links fill both ends in one action | `2a` | Two separate suggestions |
| 10 | Recents show contact, not timestamp | `2a` | Relative time always |
| 11 | Pins: ring for start, teardrop for end, numbers between; **no A/B** | `2c` | Letter badges (meaningless, collide with numbers) |
| 12 | Shape + glyph carry role; colour reinforces only | `2c` | Colour-primary encoding |
| 13 | Estimate bar ≠ CTA; failure keeps its height | `1b` | Merged info/action bar |
| 14 | Replace MKDirections ETA when provider offers land | — | Show both (two times = bug report) |
| 15 | Custom fields defined once per org, own section, two flags | `4b` | Per-order ad-hoc fields |
| 16 | Three custom fields ride to the carrier; UI says which | `4b` | Silently local, or silently sent |
| 17 | Map callouts carry per-stop detail; rows stay two lines | `4a` | Three-line rows |
| 18 | Courier gets a full card, not a compressed row | `4a` | Taxi-style one-liner (wrong: one courier per order) |
| 19 | Motion reports state changes only; no celebration effects | `4c` | Pow's broader catalogue |
| 20 | Hold iOS 17 | `4c` | 18 for `breathe` alone |
| 21 | Live Activity: 7 states, failures do not auto-dismiss | `5a` | Uniform dismissal |
| 22 | Two widgets: waiting, working. Never orders from a tap | `5b` | Price-only widget |
| 23 | Push only for actionable events; thread per order | `5c` | Push every transition |
| 24 | Status change = new notification; refinement = replace last | `5c` | Always new, or always replace |
| 25 | Parcel photos as attachments: thumbnail collapsed, carousel expanded | `5c` | Text-only notifications |
| 26 | Share-in fills a draft point | `5d` | Paste affordance alone |
| 27 | Three App Intents, not thirty | `5d` | Exhaustive intent surface |
| 28 | Spotlight indexes orders by custom-field value | `5d` | In-app search only |
| 29 | Five shared components in a package below app+widget | `5e` | Duplicated views |
| 30 | Semantic colour set, named by meaning | `6b` | Hex per call site |
| 31 | `ViewThatFits` candidate lists; no `size` parameter | `6d` | Parameterised layouts |
| 32 | Scan-to-fill: recognition proposes, sender confirms per field | `6a` | Auto-fill on scan |
| 33 | Regular width = iPad **with keyboard**; Mac follows | `6c` | Phone-only |
| 34 | Review sheet before ordering | `5f` | Direct order button |

---

## 4. Field taxonomy → UI

Your demo made this visible and the research half had under-counted it. Three rules, drawn in
`3d`.

1. **One summary line per group, expanding to typed rows.** The draft must be readable in
   three seconds; density lives one tap down. The demo shows every field because it is a demo;
   the app must make every field *reachable*.
2. **Constraints replace hints.** Where a field is bounded, the bound is the helper text.
   Unavailable options render disabled with their reason rather than vanishing, so the
   vocabulary stays learnable.
3. **Units belong to the field.** Centimetres and kilograms in the UI, metres on the wire.
   Currency is a picker. The phone extension is its own field. No free-text number ever means
   two things.

Interdependencies that must be enforced in the UI, not discovered via API errors:

- loaders 0–2, **and only with `cargo`** (live API answers `409 estimating.too_many_loaders`)
- `cargoType` only with `cargo`
- thermobag only with `courier`
- `due` inside the provider window (+1 h … +30 d)
- `coordinates` are **lon,lat** on the wire — the one ordering bug that produces a plausible
  wrong answer instead of an error

Keyboard and autofill per field type: `textContentType` on every contact field, plus
`.phonePad`, `.numberPad` for flat/floor, `.decimalPad` for weight/cost. A sender is always
copying from somewhere.

---

## 5. Semantic colours

Named by meaning so no hue name appears in a diff. Asset catalog, light + dark, compile-time
symbols. Every status pairs colour with glyph **and** words.

| Token | Means | Glyph · words |
|---|---|---|
| `statusDraft` | nothing sent | — · «Черновик» |
| `statusSearching` | waiting for a courier | ◌ variable colour · «Ищем курьера» |
| `statusActive` | en route, on plan | ◉ · «Курьер едет» |
| `statusDone` | delivered | ✓ · «Доставлено» |
| `statusAttention` | needs a decision | ⚠ · «Не вручили» |
| `statusCancelled` | closed, undelivered | ✕ · «Отменён» |
| `pointStart` | pickup | concentric ring |
| `pointEnd` | drop-off | teardrop |
| `scanConfident` | recognised | ✓ solid outline |
| `scanUncertain` | check this | dashed outline · «проверьте» |

Two rules: a status colour never appears without glyph and words; `statusAttention` is for
decisions, and a network failure is a retry, not attention. Values are deliberately darker
than `.systemGreen`/`.systemRed` where text sits on them — verify AA at 13px, the tight case.
The set lives in the shared package, or the widget's green drifts from the app's within two
releases.

---

## 6. Shared package

Widgets and Live Activities cannot import the app target. Membership test: *does it render
from plain values, with no controller, no network, no environment?*

```
YDeliveryKit/            (local package, below app + widget + activity)
  StatusChip             status → colour, glyph, text
  RouteLine              points + progress → dots, teardrop, solid/dashed
  PointBadge             role + index → 2c shape/glyph pair
  ETALabel               date + confidence → «в 9:41» / «~14 мин» / «обычно 3–7 мин»
  OrderIdentity          custom fields → sender's own order number
  Colors.xcassets        the §5 set
```

Each is a `ViewThatFits` candidate list, authored **most complete first**, with the last
candidate the irreducible minimum that cannot overflow. Authoring order is the priority
ranking — that is where the design decision lives.

**The order store belongs in an App Group from day one.** Widgets read it directly.
Retrofitting after Keychain and history exist is the expensive version of this decision, and
it is the single most consequential line in this document.

---

## 7. Build order

Each phase ends somewhere shippable.

### Phase 1 — structure (touches shipped code)
- Two tabs; `NewDelivery` becomes a modal flow. Draft survives dismissal.
- Order store into an App Group; `YDeliveryKit` created with the colour set and `StatusChip`.
- Local store of completed orders and points — the one substrate for recents, saved places
  and repeat.
- `textContentType` + keyboard types on every existing field.

*Done when:* nothing looks new, the draft cannot be destroyed by navigation, and a widget
target could read the store if it existed.

### Phase 2 — the draft screen (`1b`, `2a`, `2c`, `3a`, `3d`)
- Fixed card: map above, route rows with `pointStart`/`pointEnd` badges, collapsed contact
  rows, swap, add point.
- Picker: saved chips, recents with contacts, choose-on-map, confirm-pin with address parts.
- Estimate bar (information, never the CTA) with its failure state.
- Tariff strip with waiting/failed states; vertical beginner explainer auto-opening until the
  first successful order.
- Parcel and options with constraint-as-hint and the interdependencies from §4.
- Review sheet before ordering.

*Done when:* a sender can complete a real order without typing an address twice, and every
bounded field states its bound.

### Phase 3 — while closed (`5a`–`5d`, `4b`)
- Custom fields: settings schema, two flags, own section in the draft, Spotlight indexing.
- Live Activity, seven states, started locally on order creation. ⟡ gated on §9.1.
- Two widgets. Three App Intents. Notification thread rules and parcel-photo attachments.
- Share-in extension.

*Done when:* a sender learns their courier arrived without opening the app.

### Phase 4 — regular width (`6c`)
- Sidebar + detail; map inside the detail; the shortcut set; focus order.
- ⟡ decide whether multiple drafts can be open (§9.4) before building windows.

### Deferred, deliberately
Scan-to-fill (`6a`) — the screen is absent, not stubbed; manual entry stays a complete path,
so this carries no UI debt. Inbound tracking — record-keeping only, and it should ship only if
useful without pretending to be live tracking.

---

## 8. Accessibility

Better done live than drawn, and the code session can drive the app with the screen curtain on
and find more than a mock will show. The design intent to check against:

- The map is an accelerator, never the only route. Every callout's content is reachable
  through its row's disclosure.
- The tariff strip is a set of choosable elements whose **limits belong in the label**, not the
  hint — otherwise choosing a tariff is guesswork.
- Confirm-pin announces the resolved address, and announces corrections when the pin moves.
- A required custom field announces itself at the field. Ordering never fails silently.
- Addresses may run to three lines before truncating. Truncating an address is never
  acceptable: a wrong address is a failed delivery.
- Reduce Motion branch for every row of `4c` — the table names each one.

---

## 9. Open questions ⟡

1. **Does the journal feed carry courier coordinates?** Blocks the moving marker (`4a`) and
   route progress (`5a`). If it is status-only, both degrade cleanly to status — but know
   before building.
2. **Is the return point (`_type: return`) a real flow** for your senders, or an API
   capability that need not surface in v1? Drawn as a role in `2b`.
3. **Do items genuinely split across stops?** `3d` hides per-item point mapping behind two
   rows because the common case is everything from A to B.
4. **Multiple drafts at once on Mac?** iPhone says no; desktop users will expect windows.
   Model decision, not layout.
5. **Currency:** a picker, or a fixed ₽ label until proven otherwise?

---

## 10. Dossier structure — proposals

1. Merge `Dossier-Update.md`, which adds §6–§13 and answers every open question in §1.5,
   §2.3, §3.4, §4 and §5.
2. **Move §3.2's link-grammar table out** to the package repo as `LinkGrammars.md`. It is
   parser specification, not design research; it will outlive the design session; and the
   dossier is marked transient. Leave a paragraph plus the design consequence — always
   human-verify the resolved point.
3. **Promote `2c` and §5 of this document into `Design.md`.** They are what the asset catalog
   is built from and should not evaporate with the dossier.
4. **Give the checklist a frame-reference column** so it becomes the handoff index rather than
   a list of unchecked boxes with no owner.
