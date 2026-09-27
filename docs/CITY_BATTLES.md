# Roma campaign and continuous city battles

Roma supports a continuous, controllable siege on the same procedural district
used by the city view. Troops follow its streets, avoid buildings and the
fountain, breach the south gate, and contest the Forum. The campaign garrison's
numbers, training and equipment carry into combat.

Roma, its strategic map and its battles now belong to one continuing campaign.
`CampaignSession` retains one `Game`, one save path and both city/map views.
Opening the map preserves the city visit; returning restores its walking
position and camera. The Alpine comparison remains a separate scenario and
save slot.

## Continuing Roma through the campaign

**Enter Roma** resumes the common campaign save when one exists. An older
separate Roma save is imported only when the common slot is absent. With
neither present it starts a Senate campaign using the menu's seed and
difficulty. An existing save where the player does not own Roma opens the
strategic map, preserving that campaign.

Use **Campaign map** in the city command bar to move to the same Mediterranean
campaign. **Next season** runs the normal seasonal economy, growth, construction,
AI, movement and aftermath. **Calendar & history** opens **Roma through the
years**, with the calendar,
population/treasury/garrison charts, a paged history and campaign construction
orders. **Advance one year** requests two normal seasons and stops for a siege,
visible nearby threat, a pending decision, ownership loss or campaign ending.
Prepared defences and unfinished battles block time before any civic cost.

After the city has been visited through the shared session, each accepted
campaign season schedules three funded civic work days before the normal
seasonal rules, whether advanced from city or map. Unfunded civic work waits;
the seasonal economy can still bring in income. **Next civic day** remains a
local management action and does not move the campaign calendar. These are
work operations, not a claim that a half-year consists of three literal days.

The calendar uses the campaign's existing 270 BC–AD 14 era and victory rules.
History records actual advances, retaining up to 640 snapshots. A 200-season
history/save fixture checks century-scale retention; it is not evidence of a
100-year AI simulation or long-run balance test.

## Playing

Open **Defend Roma → Practice siege**. Select a formation in the roster or the
map; left-drag a rectangle across the city to select several friendly
formations. Shift-click or Shift-drag adds to the selection. Marquee selection
works during deployment and live fighting; releasing over a HUD panel cancels
the gesture. Right-click clear ground to deploy. Choose
**Begin battle** to start the continuous simulation. There is no step button.

| Control | Effect |
|---|---|
| Right-click ground | Give the selected movement order to the selected cohorts. |
| Right-click enemy | Focus attacks; with Charge selected, order cavalry to charge. |
| Move / Attack move | Travel to a position, or engage enemies along the way. |
| Hold position | Stop moving and fight enemies within reach. |
| Fall back | Withdraw while under fire, without stopping to engage. |
| Charge | Cavalry accelerates; a sufficient run-up adds impact damage and starts recovery. |
| Cease fire / Fire at will | Disable or restore ranged attacks. |
| Space / Pause / Resume | Pause precisely; issue orders while paused if desired. |
| Speed | Switch between normal and double simulation speed. |
| WASD / mouse wheel or pinch | Pan / zoom the battle camera. |
| Middle-drag / trackpad pan | Move the camera across ground. |
| Alt-left-drag or Alt-middle-drag | Orbit and tilt the camera. |
| Q / E; Up / Down | Orbit; change camera elevation. |
| F / Follow selected | Follow the centre of the selected formations. |
| V / Aerial view | Return to an overview of the city and gate. |
| Inspect troops / Tilt view | Frame selected troops closely / switch elevation. |
| Double-click or middle-drag the plan | Recenter the camera using the inset. |
| Ctrl/Cmd+A | Select all living defending formations. |

**Archers counter cavalry; cavalry counter foot soldiers; foot soldiers counter
archers.** This is the requested gameplay cycle, not a historical universal.
Archers shoot at range with building and wall occlusion; they are weaker in
close combat. Cavalry moves faster and can charge. Soldiers must close the
distance to archers. Numbers, training, equipment, positioning and support can
still overcome an unfavourable matchup. Cohorts lose visible representatives as
their strength falls and rout when their morale breaks. Each displayed model
represents four troops; combat resolves at cohort level.

Win by defeating the attackers or holding out for six simulated minutes. Keep
the Forum contested: fifteen uncontested seconds of occupation gives attackers
the city. A routed garrison also loses the defence. Gate integrity, time,
formation strength and a final casualty report remain visible.

## Town recruitment and campaign consequences

**Barracks → Troops** displays the actual garrison and eligible recruitment.
Early **Allied Bowmen** are available through Roma's city recruitment interface.
Cavalry retains its stables prerequisite. Recruitment ordered through the city
uses the civic queue: the first local cohort completes after three funded civic
days, including those scheduled by a campaign season. Recruitment ordered from
the strategic map retains its seasonal queue. Each job advances through its
own queue once; a seasonal pass cannot train a civic recruit a second time.
Recruitment pays the shared
money/population costs, respects capacity and siege restrictions, and uses the
city's real recruit profile. Drill and equipment programmes affect troop quality.
Completed cohorts join the garrison and appear as distinct sword, bow or mounted
formations in the barracks yard. Overflow follows the campaign's existing force
capacity rules rather than silently exceeding the garrison limit.

Practice uses copies and leaves the campaign unchanged. A prepared real siege
instead offers **Defend current siege**, or **Roma awaits defence** on the
campaign map. It waits for the player and applies the resulting losses,
experience and capture through the ordinary siege aftermath exactly once.
Other settlements and field battles retain their existing resolution.

**Save battle** pauses and saves the complete fight. Leaving the battle view
pauses it; reopening allows Resume. Moving to the map cannot leave an unseen
fight running. City and map Save/Load use the same campaign slot. Returning to
the main menu saves that session; a failed save keeps it open. A completed
defeat report remains accessible after Roma changes hands, and the surviving
campaign can continue. Live campaign assaults cannot be discarded
to erase losses. Practice can be ended at any time.

## Runtime and deterministic protocol

`CityBattleHost` is a runtime scheduler outside `src/core` and outside the scene
tree. Its worker submits fixed 100 ms ticks and serializes commands, saves and
snapshots under one mutex. It does not run catch-up bursts after suspension.
The main thread renders detached snapshots. It never moves authoritative troops,
resolves damage or advances RNG in a frame, animation, timer or draw callback.
Closing, loading, switching views or exiting joins the worker before
civic/campaign state is read.
The modal battle view disables other campaign simulation commands.

`CityBattleSim` is a scene-free deterministic engine. Integer centimetre
positions, health, paths, cooldowns, morale, orders, gate and objective clocks
persist. Movement uses a grid derived from the same authored streets, footprints
and wall opening as the city. Damage is gathered against one pre-tick state and
then applied simultaneously. The UI interpolates the resulting positions,
animates marching/melee and draws cosmetic arrow volleys. Picking follows the
same interpolated positions as drawing. Hidden enemy rosters never select a
model; an observed enemy's tactical role may become visible.

| Game command | Contract |
|---|---|
| `city_battle_begin(region, practice)` | Validate ownership/siege and snapshot forces. |
| `city_battle_status(region)` | Return a detached read-only report. |
| `city_battle_command(region, ids, action, position, target)` | Validate a whole batch before changing any cohort's order. |
| `city_battle_order(region, id, node)` | Compatibility command for authored landmarks. |
| `city_battle_start(region)` | End deployment and enable continuous play. |
| `city_battle_control(region, action)` | Pause, resume or change playback speed. |
| `city_battle_step(region)` | Internal deterministic quantum for the runtime worker, replay and tests. |
| `city_battle_close(region)` | Clear an eligible practice, completed or stale session. |
| `city_campaign_enter(region)` | Activate local civic work in the shared seasonal campaign, idempotently. |
| `city_campaign_status(region)` | Read detached dates, stocks, history and interruption reasons. |
| `city_campaign_advance(region, seasons)` | Request bounded ordinary campaign seasons; repeat interruption checks before further advancement. |

The shared `BattleResolver.side_estimate` prices troop quality and campaign
modifiers; the tactical role matrix supplies the requested counter cycle.
`CityBattleResolver` returns the fought outcome through `SiegeRules.assault`.
There is no second casualty roll. Existing campaign character/occupation
consequences retain their usual saved RNG. Practice consumes none.

Save changes are additive. Compatible older landmark battles migrate into
paused spatial sessions without restoring casualties or altering the campaign
source. Malformed records reject at the save boundary. Changed source troops
or layouts are refused and can be safely discarded through the stale-session
recovery flow.

The additive `city_campaign` save record stores activation and dated history.
Older saves remain inactive until the city is entered. Repeated view changes
never reset the history or duplicate work, and loading replaces the shared
state dictionary rather than constructing a second campaign.

All tuning lives in `balance.city_battle.realtime`; spatial authoring lives in
`roma_city.battle.spatial`. JSON schemas and cross-reference validation cover
roles, profiles, the counter cycle and shared gate/objective coordinates.
Seasonal civic work, batch limits and history retention live in
`balance.city_campaign`.

## Verification and scope

Run data validation, fresh Godot import and the complete test suite, inspecting
stderr as well as exit codes. Focused suites are `city_battle`,
`city_battle_realtime`, `city_battle_campaign`, `city_battle_interception` and
`city_battle_ui`, `city_campaign`, `roma_session`, `app_modes` and `city_view`.
They cover spatial orders, full army spawns, counters in actual
duels, fire/charge, pause without UI frames, recruitment, save replay and campaign
commit. `tools/city_battle_playtest.gd` exercises rendered mouse input and a full
continuous fight. `tools/roma_campaign_playtest.gd` checks rendered city/map
roundtrips, actual recruitment and calendar controls, shared saves, live
marquee and camera gestures, suspended battles and real siege aftermath.
`tools/map_playtest.gd` checks planning, marching, arrival and
maximum zoom. QA images remain outside the repository.

Roma is the complete playable reference surface for this model. The simulation
is at formation level, with procedural representative soldiers; it does not
claim individual-soldier physics or surveyed historical reconstruction. Multiple
breaches, siege towers, multiplayer and tactical layouts for other cities are
outside this implementation. See the [current review](reviews/2026-09-roma-unified-campaign.md)
for verification results and the local build location.


## Fortress preparation and siege equipment

Use **Inspect defenses** during peacetime to examine the south gate, curtain wall
and barracks. **Reinforce the south gate** adds 80 integrity after four civic work
days; **Prepare incendiary arrows** unlocks fire-arrow orders after three. Both
are paid works with recurring maintenance and civic effects. Work waits during a
siege, and unfinished projects grant no protection.

New battles contain a crewed battering ram. Deploy archers near the inside of the
south gate, select **Target siege ram**, then **Use fire arrows** if prepared.
Repeated volleys ignite the timber; burning consumes real equipment health and
stops its gate strikes when destroyed. Infantry can still batter the gate slowly.
Arrow trails, smoke, charred timber, hit reactions and fallen representatives are
presentation of deterministic ticks. Pausing freezes in-flight effects.

Older in-progress battles resume their original equipment model. Start a new
practice siege to see the ram. The [fortress review](reviews/2026-09-roma-fortress.md)
records validation, the local Mac build and remaining visual limitations.

## Specialist formations and close combat

New Roma battles include mounted general guards, veteran assault abilities and
braced elite spears. Select a specialist to see its named ability, timer and
effects; abilities can be ordered while paused. General rally protects nearby
unobstructed allies without healing them. Enemy specialists follow the same
rules. Ordinary attacks now drive articulated front-rank thrusts, cuts, shield
reactions and falling casualties, with distinct mounted escorts and veteran kit.

Roma's barracks can recruit one paid **Commander’s Mounted Escort** per faction
while an eligible general is present. This uses the real treasury, population,
training queue and upkeep. Existing active battles retain their former rules;
start a new practice to enable specialties. See
[the swordplay review](reviews/2026-09-roma-swordplay.md) for tuning, limits and QA.
