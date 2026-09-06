# Roman War 0.12 — campaign map review and improvements

This review starts at `origin/main`, commit `af12229` (0.11.0), on
`codex/map-gameplay`. The GitHub default branch was verified as `main` on
2026-09-05. The local workspace was initially empty; no existing local edits
were replaced. Historical branches were inspected through the integration
history and handoff rather than merged into the trunk.

## Assessment

The foundation is worth keeping. The deterministic dictionary state, additive
save migrations, schema-validated content, factor breakdowns, and
BattleResolver boundary support the requested simulation well. The campaign
is much deeper than the map currently communicates. Replacing that engine or
starting another map implementation would discard useful work.

The review covered the source/module inventory, game facade, turn orchestration,
movement/pathfinding, force/commander lifecycle, combat/sieges, visibility,
save/load boundary, rendering/input, campaign panels, data/schema validation,
CI, and the existing tests and design/handoff history. AI, society, politics,
economy, knowledge and naval systems were assessed through their boundaries,
documented limitations, and full campaign/replay tests; this is not a claim
that every inherited rule has been exhaustively audited. The resulting source
inventory contains 87 GDScript files, with 34 JSON data tables and 34 schemas.

The baseline ran **469 tests with zero assertion failures**. Its log also
contained a native exclusive-window error during the assault UI test. That
matters: an assertion total alone did not establish a clean run.

## What changed

- **A map order strip.** Select an army's standard or close-view formation;
  choose a destination (or press M), click to pin it, inspect the route and
  issue orders. Escape cancels planning while keeping the army selected.
  Conventional right-click orders and the existing force controls still work.
  Forced march has an explicit toggle, and the warnings explain its fatigue.
- **One read-only order preview.** `MapOrderRules` identifies march, withdrawal,
  field attack, siege and assault, with movement costs, season-by-season legs,
  uncertainty and useful refusal reasons. A changed pinned quote is refreshed
  before it can execute. A distant hostile town is approached, not silently
  attacked. Friendly/neutral territory does not automatically declare war.
- **Actual marching.** `advance_march` returns the traversed region ids. The
  visual column follows the retained road geometry, turns at bends, carries a
  mounted commander and standard, and settles into camp. An optional camera
  follows it; manual pan/zoom releases follow. Turning animation off, loading,
  skipping playback, or issuing subsequent commands does not affect results.
- **Orders persist visibly.** A queued route displays the saved path rather
  than replanning to the same destination. Its end-turn journal beat carries
  the source and traversed route, so the day's presentation can show the
  continuing march. Old journals without those optional fields still work.
- **Three useful map scales.** Territory view retains province ownership and
  aggregate markers. Campaign view retains standards and existing geography.
  Close view (from 1.8×, up to 5.5×) reveals original procedural settlement
  wards, gates, civic halls, fields, wooded hills, trees, mountains, camps,
  troop ranks and commanders. Political washes become lighter, route widths
  stay readable, and standards stop growing into giant billboards.
- **Navigation.** Geographic overview with clickable camera placement, zoom
  presets, pinch zoom anchored beneath the fingers, two-finger pan, F to find
  the commander, and V to switch close/campaign view. Held keys no longer add
  repeated discrete jumps on top of continuous pan. Camera polling pauses
  under campaign dialogs, scrolls, battle playback and the building drawer.
- **Performance.** Detailed terrain has a retained draw list per province;
  only chunks intersecting the camera are visible. The small army layer can
  animate without rebuilding land, roads or settlements. Cosmetic decoration
  and formation anchors are cached. Unseen army rosters stay private.
- **Readable arrivals.** Formations use separate positions inside their
  destination province. Compact columns fit narrow coastal land, so a visiting
  commander remains visible and selectable beside an allied resident army.

The new experience is an animated, detailed **2D campaign presentation**. Its
figures represent formations; they are not individually simulated soldiers.
Province adjacency remains the movement model, commanders travel with their
armies, and the campaign still resolves by seasons. Continuous tactical
movement, terrain collisions, independent commander travel, real-time battles,
and an actual 3D world would require a separate simulation/design phase.

## Correctness findings closed

| Finding | Change and regression coverage |
|---|---|
| Unseen roads changed route cost/range/ETA through fog | Path previews use terrain cost until a province's roads are known. Tests vary hidden roads and armies and require identical previews. Execution still uses actual movement rules. |
| A rejected foreign move could erase that army's march before checking ownership; foreign halt/path queries were also available | Guard cancellation, halt and movement preview/reach at the facade. Tests require the foreign state to remain unchanged. |
| Adjacent combat was not represented by the old empty-path hover preview | Explicit attack/siege/assault intent includes the target even when there are zero march legs. Availability distinguishes movement, relief armies, existing sieges and unready engines. |
| Confirmation callbacks read whichever army was selected later | Field battle and assault confirmations bind the selected attacker. Pinned orders are quoted again before execution. |
| Confirming an assault could open the battle window before the confirmation was hidden | Hide the confirmation before invoking its handler. The baseline exclusive-window error no longer appears in focused regression logs. |
| Godot import errors were ignored in CI; invalid test scripts could fail to instantiate without a clean test failure | Remove import's `|| true`, reject non-instantiable scripts, preserve pipeline exit status and fail on Godot error diagnostics. Add exact suite filters for development. |

The underlying weighted Dijkstra algorithm was retained. Consolidating the UI
march path around its existing execution result is a maintenance improvement;
there is no claim that the old adjacent-step shortcut was more expensive than
the best path (destination-based nonnegative costs make a direct step optimal).

## Follow-up priorities supported by this review

1. **Save integrity.** `SaveGame.from_json` checks the wrapper/version but does
   not validate required state structure before `NewGame.ensure_state_keys`
   dereferences it. `write_file` replaces the save directly rather than writing
   and validating a temporary file before an atomic replacement. Add a
   compatible state-validation boundary and recovery/backup tests as a focused
   follow-up; this patch preserves the current save format.
2. **Military parity and AI intent.** The player facade charges a season for an
   attack; AI military code calls `CombatRules` directly. This is a documented
   inherited asymmetry, not changed here. Close it with AI planning/balance
   tests, then surface enemy intent and counterplay. Do not change it casually
   while reviewing a presentation improvement.
3. **The sea remains a separate foundation phase.** Naval movement is still
   abstract transport. Naval battles, embarked stacks and AI fleet production
   are not implemented by the new visuals. Keep those changes behind existing
   force and resolver boundaries.
4. **Campaign readability beyond the map.** Force and region panels still
   rebuild many controls and mix military, administration and recruiting in a
   long scroll. The command strip pulls frequent map actions out of that
   scroll. A subsequent panel pass should preserve expanded groups, roster
   selections and scroll position, then use collapsible sections.
5. **Broader balance requires evidence.** Existing societal and AI limitations
   deserve seeded soaks and playtests. This pass does not alter treasury,
   recruitment, society, battle odds or expansion tuning to make visual motion
   feel more dramatic.

## Reproduction

Use Godot 4.4.1 (the project's CI version) and Python with `jsonschema`:

```sh
python3 tools/validate_data.py
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
# Short iteration loop:
godot --headless --path . --script res://tests/run_tests.gd -- suite=map_orders,map_experience,ui_forces,ui_smoke,pathfinding
# Actual rendered order flow and screenshots:
godot --path . --script res://tools/map_playtest.gd -- out_dir=/tmp/roman-war-playtest
# General zoom/panel snapshots:
godot --path . --script res://tools/screenshot.gd -- out_dir=/tmp/roman-war-shots zooms=0.5,1.2,3.5,5.5 select_army
```

The rendered harness selects an existing Julii army in seed 42, pins a real
reachable province with mouse press/release events, asserts that planning did
not move it, issues the order through the button, checks arrival, and captures
the moving formation and all map scales. Frame-time samples exclude synchronous
screenshot readback and the zoom transition; they are measurements on one
machine, not a cross-platform performance guarantee.

New code uses Godot's documented
[pinch gesture](https://docs.godotengine.org/en/4.4/classes/class_inputeventmagnifygesture.html)
and [pan gesture](https://docs.godotengine.org/en/4.4/classes/class_inputeventpangesture.html)
APIs. No new runtime dependency or image asset was introduced.

## Verified results — 2026-09-05

| Check | Result |
|---|---|
| Full Godot 4.4.1 regression suite | **486 tests, 0 failures**, including the original 469 tests and 17 new order/presentation tests |
| Content/schema/cross-reference validator | **0 errors, 0 warnings** across 34 data tables and 34 schemas |
| Final project import and normal headless boot | Successful; no Godot error diagnostics |
| Rendered order playtest | Passed visible destination selection, pinning without movement, issuing, animated travel, arrival and maximum zoom |
| Map combat integration | Passed neighbouring siege, ready assault in the same province, confirmation without premature state/RNG changes, and resolution through the existing battle system |
| Source whitespace | `git diff --check` passed |

The full test log has no `ERROR:` or `SCRIPT ERROR:` diagnostics. One inherited
anchor/size warning remains in a UI layout test; it also appeared at baseline.
The baseline exclusive-dialog error is fixed.

The final rendered sample at 5.5× on an Apple M3 Max, Godot Compatibility
renderer, and a 3456×1986 viewport measured **17.4 ms median**, **18.7 ms p95**,
and **59 FPS** on the engine counter. Before per-province culling, the newly
added detailed terrain measured 34.7 ms median in this same exercise. This
comparison measures optimization within this patch, not a performance claim
against the original 0.11 map. It is a short local sample, not a benchmark of
every region or campaign size.

Six rendered QA images were inspected: territorial view, commander view,
pinned route, column on the road, arrival alongside allied troops, and maximum
detail. The harness writes them outside the repository under its `out_dir`.
The changes are local on `codex/map-gameplay`; no remote branch or release was
published by this review.

## Follow-up: v0.13

The commander identity, scouting, movement composition and direct-input work
continues in [the v0.13 review](2026-09-v13-map-overhaul.md). The baseline review
above is retained as a record of the original cross-agent codebase handoff.
