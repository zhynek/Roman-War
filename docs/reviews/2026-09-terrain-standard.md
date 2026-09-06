# Live terrain, cartography and visual standard — 2026-09-06

**Release update:** the owner subsequently authorized production release as
0.14.0. See `docs/releases/0.14.0.md` and `docs/NEXT_DEVELOPMENT.md`. The review
below records the development checkpoint before that promotion.

The approved realistic 3D direction is now the default **live campaign**
presentation. The classic map remains an Options comparison. This is a
local development change on the occupied `codex/map-gameplay` worktree, based on
`origin/main` at `af12229`; previous v0.12/v0.13 and study work is preserved.
No production application, branch merge or hosted release has been published.

## Gameplay connections

- `campaign_terrain.json` defines physical crossings separately from political
  adjacency. Eleven authored borders demonstrate bridges, an unbridged river,
  marsh causeway, mountain passes, unbroken ridge and open-water straits.
  These are campaign-scale authored constraints, not a surveyed historical
  reconstruction of particular ancient bridges.
- Marsh retains its 2-point base march cost; plains cost 1. Roads reduce the
  destination terrain cost. Bridge crossings add 0.25 points. Passes remain
  traversable mountain routes; an unbroken ridge/unbridged river is impassable.
- Movement, player paths and previews, siege entry, field attacks, agents, AI
  traversal, land commerce and grain connections use physical land connectivity.
  Open-water routes use the existing abstract coastal transport action.
- Existing hill/mountain/class advantages remain in the shared battle model.
  Crossing defense adds named factors: bridge +20%, causeway/pass +10%.
  Estimates and actual resolution receive the same battle context. There is
  still no separate individual-battle scene.
- The army strip reports a secure **ground** connection to the capital through
  friendly/allied land. Enemy forces, sieges and impassable crossings break it.
  It is a connectivity report, not a new ration, attrition or naval-supply model.

## What the player knows

`cartography` and directional `map_access` are additive save fields. Observers
record geography at authoritative action/turn boundaries. UI queries never
write the atlas. Old saves start from their present observers rather than an
omniscient map; past travel cannot be reconstructed if the old save did not
record it.

Uncharted terrain is not drawn or offered as a player route. Previously mapped
terrain stays available, while current military details require current
observation. Settlement lookouts, armies, scouts, posts, agents and fleets supply
reports. Physical barriers also restrict land sight propagation.

Negotiation offers can grant or request map access with payments or other terms.
Accepted access includes an atlas and subsequent direct geographic reports.
An alliance alone does not share maps. War ends future access without erasing
already learned geography. Neither the atlas nor the agreement shares a live
foreign roster; rival miniatures remain generic public representations.

## Presentation

`CampaignLandscape` renders retained province meshes, procedural ground detail,
forests, marsh surfaces, river crossings, roads, passes, towns, watchposts and
army figures from the same map/terrain definitions used by rules. The camera is
angled and orthographic; picking intersects the same height field used to place
the scenery. Army position and formation picking use the existing presentation
positions. Animated figures consume the already-resolved march path; no frame,
tween, shader or timer moves a real force or consumes campaign RNG.

Shared dark green/bronze styling covers the campaign, dialogs, construction and
recruitment drawers, and start menu. Commander portraits and unit/building plates
are generated in 3D and cached in memory; their temporary render viewports are
freed after capture. Unit figures preserve public class distinctions, including
mounted troops, archers, siege equipment, elephants and ships. No image assets
were added to the repository.

The visual direction is now standard; **the current original procedural models
are still stylized and are not finished photorealistic assets**. Settlement
footprints and troop counts are representative at campaign scale. Elevation
advantages are province-level factors, not free placement onto an individual
hill. The optional woods-emergence study remains a staged art/motion example,
not a newly implemented ambush rule.

## Review and verification

```sh
python3 tools/validate_data.py
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
godot --path . --script res://tools/map_playtest.gd -- out_dir=/tmp/terrain-map-qa
godot --path . --script res://tools/terrain_playtest.gd -- out_dir=/tmp/terrain-ui-qa
python3 tools/build_realism_preview.py --campaign --godot /path/to/Godot
```

The standalone app is built under `build/terrain-preview`, with its own bundle
identifier and isolated per-process development Save/Load directory. It opens
an actual Julii seed-42 campaign; Options offers the classic comparison and the
separate staged woods study. Its save slots are for review within that process,
not a persistent player campaign.

The complete suite passed **516 tests, 0 failures**, including seven dedicated
terrain/cartography tests. Data validation passed with zero errors/warnings.
The expanded rendered harness checks projection/picking, renderer state/RNG
isolation, map access, classic comparison, marsh/pass scenery and unit/building
screens. All 87 affected tests passed again after the final presentation edits.
The rendered map playtest passed planning, marching, arrival and maximum zoom.
QA images and logs stay outside the repository; build verification
logs accompany the development archive.
