# Roma: walkable city and building development

This work builds on the unified app at `95cc24b` and preserves the campaign and
Alpine route. It adds **Enter Roma** to the same main menu. When a campaign
player owns Latium, the region panel also offers **Enter Roma** and shares that
campaign's actual treasury, taxes and societal stocks.

## Playing — current local phase 3

The pointer starts free. Left-click a building or site in the scene to select
it; right-click opens its dossier, as does **Building details** in the bottom command
bar. Selected footprints receive visible corner markers. Roof and wall picking
use the same building geometry and identifiers, including the three enterable
interiors. Residence cards explain their current scope and link relevant civic
orders; the six civic sites have their own development dossiers.

**Govern Roma** in the bottom bar, or **G**, opens a broad command panel for
policies, public works and the city report. **H** hides the top and side overlays
while leaving the bottom bar and its governing command available. The bar also
provides inspection, city plan, mouse look, civic-day advancement, **Day report**,
saves and return. The command panel has **Policies & relief**, **Public works**
and **City report** tabs, with each order's cost and current availability.

Use W/A/S/D to walk, Shift to hasten, and Left/Right to turn. **Tab** toggles
mouse look; **Escape** releases the pointer and closes the panel. **E** speaks
to a nearby citizen or opens a nearby place's dossier. **M** switches between
street view and the city plan. The tavern, muster house and council house have
open, physically walkable doors and furnished interiors.

Double-click a destination in the scene, city plan or compass map to jump
there. Site and building targets use authored approaches or entrances; ground
targets need capsule clearance and a connection to the street network. The
navigation helper rejects blocked or inaccessible destinations instead of
placing the governor inside walls, on roofs or in the fountain. A dossier's
entrance button uses the same helper. Navigation changes only the governor's
presentation position: it consumes no treasury, civic days, campaign turns or
campaign randomness.

## Building development and governing

The forum, fountain, tavern, barracks, market and council house each have
**Orders** and **Development** tabs. Development compares the **Existing**,
**Building** and **Completed** models using the same original architecture as
the street. Left-drag rotates the model and the mouse wheel zooms it. Switching
stages only changes a separate preview: it cannot fund work, complete a project,
alter the live city's appearance or spend time. The dossier retains actual
progress, expected or recorded completion day, price, maintenance, relevant
actions, and named grievance and legitimacy effects.

**Preview consequences** beneath an available order shows immediate treasury
and unrest changes, then the next civic day's stock changes and events.
**City report → Show tomorrow’s outlook** forecasts a day with the current
orders. These pure APIs deep-copy the state and execute the same command/day
rules, so funded results match actual execution from that state. They distinguish
an affordable order from a following day whose upkeep cannot yet be paid. Later
orders can change the forecast; it is not a prediction of future player choices.
The city report also retains the named factors behind local unrest, and
**Next civic day** quotes the full civic upkeep before spending it.

The four new refurbishments accompany existing street and water works. Current
tuning is authored in `data/balance.json`, and each dossier quotes it at runtime:

| Work | Up-front denarii | Civic days with ordinary crews | Daily maintenance after completion |
|---|---:|---:|---:|
| Street repairs | 340 | 3 | 4 |
| Water restoration | 420 | 4 | 5 |
| Tavern refurbishment | 300 | 3 | 6 |
| Barracks refurbishment | 480 | 4 | 12 |
| Market refurbishment | 380 | 3 | 8 |
| Council-house refurbishment | 460 | 4 | 9 |

Pending refurbishments display scaffolds. Completed work adds tavern shade and
renewed terrace furniture, barracks equipment and drapery, covered market
stalls, or council-house plaster and a civic notice board. These presentation
changes do not move collisions into a governor's existing position or close
entrances. The original street repairs, restored water, rubbish, closure notices,
patrols, petitioners and grain queues continue to reflect orders and conditions.
Completed works bring recurring maintenance and stated societal tradeoffs; they
are not a free or repeatable completion reward.

The new standing workforce policies change actual physical construction rates:

| Workforce | Work completed per civic day | Additional daily denarii | Daily grievance / legitimacy change |
|---|---:|---:|---:|
| Ordinary crews | 1 | 0 | 0 / 0 |
| Paid additional crews | 2 | 26 | −0.10 / +0.15 |
| Requisitioned civilian labor | 2 | 6 | +0.65 / −0.45 |

These costs and social flows continue until the policy is changed. Project
completion estimates use the remaining work divided by the current crew rate,
rounded up; military programmes retain their own training pace. All prices,
rates and effects are authored in `data/balance.json` and quoted at runtime.

## Actual troop development

The barracks dossier has a **Troops** tab showing the actual settlement garrison
with experience, weapon and armour levels, plus the troop types currently
available through campaign recruitment. Roma's initial campaign barracks already
supports Town Watch, Hastati, Principes and Triarii; this phase does not invent
new type unlocks or turn one type into another.

The restored barracks enables **Establish the drill programme**: 800 denarii,
three civic days and 18 daily maintenance. Completion gives eligible recruitable
land units present in Roma one experience level, within the campaign cap, and
adds one level to future recruits raised here. Its daily grievance / legitimacy
tradeoff is +0.25 / −0.10. The completed drill programme enables **Standardize
garrison equipment**: 1,000 denarii, four civic days and 20 daily maintenance,
with +0.15 / +0.10 grievance / legitimacy flows. Its local standard adds one
weapon and armour level, within campaign caps, and refits eligible units present
when it finishes. Better existing equipment is retained. Troops elsewhere are
not silently trained or refitted. A siege pauses military programme progress.

Both programmes feed `RecruitmentRules.recruit_profile`; equipment uses the
existing stamping/retraining seam and the resulting unit values are consumed
by the existing combat resolver. They create no separate city combat model.
Standalone Roma trains and equips its existing garrison. When entered from a
campaign, this tab can also queue new units through `Game.queue_unit`; the
displayed queue advances through campaign seasons, never through civic days.
The focused city mode therefore shows troop types and quality without offering
a recruitment queue it cannot advance.

## Civic dawn and saved reports

After an explicit **Next civic day** succeeds, an original synthesized gong and
a dawn overlay present the already-resolved result. The report records stock
values before and after the day, actual grievance, legitimacy and unrest deltas,
named daily causes, completed projects, relief expiry and military outcomes.
Orders paid since the last civic day are listed separately from overnight
upkeep; repeated actions aggregate their count and cost instead of growing an
unbounded history. Completed works affect the following day's social flows,
and stock limits can cap a displayed factor sum's actual effect.

**Walk into the new day**, **Escape**, **Enter** or **Space** dismisses the dawn
overlay. **Gong: on** toggles mute for the current city visit. **Day report**
reopens the most recent saved report without advancing another day or replaying
the gong ceremony. The sound, fade and report callbacks are presentation only;
the core completes the day before they begin.

A civic day is an explicit local simulation command, separate from the
campaign's seasonal End Turn. Walking, jumping, camera motion, citizen animation
and opening panels spend neither civic days nor campaign turns, and consume no
campaign randomness. The initial neighborhood is restive; this is an authored
local scenario pressure, not a secret report of the campaign's public order.

The focused main-menu mode uses `user://roma_city_save.json`, with the existing
verified staging and backup system. Return saves this city before leaving;
re-entering resumes it. Campaign entry instead borrows that campaign's facade
and save path, suspends the campaign screen, and restores it on return. Saving
from there writes the campaign slot. The additive city state retains work and
military progress, workforce policies, completed improvements, pending civic
orders and the latest day report across saves. Earlier saves receive ordinary
crews and an empty report/order ledger; no missing history is invented. Camera
positions and individual cosmetic pedestrian positions are not saved.

## Procedural visual work

Smaller chipped paving replaces the large road squares, while quieter limestone
flags mark the forum. Timber, terracotta, plaster, earth and foliage use original
analytical material grain. Ground paving no longer casts tiny self-shadows that
produced broad moire patterns. Pitched roofs and sloping awnings now size their
geometry before rotation, correcting the prior flattened, floating appearance;
roof picking planes match those corrected surfaces.

Interior lamps have visible warm flames and local light, with geometric painted
panels, tableware, hanging herbs and civic or military fittings. Branches and
irregular cypress and olive canopy clusters replace the uniformly stacked tree
masses. The new terrace and the existing furniture retain stable collision
footprints. All artwork remains original runtime geometry with no image assets.
These are increasingly detailed procedural models, not photorealistic or
surveyed reconstructions. The rotatable model preview is a comparison of
implemented stages, not a freeform construction editor.

Phase 3 adds visible dressed masonry, worn plaster edges, doors and hardware,
shutter boards, roof tile mouths and rafters. The model viewer uses the same
site and completed-work geometry as the live district. Soldier drill and
equipment programmes also change the muster-yard fittings.

Citizens now have sculpted facial features, fitted eyelids, hands and sandals,
with smooth skin, woven cloth, leather and metal materials. Articulated knees,
ankles, elbows and wrists support planted foot contacts, weight transfer,
breathing and head movement. Corrected mesh winding removes the earlier striped
self-shadow artifacts. Completed drill synchronizes guards; equipment upgrades
add visible armour. These figures remain a representative visual population.

## Layout and historical scope

`data/roma_city.json` is the single authored layout for roads, building
footprints and heights, doors, gates, civilian routes, anchors and sites.
Buildings, gate walls and major furnishings have collision; the camera's
capsule uses the actual street geometry. The geometry and citizen appearance
are original runtime meshes, with no image assets or imported artwork.

This is an **interpretive Republican neighborhood**, approximately 156 metres
within the walls, built for the campaign's 270 BC setting. It is not a surveyed
reconstruction of all ancient Rome. The administrative house and muster house
are gameplay interpretations, not reconstructions of imperial monuments or a
claim for an imperial permanent barracks at this date. Colosseum, imperial
basilicas and later monumental fora are deliberately absent.

Historical framing consulted:

- [Parco archeologico del Colosseo: the Roman Forum](https://colosseo.it/en/area/the-roman-forum/) describes the Forum's evolving civic role.
- [Parco archeologico del Colosseo: Curia Iulia](https://colosseo.it/en/invisible-deposits-conference/the-curia-iulia/) dates Caesar's later refoundation, which this scene does not claim to reproduce.
- [World History Encyclopedia: Food in the Roman World](https://www.worldhistory.org/article/684/food-in-the-roman-world/) describes food-and-wine establishments; this is comparative daily-life context, not proof of a particular 270 BC floor plan.

## Future battles

The layout retains wide approach streets, a central assembly space, narrow
side streets, courtyards, perimeter gates and interior door openings. Routes,
footprints and barriers use shared coordinates, giving tactical movement an
explicit surface to consume. This phase does **not** implement fighting,
formations, siege destruction, tactical AI, navigation baking or a second
combat resolver. Future battles must continue through the BattleResolver seam.

The citizens are a representative visual population; they do not simulate
individual households, employment, inventories or injury. Further fidelity work
includes a historically researched larger district, richer character motion,
ambient street sound, more indoor activities and freely placed buildings tied
to persistent construction. The civic gong is a presentation cue, not an ambient
soundscape. Current structural changes remain
the named public works and refurbishments. Arbitrary demolition, a terrain
editor and household-level simulation are not implemented.

## Verification

Run the data validator and a fresh Godot import, then the full suite. Focused
suites are `city_governance,city_people,city_view,city_navigation,app_modes`.
The rendered acceptance tool `tools/city_playtest.gd` checks citizen/state separation,
continuous capsule sweeps through all three interiors, exterior collision,
orders, project completion and save round-trip, and captures the street,
forum, city plan, interiors, work orders, improvements and tavern closure.
Screenshots go to `/tmp/roman-war-roma-qa` by default, outside game assets.


## Phase 3 verified result, 2026-09-26

- Godot 4.4.1 full suite against the exact frozen exported source:
  **576 tests, 0 failures**, with no script/error diagnostics. The inherited
  general UI anchor warning remains.
- Data/schema/reference validation: **0 errors, 0 warnings**; fresh full import,
  universal export, signature and architecture checks passed.
- Source and exported-app acceptance passed for current/construction/future
  models, preview purity, workforce orders and real construction rates, exact
  forecast/actual agreement, gong playback and mute, new-day acknowledgment,
  duplicate-day prevention, completed works, barracks prerequisites, actual
  garrison training/equipment, future recruit quality, saved aftermath and
  resized report layout. Screenshots inspected at 1280×800 and 1600×1000.
- Existing pointer, right-click, double-click, minimap, resize and save/load
  acceptance passed. **17 navigation physics checks** passed against the final
  geometry, including doors, roof occlusion and disconnected destinations.
- Street/interior acceptance passed: walking, all three interior doorway
  capsule sweeps, exterior blocking, street/water works and save round-trip.
  A short M3 Max sample at 1440×900 measured **8.7 ms median / 21.1 ms p95**;
  this local observation is not a hardware guarantee.
- Required campaign planning, marching, arrival and maximum-zoom checks passed;
  all four screenshots were inspected. QA images remain outside the repository
  under `/tmp/roman-war-roma-phase3*` and `/private/tmp/roma-people-phase3`.
- **0.15.2-preview.20260926** is the verified universal Mac preview. All **38**
  data tables are packed; campaign/save/replay package probe passed. Source
  hashes match the working runtime files. Logs, provenance, the exact source
  snapshot and player controls accompany the app in
  `build/roma-city-phase3-20260926/`.

The intermediate focused gates passed 57 core/recruitment/save tests and 40
city/presentation tests. The complete 576-test run above is the final gate.
This is a development preview; no production release or tag was made.

## Phase 2 verified result, 2026-09-26 (historical)

- Content/schema/reference validation: **0 errors, 0 warnings**; fresh Godot
  import and release export passed without script/error diagnostics.
- Godot 4.4.1 full suite against the exact frozen preview source:
  **565 tests, 0 failures**. The inherited general UI anchor warning remains;
  there are no script/error diagnostics.
- Actual pointer acceptance passed in source and the exported Mac app at
  1280×800 and 1600×1000: bottom governing controls, roof selection, right-click
  dossier and funding, double-click street/entrance travel, minimap travel,
  completion visuals, save/load, and resized picking. The scrolled development
  timeline and its effects were separately rendered and inspected.
- Navigation physics: **17 checks passed**, including real occlusion, doors,
  roofs, all six civic approaches, furniture, wall boundaries, a disconnected
  fountain basin and campaign/RNG invariance. Six uncached travel samples on
  this machine measured 17.5 ms median and 43.3 ms maximum.
- Street/interior acceptance passed: actual walking and explicit mouse-look
  capture, three doorway capsule sweeps, wall collision, street/water works,
  save/load and viewport fit. A 1440×900 M3 Max sample measured 8.4 ms median
  and 12.9 ms p95 frame time. These are local samples, not hardware guarantees.
- Required campaign planning, marching, arrival and maximum-zoom checks passed;
  all four screenshots were inspected. City screenshots remain outside the
  repository under `/tmp/roman-war-roma-phase2*`.
- Universal Mac preview **0.15.1-preview.20260926**: both architectures and
  ad-hoc signature verified; 38 data tables packed; campaign/save/replay
  package probe passed. Source hashes match the working runtime files.

Preview: `build/roma-city-phase2-20260926/`. This contains the app, distributable
archive, exact source snapshot, player controls, verification logs and updated
provenance. No release tag or production publication was made.

## Phase 1 verified result, 2026-09-26 (historical)

- Content/schema/reference validator: **0 errors, 0 warnings**.
- Godot 4.4.1 full suite: **556 tests, 0 failures**, no script/error diagnostics.
  One inherited anchor-layout warning remains in the general UI test.
- Rendered Roma: actual click/W walking and Escape release, all three door
  capsule sweeps, wall blocking, project completion, separate save slot and
  save/load round-trip passed. Eight city images inspected outside the repo.
- Required campaign map: planning, marching, arrival and maximum-detail checks
  passed, with the four relevant screenshots inspected.
- Universal Mac preview exported, ad-hoc signature and both architectures
  verified, all **38** content tables packed, campaign/save/replay package probe
  passed. The source snapshot and build provenance are retained with the app.
- A short rendered sample on this Apple M3 Max at 1440×900 measured 7.8 ms
  median and 11.3 ms p95, excluding screenshot readback. This is a local sample,
  not a performance guarantee for other hardware or a larger future city.

First-phase preview: `build/roma-city-preview-20260926-verified/` (ignored build output),
version `0.15.0-preview.20260926`. No release tag, remote branch, or production
publication was made. The packaged render and final archive differ only in
`tools/build_probe.gd`'s updated expected table count, and the final package
probe passed. Runtime game content and visual code were identical between
those first-phase artifacts.
