# Handoff — picking up Roman War in a fresh session

Everything an assistant (or a human) needs to be productive here within five
minutes. This deliberately does **not** repeat what the other docs cover:

| For | Read |
|---|---|
| Architecture rules, conventions, clean-room policy | [`CLAUDE.md`](../CLAUDE.md) (auto-loaded by Claude Code) |
| What every system does and the phase-by-phase status table | [`docs/DESIGN.md`](DESIGN.md) — §10 is authoritative |
| What the game is like to play | [`PLAYING.md`](../PLAYING.md) |
| How to produce a downloadable app | [`BUILDING.md`](../BUILDING.md) |
| Why the design is what it is | [`docs/research/rtw-research-report.md`](research/rtw-research-report.md) |

## 1. Where things stand

An original clean-room turn-based grand-strategy game of the 270 BC
Mediterranean, in Godot 4.4 / GDScript. The campaign engine is data-driven: 17
JSON tables under `data/` validated by `schemas/`, with a thin deterministic
rules engine in `src/core/`. Battles resolve behind a swappable
`BattleResolver` interface.

**Built:** Phases 0–5 (map & turns, settlements & economy, armies & sieges at
foundation depth, the full character/family layer, and agents & diplomacy),
the Phase 7 senate foundation loop with four mission kinds, and a playable
Phase 8 campaign UI including agent orders and a negotiating table.

**Green as of the Phase 5 commit:** 98 tests / 0 failures, validator 0 errors /
0 warnings, clean boot, and a 120-turn headless probe with agents and envoys
active. Branch `claude/next-roadmap-phase-rjxwas`, everything pushed. A Mac
build of the Phase 4 state was delivered to the user earlier; the Phase 5
build has not been produced yet (see `BUILDING.md`).

**Phase 5 in one paragraph.** Agents are state entities
(`state.agents`) with data-driven kinds (`data/agents.json`: envoy, spy,
assassin), trained where the right building stands, walking any border, and
resolved by one skill-vs-difficulty contest shape against a settlement's
counter-intelligence or a character's personal security (`AgentRules`). Spies
watch, open besieged gates and guard their own cities; assassins kill family
members and agents or wreck buildings; envoys carry offers and bribe captains,
brigands and independent towns. `DiplomacyRules` adds an opinion memory,
treachery, war weariness, an attitude breakdown, and a deterministic offer
evaluation returning named factors — the other side accepts exactly when the
balance is not negative, so the scroll weighs an offer before it is made.
Accepted terms move gold, start tribute streams, cede regions peacefully, and
create protectorates that pay their overlord a share of income. Saves are at
version 2; version-1 saves upgrade on load.

## 2. Get productive in five minutes

The container starts with **no Godot installed**. Get it:

```sh
cd /tmp && curl -sSL -o godot.zip \
  https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip
unzip -q godot.zip && chmod +x Godot_v4.4.1-stable_linux.x86_64
```

> **Always run `--import` first — and again after adding any `class_name` file.**
> ```sh
> godot --headless --path . --import
> ```
> This is the single biggest time-waster in this project. A missing or stale
> `.godot/` class cache produces bogus `Identifier "X" not declared in the
> current scope` parse errors on globals that plainly exist, causes test files
> to fail to load *while the runner still prints passes for them*, and can make
> the suite look like it is hanging. CI does this step explicitly for the same
> reason.

Then the three commands that must stay green:

```sh
python3 tools/validate_data.py                                   # 0 errors, 0 warnings
godot --headless --path . --script res://tests/run_tests.gd      # 98 tests, 0 failures (~15s)
godot --headless --path . --quit-after 5                         # clean boot, no output = good
```

`pip install jsonschema` if the validator complains about the import.

A handy way to see a system live: write a small `extends SceneTree` script
with an `_init()` that calls `Game.new_campaign(...)`, drives it, prints, and
`quit(0)`; copy it into the project root, run it with
`godot --headless --path . --script res://probe.gd`, and delete it (and its
`.uid`) afterwards so it is never committed.

## 3. Building a playable app

`BUILDING.md` has the recipe. The four things that are painful to rediscover:

- **Export templates** are a separate ~1.2 GB download
  (`Godot_v4.4.1-stable_export_templates.tpz` from the same release page),
  unzipped into `~/.local/share/godot/export_templates/4.4.1.stable/`.
- **`textures/vram_compression/import_etc2_astc=true`** must stay in
  `project.godot`, or the macOS export dies with a configuration error.
- **macOS architecture must stay `universal`.** The stock template ships only a
  universal binary; an `arm64` export fails with "template binary not found"
  because thinning needs Apple's `lipo`, which does not exist on Linux.
- **Ad-hoc signing is mandatory for Apple Silicon** (`codesign/codesign=1`).
  arm64 macOS refuses to launch a fully unsigned binary outright rather than
  merely warning.

Delivering the build: `SendUserFile` caps at **30 MiB** and the universal zip is
56 MB. The fix used was to extract the arm64 slice from the Mach-O fat binary in
Python (fat header at offset 0, `cputype 0x0100000c`), overwrite the executable,
re-zip → 27 MB. **Verify `LC_CODE_SIGNATURE` (cmd `0x1d`) survives in the thinned
slice before shipping**, or the app will not launch.

## 4. Determinism traps not in CLAUDE.md

1. **Sort keys in any loop that can steer an RNG draw.** A JSON round-trip
   reorders dictionaries, so an unsorted iteration makes a loaded save diverge
   from the live game. This shipped as a real bug once and the save round-trip
   test caught it only after the RNG fix below.
2. **`state.rng_state` is a decimal *string*, not an int.** JSON numbers are
   float64 and silently round a 64-bit RNG state to a multiple of ~1024,
   producing a different random stream after loading.
3. **The campaign RNG now draws at `NewGame`** — starting agents are named from
   the culture pools in campaign order. Anything that changes the number of
   starting agents changes every subsequent draw of a seed.
4. **Offer evaluation is deliberately dice-free.** Do not add randomness to
   `DiplomacyRules.evaluate`: the UI promises "they accept exactly when the
   balance is not negative", and the negotiation tests assert on exact sums.

## 5. Ways forward

The roadmap (DESIGN.md §10) now has Phase 6 as the only untouched phase.

### Phase 6 — AI opponents (the obvious next step)
`src/core/rules/ai_stub.gd` is still passive settlement management: nothing
expands, declares war, defends, sends agents, or makes offers. Everything it
needs now exists: `DiplomacyRules.evaluate/propose` (an AI can build the same
proposal dictionaries the scroll does), `attitude`, `power_ratio`,
`AgentRules` for spies and assassins, and the difficulty multipliers already
read from `balance.json → ai`.

> Build Phase 6: replace the passive `AiStub` with modular AI behaviours —
> economy, expansion, war, defence, diplomacy (offers and responses through
> `DiplomacyRules.propose`), and agents — so factions actually play the game.
> Keep it deterministic and data-tunable (an `ai_personalities.json` with
> per-faction aggression/greed/loyalty weights would fit the architecture),
> wire the existing difficulty constants, and verify with a long headless
> campaign that the map changes hands and treaties are honored or broken
> believably.

### Phase 7 — Politics depth
Senate offices (`office_gained` triggers are still forward-authored and
allowlisted in the validator), the `blockade_port` and `leader_suicide`
mission kinds (need naval blockades / a leader-suicide action), richer event
scripting, `faction_destroyed` obituary events.

### Phase 8 — Balance & polish
Driven by playtesting. The Phase 5 numbers were sanity-checked, not played:
a fresh assassin has roughly a 15–25% chance against a leader in his capital
and 30–40% against a family member at home; a fresh spy in an enemy capital is
caught about one turn in ten; trade rights are cheap for anyone without a
border grudge; alliances need common enemies or gold. All of it is in
`balance.json → agents` and `→ diplomacy`.

If the user reports a problem, **ask for the world seed** — the same seed
reproduces their exact campaign, which makes any bug directly debuggable.

## 6. Known gaps (verified, not guesses)

- **AI factions never initiate diplomacy or use agents.** They evaluate the
  player's offers with the attitude model and their starting spies guard
  their capitals, but nothing more. Phase 6.
- **Envoy bribery is deterministic** (pay the price, the captain turns) and
  family-led armies can never be bought; the research report's "bribe
  generals" is deliberately not implemented.
- **Protectorates** are a stance plus an `overlord` field and an income share;
  there is no military access, no dragging vassals into wars, and a vassal can
  declare war on its overlord at will (which simply ends the protectorate).
- **Alliances carry no obligations** beyond trade and the attitude bonus:
  allies are not called into wars.
- **Starting families are adult men only**: no spouses, no children, no
  `gender` field set in `campaign.json`. The marriage path only opens once
  in-game births produce daughters, so the family tree bootstraps slowly.
- **Sea-zone anchor positions** in `regions.json` are unused — `map_view.gd`
  draws sea lanes from shared-zone membership and never renders zone labels.
- **Phase 3 remainder**: embark-on-fleet transport (sea movement is an
  abstracted crossing today), naval battles, port blockades, forts and
  watchtowers, ambush.
- **Art is placeholder** — coloured circles on a geographic map; agents are
  diamonds.

## 7. Process notes

- **Git identity must be `noreply@anthropic.com` / `Claude`** before committing,
  or a stop hook flags the commits as unverified and they need re-authoring.
- **Run adversarial review agents after building anything substantial.** Three
  reviewers (engine correctness, UI behaviour, data/doc fidelity) found **37 real
  issues** after Phase 4 that the 60-strong test suite had missed, and another
  round after Phase 5 caught what the 98-strong suite missed. Give each
  reviewer the research report plus a specific lens, tell them to run the
  suite themselves, make them read-only, and require findings-only output.
- When adding a rules module, add tests to `tests/` **and** cross-reference
  checks to `tools/validate_data.py` if it introduces a data table. Both gates
  must pass before committing.
- JSON tables are rewritten with `json.dump(..., indent=2, ensure_ascii=False)`
  plus a trailing newline; without `ensure_ascii=False` every em dash in the
  descriptions turns into `—` and the diff is unreadable.
