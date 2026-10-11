# Organization and branch audit — 2026-09-24

Reviewed local HEAD `ae200cb` on `claude/aurora-reconcile`: repository layout, Git history,
resource references, validation runner, export filtering, service ownership, persistence,
touch handling and menu restart paths. This is an organization/maintenance audit, not a
complete gameplay or Android release certification. No gameplay code or branch was changed.

## Findings, in priority order

1. **Back up the six local commits.** GitHub branch tips were verified with `git ls-remote`.
   The feature branch on GitHub ends at `e157a6b`; local HEAD is six commits ahead. Those six
   include the September 20 audit and four fixes for save handling, touch input and biome
   restart continuity. They are committed locally but not present on either GitHub branch.
   Push the feature branch before integration; no force push is needed for the observed tips.

2. **The usual validation command omits important coverage.** `scripts/check.sh:51` runs
   four headless scripts plus an export-content check, but not `aurora_calm_probe.gd`.
   The four recent fixes also have no maintained regression checks exercising failed save
   writes, malformed save containers, multi-touch release or pause-menu phase banking.
   Searching the active probes found no tests of those save/input/restart entry points.
   The prior audit's reproductions are useful evidence, but not repeatable checked-in gates.
   Add isolated-save regression coverage and include the Aurora integration cases in the
   normal runner. There is no tracked GitHub Actions workflow; the checks depend on being
   run manually. A clean-checkout import and pinned engine/templates would be prerequisites
   for useful CI, not just adding a workflow file.

3. **Current-state documentation has drifted.** `README.md:34` says there are exactly twelve
   maintained checks, while fourteen `.gd` scripts now sit directly under `scripts/debug/`
   (plus the shell export check). Its claim that every headless gate is blind to biome code
   is too broad: the Aurora probe explicitly exercises scheduling/night queries.
   The September 20 audit still presents all four findings as open even though commits
   `7b844a2`, `e5ba888`, `9f07726` and `ae200cb` address them. `HANDOFF.md` has no entry for
   those fixes. Add a resolution note to the historical audit, update the current handoff,
   and keep one authoritative check inventory. Old engine-rewrite claims in the runner and
   debugging guide also contradict later measured corrections in those same docs.
   `scripts/autoload/services.gd:12` says script runs do not register autoloads, while the
   newer code/docs correctly distinguish the missing global identifier from a present node.
   These contradictions risk future agents undoing correct work or trusting incomplete tests.

4. **Keep large runtime files from accumulating unrelated responsibilities.** Terrain is
   2,303 lines, Player 1,055, SkyBackdrop 843 and GameManager 788, including extensive comments.
   Size alone is not a defect. Existing separation into directors, spawners, persistence and
   upgrade services is sensible. Move long historical explanations to research documents;
   extract cohesive behavior only when a real change needs it. A broad rewrite would add
   risk, especially around terrain sampling, sibling draw order and world rebasing.

5. **Release acceptance remains separate from clean organization.** The Android preset
   remains APK-oriented with blank SDK overrides; signing/store setup and physical-device
   acceptance remain documented unfinished work. Empty SDK overrides are defaults, not an
   independently established defect. This audit did not verify release signing, Android
   frame rate, thermal behavior, touch delivery or visual/audio acceptance.

## What is already clean

- Clear separation of runtime scripts, scenes, shipped assets, development docs, research,
  historical audits and ignored source art. One services autoload owns persistence/upgrades.
- No missing literal runtime `res://` file references in the scanned scripts/scenes/resources.
- No tracked credentials, keystore, `.godot` cache or Android build output found by path scan
  (this is not a full secret-history scan).
- Source art is `.gdignore`d. Debug/experiment export filtering passes its actual pack check.
- The latest save code checks write/flush success before rename, validates field/container
  types, tracks held touch indices and banks biome phase on paused restart/home paths.
  These fixes were inspected; their original fault-injection cases were not rerun here.
- Approximately 97 MB of source art and historical captures versus 8.8 MB of runtime assets.
  This is repository weight, not evidence that source art ships. No deletion is warranted
  solely from these sizes.

## Validation performed

- Fast runner: **5/5 PASS**, 38 seconds, including export content.
- Full Aurora probe: **182,974 assertions PASS**, two live integration cases.
- Literal runtime-resource reference scan: no missing paths.
- `git diff --check`: passed.
- The first headless attempt crashed after the sandbox denied Godot's normal user log path.
  Reran successfully using a temporary launcher that adds `--log-file /tmp/...`; repository
  runner unchanged. Aurora also emitted a macOS system error before completing successfully;
  no GDScript error was reported. This is not claimed as warning-free execution.
- No rendered visual gates, broader physics probes, Android install or fresh-clone setup run.
- A concurrent edit to `CLAUDE.md` appeared during inspection; left intact. Engine runs did
  not change tracked project settings/scenes. This report is the only file this audit added.

## Why this branch exists and how to return to main

A branch is a named line of saved project versions. `claude/` is just a naming prefix;
`aurora-reconcile` records the job it was created for. Commit `d29012e` combined two separately
planned/part-built Aurora branches. GitHub `main` already received an earlier version via
merge `9dbd938` (PR #1), but subsequent work continued on this feature branch.

Verified state:

| Reference | Commit | Relationship |
|---|---|---|
| Local feature branch | `ae200cb` | Current working code; six commits not pushed |
| GitHub feature branch | `e157a6b` | Behind local feature branch by six commits |
| GitHub main | `9dbd938` | Earlier Aurora merge |
| Local main | `60007f4` | Behind GitHub main by 25 commits |

`origin/main...HEAD` reports one commit only on main (the earlier merge commit) and 31 only
on the feature branch. A read-only three-way merge preview reported no conflicts. That is
integration evidence, not proof of runtime correctness or a guarantee against future changes.

**Do not merely switch to the existing local main expecting the latest game.** That checks out
older files; it does not transfer feature work. With committed changes preserved, switching
itself does not erase them, but running the older game can also rewrite newer save data without
new fields. Avoid testing old branches against valuable progression.

Recommended sequence: finish/preserve concurrent edits; push this feature branch; open a PR
against updated main; review and run checks plus the outstanding visual/device acceptance;
merge; then update and switch local main. Keep the feature branch until integration is
verified. For future work, branch from updated main for a bounded change and merge it when
ready instead of using one feature branch indefinitely.

## Integration follow-up — 2026-09-24

The owner authorized bringing this work onto `main`. The earlier branch table and findings
above describe the pre-integration snapshot, not the branch state after the merge.

- Preserving this report at the owner's requested root path, `audit.md`, and the existing
  three-line `CLAUDE.md` edit documenting project-settings recovery.
- Remote tips refreshed; Git push access verified. GitHub CLI is not authenticated, so
  integration uses an ordinary Git merge and push instead of creating a pull request.
- Rendered sky gate: **PASS**, all nine palettes, 44 measured layers, including Aurora
  checks at both viewport widths and both night palettes.
- Visual checks run in a temporary copy with save paths redirected to temporary files;
  the owner's progression is not used or modified. No gameplay changes are part of
  this integration. Android acceptance and the maintenance findings above remain open.
- Ice capture completed with three images; the final frame was inspected and showed no
  obvious rendering breakage. Biome capture completed with eight images; the night frame
  was inspected. As noted in the earlier audit, this capture tool substitutes the intro
  palette for one rotating palette; the separate sky gate covers all nine.
