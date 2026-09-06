# What moved under you — Devin round 2, PRs #18–#22, 2026-09-06

For the Fable creator session. Transient: delete once read.

**Your tree was clean when I started and is clean now.** Nothing of yours was stashed,
parked, or edited out from under you — this round was all committed work on the branches.

## The stack was rebased again; five branches force-pushed

| PR | Branch | Was | Now |
|---|---|---|---|
| #17 | `feat/draft-route-card` | `3a32930` | unchanged |
| #18 | `feat/picker-upgrades` | `16f321a` | `29cad66` |
| #19 | `feat/estimate-bar` | `5435e52` | `f7094d9` |
| #20 | `feat/tariff-strip` | `93cf4bc` | `08d785d` |
| #21 | `feat/parcel-options` | `b647202` | `655de1d` |
| #22 | `feat/review-sheet` | `ed4adb1` | `66dd1bf` |

All six merge into `main` in order with no conflicts; the merged result passes 139 tests in
15 suites. `main` also gained `.devin/wiki.json`, which touches nothing here.

## What changed in your slice-5 and slice-6 code

**#21 — four fixes.** `DeliveryOptions.due` now reaches `OfferRequirements`, so a scheduled
pickup is priced as scheduled; it also counts toward the container being non-empty.
`setScheduled(_:within:)` moved the «Scheduled pickup» switch's *meaning* into the model —
toggling on used to write nothing, so a schedule saved without touching the picker departed
immediate. `removePoints` releases item stop references, and `OfferRequest`'s initializer
normalises them again. The courier note left `pricingInputs`. And `itemsThatDontFit` got the
caller your PR description promised — explainer cards now carry a misfit line.

**#22 — five fixes, mostly in `placeOrder`.** The state machine now switches on the claim's
status: only `readyToAccept` accepts, `searching` is recognised as already placed, an
unknown status throws `OrderingUnknownState`. A new `Ordering.unresolved` case exists for a
failure *during* acceptance — the old catch said "nothing was charged", which cannot be
known then. Recording is a one-time transition (`placedOrderIsRecorded`) and
`OrderStore.record` is idempotent by `Order.id`. `OrderRequest` normalises item stops like
`OfferRequest`.

## Things you may bump into

- **`ContactChoice`** replaced `Contact?` in `PointPickerView.confirm` (#18). `nil` meant two
  opposite things; a contactless chip now says `.replace(nil)`, refining says `.unchanged`.
- **`Ordering` gained `.unresolved(String)`** — any `switch` over it needs the case.
- **`OfferRequest.items` and `OrderRequest.items` are `private(set)`** and normalised in
  their initializers. Construct through the init; don't reach around it.
- **`StoreController` gained `historyUnavailable` and `hasPlacedAnOrder`.** The explainer
  gate uses the latter, not `orders.isEmpty`.
- **`OffersUnreadable`** is thrown when every offer in a response fails to parse.

## Three things for Pavel, not for you

Raised in the PR threads and in my report: whether CLAUDE.md rule 6 covers the ordering poll,
whether "first successful order" means placed or delivered, and a due-window discrepancy
between DESIGN-HANDOFF §4 and the vendored spec. Don't act on those until he rules.

Devin's re-review of this round had not landed when this was written.
