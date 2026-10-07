# A Village at Your Fingertips — 0.9.0 verification

Baseline: clean `main`, fetched origin at
`d3343bc1773336b08ae58b0376b6b4b0a36afbec`. The earlier Roma bottom bar and
building development viewer were found in `src/ui/city/city_screen.gd` and
`docs/reviews/2026-09-roma-city.md`. They informed the village interaction pattern;
no parent classes or economic systems were copied into the independent project.
Version 0.9.0 was available. Fourteen prior releases / 86 assets and stable latest
`v0.14.2` were recorded in `/tmp/yenikapi-0.9-baseline/` before publication.

## Scope and preserved state

Original procedural place illustrations, a bottom command dock, building-based
improvement/standing-order cards, current/planned model comparison, normal-stock
commission/pause/cancel, a connected growth guide, local knowledge, visible warning
and recovery, role selection, seasonal report and explicit saves form the new
primary interface. The detailed ledger and previous chapters remain accessible.
Reviews collapse the action row to keep small-window choices readable. Rendering
is original vector art and production meshes; no image files were added.

Every command uses existing quotes and rules. No scene-free core, balance,
seasonal semantics, historical claim, save wrapper, reference mesh, dwelling or
previous model is changed. Existing saves adopt nothing by merely opening this UI.
The selected card/model angle are unsaved presentation. Authored numeric choices
are canonicalized before dispatch, preserving exact save/load representation.
New-game confirmation preserves the old file until Save is explicitly requested.

## Development findings and checks

The first rendered pass exercised construction, preparation, incidents and repair.
It exposed integer/float representation differences in authored choices; dispatch
normalization fixed them without changing the core or save reader. A subsequent
layout pass exposed a header's pre-layout minimum height moving a review offscreen.
Reviews now follow the actual laid-out header. Native-size text and a collapsed
action row give small-window reviews enough room. The first native confirmation-window check did not receive its synthetic click;
restart now uses an explicit confirmation in the same village panel, preserving
the current game until confirmed. These failed development runs were not published.

Visual schema/reference validation and six malformed-data cases pass. The first
complete source playthrough passed 96 checks / 18 images; the expanded final gate
adds normal-stock compact/outward homes, actual world selection, current/planned
models and confirmed restart. All existing gates remain required. Exact frozen
results and public byte verification follow below when complete.

## Fresh before-change observations

Source Godot 4.4.1, Apple M3 Max / Metal 3.2 Forward+, 1600×1000:
opening assets 1,296 ms; opening living 4,318 ms; adaptation commission 286.972 ms;
priority 53.343 ms; site comparison 7.913 ms; watch reassignment 387.533 ms;
adaptation-completion season 3,885 ms; ordinary living season 702 ms;
targeted living inspections 15.644–16.271 ms; forced living routes 150 ms.
`/tmp/yenikapi09-before.log` separates command, world and UI time.

The new visual profile records synchronous callback time and time through two
rendered settling frames separately. Actual-pointer playtest timing includes its
fixed frame pacing and is not presented as interaction latency. All observations
are local samples, not guarantees; physical scene replacement remains more costly
than changing a menu. No Intel performance or Developer ID notarization is claimed.


## Source candidate acceptance

The expanded source playthrough passed **386 checks / 25 captures**, all inspected
at 1600×1000 and 1024×768. It completed paid incident recovery and both housing
layouts from the same real saved state. No resources or completed projects were
injected. Model inspection subsequently caught two presentation edge cases:
Godot's strict array lookup needed canonical numeric data for the current-order
label, and an unbuilt site's Current model must not fall back to another home.
Both have focused regression checks; exact-app acceptance repeats the expanded
playthrough including these cases. The final visual rule/purity suite has **67**
checks. All previous village gates passed; parent data/import, **705 tests**, and
rendered planning/marching/arrival/maximum-detail acceptance passed without script
or error diagnostics. The four map images were inspected.


The first frozen attempt at `4157ebf` stopped during the retained source interaction
profile: direct `asset_panel.begin()` still entered with visual mode enabled, so
the hidden-ledger optimization skipped creating tabs. The legacy asset entry now
explicitly selects ledger mode, like the other earlier chapter entry points. A
regression check covers it. Showing a previously hidden ledger also rebuilds its
current content, covering direct place inspection after visual play. Godot exited zero; stderr inspection rejected the
candidate. It was never exported or published. The fresh final build repeats all
gates after this correction.

The second candidate at `c04e995` passed 12,160 source and exact-app checks, export,
signing and reference rendering. The retained tutorial input harness then clicked
its start button below the introduction's scrolled viewport after the extra return
to visual controls shifted the layout. It now scrolls the actual button into view
and synchronizes the native pointer before its single press/release, as the other
chapter harnesses already do. No gameplay state or extra click is injected. This
candidate was not published; the next frozen build repeats all release gates.


## Parent CI

[GitHub CI on the frozen payload](https://github.com/zhynek/Roman-War/actions/runs/37580508467)
passed both data validation and the complete parent suite. The preceding
[c04e995 run](https://github.com/zhynek/Roman-War/actions/runs/37579317693)
passed 704 tests but missed the existing parent turn-time limit: 604 ms average
against 600 ms. Parent code, test limits and campaign data were unchanged; no
threshold was relaxed. The local complete suite also passed all 705 tests.


## Frozen exact-app acceptance

Frozen payload: `1d4e49a0772f486c8efac8d507a13ebef34a77e4`. The fresh build passed **12,160**
rule/geometry/UI checks on each executable, every schema and malformed-data gate,
**4,159** rendered checks and **151 captures** (125 retained
views plus the expanded 26-view visual playthrough). All captures were inspected.
Logs include stderr and were scanned independently. The universal app's signature,
Apple Silicon/Intel architectures, packed content and source hashes were verified.

All **36 GLBs remain byte-identical to 0.8.0**. The nine ZIPs pass integrity and
member readback: the app ZIP matches the actual tested bundle; the source ZIP
matches frozen hashes; model partitions match tested exports. The checksum manifest
and provenance match all nine ZIPs. No failed candidate was published.

The exact-app visual flow uses real pointer controls and ordinary resources for
improvements, standing choices, finite labor, warnings, paid repair, saved state,
compact/outward homes, current/planned models, unbuilt sites and restart confirmation.
It checks canonical order labels, disabled prerequisites, authority, duplicate
payments, state purity and retained reference boundaries. Small-window review uses
1024×768; retained acceptance also covers 1280×800. The scene-free core and save
reader are unchanged from 0.8.0.

## Final interaction measurements

Godot 4.4.1, M3 Max, Metal 3.2 Forward+, 1600×1000. Values below are single local
observations. Callback includes synchronous rules/world/UI work; rendered ready
includes two actual drawn settling frames. Neither is inferred from frame rate.
The source and exact app use the same profile scenario and commands.

| Interaction | Source callback / rendered ready | Exact app callback / rendered ready |
|---|---:|---:|
| Start living village | 1400.579 / 1480.056 ms | 1104.547 / 1184.826 ms |
| Choose a place | 5.820 / 35.579 ms | 3.987 / 34.492 ms |
| First building preview | 39.334 / 70.471 ms | 33.728 / 64.125 ms |
| Cached building preview | 6.614 / 36.624 ms | 5.004 / 34.461 ms |
| Open growth guide | 16.890 / 47.802 ms | 17.080 / 47.711 ms |
| Local knowledge | 17.389 / 47.375 ms | 14.188 / 44.432 ms |
| Change material preparation | 70.355 / 99.578 ms | 59.491 / 88.658 ms |
| Commission adaptation | 250.943 / 284.847 ms | 204.364 / 238.159 ms |
| Change project priority | 51.451 / 80.894 ms | 41.390 / 70.369 ms |
| Complete physical adaptation | 3630.309 / 3673.507 ms | 2929.669 / 2972.180 ms |
| Following season | 210.594 / 240.956 ms | 173.255 / 202.836 ms |
| Change watch priority | 6.899 / 36.140 ms | 5.091 / 33.462 ms |
| Fresh living season with ordinary preparation | 792.328 / 823.470 ms | 642.645 / 673.905 ms |

The old ledger profile also remains available for comparison: exact-app opening
living 3,647 ms; ordinary living season
595 ms; adaptation completion
3,185 ms; forced living route rebuild
128 ms. The fresh pre-change source sample
above uses that same retained profile. The visual opening batches the existing
adoption commands before one presentation refresh. Cached model menus are cheap;
physical changes and complete reloads still pause while geometry/routes rebuild.
Different rows contain different settlement states and should not be treated as
universal speedup ratios. No Intel timing or notarization is claimed.

Build output: `build/yenikapi-early-settlement-0.9.0-final3/`.
Exact-app captures: `/var/folders/31/vy1_xpsn5p58y89s48qrckcm0000gn/T/yenikapi-0.9.0-exact-qa-f_ut5d8z`.
