# Roman War

An original, clean-room turn-based grand-strategy game of the ancient Mediterranean,
inspired by the *mechanics* (never the assets, text, or data) of classic 2004-era
campaign strategy games. Built with Godot 4 for macOS (and anywhere else Godot runs).

**Play version 0.14.0:** download the universal macOS app from the
[production release](https://github.com/zhynek/Roman-War/releases/tag/v0.14.0).
The campaign now uses procedural 3D terrain, physical crossings and negotiated
map access. See the [release notes](docs/releases/0.14.0.md) and
[next development handoff](docs/NEXT_DEVELOPMENT.md).

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
src/ui/              Campaign UI: start menu, map view, settlement/army/family panels
tests/               Headless GDScript test suite (godot --headless --script)
tools/               validate_data.py (schema + cross-reference validation), soak.gd (balance soaks)
docs/                Design document, military strategy guide, handoff notes, research report
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
- **Every building buys something and costs something.** Under the order and
  growth numbers sits a societal layer of eight slow-moving stocks — Standing,
  Grievance, Belonging, Expectation, Ambition, Martial Spirit, Craft and
  Plunder's Share — with memory that the rest of the engine does not have. Its
  load-bearing rule is one subtraction: whatever a province is asked to bear
  beyond what it consents to has to be *coerced*, and only the coerced share
  charges Grievance. Garrisons raise public order and do not lower the load, so
  a held-down province reads calm while the pressure builds and then goes all at
  once. The same shape runs the other way: provision becomes expectation, so
  withdrawing a bath house leaves a city worse off than never having built one.
  Nothing in the layer is random — the difficulty is delay, hysteresis, coupled
  feedback, and not being able to see a province you have built no road to.
- Because those stocks move over decades, each province can hold one **standing
  edict** — a corn dole, a census, martial law, an amnesty — that acts within a
  few turns and trades one thing for another. It is the player's fast lever, and
  it is shaped like a building you can raise and pull down in a season.
- **Battles are decided by composition, ground and preparation before fortune.**
  Twelve unit classes counter one another on a historically weighted matrix
  (spears and pikes stop cavalry, cavalry rides down infantry and archers,
  missiles shred elephants and chariots), each class has its own ground and
  its own worth at a wall, kit from armouries and drill from barracks travel
  with the men, and the estimator that prices all of it is RNG-free — so the
  game can show the odds before every attack and name the factors that decided
  each battle after it. War flows back into the towns: garrison quality keeps
  order, the levy strains the town that raised it, and a decisive battle is
  felt in every city of both realms.
- The whole `GameState` is a plain dictionary: saving is `JSON.stringify`, and
  every random draw goes through one seeded RNG, so campaigns replay
  deterministically.

## Map experience (0.13)

Click an army or its commander, then click its destination; drag the army for
an immediate route preview. Close view now shows individual commander faces,
authored equipment for all 21 factions, cultural troop formations and mounted
leaders. Cavalry travels and scouts farther than infantry or artillery.
Build watchtowers and fortified posts, inspect visible garrison/wall strength,
and watch recorded enemy movements through your scouts' coverage. Far zoom
retains the territorial view and the deterministic province-based campaign.

Read the [v0.13 review and validation notes](docs/reviews/2026-09-v13-map-overhaul.md),
the [initial codebase review](docs/reviews/2026-09-map-experience.md), and
[map controls](PLAYING.md#commanding-armies-directly-on-the-map-013).

## Status

Phases 0–7 of the research report's roadmap are built and tested: campaign map,
turn loop, settlements, economy, recruitment, auto-resolved battles, sieges
(with amphibious landings), mercenaries, events, victory checks, the full
character layer (traits, retinues, family tree with seeded households,
succession), the societal layer that makes those decisions weigh something, the
agents & diplomacy layer (attitude model with memory, negotiation offers with
tribute and region deals, diplomats/spies/assassins on the map), and a
persona-driven campaign AI that garrisons, builds, raises armies, clears the
independents, declares wars it thinks it can win, and sues for peace when
losing — the world moves without the player.

On top of that sits the Deep Strategy layer (DESIGN.md §12): 37 historical
techniques that spread by contact, conquest and espionage — awareness is
free, institutionalizing costs treasury and years, defeat discounts military
reform (the corvus law), and recruits are armed to their city's standard for
life; nine provincial edicts, one standing order per province, that bite over
a few turns and stop the moment they are revoked while whatever they moved
stays moved (the grain dole that becomes an expectation, martial law that buys
order and spends everything else); and a structured chronicle that writes each campaign's history — wars ledgered
and summarized, reigns summed, generals earning epithets from their deeds —
rendered as prose in an annals scroll and stored as machine-readable data
(the contract for an optional future AI narrator). Every technique, edict
and epithet carries its documented historical basis; ten players end in ten
measurably different worlds, and the soak prints the divergence as a number.

The military strategy layer (DESIGN.md §6.5–6.8, the guide in
[`docs/MILITARY_STRATEGY.md`](docs/MILITARY_STRATEGY.md)) turns investment into
outcomes you can read: the unit-class counter matrix and per-class terrain in an
RNG-free battle estimator, weapon and armour kit from armouries and forges, a
casualty and rout model that punishes the countered and the slow, garrison
quality, levy strain and war mood in public order, and thirty warcraft
techniques — the maniple, the sarissa, the Parthian shot, the Companion wedge —
learned from buildings, resources and the enemies a people has fought, folded
into the same knowledge engine as every other craft.

A playable campaign-map UI covers it all: a procedurally painted terrain map
with fog of war and settlement iconography drawn from the campaign data;
settlement/army/agent panels driven by the engine's factor breakdowns; the
building yard and muster hall with illustrated ladders; a negotiation scroll
with live appraisal; knowledge, edicts, annals and family scrolls; the odds
before every attack and a battle report after it; a guided
campaign trail of objectives that react to the world and pay real rewards, with
explorable points of interest; an animated battle replay; a sequenced end turn
that plays the day out on the map and closes on a Daily Dispatch; and
save/load.

The Senate's politics (DESIGN.md §8.1) close the Roman houses' arc: six
magistracies filled by summer election, offices that reach a man's attributes
and soak up his house's ambition, the Senate's demand for a patriarch's life
when a house grows too great, and a civil war in which the other houses pick
sides, that no envoy can end, and that ends only when the Senate falls. Naval
combat and a real-time battle scene are the next phases; their data tables and
state hooks already exist.

## Clean-room policy

Mechanics, historical facts, real place names, historical unit types, and deities
are not copyrightable and are used freely. All names, descriptions, data values,
and (future) art and music in this repository are original work. No assets, text,
or data files from any commercial game are copied. Working title "Roman War".
