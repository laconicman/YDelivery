# Design System — Controls, lists, and the gateway

The second rulings session, 2026-10-05: the author's review of TestFlight 1.0 (5) on a
Russian device, grounded on a seeded simulator walk (the `--uitest-*` flags of
`docs/agent-tasks/screenshot-and-ux-pass.md`, iPhone 16 Pro, iOS 18.2, RU). The first
session (<doc:DesignSystemSemantics>) ruled what the UI *says* — bounds, hints, errors.
This one rules what the UI *is*: which shapes act and which report, how a `List`
dresses its sections, and what the compose screen's gate owes before and after it
opens. The trigger was YD-39 (a control's look is chosen per site, not per role) made
concrete by the author's list: borderless words in rows, two section styles on one card,
a blue CTA while bounds are owed, a confirmation sheet that repeats the card, a stop that
carries nothing and says nothing, two disclosure chevrons a thumb apart.

**Status: ruled 2026-10-05.** The decided rows live in <doc:DesignSystem> → "Control
roles", "The gateway", "Lists and rows", and placement-grammar rule 2's addendum. This
page keeps the survey, the inventory, the reasoning, and the one alternative held in
reserve. The retrofit lands as the Kit patch and two app PRs named at the end.

## The direction the record already held

Read back from the DocC rulings, the `(author, …)` notes in <doc:TechDebt>, issues
#62/#71/#72/#75 and the PR bodies #22→#132, before anything new was proposed:

1. **Offer the remedy where the state is rendered** — #71 («Say what's inside» should
   *be* the parcel section), #72 (the signed-out state offers Sign in), blockers as
   doors (#103), placement rules 1–3.
2. **The sheet re-states, never originates; two of anything on one screen is a bug
   report** — placement rule 3; decision #14 ("distance only").
3. **Explicit beats symbolic; glyph and words always; color only reinforces** — the
   `required` caption, the chip rule, the pin table's grayscale test.
4. **Constraints replace hints; an unavailable control stays visible and names its
   reason** — field rules 2 and 5; `DescribeContent`'s disabled Save with its
   `saveUnavailableReason` beneath is the precedent.
5. **A failure is a retry; a bound is not an error** — the semantics session entire.
6. **System idioms; no dependency larger than the problem** — `primaryAction()` kept the
   system capsule; StepperView was declined (#62).
7. **Wide targets** — the whole status line is the trail's disclosure (author, #109); the
   full-width add row.
8. **Never truncate an address** — reflow ladder step 5.
9. **Design, don't patch** — YD-37's deferral.
10. **Added this session:** tinted bare words in a row do not read as controls (author);
    a CTA must not claim a readiness it does not have (author) — the complement of the
    drive's "a CTA must never look reachable while a tap dead-ends".

## What the review found

1. **Tinted words act as buttons inside content rows.** The route card's
   Swap · Add stop · Reorder strip, the «Add an item» / «Add from library» pair, the
   point row's «+ Who receives» invitation, the map callout's «Edit point» / «Save as
   place» pair — all `.borderless` words in the accent color sharing a row with content
   or with each other. Each is defensible alone (Settings' «Sign Out» is a tinted word
   too); together a tap target has no single signature, and PR #131's misfire (one tap
   firing every automatic button in a row) was the mechanical symptom of the same drift.
2. **The route section lost its card.** `routeCard` highlights the callout's row with
   `.listRowBackground(Color.accentColor.opacity(calloutPin == row.id ? tint : 0))` —
   which *replaces* the inset-grouped background with a transparent one for every row,
   so the «Маршрут» section renders on the bare background while «Что внутри», «Ваши
   поля» and «Варианты» are cards. Its separators then run from the badge's text edge to
   an edge no card shares — the "strange indentation". The action strip's
   `listRowBackground(Color.clear)` treated the symptom ("the last row of a missing
   List") and left the cause.
3. **The gate claims a readiness it does not have.** «Проверить заказ» renders
   prominent blue while three bounds are owed. Semantics ruling #3 made it *enabled* so
   the sheet could explain the bounds — but the sheet then re-states the whole card, and
   the sender pays a tap and a context turn to read bounds the card could have shown
   where they are decided (the author's words: "a disabled button with a list of
   warnings would do the same without duplication").
4. **Per-item bounds are invisible on the item row.** «needs a declared value» lives only
   in `orderBlockers`, so a parcel with no price in rubles reads as complete until the
   sheet says otherwise. Placement rule 2 ("per-field bounds sit beside the field") was
   applied to the schema fields and never to items.
5. **A stop that carries nothing says nothing.** `parcelActions(at:)` returns `nil` and
   the row draws no line — while the provider refuses the route outright («Для точки
   назначения 2 нет отправлений», YD-19). No blocker exists for it either: the sheet
   would have let the order leave to a 400.
6. **Two disclosures a thumb apart; addresses truncate.** The Deliveries row's push
   accessory `›` is the system's — vertically centred in the cell — and the trail's `⌄`
   sits on the status line's trailing edge directly beneath it. `routeLine` wears
   `.lineLimit(1)`: «ул Москворечь…» truncates against reflow rule 5 on the very row the
   address exists to show.
7. **Found on the way.** `Notice(.bound, "…")` renders the *English* key on a Russian
   device although the Russian string sits in the app's compiled `ru.lproj` — a
   `LocalizedStringKey` handed across the package boundary resolves against the wrong
   catalog; the Kit's `Text`-taking initializer is the seam. «Reorder» is translated
   «Повторить» (= Repeat — the Deliveries swipe's word; YD-38). «Заказ для 1 890 ₽» is a
   calque of "Order for". Order detail shows the raw wire word «Тариф: express». The
   `--uitest-offers` fixture still spells `.other("superexpress_d2d")`, stale since #124.

## The inventory

Every `Button` in `YDelivery/Features/`, by site, with the role it is ruled into
(the vocabulary is defined in <doc:DesignSystem> → "Control roles"). ✓ marks a site
already wearing its role — kept as precedent.

| Site | Today | Role |
|---|---|---|
| `DeliveriesView+Content` «New Delivery» · `OrderBar` | `primaryAction()` ✓ | primary action |
| `ReviewSheet` confirm / Done / Check again | `.borderedProminent` + `.controlSize(.large)` | primary action — `primaryAction()` |
| `ReviewSheet` «Leave it for now» / «Close» | automatic, large | secondary action |
| `SearchContent` / `DescribeContent` / `RefineContent` card pairs | `.borderedProminent` + `.bordered` ✓ | card actions |
| `PointCallout.Card` «Edit point» / «Save as place» | `.borderless` pair | card actions — the callout is a card, not a `List` |
| `SettingsView` Sign In / Sign Out · `OrderDetailView` «Share with the recipient» · `ItemEditor` «Save as a template» | List default, alone in the row ✓ | action row |
| «Add field» | List default, alone in the row ✓ | add row |
| `routeCard.actions` «Add stop» | `.borderless`, in a strip | add row — alone in its row |
| `routeCard.actions` Swap · Reorder | `.borderless`, in a strip | header actions on «Route» |
| «What's inside» «Add an item» | `.borderless`, paired | add row |
| «What's inside» «Add from library» | `.borderless`, paired | header action on «What's inside» |
| Options summary row | `.plain` + trailing chevron ✓ | row door — the model |
| Item rows · `LibraryView` rows · `CustomFieldsView` rows · `ItemEditor` stop rows | `.plain` whole row, no chevron | row door — gains the chevron |
| `PointRow` address line | `.plain`, placeholder `.tertiary` ✓ | prompt door |
| `PointRow` contact invitation «+ Who receives» | `.borderless` tinted Label | prompt door — `.tertiary`, untinted |
| `Deliveries` status line | gesture on the full line, `⌄` trailing | chip-as-control — `⌄` inside the chip |
| `StatusChip` everywhere else | glyph + words ✓ | chip-as-indicator |
| `TariffCard` | `.plain` card with a selection stroke ✓ | selectable card — its own shape |
| Sort menus, the explainer's ⓘ | footnote controls in the section header ✓ | header action — the precedent |
| Cancel / Delete / Sign out | `role: .destructive` ✓ | destructive verb (semantics table) |

The rule that falls out of the table: **a tinted word is a whole row, a header control,
or a capsule — never a fragment of a content row.** Fragments either become prompts (an
unanswered door shows its prompt in `.tertiary`, field-taxonomy rule 4) or leave the row
for the header.

## Reasoning behind the rulings

**Header actions, not chips, for Swap and Reorder.** Three candidates: (A) the
arrangement controls move into the section header as small trailing controls, add rows
stay single full-width rows; (B) every multi-action row becomes a strip of `.bordered`
capsules (Maps' place card); (C) one row per action (Settings). (A) was taken because
Swap and Reorder *arrange* the section rather than belong to it — the «Delivery options»
header already seats Sort and ⓘ the same way, and `EditButton` in a header is Apple's own
seat for reordering — and because it leaves exactly one add row per section, which is
the add idiom the rest of iOS teaches. (B) stays the recipe where there is no header to
hold the controls: cards outside a `List` (the callout). (C) is **held in reserve**:
it is the most Apple-default and the tallest — the route card would grow three rows for
two arrangements. If header controls prove undiscoverable on device, (C) is the fallback
the author named (2026-10-05), and it needs no doctrine change — the add row *is* (C)
for one action.

**The chevron inside the chip** is what tells a control from an indicator with color
removed — YD-39's test, answered. A capsule that reports (`StatusChip` on a detail
header, in a widget) carries glyph and words; a capsule that acts (the Deliveries row's
chip, which opens the trail) carries `chevron.down` inside the capsule, rotating when
open, swapping for a mini spinner while the read is out. The gesture stays on the full
status line (author, #109) — only the glyph moved, so the line's trailing edge now holds
one accessory, the as-of stamp, and rule 7 ("accessories trail") stays true without two
chevrons sharing an edge.

**The push accessory sits beside the lines it opens.** The author asked for `›` on the
address lines, not the cell's centre, and for both chevrons to come apart; the chip's
`⌄` alone would have done the latter, but a cell-centred `›` still floats between the
price line and the status line, attached to neither. So the system accessory is hidden
(an `EmptyView`-labelled `NavigationLink` behind the row, the standard SwiftUI seam) and
the row draws `chevron.forward` `.tertiary` aligned with the route lines — the content
the push opens. Addresses wrap to two lines (three at accessibility sizes) — which
alone would have pushed the two marks apart, and is owed anyway by reflow rule 5.

**The gate.** The author questioned whether the review sheet should exist: "it mostly
repeats the presenting screen". Three shapes were weighed: (1) the sheet keeps only
what the card cannot do — consent for money (route, parcel, class, price restated once,
one verb) and the run's states (placing · estimating · accepting · placed · failed ·
unresolved, with the re-price disclosure of #106); (2) no sheet — a two-step bar that
arms as «Заказать за 1 890 ₽» and orders on the second tap, the run states rendered in
the bar's seat while the card locks; (3) keep the sheet as is and only restyle the bar.
(1) was taken (author, 2026-10-05). The irreversible action keeps its consent surface —
money moves on accept, and the Apple Pay sheet is the precedent for restating what is
bought before it is — but the sheet loses its *blocked* state entirely: a sheet that
opens on a blocked order is now a bug, because every bound it used to list is stated on
the card and the bar points at the first one. (2) saves a tap and was not taken because
it puts a money-moving second tap on the same pixels as the first and makes the compose
card host the run; it stays on record as the shape to try if the sheet still reads as
duplication once it is consent-only.

**The bar while blocked.** Three behaviours: (a) bound look, still responsive — a tap
scrolls the card to the first owed bound and shakes it, and one line above the bar names
the next step and counts the rest («Укажите ценность вещи · ещё 2»); (b) truly disabled,
with the full «Перед заказом» list as the card's last section (PR #103's door rows moved
from the sheet to the card); (c) both. (a) was taken (author, 2026-10-05): a bar that
ignores a tap with no reason beside it is the drive's dead CTA, and a full list below
the fold duplicates the inline bounds — the one-line summary names the next step, the
rows carry the rest. The look is the `bound` role's: no accent fill — the capsule in the
neutral tint, `exclamationmark.circle` leading, the destination's words. Every blocker
therefore carries a short imperative *step* beside its full sentence (the sentence stays
for the row; the step feeds the bar's line and VoiceOver's hint). The bar's title names
its destination in both states — «К оформлению», then «К оформлению · 1 890 ₽» — and
the one verb that orders lives on the sheet: «Заказать за 1 890 ₽» (English keeps
"Order for 1 890 ₽"; the Russian was the calque).

**Prompts versus bound lines.** Field-taxonomy rule 4 already splits unanswered rows in
two: a *picker-shaped* door shows its prompt, visibly unanswered, in `.tertiary`; a
*form-backed* row adds the `bound` line when unmet. The point row's address and contact
are picker-shaped (they open the one-flow picker), so the contact invitation becomes a
prompt — `.tertiary`, plus glyph untinted — and loses the accent it never earned; the
item row is a summary of a form, so a missing value, name, weight or count puts the
`bound` line on the row, which is also the door to the editor. A stop that carries
nothing is a bound of the route (the wire refuses it), stated on that stop's row —
«Nothing boards or leaves here — assign a parcel» — and listed among the blockers with
the first item's editor as its door (a fresh item when there is none).

## Alternative held in reserve

**One row per action** (candidate C above). Settings-style: each verb its own
full-width tinted row with a glyph, nothing shares a row. Most Apple-default, tallest;
not taken because the route card's two arrangement controls would cost two rows and the
header already has the seat. Revisit if a device pass finds header controls missed —
the add row is already this recipe, so adopting (C) wholesale is a move of two buttons,
not a redesign.

## Retrofit order

- **Kit patch** — `StatusChip(status:disclosure:)` (the control chip) and
  `Notice.init(_:_ message: Text, symbol:)` made public (the bundle fix).
- **The compose card** — the route card's background restored; Swap/Reorder to the
  header, «Add stop» and «Add an item» as add rows, «From library» to the header; the
  item row's bounds; the stop-that-carries-nothing bound and blocker; the gate — blocked
  look, next-step line, scroll-and-shake, the sheet consent-and-run only, «Заказать за»;
  `Notice` sites passing `Text`; «Переставить» for Reorder; the fixture's named class.
- **The Deliveries row** — `›` beside the route lines, `⌄` inside the chip, two-line
  addresses; order detail's tariff in the app's words.

## Validation

- **Previews per role**: each recipe in `Button+Roles` carries a preview of its states;
  the compose card's previews cover a blocked bar with its next-step line and a ready
  bar; the Deliveries previews cover collapsed, opening and expanded chips.
- **The screenshot walk re-runs** (`screenshot-and-ux-pass.md`, walks 1–2) after each
  app PR; `ListRowDoorsTests` is updated to the header control and still proves one tap
  opens one target.
- **This page was checked against the index before its PR** — DeepWiki named the
  dependents of the sheet's blocked branch (`blockerDoor` + `sheet(onDismiss:)` routing,
  `NewDeliveryOrderingTests`' blocker assertions, `HistoryScreenshotTests`' centre tap
  and chip tap) and `routeCard`'s transparent row background; each is addressed in the
  retrofit's briefs.

## See Also

- <doc:DesignSystem>
- <doc:DesignSystemSemantics>
- <doc:TechDebt>
