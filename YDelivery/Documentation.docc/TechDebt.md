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

## YD-2 — The test targets are template stubs — **open**

`YDeliveryTests` holds one empty `@Test`; the UI test target is the Xcode template
verbatim.

- **Cost:** the test action is green and means nothing — worse than red, because it looks
  like coverage.
- **Discharge:** first real logic (offer mapping, journal event application) arrives with
  Swift Testing suites; the UI target keeps exactly one launch smoke test and loses the
  rest of the template.

## See Also

- <doc:Design>
- <doc:Roadmap>
