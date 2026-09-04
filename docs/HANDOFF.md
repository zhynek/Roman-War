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
Mediterranean, in Godot 4.4 / GDScript. The campaign engine is data-driven: 18
JSON tables under `data/` validated by `schemas/`, with a thin deterministic
rules engine in `src/core/`. Battles resolve behind a swappable
`BattleResolver` interface.

**Built:** Phases 0–6 (map & turns, settlements & economy, armies & sieges at
foundation depth, the full character/family layer, agents & diplomacy, and
the campaign AI), the Phase 7 senate foundation loop with four mission kinds,
and a playable Phase 8 campaign UI including agent orders, a negotiating
table and an offers scroll.

**Green as of the Phase 6 commit:** 120 tests / 0 failures, validator 0
errors / 0 warnings, clean boot, an 80-turn headless campaign in which the
AI took 30 of 33 independent towns and declared 25 wars (about a third of
them across a treaty, now only ones older than ten seasons), and a save made
mid-campaign with the AI live replayed in step for 20 turns. Branch
`claude/next-roadmap-phase-rjxwas`, everything pushed. A Mac build of the
Phase 4 state was delivered to the user earlier; no build of Phases 5–6 has
been produced yet (see `BUILDING.md`).

**Phase 6 in one paragraph.** `AiStub` is gone. `AiController`
(`src/core/rules/ai/`) runs four behaviours per non-player faction each turn
— diplomacy, economy, military, agents — through exactly the calls the player
uses, steered by `data/ai_personalities.json` (aggression, expansion,
caution, greed, cruelty, diplomacy, espionage, loyalty, max_wars) and
`balance.json → ai`. Decisions are pure functions of the state over sorted
ids; only the battles and agent attempts it starts roll dice. Offers to the
player queue in `state.pending_offers`, are shown in the offers scroll after
end turn, and lapse unanswered at the next end turn. The AI's per-faction
memory lives in `state.factions[fid].ai`. Saves are at version 3.

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
godot --headless --path . --script res://tests/run_tests.gd      # 120 tests, 0 failures (~45s)
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
5. **The AI is dice-free too**, on purpose: every decision is a function of
   the state over sorted ids, so two runs of the same seed play the same and
   `test_ai_turn_is_deterministic` holds. Variety comes from battle rolls
   and personalities, never from `rng` inside `src/core/rules/ai/`.

## 5. Ways forward

Every numbered phase of the roadmap (DESIGN.md §10) now has an engine
behind it; what remains is depth (Phase 7) and polish (Phase 8).

### Phase 7 — Politics depth (the obvious next step)
Senate offices (`office_gained` triggers are still forward-authored and
allowlisted in the validator), the `blockade_port` and `leader_suicide`
mission kinds (need naval blockades / a leader-suicide action), richer event
scripting, `faction_destroyed` obituary events, and the late-game civil war
as a real climax (the AI houses should turn on the player when the Senate
outlaws them; today only the thresholds fire).

> Build Phase 7: senate offices held by family members (elections by
> influence, office traits, the `office_gained` trigger), the punitive
> late-game mission ladder ending in the demand for the patriarch's life,
> port blockades for fleets, and obituary events for destroyed factions.

### Phase 8 — Balance & polish
Driven by playtesting. Things the headless probes showed that a playtest
should confirm or refute:

- **AI treasuries balloon** (hundreds of thousands by 240 BC) even after
  wealth now buys extra field armies; the economy is generous for everyone
  and the AI's spending is capped by garrison targets and one queue slot per
  settlement per turn. Either the income curve or the AI's ambitions need
  tuning (`ai.field_army_gold_per_extra`, `garrison_units_cap`).
- **Submission demands** come every few seasons from any enemy that dwarfs a
  passive player (`ai.submission_demand_strength_ratio`,
  `offer_interval_turns`); a real player fights back, but the cadence may
  still annoy.
- The Phase 5 numbers: a fresh assassin has roughly a 15–25% chance against
  a leader in his capital and 30–40% against a family member at home; a fresh
  spy in an enemy capital is caught about one turn in ten; trade rights are
  cheap for anyone without a border grudge; alliances need common enemies or
  gold. All in `balance.json → agents` and `→ diplomacy`.

If the user reports a problem, **ask for the world seed** — the same seed
reproduces their exact campaign, which makes any bug directly debuggable.

## 6. Known gaps (verified, not guesses)

- **AI armies never take ship.** `AiMilitary.march_toward` walks land paths
  only, so island and overseas targets are never attacked by the AI;
  `MovementRules.sea_move_army` exists for it to use.
- **Allies do not coordinate** and are not called into wars; the AI's wars are
  each its own affair. The AI never negotiates land or tribute — its offers
  are peace, trade, alliance and submission; a gift is added only to sweeten
  a peace, trade or alliance offer to another AI court, never to the player.
- **Acceptance is personality-blind.** `DiplomacyRules.evaluate` never reads
  the personality, so Germania takes trade rights as readily as the Free
  Cities; temperament shows only in what a court offers and when it fights.
  A Phase 8 candidate: weight the evaluation by `diplomacy` and `loyalty`.
- **Roman starts are quiet early.** The houses start allied with their kin,
  Roman kin never war on each other, and their neighbours are independents,
  so a Roman player sees few offers or declarations until the borders reach
  foreign courts (a passive Julii saw none in 60 turns; Macedon saw 15 and 3).
- **Envoy bribery is deterministic** (pay the price, the captain turns) and
  family-led armies can never be bought; the research report's "bribe
  generals" is deliberately not implemented. Captains are not assassination
  targets either (only family members and agents are).
- **Protectorates** are a stance plus an `overlord` field and an income share;
  there is no military access, no dragging vassals into wars, and a vassal can
  declare war on its overlord at will (which simply ends the protectorate) —
  the only way out for a vassal, since it cannot negotiate its release.
- **Foreign agents are always visible** where the fog is lifted; "covert"
  only means they can be caught. Hiding them until a spy of ours shares the
  region would be a small change in `map_view.gd` and `region_panel.gd`.
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
  issues** after Phase 4 that the 60-strong test suite had missed, and the same
  three lenses after Phase 5 found **another 30-odd** the 98-strong suite had
  missed — among them agents acting without limit in a turn, an envoy trained
  to skill 10 by churning treaties, tribute promised and never paid, and a
  bought besieger capturing a city at peace. Give each reviewer the research
  report plus a specific lens, tell them to run the suite themselves, make
  them read-only, and require findings-only output.
- When adding a rules module, add tests to `tests/` **and** cross-reference
  checks to `tools/validate_data.py` if it introduces a data table. Both gates
  must pass before committing.
- **CI can fail without running anything.** The first push of this branch
  showed both jobs failing within three seconds with `runner_id: 0` and no
  steps — GitHub never assigned a runner (an Actions minutes/billing condition
  on the account; six earlier runs hung for six hours each and burned the
  month's quota). That is not a code failure: the two CI commands are exactly
  the validator and test commands above, and both were green locally. Re-run
  the workflow once minutes are available before reading red as a bug.
- JSON tables are rewritten with `json.dump(..., indent=2, ensure_ascii=False)`
  plus a trailing newline; without `ensure_ascii=False` every em dash in the
  descriptions turns into `—` and the diff is unreadable.
