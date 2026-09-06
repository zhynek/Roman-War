# Realism study — development comparison, 2026-09-06

This is an opt-in **3D art and motion prototype**, not a completed photorealistic
campaign renderer. It introduces a separate, staged landscape that can be
compared with the retained, playable 2D campaign. No production main scene,
version, installed app or gameplay rules are changed.

The occupied `codex/map-gameplay` worktree was retained, including its v0.12 and
v0.13 changes. A fresh fetch verified HEAD and `origin/main` have zero divergent
commits. No historical branch was substituted, and nothing was published.

## Try it

Open the separate `build/realism-study/Roman War Realism Study.app`, or run:

```sh
godot --path . --script res://tools/realism_preview.gd
# The same interactive entry as the standalone app:
godot --path . res://src/ui/realism/development.tscn
```

**Play approach** follows the shoreline track. **Woods emergence** changes the
camera and plays the opposing formation leaving the trees, stopping at contact.
The timeline supports arbitrary seeking and pausing. Drag to orbit, Shift-drag
to pan, wheel/pinch to zoom. The four presets cover landscape, troops, wooded
flank and mountain pass. Terrain notes explain the visual choices. Click a
visible figure for its illustrative formation note.

**Existing campaign** returns to the actual 2D campaign. **Open 3D study** opens
the paused comparison again. Both development entry points isolate `user://`
before constructing CampaignScreen. This is a throwaway Julii seed-42 campaign;
the normal player save is never read or written. Save slots in this preview are
per-process, so they are not intended as long-term campaigns.

Ordinary campaigns do not expose the study or construct its viewport. An
explicit `-- realism-preview` launch flag enables its Options menu entry.

## Implemented

- An original procedural 3D height field, mountain ridges, depressed lake,
  water shader, wet margins and reeds, grasses, rocks and dense woodland.
- A dry raised track beside the marsh. Both feet and roads sample the same
  continuous ground. A four-file column follows path bends with articulated
  leg motion and individual gait phases; a mounted commander carries a standard.
- Detailed mesh parts for faces, helmets, cheek guards, mail relief, cuirasses,
  sandals, greaves, curved shields, metal bosses and weapons. Colors derive from
  public UnitArt culture kits. Geometry is representational and still stylized.
- Real-time light, shadows, physical material responses, restrained distance
  fog, and retained MultiMesh batches. No generated or imported bitmap assets.
- Pausing, replaying, scrubbing, camera orbit/pan/zoom and explicit comparison.
  Hidden study viewports stop rendering. The overlay consumes keyboard input
  and disables the underlying campaign camera while visible.

## Boundaries and next work

The study has no Game reference. It receives only authored art settings;
`RealismTerrain`, `RealismWorld` and `RealismModels` cannot inspect campaign
armies or hidden enemy composition. The opposing formation is explicitly
illustrative. Animation never moves a campaign force, spends movement, starts
combat or draws campaign RNG. BattleResolver and save format are untouched.

The landscape is not a geographic reconstruction of a campaign province.
Water avoidance, the raised track and woodland emergence are authored visual
examples. They do not introduce terrain collisions, ambush odds, line-of-sight
rules or continuous tactical movement. The existing campaign still uses its
province graph. Comparing views therefore compares aesthetic approaches, not
identical geography in two renderers.

This establishes a reviewable 3D development direction; it does **not** meet a
finished hyperrealism bar. Character anatomy/rigging, physically richer ground
materials, natural shore erosion, seamless regional terrain generation, camera
LOD and per-culture/class equipment need further art work. A full campaign
integration should consume already fog-filtered map presentation snapshots and
resolved movement traces, retaining shared drawing/picking coordinates. Keep
new terrain movement or ambush rules as a separately designed engine change.

## Reproduce verification and packaging

```sh
python3 tools/validate_data.py
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
godot --path . --script res://tools/map_playtest.gd -- out_dir=/tmp/classic-qa
godot --path . --script res://tools/realism_preview.gd -- qa out_dir=/tmp/realism-qa
python3 tools/build_realism_preview.py --godot /path/to/Godot
```

The packaging tool copies the working source into a temporary project and
changes only that copy's name, bundle id and main scene. It exports a debug
app into the ignored build directory and rejects Godot error diagnostics as
well as failing exit codes. QA screenshots remain outside the repository.

The study tests cover repeatable height, complete four-file road clearance,
finite route endpoints, terrain sampling, explicit development gating, isolated
storage and uncorrelated vegetation placement. The rendered harness also checks
that the entire campaign JSON (including RNG) is identical after camera changes,
seeking and playback, that comparison restores campaign input, and that the
hidden viewport stops rendering.

Godot 4.4 [environment documentation](https://docs.godotengine.org/en/4.4/classes/class_environment.html)
was checked for the lighting and Compatibility renderer capabilities. The study
uses the existing Compatibility renderer; it does not enable unsupported SSR,
volumetric fog or SDFGI effects.

## Verified results

- Content/schema/cross-reference validation: **0 errors, 0 warnings**.
- Complete regression suite: **509 tests, 0 failures**, no `ERROR:` or
  `SCRIPT ERROR:` diagnostics. The existing anchor layout warning remains.
- Final affected suites after input/pause refinements: **72 tests, 0 failures**.
- Classic map rendering: planning, marching, arrival and maximum zoom passed;
  all four were inspected, with QA images outside the repository.
- Final exported-app rendering: landscape, marching column, woodland emergence,
  contact, maximum troop detail and mountain pass captured. Viewport event
  routing, paused gait, complete campaign/RNG immutability, comparison, and
  hidden-viewport suspension passed.
- Apple M3 Max, Compatibility, 3456×1990: 75-frame exported-app sample measured
  **24.6 ms median / 28.5 ms p95**. This is a short local sample only.
- Universal macOS export and strict ad-hoc signature verification passed.
  The standalone app was opened and its paused study visually confirmed.
- `git diff --check` passed. No release, remote push, or production replacement.

The full suite preceded the final presentation-only input/pause refinements;
the affected suites and exported renderer were checked again afterward.
Build metadata and logs are in `build/realism-study/BUILD-INFO.json`.
The user was asked whether original texture/model assets may be allowed for a
subsequent photorealism pass; no permission to change the art policy was assumed.
