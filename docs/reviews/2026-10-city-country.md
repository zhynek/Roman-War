# City, countryside and country — October 2026

The shared Roma campaign now begins above the living city. Wheel or trackpad
zoom can inspect its buildings, widen to the whole district, and continue
outward into the campaign map. The campaign retains the same Game and save.
Selecting Roma and choosing **Enter Roma** returns to the retained city;
ordinary governing commands and the explicit **Campaign map** button remain
available.

## Navigation and architecture

The campaign map spans 0.18× to 40×. **Country** frames charted geography,
**Countryside** shows its intermediate terrain context, and **City** frames
the selected settlement or the player's capital. Scrolling remains anchored
to the pointer. At close range, town selection uses the map's terrain projection
and known province geometry; force picking uses the drawn miniature positions.

Known, surveyed settlements have original procedural architectural models:
street blocks, homes, civic precincts, walls and gates, farms, and watchposts.
Completed building tiers and settlement size determine their development.
Working construction has scaffolding; later queue entries do not appear as
visible projects. Housing reserves the geographic road approaches, with gates
aligned to those approaches. Models and close detail are retained and culled
with the camera, rather than regenerated on every frame.

This is a transition between the existing detailed Roma district and a
campaign-scale settlement miniature. They share campaign development and
ownership, but are not the same building-for-building mesh. Roma remains the
enterable city; other settlements retain their campaign commands. The
procedural models are illustrative architecture, not historical city surveys
or finished photorealistic assets. No image assets or external artwork were
added.

## Observation and memory

Geographic knowledge and current observation remain separate. Settlement
reports carry the observed owner, population, settlement tier, completed
building levels, watchpost, current construction and campaign date. When the
observer leaves, the last report drives the architectural model and ownership
display. Hidden development and ownership changes do not redraw that city.
Returning scouts or active observation replace the report at existing
reconnaissance boundaries.

Watchtowers and fortified posts use the existing sight and forest-detection
rules. Knowing a forest exists does not reveal an army concealed beneath its
canopy. Settlement reports contain no troop rosters, and campaign models only
receive public reports. Treaty maps grant geography without inventing a city
survey. Uncharted land remains hidden and cannot be selected through the
close-view model.

Terrain and tree layouts are presently fixed geography. The dated city report
does not introduce changing forests, logging, or a new ambush simulation; the
existing concealed-force rules continue to govern military observation.

The optional `settlement_memory` save field is initialized in new games and
fixtures, backfilled from current observation in legacy saves, validated at
the save boundary, and read through detached report queries. Legacy maps do
not fabricate architectural history for places no longer in sight. Camera
gestures, model previews, scene changes, and drawing consume no campaign time,
movement, money, or RNG.

## Reproduction

Run the normal data/import/full-suite/map-playtest release gates in
`AGENTS.md`. The added rendered acceptance harness uses a fresh shared senate
campaign and isolated QA storage:

```sh
godot --path . --script res://tools/city_country_playtest.gd -- out_dir=/tmp/roman-war-city-country
```

It injects real pointer input into the rendered window for city zoom, the
outward handoff, scale buttons, city selection and entry, and the explicit
return command. It checks that the whole navigation cycle leaves campaign
state and RNG unchanged. Additional controlled fixtures exercise loss of
observation, hidden development and troops, renewed scouting, and an observed
architectural growth comparison. Those growth images are fixtures, not a
claim that a long campaign was played or its balance validated.

Screenshots stay outside the repository. The image sequence covers detailed
Roma, the complete campaign miniature, countryside, charted country, maximum
zoom, the remembered town before and after hidden changes, renewed observation,
and development before and after the growth fixture.

## Rendered result — 2026-10-03

Final release gates passed: **705 tests, 0 failures** on Godot 4.4.1; data
validation **0 errors, 0 warnings**; clean import and no `ERROR:` or
`SCRIPT ERROR:` diagnostics in the full suite. The existing non-equal-anchor
warning in a UI smoke test remains. The required `map_playtest.gd` passed
planning, issuing, marching, arrival and 40× maximum zoom; all four related
screenshots were inspected under `/tmp/roman-war-city-country-final-map`.
The exported runtime, data, schema and test source hashes match the final
working source. `git diff --check` passed. No production release was published.

The city-to-country harness passed with exit code 0 and no Godot script or
error diagnostics on Godot 4.4.1, Forward+, Apple M3 Max. All twelve PNGs were
inspected at 1600×1000: the city/detail handoff, scale buttons, explicit entry
and return, maximum zoom, identical architecture before/after hidden changes,
freshly observed development, and the larger developed Roma fixture rendered
successfully. The real pointer events include the project's window-stretch
transform; this matters when reproducing at sizes above the 1280×800 logical
canvas. This was acceptance inspection, not a frame-rate benchmark.

The exact exported **0.22.0 Mac preview** at
`build/city-country-20261003/Roman War Playtest.app` also passed the complete
harness with exit code 0 and no Godot error diagnostics. Its twelve images
were written to `/tmp/roman-war-city-country-packaged`; the whole-city,
country, maximum-detail, remembered-intelligence and developed-city images
were inspected from that exported run. This confirms the packaged executable
and bundled resources, not just an editor launch. The initial country view
contains the four provinces the fresh senate campaign can observe; the rest
remains uncharted. Broader terrain becomes available through play and map
access, not through a camera gesture.
