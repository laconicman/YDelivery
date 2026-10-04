# Reconciliation report — 2026-10-04

The app had drifted from "limited but polished" to "partly odd, partly broken" while
feature branches were integrated and reviews shipped. This is the record of the day that
brought it back: what was found, what was decided, what landed, with the evidence. It is
written for the owner to read later; every claim below points at a PR, a commit, a test
or a file.

## 1. Findings — the root causes behind what the owner saw

| Symptom reported | Root cause (verified) | Fix |
|---|---|---|
| Trail/timeline «appears before the row fully expands»; three attempts didn't take | `toggleTrail` set `expandedID` (animated) and `trail = nil`; the SQLite read then set `trail = fetched` ~10 ms later **outside any transaction**. The earlier fix only added a transition to the `isExpanded` insertion. Measured at 60 fps: animating both writes removes the pop, but the cell host centre-interpolates the row's *frame* (collapsed lines dip mid-cell, overlap the route); `fixedSize`+`frame`+`clipped` change nothing; a no-transaction publish is a one-frame snap. | The trail is **a row of its own** — List animates row insertion natively (#109). Frames: `/tmp/trail-anim/{before,variantC,variantD,E,F,G}-frames/` during the session; the PR body carries the measurements. |
| Four identical «Courier» cards at different prices; no times | The wire log shows one `offers/calculate` answering four `courier` offers differing only by `description` (`express`, `express_30min_longer`, `2_hours_delivery`, `express_60min_longer`) and `delivery_interval.to`; `Offer` parsed the windows and never rendered them; `offer_ttl` (10 min) and `description` were not mapped. | Windows on every card, Fastest/Cheapest, TTL re-price (#117). |
| Route estimate: an 88 m «drive» for a 6 km route in Moscow | Apple's automobile graph returns a degenerate stub instead of an error there; walking returns the real curve. | Geodesic gate + walking fallback for the curve, **distance only** on the bar (owner decision #14), a real deadline race (#112). |
| Cancellation error as plain text, no log CTA | No semantic error chrome existed; the design system had status colours only. | `Notice` feedback roles (Kit 0.4.8/0.4.12): bound / warning / error / success — free terms green with the ruble glyph, paid as warning, failures with inline «Share diagnostics» (#101–#105). |
| «Delete» in Deliveries feels wrong | A delivery is an event the provider remembers and re-discovers; deletion lies about the account. | Ruling: archive, not delete (Design); toolbar Sort/Show landed (#118); the archive column follows (Kit). |
| Several logging mechanisms, some not shared | One shareable JSONL (wire exchanges) + 7–9 OSLog-only `Logger`s that iOS cannot read back after a relaunch. | Ruling: one diagnostics file with two record kinds + a launch header; MetricKit later (Design → "The rest of the app is not in the file"). |
| A seed order «Courier on the way» the sender couldn't cancel | `--ckschema-seed` wrote an active fake claim into the **real** App Group store, and `INSERT OR REPLACE` over the real provider account. | Isolated database, terminal status, qualified deletes, device-verified sixteen record types (#90). |
| CloudKit sync never ran on devices | Kit's entitlement gate rejected real provisioning profiles (`icloud-services = "*"`); `building` never serialized. | Kit #34 → 0.4.11. **This means sync is live for the first time on TestFlight builds from here on.** |
| Release config did not compile | Four `#Preview` blocks called DEBUG-only fixtures outside `#if DEBUG`. | #86; CI builds Release as its own job (`Build Release`). |
| Upload validator rejected the archive | Share extension plist shape; widget lacked `CFBundleDisplayName`. | #87 (verified by the accepted upload). |
| CI flake on `StoreControllerTests` | Two other test fixtures built a `StoreController` with `.systemSurfaces` and re-rendered the simulator's **real** widget snapshot in parallel. | #113. |

Also found during the drive and fixed in the same round: a BGTask launch-handler trap
(#89), a `TimeoutGate` that could leave MapKit work running (#112), a `409` at accept
that would rotate the idempotency key while the claim stayed acceptable elsewhere —
**two couriers** (#107), transient `429/5xx` clearing a valid quote (#107), a refresh that
could unlock a stale field schema (#105), the pending-trail tap closing the wrong row
(#109/#118), a row-blind clean pass in the seed that would have deleted the owner's real
records (#90 — caught by review before merge).

## 2. Decisions recorded (owner, 2026-10-04)

- Signing (#92, Kit #36) parked as draft — not needed for 1.0 TestFlight. *Superseded
  the next day by the participant direction, see §6.*
- `release/1.0-testflight` retired; TestFlight builds are archives of `main`, tagged
  `tf/<marketing>-<build>`; build number 3 carried (#114).
- Trail reveal: the whole status line is the disclosure control; the first two lines
  follow the link.
- Degenerate driving graph → distance only; the provider's windows are the time of record.
- `superexpress_d2d` is «Super-express» in English, «Быстрее» in Russian (API 0.3.2).
- Tariff scope: windows + two-way sort. Deliveries scope: toolbar now, archive after the
  Kit column. Logging: the JSON file stays (post-relaunch evidence); OSLog is the console.
- Both `Build and test` and `Build Release` required on `main` (**owner action pending**).

## 3. What landed

**App — 25 PRs** (Devin Review round(s) on each; every inline finding answered in-thread;
`contrib` ledger cleared to owed 0 / re-read 0; both CI jobs green):
#86 #87 #88 #89 #90 #97 #100 #101 #102 #103 #104 #105 #106 #107 #109 #110 #111 #112 #113
#114 #115 #116 #117 #118 #119. `main` moved from `8f58bf4` to `8ac0d99`.

**Kit:** `0.4.11` (entitlement gate, `building`), `0.4.12` (`Notice(.success)`).
**API:** `0.3.2` (`superexpress_d2d`).

Closed as folded: #96 (into #90). Open: #92 (draft, parked → redesign, §6).

## 4. Evidence worth keeping

- 60 fps recordings and frame tables for the trail variants were produced under
  `/tmp/trail-anim/` (not committed — large; the PR #109 body carries the numbers).
- Device runs on PavP (iPhone 16 Pro, iOS 26.6.2): trail reveal (search field stays
  put), the isolated seed (`entitled=true isRunning=true`, both flushes, delete pass),
  `cktool export-schema` → sixteen custom types with `pinned`, `building`, `authorHint`.
- Wire log (`wire-log.jsonl`) from 2026-10-03: the five-offer response that motivated #117.

## 5. Owner actions

1. Add `Build Release` to the `main` ruleset's required checks.
2. Review the Russian added by #119 (table in its description).
3. Local leftovers left untouched: branch `feat/journeys-on-rows` (12 commits, likely
   folded into #29/#30); one stash on `main` (Package.resolved only).
4. Kit #36 / #92: see §6 — a design decision is owed before any more code.

## 6. Direction recorded 2026-10-05 — many providers, docked legs, independent couriers

The owner's note: other delivery services someday; complex docking scenarios between
them; independent couriers participating through this app (or its courier edition);
signing matters for journaling and this intent may shape the schema. Roadmap-level, not
now — but the schema must not cement the opposite. Recorded in [Vision](../../YDelivery/Documentation.docc/Vision.md)
(direction), [Schema](../../YDelivery/Documentation.docc/Schema.md) (what not to cement), [Collaboration](../../YDelivery/Documentation.docc/Collaboration.md) (signing generalised
to participants), [Roadmap](../../YDelivery/Documentation.docc/Roadmap.md) (Later).

## 7. Still open after this round

- Kit write discipline (YD-34): `DELETE`+re-`INSERT` under one key and `INSERT OR
  REPLACE` on synced tables lose or never upload rows — confirmed in `sqlite-data` 1.12
  source (`afterInsert`'s metadata upsert is a no-op on conflict; `afterDelete` sets
  `_isDeleted`). Fix in flight as the next Kit PR.
- Archive column (`OrderPrivateState.archivedAt`) + the archive affordances.
- Diagnostics event records + launch header (Design A + D).
- `surge_ratio` caption on tariff cards; cancel-on-abandon for refused `readyToAccept`
  claims (YD-23).

## 8. On Paul Hudson's SwiftUI agent skill

Installed as `swiftui-pro` (byte-identical to upstream v1.1). A good review checklist —
deprecated APIs, Reduce Motion, `withAnimation … completion:` over delays — but generic:
it has nothing on List row-height mechanics and would not have found the trail bug. Worth
running as a lint pass over views; not a diagnostician.
