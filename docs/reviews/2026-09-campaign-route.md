# Playable Alpine route — development checkpoint, 2026-09-06

Historical checkpoint: this route was subsequently audited and approved for
[release 0.14.1](../releases/0.14.1.md) on September 26. Use that release's Mac
apps and build commands; the unpublished status below records September 6.

Production remains **v0.14.0**. This work is on local branch
`codex/campaign-route`, based on fetched `origin/main` at `3670aac`. The worktree
was clean before editing. Nothing has been published or promoted to production.

## Play the separate app

Build with:

```sh
python3 tools/build_realism_preview.py --route --godot /private/tmp/roman-war-godot/Godot.app/Contents/MacOS/Godot
```

The output is `build/campaign-route-development/Roman War Route Development.app`
and its ZIP. The development version is `0.14.0-dev-route.1`, with bundle ID
`com.romanwar.campaign-route-development`. Production project settings and the
existing `build/v0.14.0` app are unchanged. Save and Load use the persistent
**Roman War Campaign Route Development** directory, separate from production.
QA entry points use disposable directories instead.

The app opens a repeatable Julii campaign at the Pannonian forest edge. Expand
the Alpine Frontier briefing, choose the next waypoint, review the quote and
press **Issue orders**. Use **End Turn** when the next march exceeds the remaining
movement. At Noreia, **Patrol woods** reveals the neighbouring forest column.
Classic comparison is in the briefing and Options. Restart route starts a fresh
scenario; Save/Load remains available for continued development play.

## Route and rules

| Leg | Destination terrain | Crossing | Base movement in this setup | Crossing defense |
|---|---|---|---:|---:|
| Pannonia → Illyria | Hills | River bridge | 1.75 | +20% |
| Illyria → Venetia | Marsh | Causeway | 2.00 | +10% |
| Venetia → Noricum | Mountains | Pass | 2.00 | +10% |
| Noricum → Raetia | Mountains | Pass | 2.00 | +10% |

Pannonia supplies the forest start and actual emergence into open terrain.
Ground defense and crossing defense are separate named factors in the existing
BattleResolver context. The order strip shows both; unit classes and other
existing combat factors still apply. Roads built later can change these costs.
Unbridged rivers, unbroken ridges and open-water borders remain impassable to
land marches. No individual tactical battle or free placement model was added.

The scenario is authored in `campaign_terrain.json`, schema checked and cross
referenced by the validator. `CampaignRoute.build()` sets initial conditions
then returns an ordinary `Game`. The five route towns begin under Julii control,
with unimproved roads and peaceful neighbours. A substantial rebel column starts
in Boiohaemum, strong enough to survive the neighbouring AI through the review
route. It uses ordinary units and ordinary rebel AI; no timer, scripted turn or
renderer keeps it alive. A directional German map agreement supplies additional
geography through `CartographyRules.grant`; there is no omniscient atlas flag.
This is an authored campaign exercise, not a claim about a particular historical
bridge or a reconstructed ancient march.

## Real woodland concealment

Geographic observation and army observation are separate queries. Normal
columns in forest evade distant settlement lookouts, including in a province
whose terrain is currently observed. Ownership and alliances do not penetrate
cover. Local armies or agents and active local towers reveal troops; entirely
mounted columns, spies and forts also search one connected neighbouring
province. Impassable borders stop this propagation. Forced marching and an
active siege expose a forest column to normal observation.

**Patrol woods** spends one movement point and searches the current province
and one connected border. Its reports last through that season, including AI
movement, then expire at the date advance. A genuinely affordable attempt to
march into a concealed hostile position halts at the border, spends a patrol
point, reveals the contact and cancels the route. Combat remains an explicit
subsequent order. Unaffordable attempts cannot act as free scouting.

`forest_patrols` is the only new save field: a faction/region/turn ledger. It is
created in new games, backfilled empty in old saves, present in fixtures, read
with defaults and round-tripped without changing save version 2. Spotting uses
no RNG. The map, region menus, aggregate badges, attack targets, path previews,
force summaries and estimates respect the same force mask. Reported supply
connectivity does not act as a sensor for hidden columns. Enemy movement
reports omit concealed endpoints; last-seen reports retain their age rather
than following hidden forces. Revealed rival miniatures still use public,
generic appearance and never their private unit classes or templates.

## Procedural presentation

The existing `CampaignLandscape` remains the live renderer. It now uses a
continuous relief field and a shared spatial index of road corridors, avoiding
region-local height discontinuities. The existing generated road polylines have
conservative corner smoothing used by classic drawing, 3D, previews and march
playback. They do not change the deterministic province graph or movement cost.

Roads are muted earth ribbons; crossings have planar water, explicit bridge
decks and sloped approaches. Causeways are placed inside their marsh endpoint.
Reeds, irregular pools, understory and stones complement larger, varied trees.
Settlements have irregular wards, varied footprints, pitched roofs, tile seams,
doors, windows and a courtyard hall. Troops use more consistent human/mounted
scale, formations fit their existing placement footprint, commander cards are
smaller, and maximum zoom is 9×. Deck elevation is shared by troop placement and
screen projection. Terrain vertex caching is limited to construction, avoiding
a cache that grows as armies animate.

All art is original runtime geometry and shaders. There are no new image
assets. The result remains visibly procedural and stylized; it is **not finished
photorealism**. Province geography remains schematic. Broader art, route shaping
and historical geography need owner review before widening this pass.

## Verification

- Content/schema/cross-reference validator: zero errors, zero warnings.
- Complete Godot suite: **526 tests, zero failures**; no `ERROR:` or
  `SCRIPT ERROR:` diagnostics. The inherited anchor-layout warning remains.
- New concealment regressions include hidden-state preview invariance, patrol
  cost/expiry, mounted and spy/post counterplay, physical barriers, guessed-ID
  attack refusal, contact halts, movement-report clipping, additive migration,
  map sharing, render-cache privacy and every route leg.
- `campaign_route_playtest.gd` executes real orders and seasons, compares each
  season with a saved twin, captures planning/crossing/arrival, and verifies
  camera/animation/renderer changes leave the full state and RNG unchanged.
  It captures the concealed and patrol-revealed enemy in both renderers.
- Required `map_playtest.gd` and expanded `terrain_playtest.gd` cover general
  planning, marching, arrival, maximum detail, geographic agreements and UI art.
- `route_app_playtest.gd -- route-qa` checks the actual development entry at
  1280×800, the briefing's separation from the order strip and initial camera
  focus on the selected route army.
- The exported app passed the complete route playtest and actual-entry check.
  Its package probe found all 36 data tables, round-tripped a save and matched
  a loaded campaign after ten simulated turns. The separate bundle identity
  and ad hoc code signature were verified.

Final packaged-route images are under `/tmp/roman-route-packaged`; general map
and terrain checks are under `/tmp/roman-route-map-final` and
`/tmp/roman-route-terrain-final`. They are not game assets. Build logs, source
hashes, archive hash and `verification/` logs accompany the development app.
The packaged source hashes match the current game, data and tools. All Roman
War QA processes exited before handoff; no development server is required.

## Next session

Keep production at v0.14.0 until explicitly approved. Start by reviewing this
route with the owner. Improve the procedural landscape further based on that
review before extending to more provinces. The inherited save writer still
needs atomic write/backup recovery; ground supply remains a connectivity report,
not rations or attrition. The inherited AI/player attack movement asymmetry and
omniscient AI planning are unchanged. No new balance claim follows from the
regression count or this short route playthrough.
