# Agent task — design-system research: semantics, hints, errors

Produce a **research plan** — not implementation — for hardening the app's design
system: the shared vocabulary every screen draws from. The trigger is a set of
misses visible on shipping screens (1.0 TestFlight) that no single component owns;
fixing them piecemeal would deepen the inconsistency the audit exists to close.

The plan's own deliverable is a doc (candidate home: `Documentation.docc/DesignSystem.md`
or a sibling) — a gap survey, a proposed vocabulary, a retrofit order, and the open
questions that need an owner's ruling. This repo's rules apply: everything lands via
PR, no AI attribution, cite sources in prose.

## What exists today — the survey's starting set

- `YDeliveryKit` holds the tokens and shared components: `Layout.Spacing.*`,
  `StatusChip`, `PointBadge`, `RouteLine`, the color/asset layer. `DesignSystem.md`
  (DocC) carries the field/density rules the New Delivery board ran on.
- Ad-hoc styling elsewhere: `.red` footnote hints, unstyled error strings, localized
  strings inline. No semantic color tokens — "red" is a raw color doing several jobs.
- Surfaces: `NewDeliveryView` (+ `ItemEditor`, `OptionsEditor`, `ReviewSheet`),
  `DeliveriesView`, `OrderDetailView`, `CustomFieldsView`, `SettingsView`,
  the share extension, `OrderBar`/`TariffStrip`/`EstimateBar`.

## Evidence already gathered — don't re-derive it

1. **Required-field hint** (`NewDeliveryView+Content.fieldRow`): red footnote prose
   inside the row, `if !isOptional && value.isEmpty`. Deliberate ("the blocker
   explains beside the field") but reads as floating section text, not footer —
   and it shares red with errors and destructive actions. No required *affordance*
   on the field itself (no marker distinguishing a required row from an optional one
   until it is already unmet).
2. **"What's inside" footer** says insurance trivia (`"The declared value is what
   the insurance covers."`) while the hard bound — the wire requires ≥1 item,
   live-verified — exists only in `orderBlockers` on the review sheet. Bounds are
   not discoverable where the decision happens.
3. **Error surfaces are unstyled**: claim-cancellation failure rendered plain error
   text — no icon, no tint, and no "share diagnostics" affordance even though
   Settings already carries `ShareLink("Share diagnostics log")`. (Raised in the
   @TF `claim_id` size-error session; the same session flagged logging gaps —
   logging is out of scope here, the *presentation* contract is not.)
4. **No status-color grammar for money-affecting actions**: cancellation has three
   outcomes the user must read at a glance — free / paid / failed. Owner's straw
   man: green = free, blue or yellow = paid, orange/red = error. Evaluate against
   HIG semantics and accessibility; do not rubber-stamp.
5. **"Not set" is a lie-shaped answer**: a required choice field offers `Not set`
   (writes `""`) as a selectable row — it looks like an answered state but keeps the
   required blocker. Consider placeholder semantics (a non-selectable prompt)
   instead of a tag among the choices.
6. **Locale mixing on one line**: field names render the sender's vocabulary
   («Заказ») beside English hint prose. Either localize the chrome or state the
   rule — today's read is accidental, not designed.
7. **`OrderBar` is mute about blockers**: "Order Courier · RUB 3,095.14" presents
   as ready while `orderBlockers` is non-empty — the review sheet carries the
   truth. Decide whether the bar reflects readiness (blocked style, blocker count,
   first-blocker preview) or stays silent by design.
8. **Reveal grammar is undefined** (owner report, 2026-10-03): expanding a
   delivery row's status trail made the timeline block land fully formed while
   the `List` cell was still stretching — `if isExpanded { … }` inserted with
   the default transition. Fixed on `feat/record-signing`'s tree:
   `.move(edge: .top).combined(with: .opacity)` on the inserted body, falling
   back to `.opacity` under Reduce Motion. `matchedGeometryEffect` was weighed
   and rejected — it morphs one element across two states and nothing here
   exists while collapsed. The open question is the *convention*: which reveal
   the house uses for "content appearing inside an animating container" —
   slide-in, fade-in, or a measured clipped reveal — and where it is written
   down so the next expanding surface (place pickers? draft sections?) doesn't
   re-derive it.
9. **Trailing-edge discipline**: the status line packed `chip | time | chevron`
   leading; the as-of stamp and disclosure mark now sit at the trailing edge
   (fixed with 8). `StatusTimeline`'s per-event stamps were already trailing —
   the row disagreed with its own expanded content. The question: "timestamps
   and accessories trail" as a stated rule, audited across rows.

## Questions the plan must answer

- **Semantic color tokens**: name the roles — `bound` (required-but-unmet is not an
  error yet), `info`, `success`, `warning`, `error`, `destructive`. Which system
  colors (`.red`, `.orange`, `.secondary`, tints) map to each, light/dark, and how
  tokens land in `YDeliveryKit` beside `Layout.*`.
- **Hint placement grammar**: when guidance lives inline vs section footer vs
  review sheet only; per-field vs per-section; the rule a contributor can apply
  without asking. The required hint is the worked example — is "beside the field"
  the convention or the exception?
- **Error chrome**: the canonical error row — icon? tint? message? action? — and
  when "Share diagnostics" attaches to it (transient vs terminal vs provider
  refusal). Define once; apply everywhere an error string renders.
- **Status colors for outcomes**: cancellation free/paid/failed as the first
  consumer; check the same roles serve tariff strip, status chips, sync states.
  Color is never the only channel — every status pairs a tint with words and/or an
  SF Symbol (accessibility rule: name the pairing, don't leave it implied).
- **Bounds discoverability**: which preconditions must be visible inline vs which
  may stay review-sheet-only — and the footer convention ("footer states bounds,
  trivia goes elsewhere" or whatever the ruling is).
- **Empty-section guidance**: `Add an item` exists but says nothing about *why* —
  should empty required sections say their bound in the empty state?
- **Required affordance**: marker on the field row itself (badge, caption, asterisk
  convention) vs hint-only — and what "answered" looks like (quiet, not green-check
  noise?).
- **Motion grammar**: which transition an inserted block uses inside an animating
  container, the Reduce Motion fallback for each, and where
  `matchedGeometryEffect` is actually warranted (shared element across states).
- **Preview coverage matrix**: the states every component must `#Preview` (empty /
  bound-unmet / error / success / loading) — the audit's regression net, since the
  repo already requires running previews per view.
- **Liquid Glass / iOS 26 fit**: whether semantic roles ride system materials and
  tint or need custom assets; what Apple's own apps do for the same jobs
  (App Store, Wallet, Health error+action rows) — cite the precedents.

## Method

1. Run the `swiftui-pro` skill (Paul Hudson's review checklist, installed at
   `~/.agents/skills/swiftui-pro` — vetted read before install, MIT) over each
   surface as a first pass; `twostraws/swift-agent-skills` is the umbrella
   catalogue if further specialist skills earn their place.
2. Inventory the surfaces above; tag every color/hint/error usage by role
   (a table, not a vibe): file, site, current treatment, proposed role.
3. Draft the vocabulary + placement grammar + error-chrome pattern with
   precedents cited (HIG, Apple apps, the repo's own `DesignSystem.md` rules).
4. Propose the retrofit order — smallest blast radius first; name which screens
   change in which PR.
5. List the open questions that need the owner's ruling (this doc's evidence
   section is allowed to pre-answer obvious ones, flagged as proposals).
6. Validation story: preview matrix + the existing screenshot-test seam; no
   implementation in this task.

## Explicitly out of scope

- Implementation of any component or token.
- The logging/diagnostics backend gaps (separate session's finding — only the
   *share-diagnostics affordance's placement contract* belongs here).
- Copy rewrites beyond what the vocabulary decisions require.

## Slices

0. This doc — own PR.
1. The plan doc (survey + vocabulary + grammar + retrofit order + open questions).
