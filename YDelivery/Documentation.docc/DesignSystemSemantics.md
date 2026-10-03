# Design System — Semantics: bounds, hints, and errors

The research plan commissioned by `docs/agent-tasks/design-system-research.md` (PR #97).
The trigger: 1.0 TestFlight screens carry inconsistencies no single component owns —
"red" is doing three jobs, errors have two dialects, and bounds live partly beside
their fields and partly only on the review sheet. Fixing them piecemeal would deepen
the inconsistency the audit exists to close.

This document is a *plan*, not a spec: it surveys the gap, proposes a vocabulary and
the grammars that use it, names a retrofit order, and lists what needs the owner's
ruling. Nothing here ships yet. When the rulings land, the decided rows fold into
<doc:DesignSystem> and this page links there instead of restating them.

Conventions used below: **proposal** marks a recommendation awaiting the owner's
ruling; *site* names are code references (file · component); ✓ in the survey means
"already correct — keep as precedent".

## What the survey found

Six systemic gaps, each visible on a shipping screen:

1. **Red is overloaded.** `.red` currently means *unmet bound* (the required-field
   hint), *failed write* (sign-in, field save, template save, chat send), and —
   through `role: .destructive` — *destructive verb* (sign out, delete, cancel).
   HIG's own rule is "avoid using the same color to mean different things"
   (HIG → Color). The first usage is wrong outright: an unmet precondition is not a
   failure, nothing has gone wrong yet.
2. **Errors speak two dialects.** Quiet: `Label(…, .exclamationmarkTriangle)` in
   `.secondary` (estimate bar, tariff strip, trail read, saved-places history). Loud:
   bare `.red` text (settings sign-in, field/template saves, chat send). Both sit in
   `OrderChatView.Content` four sections apart — `loadError` is gray-and-glyph,
   `sendError` is red-and-bare. The quiet dialect is the deliberate one: "a failure
   is a retry, not attention" is already the estimate bar's stated rule
   (`NewDeliveryView+Content.EstimateBar`, decision #13). The loud one is accidental.
3. **The loud text also fails contrast.** `.red` (`#FF3B30`) on the grouped white
   surface measures ≈3.6:1 at footnote size — below the WCAG AA 4.5:1 floor for small
   text. `.orange` (`#FF9500`, the trail's signature warning) measures ≈2.2:1. The
   dark-mode variants pass (#FF453A on black ≈5:1), so the miss is light-mode-only —
   exactly what the catalog's "values run deliberately darker than `.systemRed` where
   text sits on them" rule (DesignSystem → "Semantic colors") already exists for.
4. **Bounds are invisible until broken.** A required field is unmarked until it is
   already unmet; "at least one item" exists only inside `orderBlockers`, discoverable
   solely by opening the review sheet; the section footer meanwhile spends itself on
   insurance trivia. The discoverable bounds that *do* exist prove the rule —
   "Prices appear when the route is complete." is a section footer doing exactly the
   right job.
5. **The CTA is mute about readiness.** `OrderBar` renders «Order Courier ·
   RUB 3,095.14» — a named, priced promise — while `orderBlockers` is non-empty
   (`canOrder` is `selectedOffer != nil`, blind to every other bound). The review
   sheet knows the truth; the bar presents as ready.
6. **One line, two languages — by accident.** Field names render the sender's own
   vocabulary («Заказ») beside English hint prose and English bound sentences. That
   mix is inherent — user data stays verbatim — but no rule says so, so nobody can
   tell intended from untranslated.

## The inventory

Every color/hint/error surface the task names, plus the ones the first pass surfaced.
*Proposed role* references the vocabulary defined below; `read-failure` and `error`
are distinct roles there on purpose.

| File · site | Today | Proposed |
|---|---|---|
| `NewDeliveryView+Content.fieldRow` — required-unmet line | `.red` footnote, no glyph; field unmarked until unmet | `bound`: marker + attention-tinted glyph line |
| `fieldRow` — choice picker `Text("Not set").tag("")` | a selectable row that reads as answered | prompt, not an answer (placeholder semantics) |
| Route section footer — "Prices appear when the route is complete." | bound in the footer ✓ | `bound`, the convention to keep |
| "What's inside" footer — "The declared value is what the insurance covers." | trivia where the bound belongs | `bound` (≥1 item, name + value); trivia moves to the item editor |
| Item row `misfit` — `Label(△)` footnote `.secondary` | warning in gray ✓ | `warning` (advisory), keep |
| Item row `journey` footnote | `info` ✓ | `info` |
| `fieldsError` / `templatesError` — `.red` footnote + Retry | loud red on a failed *read* | `read-failure`: quiet + in-place retry |
| `EstimateBar.failed` — `Label(△).secondary` + Retry | quiet failure, bar keeps its height ✓ | `read-failure` — the precedent |
| `TariffStrip.failed` — same shape + reason line | ✓ | `read-failure` |
| `TariffStrip.ready(empty)` — `?` glyph + Retry | answered-and-nothing, actionable ✓ | `info` |
| `TariffStrip.signedOut` — secondary invitation | ✓ | `info` |
| `OrderBar` — ready-looking title while blockers exist | mute | owner ruling: destination-named title proposed |
| `PointRow.addressWarning` — `Label(△)` footnote `.secondary` | advisory ✓ | `warning`, quiet end |
| `PointRow` contact invitation + "Only the order asks — prices don't." | steering hint, `.tertiary` ✓ | `info` |
| `PointRow.parcelActions` — `Label(📦)` footnote | ✓ | `info` |
| `SearchContent.historyUnavailable` — `Label(△)` + consequence footer | quiet + states what still works ✓ | `read-failure` |
| `SearchContent.locationDeniedCard` — glyph, headline, "Open Settings" | refusal card with an action ✓ | `bound`-shaped refusal — precedent for error chrome's action row |
| `PasteCard.failed` — per-cause glyph (`wifiSlash`) + Dismiss | cause-specific glyph, not generic ✓ | `error` precedent: glyph names the cause |
| `DescribeContent` footers — no-building / not-dialable / steering | bound stated where edited ✓ | `bound`/`warning` split below |
| `DescribeContent.saveUnavailableReason` — `.secondary` under the disabled button | disabled control states its reason ✓ | `bound` |
| `RefineContent` confirm bar `errorText` — `.red` footnote | a failed *read* in red | `read-failure` |
| `ReviewSheet` blockers — `Label(⊘ exclamationmarkCircle)` subheadline, untinted | the union-of-bounds list ✓ | `bound`, gets the role's tint |
| `ReviewSheet` footer — "Money moves and a courier is dispatched…" | the one caution before an irreversible action ✓ | `warning`-adjacent footer, keep untinted |
| `ReviewSheet.failed` — `Label(△)` + Try again | right shape, no tint | `error` chrome |
| `ReviewSheet.unresolved` — `Label(?)` + footnote + "Check again" | unknown-outcome, read-only retry ✓ | `warning` — uncertain is not failed |
| `ReviewSheet.placed` — `statusSearching`-green ✓ + bounce + haptic | outcome wears the status it enters ✓ | `success` — the precedent |
| `ReviewSheet.recordWarning` — footnote + "Save it again" | quiet ✓ | `warning` |
| `DeliveriesView+Content.syncError` — footnote under the rows | quiet, list stays ✓ | `read-failure` |
| `…historyUnavailable` — `ContentUnavailableView(△)` | whole-surface failure gets the full state ✓ | `read-failure` |
| `…` signed-out — `ContentUnavailableView(.key)` | invitation, not an error ✓ | `info` |
| Row `trailError` — `Label(△).secondary` | quiet beside the row ✓ | `read-failure` |
| `statusLine` — chip · spacer · time · chevron | accessories trail (fixed, PR #98 line) | the trailing-edge rule below |
| `OrderDetailView` cancellation `.ready` — terms footnote + destructive button | the bound states itself; the verb is `role: .destructive` ✓ | `bound`-flavored explanation + `destructive` |
| Cancellation `.failed` / `.unconfirmed` / `.unrecorded` — plain footnote + Try again | no glyph, no tint, no diagnostics | `error` chrome + share-diagnostics affordance |
| Cancellation `.cancelled` — `Label(✓).secondary` | quiet terminal ✓ | status-colored outcome (see grammar) |
| `shareError` — `.alert(error:)` + `PresentableError` | terminal refusal interrupts with title/reason/remedy ✓ | the alert's proper seat (HIG → Alerts) |
| `OrderChatView.loadError` — `Label(△).secondary` | quiet ✓ | `read-failure` |
| `OrderChatView.sendError` — `.red` footnote | the other dialect, same file | `error` chrome |
| `SettingsView` sign-in error — `.red` footnote in the section footer | loud, no action | `error` chrome + diagnostics |
| `SettingsView` "Nothing captured yet" | `.secondary` ✓ | `info` empty |
| `CustomFieldsView` `fieldsError` — `.secondary` bare text, no retry | quiet but actionless | `read-failure` + Retry |
| `FieldEditor` `saveError` — `.red` section text | loud | `error` chrome |
| `CustomFieldsView` empty — "No fields yet — add «Заказ»…" | empty state states the way in ✓ | `info` |
| `FieldEditor` required/shown footer — the invariant where it's enforced | bound explains the disabled toggle ✓ | `bound` |
| `CustomFieldsView` row subtitle — "Text · required · Claim document" | requiredness is *marked persistently* in the schema ✓ | the precedent the field affordance should copy |
| `LibraryView` unreadable — `ContentUnavailableView(△)` per segment | ✓ | `read-failure` |
| `LibraryView` empty — `ContentUnavailableView` + way-in description | ✓ | `info` |
| `LibraryView` footers — "saved from a stop while composing" | provenance where the "+" would be looked for ✓ | `info` |
| `LibraryView+TemplateEditor` `failure` — `.red` footnote | loud | `error` chrome |
| `SavePlaceSheet` / `SaveTemplateSheet` `failure` — `Label(△).secondary` + reassurance footer | closest to canonical ✓ | `error` chrome minus the red text |
| `ShareView.failed` — `ContentUnavailableView(mappinSlash)` + guidance | ✓ | `read-failure` (extension's whole surface) |
| `ShareView` footer — "guessed from the text — check the pin" | advisory where the parsed value sits ✓ | `warning`, quiet end |
| `StatusTimeline` signature warning — `Label(△fill).caption.orange` | the only `.orange`; fails AA at caption size | `warning` (darkened text token) |
| `YDeliveryWidgets` — `status.color`, `status.symbol`, `StatusChip` | shared vocabulary already ✓ | unchanged; proof the tokens must live in `YDeliveryKit` |

## The proposed vocabulary

Six feedback roles, named by meaning — same rule the status set already runs on
("named by meaning so no hue name appears in a diff", DesignSystem → "Semantic
colors"). Each role owns a color channel, a glyph, and a words rule; **a role's color
never appears without its glyph or its words** — the chip's rule generalized.

| Role | Means | Chrome | Color channel |
|---|---|---|---|
| `info` | guidance, explanation, provenance, invitations | footnote, `.secondary`; glyph only where scanning needs it | system hierarchical style — no hue |
| `bound` | a precondition, visible before it is broken; *not* an error | `exclamationmark.circle` line beside the field / section footer / review-sheet blocker row | **proposal:** `statusAttention` hue family — "a decision is owed"; neutral `.secondary` is the fallback |
| `warning` | proceedable-but-risky; trust degradation; uncertain outcomes | `exclamationmark.triangle` + words; glyph may stay bright, words take the darkened text token | `warningText` ≈ `statusSearching` light `#8A5A00` (≈5.9:1), dark reuses its dark value |
| `error` | an action tried and failed — writes, commands, refusals | glyph tinted the bright hue, words in `errorText`; optional action row | `errorText` darkened red, AA ≥4.5 at footnote; glyph `.red` is fine (non-text bar is 3:1) |
| `success` | the outcome the sender wanted | `checkmark.circle.fill` + status words | `statusDone` — or the status the outcome enters (`ReviewSheet.placed` wears `statusSearching` on purpose) |
| `destructive` | a verb, never a message | `Button(role: .destructive)` only | system red on controls; never tints text |

Each role's channel splits the way the two-entries rule already does (DesignSystem →
"Token shape"): the *glyph* entry keeps the bright hue — non-text graphics clear at
3:1 — while the *text* entry is the darkened variant that passes 4.5:1 at footnote
and caption sizes. One role, two catalog entries, never a raw hue at a call site.

Two roles carry no hue of their own and should not: `info` and (optionally) `bound`.
`destructive` is an action role — its color lives on the control, which is what keeps
`.red`-the-verb out of `.red`-the-message. The boundary that does the most work is
`bound` vs `error`: a bound is the shape of the form, true whether or not the sender
has looked at it; an error is something that *happened*. Red for "you haven't typed
yet" teaches alarm fatigue and, per the survey, currently also fails AA.

**The read/write split the grammar codifies.** The codebase already draws it
inconsistently; the vocabulary makes it deliberate:

- **A failed *read* is `read-failure`, not `error`.** The surface keeps its shape,
  the message is `.secondary`, an in-place Retry sits beside it, and the glyph
  (`exclamationmark.triangle`) stays allowed but quiet. Where the whole surface is
  the content, `ContentUnavailableView` carries it (the Library precedent). HIG's
  own precedent: "when a server connection is unavailable, Mail displays an
  indicator that people can choose to learn more" (HIG → Alerts) — a failed read
  informs; it does not accuse. Owners today: `EstimateBar`, `TariffStrip`,
  `historyUnavailable`, `trailError`, `syncError`, `LibraryView` — and the sites
  that should join them: `fieldsError`, `templatesError`, `RefineContent` geocode
  failure, `CustomFieldsView.fieldsError`.
- **A failed *write* or command is `error`.** Sign-in refused, save refused, send
  refused, cancel refused, provider `409`. These get the canonical chrome below.
- **An unknown answer is `warning`.** `unresolved` acceptance, `unconfirmed`
  cancellation — the provider may have applied it; the words say so and the action
  is a *read* (Check again), never a resend. This distinction is already the
  review sheet's own logic ("no retry here on purpose"); the role just names it.
- **A terminal refusal that must interrupt is the alert's seat**, not the row's —
  `PresentableError` + `.alert(error:)` (the share-ask precedent). HIG → Alerts:
  sparingly, only when the information is critical *and* the row can't carry it.

## Placement grammar

The question a contributor should never have to ask: *where does this sentence sit?*
Answered by whose bound it is:

1. **A bound states itself where the decision is made.** The field that carries it,
   the footer of the section whose membership it constrains, the review sheet when
   the bound spans sections. Never first discoverable at review — a blocker the
   sender could not have seen upstream is a design bug, which is the audit's test.
2. **Per-field bounds sit beside the field** (required-and-empty); **per-section
   bounds sit in the section footer** (≥1 item; "Prices appear when the route is
   complete." is today's correct instance); **order-level bounds list on the review
   sheet** ("every stop needs a person" — no single row owns it).
3. **The review sheet is the union, not the source.** Every blocker it lists also
   exists, quietly, at its owning surface — the sheet re-states, never originates.
   Today's counterexample is "Say what's inside": the wire requires ≥1 item
   (live-verified), and nothing says so until the sheet.
4. **Footers state bounds and consequences; trivia lives at the field it explains.**
   The insurance sentence is the item editor's `Value` row's business, not the
   section footer's — the footer's job is "the order needs at least one item".
5. **An unavailable option stays visible and names its reason** — the existing rule
   (OptionsEditor footers, `StopChooser`, `DescribeContent`'s bookmark) reaffirmed
   and extended: it now applies to `CustomFieldsView.fieldsError`, which is quiet
   but offers no retry.
6. **An answered bound is quiet.** No green checkmarks on filled fields; silence is
   the answered state (the same choice `StatusTimeline` makes — a `.verified`
   signature renders nothing). The marker persists; the bound line leaves.
7. **Trailing edge: timestamps and accessories trail, content leads.** The status
   line's fix — chip · spacer · as-of stamp · chevron — is the rule, already the
   timeline's own layout. Audit on adoption: `LibraryView` rows, `OrderDetailView`
   status header, `ReviewSheet` stops.

## Error chrome — the canonical row

One shape for "something failed", so a failure reads the same everywhere:

- **`Label`** — `exclamationmark.triangle` by default, or the cause's own glyph
  where one exists (`wifiSlash` for a dead connection, the `PasteCard` precedent).
  Glyph tinted the role's bright hue (graphics bar: 3:1 — `.red` qualifies); words
  in the role's text token, `errorText`/`warningText` — AA-dark, because the bright
  hues fail at 13 px (measured, survey §3).
- **Words**: what failed, stated plainly — the `LocalizedError` contract already
  guarantees a filled `errorDescription`; nothing editorializes past it.
- **Action**: the honest next step. `Try again` for a retryable write; `Check again`
  for a re-read (never re-sends); `Open Settings` for a refusal only Settings can
  fix; nothing for a bound, which needs no button — it needs the field.
- **"Share diagnostics" attaches where a wire exchange is implicated** — sign-in,
  offers fetch, claim create/accept/cancel, sync. It never attaches to local
  validation (bounds are not errors) or to pure storage failures — the log holds
  requests and responses, so there is nothing in it to share about a disk write.
  The affordance is the existing `ShareLink("Share diagnostics log")` surfaced
  beside the message; Settings' row stays the always-on path. **Proposal:** inline
  on surfaces where the error is the content (order detail, review sheet,
  sign-in); a "details in Settings → Diagnostics" footnote elsewhere — owner to rule.
- **Precedence stays where it is**: a destructive confirm still runs through the
  confirmation dialog (`OrderDetailView`'s cancel) and a terminal refusal through
  `.alert(error:)`; the row is for failures the sender can act on in place.

## Status colors for outcomes — cancellation first

The straw man — green = free, blue/yellow = paid, orange/red = failed — fails on
HIG's own terms and on this vocabulary:

- **"Free" is a property of the terms, not an outcome.** The sender's channel for
  money is the number on the button — "Cancel this delivery — pay 807.60 ₽" is
  *consent*, and consent has to be words, not hue. A green `free` would paint a
  destructive verb in a safe color (HIG → Color: don't reuse a color for a
  different meaning; the verb stays `role: .destructive`).
- **The outcome wears the status it produced** — the `ReviewSheet.placed`
  precedent. A landed cancellation renders `statusCancelled`'s vocabulary
  (gray, circled ✕, "Cancelled"), not a green checkmark: the order's truth is
  *cancelled*, which is terminal-neutral, not a triumph. Today's `Label(✓).secondary`
  is the right instinct with the wrong glyph — ✓ means "succeeded" and is one shade
  off "delivered".
- **Failed** splits by certainty: `.failed` → `error` chrome (definite refusal,
  retry re-asks); `.unconfirmed` → `warning` (answer lost — the provider may have
  applied it; retry re-reads); `.unrecorded` → `error` words, because the local
  write is what failed, with the retry re-writing rather than re-sending.

**Proposal:** cancellation adopts the role grammar outright — `bound`-styled terms
explanation, destructive verb, `error`/`warning` failure states, status-colored
terminal. The same mapping then serves the other outcome surfaces for free: the
tariff strip's failure is `read-failure` + retry; `StatusChip` already *is* the
status-color grammar; sync states are `read-failure`. The "color is never the only
channel" rule is already law — glyph and words ride every status; here it is
restated as "the channel for money is the numeral".

## Bounds, required fields, empty states

- **Required fields get a persistent marker** — **proposal:** a `.tertiary`
  "required" caption beside the field name (the schema editor already flags them
  persistently in its row subtitles — "Text · required · Claim document" — which is
  the house precedent; an asterisk is the platform convention but reads as
  punctuation, not words, to VoiceOver). Owner to rule on the marker's shape.
- **The unmet state adds the `bound` line** — glyph + words, attention-tinted per
  the vocabulary; it disappears on answer. Red retires from this seat.
- **`Not set` stops being an answer.** Required choice fields drop the `""` tag —
  the collapsed row shows the field's prompt in placeholder style until a real
  choice lands (the empty selection is then visibly *un*answered, which is the
  truth). Optional fields may keep an explicit "None" row — there, clearing *is* an
  answer. The picker-style mechanics (menu vs navigation-push) are the PR's
  implementation detail.
- **Empty required sections state their bound.** "What's inside" with no items
  reads «Add an item» + footer "at least one item — the order needs a parcel to
  carry"; the insurance sentence moves to the item editor's `Value` section. The
  Library's "No places yet" + way-in is the shape to copy.
- **Field-error motion** (`DesignSystem` → Motion row 7: the ~2-frame shake) is
  spec'd but unshipped. Either it ships with the `fieldRow` retrofit — it belongs
  exactly there, beside-the-input only — or the spec row is struck. Owner's call;
  flagging rather than quietly keeping dead spec.

## Motion grammar — the reveal convention

Added to the existing table (DesignSystem → "Motion"): **content inserted inside an
animating container reveals with `.move(edge: .top).combined(with: .opacity)`;
Reduce Motion swaps it for `.opacity` whole** — the trail-expansion fix
(`b9f7aa7`) is the precedent, and the rule exists so the next expanding surface
doesn't re-derive it. `matchedGeometryEffect` is reserved for its actual job — one
element morphing across two states — and is wrong for insert/remove, where the
element exists in only one. Every animated insertion names its Reduce Motion path
in the same computed property (the `revealTransition` pattern): the fallback is
part of the transition, not an afterthought.

## Preview coverage matrix

Rule 4 already requires a running `#Preview` per view; the matrix makes state
coverage explicit. Every component that can be empty/bound/failed/succeeded previews
each state it can reach; each retrofit PR fills its surface's gaps.

| Component | States owed | Has | Gap |
|---|---|---|---|
| `fieldRow` (via `Content`) | met, required-unmet, choice-unset | met only | unmet, unset |
| `TariffStrip` | loading, ready, ready-empty, failed, signed-out | 4 of 5 | ready-empty |
| `EstimateBar` | calculating, ready, failed | all | — |
| `OrderBar` | hidden, blocked-title, ready | none standalone | all (currently only inside `Content` previews) |
| `ReviewSheet` | ready, blocked, placed, failed, unresolved, record-warning | ready, blocked, placed | failed, unresolved, record-warning |
| Cancellation section | loading, free, paid, paid-unnamed, unavailable, failed, unconfirmed, unrecorded, cancelling, cancelled | free, paid, paid-unnamed, unavailable, unconfirmed | failed, unrecorded, cancelling, cancelled |
| `OrderChatView` | stream, empty, loadError, sendError | stream, empty, loadError | sendError |
| `LibraryView` | places, empty, unreadable | all | — |
| `CustomFieldsView` | list, empty, fieldsError, saveError | list, editor | fieldsError, saveError |
| `SettingsView` | out, in, failed | all | — |
| `DeliveriesView` | populated, trailError, syncError, unreadable, signed-out | populated, trailError, syncError | unreadable, signed-out |
| `StatusTimeline` | live, delivered, multi-day, unknown, tampered, empty | all | — |
| `ShareView` | ready, failed | ready | failed |
| `PointPickerView.RefineContent` confirm bar | empty, resolving, failed, approximate | all | — |

## Liquid Glass / iOS 26 fit

The floor stays iOS 17 and the grammar needs nothing iOS-26-specific — that is the
point of building it on semantic roles. Three notes, sourced:

- **System materials and dynamic colors do the adapting.** HIG → Color: "provide
  both light and dark colors to support Liquid Glass adaptivity" — the catalog
  already carries both; the new text tokens add their pair at birth.
  `.regularMaterial`/`.bar`/grouped backgrounds in the surveyed surfaces are
  already the materials Liquid Glass composes with; no `.glassEffect` is wanted —
  a bound row is content, not chrome.
- **Glyphs beat custom assets.** Every role's marker is an SF Symbol — they adapt
  to rendering modes and accessibility settings for free (SFSafeSymbols keeps the
  names compile-checked; each new symbol still gets the iOS-17 availability check
  the DesignSystem requires).
- **Apple's own precedent is *quieter* than this app's current loudest state.**
  App Store's cannot-connect page: plain words plus a Retry — no red. Wallet's
  pass/transaction states: tint + words + glyph, never hue alone. Settings →
  Wi-Fi's "No Internet Connection": plain text under the toggle. Health's
  error/action rows pair an icon with body text. None of them spends red on a
  hint — which is what `fieldRow` does today.

## Retrofit order — smallest blast radius first

Six PRs, each independently reviewable; the shared tokens come first because the
package-first rule (CLAUDE.md §7) puts shared vocabulary in `YDeliveryKit`, and
everything after is adoption, not invention.

1. **`YDeliveryKit` — roles + tokens** (additive; no app change): `bound`,
   `warningText`, `errorText` colorsets with light/dark variants at AA-verified
   values (the measured table above is the starting point); a `Notice`/`ErrorRow`
   view owning the canonical chrome — glyph, words, optional action slot, optional
   diagnostics link; the status-colored `.cancelled` glyph helper if the ruling
   takes it. Previews: one per role.
2. **Write-failure surfaces** — `SettingsView` sign-in, `CustomFieldsView`
   saveError/FieldEditor, `LibraryView+TemplateEditor`, `SavePlaceSheet` +
   `SaveTemplateSheet`, `OrderChatView.sendError`. Text-and-glyph swaps onto the
   canonical row; diagnostics affordance per the ruling.
3. **The compose card** — `fieldRow`: required marker, `bound` line, "Not set"
   placeholder semantics; "What's inside" footer states the ≥1 bound; insurance
   trivia moves into `ItemEditor`'s value section. Preview gaps filled.
4. **Read-failure unification** — `fieldsError`, `templatesError`, `RefineContent`
   geocode failure, `CustomFieldsView.fieldsError` (gains Retry): adopt the quiet
   convention already proven on `EstimateBar`/`TariffStrip`.
5. **Money-adjacent last** — `OrderBar` readiness per the ruling; `ReviewSheet`
   blocker rows onto `bound` tint; `failed`/`unresolved` onto `error`/`warning`
   chrome; the cancellation section's full grammar. Largest blast radius, the
   most previews added.
6. **Fold-in** — ruled rows move into `DesignSystem.md`; this page links to the
   ruling notes.

## Open questions — owner rulings needed

1. **`bound` tint**: `statusAttention` family ("a decision is owed" — same hue the
   order wears when it needs one; AA-passing already) vs neutral `.secondary`.
   *Proposal: the attention family — a bound must be findable on a long card, and
   hue is the find.*
2. **Required marker shape**: persistent `required` caption (house precedent:
   `CustomFieldsView` subtitles) vs asterisk vs nothing-until-unmet.
   *Proposal: the caption — explicit beats symbolic, and VoiceOver reads it for free.*
3. **`OrderBar` readiness**: destination-named title — "Review the order" while
   blocked, "Order Courier · ₽" when ready — vs blocker count vs silence.
   *Proposal: the title names the destination the tap actually opens.*
4. **Diagnostics placement**: inline `ShareLink` on provider-implicated errors vs a
   "details in Settings → Diagnostics" footnote. *Proposal: inline where the error
   is the content; footnote elsewhere.*
5. **`read-failure` glyph**: keep the triangle marker (scanability — a failed read
   must not read as an empty one) vs words-only. *Proposal: keep it.*
6. **Field-error shake**: ship with the `fieldRow` retrofit or strike the spec row.
7. **Locale rule**: chrome localizes to the app's language, user/provider
   vocabulary stays verbatim, quoted where interpolated («Заказ» is required…).
   *Proposal: state exactly that — it is what the code already does; a real
   localization pass is a Roadmap item, not a design-system one.*
8. **Cancellation "free"**: any affirmative marker at all, or words-only.
   *Proposal: words-only — the button's number is the channel.*

## Validation

- **Previews are the regression net.** The matrix above is the contract: each
  retrofit PR adds its surface's missing states, and rule 4 ("every `#Preview`
  must run") makes the net self-checking in the build.
- **The screenshot seam already exists** — `docs/agent-tasks/screenshot-and-ux-pass.md`:
  seeded launch flags (`--uitest-history`, `--uitest-three-stop-draft
  --uitest-fields`) reach every surveyed surface without a provider token, and its
  numbered evals become this audit's checklist (walk 1 step 4 watches the
  `read-failure` footnote; walk 2 step 3 is the blocker path end to end). The
  walk re-runs after PRs 3–5.
- **Contrast is measured, not eyeballed** — WCAG AA 4.5:1 for footnote-size words,
  3:1 for glyphs, verified "against the surface the words actually sit on"
  (DesignSystem): grouped background, the chip's 12% tint, the `.bar` material.
  The survey's measured numbers are the baseline the new tokens must keep beating.
- **This document itself was DeepWiki-reviewed prospectively** before its PR —
  the plan was described against the indexed code and objections were folded in.

## Sources

- HIG → Color (`developer.apple.com/design/human-interface-guidelines/color`):
  "avoid using the same color to mean different things"; "avoid relying solely on
  color"; dynamic system colors' semantic meanings must not be redefined;
  light + dark variants for Liquid Glass adaptivity.
- HIG → Alerts (`…/alerts`): use sparingly; "when a server connection is
  unavailable, Mail displays an indicator that people can choose to learn more";
  destructive style on the action people didn't deliberately choose; caution
  symbol sparingly.
- WCAG 2.x contrast (w3.org/WAI/WCAG21): AA 4.5:1 normal text, 3:1 large text and
  non-text graphics. Measured values in survey §3 computed with the standard
  relative-luminance formula on the catalog's sRGB values.
- This repo: `DesignSystem.md` (status table, two-rules-plus-one, reflow ladder,
  motion table); `docs/agent-tasks/design-system-research.md` (the evidence set);
  `docs/agent-tasks/screenshot-and-ux-pass.md` (the validation seam);
  `REVIEW.md`-era review comments cited inline per site ("review, PR #n").
- Skills applied as first pass: `swiftui-pro` (views/design/accessibility
  checklists), `axiom-design`/`hig.md` (contrast floors, label hierarchy),
  `axiom-accessibility` (DifferentiateWithoutColor, Reduce Motion).

## See Also

- <doc:DesignSystem>
- <doc:Design>
- <doc:TechDebt>
