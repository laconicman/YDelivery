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

## YD-5 — An unresolved acceptance does not survive a restart — **open**

`acceptClaim` can time out or fail *after* the provider took it: the flow renders
`Ordering.unresolved` with a read-only «Check again» (`reconcileUnresolved(watch:)`), but
that state lives in the draft model only. Force-quit mid-reconcile and the app forgets a
claim that may be spending money; the vendor remembers.

- **Cost:** the one state where the app can lie by omission about money.
- **Discharge:** persist the pending claim id and reconcile on launch — lands naturally
  with Phase 3's journal (match by the `claimID` every order already carries) and the
  store-stack decision (<doc:Roadmap> → the research). Until then the window is one
  foregrounded flow wide.

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
  field would duplicate.

## YD-7 — Post-draft statuses read as unknown — **open**

`PlacedClaim.Progress` collapses exactly the statuses the ordering flow decides on;
`pickuped`, `delivered`, `cancelled` and the rest of the zoo land in `.other(raw)` —
honest, but dumb copy if ever surfaced.

- **Cost:** any surface polling past acceptance (an unresolved reconcile that finds a
  far-along claim) shows a raw wire word.
- **Discharge:** the full wire→`OrderStatus` vocabulary that Phase 3's journal needs
  anyway; `.other` then survives only for statuses Yandex invents later.

## YD-8 — DMS coordinate strings are a documented parse gap — **open**

<doc:LinkGrammars> lists `55 45 20.9N …` as a raw-string row; `MapLink` parses decimal
pairs and hemisphere suffixes only, and the tests record the gap.

- **Cost:** a pasted DMS pair is not offered at all — rare on phones, common on paper.
- **Discharge:** a DMS arm in `MapLink`'s raw parser, tests citing the grammar table.

## See Also

- <doc:Design>
- <doc:Roadmap>
