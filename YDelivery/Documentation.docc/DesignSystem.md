# Design System

The four specifications from the 2026-08 design session that outlive its boards: what the
asset catalog, the pin badges, the field forms, and every animation are built from. Frame
ids (`2c`, `4c`, …) reference the boards in `design/`; the boards argue, this records.

## Semantic colors

Named by meaning so no hue name appears in a diff. Asset catalog, light + dark, compile-time
symbols. The set lives in the shared package (`YDeliveryKit`) once it exists — or the
widget's green drifts from the app's within two releases.

| Token | Means | Glyph · words |
|---|---|---|
| `statusDraft` | nothing sent | — · «Черновик» |
| `statusSearching` | waiting for a courier | ◌ variable color · «Ищем курьера» |
| `statusActive` | en route, on plan | ◉ · «Курьер едет» |
| `statusDone` | delivered | ✓ · «Доставлено» |
| `statusAttention` | needs a decision | ⚠ · «Не вручили» |
| `statusCancelled` | closed, undelivered | ✕ · «Отменён» |
| `pointStart` | pickup | concentric ring |
| `pointEnd` | drop-off | teardrop |
| `scanConfident` | recognised — UI text and outlines | ✓ solid outline |
| `scanUncertain` | check this — UI text and outlines | dashed outline · «проверьте» |
| `scanOverlayConfident` | recognised — viewfinder overlay only | ✓ solid outline |
| `scanOverlayUncertain` | check this — viewfinder overlay only | dashed outline |

Two rules: **a status color never appears without glyph and words**; and `statusAttention`
is for *decisions* — a network failure is a retry, not attention. Values run deliberately
darker than `.systemGreen`/`.systemRed` where text sits on them; verify AA at 13 px, the
tight case, **measured against the surface the words actually sit on** — the chip's 12%
tint, not the naked background (designer confirmation, 2026-08-30).

A third rule, the general form of a bug the scan tokens carried: **a token that renders
both as a graphic on dark chrome and as text on light gets two entries, not one clever
value** (designer, 2026-08-30). The overlay pair keeps the bright system values at the
3:1 graphics threshold — safe for pins and outlines because shape and glyph carry the
role, so poor contrast loses emphasis, never meaning. The UI pair holds AA for text in
both modes: light `#14682F`/`#8A5A00` matching the 6a results screen; dark reusing
`statusDone`/`statusSearching` dark values rather than inventing more. Confidence must
survive greyscale: solid versus dashed outline, plus the word.

### Implementation approach (house precedent)

Per the author's `SwiftUI/Themes` project (Multi-Theme App with Namespaces; the
controller-owned selection traces to Manferdini's SettingsController note in the vault):
**asset-catalog compile safety needs no third-party generator.** Colorset folders marked
`provides-namespace` plus Xcode's generated asset symbols
(`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`, already on in this project)
yield nested compile-time symbols — `.Blaze.Text.primary` in that project; here, a flat
single-theme set reads `Color(.statusActive)` with a typo being a build error, not a blank.

For `YDeliveryKit`: the catalog lives in the package (generated symbols work in SwiftPM
targets since Xcode 15, resolving against `Bundle.module` — which is exactly what keeps the
widget's green identical to the app's), tokens stay flat while there is one theme, and the
namespace mechanism is the growth path if theming ever becomes a feature — the Themes
project shows that shape working, `ThemeManager` modernizing to an `@Observable` controller
per this app's rules.

## Pin & badge taxonomy (board `2c`)

Shape and glyph carry the role; **color only reinforces**. The grayscale column is the test:
every row must stay distinguishable with color removed. Because that holds, the palette
keeps the market's green/red reading — moved to Okabe-Ito green and vermillion so the pair
also survives protanopia. Map marker and list badge share the glyph, which makes the route
list the map's legend.

Ends are symbols, not letters — A/B badges are withdrawn: they carry no meaning, need
localizing at accessibility sizes, and collide with numbered intermediates.

| Role | Shape on map | Token · color | SF Symbol (list badge) |
|---|---|---|---|
| Start · pickup | concentric ring | `pointStart` · Okabe-Ito green `#1E8E3E` | `smallcircle.filled.circle`; a row stating the *action* may use `shippingbox.fill` («забрать») |
| Intermediate *n* | numbered circle | `pointMid` · secondary | `3.circle.fill` (n) |
| End · drop-off | teardrop | `pointEnd` · vermillion `#D55E00` | `mappin.circle.fill`; action rows may use `house.fill` («доставить») |
| Warehouse | rounded square | `placeWarehouse` | `building.2.fill` |
| ПВЗ · staffed pickup | rounded square | `placePickup` | `storefront.fill` |
| Постамат · locker | rounded square | `placeLocker` | `cabinet.fill` |
| Return point | circle + arrow | `placeReturn` | `arrow.uturn.backward.circle.fill` |
| Recent | *(row icon only — never a pin shape)* | secondary | `clock` |

Verify every symbol name in the SF Symbols app against the iOS 17 floor before it lands in
the catalog.

## Field taxonomy → UI (handoff §4; dossier Part II §6)

Three rules, drawn in board `3d`:

1. **One summary line per group, expanding to typed rows.** The draft reads in three
   seconds; density lives one tap down. The demo shows every field because it is a demo;
   this app makes every field *reachable*.
2. **Constraints replace hints.** Where a field is bounded, the bound *is* the helper text.
   Unavailable options render disabled with their reason rather than vanishing, so the
   vocabulary stays learnable.
3. **Units belong to the field.** Centimetres and kilograms in the UI, metres on the wire.
   Currency is a picker. The phone extension is its own field. No free-text number ever
   means two things.

Interdependencies the UI enforces up front — never discovered via API errors:

| Constraint | Source of truth |
|---|---|
| loaders 0–2, **and only with `cargo`** | live API answers `409 estimating.too_many_loaders` |
| `cargoType` only with `cargo` | provider tariff rules |
| thermobag only with `courier` | provider tariff rules |
| `due` inside the provider window (+1 h … +30 d) | provider rules |
| `coordinates` are **lon,lat on the wire** | the one ordering bug that yields a plausible wrong answer instead of an error |

Keyboard and autofill per field type: `textContentType` on every contact field, plus
`.phonePad`; `.numberPad` for flat/floor; `.decimalPad` for weight/cost. A sender is always
copying from somewhere.

## Motion (board `4c`)

One rule: **animation reports a state change the user did not cause, or confirms one they
did — never decorates a static screen.** Everything below exists at iOS 17; motion alone
never justifies raising the floor.

| Moment | Effect | Why it earns it | Reduce Motion |
|---|---|---|---|
| Ищем курьера | `.symbolEffect(.variableColor)` | the one genuinely indeterminate wait; the glyph is the spinner | static + text |
| Статус сменился | `.contentTransition(.symbolEffect(.replace))` | arrives while you look elsewhere — the swap is the notification | cross-fade |
| Цены пришли | `.numericText()` + shimmer→value | price landing in a strip already being read must not just blink | instant |
| Точка подтверждена | `.symbolEffect(.bounce, value:)` | confirms the tap landed when the map barely changes | haptic only |
| Заказ создан | `.bounce` + success haptic | the one irreversible action; no confetti — money just moved | haptic only |
| Курьер двигается | `withAnimation(.linear)` on coordinate | interpolate between polls; a teleporting scooter reads as a bug | jump |
| Ошибка поля | shake (~2-frame offset) | only where the error sits beside the input; never for network failures | color + text |

On Pow: two effects would be taken (`.shake`, a price-change effect), both ≈20 lines —
**skip the dependency** and keep the vocabulary in the app, where each Reduce Motion branch
is visible in the same file. Adopt Pow only if its transition set is wanted broadly.

## See Also

- <doc:Design>
- <doc:LinkGrammars>
- <doc:Vision>
