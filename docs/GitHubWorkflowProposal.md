# GitHub Workflow Proposal — YDelivery

*First survey — 2026-09-29.* Companion to the DiceLab report of the same name; the
section shape is kept identical so the reports consolidate. Every row below was
verified live with `gh`/`git` on the date above, not recalled.

## What exists today (verified live)

| Capability | State | Evidence |
|---|---|---|
| Tags | **0** | `git tag \| wc -l` → 0 |
| Releases | **0** | `gh release list` → empty |
| `.github/` | `workflows/ci.yml` only | `find .github -type f` |
| CI | **Runs, green**: `macos-15`, `latest-stable` Xcode → `brew install xcodegen && xcodegen` → `xcodebuild test` (unit + UI) on `iPhone 17 Pro, OS=latest`. Triggers: PRs, pushes to `main`, manual. Concurrency group cancels superseded runs. 12 ✓ / 5 ✗ / 1 cancelled in the last 50; a green run is **12–16 min** | `.github/workflows/ci.yml`, `gh run list` |
| Milestones | 0 | `gh api .../milestones` → `[]` |
| Labels | GitHub defaults + `accessibility`; **applied to 0 of the last 20 PRs** | `gh label list`, `gh pr list --json labels` |
| Issues | **0 ever** — the `YD-n` register in `TechDebt.md` and the Roadmap are the tracker | `gh issue list --state all` |
| Merge convention | **Squash, exclusively** (#1–#59 are single-parent commits); merge and rebase also enabled, unused. Squash title = PR title, body = commit messages | `git log --format=%p`, repo API |
| `delete_branch_on_merge` | **`false`** — 4 merged branches still on the remote (`feat/claim-refusals`, `feat/pending-acceptance`, `feat/share-handoff`, `feat/widget-surface`); 23 stale tracking refs in the local clone until `fetch --prune` | repo API, `gh api .../branches` |
| `allow_auto_merge` | `false` | repo API |
| Branch protection / rulesets | **None on `main`** — direct push and force-push accepted. `CLAUDE.md` rule 10 says "`main` is protected"; the sibling repos (`YDeliveryKit`, `YandexDeliveryExpress`) *are* protected (admins enforced, no force-push, **no required checks**) | `GET .../branches/main/protection` → 404 "Branch not protected"; rulesets `[]` |
| PR bodies | `## Summary` + `#### Test plan` by convention in 8 of the last 10 — a habit without a template | `gh pr list --json body` |
| Issue/PR templates | None | `ls .github/ISSUE_TEMPLATE`, `pull_request_template.md` → absent |
| Dependabot | None; external actions: `actions/checkout@v5`, `maxim-lobanov/setup-xcode@v1` | `.github/dependabot.yml` absent |
| License | `LICENSE` present | repo |
| `SECURITY.md` / `CONTRIBUTING.md` / `CODEOWNERS` | Absent | `ls` |
| Discussions / Projects / Wiki | Discussions off; Projects on (unused); Wiki off | repo API |
| Versioning in the project | `MARKETING_VERSION: "1.0"`, `CURRENT_PROJECT_VERSION: 1` — never bumped, no tag anchors them | `project.yml` |
| Reviewer | Devin Review on every push (`REVIEW.md` steers it); this session found **15 inline findings across #56–#58 with no in-thread reply** and one 🔴 that was *edited in place* after the final push and merged unread | `contrib in laconicman/YDelivery --pr N` |
| DeepWiki | `.devin/wiki.json` steers it; **no README badge**, so no weekly auto-refresh — the index was ~20 PRs stale at review time; the two sibling repos carry the badge | `grep -i deepwiki README.md` |

Facts that shape the proposals:

- **Solo maintainer, docs-as-tracker.** `Roadmap.md` / `TechDebt.md` / `Design.md` in
  DocC are the working system; GitHub issues are used only when a *decision* needs a
  linkable record (`YandexDeliveryExpress#15`, `YDeliveryKit#25` → PRs). That pattern
  works; the proposals below do not try to move the tracker.
- **Three repos move together.** App PRs routinely depend on a Kit or API tag cut the
  same hour (`0.3.11`–`0.3.14` in one night, `0.4.1` today). Anything proposed here must
  cost the same or less across the three, or it will be applied to one and drift.
- **CI is real and slow-ish (12–16 min).** Waiting on it is the single largest idle cost
  in a PR cycle; two of the night's merges happened before the green check by hand.
- **The app has no distribution yet** — no TestFlight, no App Store build. Tags and
  releases would be checkpoints ("this is what the reviewer saw"), not shipments; the
  moment TestFlight enters, `MARKETING_VERSION` needs an anchor.
- **The reviewer is paid per round and edits findings in place.** A finding can escalate
  *after* the push that "addressed" it; a count of comments is not a read of them.

---

## Proposals — cheapest first

### 1. `delete_branch_on_merge` + `fetch.prune` (repo-agnostic) — 10 seconds

Four merged branches sit on the remote and the clone carried 23 dead tracking refs.
One API call and one git setting, and this class of debt stops accruing:

```bash
gh api repos/laconicman/YDelivery -X PATCH -F delete_branch_on_merge=true
git config --global fetch.prune true          # travels to every repo
gh api repos/laconicman/YDelivery/git/refs/heads/feat/claim-refusals -X DELETE   # ×4, once
```

Same call for `YDeliveryKit` and `YandexDeliveryExpress` (both `false` today).

### 2. The DeepWiki README badge (repo-specific) — one line

The two sibling repos have it; this one does not, and its index was ~20 PRs behind
when consulted — every "consult DeepWiki on every step" answer about the *app* was
answering about a codebase without sqlite-data, widgets, sharing or chat. The badge is
what earns the weekly automatic pass:

```markdown
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/laconicman/YDelivery)
```

Costs nothing; the manual refresh requested today covers the gap until the first
automatic one lands.

### 3. Protect `main` — with the check the app already has (repo-specific decision)

`CLAUDE.md` rule 10 believes `main` is protected. It is not — and this is the one repo
of the three that *has* a CI check to require. Options:

- **(a) Match the siblings** — block force-push and deletion, no required check. Closes
  the catastrophic surface, keeps the "merge after CI by hand" habit:
  ```bash
  gh api repos/laconicman/YDelivery/rulesets -X POST --input - <<'JSON'
  { "name": "protect main", "target": "branch", "enforcement": "active",
    "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
    "rules": [ { "type": "non_fast_forward" }, { "type": "deletion" } ] }
  JSON
  ```
- **(b) (a) + require the `Build and test` check** — turns CI from advisory into a gate.
  The cost is the 12–16 min wait on *every* merge, including the two-line pin bumps that
  were merged early this week on purpose. `workflow_dispatch` and `concurrency` are
  already there, so the wait is the only cost:
  ```json
  { "type": "required_status_checks",
    "parameters": { "strict_required_status_checks_policy": false,
      "required_status_checks": [ { "context": "Build and test" } ] } }
  ```
- **(c) (b) + `allow_auto_merge`** — makes the wait free: `gh pr merge N --squash --auto`
  merges the moment the gate greens, so the wait costs no attention. With the required
  check in place, `--auto` *is* a CI gate (unlike DiceLab's unprotected case).

**Recommendation: (c).** The night's pattern — open PR, poll CI for 15 minutes, merge —
is exactly what auto-merge removes, and the one merge that shipped a 🔴 was the one
where the check was read as a count. If (c) is too much habit change at once, (a) today
and (b)/(c) after the first TestFlight build; either way the `CLAUDE.md` claim should
match the setting the same day.

### 4. A merge-time reviewer audit (repo-agnostic habit) — 30 seconds per PR

Devin Review edits findings in place and posts follow-up verdicts; the merge-time check
this week compared comment *counts* and missed an in-place escalation to 🔴. The
`contrib` CLI settles the decidable part:

```bash
contrib in laconicman/YDelivery --pr N        # owed 0 AND to re-read 0 before merge
```

and, when a finding is answered in a *separate* PR, the answer still goes in the thread
(`gh api -X POST repos/…/pulls/N/comments/<id>/replies -f body=…`) — a top-level summary
comment is not a reply and leaves every thread `open-ask`. This is a habit, not a
setting; it could become a required check only at team scale.

### 5. Squash-only + PR template (repo-agnostic) — one API call, one file

Every merge is a squash; merge and rebase are fat-finger targets on the merge button:

```bash
gh api repos/laconicman/YDelivery -X PATCH -F allow_merge_commit=false -F allow_rebase_merge=false
```

The `## Summary` / `#### Test plan` shape is already a habit in 8 of 10 bodies; a
template makes it 10 of 10 and adds the two lines this repo actually needs:

```markdown
<!-- .github/pull_request_template.md -->
## Summary

#### Test plan
- [ ] `xcodebuild test` / CI green
- [ ] Every new or touched view has a running `#Preview` (rule 4)

#### Docs touched
- [ ] Roadmap / TechDebt / Design updated, or none needed — say which
#### Kit / API version note
- [ ] Consumes `YDeliveryKit x.y.z` / `YandexDeliveryExpress x.y.z` — patch or minor, stated
```

### 6. Dependabot for Actions (repo-agnostic, tiny) — one file

Two external actions (`checkout@v5`, `setup-xcode@v1`) and no bump mechanism:

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule: { interval: "monthly" }
```

Swift packages are *not* added here on purpose: the pins are floors chosen by hand
(`minorVersion`), and a bot PR against `Package.resolved` would fight the "package-first,
tag, then consume" sequencing.

### 7. Tags and releases as review checkpoints (repo-specific; decision needed)

Zero tags on an app whose two dependencies are tagged 24 and 5 times. Nothing anchors
"the build the author walked on the device on 2026-09-25" or "what shipped to the first
TestFlight tester". Options:

- **(a) Do nothing until TestFlight.** Honest today: releases are checkpoints, not
  shipments, and the Roadmap's *Done* section already names PR ranges per phase.
- **(b) Phase tags** — `phase-3`, cut at the Roadmap's done-when, annotated with the
  done-when sentence: `git tag -a phase-3 -m "a sender learns their courier arrived without opening the app"`
  plus `gh release create phase-3 --generate-notes`. Cheap, and the release notes come
  free from PR titles (which are already sentences).
- **(c) Semver tied to `MARKETING_VERSION`** — DiceLab's model, with a `release.yml`
  asserting tag = `MARKETING_VERSION`. Only worth it once a build leaves the machine.

**Recommendation: (b) now, (c) at the first TestFlight upload** — with `1.0` bumped to
`0.x` first, since "1.0" with `CURRENT_PROJECT_VERSION: 1` is a template default, not a
version.

### 8. Labels → `release.yml` (repo-agnostic, only with §7) — one file, 20 s/PR

Labels are applied to nothing today, so generated release notes would be one flat list.
If §7 lands, four labels earn their keep — `feature`, `fix`, `docs`, `debt` (the last
mapped to `YD-n` discharges) — and:

```yaml
# .github/release.yml
changelog:
  categories:
    - title: Landed
      labels: [feature]
    - title: Fixed
      labels: [fix]
    - title: Debt discharged
      labels: [debt]
    - title: Docs
      labels: [docs]
```

`gh pr create --label fix` is the whole habit. Skip if §7(a) is chosen.

### 9. A Kit/API CI (cross-repo, repo-specific to the trio) — copy one file

The Kit and API repos are protected but have **no CI**; the Kit's `0.3.11` needed three
retags in one night because the toolchain difference only surfaced when the *app's* CI
consumed it. The app's `ci.yml` minus the `xcodegen` step is the Kit's workflow:

```yaml
- run: xcodebuild test -scheme YDeliveryKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
```

(`swift test` on macOS does not build the iOS-only Kit — `CLAUDE.md` rule 6.) With it in
place, the Kit's protection can require the check too, and a tag is cut on a green
`main` rather than a green laptop. This is the one proposal that is infrastructure; it
pays because the three repos ship together.

### 10. Small hygiene files (repo-agnostic) — minutes, low priority

- **`SECURITY.md`** — five lines: this app handles OAuth tokens and route PII (YD-12);
  a public repo about a payment-adjacent service should say where to report a leak.
- **`CONTRIBUTING.md`** — skip; `CLAUDE.md` and the README already carry the rules, and
  there are no outside contributors to onboard.

---

## Deferred — team-scale or inapplicable here

| Feature | Why it does not pay |
|---|---|
| Issues as the canonical tracker | `TechDebt.md` (`YD-n`) + `Roadmap.md` are the system, rendered as DocC and cross-linked from code (`// TODO(YD-n)`); issues stay the *decision-record* exception (`#15`, `#25` in the siblings). Moving 18 register items into issues duplicates a working thing. |
| Milestones | Phases live in the Roadmap with done-when sentences; §7(b)'s phase tags give GitHub a visible anchor without a second board. |
| Issue templates / forms | No external reporters. |
| CODEOWNERS / required reviews | One maintainer; Devin Review is the reviewer and already runs per push. |
| GitHub Projects | Roadmap is the board; Projects is on and unused — `gh api … -F has_projects=false` is cosmetic. |
| Signed commits | Contributor-authenticity payoff; solo repo. |
| SwiftLint / SwiftFormat in CI | Conventions are comment- and review-driven (`REVIEW.md`); revisit if drift shows. |
| Device lane in CI | Share acceptance, App Clip, Live Activity survival across updates need a physical device and a second iCloud account — the open list in `Collaboration.md` — and no hosted runner has either. Stays a manual pass. |
| Dependabot for Swift packages | Conflicts with the hand-chosen `minorVersion` floors and the package-first tagging flow. |

---

## Rollout

**Now (~15 min, all reversible):**

```bash
gh api repos/laconicman/YDelivery -X PATCH -F delete_branch_on_merge=true \
   -F allow_merge_commit=false -F allow_rebase_merge=false                      # §1, §5
for b in feat/claim-refusals feat/pending-acceptance feat/share-handoff feat/widget-surface; do
  gh api "repos/laconicman/YDelivery/git/refs/heads/$b" -X DELETE; done         # §1
git config --global fetch.prune true                                            # §1
# README badge (§2) — one line, in the next docs PR
# §3: pick (a)/(b)/(c); apply the ruleset JSON above; then fix CLAUDE.md rule 10 to match
```

**Next PRs (habits, not setup):**

- `contrib in … --pr N` → `owed 0`, `to re-read 0` before `gh pr merge` (§4)
- `gh pr merge N --squash --auto` once §3(c) is on (§3)
- Commit `pull_request_template.md` + `dependabot.yml` (§5, §6)

**At the Roadmap's next done-when:** `git tag -a phase-3 …` + `gh release create
--generate-notes` (§7b); labels + `release.yml` only if the notes prove worth reading (§8).

**Cross-repo, one afternoon:** the Kit/API `ci.yml` (§9), then require the check in
their existing protection.

**Watch for:** §3(b)/(c) will block the fast pin-bump merges — that is the point; if it
bites, `workflow_dispatch` plus `--auto` is the remedy, not an admin bypass.

---

## Repo-agnostic vs repo-specific — the consolidation view

| Travels to any repo | Depends on this repo |
|---|---|
| §1 branch cleanup, §4 reviewer audit, §5 squash-only + template, §6 Actions Dependabot, §8 `release.yml`, §10 hygiene | §2 badge (only the one repo of the trio missing it), §3 protection *with a required check* (needs the CI this repo has), §7 phase tags (the Roadmap's done-when sentences make them meaningful), §9 sibling CI (the three-repo tagging flow) |
| Deferred table rows 1–7 | Device lane (CloudKit sharing, App Clip, Live Activity), Swift-package Dependabot (the `minorVersion` floor convention) |
