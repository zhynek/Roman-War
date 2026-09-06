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
