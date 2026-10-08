<!-- Copied from zach-hynek/digital-command-center docs/testing-policy.md. Edit there, then recopy here. -->

# Testing policy: build it right, verify once, test weekly

This rule applies to every coding agent session (Claude Code and Codex) in every one of Zach's repos.
It started on 2026-10-08 as an experiment. Source of truth: `docs/testing-policy.md` in
`zach-hynek/digital-command-center`. The weekly review is run from the Isengard command center.

## 1. During a dev cycle

1. Do not write new unit tests, integration tests, or end-to-end tests.
2. Do not run the existing test suite. Not before a commit, not after a push, not "to be safe".
3. Do not poll or wait on CI checks after a push. Report the push and stop.
4. Spend the saved effort before you write code. Read the code you will change. Trace its callers.
   Plan the change. Get it right the first time.
5. Verify the change once, directly, with the fastest check that proves this one change works:
   - typecheck or compile the files you changed (for example `tsc --noEmit`, `python -m py_compile`, `swift build`);
   - run the changed command, function, or page once by hand and show the real output;
   - for a UI change, load the page once and look at it.
   One pass. If it passes, stop. Do not add a test to "lock it in".
6. In your handoff write one line in this form:
   `Verified by: <what you ran>. Tests: not run (weekly review policy).`
   Never say tests passed if you did not run them.
7. If a repo's own CLAUDE.md or AGENTS.md says "run the tests before handing off", this rule wins.
   Say in the handoff that you skipped them under the weekly review policy.

## 2. Exceptions

Run or write a test only when one of these is true:

- Zach asks for tests in this session.
- You are fixing a bug that already escaped once. Write one failing test that reproduces it, make it pass, stop.
- The change touches money, authentication, credential handling, data deletion, or a database migration.
- You are the weekly review agent (section 3).

## 3. Weekly review

- Each repo gets one GitHub Actions workflow, `.github/workflows/weekly-tests.yml`. It runs the full suite
  once a week and when started by hand. It does not run on push or on pull requests.
- The Isengard command center shows the result on the project's canvas under recent workflow checks.
- A red weekly run becomes one assignment in the command center: **Start work → "Weekly test review"**.
- The weekly review agent reads the week's commits, runs the full suite, fixes what broke, writes tests only
  for that week's changes where a test adds real protection, and opens one pull request. Zach reviews it.
- The agent writes the result as a report. Nothing is accepted automatically.

--- project-doc ---

# Roman War — guidance for every coding agent

Read `CLAUDE.md` before editing: it is the shared architecture contract, not
Claude-specific advice. Preserve its deterministic, scene-free engine,
data/schema conventions, additive saves, BattleResolver seam, and original
procedural art policy. Do not maintain a competing set of rules here.

Then read `docs/HANDOFF.md` and `docs/reviews/2026-09-map-experience.md`.
Start from the current `origin/main`; historical Claude branches contain
superseded implementations. Check the worktree before switching or editing.

For map work, validate all three surfaces:

1. Data: `python3 tools/validate_data.py` (requires `jsonschema`).
2. Godot import, then the complete suite:
   `godot --headless --path . --import` and
   `godot --headless --path . --script res://tests/run_tests.gd`.
   Check stderr as well as the exit code: Godot can report script errors
   without returning a failing process status.
3. Actual rendering: `godot --path . --script res://tools/map_playtest.gd`.
   Inspect planning, marching, arrival and maximum-zoom screenshots. Keep QA
   images outside the repository; they are not game assets.

During development, target related suites with
`-- suite=map_orders,map_experience,ui_forces,ui_smoke,pathfinding` after the
test runner command. The full suite remains the release gate.

All animation is presentation. Never move a force, spend movement, resolve
combat, or advance RNG in a tween, timer, drawing callback, or UI frame.
Keep visual picking attached to the same positions used by drawing. Never
render an enemy's hidden roster to make its miniature more specific.
