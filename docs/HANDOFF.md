# Handoff — picking up Roman War in a fresh session

Everything an assistant (or a human) needs to be productive here within five
minutes. This deliberately does **not** repeat what the other docs cover:

| For | Read |
|---|---|
| Architecture rules, conventions, clean-room policy | [`CLAUDE.md`](../CLAUDE.md) (auto-loaded by Claude Code) |
| What every system does and the phase-by-phase status table | [`docs/DESIGN.md`](DESIGN.md) — §11 is authoritative |
| What the game is like to play | [`PLAYING.md`](../PLAYING.md) |
| How to produce a downloadable app | [`BUILDING.md`](../BUILDING.md) |
| Why the design is what it is | [`docs/research/rtw-research-report.md`](research/rtw-research-report.md) |

## 1. Where things stand

An original clean-room turn-based grand-strategy game of the 270 BC
Mediterranean, in Godot 4.4 / GDScript. The campaign engine is data-driven: 18
JSON tables under `data/` validated by `schemas/`, with a thin deterministic
rules engine in `src/core/`. Battles resolve behind a swappable
`BattleResolver` interface.

**Built:** Phases 0–4 (map & turns, settlements & economy, armies & sieges at
foundation depth, the full character/family layer), the Phase 7 senate
foundation loop, a playable Phase 8 campaign UI, and **Phase 9 — the societal
layer**, which is now the core of the game: eight slow stocks with memory, a
real trade-off on all 81 building chains, and crises that name the historical
mechanism they illustrate. Read `docs/DESIGN.md` §4 before touching any of it.

**Green as of commit `1b088d3`:** 108 tests / 0 failures, validator 0 errors /
0 warnings, clean boot. Branch `claude/game-decision-tradeoffs-pnixzs`, working
tree clean, everything pushed. A Mac build of an earlier state was delivered to
the user, who is playtesting.

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
godot --headless --path . --script res://tests/run_tests.gd      # 69 tests, 0 failures (~10s)
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
3. **Quantize any continuous float you put in the state.** Godot's `JSON.stringify` does
   not round-trip an arbitrary double, so a loaded save drifts from the live game in the
   last digits and then diverges. `SocietyRules.quantize()` rounds onto a four-decimal grid
   — verified against 200k random values. `snappedf()` is **not** equivalent: it can land
   on a double adjacent to the grid point, which prints and re-parses as a different
   number. Symptom: `test_save_round_trip` fails after ~40 turns but passes after 4.
4. **Nothing in `SocietyRules` or `LegibilityRules` may draw from the RNG.** The UI calls
   those queries arbitrarily often; one draw would make a save replay differently. There is
   a test that asserts `state.rng_state` is untouched by every query.

## 5. Three ways forward

The user has not committed to a direction. Each is self-contained; pick one and
paste its prompt.

### Phase 6 — AI opponents
The world currently feels empty: `src/core/rules/ai_stub.gd` is **33 lines** of
passive settlement management. Nothing expands, declares war, or defends. The
difficulty multipliers already exist and are already read
(`balance.json → ai.difficulty_income_multiplier`, `ai.difficulty_order_bonus`).

> Build Phase 6: replace the passive `AiStub` with real modular AI behaviours —
> economy, expansion, war, and defence — so factions actually play the game.
> Keep it deterministic and data-tunable, wire the existing difficulty
> constants, and verify with a long headless campaign that the map changes hands.

### Phase 5 — Agents & diplomacy
`DiplomacyRules` currently offers only symmetric stances and war declaration;
the UI sets a stance directly and the other side simply accepts. The
`personal_security` and `agent_skill` ancillary effects are authored in the data
and have **no engine reader** — they exist for this phase.

> Build Phase 5: diplomats, spies and assassins as campaign agents, plus a real
> negotiation model (offers, tribute, region deals, bribery) and an AI attitude
> model, replacing the direct set-a-stance panel.

### Phase 9 depth — a fast lever for the player

The societal stocks move on 20-to-90-turn constants, which is the point, but it leaves the
player with no way to *act* on a province in the year they notice the problem. Everything
they can do (build, demolish, retax) is itself slow.

> Add provincial edicts: a small `data/edicts.json` table, one standing order per
> settlement (a grain dole, a census, martial law, a labour levy, manumission), each
> trading one societal stock against another on a timescale of a few turns. Keep the
> engine thin — the edict supplies effect values the existing flows already read.

### Phase 8 — Balance & polish
Driven by whatever the playtest surfaced. The societal constants in
`data/balance.json → society` are the newest and least playtested numbers in the file.

> Here is what felt wrong when I played: <notes>. Tune the balance constants and
> UI accordingly.

If the user reports a problem, **ask for the world seed** — the same seed
reproduces their exact campaign, which makes any bug directly debuggable.

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
- **Phase 3 remainder**: embark-on-fleet transport (sea movement is an
  abstracted crossing today), naval battles, port blockades, forts and
  watchtowers, ambush.
- **Art is placeholder** — coloured circles on a geographic map.

## 7. Process notes

- **Git identity must be `noreply@anthropic.com` / `Claude`** before committing,
  or a stop hook flags the commits as unverified and they need re-authoring.
  Develop on `claude/new-session-3g3s4m`.
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
