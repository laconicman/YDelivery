# Design

Load-bearing decisions, each with the alternative that was rejected. Where this and
`CLAUDE.md` disagree, believe this.

## A product, not a demonstration

The sibling demo's design doc says "the app is a demonstration, and that changes what good
means" — rough package edges are shown there deliberately. This app inverts that: **the user
never sees the API's vocabulary**, and awkwardness in the package surface is either absorbed
in this app's controller layer or, better, fixed in the package (its Roadmap has a
"convenience call shorthands" item waiting for exactly this evidence).

**Rejected:** evolving the demo into the product. A repo whose stated purpose is honest
demonstration cannot also optimize for polish without one goal quietly eating the other.

## Generated types stop at the controller boundary

Views and view models take app models — `Order`, `RoutePoint`, plain values — never
`Components.Schemas.*`. Controllers own the mapping in both directions. Three reasons:
R1 (`swiftui-foundations`) at architecture scale; the package's spec is hand-written and
*expected* to change as live evidence arrives, and this boundary is what keeps those changes
out of the UI layer; and previews/tests get literal-constructible inputs for free.

**Rejected:** views on generated types. The demo does it on purpose — its AD-3 records the
cost — and that cost is the demonstration. Here it would just be coupling.

## The floor is iOS 17, in Swift 6 language mode

iOS 17 is the package's floor and the lowest OS where everything this app is made of —
`Observation`, SwiftData, SwiftUI MapKit (`Map` content builders, `MapPolyline`),
`#Preview` — is unconditional. Live Activities (16.1+) clear it comfortably.

Swift 6 mode with `MainActor` default isolation and Approachable Concurrency (the Xcode 26
template defaults, kept): strict data-race checking costs almost nothing in a new codebase
and a migration later would cost weeks. UI-facing controllers are `@MainActor` by default;
anything long-running hops off explicitly.

**Rejected:** iOS 16 — three rewrites at once (`ObservableObject` era, Core Data instead of
SwiftData, `MKMapView` wrappers instead of SwiftUI MapKit) plus re-opening the package's
documented floor, for a device population this B2B tool does not have. Also rejected:
iOS 18+ — nothing above 17 is needed yet, and reach is free.

## SwiftData is the persistence layer and the app's model layer — **reopened 2026-08-28**

Orders, route points, saved addresses and contacts live in the local store as the single
source of truth the UI observes. Status history arrives by applying `claims/journal` events
(see <doc:Vision>), so the app is usable offline and history survives the vendor's 72-hour
claim visibility horizon. That much stands.

**What reopened the stack choice:** the CloudKit ambitions — an organization sharing one
Yandex token, employees reading/creating/editing orders by role — need shared databases
(plausibly a shared record zone, "sharing the table"). SwiftData's CloudKit sync offers no
`CKShare` surface; `NSPersistentCloudKitContainer` does. Phase 2 therefore opens with a
schema-and-stack research task (<doc:Roadmap>) rather than an implementation sprint, and the
schema gets designed with relational discipline first — the LearnWords project on this
machine records what a rushed CloudKit schema costs.

**Still rejected:** "no store, poll `claims/search` on every launch" — history becomes
hostage to the API's retention and the network.

## Polling first; a push relay only as a later, separate deliverable

Journal polling in the foreground + `BGAppRefreshTask` + local notifications covers the
product's notification story with zero infrastructure, and the journal work is mandatory
anyway. A push relay (Cloudflare Worker or edgepush receiving Yandex's webhook, posting to
APNs over HTTP/2) is additive later and lives in its own small repo when it comes. CloudKit
was checked and cannot receive webhooks — recorded so it is not re-litigated.

**Rejected:** building the relay first. It gates nothing in phases 1–3 and adds an
operational dependency before the app has users.

## Claims sync: search for membership, journal for freshness (2026-09-23)

The claims list is fed by both discovery operations, on purpose — neither alone is
enough. `claims/journal` is a *change feed*: cheap delta polling for claims the
device already knows, but it only reports claims that *changed* — it can never
discover a claim created before the cursor existed, on another device, or by
support, and its events carry no coordinates or routes. `claims/search` is a
*snapshot query*: whole claim cards by state — it is what finds orders the app
never recorded. So the division of labor is: **search reconciles membership**
(`active` and `delayed` every pass — the claims that can still move — plus a
one-time `finished` backfill so history predating the install arrives once), and
**journal keeps known claims fresh** between reconciliations. The store stays the
list's only source of truth: rows render what the device remembers, sync writes
what the provider says.

Mechanics that carry their reasons: the journal cursor persists *after* each page's
events land — a crash mid-page replays, and replay is safe because every event sets
an absolute state (status, price), never a diff. An `invalid_cursor` refusal means
replay from the beginning, not an error shown to the sender. A journal claim whose
card fetch fails joins a persisted *pending queue* — the cursor advances past its
event, so the queue is the only memory of it until a retry or a search pass lands
the card. The cursor, the backfill flag, and the queue live in one small App Group
file beside the order store — wiped on the identity boundary, which is wired
*synchronously*: `ClientController` fires a hook inside `signIn`/`signOut`
themselves, because a 30-second poll cannot see a sign-out that ends before the
next tick. A pass resumed across that boundary drops its writes — the identity
generation is re-proved after every suspension and before every write, because a
cleared file must not be repopulated by the old credential's late response.
Each feed keeps its own failure — a journal success never clears a
search refusal — and a search pass that runs out of pages with a live cursor
reports `SyncIncomplete` rather than stamping `historyBackfilled` on partial
membership (review, PR #35). The same page cap on the journal is *not* reported:
its cursor already advanced past what it applied, so a truncated pass continues
where it stopped on the next tick — self-healing, unlike search's reset. The poll lives in
`ClaimsSyncController`, not a view: a map or detail pushed over the list must not
freeze courier progress (CLAUDE.md rule 6). The wire's status zoo collapses into
the sender's six states at the model boundary — statuses parked on the sender's
decision (`ready_for_approval`, `performer_not_found`, `pay_waiting`, `returned`)
read `attention`, never a raw wire word (YD-7, discharged).

**Rejected alternatives:** journal-only sync (a change feed is not a membership
database — the "loses orders" bug it was meant to fix); search-only polling
(whole cards on every tick — the expensive version of what the journal does
cheaply); and keeping the `return` point out of merged routes (this app *sends*
its drop-off as `return`, so the wire's last stop is the sender's destination,
not courier bookkeeping).

**Deferred, on the record:** a *scheduled* full replay — paging `finished`
repeatedly or replaying the journal from epoch — belongs to a maintenance task
gated on favorable conditions (unmetered Wi-Fi, charging), which the platform can
schedule via `BGProcessingTask` once the persistence stack settles (the
Phase-2 research owns that seam). CloudKit silent notifications may later serve as
a *cross-device wake-up* — one device syncs, a shared-zone change nudges the
others — but they can only trigger our own reconcile; Yandex's webhooks cannot
reach CloudKit, so provider→device push still waits on the relay above.

## iOS-only

One platform until the product shape settles. The package supports macOS, and nothing in
the architecture (no UIKit in shared code) forecloses a Mac target later.

**Rejected:** keeping a Mac destination buildable from day one — a standing tax on every
screen for a target nobody runs yet (YAGNI).

## The token lives in the Keychain

An OAuth token that can spend real money is a credential, not a preference.
`kSecClassGenericPassword`, no iCloud sync. The demo's `@AppStorage` token is explicitly a
demo-only allowance; copying it here would ship the anti-pattern the demo documents.

Since 2026-08-30 the item lives in the **App-Group keychain access group** (`AppGroup.id`),
not the default team-prefixed one — see "Surviving an account transfer" below for why.

**Rejected:** `@AppStorage`/`UserDefaults` (plaintext on disk, backed up), and environment
variables (fine for the demo's scheme-launched runs; useless for a product installed from
TestFlight). Also rejected (2026-08-30, on review of
[swift-security](https://github.com/dm-zharov/swift-security)): a Keychain wrapper
dependency. The library is vetted and would express the same store in fewer, type-safe
lines — but the app holds exactly one generic password behind three tested methods, and a
whole SecItem abstraction on the credential path is a dependency **larger than the
problem** (the standing preference, stated explicitly so the question is not re-asked).
Reconsider if the keychain surface ever grows past this one item — per-organization
tokens are the plausible trigger.

## Surviving an account transfer

Nothing has shipped, which is exactly when transferability is cheap (analysis 2026-08-30,
against Apple's current App Store Connect transfer documentation). What this app does
about each constraint:

- **An unreleased app cannot be transferred at all** — the criteria require a version live
  on the App Store. If a different owning entity ever becomes plausible, the cheapest
  transfer is publishing v1 from that entity in the first place.
- **Keychain is the one user-visible loss, pre-empted.** Default access groups are
  team-prefixed; a transfer changes the prefix and strands every credential
  (QA1726/TN2311). The token therefore lives in the App-Group access group — no team
  prefix, re-registered to the recipient, blessed by Apple's current guidance for exactly
  this.
- **The CloudKit container stays exclusive to this app.** Containers transfer with the
  app — data, schema, and identifier — but sharing one with a sibling app breaks that
  sibling at transfer time. A hard input to the Phase-2 schema research; the transferor
  also loses all dashboard access to user data.
- **APNs credentials are team property.** The old team's keys stop signing pushes shortly
  after a transfer completes; device tokens and the topic (bundle id) survive. The Later
  push relay treats Team ID / Key ID / key as rotate-able configuration with a runbook
  line: swap credentials the moment a transfer completes.
- **Survives untouched:** bundle ID, the App Group identifier and its on-device data,
  ratings and users. **Does not transfer:** TestFlight builds and testers.

## The destination & ordering design (2026-08)

The design session's transient handoff folded in here and into <doc:Roadmap> and was
deleted with Phase 2's round-up (2026-09-06), along with the boards for surfaces that
shipped; the boards for Phase-3+ surfaces stay in `design/`. Its four permanent
specifications live in <doc:DesignSystem>. Three decisions shape everything else:

**The route card is fixed; the map sits above it.** Delivery classes must be visible before
pricing — courier vs van changes the route, not just the price — and filled point rows run
two lines (address + contact) with routes reaching five and ten points; a bottom sheet you
must drag to read the route is the wrong container, and the fixed card is the safer shell at
accessibility sizes. **Rejected:** the map-first taxi shell — the better shell only where
the user is the one travelling.

**A point carries data, not coordinates.** A saved place stores address parts, a default
contact, a role, default options; history stores whole orders, so «Повторить» refills
everything in one tap. Recents, saved places and repeat-order are one local store read three
ways. **Rejected:** three separate features — triple the work, split truth.

**The tab bar goes.** «New Delivery» is a verb, not a place; two tabs remain (Доставки,
Настройки) and the flow presents modally, making the draft's lifetime legible — a tab
switch may no longer destroy it. **Rejected:** the three-tab layout this app shipped with.

Two framings that settle later arguments: **the unit of work is the order, not the parcel**
(the sender's own order number outranks the vendor's claim id on every surface), and **the
app is mostly used while it is closed** (ordering takes ninety seconds; the forty waiting
minutes happen on the Lock Screen).

The session's two open questions that Phase 2 touched were settled by the author
(2026-08-30): **the return point is a real v1 flow** — a per-row role, a full wire
`_type: return`, not a badge reserved for later — and **currency is a picker** over the
wire's three (₽ \$ €), RUB default, never a text field.

## A person's name is components, joined by the formatter

`Contact` stores `givenName` and `familyName`; the one full-name string the store and the
wire speak is assembled by `PersonNameComponents`' formatter, and the substrate keeps the
components beside it so nothing ever needs parsing back. The deciding fact: Foundation's
name parser — both `PersonNameComponentsFormatter.personNameComponents(from:)` and the
parse-strategy initializer — returns nothing for «Иван Петров» (verified on-host,
2026-09-06, pinned by a test). In this app's first market, a stored single string is
unsplittable.

**Rejected:** one `name` string parsed back into fields when needed — dead on arrival for
Cyrillic. Also rejected: hand-splitting on the first space — wrong for mononyms,
patronymics, and every locale that orders names family-first.

## English development language; Russian is the first localization

Source strings are English (author, 2026-08-30): `developmentRegion` en, string catalogs
with generated symbols already enabled, and the shared package owning its strings against
`Bundle.module` — so app, widget, and notification say exactly the same words in every
language. The first shipped localization is a **complete Russian catalog** — the market
the API serves — and every later language is additive from the same mechanism.

**Rejected:** Russian as the development language. It would read natively in the first
market sooner, but it bakes the source into one locale; English keys keep the catalogs,
generated symbols, and each later language on the paved path. The interface vocabulary
rules (courier, van, stop — never the vendor's words) bind in every language equally.

## Unofficial, visibly

The name is `YDelivery`, not Yandex-anything; no Yandex logos, colors, or iconography.
The README carries the disclaimer. This is both trademark hygiene and honesty about what
the app is.

## Wire diagnostics: a file for evidence, OSLog for the console (2026-09-22)

Field evidence — "the API answered something the spec didn't predict" — is the input the
package's TD-22-class questions need, so the app captures every exchange itself. Two sinks
ride the package's `middlewares:` composition slot (the seam added in `0.2.1` for exactly
this): `OSLogLoggingMiddleware` at `.debug` for an attached debugger's console, and the
app's own `WireLogMiddleware` → `WireLogStore`, a bounded JSONL file (512 KB, oldest half
dropped at line boundaries) in Application Support that Settings exposes through a
ShareLink. The middleware chain runs after auth, so it sees `Authorization` — recorded in
the package register as TD-23 — and the discipline is that the sink records bodies and
statuses, never headers.

Why a file rather than extracting OSLog afterwards: `OSLogStore(.currentProcessIdentifier)`
is scoped to the process ID, so a relaunch — force-quit, jetsam, or simply reopening days
later — strands the evidence; `.debug` messages never reach disk at all; marking bodies
`.public` would expose route PII to `log collect` and sysdiagnose; and OSLog clips large
interpolated payloads, so a truncated JSON body looks complete but isn't. The file is
app-owned, `.complete`-protected at creation, survives relaunch (the whole point), and
leaves the device only through the explicit share act — YD-12 registers that PII trade.
Firefox iOS's `copyLogsToDocuments` is the same pattern at scale.

The log's own integrity is part of the decision, settled through PR #33's review: writes
are atomic-or-rolled-back (a failed append truncates to the pre-write offset; a failed
creation deletes the file), `.complete` protection failure removes the file rather than
leaving PII unlocked, and `exportURL` itself validates — a file whose final line isn't a
whole JSON object is never shareable, so torn bytes inherited from a previous launch stay
dark and the next append cuts them. Identity boundaries are sequenced: sign-in awaits the
wipe *before* the client exists, sign-out drops the share affordance synchronously and the
`isSignedIn` gate keeps a late in-flight write of the dead identity from ever looking
shareable.

**Rejected:** `OSLogStore` extraction (PID-scoped, level-dependent persistence, `.public`
PII exposure, truncation); transport-level capture (sits below the middleware chain but
sees the same `Authorization` — the exposure the reviewer flagged — while adding a second
seam the middleware slot already provides); OSLog-only (no relaunch survival, the engaged-
user scenario's core case).

## See Also

- <doc:Vision>
- <doc:Roadmap>
- <doc:TechDebt>
