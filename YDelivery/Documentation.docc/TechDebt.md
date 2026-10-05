# Tech Debt

Compromises this app carries. Each names what it costs and what would retire it. Reference
one from code as `// TODO(YD-n): …` — *YD* so these never collide with the package's `TD-n`
or the demo's `AD-n`. Numbers are never reused.

## YD-1 — No CI — **discharged**

Every verification was a laptop ritual: `xcodebuild build … -skipPackagePluginValidation`
and the test action, run by whoever remembers.

- **The cost it carried:** a broken `main` is discovered by the next person to pull it,
  and "the previews all run" is asserted, never checked.
- **Discharged by:** `.github/workflows/ci.yml` — `xcodebuild test` on the full scheme
  (unit + UI suites) on `macos-15` with `latest-stable` Xcode, on every PR and every
  push to `main`, both skip-flags carried (`-skipPackagePluginValidation` keeps the
  OpenAPI generator plugin's trust prompt from failing non-interactive builds).
  `project.pbxproj` is gitignored, so the workflow regenerates it with `xcodegen`
  from the committed `project.yml`. All three repos are public — standard runners
  need no secrets.

## YD-2 — The test targets are template stubs — **discharged**

`YDeliveryTests` held one empty `@Test`; the UI test target was the Xcode template
verbatim.

- **The cost it carried:** the test action was green and meant nothing — worse than red,
  because it looked like coverage.
- **Discharged by:** the first real logic arriving with its suites (2026-08-28) —
  `TokenStoreTests` runs the Keychain round-trip against per-test service names, and
  `ClientControllerTests` pins the session lifecycle, including the trimmed-and-persisted
  token and the rendered empty-token error. The UI target keeps exactly the launch smoke
  test.

## YD-3 — SF Symbol names are raw strings — **discharged**

`Image(systemName: "chevron.forward")` and its siblings compile whether or not the symbol
exists; a typo renders an empty image at runtime (author's review, 2026-08-28).

- **The cost it carried:** no compile-time safety over an asset namespace that changes
  with every OS.
- **Discharged by:** [SFSafeSymbols](https://github.com/SFSafeSymbols/SFSafeSymbols) 7.0.0
  (2026-08-30) — a dependency of `YDeliveryKit` from its first commit, then one sweep
  over the app's call sites. The demo repo already depended on it, so this is alignment.
  Availability annotations also enforce the iOS 17 floor per symbol, which the
  DesignSystem's pin table asks to be verified by hand. The one exception: MapKit's
  `Marker` has no SFSafeSymbols overload, so it takes `SFSymbol.mappin.rawValue` — still
  compile-checked.

## YD-4 — The project file is hand-maintained — **discharged**

The pbxproj was hand-edited for the floor, language mode, and the package dependency.
Buildable folders keep file lists out of it, but build settings still live in a format no
contributor should have to untangle — and the house precedent is XcodeGen
(`NetworkObserverSample/project.yml`).

- **The cost it carried:** settings diffs were noisy to review; a second target (widgets,
  App Intents) would have multiplied the hand-editing.
- **Discharged by:** `project.yml` at the repo root (2026-08-30) — synced folders, the
  same package pin, and effective build settings verified equal by diffing
  `xcodebuild -showBuildSettings` per target before and after (the residue restates Xcode
  defaults). The pbxproj and the generated scheme left version control; `xcodegen generate`
  recreates them after cloning or editing the spec.

## YD-5 — An unresolved acceptance does not survive a restart — **discharged**

`acceptClaim` can time out or fail *after* the provider took it: the flow renders
`Ordering.unresolved` with a read-only «Check again» (`reconcileUnresolved(watch:)`), but
that state lived in the draft model only. Force-quit mid-reconcile and the app forgot a
claim that may be spending money; the vendor remembers.

- **Discharged by:** the `pendingAcceptances` device-tier table — schema-forwarded
  by <doc:Schema>, given writers in `YDeliveryKit` 0.3.5. The ordering flow notes
  the claim id the moment the answer is lost (`ClaimsSyncController.
  noteUnresolvedAcceptance`), and every journal tick's
  `drainPendingAcceptances` asks after it: a claim already in history resolves
  by presence, a fetched card merges into an order and resolves with the link,
  a silent one stays pending for a week then lapses — the poll stops, the audit
  row remains. The identity boundary wipes the table with the rest of the
  sync state.
- **The cost it carried, before discharge:** Phase 3's claims sync had already
  narrowed the forgetting to one reconcile gap — the pending id lived between
  the timeout and the next search tick, a row that could sit stale for one
  poll cycle. Now the gap is a 30-second drain at worst, and the attempt
  itself is auditable.

## YD-6 — Item rows do not show their journey — **discharged**

`repairItemJourneys()` keeps per-item stops valid across delete, reorder, `setRole` and
`setItem` — but the row rendered name and summary only, so a repaired (released) stop
reference changed silently.

- **The cost it carried:** on multi-stop routes a sender could believe an item still
  boarded where it no longer did; the truth was one editor-open away, which was one
  too far.
- **Discharged by:** `journeyLine(for:)` on the draft model — the item row carries
  «A → B» in the stops' own words whenever the route has middles, and point rows
  state what the parcel does at their door (`parcelActions(at:)`, Round 5, #45–46).
  Both directions render while the author chooses between them (2026-09-18).

## YD-9 — Editing a contact opens the whole point flow — **open**

The point row's contact line pushes the same picker the address uses, landing on
Describe (decision #40's one flow). It is usable — the author tried it — but a
two-stage stack for what reads as "edit the person" is heavier than the ask
(author, 2026-09-18).

- **Cost:** an unusual re-entry for the most common edit; the design language for
  "open the person, not the point" does not exist yet.
- **Discharge:** a re-entry that targets the tapped fact *within* the one flow —
  e.g. Describe scrolled to the contact section, or a lighter sub-editor — once the
  next design round names it.

## YD-10 — The wire's `building` (корпус) field has no UI — **discharged**

`AddressParts` covers entrance/floor/apartment/intercom; the claim schema also takes
`building` — «строение или корпус» — which the app never collects (DeepWiki consult
on `openapi.yaml`, 2026-09-18). The no-building warning added beside it catches a
*missing house number*, a different fact.

- **Cost:** addresses like «д. 15, корпус 2» can only be typed into the address line,
  not structured — the wire field exists and goes unfilled.
- **Discharged by:** `AddressParts.building` (Kit `0.3.7`) — collected on the
  picker's describe stage («bldg.»), rendered as the callout's leading chip,
  persisted on every point-bearing table (`routeStops`/`savedPlaces`/`draftStops`
  gained the column), mapped to the wire's `building` on the way out and read back
  from claim responses. `porch`/`sfloor`/`sflat` do not duplicate it — they are
  door details, while `building` qualifies the address itself; `destinationKey`
  folds it in so «Тверская 6, к. 1» and «к. 2» stay distinct memories.
- **On the `subThoroughfare` half:** carrying `CLPlacemark.subThoroughfare` into
  `PickedPlace` was considered and deliberately not done — the picker's own
  `deliveryAddress` composer already writes it into `fullname`, which is exactly
  the string `lacksBuilding` reads, so the fact reaches the heuristic today. A
  separate stored copy would only duplicate `fullname`'s content and go stale the
  moment the sender edits the address; the residual blind spot (pasted or typed
  addresses) has no placemark to carry the fact from anyway.

## YD-7 — Post-draft statuses read as unknown — **discharged**

`PlacedClaim.Progress` collapses exactly the statuses the ordering flow decides on;
`pickuped`, `delivered`, `cancelled` and the rest of the zoo land in `.other(raw)` —
honest, but dumb copy if ever surfaced.

- **The cost it carried:** any surface polling past acceptance showed a raw wire word.
- **Discharged by:** `OrderStatus(claimStatus:)` in `Model/ClaimSync.swift` (2026-09-23)
  — the full wire→`OrderStatus` vocabulary the claims list needed anyway: statuses
  parked on the sender's decision (`ready_for_approval`, `performer_not_found`,
  `pay_waiting`, `returned`) read `attention`, the courier's working states read
  `active`, and nothing reaches a row as a raw word. `.other` survives only inside
  `PlacedClaim.Progress`, where it still means "the draft's job is done" — the
  flow's vocabulary, correctly narrower than history's.

## YD-8 — DMS coordinate strings are a documented parse gap — **discharged**

<doc:LinkGrammars> lists `55 45 20.9N …` as a raw-string row; `MapLink` parsed decimal
pairs and hemisphere suffixes only, and the tests recorded the gap.

- **Cost:** a pasted DMS pair was not offered at all — rare on phones, common on paper.
- **Discharged by:** a DMS arm in `rawCoordinatePair` — two hemisphere-lettered axes
  (the letter is mandatory and labels the axis, so axis order never gets guessed);
  minutes and seconds bound at < 60, degrees inside the hemisphere's bound. Tests
  cite the grammar row and the unprovable declines.

## YD-11 — `createClaim`/`acceptClaim` still read `.ok` and bury refusals — **discharged**

`offers(for:)`, `claimState`, and the cancel pair now switch the documented response
cases so the provider's `{code, message}` reaches the strip as `ProviderRefusal`
(PR #31, and the cancellation PR that followed). `createClaim` and `acceptClaim` still
reached for `response.ok`, which threw an accessor error on a documented refusal — the
provider's sentence lost at exactly the calls where money moves.

- **Discharged by:** `createdClaim(from:)` and `acceptedClaim(from:version:)` — the
  same static `…(from:)` mapper the fixed call sites use, so a refused create or
  accept renders «тариф недоступен» / the 409 stale-version sentence instead of the
  generic failure.

## YD-12 — The wire log holds route PII; sharing it is the consent act — **open**

`WireLogStore` writes every request and response body verbatim — addresses, recipient
names, phone numbers, door codes — to `wire-log.jsonl` in Application Support, so an
engaged user can produce real wire evidence (the package's TD-22 is the first customer).
The file never leaves the device on its own; the Settings ShareLink is the only way out,
and its footer says what the log contains. It is `.complete`-protected against
locked-device reads, wiped on sign-out and on a fresh sign-in (a new credential is a new
identity), and bounded — but none of that narrows what a *deliberate* share carries.

- **Cost:** anyone the user shares the file with sees everything in it, and the file
  persists across launches — that persistence is the point (a force-quit must not lose
  the evidence), so there is no "session only" softening to hide behind.
- **Discharge:** a real privacy pass when the feature earns one — field-level redaction
  on share (names and door codes masked, addresses and statuses kept), or a capture
  window toggle so the log is opt-in rather than always-on. Neither is worth building
  before the first shared log proves the mechanism earns its keep.
  The planned event records (Design → The rest of the app is not in the file)
  widen what the shared file holds and must stay PII-free by construction —
  identifiers and error descriptions only.

## YD-13 — A superseded sync pass can complete one in-flight write — **open**

`persistChanged` re-proves `identityGeneration` before each `store.record`, but the
record call itself suspends — an identity change landing *inside* that write lets the
old account's row complete past the boundary (Devin Review, PR #35). The guard catches
the *next* row; the one in flight is unreachable.

- **Cost:** bounded today, deliberately — `OrderStore` is not per-account (the identity
  wipe covers the sync state; device history persists across sign-in by design), so a
  late row joins a file that legitimately holds same-class rows already. It becomes a
  real cross-account write the day orders are owner-scoped.
- **Discharge:** the owner-scoped order schema under the persistence-stack migration
  (<doc:Collaboration>) — the same redesign that gives records their `CKShare`
  hierarchy. A compensating un-record is the fallback only if the file store outlives
  the spike; the store has no delete API today and growing one to fence a one-row edge
  is the chaos the register exists to avoid.

## YD-14 — The provider can black-hole connections under burst load — **discharged**

Field check, 2026-09-23: after ~20 read-only requests in five minutes, every endpoint —
`claims/journal`, `claims/search`, `claims/info`, `offers/calculate` — hung at the
transport level (curl `-1001`, no HTTP status, no `Retry-After`), still silent 25+
minutes on. Minutes earlier the same window had both discovery endpoints answering and
decoding clean, so the wire contract is not in question; the provider's failure mode
under load is a silent stall, not a refusal.

- **Cost:** a sync pass can stall for the URLSession default — 60 s per request;
  `URLSessionTransport()` sets nothing tighter — so a throttled pass lingers for
  minutes across pages while `isSyncing` holds the gate. It recovers on the next tick,
  but the stall is invisible.
- **Discharged by:** `ClientController.providerSession`, a `URLSession` with an
  explicit 30 s `timeoutIntervalForRequest` handed to the transport the API package's
  `transport:` parameter now accepts (YandexDeliveryExpress 0.3.1) — a stalled request
  fails in tens of seconds and the page budgeting `maxPages` bounds a pass on top.
  The transport's own timeout, not a wrapping `Task`: a cancelled task can leave the
  socket open, and the stall is the thing being bounded. If the stall ever proves
  adaptive (throttling that answers eventually), revisit *which* timeout before
  widening it.

## YD-15 — `routeStops.role` is position-derived, not model-carried — **discharged**

Discharged: `RoutePoint.role` (`pickup`/`dropoff`/`return`, Kit `0.3.9`) is the
carrier end to end. The draft already sent roles to the wire; claim sightings
now map `point.type` back through `RoutePoint(claimPoint:)`, so provider-
discovered routes carry them too. `insertStops` writes the carried role with
position as the fallback for roleless points, `routeStop(_:)` reads it back
(an unknown spelling reads roleless, never drops the stop), and `RouteLine`
honors it — a return leg renders the return mark, not a mislabelled drop-off.
`Order.destinationPoint`/`[RoutePoint].destinationIndex` answer "where is the
parcel going" as the last *drop-off*, keeping the notification title, Live
Activity, share text, intents, the widget snapshot and the detail map's ETA
honest when a return leg rides last. `init(repeating:)` restores carried
roles; reversed repeats re-derive by position since direction recasts the
stops. `destinationKey` deliberately excludes role — a place's function is
context, not identity. Item journeys follow the same end: a `nil` handover
means the last drop-off, not the last seat — `defaultHandoverIndex` is the
one home the callout, the repair pass, the editor's chooser and both wire
writes read, so a return leg can never answer an unmarked parcel's journey.

## YD-16 — Draft field values are memory, not disk — **discharged**

Discharged: the draft tier is real columns (`orderDrafts` carries the options
set and the remembered class; `draftStops`/`draftItems` mirror the shared shape;
`draftCustomFields` holds values plus revealed-but-empty disclosures, `NULL` =
disclosed-unanswered), and `NewDeliveryView.Model` runs a save-on-edit loop —
`persistDraftChanges` observes the `persistedDraft` projection, debounces
400 ms, writes whole snapshots through `StoreController`'s serialized tail, and
flushes on `.background`. `init(restoring:)` rebuilds the model at launch,
gated on `isPristineDraft` so a read that loses to a fast typist never eats
their words; a route that cannot satisfy the invariants falls back to the
founding pair rather than resurrecting something uneditable. Consumed on
`placed` — a queued save cannot resurrect the row because the consume rides the
same tail and the loop is disarmed first. Reads decode without the trapping
subscript so a corrupt draft throws instead of self-wedging every launch
(Kit `AppDatabase.ReadError`).

- **Cost:** minutes of re-typing at worst; no money moves and no provider state
  forks — a draft has no provider existence by definition.
- **Discharge:** real columns on `OrderDraft` + children, a `draftCustomFields`
  (or denormalized values on the draft row), and a save-on-edit loop — the schema
  anticipated it; the slice landed without it because an in-memory draft is the
  honest minimum while the draft tier's own shape is still provisional.

## YD-17 — A deleted order-number definition orphans its saved values — **discharged**

`OrderCustomField` snapshots `carrier` at write time (Kit `orderCustomFields.carrier`,
with a migration backfilling pre-existing rows from the schema that typed them), and
every reader — `orderNumber(for:)`, `SpotlightIndexer` — resolves off the value's own
snapshot. The wider finding review surfaced was worse than the deleted-definition edge:
the definitions tier is *private*, so a collaborator could never have joined it — the
denormalized snapshot is what makes the shared tier self-describing (Kit PR #8).

## YD-18 — A cancelled request's wire record can race the identity wipe — **discharged**

`signIn` invalidates the previous identity's `URLSession` *before* `wireLog.clear()`
(review, PR #49), so a task in flight can no longer complete a real response into the
wiped log. `invalidateAndCancel` was synchronous about the socket but not about the
middleware: a cancelled task still unwound through `WireLogMiddleware`, which records
the exchange — *with the request body* — and that append was scheduled on the store's
own queue. It could land after `clear()` had run, leaving one old-identity record in
the new identity's shareable log.

- **Discharged by:** a write epoch on `WireLogStore`. `clear()` bumps the epoch inside
  a lock in the same actor hop as the removal; `WireLogMiddleware` mints its stamp at
  init (the session's generation — a middleware dies with its client, so it can never
  outlive a wipe); `append(_:epoch:)` drops anything stamped under a superseded epoch.
  The gate sits on the store, so the bump-plus-wipe ordering holds regardless of when
  the late append is scheduled — no drain latency on sign-in. The drain alternative
  (`finishTasksAndInvalidate` plus settling) was rejected in the register: paying
  latency on every sign-in to fence a one-line leak is the wrong trade.

## YD-19 — The provider prices routes it will not carry — **open**

Device-drive finding B1: a three-stop route priced exactly one offer, and the
accept refused outright — «Для точки назначения 2 нет отправлений», no shipments
for the middle point. Pricing promised what the claim stage refuses; the sender
invests contacts and item values into a route that can never be ordered.

- **Cost:** a dead route reads as a priced route until the refusal — and the
  refusal names "point 2" in provider jargon, not the stop the sender knows.
- **Discharge:** surface per-point serviceability at pricing time if the API
  exposes it (check `offers/calculate`'s per-point fields); at minimum translate
  the refusal — map the point index back to the draft's own stop name.

## YD-20 — A shrinking offer count explains itself nowhere — **open**

Device-drive finding B2: the three-stop route priced one offer; the same two
endpoints priced five. Provider-side filtering (class capability × route ×
requirements) is legitimate — but the strip just shows fewer cards. The explainer
names *item* misfits; nothing says why a class is absent entirely.

- **Cost:** a sender watching five cards become one can't tell provider filtering
  from a bug, and may re-enter data to coax offers that cannot exist.
- **Discharge:** one honest caption when known classes go unpriced — "only Courier
  serves this route" — derived from the classes the explainer already knows about.

## YD-21 — The loading strip's skeleton may not read as redacted — **open**

Device-drive finding B3: while offers loaded, the tester read **999 ₽** as real
prices on every card. The code has redacted those placeholders since PR #20
(`TariffClass.placeholders` + `.redacted(reason: .placeholder)`) — so either the
drive's build predates the merge, or `.redacted` is not surviving the card's
composition (custom `Button` label, `.contentTransition(.numericText())`).

- **Cost:** if the skeleton does not render, one accept at a placeholder price is
  a real claim at a fake price — money moves on a number that never existed.
- **Discharge:** reproduce on device or sim; if redaction is being neutralised,
  drop the numeric transition in placeholder state or draw the card's own
  skeleton shape. Verify with the strip's loading preview, not the code's intent.

## YD-22 — An options toggle's centre tap lands dead — **open**

Device-drive finding C3: `To the door`/`Scheduled pickup` switches would not flip
on a centre `.tap()` — the element spans the whole row and the knob sits at its
right edge. The drive worked around it by aiming at the knob (a11y smell, surfaced
through test-infra).

- **Cost:** a control that ignores a centre tap is a control VoiceOver and
  switch-control users may not be able to operate — the workaround required
  knowing where the knob lives.
- **Discharge:** an a11y pass on the options rows — confirm the toggle's
  hit-target frame covers the row, or the row's tap forwards to the switch; then
  drop the test's coordinate-aimed workaround.

## YD-23 — Claims created-but-never-carried litter the history — **open**

Device-drive finding D1: every failed accept still created a provider-side claim
(seven across one evening). Reconciliation correctly ingested each as terminal —
the machinery worked; the landmine is that a claim can exist while the sender is
told the order failed, and the account accumulates refused claims a sender cannot
remove.

- **Cost:** "order again" can mean "pay twice" — the litter is real claims with
  real claim IDs, indistinguishable in count from orders the sender meant.
- **Discharge:** a cleanup story — provider-side archive/cancel for terminal
  refused claims if the API offers one, or a list affordance that hides
  never-dispatched claims from the running history (keep the audit trail;
  stop counting them as orders).

## YD-24 — The scheduled-pickup safety rail is capped at hours — **open**

Device-drive finding D3: the owner's rule is future-date claims so
cancel-before-dispatch stays free — but the provider ceiling is +4 h for Courier
(5 days for Cargo). A sender wanting next-week delivery on the class a small
parcel needs has no rail; the bound is honestly stated, the ceiling is the
provider's.

- **Cost:** the free-cancel window strategy doesn't reach the common "send it
  next week" ask for Courier.
- **Discharge:** provider-side — confirm whether the API exposes a longer
  window on other parameters; if not, record it in the package's TechDebt and
  keep the footer honest about the ceiling (it already is).

## YD-25 — A placed order retires the draft into a blank compose — **open**

Device-drive finding D4: when the parked draft's claim resolved, "New Delivery"
reopened a blank two-stop draft — empty points for a sender who never asked for
a second order. Retiring the draft on success is right; the *destination* after
Done is not.

- **Cost:** after placing an order the sender more likely wants the Deliveries
  list (or the new order's detail) than a fresh compose — the current default
  invites an accidental second draft.
- **Discharge:** a navigation ruling — land on Deliveries (or the placed order's
  detail) after a successful place, keeping "New Delivery" for a deliberate ask.

## YD-26 — Fixture writes live in the sender's real store — **open**

Device-drive finding E1: `--uitest-fields` left «Заказ» as a stored *required*
field and an earlier seed left "Schema seed" — real rows that blocked a real
order and survive sync. Test fixtures and production data share one store.

- **Cost:** a real order can be hostage to test residue — the blockers were
  accurate, which is exactly what makes fixture litter dangerous.
- **Discharge:** a fixture quarantine — prefix-marked writes the seeded paths
  recognise and a cleanup hook that purges them, or a fixture-scoped store the
  seeds can target without touching the sender's data.
- **Partly discharged** — the schema seed writes an isolated database and
  deletes its rows (#90); the `--uitest-*` fixtures still write the real store

## YD-27 — A point's coordinates can drift on a contact-only save — **open**

Device-drive finding E2: a 2.8 km route once read 90 m — a point's geo moved
through describe→"Save the point" cycles where the sender only meant to save a
contact. The save persists the whole point, position included.

- **Cost:** silent geo drift prices and routes a parcel to a place nobody
  chose — the class of wrong that reads plausible, not broken.
- **Discharge:** confirm-before-writing the geo half — a save that notices the
  pin moved asks first — or split "Save the point" (geo) from "Save" (contact).

## YD-28 — "Who receives" rows are indistinguishable across stops — **open**

Device-drive finding E3: every stop offers the same "Who receives" label; a UI
test (and a VoiceOver user) cannot tell stop 1's row from stop 3's without
reading the address above it.

- **Cost:** a real a11y defect on multi-stop routes — the label is the handle,
  and the handle names nothing.
- **Discharge:** a one-word change — the row label carries its stop ("Who
  receives — pickup"), matching the placeholder variants already per-stop.

## YD-29 — Choice fields write on stray taps — **open**

Device-drive finding E4: «Тип груза» acquired "Коробка" mid-session with no
deliberate edit — a stray tap on a choice field writes immediately. Not a defect,
but the class of thing that makes a draft feel haunted.

- **Cost:** the review sheet's summary is the only honest readback; silent
  writes between visits erode trust in what the draft says.
- **Discharge:** undo or dirty-marking for choice fields — at minimum a visible
  diff cue on fields changed since the sheet was last reviewed.

## YD-30 — Describe-form hit targets misroute typed digits — **open**

Device-drive finding E5: typed phone digits once landed in a door-details pill
instead of the phone box — the pill row sits adjacent and focus/targeting is
easy to miss.

- **Cost:** nonsense rides to a courier (a floor that reads like a phone
  number) unless a second pass catches it — the drive cleared exactly that.
- **Discharge:** one hit-target pass on the describe form — target frames and
  focus order verified where pills sit beside the contact fields.

## YD-31 — Route estimate rides a region-gated graph — **open**

Device-drive finding: `MKDirections` `.automobile` returned a ~90 m/16 s stub for
a 5.3 km Moscow route instead of failing — on-device proof that driving coverage
degenerates rather than erroring in Russia (the same device routes 4 km in NYC
correctly; `.walking` returned the real 6.2 km; `.transit` errors honestly with
`MKErrorDomain 5`; `.any` resolves to automobile and degenerates the same way).
The estimator now gates each leg against the geodesic — a road route can never
be shorter than the straight line between its ends — and retries the leg as
`.walking`, so distance and the map curve stay true at pedestrian pace.

- **Cost:** the estimate's time side reads as walking pace even for vehicle
  classes (cargo, express), and the polyline is foot geometry — honest today,
  wrong-flavored for a van.
- **Discharge:** tie transport to the tariff's vehicle class — foot for
  courier, automobile-with-the-same-geodesic-gate for cargo/express — and once
  offers land, take the time side from `deliveryInterval`/`pickupInterval`
  (the provider's own courier ETA beats MapKit's pace). If real road curves are
  ever wanted, MKDirections cannot supply them here — Yandex MapKit Router,
  2GIS, or OSRM are the realistic geometry sources; no `.bicycle` mode exists
  in `MKDirectionsTransportType` for a cycling estimate. Apple's availability
  page lists Russia under Turn-by-Turn Navigation but not Transit/Cycling, so
  the service tier visibly trails the advertised list — re-probe `.transit`
  and `.automobile` on major OS releases.

## YD-32 — Same-class offers differ only by price — **open**

The provider returns several offers per class — wire evidence: `courier` arrives
as `express`, `express_30min_longer`, `2_hours_delivery` at different prices.
The tariff card renders class name + price and nothing else:
`Offer.pickupInterval`/`deliveryInterval` are parsed but rendered nowhere, and
the wire's `description` — the provider's own name for the speed/price
trade-off — isn't mapped at all. The sender sees two «Курьер» cards at
different prices and is left to guess why.

- **Cost:** choosing between same-class offers is a price lottery — speed is
  the thing being priced, and nothing on the card names it.
- **Discharge:** the tariff-cards slice (<doc:Roadmap> → Now): the provider's
  pickup/delivery windows on every card, Fastest/Cheapest sort, and a re-price
  when the ten-minute `offer_ttl` lapses.

## YD-33 — The background-refresh launch handler has no automated test — **open**

The handler registered in `YDeliveryApp.init()` only runs when iOS launches a
`BGAppRefreshTask`. CI, the unit suites and UI tests never reach it, and a debug run
doesn't either unless someone triggers it by hand. That is how a launch handler on
the wrong queue shipped in TestFlight 1.0 (1) and trapped in the field
(<doc:Design>, "Background refresh is delivered on the main queue").

- **Cost:** any regression in the handler's isolation, cast or completion reporting
  shows up only as a field crash or a quietly dead refresh chain. Swift Testing's exit
  tests can't host the check either: they don't run on iOS.
- **Today's ritual, on a device:** Apple documents the simulate calls as device-only
  ([Starting and Terminating Tasks During Development](https://developer.apple.com/documentation/backgroundtasks/starting-and-terminating-tasks-during-development)).
  Run with the debugger attached, let launch finish (an early pause lands in dyld,
  where expressions can't resolve), pause, then:

  ```
  e -l objc -- @import BackgroundTasks
  e -l objc -- (BOOL)[[BGTaskScheduler sharedScheduler] submitTaskRequest:[[BGAppRefreshTaskRequest alloc] initWithIdentifier:@"com.learnable.YDelivery.claims-refresh"] error:nil]
  e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.learnable.YDelivery.claims-refresh"]
  continue
  ```

  The `@import` is needed in a Swift-only binary. The explicit submit is needed
  because the app arms a request only on `.background`; without one the scheduler
  logs "No task request … has been scheduled" and does nothing.
  `_simulateExpirationForTaskWithIdentifier:` exercises the expiry path the same way.
  To see the pass finish, break on `-[BGAppRefreshTask setTaskCompletedWithSuccess:]`
  (the success flag is in `x2`). The subclass overrides it, so a breakpoint on the
  `BGTask` method never fires. Verified 2026-10-01 on iOS 26.6.2: the unfixed handler
  trapped on `com.apple.BGTaskScheduler (…)`, and the fixed one completed on main with
  `YES`.
- **Discharge:** a seam that lets a unit test invoke the registered handler from a
  non-main queue, or a UI-test hook that triggers the launch. Either has to stay out of
  the shipped binary: the private selectors are grounds for App Store rejection.

## YD-34 — sqlite-data swallows a re-insert under an existing key — **discharged for the Kit's writers (0.4.13)**

Upstream `sqlite-data` (1.12.0) loses a row that is deleted and re-inserted under
the same primary key in one transaction — the exact shape of `recordOrder`'s
stop/custom-field rewrite and every `INSERT OR REPLACE` rerun. The `afterDelete`
trigger marks `SyncMetadata._isDeleted` and queues a remote `.deleteRecord`; the
`afterInsert` trigger's `SyncMetadata.insert` then lands on `ON CONFLICT DO
NOTHING` against the still-existing metadata row, so `_isDeleted` stays set and
**no `.saveRecord` is ever queued**. The remote delete ships; the re-created row
never re-uploads. The row sits locally healthy while every other device loses it.

Found while seeding the development schema (`--ckschema-seed`, 2026-10): a rerun's
stops never re-serialized, which is why a column added to the row descriptor
(`building`) could not reach the dev schema until the seed issued a plain UPDATE —
the one write shape that always re-marks the row save-pending.

- **Cost:** every `recordOrder` remotely deletes the order's `routeStops` and
  `orderCustomFields`; the local copies persist, so it is silent. Columns added to
  a synced row type can never reach CloudKit for rows written this way — the
  serializer only runs on an upload, and no upload is ever queued.
- **Discharge:** discharged for the Kit's writers in 0.4.13 (Kit #41). Every synced
  write is now an explicit upsert plus a prune — `routeStops`,
  `orderCustomFields`, `savedPlaces`, `parcelTemplates`/`parcelTemplateItems` —
  never a delete-then-reinsert, never `INSERT OR REPLACE`, so the metadata stays
  alive and every edit re-queues. A cleared custom field keeps its row with an
  empty `value` rather than tombstoning a key a refill would reuse, and a copied
  template item writes under a derived id (`templateID ‖ copiedItemID ‖
  occurrence`) instead of re-homing another template's row; the tombstone window
  (a deleted key re-created before the server acknowledges the delete) is named
  at `insertStops` for the day routes become editable after placement. Confirmed
  in `sqlite-data` 1.12.0 source (`Internal/Triggers.swift`: `afterInsert` →
  `SyncMetadata.insert … onConflictDoUpdate { }`, a no-op; `afterUpdate` bumps
  `userModificationTime` but never clears `_isDeleted`; `afterDeleteFromUser`
  sets it) — and `INSERT OR REPLACE` never bumps `userModificationTime` either
  (SQLite's REPLACE fires no delete trigger without `recursive_triggers`), so a
  replaced row's edit never uploads. The residual: the upstream behaviour is
  documented in the Kit README as a write rule rather than fixed upstream, so a
  future raw write could regress it — that stays as this item's last line.

## YD-35 — Unit tests pass only in English — **open**

Eight unit tests compare user-facing sentences against English literals. On a device or
simulator set to Russian they fail although the app behaves correctly (seen on a
Russian-language device, 2026-10-05):

- `DeliveriesRowsTests/searchHaystack`, `attentionRowNamesItsWait`
- `NewDeliveryOrderingTests/everyInvalidItemGetsItsDoor`, `staleFieldCacheBlocks`,
  `requiredFieldBlocks`, `doorMeansTheOption`, `estimationTimesOut`
- `LocalizationTests/englishFallback`

CI pins no language. Its runner simulator defaults to en-US, so these pass there and
the dependence never shows up in CI.

- **Cost:** a local run on a Russian-language device, this app's main audience, shows
  red for nothing. Real regressions hide among the false ones, and each run gets
  re-diagnosed.
- **Discharge, one of:**
  - **A prerequisite:** pin the test language, through the scheme's test action
    (`project.yml`) or `xcodebuild -testLanguage en -testRegion US`, so every run
    sees English. Cheapest, but it hides how the code behaves in Russian.
  - **Locale-aware:** compare against `String(localized:)` of the same key, a
    convention several tests already follow (`blockersStateTheBounds`,
    `undialablePhoneBlocks`).
  - **Locale-agnostic:** assert on what the sentence is built from (the item's ordinal,
    the blocker's destination, the status kind) rather than on its prose.
  - Whichever is chosen, `englishFallback` needs a bundle it can force to English.
    The question it asks only exists in that language.

## YD-36 — `sdd_long`'s meaning is unsourced — **open**

`TariffClass.sddLong` shows as «Same-day» / «День в день» with the blurb "A longer
run, still within the day". It has no weight or size bounds, so every parcel fits.
None of that is sourced. The package spec has carried `sdd_long` since its first
layout with only «принят на веру из документации», and Yandex's own pages (the
package's `Upstream/yandex-docs` cache) never mention it. Every `taxi_class` list
there reads `courier, express, cargo, sdd_multislot`. Same-day delivery is documented
as a separate path: `claims/create` with `same_day_data` (dimensions and weight) and
no `client_requirements`. Another reading, a larger vehicle such as a minivan or
truck, is unsourced too.

- **Cost:** a sender can pick a class whose name, promise and limits the app made up.
  A parcel too big for whatever `sdd_long` really is gets no warning.
- **Discharge:** a live `offers/calculate` on a real account showing what an
  `sdd_long` offer carries (`description`, intervals, price against `cargo`). Then
  set its words, glyph and limits from that evidence and cite it here.
- **The documented sibling:** `sdd_multislot` arrived with API 0.3.3 as
  `TariffClass.sddMultislot`. Its words come from the docs: «В течение дня», needing
  every item's size and weight. Its limits stay unset because the docs give no
  numbers. Whether such an order can be placed at all through the unified create path
  is the package's `same_day_data` question.

## YD-37 — Same-day can be offered but not ordered — **open, deferred**

The app has one create path: `client_requirements.taxi_class` plus the offer's payload.
Same-day doesn't fit it. Yandex routes it through `same_day_data` (a delivery slot),
needs every item's size and weight, and refuses the unified create with
`sdd_client_requirements_forbidden` (package TD-25). Until then an `sdd_multislot`
card can show in the strip, but the review sheet blocks it
(`TariffClass.isOrderable`), naming the class and pointing back at the strip.
`createRequest` refuses it as a second line.

- **Cost:** a sender outside Russia can be shown a class they can't order. The docs
  say the tariff is unavailable in Russia, so this app's main market shouldn't meet it.
- **Deferred deliberately** (author, 2026-10-05): ordering same-day probably changes
  the UX significantly. Choosing a slot is a different step from picking a card,
  and the measurements become mandatory rather than optional. That should be
  designed, not patched in. The blocker is the stopgap, not the design.
- **Discharge:** answers from Yandex support (the slot's source, whether
  `offer_payload` applies, availability by country), then the package's TD-25, then
  a design round for the same-day flow.

## YD-38 — The Russian wording is unreviewed — **open**

The Russian in the three catalogs (app, widgets, share) — the first pass (#111), the
sweep that closed every missing key (#119) and the strings the tariff, toolbar and
archive work added since (#117, #118, #121) — was written in unattended sessions and has
not been read by a native speaker. It may be imprecise and carry loan translations and
calques where Russian has its own word (author, 2026-10-05).

- **Cost:** the app's main audience reads it; a calque reads as machine output and
  undercuts the care the rest of the screen shows.
- **Discharge:** the author reads the `ru` column of each catalog and edits in place —
  `xcstringstool`/Xcode, never by hand (the catalogs are structured files); YD-35's
  locale-aware tests are the guard that a rewording breaks nothing.

## See Also

- <doc:Design>
- <doc:Roadmap>
