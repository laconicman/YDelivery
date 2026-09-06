# YDelivery — product app

An unofficial, real client for Yandex Delivery's Express (B2B Cargo) API, built on
[`YandexDeliveryExpressAPI`](../YandexDeliveryExpress). Unlike its sibling
`YandexDeliveryExpressDemo` — whose job is to show the package's rough edges honestly — this
app optimizes for the person sending a parcel. Convenience is the product here.

The DocC catalog (`YDelivery/Documentation.docc/`) is authoritative for direction:
`Design` (decisions + rejected alternatives) · `Vision` (what this app is, the capability
map) · `Roadmap` (priority order) · `TechDebt` (numbered `YD-n` register). The package's
catalog is authoritative for anything about the API itself — read its `WorkingWithYandex`
before assuming a response shape.

## Architecture

Four-layer MVC per `swiftui-app-structure`: Model (structs + SwiftData) → Controller
(`@Observable`, injected via environment) → Root view (one per screen, `…View`) → Content
views (nested, unsuffixed). View models are `…View.Model` beside their root view. Group by
**feature**, not by role.

Floor: iOS 17.0. Swift 6 language mode, `MainActor` default isolation, Approachable
Concurrency — all deliberate, see `Design`.

## Rules specific to this repository

1. **Generated types stop at the controller boundary.** Views and view models see app
   models (`Order`, `RoutePoint`, …), never `Components.Schemas.*`. Mapping lives in the
   controllers/model layer. This is the load-bearing difference from the demo, which shows
   generated types deliberately.
2. **No singletons.** Controllers are created once in `@main` and injected with
   `.environment(_:)`.
3. **No `try!`, no `fatalError` in app code.** Unauthenticated, offline, or misconfigured
   are states to render.
4. **Every view gets a `#Preview`, and every `#Preview` must run.** Content views take plain
   values and closures (R1/R2); run the R1–R10 checklist from `swiftui-foundations` before
   finishing any view.
5. **`body` declares structure; it never computes presentation** (R5). Formatting in
   extensions on the formatted type; derivation in the view model or controller.
6. **Async work is structured and owned.** Polling loops (journal sync, courier position)
   live in controllers as cancellable `Task`s tied to their owner's lifetime — never in
   views, never fire-and-forget without error handling. Follow `swift-concurrency`.
7. **Package-first sequencing.** A feature needing API surface the package lacks starts as
   a package PR (spec + tests), tagged and consumed by URL — then the app feature. Record
   the need in the package's Roadmap/TechDebt, not only here.
8. **Secrets live in the Keychain.** Never `UserDefaults`/`@AppStorage` for the OAuth
   token; never commit one. The demo's `@AppStorage` token is a demo-only allowance.
9. **Swift Testing for logic, XCTest only for `XCUIApplication`.** Test the pure functions
   and controllers, not SwiftUI views.
10. **Everything lands via PR.** Devin Review runs automatically on push; `REVIEW.md`
    steers it. No AI attribution in commit messages or PR descriptions. For peripheral
    files (the design boards' JS, generated artifacts), applying the reviewer's inline
    suggestion via GitHub's "Apply suggestion" is an accepted cheap path — hand-crafted
    commits are for the code this repo exists to ship.

## Author's standing preferences

Clarity over brevity. Prefer a vetted SPM when the dependency is smaller than the problem;
say so explicitly when it is not. Cite sources in prose and code comments. DRY, separation
of concerns, low coupling / high cohesion first. Error types conform to `LocalizedError`
with a filled `errorDescription` where they could ever surface — a properly filled error
can be passed around and displayed as is (author, 2026-09-02). Prefer implicit returns
wherever the compiler allows, including single-expression `switch`/`if` expressions
(author, 2026-09-02). No magic numbers or strings: shared measures come from
`YDeliveryKit`'s `Layout` tokens, one-off measures are *named* constants beside their
component, and repeated string fragments (separators, joins) get one named home (author,
2026-09-06). Person names are explicit components (`givenName`/`familyName`) concatenated
via `PersonNameComponents`/its formatter, parsed with its parse strategy — never
hand-split or hand-joined (author, 2026-09-06).

## Related skills

`swiftui-app-structure` · `swiftui-foundations` · `swiftui-expert-skill` ·
`swift-file-organization` · `software-development-principles` · `swift-concurrency` ·
`swift-testing-expert` · `axiom-location` · `axiom-data` · `atomic-commits` · `git-branching`
