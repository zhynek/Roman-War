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
Mediterranean, in Godot 4.4 / GDScript. The campaign engine is data-driven: 16
JSON tables under `data/` validated by `schemas/`, with a thin deterministic
rules engine in `src/core/`. Battles resolve behind a swappable
`BattleResolver` interface.

**Built:** Phases 0–4 (map & turns, settlements & economy, armies & sieges at
foundation depth, the full character/family layer), the Phase 7 senate
foundation loop, a playable Phase 8 campaign UI, and **the day at court** — the
turn journal, the fog-filtered end-turn sequence and the Daily Dispatch, with a
bounded AI so the day has something to show (`docs/DESIGN.md` §2.3.1–2.3.2).

**Green:** 93 tests / 0 failures, validator 0 errors / 0 warnings, clean boot.
Branch `claude/daily-campaign-turn-sequence-8mq71d`.

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
> the suite look like it is hanging. It cost time twice in one session. CI does
> this step explicitly for the same reason.

Then the three commands that must stay green:

```sh
python3 tools/validate_data.py                                   # 0 errors, 0 warnings
godot --headless --path . --script res://tests/run_tests.gd      # 93 tests, 0 failures (~40s)
godot --headless --path . --quit-after 5                         # clean boot, no output = good
```

`pip install jsonschema` if the validator complains about the import.

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

## 4. Two determinism traps not in CLAUDE.md

1. **Sort keys in any loop that can steer an RNG draw.** A JSON round-trip
   reorders dictionaries, so an unsorted iteration makes a loaded save diverge
   from the live game. This shipped as a real bug once and the save round-trip
   test caught it only after the RNG fix below.
2. **`state.rng_state` is a decimal *string*, not an int.** JSON numbers are
   float64 and silently round a 64-bit RNG state to a multiple of ~1024,
   producing a different random stream after loading.

## 5. Three ways forward

The user has not committed to a direction. Each is self-contained; pick one and
paste its prompt.

### Phase 6 — AI opponents, properly
`src/core/rules/ai.gd` now marches, besieges, storms and declares war, and the
map does change hands (`tests/test_ai.gd` proves it over forty turns). What it
still does not do is listed in its own docstring: economic planning beyond
cheapest-first, negotiation, naval and fleet behaviour, agents, coordinated
multi-army operations, defensive stacking, and any plan longer than one turn.
The difficulty multipliers are read but only for income and order
(`balance.json → ai.difficulty_income_multiplier`, `ai.difficulty_order_bonus`).

> Take `AiRules` from bounded to real: split it into economy / expansion / war /
> defence behaviours that hold a plan across turns, wire the difficulty
> constants into aggression as well as income, and verify with a long headless
> campaign that a strong faction actually snowballs.

### Phase 5 — Agents & diplomacy
`DiplomacyRules` currently offers only symmetric stances and war declaration;
the UI sets a stance directly and the other side simply accepts. The
`personal_security` and `agent_skill` ancillary effects are authored in the data
and have **no engine reader** — they exist for this phase.

> Build Phase 5: diplomats, spies and assassins as campaign agents, plus a real
> negotiation model (offers, tribute, region deals, bribery) and an AI attitude
> model, replacing the direct set-a-stance panel.

### Phase 8 — Balance & polish
Driven by whatever the playtest surfaced.

> Here is what felt wrong when I played: <notes>. Tune the balance constants and
> UI accordingly.

If the user reports a problem, **ask for the world seed** — the same seed
reproduces their exact campaign, which makes any bug directly debuggable.

## 5b. Three traps the Dispatch work added

1. **`data/dispatch.json` and `TurnJournal.KINDS` are checked against each other
   in both directions** by `tools/validate_data.py`. Add a beat kind without its
   prose (or leave prose behind after removing a kind) and the validator fails.
   That is deliberate — it is what keeps content out of GDScript.
2. **The interface font is Open Sans and has no Miscellaneous Symbols block.**
   The obvious icon characters (⚔ ★ ✦ ▲) render as empty boxes. Every mark in
   `DispatchFormat.ICON_MARKS` is checked against the real font by
   `test_dispatch.gd :: test_every_icon_actually_renders` — run it before
   trusting a new icon.
3. **`CampaignScreen.playback_enabled` is the seam** that keeps `_end_turn()`
   synchronously completable. The headless suite drives twenty-five turns in a
   loop with no frames; leave playback on there and the second call is refused
   because the first day is still on screen.

## 6. Known gaps (verified, not guesses)

- **Starting families are adult men only**: 20 leaders, 19 heirs, 32 family, and
  **no spouses, no children, no `gender` field set** in `campaign.json`. The
  marriage path only opens once in-game births produce daughters, so the family
  tree bootstraps slowly. Seeding real households would fix it.
- **Sea-zone anchor positions** in `regions.json` are unused — `map_view.gd`
  draws sea lanes from shared-zone membership and never renders zone labels.
- **`office_gained` triggers are dead** until Phase 7 offices exist. The
  validator knows: `FORWARD_TRIGGERS` in `tools/validate_data.py` allowlists
  them, and warns about any *other* trigger kind no engine call site fires.
- **Three mission kinds are still forward content**: `blockade_port` needs port
  blockades (Phase 3 remainder), `assassinate_leader` and `leader_suicide` need
  agents (Phase 5). `SenateRules.LIVE_KINDS` names what is actually judged, and
  `FORWARD_MISSION_KINDS` in the validator allowlists the rest — anything in
  neither list is an error.
- **Phase 3 remainder**: embark-on-fleet transport (sea movement is an
  abstracted crossing today), naval battles, port blockades, forts and
  watchtowers, ambush.
- **Art is placeholder** — coloured circles on a geographic map.

## 7. Process notes

- **Git identity must be `noreply@anthropic.com` / `Claude`** before committing,
  or a stop hook flags the commits as unverified and they need re-authoring.
  Develop on `claude/daily-campaign-turn-sequence-8mq71d`.
- **Run adversarial review agents after building anything substantial.** Three
  reviewers (engine correctness, UI behaviour, data/doc fidelity) found **37 real
  issues** the 60-strong test suite had missed — including armies declaring war
  by accident on the first turn, a save-determinism break, movement traits that
  silently did nothing, and generals still governing cities they had marched away
  from. Give each reviewer the research report plus a specific lens, tell them to
  run the suite themselves, and require findings-only output.
- When adding a rules module, add tests to `tests/` **and** cross-reference
  checks to `tools/validate_data.py` if it introduces a data table. Both gates
  must pass before committing.
