# Agent task — the sender's library: parcel templates, pins, one tab

Build the library `Roadmap` already weighed ("Next — the sender's library (author's
idea, weighed 2026-09-29)") and `Schema` defers (`ParcelTemplate` bullet): reusable
parcel templates beside the saved places, a `pinned` flag on both lists, and one
«Library» tab that curates them — recommendation (b) of the tab question.

Owner rulings (2026-10-01): full library scope; a template holds **one item's fields
now**, but the storage schema must be shaped so multi-item bundles and remembered
delivery prefs can join later without a forked migration; `pinned` lands on **both**
lists; pin ≈ favourite (one flag, not two — the roadmap's ruling stands).

## The storage decision — root + items, priced

`parcelTemplates` + `parcelTemplateItems`, **private tier**, mirroring
`orderDrafts`/`draftItems`:

- The child table exists from day one with a `position` column even though v1 only
  ever writes one item row per template. A bundle (B) then becomes a *UI widening* —
  the editor allows more rows — instead of a schema fork that migrates flat rows
  into a child table. `items.count == 1` is a UI convention, never a schema
  invariant: say so in the row's doc comment.
- A JSON payload column was priced and rejected: `choicesJSON` is the precedent for
  an *opaque list of strings*; the parcel payload is the feature's core data, and
  the contract's default is relational discipline with deviations named and priced.
- Delivery prefs (C — remembered tariff class, options) are additive
  `columnMigrations` on `parcelTemplates` later — proven machinery, zero cost now.
- `parcelTemplates.name` is the chip label — a real column, seeded from the item's
  name when saving, so a template can be renamed without lying about the goods.

Private tier accepts FK children (`orderPrivateStates` already carries one); the
zero/one-FK share arithmetic only governs `tables:` shareability, and a template is
never a share member by design — the sender's vocabulary syncs to their devices,
period. Actual parcels on an order stay `OrderItem` rows.

## Behaviour rules

- Ordering is `ORDER BY "pinned" DESC, "rowid"` on both lists — pinned entries lead
  pickers, the rest keep insertion order. No `position` column on either list in v1;
  manual reorder is an additive column if the Library earns it.
- Applying a template **appends** a fresh `ParcelItem` — new id, nil journey refs
  (the route's ends). Applying twice makes two identical boxes: legitimate, no dedupe.
- A template never stores journey refs — they are route-relative by definition.
  Tariff fit warnings re-derive on apply through the existing `fitWords` path.
- «Save as template» lives in the **ItemEditor** (the filled form — the roadmap's
  wording), plus the item row's context menu as a second door. A naming sheet seeded
  with the item's name; Save disabled while blank (`SavePlaceSheet`'s shape).
- Places stay born in the picker flow — a place is a resolved point on a map. The
  Library's Places segment is **curate-only**: rename/retype (the existing
  `SavePlaceSheet`), pin, delete. No add button; a footer says places are saved
  mid-draft.
- Delete confirmations mirror the picker's `pendingDelete` dialog pattern.

## Slices

### 0. This doc

Own PR — the spec survives the session that writes it.

### 1. YDeliveryKit (patch → next tag)

- `Tables.swift`: `SavedPlaceRow` gains `pinned`; new `ParcelTemplateRow`
  (`id`, `name`, `pinned`) and `ParcelTemplateItemRow` (`id`, `templateID` FK →
  `parcelTemplates`, `position`, then the `orderItems` field set minus journey refs)
  in the private-tier MARK — doc comments carry the "never a share member; an order's
  parcels stay `orderItems`" contract.
- `DDL.swift`: the two `CREATE TABLE`s; `columnMigrations` gains
  `(savedPlaces, "pinned", "INTEGER NOT NULL DEFAULT 0", nil)` for existing databases.
- `AppDatabase.swift`: `privateTables:` += both rows; `readPlaces` orders
  `pinned DESC, rowid`; `savePlace` writes `pinned`; new `readParcelTemplates()`
  (roots joined to position-ordered items), `saveParcelTemplate(_:)` (upsert root +
  wholesale child replace — the draft-save discipline; `PRAGMA foreign_keys` is off
  so children die explicitly), `deleteParcelTemplate(id:)` (children first, idempotent),
  `setPlacePinned` / `setParcelTemplatePinned`.
- `ParcelTemplate` model in `YDeliveryData` beside `SavedPlace` — `id`, `name`,
  `pinned`, `items: [Item]`; `Item` mirrors `OrderDraft.Item` minus the two stop
  refs (array order is the position, like `Order.route`), same decimal-string `cost`
  discipline.
- `SavedPlace` gains `pinned = false` — a member var so the existing init stands.
- Tests: template round-trip with item order, wholesale item replace on re-save,
  pinned-first ordering on both lists, idempotent delete with explicit child sweep,
  `pinned` persistence, SyncEngine schema validation covering the new tables, and a
  column-migration test on a pre-`pinned` `savedPlaces` shape.

### 2. App — the draft's use path

- `project.yml` bumps the `YDeliveryKit` floor to the new tag (minor release line).
- `StoreController`: `parcelTemplates` published, `templatesError` channel (the
  could-not-look discipline), `save(template:) async throws`, `deleteTemplate`,
  `setPlacePinned`/`setTemplatePinned`, refresh reads templates beside places.
- «What's inside» gains a template-chips row above the item rows (the picker's
  `chipsRow` precedent); tap → append `ParcelItem(from: template)` — a mapping
  extension on `ParcelItem` (fresh id, `cost` parsed POSIX like `init(restoring:)`,
  nil journey refs).
- «Save as template»: ItemEditor affordance + item-row context menu → naming sheet
  seeded with the item's name → `store.save(template)`, the sheet owning the write
  and rendering its failure (`SavePlaceSheet` discipline).
- The place chips' context menu gains Pin/Unpin (`pinChip` intent on
  `SearchContent`, same defaulting as `editChip`).

### 3. App — the Library tab

- `RootView`: `Tab.library` between deliveries and settings;
  `Label("Library", systemSymbol: .archivebox)`.
- `Features/Library/LibraryView.swift` (+ `+Content.swift` when the root passes
  presentation): segmented Places | Parcels; `.searchable` filters the visible
  segment (name / address / item summary).
  - Places rows: name, kind glyph, address + contact second line, pin mark;
    context menu Pin/Unpin · Edit (`SavePlaceSheet`, name+kind) · Delete (confirm).
  - Parcels rows: name + item summary; Pin/Unpin · Edit · Delete; toolbar "+" →
    `ParcelTemplateEditor`: template name + one item's fields reusing
    `ItemEditor.SizeFields` — no journey section, no tariff footer (no route exists
    here). The model already supports `items: […]`; the editor writes exactly one.
- Tests: pin toggles persist, deletes confirm, search filters, editor round trip.

### 4. Sweep

- `Roadmap` moves the entry to landed; `Schema` drops the Deferred bullet and
  records the private-tier tables; `Design` gets a line if the tier write-up needs it.
- `CloudKitSchemaSeed` gains a `parcelTemplates` row + item + a pinned `savedPlaces`
  row — the private-tier record types reach the dev schema the same way places did.
  Sequencing: the seed lives on `chore/cloudkit-schema-seed` (PR #90); this rides
  whichever app slice lands after it merges, else a follow-up.
- Kit README states `ParcelTemplate` if it enumerates the stores.

## Acceptance

- A template saved from a filled item form appears as a chip in «What's inside»,
  pinned-first ordering works on both lists, applying a chip appends the item with
  the route's ends, and the Library curates both collections.
- Kit + app test suites green; every new view carries a running `#Preview`;
  `xcodegen generate` output committed.
- CI green on every PR; Devin Review owed 0 before merge.

## Out of scope (named so nobody "adds it while they're in there")

- No shared tag vocabulary (needs the `Workspace` share-root re-rooting — deferred
  with the rest), no favourites flag distinct from pin, no manual reorder column,
  no template→tariff memory, no bundles UI. B and C are door-open schema choices,
  not features.
- Places are not creatable from the Library — the picker owns their birth.
