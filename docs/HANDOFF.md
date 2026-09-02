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
foundation loop, a playable Phase 8 campaign UI, and the **military strategy
layer**: unit-class counters and per-class terrain/walls in the RNG-free
`BattleResolver.estimate()`, weapon/armour kit from armouries, the casualty and
rout model, garrison quality / levy strain / war mood in public order, and
faction doctrines (`DoctrineRules`, `data/doctrines.json`) with a Reforms scroll,
attack odds preview and battle reports. `docs/MILITARY_STRATEGY.md` is the
player-facing guide; DESIGN §5.5–5.8 the spec.

**Green as of the tip of `claude/military-strategy-gameplay-ecnngs`:** 115
tests / 0 failures, validator 0 errors / 0 warnings, clean boot. A Mac build
of the pre-military-layer game was delivered to the user, who is playtesting;
saves from it load (save version 2 upgrades them, granting the campaign's
starting doctrines).

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

## 4. Determinism traps not in CLAUDE.md

1. **Sort keys in any loop that can steer an RNG draw.** A JSON round-trip
   reorders dictionaries, so an unsorted iteration makes a loaded save diverge
   from the live game. This shipped as a real bug once and the save round-trip
   test caught it only after the RNG fix below.
2. **`state.rng_state` is a decimal *string*, not an int.** JSON numbers are
   float64 and silently round a 64-bit RNG state to a multiple of ~1024,
   producing a different random stream after loading.
3. **Initialise new state fields in `NewGame` *and* `SaveGame.upgrade`, never
   lazily on first read.** The determinism tests compare canonical JSON of a
   live game against a loaded one; a key added lazily lands in a different
   position and the comparison fails even though the numbers agree.
4. **Doctrine lists are kept sorted** (`DoctrineRules.grant`) and every
   doctrine-effect merge iterates sorted ids; `war_record.faced` is written in
   sorted class order. Keep it that way.

## 5. Three ways forward

The user has not committed to a direction. Each is self-contained; pick one and
paste its prompt.

### Phase 6 — AI opponents
The world currently feels empty: `src/core/rules/ai_stub.gd` is a few dozen
lines of passive settlement management plus doctrine adoption. Nothing
expands, declares war, or defends. The difficulty multipliers already exist and
are already read (`balance.json → ai.difficulty_income_multiplier`,
`ai.difficulty_order_bonus`), and `BattleResolver.estimate()` gives an AI the
RNG-free odds of any attack, with the counter matrix telling it what to recruit
against what it has faced (`war_record.faced`).

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

### Phase 8 — Balance & polish
Driven by whatever the playtest surfaced.

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
  watchtowers, ambush. The `ship` class has no matchups (no naval battles yet).
- **Military layer edges**: doctrine `escape_pct`/`pursuit_pct` are side-wide
  (the Parthian shot speeds the whole army's escape, not only horse archers);
  the AI does not yet read `estimate()` or recruit to counter what it has
  faced; the counter matrix and doctrine costs have had no playtest tuning.
- **Art is placeholder** — coloured circles on a geographic map.

## 7. Process notes

- **Git identity must be `noreply@anthropic.com` / `Claude`** before committing,
  or a stop hook flags the commits as unverified and they need re-authoring.
  Develop on `claude/military-strategy-gameplay-ecnngs`.
- **`data/buildings.json` and `data/campaign.json` are plain `indent=2` JSON
  with no trailing newline and unescaped non-ASCII**: `json.dumps(doc, indent=2,
  ensure_ascii=False)` round-trips them byte-for-byte, so scripted edits keep
  diffs small. `balance.json`, `unit_classes.json` and `doctrines.json` end with
  a newline.
- **The unit-class counter matrix** is authored so any pair's two multipliers
  multiply to 0.85–1.15 (validator warns); the net counter is their ratio, and
  `docs/MILITARY_STRATEGY.md` §2 is generated from the data — regenerate its
  tables if you retune.
- **Effect keys must have readers.** The validator fails on any building or
  doctrine effect key not read (as a quoted literal) under `src/core`; add the
  reader before the data, or list the key in `FORWARD_EFFECTS` deliberately.
- **Run adversarial review agents after building anything substantial.** Three
  reviewers (engine correctness, UI behaviour, data/doc fidelity) found **37 real
  issues** the 60-strong test suite had missed — including armies declaring war
  by accident on the first turn, a save-determinism break, movement traits that
  silently did nothing, and generals still governing cities they had marched away
  from. Give each reviewer the research report plus a specific lens, tell them to
  run the suite themselves, and require findings-only output.
- When adding a rules module, add tests to `tests/` **and** cross-reference
  checks to `tools/validate_data.py` if it introduces a data table. Both gates
  must pass before committing. Run `--import` again after any new `class_name`
  (`ArmyRules`, `DoctrineRules`, `ReformsPanel` were the latest).
