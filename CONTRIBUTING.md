# Contributing to Roman War

Thanks for looking. This repository is **publicly readable but not open to
direct changes**: everything lands through a pull request that @zhynek reviews
and merges. That includes pull requests opened by @zhynek. `main` is protected;
nobody pushes to it, and nobody merges their own work.

Please read [`LICENSE`](LICENSE) before contributing — it is a source-available
licence, not an open-source one, and opening a pull request grants the project
the right to use and relicense your contribution.

If you are an AI coding agent, read **[`AGENTS.md`](AGENTS.md)** as well. It is
the single source of truth for the architecture rules, and it is not optional.

## Getting set up

You need two things and nothing else:

- **[Godot 4.4+](https://godotengine.org/download)** — the engine. No addons.
- **Python 3** with `jsonschema` (`pip install jsonschema`) — for the data validator.

```sh
git clone https://github.com/zhynek/Roman-War.git
cd Roman-War

godot --path .                                              # play the campaign
godot --headless --path . --script res://tests/run_tests.gd # run the test suite
python3 tools/validate_data.py                              # validate every data table
```

If Godot reports `"X" is not declared in the current scope` or
`nonexistent function` for something that plainly exists, your `.godot/` class
cache is stale. Re-import:

```sh
godot --headless --path . --import      # or, when truly stuck: rm -rf .godot && retry
```

## The two gates

Every change must pass both, locally, before you open a pull request:

```sh
python3 tools/validate_data.py
godot --headless --path . --script res://tests/run_tests.gd
```

CI runs the same two on every pull request, so a failure here is a failure
there. The pull-request template asks you to state which gates you actually ran
— please answer it truthfully. "I ran it and it passed" and "it should pass"
are different answers and both are acceptable; guessing silently is not.

## What makes a good pull request here

- **One idea.** A bug fix and a balance pass are two pull requests, not one.
- **Content in data, not in code.** New buildings, units, factions, traits,
  events, techniques or edicts belong in `data/*.json` with a matching schema in
  `schemas/` and cross-reference checks in `tools/validate_data.py`. The engine
  in `src/core/` stays a thin rules machine.
- **Constants in `data/balance.json`.** Not scattered through rules modules.
- **New rules come with tests.** `tests/` has one file per system; add to the
  matching one or create a new `test_*.gd` and register it in `run_tests.gd`.
- **Determinism preserved.** `src/core/` is scene-free and deterministic: no
  `Node`, no UI, no wall-clock time, no unseeded randomness. Every draw goes
  through the RNG in the game state, and any loop that can steer a draw sorts
  its keys first. A change that breaks this may look fine for weeks and then
  make every loaded save diverge from the live game.
- **Saves stay compatible.** Adding a state key means touching `NewGame.build`,
  `NewGame.ensure_state_keys`, `tests/fixtures.gd`, every reader (via `.get`),
  *and* every entity-creation site. Miss one and resumed saves silently drift.

`AGENTS.md` has the complete list, including the societal-layer rules, the
building-effect budget, the chronicle contract and the art rules. Read it.

## The clean-room policy — the one rule with no room for judgement

Roman War is inspired by the **mechanics** of classic campaign strategy games.
Mechanics, historical facts, real place names, historical unit types and real
deities are not copyrightable and are used freely — `hastati`, `Latium` and
`Jupiter` are all fine.

**Text, descriptions, data values and assets from any commercial game are not.**
Do not paste them, do not paraphrase them from memory, do not ask a model to
"write it like the original". Every name, description and number in this
repository is original work and must stay that way. If you cannot write
something from scratch, leave it blank and say so in the pull request.

This is the one mistake the project cannot take back, so it outranks being
helpful, being fast, or filling in a blank.

## Two things that are generated, not written

- `data/map_geometry.json` — regenerate with
  `python3 tools/generate_map_geometry.py` (fixed seed, byte-stable) after any
  change to region positions, adjacency or sea-zone anchors in
  `data/regions.json`, and commit the result. Never hand-edit it.
- Map and UI work is invisible to headless CI. Eyeball it:
  `xvfb-run -a godot --path . --script res://tools/screenshot.gd`

## Branches and commits

Branch from the latest `main`. Name branches `<topic>` or `<tool>/<topic>` —
`society-hysteresis-fix`, `claude/senate-seat-rebalance`, `codex/validator-speedup`.

Commit messages here are descriptive sentences, not Conventional Commits.
Match `git log`:

```
Phase 7 review round: the fixes three adversarial reviews asked for
Fix the campaign screen and the day's overlays never filling the window
```

not `fix(senate): review`. Say what changed and why — the diff says how.

If an AI tool did material work on a commit, record it in a trailer
(`Co-Authored-By: ...`). Keep tool and model names out of code comments, data
files and docs; trailers and the pull-request description are where they belong.

## Reporting a bug or proposing an idea

Open an issue — there are templates for both. For anything security-sensitive,
see [`SECURITY.md`](SECURITY.md) and do **not** open a public issue.
