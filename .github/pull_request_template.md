## What this changes

<!-- One or two sentences. What is different after this merges, and why? -->

## Gates

Both must pass before this can be reviewed. Tick only what you actually ran —
"I ran it and it passed" and "I expect it to pass" are different answers, and
the honest one is always the right one.

- [ ] `python3 tools/validate_data.py` — ran it, passed
- [ ] `godot --headless --path . --script res://tests/run_tests.gd` — ran it, passed
- [ ] I could not run the gates locally (say why below, and CI will decide)

<!-- If a gate failed or you skipped it, explain here. -->

## Checklist

- [ ] One coherent idea — this is not a fix and a rebalance in one pull request
- [ ] New content went into `data/*.json`, not hardcoded into GDScript
- [ ] New tunable numbers went into `data/balance.json`
- [ ] New data tables have a schema in `schemas/` and cross-reference checks in `tools/validate_data.py`
- [ ] New rules have tests in `tests/`
- [ ] `src/core/` stayed scene-free and deterministic (no `Node`, no wall-clock, no unseeded randomness)
- [ ] New state keys are back-filled in `NewGame.ensure_state_keys`, added to `tests/fixtures.gd`, read with `.get`, and emitted at **every** creation site
- [ ] `data/map_geometry.json` was regenerated with the tool, not hand-edited (or is untouched)
- [ ] No image, audio or font files added — there are none in this repository and none may be added
- [ ] **Clean-room:** every name, description and value here is original. Nothing was copied, paraphrased or model-generated "in the style of" any commercial game.

## Anything you were unsure about

<!-- Assumptions you made, judgement calls, things a reviewer should look at
     hardest. This section is more useful than a confident empty one — an
     honest "I wasn't sure whether X, so I assumed Y at line 42" saves a
     review round. Delete only if there genuinely was nothing. -->

## How this was made

<!-- Optional but appreciated. Written by hand? With Claude Code, Codex,
     another agent? Which parts? It helps calibrate how closely to read the
     diff. Put tool and model names here, not in code comments. -->
