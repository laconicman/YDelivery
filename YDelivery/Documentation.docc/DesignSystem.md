# Design System

The four specifications from the 2026-08 design session that outlive its boards: what the
asset catalog, the pin badges, the field forms, and every animation are built from. Frame
ids (`2c`, `4c`, …) reference the boards in `design/`; the boards argue, this records.

## Semantic colors

Named by meaning so no hue name appears in a diff. Asset catalog, light + dark, compile-time
symbols. The set lives in the shared package (`YDeliveryKit`) once it exists — or the
widget's green drifts from the app's within two releases.

| Token | Means | Glyph · words |
|---|---|---|
| `statusDraft` | nothing sent | — · «Черновик» |
| `statusSearching` | waiting for a courier | ◌ variable color · «Ищем курьера» |
| `statusActive` | en route, on plan | ◉ · «Курьер едет» |
| `statusDone` | delivered | ✓ · «Доставлено» |
| `statusAttention` | needs a decision | ⚠ · "Needs a decision" |
| `statusCancelled` | closed, undelivered | ✕ · «Отменён» |
| `feedbackBound` | a precondition owed — the `bound` role's glyph and words | `exclamationmark.circle` · bound line |
| `feedbackWarningText` | words for the `warning` role — its glyph keeps `.orange` | `exclamationmark.triangle` |
| `feedbackErrorText` | words for the `error` role — its glyph keeps `.red` | `exclamationmark.triangle` or the cause's own glyph |
| `pointStart` | pickup | concentric ring |
| `pointEnd` | drop-off | teardrop |
| `scanConfident` | recognised — UI text and outlines | ✓ solid outline |
| `scanUncertain` | check this — UI text and outlines | dashed outline · «проверьте» |
| `scanOverlayConfident` | recognised — viewfinder overlay only | ✓ solid outline |
| `scanOverlayUncertain` | check this — viewfinder overlay only | dashed outline |

Two rules: **a status color never appears without glyph and words**; and `statusAttention`
is for *decisions* — a network failure is a retry, not attention. The chip's words name
the family's truth, so where the collapsed family hides a materially different provider
state, the provider's own phrase rides beside the chip: a claim parked at
`ready_for_approval`, one refused before dispatch, and a delivery that failed en route
are all `statusAttention` — only `ProviderStatusPhrase`'s words tell them apart (the
`.attention` rows render `Order.statusDetail`; collapsed status alone was the device
drive's D2 finding). Values run deliberately
darker than `.systemGreen`/`.systemRed` where text sits on them; verify AA at 13 px, the
tight case, **measured against the surface the words actually sit on** — the chip's 12%
tint, not the naked background (designer confirmation, 2026-08-30).

A third rule, the general form of a bug the scan tokens carried: **a token that renders
both as a graphic on dark chrome and as text on light gets two entries, not one clever
value** (designer, 2026-08-30). The overlay pair keeps the bright system values at the
3:1 graphics threshold — safe for pins and outlines because shape and glyph carry the
role, so poor contrast loses emphasis, never meaning. The UI pair holds AA for text in
both modes: light `#14682F`/`#8A5A00` matching the 6a results screen; dark reusing
`statusDone`/`statusSearching` dark values rather than inventing more. Confidence must
survive greyscale: solid versus dashed outline, plus the word.

### Implementation approach (house precedent)

Per the author's `SwiftUI/Themes` project (Multi-Theme App with Namespaces; the
controller-owned selection traces to Manferdini's SettingsController note in the vault):
**asset-catalog compile safety needs no third-party generator.** Colorset folders marked
`provides-namespace` plus Xcode's generated asset symbols
(`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`, already on in this project)
yield nested compile-time symbols — `.Blaze.Text.primary` in that project; here, a flat
single-theme set reads `Color(.statusActive)` with a typo being a build error, not a blank.

For `YDeliveryKit`: the catalog lives in the package (generated symbols work in SwiftPM
targets since Xcode 15, resolving against `Bundle.module` — which is exactly what keeps the
widget's green identical to the app's), tokens stay flat while there is one theme, and the
namespace mechanism is the growth path if theming ever becomes a feature — the Themes
project shows that shape working, `ThemeManager` modernizing to an `@Observable` controller
per this app's rules.

## Feedback roles (semantics session, 2026-10)

Status colors describe *orders*; feedback roles describe *sentences the UI says to the
sender*. Six roles, named by meaning; each owns a chrome shape, and the hue-bearing ones
split the way the scan pair already did — the glyph keeps the bright system hue (non-text
graphics clear at 3:1), the words take the AA-darkened text token. **A role's color never
appears without its glyph or its words** — the chip's rule generalized.

| Role | Means | Chrome |
|---|---|---|
| `info` | guidance, provenance, invitations, empty states | footnote `.secondary`; glyph only where scanning needs it — carries no hue |
| `bound` | a precondition, visible *before* it is broken — never an error | `Notice(.bound)` — attention-family `exclamationmark.circle` + words beside the field, in the section footer, on the item's or the stop's row, or on the gate's next-step line |
| `warning` | proceedable-but-risky; an outcome that came back uncertain | `Notice(.warning)` — triangle + `feedbackWarningText` words |
| `error` | an action tried and failed — a write, a command, a refusal | `Notice(.error)` — triangle or the cause's own glyph + `feedbackErrorText` words; the action sits beside it |
| `success` | the outcome the sender wanted | `checkmark.circle.fill` + status words — or the status the outcome enters (`ReviewSheet.placed` wears `statusSearching`; a landed cancellation wears `statusCancelled`, never a green ✓) |
| `destructive` | a verb, never a message | `Button(role: .destructive)` only — system red lives on controls and never tints text |

The boundary that does the work is `bound` vs `error`: a bound is the shape of the form,
true whether or not the sender has looked; an error is something that *happened*. Red for
"you haven't typed yet" is alarm fatigue — and `.red` text fails AA at footnote size
(≈3.6:1, measured; the dark variants pass, so the text tokens exist).

**The read/write split.** A failed *read* is not an `error`: the surface keeps its shape,
the message stays `.secondary`, an in-place Retry sits beside it, and the triangle — kept,
a failed read must not read as an empty one — stays quiet. Where the whole surface is the
content, `ContentUnavailableView` carries it. A failed *write* or command is `error` and
gets the chrome row. An *unknown* answer is `warning` — the provider may have applied it,
so the retry is a read ("Check again"), never a resend. A terminal refusal that must
interrupt takes `.alert(error:)`, sparingly; the row is for failures the sender can act
on in place.

### Placement grammar — whose bound it is decides where the sentence sits

1. **A bound states itself where the decision is made** — the field that carries it, the
   footer of the section whose membership it constrains, the gate's next-step line when
   the bound spans sections. A blocker first discoverable at the review sheet is a
   design bug — the sheet lists none (controls session, 2026-10-05).
2. Per-field bounds sit beside the field — and per-*item* on the item's row, per-*stop*
   on the stop's row (a stop that carries nothing says so); per-section bounds sit in
   the section footer ("Prices appear when the route is complete." is the model);
   order-level bounds are the gate's — the bar's line names the first and counts the
   rest.
3. **The gate is the union, not the source.** Every bound the bar counts also exists at
   its owning surface, and the bar's tap is the door to the first. (The review sheet
   held this role until 2026-10-05; it now opens only when nothing is owed.)
4. **Footers state bounds and consequences; trivia lives at the field it explains.**
5. **An unavailable option stays visible and names its reason.**
6. **An answered bound is quiet** — silence is the answered state; the marker persists,
   the bound line leaves.
7. **Trailing edge: timestamps and accessories trail, content leads.**

### The canonical failure row

`Notice` (`YDeliveryKit`) owns the row: cause-specific glyph where one exists
(`.wifiSlash` for a dead connection), words stating plainly what failed — the
`LocalizedError` contract guarantees a filled `errorDescription` — and the honest next
step beside it: "Try again" for a retryable write, "Check again" for a re-read, "Open
Settings" for a refusal only Settings can fix, nothing for a bound. **"Share diagnostics"
attaches where a wire exchange is implicated** — inline where the error is the content,
a "details in Settings → Diagnostics" footnote elsewhere; never to local validation or
pure storage failures (the log holds requests and responses, nothing about a disk write).
Chrome localizes to the app's language; user and provider vocabulary stays verbatim,
quoted where interpolated.

### The gateway — the bar and the sheet (controls session, 2026-10-05)

The compose screen's one standing action is a *gate*, and the bar names its
destination, never a promise it cannot keep: «К оформлению» ("Check out"; the sheet it
opens is «Оформление заказа», "Checkout"). Three states:

- **Hidden** while no prices were asked for — no route, nothing to go to.
- **Blocked** while a bound is owed: the `bound` role's look — the capsule in the
  neutral tint (`.bordered`, large), no accent fill, `exclamationmark.circle` in the
  bound tint leading, the destination's words in `.primary`, and beneath them inside the
  same capsule the next step with the count of the rest — «Укажите ценность вещи · ещё 2».
  It is *not* disabled: a tap scrolls the card to the first owed bound and shakes it.
  Every blocker therefore carries a short imperative *step* beside its full sentence —
  the sentence stays on the row, the step feeds the bar and the rotor hint.
- **Ready**: «К оформлению · 1 890 ₽» — destination first, the price as the fact. The
  tap opens the sheet.

The review sheet owns **consent and the run**, nothing else: route, parcel, options,
class and price restated once; the one verb that orders — «Заказать за 1 890 ₽» ("Order
for 1 890 ₽") — then placing · pricing · confirming · placed · failed (with #106's
re-price disclosure) · unresolved. It has no blocked state: a sheet that opens on a
blocked order is a bug, because every bound is stated on the card and the bar points at
the first. *Supersedes* semantics ruling #3 (the enabled «Review the order» whose sheet
listed the bounds) — the card is where blockers explain themselves now.

**A control that cannot act states its reason on the same surface.** `DescribeContent`'s
disabled Save with `saveUnavailableReason` beneath it was the precedent; the bar
generalizes it. A control that swallows a tap with no reason beside it is the device
drive's dead CTA; one that looks ready while the order is not is its mirror image.

The look of the primary verb is one recipe with one name — `Button.primaryAction()`
bundles bordered-prominent, large, headline, full width (a `ButtonStyle` could not keep
the system's capsule); sites add only edge padding.

## Control roles (controls session, 2026-10-05)

Feedback roles describe sentences; control roles describe *shapes that act*. Each role
owns one recipe with one name (`YDelivery/Features/Button+Roles.swift`); a site picks the
role, never the style — **a bare `.buttonStyle(…)` in a feature file is the smell**
(REVIEW.md). The test is the pin table's: a control and an indicator of one silhouette
must still read apart with color removed. Survey, inventory and reasoning:
<doc:DesignSystemControls>.

| Role | Means | Recipe · name | Seat |
|---|---|---|---|
| primary action | the screen's one standing verb | bordered-prominent, large, headline, full width · `primaryAction()` | the bottom inset («New Delivery», the gate), the sheet's verb |
| secondary action | the quieter choice beside a primary | `.bordered`, large, full width · `secondaryAction()` | only in an action stack under a primary («Close», «Leave it for now») |
| card actions | two or three verbs on a card outside a `List` | `.borderedProminent` + `.bordered`, regular size, side by side, `actionSpacing` apart · `leadCardAction()` + `cardAction()` | the paste and location cards, the map callout |
| action row | the whole row is the verb | tinted words (+ glyph), the List's default style, **alone in its row** | Settings' Sign In / Sign Out, «Share with the recipient», «Save as a template» |
| add row | an action row whose verb is *add* | `plus` glyph + verb, alone in its row — one per section | «Add stop», «Add an item», «Add field» |
| header action | arranges, filters, or opens a library *for* the section — never a member of it | footnote `Button`/`Menu`, trailing in the section header · `headerAction()` | Sort · ⓘ on «Delivery options»; Swap · Reorder on «Route»; «From library» on «What's inside» |
| row door | the row opens its subject | `.plain` whole row (or a `NavigationLink`), trailing `chevron.forward` `.tertiary`, content never tinted · `rowDoor()` | «Options», item rows, Library rows, field rows |
| prompt door | a row door not yet answered | its prompt in `.tertiary`, a `plus` glyph where the verb is *add*, untinted (field rule 4) · `promptDoor()` | «Where to deliver?», «Who receives — a name and a phone» |
| bound door | a bound line that is also the door to the editor answering it | the `bound` notice as its label, untinted · `boundDoor()` | a stop that carries nothing (<doc:DesignSystemControls> → "Prompts versus bound lines") |
| chip-as-control | a capsule that acts — expands, filters, picks | `StatusChip(status:disclosure:)`: `chevron.down` *inside* the capsule, up when open, a mini spinner while the read is out | the Deliveries row's chip |
| chip-as-indicator | a capsule that reports | glyph + words, never a `Button`, never a chevron | `StatusChip` on the detail header, in widgets |
| selectable card | one of several, chosen | `.plain` card with the accent selection stroke | `TariffCard` |
| destructive verb | see the feedback roles table | `Button(role: .destructive)` | Cancel, Delete, Sign out |

Two rules: **a tinted word is a whole row, a header control, or a capsule — never a
fragment of a content row** (a fragment becomes a prompt or leaves for the header); and
**a row door carries its chevron whatever it opens** — the mark means "this row opens",
not "this row pushes", so a sheet-opening row and a pushing row read the same.

*Held in reserve:* one row per action (Settings-style, nothing shares a row) — the most
Apple-default and the tallest; the add row already is it for one action, so adopting it
wholesale is a move of two buttons, not a redesign (<doc:DesignSystemControls>).

## Lists and rows (controls session, 2026-10-05)

- **One list style per screen** — inset-grouped, every section a card. A row's selection
  or highlight tint layers *over* the card background (the grouped color with the tint
  on top in one `listRowBackground`), never replaces it: a transparent row background
  drops the whole section out of its card (the route card, 2026-10-05), and its
  separators then run between edges no neighbour shares.
- **Separators follow the system.** They inset to the text after a leading badge or
  glyph — Settings does the same — and a section's chrome (header controls) is not a
  row, so nothing hides or fakes a separator to attach it.
- **Rows wrap, never truncate** — reflow rule 5 applied to list rows: two lines for an
  address (three at accessibility sizes), the origin yielding before the destination.
- **Two disclosures in one row read apart by seat**: the push accessory `›` sits beside
  the lines it opens (the route lines, not the cell's centre — the system accessory is
  replaced by the row's own mark), the in-place disclosure `⌄` sits *inside* the control
  it expands (the chip); two chevrons never share a trailing edge. Rule 7's trailing
  edge keeps the stamp and one accessory.

## Pin & badge taxonomy (board `2c`)

Shape and glyph carry the role; **color only reinforces**. The grayscale column is the test:
every row must stay distinguishable with color removed. Because that holds, the palette
keeps the market's green/red reading — moved to Okabe-Ito green and vermillion so the pair
also survives protanopia. Map marker and list badge share the glyph, which makes the route
list the map's legend.

Ends are symbols, not letters — A/B badges are withdrawn: they carry no meaning, need
localizing at accessibility sizes, and collide with numbered intermediates.

| Role | Shape on map | Token · color | SF Symbol (list badge) |
|---|---|---|---|
| Start · pickup | concentric ring | `pointStart` · Okabe-Ito green `#1E8E3E` | `smallcircle.filled.circle`; a row stating the *action* may use `shippingbox.fill` («забрать») |
| Intermediate *n* | numbered circle | `pointMid` · secondary | `3.circle.fill` (n) |
| End · drop-off | teardrop | `pointEnd` · vermillion `#D55E00` | `mappin.circle.fill`; action rows may use `house.fill` («доставить») |
| Warehouse | rounded square | `placeWarehouse` | `building.2.fill` |
| ПВЗ · staffed pickup | rounded square | `placePickup` | `storefront.fill` |
| Постамат · locker | rounded square | `placeLocker` | `cabinet.fill` |
| Return point | circle + arrow | `placeReturn` | `arrow.uturn.backward.circle.fill` |
| Recent | *(row icon only — never a pin shape)* | secondary | `clock` |

Verify every symbol name in the SF Symbols app against the iOS 17 floor before it lands in
the catalog.

## Field taxonomy → UI (handoff §4; dossier Part II §6)

Four rules — three drawn in board `3d`, the fourth ruled at the semantics session:

1. **One summary line per group, expanding to typed rows.** The draft reads in three
   seconds; density lives one tap down. The demo shows every field because it is a demo;
   this app makes every field *reachable*.
2. **Constraints replace hints.** Where a field is bounded, the bound *is* the helper text.
   Unavailable options render disabled with their reason rather than vanishing, so the
   vocabulary stays learnable.
3. **Units belong to the field.** Centimetres and kilograms in the UI, metres on the wire.
   Currency is a picker. The phone extension is its own field. No free-text number ever
   means two things.
4. **Required is marked before it is broken.** A `.tertiary` "required" caption rides
   beside the field name — explicit beats symbolic, and VoiceOver reads it for free (the
   schema editor's "Text · required · Claim document" subtitle is the precedent). Unmet
   adds the `bound` line, which leaves on answer; answered stays quiet. A required choice
   picker carries no fake `""` answer — the collapsed row shows the prompt, visibly
   *un*answered; optional pickers may keep an explicit "None" row, because there clearing
   *is* an answer. An empty required section states its bound ("at least one item — the
   order needs a parcel to carry") rather than spending the footer on trivia.

Interdependencies the UI enforces up front — never discovered via API errors:

| Constraint | Source of truth |
|---|---|
| loaders 0–2, **and only with `cargo`** | live API answers `409 estimating.too_many_loaders` |
| `cargoType` only with `cargo` | provider tariff rules |
| thermobag only with `courier` | provider tariff rules |
| `due` inside the provider window (+1 h … +30 d) | provider rules |
| `coordinates` are **lon,lat on the wire** | the one ordering bug that yields a plausible wrong answer instead of an error |

Keyboard and autofill per field type: `textContentType` on every contact field, plus
`.phonePad`; `.numberPad` for flat/floor; `.decimalPad` for weight/cost. A sender is always
copying from somewhere.

## The reflow ladder (board `3f`)

At accessibility-extra-large the draft reflows down **a ranked ladder, not breakpoints** —
in order: (1) label and value stack; (2) a leading glyph keeps its size but the row grows;
(3) the tariff strip becomes a vertical list — the horizontal strip cannot survive, which
is why the `3a` explainer is the layout to build; (4) toolbar Cancel/Done wrap to their own
row; (5) two-line address rows run to three lines rather than truncate. **Truncating an
address is never acceptable — a wrong address is a failed delivery.** In code the ladder is
`ViewThatFits` candidate lists, authored most complete first (decision #31).

## Motion (board `4c`)

One rule: **animation reports a state change the user did not cause, or confirms one they
did — never decorates a static screen.** Everything below exists at iOS 17; motion alone
never justifies raising the floor.

| Moment | Effect | Why it earns it | Reduce Motion |
|---|---|---|---|
| Ищем курьера | `.symbolEffect(.variableColor)` | the one genuinely indeterminate wait; the glyph is the spinner | static + text |
| Статус сменился | `.contentTransition(.symbolEffect(.replace))` | arrives while you look elsewhere — the swap is the notification | cross-fade |
| Цены пришли | `.numericText()` + shimmer→value | price landing in a strip already being read must not just blink | instant |
| Точка подтверждена | `.symbolEffect(.bounce, value:)` | confirms the tap landed when the map barely changes | haptic only |
| Заказ создан | `.bounce` + success haptic | the one irreversible action; no confetti — money just moved | haptic only |
| Курьер двигается | `withAnimation(.linear)` on coordinate | interpolate between polls; a teleporting scooter reads as a bug | jump |
| Ошибка поля | shake (~2-frame offset) | only where the error sits beside the input; never for network failures | color + text |
| Content reveal | `.move(edge: .top)` + `.opacity` inside an animating container | insert/remove is not a morph — `matchedGeometryEffect` is wrong for an element that exists in only one state (the trail-expansion fix is the precedent) | `.opacity` whole |

On Pow: two effects would be taken (`.shake`, a price-change effect), both ≈20 lines —
**skip the dependency** and keep the vocabulary in the app, where each Reduce Motion branch
is visible in the same file. Adopt Pow only if its transition set is wanted broadly.

## See Also

- <doc:Design>
- <doc:DesignSystemSemantics>
- <doc:DesignSystemControls>
- <doc:LinkGrammars>
- <doc:Vision>
