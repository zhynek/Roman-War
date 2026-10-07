# Buildings That Show Their Work — 0.10.0 verification

Baseline: fetched `origin/main` at
`257fb72149a9db3d05cab079a5c640175231f4c1`, the published 0.9.0 village.
Version 0.10.0 was unused. The fifteen prior releases and their assets were recorded
in `/tmp/yenikapi-0.10-releases-before.json`; stable latest was `v0.14.2`.
Unrelated city-lifecycle draft work was preserved outside the feature commit.
The release is frozen from an isolated clean checkout of committed feature source.

## Boundaries and acceptance

The saved queue and completed IDs still own projects. Existing asset initiatives
own staffing, priority and pause, with the existing finite allocator, payment and
refund rules. No core, balance, wrapper, household relationship, historical claim,
dated reference or previous release is intentionally changed. Portable board/easel
furniture is an explicit gameplay interpretation in the existing working room.
There is no new facility benefit, delivery economy or construction damage system.

The construction read model, site meshes, matching picking/collision, small status
marks and room plans derive from those records. The dock, exact site and enlarged
easel all open `visual_commands.gd`'s project review and public command boundary.
Actual original occupied buildings also select their ongoing adaptation. Pausing
preserves the partial geometry and investment; only explicit seasonal resolution
can add forecast work. Cancellation uses the unchanged unused-fraction refund.

The construction checks cover all quarter stages, actual assigned citizens,
intermediate saves, old manual-workforce forecasts, authority, finite competing
crews, zero staffing, missing prerequisites, disabled access, both active/paused
incident lifecycles and deterministic replay. Completed geometry is compared with
a fresh build object-by-object. Citizen routes are walked through actual collision.
Retained rendered suites cover complete compact/outward development.

The new real-input walkthrough begins with ordinary resources. It commissions
through board → selected easel → enlarged controls, then changes the same project
through overview and physical site, saves/loads partial work, pauses/resumes, reaches
completion, compares competing investments, cancels legitimately, inspects a blocked
outer home, and checks 1024×768 controls. Both incidents are resolved with active
and paused projects after pre-incident saves, then replayed and loaded after the
outcome. Screenshots include landscape, aerial, street and working-room interiors.
No progress, resources or completed work are injected into these scenarios.

## Findings during development

Numeric-equivalent footprint arrays from authored JSON and canonical saved records
were comparing unequal, forcing needless world replacement. Explicit numeric
footprints fix that. Real footprint changes now patch local terrain triangles and
reuse unchanged buildings. Route caches are retained only after height/collision
revalidation. New terrain vertices must extend tangent arrays too; an early render
caught and corrected that mismatch. Exact cold-build face comparisons guard the
result. Finite authored building changes append a small number of terrain vertices;
this is not an unlimited terrain editing API.

Room inspection caught tiny plan labels, an edge-on easel and clipped controls;
these were corrected. The acceptance harness originally assumed the care project
would finish during winter, despite the allocator correctly forecasting zero work.
It now records that shortage and waits for actual completion. Native/deferred UI
events exposed stale test-control references; clicks now use atomic pointer input
and re-find controls, retrying only when no command or state change occurred.
Failed development runs are not release acceptance.

## Before-edit profiling

Exact 0.9.0 Mac application, Godot 4.4.1, Apple M3 Max, Metal 3.2 Forward+,
1600×1000, measured before source changes. Times include the callback and two
rendered settling frames; these are local samples, not guarantees.

| Existing visual-profile operation | Ready time |
|---|---:|
| Select a place | 37.987 ms |
| Cached project model | 19.461 ms |
| Compare growth | 38.009 ms |
| Change priority | 53.149 ms |
| Adaptation-completion season | 3,061.817 ms |
| Fresh living season | 670.770 ms |
| Ordinary season in that sequence | 189.971 ms |

Logs: `build/yenikapi-0.10-baseline/visual-profile.log` and
`detail-corrected.log`. A separate diagnostic measured authoritative resolution at
0.993 ms and showed route rebuilding dominating scene refresh. New planning-room
operations did not exist in 0.9.0, so no fabricated pre-feature timings are given.
The new profile records each required site, oversight, board, easel, comparison,
staffing, priority, pause/resume, seasonal, completion and route operation.
Exact-package measurements and final acceptance/public byte results are appended
after the frozen build. No Intel performance or Developer ID notarization is claimed.


## Source candidate and parent acceptance

Initial feature candidate: `0f44d23`. Source validation and all retained suites pass
**13,001 assertions**, including **841 construction checks**. The final normal-stock
construction input sequence passed **661 checks / 33 captures**. Parent data
validation reports zero errors/warnings; import, all **705 tests**, and the rendered
map playtest pass. Planning, marching, arrival and maximum zoom were inspected.
Every log was scanned for script errors independently of exit status.

Logs are under `build/yenikapi-0.10-source-gates/` and
`build/yenikapi-0.10-parent-gates/`; source screenshots are outside the repository
at `/tmp/yenikapi-construction-final-source/` and `/tmp/yenikapi-0.10-parent-map/`.
The clean release source is `/tmp/yenikapi-0.10-release-source/`. Source UI
inspection covered all 33 views; exact packaged acceptance remains the release gate.

A final coexistence review separated two workroom adaptations onto opposite sides
of the retained building, and incident preparation/repair displays along their
shared site edge. Their positions depend on stable identity, never queue order,
so later commissioning cannot move a paused project. Five additional checks prove
coexisting workroom displays are distinct and individually selectable (846 total
construction checks); the rendered gate adds their normal-stock coexistence view.
The first candidate build was stopped before publication and superseded.
