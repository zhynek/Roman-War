# The stores at dawn — playable village defense · local 0.13.0

This records the retained 0.13 baseline and unadopted warfare behavior. For the
explicitly adopted 0.14 tactical, fortification, recurring-threat and aftermath
extension, see [WARFARE.md](WARFARE.md) and
[the current controls guide](WARFARE-CONTROLS.md).

Open **New village**, then **Defend the village** in the top command bar. An
existing saved village uses its current residents, terrain, buildings, projects,
resources and equipment. The dated reference scene remains a separate view.
The encounter is fictional gameplay, not evidence for an attack on Neolithic
Yenikapı. Wooden watch kits retain the existing hypothetical preparedness basis;
no bows, metal weapons, Roman units or historical military organization are added.

## Prepare and play

The introduction names available home-watch adults and quotes mobilization
rations, kits, readiness and maintained watch facilities. Mobilization explicitly
adopts the battle extension. Opening this screen adopts nothing. Older chapters
must first explicitly adopt Asset governance → Land planning → Living village
through the existing management screens.

Use **Prepare material each season**, **Commission watch shelter**, then
**Commission wooden kits**. The controls use the same public seasonal commands,
prices, finite labor, prerequisites and project queue as Village. Resolve seasons
to finish paid work; toggle watch training when kits are ready. Read the forecast
and manage food/care in Village when needed. The preparation screen is a shortcut
to these existing systems, not a separate economy or a grant of soldiers.

Only adults assigned to ordinary home watch or watch practice can mobilize.
Travelers, escorts, care, civic and project workers remain committed. The ordinary
two-adult watch forms two individually selectable groups; larger watches form
pairs, up to eight defenders. Members retain their names and household identity.
Children and civilian households never become combat groups. A prepared first
encounter is substantially easier than sending an unequipped watch.

**Practice on a copy** uses the same actual village and watch. It never changes
ongoing stocks, extensions, residents, orders or saves. Saving is disabled inside
practice. Return from its report to recover the exact continuing village.

During deployment the encounter is paused. Choose defenders, right-click clear
ground to position them, and use Face to orient them. Buildings and obstacles are
excluded by a conservative grid sampled from the actual current village surface,
including current project presentation. The named objective rings mark the
stores, approaches and refuge. Deployment is limited to the village side of the
approach. **Begin encounter** starts the independent fixed-tick worker.

| Control | Action |
|---|---|
| Left click / left drag | Select one group / rectangle of groups |
| Shift + selection | Add groups |
| Ctrl+A / Select all | Select available defenders |
| M, then right-click | Move; does not stop to attack |
| T, then right-click observed enemy | Pursue and attack that group |
| A, then right-click ground | Advance, engage nearby enemies, then continue |
| H | Hold current position and fight in reach |
| D, then right-click / named place button | Defend a position with a limited pursuit radius |
| R, then right-click | Withdraw to that location and leave combat on arrival |
| F, then right-click | Face toward that point |
| Withdraw everyone | Send all available groups to the refuge |
| Space / Pause | Pause or resume; orders work while paused |
| Speed | Toggle normal and twice-normal simulation speed |
| 0 / V | Overhead / close view of the selected group |
| Wheel / middle drag | Camera zoom / pan, independent of orders |
| Save battle / Resume saved battle | Atomic independent village save; saved fight is paused |

Strength, morale and current orders appear in the side panel. Procedural figures,
health bars, selection rings, facing marks, destination lines, staff motions,
impact flashes, falls and retreat motion derive from detached battle snapshots.
Picking uses exactly the drawn anchors. Enemy figures remain hidden until seen;
their models use a generic observed raider appearance, never private kit data.

## Outcomes and recovery

The raiders move toward the actual shared store and react to nearby defenders.
They withdraw when morale fails. Equipment, training, frontal holding, rear
exposure, range and positioning affect simultaneous damage. Defenders can also
be forced to retreat. Groups are the combat unit; cosmetic limbs never resolve
hits and the simulation uses no RNG.

Victory means the raiders have routed, followed by a short visible retreat.
Defeat means the undefended store was held for 18 simulated seconds, or the watch
can no longer contest it. Reaching a chosen withdrawal destination removes a
group from combat; withdrawing the whole watch concedes supplies. A five-minute
simulation limit and a separate inactivity limit ensure an unreachable fight
ends. A dispersed stalemate protects the remaining supplies but retains injuries.

The report shows why the encounter ended, incapacitated defenders, lost kits,
protected/lost supplies and the rations spent mobilizing. **Accept report &
return** applies the outcome exactly once. Defeat or withdrawal loses up to 24
actual provisions; victory/stalemate adds no food reward. Injuries remove named
participants from the available adult workforce. Two fed seasons with at least
two ordinary care workers return them to work. Existing kit upkeep replaces lost
kits using prepared sets, timber and a repair adult. Reduce optional commitments
and protect food/care if recovery stalls. The preparation screen retains the last
report and names residents still recovering.

This first scenario has incapacitation and recovery rather than permanent battle
deaths. Homes, household history, paid projects, building revisions, contacts,
progression and existing incident timelines are preserved. Only battle rations,
taken supplies, lost equipped kits and temporary adult availability change.
One consequential encounter is available per village; practice remains repeatable.

## Architecture and saves

`defense_rules.gd` is the independent village adapter; the parent's
`BattleResolver` boundary and campaign saves are untouched. `defense_sim.gd`
uses integer centimeters, health, morale, cooldowns and 100 ms ticks.
`defense_navigation.gd` routes on an immutable serialized collision grid.
`defense_adapter.gd` captures that grid from the current village once. Homes are
kept out of the combat surface. `defense_host.gd` adapts Roma's worker/mutex,
serialized-command and detached-snapshot pattern without importing parent rules,
units, map, balance, scenes or save data. No frame, tween, camera or animation
advances battle or seasonal rules.

The additive `defense: {}` key is inactive in older saves. Explicit mobilization
adopts version 1, a semantic profile hash, one active battle, one report and a
resident recovery ledger. Adopted villages use independent save wrapper **9**;
wrappers 1–8 retain their meanings and lifecycle/town profile hashes. Older apps
cannot open an adopted wrapper-9 save. The original independent atomic writer
still validates the temporary file before rename. No reference bookmark or
parent campaign file is read. Saved active encounters retain the navigation,
commands with tick numbers, positions, paths, destinations, facing, health,
morale, cooldowns, objective progress and pending outcome. There is a bounded
2,000-command budget per encounter; exceeding it refuses new commands atomically.

Seasonal advancement and workforce/spending commands refuse while any battle is
unresolved, including an unaccepted report. The worker owns a detached battle;
saving pauses it and copies the snapshot through the ordinary save boundary.
Loading validates the saved navigation against the current village. Closing the
surface pauses and joins the worker before returning to Village. Seasonal changes
remain locked until explicit outcome acceptance, so save/reload cannot
double-commit or bypass reconciliation.

## Scope and verification commands

This is one small, controllable village defense. It has no campaign invasions,
permanent combat deaths, ranged weapons, building destruction, physical weapon
collision, individual-agent crowd avoidance, sound, or arbitrary encounter editor.
A conservative one-meter grid may refuse a narrow passage walkable by a single
civilian. Groups can overlap each other; building clearance is conservative.
First navigation capture and large existing village rebuilds can briefly pause
the interface. There is no claim of Intel performance testing.

From the independent experience directory, with Godot 4.4.1 and `jsonschema`:

```sh
python3 tools/validate_defense.py
python3 tools/test_defense_data.py
godot --headless --path . --import
godot --headless --path . --script res://tools/defense_checks.gd
godot --path . --max-fps 30 --script res://tools/defense_preview.gd -- out_dir=/tmp/village-defense-render
```

Run every retained village data/rule/geometry gate as well as parent data,
import, complete suite and `tools/map_playtest.gd`. Check stderr, not only exit
status. QA screenshots and isolated saves belong outside the repository.
Delivery results and launch paths are in `../VERIFICATION-DEFENSE.md`.

## City-progression audit integration — October 2026

The original defense profile remains wrapper 9. Explicit warfare adoption selects
wrapper 10; loading an old profile does not opt in. City lifecycle is optional:
Living village and its prerequisite household/asset/land chapters supply actual
residents, equipment, ordinary labor and preparation. Town facilities are useful
situational production/recovery investments, not battle prerequisites.

The October integration preserves this baseline and the current warfare loop.
The in-game guide now distinguishes explicit chapter setup, Town support, earned
civic rank, paid preparation and the three command modes. The combined review
uses public-command progression and matched watch/fortification comparisons;
see [WARFARE.md](WARFARE.md) and the dated follow-up in the city audit. No parent
military bridge, permanent combat deaths or later civic tier is introduced.
