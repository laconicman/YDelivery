# Tech Debt

Compromises this app carries. Each names what it costs and what would retire it. Reference
one from code as `// TODO(YD-n): …` — *YD* so these never collide with the package's `TD-n`
or the demo's `AD-n`. Numbers are never reused.

## YD-1 — No CI — **open**

Every verification is a laptop ritual: `xcodebuild build … -skipPackagePluginValidation`
and the test action, run by whoever remembers.

- **Cost:** a broken `main` is discovered by the next person to pull it, and "the previews
  all run" is asserted, never checked.
- **Discharge:** a workflow running build + tests on push, with
  `-skipPackagePluginValidation` (the OpenAPI generator plugin's trust prompt fails
  non-interactive builds with no useful message otherwise). Scheduled on the Roadmap.

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

## YD-10 — The wire's `building` (корпус) field has no UI — **open**

`AddressParts` covers entrance/floor/apartment/intercom; the claim schema also takes
`building` — «строение или корпус» — which the app never collects (DeepWiki consult
on `openapi.yaml`, 2026-09-18). The no-building warning added beside it catches a
*missing house number*, a different fact.

- **Cost:** addresses like «д. 15, корпус 2» can only be typed into the address line,
  not structured — the wire field exists and goes unfilled.
- **Discharge:** one more `AddressParts` field mapped to `building` at the claim
  boundary; check whether `porch`/`sfloor`/`sflat` mappings already cover what the
  field would duplicate. In the same pass, `CLPlacemark.subThoroughfare` carried
  into `PickedPlace` would replace `lacksBuilding`'s last-token heuristic with a
  known fact (review, PR #30).

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

## YD-15 — `routeStops.role` is position-derived, not model-carried — **open**

`AppDatabase.insertStops` writes `pickup` for index 0 and `dropoff` for the rest,
because `Order.route` is bare `[RoutePoint]` — the app model carries no stop role,
and placed-order construction discards the draft's roles before the store sees
them (review, PR #38). Correct for every route the product can express today —
one pickup, N dropoffs — but a future *return* leg (courier returns to origin)
would persist as `dropoff`, indistinguishable from a delivery.

- **Cost:** a return route would silently mislabel its last stop; provider-
  discovered routes with a return point would likewise flatten. The schema column
  exists — the write just can't fill it honestly yet.
- **Discharge:** carry role on `RoutePoint` (or a route-stop value type) from the
  draft through `Order` into `insertStops`, and map provider route kinds to the
  same representation in claims discovery. Do it when the product gains return
  routes — inventing the enum early only decorates a model nobody populates.

## YD-16 — Draft field values are memory, not disk — **open**

`orderDrafts`/`draftStops`/`draftItems` exist as a skeletal tier (<doc:Schema>), but the
draft the sender edits — including its «Ваши поля» answers — lives in
`NewDeliveryView.Model` only. A force-quit mid-draft loses typed values along with the
route; custom fields made the loss *larger*, not new (YD-5's unresolved acceptance is
the sharper cousin — the claim may exist provider-side; a lost draft is merely annoying).

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

## YD-18 — A cancelled request's wire record can race the identity wipe — **open**

`signIn` invalidates the previous identity's `URLSession` *before* `wireLog.clear()`
(review, PR #49), so a task in flight can no longer complete a real response into the
wiped log. `invalidateAndCancel` is synchronous about the socket but not about the
middleware: a cancelled task still unwinds through `WireLogMiddleware`, which records
the exchange — *with the request body* — and that append is scheduled on the store's
own queue. It can land after `clear()` has run, leaving one old-identity record in the
new identity's shareable log.

- **Cost:** one log line per in-flight task at the instant of a token swap — a request
  path and body, never a response and never headers. Rare (a sign-in must land inside
  a request's flight) and small (the new identity's log starts with an older
  identity's tail call).
- **Discharge:** a write epoch on `WireLogStore` — `signIn` bumps a generation before
  the wipe, the middleware stamps its session's epoch, and stale-epoch appends drop.
  Alternatively a drain step (`finishTasksAndInvalidate` plus settling) before the
  wipe, which pays latency on every sign-in for a one-line leak.

## See Also

- <doc:Design>
- <doc:Roadmap>
