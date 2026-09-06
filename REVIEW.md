# Review Guidelines

Review-specific guidance. `CLAUDE.md` carries this repository's standing rules and is
ingested alongside this file — nothing here restates it. These are the diff-level cues and
the noise filters.

## Critical Areas

- Flag `import YandexDeliveryExpressAPI` or any `Components.Schemas` reference under
  `YDelivery/Features/` — generated types stop at the controller boundary (CLAUDE.md
  rule 1); only `YDelivery/App/` controllers and the future model layer may see them.
- Flag any change under `YDelivery/App/TokenStore.swift` or
  `YDelivery/App/ClientController.swift` that logs, prints, or interpolates a token into an
  error, or that moves credential storage off the Keychain.
- Flag a status flip of a `YD-n` entry in
  `YDelivery/Documentation.docc/TechDebt.md` that does not name what discharged it.

## Conventions

- Require a running `#Preview` on every view in the diff; flag a preview that needs an
  `.environment(…)` object the preview does not construct itself — previews use
  `TokenStore(service: "preview.YDelivery")`, never the app's real service.
- Flag a new `// TODO` in Swift code that carries no `YD-n` register number.
- Require content views (`…View+Content.swift`) to take plain values, bindings, and
  closures; flag one that reaches into a controller or the environment. The rule is about
  the view's **stored properties**: a convenience `init(draft:)` in an *extension* is the
  prescribed bridge, not a violation of it — it keeps the properties plain and leaves the
  memberwise initializer alive for previews (R2; Manferdini, *SwiftUI Structural
  Foundations* 3.4). Flag that initializer only when it appears in the view's own
  declaration or when a stored property takes a model type (misfired on PR #17).
- Flag a feature that needs API surface absent from `YandexDeliveryExpressAPI` being built
  against hand-rolled URLs — the package grows first (CLAUDE.md rule 7).

## Anti-patterns to Flag

- Flag `ObservableObject`, `@Published`, `@StateObject`, or `@EnvironmentObject` in new
  code — the floor is iOS 17 and the project is Observation-only.
- Flag `@AppStorage` or `UserDefaults` holding anything secret-shaped — the demo repo's
  token-in-`@AppStorage` is a demo-only allowance that must not migrate here.
- Flag `Task { … }` blocks that neither await a result nor handle thrown errors, and any
  polling loop created outside a controller that owns and cancels it — **except** a loop
  whose whole life is one screen's, which CLAUDE.md rule 6 permits in that screen's view
  model when it is owned, cancellable and handles its errors (settled 2026-09-06; the
  ordering wait in `NewDeliveryView.Model` is the example). Flag one that should outlive
  its screen — journal sync, courier position — wherever it sits.
- Flag `DispatchQueue.main.async` in a file already using Swift Concurrency — it hides an
  isolation bug rather than fixing one.
- Flag a blanket `@MainActor` (or removal of `nonisolated`) applied to make a diagnostic
  disappear without a stated UI reason; `YDelivery/App/TokenStore.swift` records the
  pattern this project expects.
- Flag an *unannotated* extension holding pure logic (parsing, formatting) on a
  `nonisolated` type: extensions do not inherit `nonisolated`, so the project's default
  isolation pins them to the main actor and the failure is a runtime SIGTRAP from a
  nonisolated caller, not a compile error (MapLink's first test run, 2026-08-30).

## Security

- Treat `YDelivery/App/TokenStore.swift` as sensitive: keep `kSecAttrSynchronizable` absent
  (no iCloud sync) and `kSecAttrAccessibleAfterFirstUnlock` unless a stated background need
  changes it.
- Reject any committed `.xcscheme`, plist, or source literal carrying a real OAuth token.

## Ignore

- Skip `Package.resolved` churn when a dependency bump is the PR's stated purpose.
- Skip `YDelivery/Assets.xcassets/` contents.
