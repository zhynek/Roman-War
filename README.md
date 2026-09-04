# Roman War

An original, clean-room turn-based grand-strategy game of the ancient Mediterranean,
inspired by the *mechanics* (never the assets, text, or data) of classic 2004-era
campaign strategy games. Built with Godot 4 for macOS (and anywhere else Godot runs).

The design philosophy, researched in depth in
[`docs/research/rtw-research-report.md`](docs/research/rtw-research-report.md), is:

1. **Campaign layer first.** The turn-based strategy map — settlements, population,
   public order, economy, armies, characters — is the game. It is built and tested
   before any battle presentation exists.
2. **Everything is data.** Factions, cultures, buildings, temples, units, regions,
   traits, events, wonders, and the campaign start state live in JSON tables under
   [`data/`](data/), validated against JSON Schemas in [`schemas/`](schemas/).
   The engine under [`src/core/`](src/core/) is a thin, deterministic rules machine.
3. **Battles are a swappable module.** The campaign only ever talks to a
   `BattleResolver` interface. Today that is an auto-resolver; a real-time battle
   scene can drop in behind the same interface later without touching campaign code.

## Project layout

```
project.godot        Godot 4.4 project file
data/                All game content as JSON (schema-validated, moddable)
schemas/             JSON Schemas — the contract every data table must satisfy
src/core/            Deterministic campaign simulation (no scene/UI dependencies)
src/core/rules/      One module per system: growth, order, economy, movement, ...
src/core/rules/battle/  BattleResolver interface + auto-resolve implementation
src/ui/              Campaign UI: start menu, map view, settlement/army/agent panels, family scroll, diplomacy table
tests/               Headless GDScript test suite (godot --headless --script)
tools/               validate_data.py — schema + cross-reference validation
docs/                Design document and research report
```

## Running

Requires [Godot 4.4+](https://godotengine.org/download). No other dependencies.

```sh
# Play the campaign
godot --path .

# Run the headless test suite
godot --headless --path . --script res://tests/run_tests.gd

# Validate all data tables against their schemas + cross-reference checks
python3 tools/validate_data.py
```

## Simulation model (short version)

- Two turns per year, 270 BC → AD 14. Each region has exactly one settlement.
- Population growth and public order are **sums of named factor lists** (farms,
  health, taxes, squalor, garrison, culture penalty, distance to capital, ...),
  mirroring the settlement-details breakdown of the genre. All anchor constants
  live in a single tunable file: [`data/balance.json`](data/balance.json).
- Settlements upgrade through village → town → large town → minor city →
  large city → huge city at population thresholds; the government building chain
  gates the upgrade, and barbarian cultures are capped below the top tiers.
- The treasury can go negative; armies cost upkeep every turn; sustained debt
  disbands units.
- The whole `GameState` is a plain dictionary: saving is `JSON.stringify`, and
  every random draw goes through one seeded RNG, so campaigns replay
  deterministically.

## Status

Phases 0–6 of the research report's roadmap are built and tested: campaign
map, turn loop, settlements, economy, recruitment, auto-resolved battles,
sieges, mercenaries, events, victory checks, the full character layer
(traits, retinues, family tree, succession), agents & diplomacy — envoys,
spies and assassins as data-driven campaign agents, and a negotiation model
with an attitude memory whose every offer is weighed as a named factor list —
and campaign AI opponents that tax, build, recruit, expand, declare war,
besiege, defend, negotiate and spy, each with a data-driven personality. A
playable campaign-map UI sits on top: geographic map with fog of war,
settlement/army/agent panels driven by the engine's breakdowns, family scroll,
negotiating table, offers scroll, and save/load. Senate depth and a balancing
pass are the next phases.

## Clean-room policy

Mechanics, historical facts, real place names, historical unit types, and deities
are not copyrightable and are used freely. All names, descriptions, data values,
and (future) art and music in this repository are original work. No assets, text,
or data files from any commercial game are copied. Working title "Roman War".
