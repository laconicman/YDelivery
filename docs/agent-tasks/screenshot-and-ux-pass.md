# Agent task — simulator walk, screenshots and UX evals

For a session that can launch the app in the iOS Simulator and interact with it like a
person (tap, swipe, type, long-press, rotate, shake). Written 2026-09-29 after a
non-interactive review pass hit the limits of XCUITest-driven screenshots; the seeded
launch flags below make every screen reachable without a provider token or an iCloud
account. **Nothing in this task touches a real account, a real device, or money.**

## Setup

```bash
cd ~/Documents/Code/Gateways/YDelivery && git pull && xcodegen generate
xcodebuild build -project YDelivery.xcodeproj -scheme YDelivery \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -skipPackagePluginValidation
# install + launch with a seed flag (bundle id com.learnable.YDelivery):
xcrun simctl launch booted com.learnable.YDelivery --uitest-history
```

Launch flags (DEBUG only). **Only `--uitest-history` is hermetic** — a throwaway store,
signed out, no widget/Spotlight/Live-Activity publication. The draft flags seed *into the
simulator's normal store* (a parked draft, a fields schema) and leave it there; that is
fine on a simulator and is why this walk never runs on a device.

| Flag | Seeds |
|---|---|
| `--uitest-history` | five orders across every status, a nine-event provider trail on the live one, a two-message chat on the delivered one |
| `--uitest-three-stop-draft` | a draft with three stops and an item (opens composing) |
| `--uitest-three-stop-draft --uitest-fields` | the same plus a «Ваши поля» schema |

Screenshots: `xcrun simctl io booted screenshot <name>.png`. Save under
`/tmp/ydelivery-walk/<flag>/<NN>-<screen>.png`, numbered in the order taken.

## Walk 1 — history (`--uitest-history`)

1. Deliveries tab as launched. **Eval:** two section headers, *In progress* and *History*;
   rows lead with a date, then «from → to», then the status pill with a time; the
   «✕ Cancelled» pill shows a *circled* X. Count rows visible without scrolling — record
   the number (target ≥ 7 on iPhone 17 Pro).
2. Tap the **status pill** of the live row. **Eval:** the row grows in place: full route
   with people, then a timeline — nine lines, «Courier is at the destination door» last
   and emphasised, times on the right. Nothing else navigates. Tap the pill again — it
   collapses.
3. Tap the **middle of a row** (on the addresses). **Eval:** the order detail opens (Kit
   0.4.1 fixed this; before, the centre opened nothing). Go back.
4. Pull to refresh. **Eval:** a footnote sync error appears under the rows (signed out —
   expected), the rows stay.
5. Tap the search field, type `Арбат`. **Eval:** only matching rows remain; the empty
   shelf's header disappears; **the «+ New Delivery» button is gone while the search
   field is active** (#62 addendum). Clear the search — the button returns.
   Also type `Picked up` and `Иван` — both should match (status phrase, contact).
6. Swipe a row left. **Eval:** *Repeat* and *Reverse* actions; tap *Repeat* — the
   compose sheet opens pre-filled with that route. Dismiss.
7. Open the **delivered** order → **Chat**. **Eval:** two entries; the toolbar shows a
   bare ✓ (known — #73 wants a prominent bottom button instead; record how it reads to
   you). Type a message, send. **Eval:** it appears at the bottom with no author name;
   the composer clears. Type a second message, and *while it is sending* keep typing —
   **Eval:** the extra characters survive.
8. Open the **live** order. **Eval:** map with two pins and a line; tap a pin — the
   callout card appears. **Eval for #75:** does the card cover the whole map? Can you
   still pan the map? How do you dismiss the card? Record exactly what worked.
9. Top-right share-order button on any order. **Eval:** an alert *«Sharing failed — The
   record could not be shared»* (known — #70; the sim has no iCloud). Record the exact
   text. «Share with the recipient» below the card should open the system share sheet
   with text.
10. Rotate to landscape on the list and on a detail. **Eval:** nothing clips; the
    compose button stays reachable.
11. Dynamic Type: Settings → Accessibility → Larger Text → largest non-accessibility
    size, return to the app. **Eval:** the status pill *wraps* rather than truncating;
    the row's date/price line does not overlap; the timeline's marks still align.

## Walk 2 — the draft (`--uitest-three-stop-draft --uitest-fields`)

1. The compose sheet as launched. **Eval:** three stops on the card; the item row says
   its journey («A → B»).
2. Scroll to the tariff strip. **Eval:** four states possible — record which shows signed
   out (expected: a sign-in invitation, not an error). Screenshot — **this is the
   listing's second screenshot and has no seed of its own; note what a seed would need.**
3. Clear the parcel description, try to order. **Eval:** the review sheet's (i) «Say
   what's inside…» — record where the parcel editor is relative to it (#71 wants it in
   place).
4. Tap a contact line on a stop. **Eval:** which screen opens (YD-9 says the whole point
   flow; record the number of taps back to the draft).

## Walk 3 — signed out, empty (`no flag`, fresh install)

1. Deliveries tab. **Eval:** *Sign in to start* with a description pointing at Settings
   and **no button** (#72 wants a CTA). Record.
2. Settings → token field: paste `not-a-token`, save. **Eval:** how the refusal renders
   (the API is not called for an obviously malformed token? or is it — record the wire
   log's entry count in Settings → Share diagnostic log afterwards).

## Deliver

- The PNGs, in their folders.
- One Markdown file: for each numbered step, `pass` / `fail` / `note`, one line each,
  plus the recorded counts and exact strings. Where an eval says *record*, the record is
  the deliverable, not a judgement.
- Anything that crashed or hung: the step, and `xcrun simctl spawn booted log show
  --last 5m --predicate 'process == "YDelivery"'` saved beside the screenshot.

## Out of scope here (needs a real device and a second iCloud account)

Share acceptance end-to-end, App Clip entry, participant removal, offline writes syncing
later, Live Activity survival across an update — `Collaboration.md` → open verifications.
