# Next development round — after Roman War 0.14.0

## Start here

The owner authorized shipping the integrated terrain build on 2026-09-06 and
then shutting down this session's Roman War processes. Version **0.14.0** uses
the normal start menu, persistent campaign saves and realistic procedural 3D
campaign view by default. The classic comparison remains in Options. The
separate Terrain Preview app is an older development artifact with per-process
saves; use the production app for actual play.

Read `CLAUDE.md`, `docs/HANDOFF.md`, and
`docs/reviews/2026-09-terrain-standard.md` before editing. Fetch `origin/main`
and inspect the worktree. Start new work from the shipped trunk; do not revive
historical Claude branches or reset local changes. The release is tagged
`v0.14.0`; the GitHub release and local `build/v0.14.0` contain the macOS app.
Release provenance and verification logs are in that local build directory.

## First deliverable: one convincing campaign scene

Produce a playable, repeatable route through a forest edge, a marsh causeway,
a river bridge and a mountain pass. Stay in campaign gameplay; individual
tactical battles are still out of scope. Use the shipped map and rule modules,
not a competing renderer or separate demo-only movement model.

1. Improve the original procedural terrain, water, vegetation, roads,
   settlement architecture and human proportions. The current art is visibly
   stylized, not finished photorealism. Reduce bright road lines, repetitive
   settlement blocks and oversized commander cards while preserving picking
   and readable orders. Retain original code-generated art under the existing
   no-image-assets contract; a different asset pipeline needs an explicit
   product decision rather than silently changing that contract.
2. Make rendered route geometry follow plausible clear ground at campaign
   scale, with bridge decks, narrow approaches and pass corridors. The engine
   currently traverses province edges; it does not simulate free movement over
   every rendered slope. If finer navigation is introduced, define a
   deterministic terrain graph first, and use it for AI, previews, execution
   and presentation. Never let animation decide a real move or combat outcome.
3. Implement a real forest concealment/reveal interaction, with deterministic
   spotting and explicit player counterplay. The woods-emergence study is
   currently staged motion, not an ambush rule. Concealed enemy models must
   remain generic and must not expose their hidden roster.

Acceptance: capture the same army planning, marching, crossing, emerging from
cover and arriving; show the exact movement costs and defensive factors; prove
camera/animation changes do not alter the state or RNG. Compare the same scene
in classic view. Review the result with the owner before widening the art pass.

## Supporting work, in order

- **Save reliability:** validate saved state before migration, write through a
  temporary file, and retain a recoverable backup. Verify old saves and the
  new cartography/map-access fields. Current saves are additive but the
  inherited save writer is not an atomic recovery system.
- **Terrain logistics:** ground supply currently reports connectivity only.
  Specify supplies, consumption, replenishment and interruption consequences
  before adding ration/attrition rules. Elevation defense is province-level;
  freely placing troops on an individual hill is not implemented.
- **Map agreements:** playtest pricing and useful diplomatic feedback. An
  accepted agreement shares geography and subsequent direct geographic
  reports, not live enemy military positions. War revokes future access but
  does not erase an acquired atlas. An alliance alone does not share maps.
- **AI and balance:** seeded long campaigns should exercise blocked rivers,
  mountain passes, bridges and trade routes. Review the inherited player/AI
  attack movement-cost asymmetry before retuning combat. Do not infer balanced
  campaigns merely from passing regression tests.
- **UI continuity:** preserve panel scroll/selection through refreshes, then
  reduce long mixed administration/military panels. Check all dialogs at the
  minimum supported window size and ensure generated art finishes loading.

## Code map

- `data/campaign_terrain.json`, its schema and `balance.json → terrain_routes`:
  terrain profiles, 11 authored campaign crossing examples, costs/advantages.
- `src/core/rules/terrain.gd`: physical connectivity and ground-supply report.
- `src/core/rules/cartography.gd`: persistent geography and directional rights.
- `movement.gd`, `pathfinding.gd`, `map_orders.gd`, combat/siege/AI rules:
  terrain-aware execution and quotes; retain the BattleResolver seam.
- `src/ui/realism/campaign_landscape.gd`: live meshes, height-field picking,
  presentation formations and terrain camera projection.
- `unit_models.gd`, `models.gd`, `plate_cache.gd` in that directory: original
  procedural models and transient viewport illustration cache.
- `map_view.gd`, `map_command_bar.gd`, region and negotiation panels:
  player controls, geographic disclosure and map trading.

## Verification and restart

Run data validation, Godot import and the complete suite before shipping.
Inspect stderr as well as exit status. Use the focused suites during iteration:

```sh
python3 tools/validate_data.py
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd -- suite=map_orders,map_experience,ui_forces,ui_smoke,pathfinding,campaign_terrain
godot --headless --path . --script res://tests/run_tests.gd
godot --path . --script res://tools/map_playtest.gd -- out_dir=/tmp/roman-map-qa
godot --path . --script res://tools/terrain_playtest.gd -- out_dir=/tmp/roman-terrain-qa
```

The last development gate passed 516 tests; the release gate is recorded in
`build/v0.14.0/verification`. QA screenshots belong outside the repository.
On this Mac, Godot is at
`/private/tmp/roman-war-godot/Godot.app/Contents/MacOS/Godot`, and Python with
jsonschema is `/tmp/roman-realism-venv/bin/python3`; temporary tools may need
reinstallation after cleanup/reboot. No server is needed to play the native
app. Start it by opening `build/v0.14.0/Roman War.app`.

At handoff, no Roman War app, Godot QA job or development server should remain
running. Unrelated projects' servers were deliberately left alone. Files,
release artifacts, existing on-disk saves and documentation are retained.
