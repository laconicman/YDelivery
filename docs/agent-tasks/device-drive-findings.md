# Device-drive findings — the field report

**Date:** 2026-10-03 · **Device:** PavP (iPhone 16 Pro, iOS 26.6.2) · **Method:** real
app, real provider session, parked draft — driven end-to-end by
`YDeliveryUITests/DeviceDriveTests.swift` while a human would tap the same pixels.
No fixture flags; everything below happened to real state.

This is the sorrow ledger for "bring the app to a usable state again." Each entry is
what a sender experiences, what the app actually did, and which question in
`<doc:DesignSystemSemantics>` the entry feeds. It feeds — and is fed by — the
design-system retrofit; nothing here contradicts that plan, but several entries are
stronger evidence than the plan had.

**Wire-verified outcome, 14:16–14:18 MSK.** The full loop the owner asked to see
ran end-to-end and is on the wire log (`wire-log.jsonl`, pulled from the device):

| t | call | result |
|---|---|---|
| 14:16:42 | `calculateOffers` `requirements.skip_door_to_door: true` | 200, five offers priced |
| 14:16:48 | `createClaim` (offer payload `/4`, `client_requirements: {taxi_class}`) | 200, claim `01a1017b…` |
| 14:16:50 | `acceptClaim` `version: 1` | **200 `accepted`** |
| ~14:16:50+ | `getClaimInfo` | `performer_lookup` — courier search live |
| 14:18:05 | `getClaimCancelInfo` | `cancel_state: free` |
| 14:18:14 | `cancelClaim` `cancel_state: free` | **`cancelled`** — owner tapped it in the app |

A UI test killed mid-flight kept its `placeOrder` task alive on-device and placed
the claim; the owner cancelled it by hand inside the free window — 84 seconds of
live claim. Place → cancel → free is proven on the wire, not just in code.

---

## A. Getting trapped — the blocked order

### A1. A blocked sheet gave the user nothing to do *(fixed)*

The review sheet, when the draft failed its own bounds, listed the blockers and
showed **no order button at all** — the footer rendered empty. A sender who reads
"«Заказ» is required" has no CTA, no path, and no indication of what "done" looks
like. Reported by the owner as the primary "can't order" complaint.

**Fix shipped (uncommitted→`feat/record-signing`):** the CTA is back, disabled,
inside the "Before ordering" section beside the blockers it answers to.

### A2. Blockers are names, not doors

The sheet *states* bounds — «Заказ» is required, every stop needs a contact, every
item needs a value — but none of them is tappable. Resolving the field blocker took
a four-screen pilgrimage (Deliveries → Settings → Your fields → field editor →
Save → back → back → draft). A sender should tap the blocker and land on the
editor that unblocks it. This is the plan's **required-field discoverability**
question sharpened: bounds need affordances, not just text.

### A3. The Order bar is a dead control while pricing

`Order Courier` exists and is hittable while offers load; tapping it does nothing.
A sender cannot tell "pricing" from "ready" from "blocked" — three states, one
rendering. The bar must show its state: spinner/placeholder while pricing, the
destination-named title once blocked (per the plan's OrderBar ruling), and the
priced CTA only when a tap can actually do something.

### A4. The floating Order bar eats the last rows

The bar overlays the bottom of the draft list. At rest it covered ~97% of the
Options row and the "Who receives" row of the last stop — both readable, both
inviting taps that land on the bar instead (this is how the review sheet kept
opening when a test aimed at a row). `safeAreaInset` exists for exactly this;
content under a floating CTA is a classic own goal. Also a **scroll-margin**
issue: `isHittable` returns true for a sliver of a row.

## B. The route nobody can take

### B1. Provider prices what it will not carry

A three-stop route priced exactly one offer (Courier). At acceptance the provider
refused outright: «Для точки назначения 2 нет отправлений» — no shipments for the
middle point. The pricing stage promised what the claim stage refuses. A sender
invests contact details and item values into a route that can never be ordered.

**What the app could do:** surface per-point serviceability at pricing time, or at
minimum translate this error — "point 2" is provider jargon; the user knows it as
"the Земляной Вал stop".

### B2. Fewer offers is information, not a bug — but it looks like one

The 3-stop route got one offer; the same two endpoints got five. Provider-side
filtering (class capability × route × requirements) is legitimate — but a sender
watching the strip shrink from five cards to one has no idea why. An honest
caption ("only Courier serves this route") costs one line.

### B3. Placeholder prices that look real

While offers loaded, the strip rendered **999 ₽** on every card — a real-looking
number, not a skeleton. One accept at a placeholder price would be a real claim at
a fake price. Redacted/skeleton treatment, per the plan's loading-state grammar.

### B4. Every failed accept reprices upward — silently

Observed across one evening: 1,659 → 1,733 → 1,803 → 1,888 ₽ for the same draft.
Each "Try again" re-prices; surge made every retry more expensive than the last.
Money-adjacent surface (plan §cancellation/money): when the retry's price differs
from the failed attempt's, say so — "was 1,803 ₽, now 1,888 ₽ — order anyway?"

## C. The option that could not be changed — this session's deepest cut

### C1. «Опция „От двери до двери“ изменилась» — systematic, not drift

Wire-verified: **every** acceptance of an offer priced with door-to-door was
refused with this error — four consecutive failures across fresh claims, first
attempts included. Then the same draft with `skip_door_to_door` priced in was
accepted on the first try. So the signature with `toDoor` enabled is not
drifting per-attempt — it is **systematically refused** by this account/route/
class combination, while the app's "Try again" resubmits the identical
requirements — identical failure, guaranteed, twice observed.

**Owner's diagnosis (correct):** on this specific refusal the app should refresh
the offer/requirements before offering another accept — even if the option was
reverted meanwhile, the wire state is stale. "Try again" without a re-fetch is a
placebo button. The deeper question — why the provider prices an option it then
refuses, on every attempt — is a provider ticket candidate (wire log has the
payloads).

### C2. The error names the option but not the fix

«От двери до двери» is a provider phrase. The app's UI calls the same thing
"To the door." A sender matching error-text to switch-label needs a translation
they shouldn't need. Either echo the wire phrase in the error with the app's
term, or deep-link straight to the option.

### C3. The switch that would not flip *(test-infra, but an a11y smell)*

SwiftUI `Toggle`s in the Options sheet ignore a centre `.tap()` from XCUITest —
verified by `value` staying `Optional(1)` across a plain tap. A **right-edge
coordinate tap lands**: the wire shows `skip_door_to_door: true` priced twenty
seconds later. `value` reports as Int NSNumber, not the documented "1"/"0"
String. If automation can't toggle it centre-tap, VoiceOver's double-tap
deserves a manual check — the element may be exposing row-level geometry with
a dead middle.

## D. Claims that exist but shouldn't, and status words that lie

### D1. Errors that still created claims — seven of them

Every option-drift failure displayed the error card — and **every one created a
provider-side claim**. The Deliveries list now holds a "Not delivered" row per
failed run (14:04, 14:06, 14:10, 14:12…): the claim reached the provider
despite the client seeing failure; the unresolved-reconciliation path ingested
each as terminal. **The machinery worked — and that's the finding:** a claim
can exist while the user is told the order failed. Reconciliation saved us;
the UX is a landmine (the user might order again and pay twice). And the
account is littered with refused claims a sender cannot clean up.

### D2. "Not delivered" is the wrong word for a claim never dispatched

Owner's words: *"'Not delivered' is not the right status for a claim that was
never accepted."* `.attention` maps terminal-undelivered to "Not delivered" —
but a claim refused upstream was never dispatched, attempted, or delivered.
The row currently reads like a failed delivery of a real parcel. Honest
vocabulary: "Not placed" / "Refused" / "Cancelled before dispatch". This is the
plan's status-vocabulary section — now with a live specimen.

### D3. Scheduled pickup is the safety rail — and it's capped at hours

Owner's instruction: future-date claims so cancel-before-dispatch is always free.
The options ceiling is +4 h for Courier, 5 days for Cargo — the user's "next
week" isn't reachable for the class a small parcel needs. The bound is honestly
stated in the footer (good), but a sender wanting next-week delivery discovers
the ceiling only inside the editor. Provider ceiling, not ours — record it.

### D4. A claimed draft retires itself

Once the parked draft's claim resolved, the draft was gone — "New Delivery" now
opens a blank two-stop draft. Retiring on success is right; the observed state
drafted empty points for a user who never asked for a second order. A fresh
draft opening silently at "Where to pick up?" is defensible — but after a
placed order the sender more likely wants the Deliveries list than a blank
compose. Destination after `Done`/`Close` on a placed order is a navigation
decision worth a ruling.

## E. Draft hygiene — how the draft got dirty

### E1. Fixture litter blocks real orders

`--uitest-fields` left «Заказ» as a stored **required** field; an earlier seed
left "Schema seed". Both blocked a real order and both survive sync — they are
real rows, not ghosts. Fixture writes need a quarantine prefix or a cleanup
hook; a real order must never be hostage to test residue.

### E2. A pin drifted: "90 m · ~0m route estimate"

At one point the 2.8 km route read 90 m — a point's coordinates moved through
describe→"Save the point" cycles without anyone intending a move. Orphaned/drifted
points: the describe screen persists position on save even when the user only
meant to save the contact. Confirm-before-writing the geo half, or split
"Save the point" (geo) from "Save" (contact).

### E3. Identical rows, ambiguous target

Every stop offers a "Who receives" row with the same label. A UI test (and a
VoiceOver user) cannot tell stop 1's row from stop 3's without reading the
address above it — the row label itself should carry its stop: "Who receives —
pickup". A one-word change; a real a11y fix.

### E4. Fields mutate silently

«Тип груза» acquired "Коробка" during one session with no deliberate edit — a
stray tap on a choice field writes immediately. Not a defect, but the class of
thing that makes a draft feel haunted. Undo or dirty-marking would help; at
minimum the review sheet's field summary is the last honest readback.

### E5. Phone digits landed in the floor field

During contact entry, typed phone digits once went into a door-details pill
instead of the phone box — the pill row sits adjacent and focus/targeting is
easy to miss. Minor; worth one pass on hit-targets in the describe form.

## F. What demonstrably works — the credit side

- Blocker listing is **accurate and specific**: it named «Заказ», the empty
  contact, and the missing value correctly and completely.
- The disabled-CTA-beside-blockers fix verified visually — the sheet now reads
  "here's the order, here's what stands between".
- Fields editor: Optional toggle, Save, swipe-delete all behave; the tombstone
  syncs.
- Swipe-to-delete a middle stop works; the two-stop route priced five offers.
- The failed state renders a styled warning card (blue `!`), not raw text — the
  error chrome exists on this surface.
- End-to-end claim **placement and free cancellation both ran on the wire** —
  `createClaim` 200 → `acceptClaim` `accepted` → `performer_lookup` →
  `cancel_state: free` → `cancelled`. The whole wire path is sound; the
  failures are at its edges.
- The killed UI test proved the async flow is correctly owned: `placeOrder`
  survived the test runner's death and completed on-device.
- Scheduled-pickup bound is stated in the footer with the class-dependent
  ceiling — the bounds honesty pattern working as designed.

## G. Standing risks for the place-and-cancel loop

| Risk | What happened / mitigation |
|---|---|
| Courier assigned → cancel costs money | The live claim reached `performer_lookup` for 84 s and still cancelled **free**. Scheduled pickup (+1 h default, max +4 h courier / 5 d cargo) widens the rail further. |
| Retry at stale signature loops forever | Confirmed — one bounded retry only; then evidence capture. App fix pending (C1). |
| Failure screen lies about claim existence | Confirmed — every failed accept left a provider-side claim; check Deliveries after any failure. All seven here are terminal — no courier, no charge — but they are litter the sender cannot remove. |
| Price surges across retries | Confirmed — 1,659 → 1,888 ₽ across one evening of retries. |
| Killed test leaves a live claim | Confirmed — `placeOrder` outlives the test runner; any interrupted run must be reconciled from Deliveries (or the wire log). |

## H. Feeds

- `DesignSystemSemantics` — bound tint, OrderBar blocked naming, error chrome,
  status vocabulary, money-adjacent surfaces: every ruling now has a live case.
- TD register candidates: C1 (stale-requirement retry), D2 (status vocabulary),
  A4 (bar overlay), B3 (placeholder prices), B4 (reprice silence).
- `DeviceDriveTests` — now documents the real journey including workarounds;
  each workaround above names the app fix that would retire it.
