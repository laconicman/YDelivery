# Review handoff — the unreviewed-PRs round

**Date:** 2026-10-04 · **Device:** PavP (iPhone 16 Pro, iOS 26.6.2)
**Scope:** everything held since the first unreviewed PR — what sits where, the
device evidence behind each change, and where a reviewer should push hardest.

## The queue

### #109 — trail reveal (`feat/trail-reveal`, stacked on status-words)

Extracted from `b9f7aa7` (`feat/record-signing`). **Stale:** the author manually
removed the same code from `DeliveriesView+Content.swift` after the PR opened —
if that removal is the decision, close rather than merge.

### #111 — `feat/l10n-ru` — app catalogs, full RU

- 429 keys across app/widgets/share `.xcstrings` with drafted RU; plural
  variations use `substitutions` + `%arg` leaves (nested variation axes do not
  compile — the format is a named-slot block, per Apple's xcstrings spec).
- `ru.lproj/InfoPlist.strings` — `knownRegions` derives from `.lproj` folders,
  not `project.yml` (verified against XcodeGen's spec and behavior).
- `00feaf5`: **the alias fix.** `Text` interpolations emit indexed `%1$@` keys;
  `String(localized:)` emits unindexed `%@` keys; extraction carried only
  indexed — every multi-argument `String(localized:)` site fell back to English.
  De-indexed aliases now cover all five live sites.
- `sdd_long`/`superexpress_d2d` → named `TariffClass` cases («День в день» /
  «Быстрее»). Caveat: `superexpress_d2d` is absent from the pinned API 0.3.1
  enum (announced 2026-10); it reaches the app via `wireSpelling` until the pin
  moves. `default:` on the frozen enum warns (`will never be executed`) — a
  candidate tidy-up: spell all five cases.
- Kit floor → **0.4.10** (kit PR merged, tag cut; both kit catalogs + resolution
  tests ship there).
- Tests: `LocalizationTests` (5) green.

### #112 — `fix/device-findings` — behavior + estimate fixes

- **Picker Cancel** on both pushed stages — semantic `.cancellationAction`
  (author's preference, confirmed).
- Route card header «Маршрут»; the swap/add-stop row re-sectioned; separator
  indents corrected.
- **Library `+` on Places**: pick flow → naming sheet fired from `onDismiss`
  (the codebase has no dismiss-chain — DeepWiki-verified; the handoff lives in
  `LibraryView.swift`).
- **Route estimate, the real bug** — see evidence below. 15 s timeout +
  `route-estimate` logger + geodesic validation with `.walking` fallback.
- OrderBar's stray `.background(.bar)` removed; **`Button.primaryAction()`**
  shared recipe for standing CTAs — a modifier bundle, not a `ButtonStyle`
  (styles cannot compose; a custom style would redraw the capsule and lose the
  system chrome).
- «What's inside»: the chips row is gone — «Add an item» and «Add from
  library» share one `HStack`; `ViewThatFits` short forms («Add» / «Library»)
  per button; a `confirmationDialog` lists templates (`Menu` inside `List`
  cannot be driven by synthesized taps — the `Add field` precedent).
- **YD-31** (region-gated estimate) and **YD-32** (same-class offers
  indistinguishable — intervals parsed, never rendered; `description` unmapped)
  in TechDebt; matching roadmap bullet under "Later".

## Device evidence — the receipts

`wire-log.jsonl` + `estimate-log.jsonl` pulled via `devicectl` `copy`
(`appDataContainer` works; `appGroupDataContainer` returns empty — protected
files do not transfer):

| probe | result |
|---|---|
| `calculateOffers` request bodies (all 12) | correct coords — draft data clean |
| automobile, Moscow (both `MKMapItem` APIs) | **88 m / 16 s stub** |
| automobile, NYC — same device | 4,081 m / 697 s — real route |
| walking, Moscow | **6,239 m / 5,574 s — real route** |
| transit, Moscow | `MKErrorDomain` 5 (honest failure) |
| `.any`, Moscow | 88 m (resolves to automobile) |

Conclusion: Apple's automobile graph degenerates regionally — it returns a stub
rather than erroring. The fix gates each leg against the geodesic (a road route
can't be shorter than the straight line) and retries `.walking`. On-device the
bar now reads ~6.2 км · ~1 ч 33 мин with the real curve. Apple lists Russia
under "Turn-by-Turn Navigation" but not Transit/Cycling — the service tier
trails the advertised list; YD-31 carries the re-probe instruction.

## Known loose threads

- `HistoryScreenshotTests` fails locally **identically on `main`** — seeded
  rows don't render in 15 s on the iOS 27 sim; CI green on the same base.
  Environmental, not this round's — worth its own entry if it persists.
- `MKPlacemark(coordinate:)`/`MKMapItem(placemark:)` are deprecated in iOS 26
  (`init(location:address:)`) — not yet migrated; no functional difference in
  the probe matrix, but the deprecation is real.
- `MKDirectionsTransportType` has no `.bicycle` — cycling ETA is unreachable.

## Verify recipe

- Unit: `xcodebuild test -only-testing:YDeliveryTests` on an iOS 26.x sim
  (Xcode 27 toolchain — 18.x runtimes crash on `_swift_initBorrow`).
- UI seeds ride `--uitest-history` / `--uitest-library` launch args.
- Device: `devicectl install`/`launch` on PavP ≈ 1 m 40 s build — comparable to
  the sim, worth defaulting to for verification rounds.
- The temporary estimate probes/`estimate-log.jsonl` writer were removed before
  commit — the fix alone ships.
