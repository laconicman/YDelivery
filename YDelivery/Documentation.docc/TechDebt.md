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

## See Also

- <doc:Design>
- <doc:Roadmap>
