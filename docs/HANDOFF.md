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

**Built: Phases 0–8.** The world plays itself (`AiRules`: economy, defence,
diplomacy with an attitude model, expedition warfare with amphibious sieges);
agents (envoys / informers / hired blades) and a full negotiation model;
the Senate's office ladder, six mission kinds, and civil-war side-picking;
seeded households in every house; a code-built visual identity (`UiTheme`)
over a full-window campaign screen. Remaining headline gaps are listed in §6.

**Also built: the Advisor stack** (`src/ui/advisor/`) — a data-driven guided
opening tutorial (`data/tutorial.json`, replayed end-to-end in CI), an
in-game LLM chat ("the Quaestor": provider-agnostic `LlmClient`, knowledge
pack in `data/advisor.json` with a systems-status ledger for bug-vs-not-built
triage), a Feedback form that files labeled GitHub issues with the world
seed attached (`state.world_seed`, SAVE_VERSION 3), and
`.github/workflows/claude-triage.yml` — issues labeled `in-game` wake
claude-code-action to triage and, for small fixes, open PRs. User-side
setup lives in repo issue #1. Keys/config: `user://advisor.cfg` only.

**Green as of the latest commit on `claude/handoff-repo-familiarization-jgqty6`:**
113 tests / 0 failures, validator 0 errors / 0 warnings, clean boot.

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
godot --headless --path . --script res://tests/run_tests.gd      # 113 tests, 0 failures (~20s)
godot --headless --path . --quit-after 5                         # clean boot, no output = good
```

`pip install jsonschema` if the validator complains about the import.

Two more tools earn their keep:

```sh
# Watch a whole campaign play itself; prints captures, wars, peaces, and a
# world table every 10 turns. The balance workhorse.
godot --headless --path . --script res://tools/sim_campaign.gd -- [seed] [turns] [faction] [difficulty]

# Screenshot the real UI without a desktop (menu, campaign, panels).
xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . \
  --rendering-driver opengl3 --script res://tools/screenshot.gd -- /tmp/shots
```

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
~56 MB. The fix used was to extract the arm64 slice from the Mach-O fat binary
in Python (fat header at offset 0, `cputype 0x0100000c`), overwrite the
executable, re-zip → ~27 MB. **Verify `LC_CODE_SIGNATURE` (cmd `0x1d`) survives
in the thinned slice before shipping**, or the app will not launch.

## 4. Determinism traps (the two in CLAUDE.md, plus what they cost)

1. **Sort keys in any loop that can steer an RNG draw or a decision.** A JSON
   round-trip reorders dictionaries, so an unsorted iteration makes a loaded
   save diverge from the live game. This shipped as a real bug once; the AI
   layer (`ai.gd`, `agents.gd`, `negotiation.gd`, `senate.gd`) is written
   sorted-first everywhere — keep it that way.
2. **`state.rng_state` is a decimal *string*, not an int.** JSON numbers are
   float64 and silently round a 64-bit RNG state to a multiple of ~1024,
   producing a different random stream after loading.
3. `test_ai.gd::test_ai_expands_into_the_world` ends with a save-resume
   lockstep check over the whole AI layer — it is the canary for both traps.

## 5. Hard-won lessons of the overnight build (worth more than the code)

- **`set_anchors_preset` sets anchors only.** The campaign screen spent its
  whole life huddled at minimum size in the window's corner because of it.
  Use `set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)` for
  code-built full-screen layouts, and verify with `tools/screenshot.gd`
  rather than trusting the scene tree.
- **Run the sim after every AI change.** The first AI cut looked correct and
  passed every unit test, yet the world froze at turn 21 — garrisons recruited
  only to their defensive target, so no expedition surplus ever formed again.
  Only `sim_campaign.gd` showed it. Its later runs also caught the dead-faction
  war counter pinning `max_active_wars` forever, and eternal stalemate wars
  (both fixed: dead factions drop out of `war_since`; `war_exhaustion_turns`).
- **Adversarial review workflows keep paying.** Two rounds (three and four
  lenses, every finding adversarially verified) found 12+ real defects the
  100-test suite missed — among them: peace leaving siege lines standing (a
  parked army could starve out a city its faction was at peace with), stale
  governors being killed in absentia by AI assaults, and the AI deadlocking
  forever on hostile single-region islands (fixed with amphibious sieges).
  Pin reviewers to `git show HEAD:` so they read a stable tree.
- **The senate/character notice streams must be split.** Trait/ancillary
  notices lack a `faction` key; routing them into `report["senate"]`
  crashed the UI log. TurnEngine now partitions notice streams by kind.

## 6. Known gaps (verified, not guesses)

- **Naval combat**: fleets scout, blockade (a Phase 7 mission), and carry no
  one — embark-on-fleet transport, ship battles, forts/watchtowers and ambush
  remain the Phase 3 tail.
- **The AI never uses agents** — no AI spies in player towns, no AI
  assassination attempts, no AI-initiated negotiation *with the player*
  (AI↔AI peace works engine-side). The counter-intelligence machinery
  (governors hunting player informers) is live.
- **Battles resolve on paper** (`AutoResolver`); the real-time battle scene
  remains a designed drop-in behind `BattleResolver`.
- **Balance is sim-tuned, not playtest-tuned.** `sim_campaign.gd` shows a
  living, non-degenerate world across seeds and difficulties; whether it is
  *fun* needs human hours. If the user reports a problem, **ask for the world
  seed** — the same seed reproduces their exact campaign.
- **Art is a styled chart** — drawn tokens, named seas, no painted terrain.

## 7. Process notes

- **Git identity must be `noreply@anthropic.com` / `Claude`** before
  committing, or a stop hook flags the commits as unverified.
- Develop on `claude/handoff-repo-familiarization-jgqty6` (all overnight work
  lives there; `claude/new-session-3g3s4m` is the pre-AI history).
- When adding a rules module, add tests to `tests/` **and** validator checks
  to `tools/validate_data.py` if it introduces a data table. Both gates must
  pass before committing. Old saves are invalidated by state-shape changes —
  bump `SaveGame.SAVE_VERSION` when you change the state dict.
