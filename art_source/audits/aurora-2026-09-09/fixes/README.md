# Audit fixes — 2026-09-09

Implemented all six findings: curtains repositioned above the ridges, full-duration night prediction, latched preview isolation, IDLE rescheduling after reset, banking before completion saves, and rendered aurora checks in the existing sky gate. Removed temporary overrides/logging. Updated the calm plan and corrected the historical handoff's overstatements. No calm terrain, wash, camera, or achievement code was added. Changes remain uncommitted.

Validation: fast five 5/5; native lifecycle/prediction 76/76; rendered gate passes for the existing 44 measurements plus aurora ramp/individual curtains at two aspect ratios, exact zero/death restoration, and night-boundary acceptance/rejection. Green peak contribution is 124–128/255. Native screenshots show the full night palette. Physical Android performance remains unmeasured.

One later capture attempt read stale frames after its desktop window stopped updating. The gate now forces a render before reading its viewport; the rerun passed and the attached screenshots were inspected. No player's live save was used by the feature probes. The lifecycle probe requires the isolated SaveStore paths described in the parent README.

- `fixes-check.log`: fast checks.
- `fixes-lifecycle.log` / `.gd`: native regression results and temporary reproducer.
- `fixed-capture-gate.log`: rendered results with fresh-frame capture and screenshot instrumentation.
- `fixed_native_night_1152_on.png` / `fixed_native_night_1440_on.png`: final full-scene captures.
