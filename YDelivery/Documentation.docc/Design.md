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

## iOS-only

One platform until the product shape settles. The package supports macOS, and nothing in
the architecture (no UIKit in shared code) forecloses a Mac target later.

**Rejected:** keeping a Mac destination buildable from day one — a standing tax on every
screen for a target nobody runs yet (YAGNI).

## The token lives in the Keychain

An OAuth token that can spend real money is a credential, not a preference.
`kSecClassGenericPassword`, no iCloud sync. The demo's `@AppStorage` token is explicitly a
demo-only allowance; copying it here would ship the anti-pattern the demo documents.

**Rejected:** `@AppStorage`/`UserDefaults` (plaintext on disk, backed up), and environment
variables (fine for the demo's scheme-launched runs; useless for a product installed from
TestFlight).

## Unofficial, visibly

The name is `YDelivery`, not Yandex-anything; no Yandex logos, colors, or iconography.
The README carries the disclaimer. This is both trademark hygiene and honesty about what
the app is.

## See Also

- <doc:Vision>
- <doc:Roadmap>
- <doc:TechDebt>
