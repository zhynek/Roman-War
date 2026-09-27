# Roma battles — playable siege protocol

Roma now supports a playable defensive assault on the same district used by
the walkable city. The player deploys the existing garrison, issues formation
orders and explicitly advances combat. A real campaign siege returns its
result through the existing `BattleResolver` boundary; practice provides an
isolated way to try the system with the current troops.

The protocol and public commands are described in
[`CITY_BATTLES.md`](../CITY_BATTLES.md). The earlier
[`Roma city review`](2026-09-roma-city.md) remains the record of civic phase 3.
This work builds on that shared city surface and its original procedural art.

## Playing the reference siege

Choose **Defend Roma** from the city's bottom command bar, then **Practice
siege** or, when available, **Defend current siege**. Practice copies the real
garrison and an authored opposing force. The real option requires the player's
Roma, a standing garrison and a valid hostile besieger whose assault equipment
is ready. An empty garrison keeps the campaign's ordinary resolution path.

Select a defending formation in the roster or on the scene/plan. Clicking a
marked interior position places it during deployment. **Begin assault** ends
deployment; subsequent position orders set a destination along the authored
streets. **Hold position** cancels that formation's movement. **Advance one
step** resolves movement, gate damage, simultaneous combat losses and objective
progress. The world waits for the next command between steps.

Attackers breach the south gate and move toward the Forum. Defenders can hold
the gate street, reinforce an occupied position or fall back to the inner
streets. The Forum must be occupied by a defender to contest it; fire from an
adjacent flank does not count as holding the objective. Eliminating the
attackers or outlasting the assault wins the defence. Losing the garrison or
allowing an uncontested Forum occupation loses it.

The overhead view, selectable formation markers and plan share the existing
city coordinates. **Inspect troops** brings the selected formation closer;
the overview restores the broader battlefield. Visible formation movement is
presentation of an already-resolved step. Picking follows the drawn positions.
Camera inspection, window resizing, model movement and ordinary frames cannot
advance combat or consume campaign randomness. A breach opens both the visible
gate leaves and their presentation collision together.

## Campaign entry and consequences

A ready hostile siege of the player's Roma exposes **Roma awaits defence** on
the campaign screen. Both the AI assault path and the starvation path defer
that decision. The season in which equipment becomes ready finishes; the next
**End Turn** opens Roma instead of silently resolving its defence or advancing
another season. Other settlements retain their existing battle flow.

Actual defenders and attackers retain their strength, experience, weapons and
armour. Strength estimation also reads the existing commanders, military
techniques, societal martial effects and wall context. Deployment therefore
changes contact and losses without replacing the campaign's troop-quality
model.

On a terminal step, `CityBattleResolver` supplies the resolved forces and
result to `SiegeRules.assault`. The existing aftermath updates war records,
chronicle entries and siege cleanup. Surviving victors receive
the normal experience award and cap. An attacker victory uses ordinary
occupation, ownership transfer, character displacement and the AI's occupying
garrison. The battle is committed once; a repeated Step cannot grant another
reward or apply another set of losses. Normal character and occupation
aftermath may consume campaign RNG, but there is no second casualty roll.

A retained defeat report remains accessible after Roma changes owner and does
not block the next campaign season. Returning from the city restores the
campaign screen. Stale sessions remain reachable for safe discard, including
when a changed source owner invalidates their original defence.

## Practice, suspension and saves

Practice uses detached force copies. Its casualties, experience awards and
outcome never alter campaign troops, treasury, ownership, chronicle or RNG.
**End practice** deliberately clears it. **Return to city** and Escape close
only the battle view; the session remains resumable. An unfinished session
pauses other city and campaign simulation commands, so the same troops cannot
be retrained, moved or disbanded while reserved for that fight.

**Save battle** writes to the current mode's existing save slot. Standalone
Roma retains its separate city slot; entry from a campaign uses that campaign's
facade and save path. The additive `city_battles` record stores deployment,
orders, unit strengths, gate integrity, objective progress, outcome and commit
status. Save version remains 2. Older saves receive an empty battle collection.
Malformed nested records are rejected at the save boundary.

Resume uses saved simulation values, independent of the last rendered frame.
Commands recheck the source forces, owner, siege, combat context and authored
layout before proceeding. Changed or missing content and stale force snapshots
produce a recoverable refusal instead of overwriting newer campaign state.

## Data and scope

The street graph is authored in `data/roma_city.json`; battle tuning lives in
`balance.city_battle`, and interface prose in `effects_glossary.city_battle`.
Schema and reference validation check graph connectivity, symmetric links,
valid entries/deployment/objective IDs and routes against the district's house
footprints, fountain and wall openings.

Enemy representatives remain generic procedural models. Hidden unit templates
or equipment do not select their appearance. No image assets or imported
artwork were added.

This is a formation-level prototype on the interpretive Roma district, with
movement along authored street nodes. It does not implement continuous
individual-soldier navigation, freely drawn routes, individual melee animation,
siege towers, multiple breaches or tactical battles in every city. It is not a
surveyed reconstruction of ancient Rome. The wider campaign retains regional
movement, and the civilians remain a presentation population.

## Verification status

| Check | Result |
|---|---|
| Data and import | Validation passed with **0 errors and 0 warnings**; fresh Godot 4.4.1 import passed. |
| Focused battle suites | **30 tests passed**, covering deterministic commands and saves, real victory/loss aftermath, siege interception, UI purity, occupied-node picking, defeat-report return and stale-session recovery. |
| Source and exported-app rendered harnesses | Passed deployment and actual pointer orders, troop inspection, resizing, frame purity, gate breach, save/load/resume, practice isolation and a real campaign defensive result. |
| Campaign map regression | **78 focused map and campaign-entry tests passed**. Rendered planning, marching, arrival and maximum-zoom screenshots inspected; measured median frame time **10.272 ms**, p95 **11.499 ms** in that local run. |
| Universal Mac preview | `build/roma-battles-preview-20260926/`, version **0.16.0-preview.20260926**; package probe, signature and architecture checks passed. |
| Full regression gate | **605 of 606 tests passed**, with no script errors. The sole failure is `test_ai_campaign::test_map_changes_hands`: its existing **600 ms** timing guard measured **1420 ms per turn**. The full gate is not green; the threshold is unchanged. |

The isolated timing comparison ran the same 60-turn, seed-42 Julii campaign
serially on the previous phase 3 source and the current source with the same
Godot 4.4.1 editor binary. Averages were **1436.426 ms** and **1459.273 ms** per
turn respectively. The current exported release averaged **1251.006 ms**.
All three produced the same normalized campaign-state hash after excluding
the new empty `city_battles` collection. Thus the existing timing limit also
fails on unchanged source in this session; it has not been relaxed. These
measurements establish a reproducible baseline comparison, not a diagnosis
of the host's slowdown or a passing performance gate.
The full run was paused outside its timed test for these isolated measurements
and then resumed to completion. Stderr also contains the existing non-equal
Control-anchor warning; it contains no script or engine error diagnostics.

The rendered harness captures the city entry, command briefing, deployment,
gate defenders, close inspection, resized view, approach, breach, practice
outcome and real campaign outcome. Its QA images stay outside the repository.
Source and packaged battle screenshots were inspected at 1280 × 800 and
1600 × 900. The preview's runtime source hashes match the working tree; its
`verification/` directory includes the completed playtest logs, with image
locations recorded in `provenance.json`.
This is a local development preview, with no new production release or tag.

Reproduce the gates with Godot 4.4.1 and Python with `jsonschema`:

```sh
python3 tools/validate_data.py
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd -- suite=city_battle,city_battle_campaign,city_battle_interception,city_battle_ui
godot --headless --path . --script res://tests/run_tests.gd
godot --path . --script res://tools/city_battle_playtest.gd -- out_dir=/tmp/roman-war-city-battle
godot --path . --script res://tools/map_playtest.gd -- out_dir=/tmp/roman-war-map-battle-qa
```

Inspect stderr as well as process status. The required campaign rendering
check covers planning, marching, arrival and maximum zoom. Focused tests and
package checks do not replace the complete regression gate above.
