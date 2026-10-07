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
