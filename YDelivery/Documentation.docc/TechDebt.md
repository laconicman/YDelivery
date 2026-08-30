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

## YD-3 — SF Symbol names are raw strings — **open**

`Image(systemName: "chevron.forward")` and its siblings compile whether or not the symbol
exists; a typo renders an empty image at runtime (author's review, 2026-08-28).

- **Cost:** no compile-time safety over an asset namespace that changes with every OS.
- **Discharge:** adopt [SFSafeSymbols](https://github.com/SFSafeSymbols/SFSafeSymbols) — the
  demo repo already depends on it, so this is alignment, not a new precedent. One chore PR
  replacing the string call sites.

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

## See Also

- <doc:Design>
- <doc:Roadmap>
