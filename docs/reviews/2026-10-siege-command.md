# Interactive siege commands — October 2026

Started from clean, fetched `origin/main` at `7e1776b` on
`codex/battle-command`. The existing continuous battle worker, shared campaign
and BattleResolver seam are preserved. No step button or frame-driven gameplay
was introduced.

## Playable changes

The Roma command panel now exposes battle line, march column, trained phalanx,
face direction, split into three platoons and select battalion. Right-dragging
previews separate positions and an orientation; the active Move, Fall back or
Attack move mode determines how troops reach their frontage. Regular right-click
orders, marquee selection, pause, speed, ranged fire, siege targeting and existing
specialist abilities remain available.

Formation changes cost simulated time. Phalanx frontage, slow turning, frontal
protection and off-front weakness make cavalry attacks from behind meaningful.
The engine accumulates damage against pre-tick facing and health; rendering
only interpolates the detached results. Rank spacing and spear geometry are
procedural. Only observed enemy role/formation information affects their models.

Platoon splitting conserves integer health, source capacity and cooldowns. It
cannot multiply the parent's damage budget. Morale uses the surviving proportion
of each platoon, and the campaign resolver recombines source units in their
original order, with one experience outcome and no extra unit slots. A new
optional battle extension keeps old active saves on their original mechanics.
Malformed extensions reject at the save boundary.

A supplied **Formation command drill** makes the feature immediately accessible
with trained hoplites, cavalry and archers. It requires ownership of Roma but no
garrison; it creates no campaign troops, money, losses or rewards.

## Historical basis and limits

[Polybius, Histories 18.28–32](https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Polybius/18*.html)
describes the Macedonian phalanx's strong front, need for suitable ground, and
vulnerability when its formation is disrupted or attacked from flank/rear. This
is a source for the broad positional tradeoff, not a claim that hoplite and
Macedonian pike formations were identical. The experience gate, numerical bonuses,
turn speeds and three-second transition are original game tuning. “Battalion”
and “platoon” are player command scales, not reconstructed ancient unit titles.

Combat remains at formation level with representative models, rather than
individual weapon collision or a physical crowd simulation. Phalanx clearance
checks the center and lateral frontage against authored terrain; it is not a
full swept rectangular footprint. The street graph remains the navigation basis.
Enemy spears use deterministic route-clearance fallback, not a general-purpose
formation-aware path planner. Unformed formations can still overlap visually in
crowded deployments. Other city/field battles retain their previous resolver,
and the player still commands the defending side in Roma.

## Review and regression coverage

Three requested adversarial reviews covered determinism/saves, data/privacy/UI,
and balance/exploits/AI. Confirmed findings were fixed and covered:

- Mode-aware frontage orders retain Move/Fall back instead of always acquiring enemies.
- Select battalion replaces unrelated selection unless Shift is held.
- Supplied drills remain accessible with an empty garrison.
- Save fields and nested units validate before typed reads or health aggregation.
- Ram volleys defer facing like ordinary attacks, eliminating a verified
  formation-array-order damage difference.
- AI trained spears leave phalanx and continue through narrow streets; a six-second
  reform cooldown prevents repeated shape changes at corners. Paths to unchanged
  targets are retained; safe forward connectors prevent slow troops being
  repeatedly pulled back to the nearest grid cell during pursuit.
- Formation placement and turning reject terrain that cannot fit the frontage.

The tactical tests additionally cover training gates, atomic multi-unit commands,
reform clocks, facing turn limits, actual frontal/rear damage, conserved split
health/damage/cooldowns, exact mid-reform save replay, legacy battles, and real
siege commit-once aggregation. The render harness exercises the actual drill,
split/formation buttons and right-drag input, confirms the background worker
continues during commands, then checks pause and save. It captures deployed
ranks, forming columns and a close phalanx view.

## Reproduction

```sh
python3 tools/validate_data.py
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
# Focused development gate:
godot --headless --path . --script res://tests/run_tests.gd -- suite=city_battle_tactics,city_battle_interactions,city_battle_realtime,city_battle_specialists
# Actual rendered controls and formations:
godot --path . --script res://tools/tactics_playtest.gd -- out_dir=/tmp/roman-war-tactics-final
godot --path . --script res://tools/map_playtest.gd -- out_dir=/tmp/roman-war-tactics-map
```

All QA images and isolated saves remain outside the repository. No image assets
were added. Final validation: **688 tests, 0 failures**, clean Godot import and no script/error
diagnostics. The inherited anchored-control sizing warning remains in the full
headless UI suite. Data validation: **0 errors, 0 warnings**. `git diff --check`
passed. Map planning, marching, arrival and maximum-zoom checks passed, and their
screenshots were inspected under `/tmp/roman-war-tactics-map`.

The universal Mac preview is
`build/roma-tactics-20261003/Roman War Playtest.app`, with the matching ZIP,
frozen source snapshot and provenance alongside it. Version:
`0.21.0-preview.20261003`. All **554** frozen input hashes match the workspace.
The builder passed data validation, import/export, ad-hoc signature checks,
Apple Silicon/Intel architecture checks and the packaged campaign/save probe.
The exact exported app also passed `tools/tactics_playtest.gd`, including live
commands, split troops, frontage dragging, phalanx/column buttons, pause and save.
Its clean log and inspected screenshots are under
`/tmp/roman-war-tactics-packaged`. This is a local development preview, using the
existing separate playtest save identity; no production app/release was replaced.
