# Roma continuous battles — September 27, 2026

## Delivered behaviour

This supersedes the stepped 0.16 battle prototype with continuous spatial
combat on Roma's existing city surface. Deployment accepts clear ground;
selected cohorts can move, attack-move, focus enemies, hold, withdraw, charge
and toggle ranged fire. Shift adds cohorts to selection. Pause/resume and
1×/2× speed are independent of camera movement and rendering.

The requested counter cycle is explicit: archers beat cavalry, cavalry beat
foot soldiers, and soldiers beat archers at comparable strength. Actual spatial
duels verify all three matchups. Range, line of sight, charge run-up/recovery,
unit quality, simultaneous damage, morale/routing, gate damage and Forum
occupation affect the result. An attack-move retains its original ground goal
after pursuing enemies. Twenty-cohort attacking armies spawn on reachable
terrain. Exact waypoint arrival prevents rounding errors at gate corners.

Recruitment is visible in the town. Allied Bowmen are available in Roma's
barracks interface; cavalry keeps its stables requirement. Standalone recruits
complete through a three-civic-day queue, while campaign recruitment retains
its existing seasonal queue. Both pay campaign money/population and inherit
training/equipment. Bowmen, foot formations and mounted formations appear in
the barracks yard in proportion to the actual garrison strength. The rendered
harness recruits through the real buttons, not just direct engine commands.

Practice stays isolated. Ready campaign sieges wait for the player and commit
actual casualties/capture through the existing `BattleResolver` seam once.
Compatible older battle saves migrate to paused spatial sessions with their
casualties preserved. The saved battle contains orders, coordinates, paths,
health, morale, cooldowns, elapsed time and capture progress.

## Architecture

`CityBattleHost` in `src/runtime` owns a worker and mutex while the battle view
is open. It serializes fixed deterministic ticks and user commands. Frames only
poll detached snapshots; no timer, tween or drawing callback advances gameplay.
Saving pauses the fight. Leaving/loading/exiting joins the worker before other
simulation access resumes. A regression blocks the main thread while verifying
that the battle advances, then verifies that pause prevents changes through
wall time and presentation frames.

All models and animation are procedural. One soldier model represents four
actual troops. Arrow volleys, melee motion and interpolation are cosmetic.
Picking uses the drawn positions. Hidden enemy templates and equipment cannot
select their models; only an observed tactical role is exposed.

## Verification

- Data/schema and cross-reference validation: **0 errors, 0 warnings**.
- Fresh Godot 4.4.1 import: no script/engine errors.
- Earlier complete regression checkpoints: **615/615** and **617/617 passed**.
- Final complete regression gate: **617 tests, 0 failures**, exit 0 and no
  script/engine errors. The existing Control-anchor warning remains non-failing.
  The campaign turn-speed guard passed without changing its threshold.
- Source rendered acceptance: **passed**, including actual bow/cavalry
  recruitment buttons, visible formations, free deployment, live orders,
  charge, group attack, pause/save/load, gate breach, victory and closing report.
  The observed defence concluded at 1:34 simulated time with 25% defender and
  87% attacker casualties, without changing the real practice garrison.
- Campaign map acceptance: **passed**. Planning, marching, arrival and maximum
  zoom screenshots inspected; median 10.446 ms, p95 12.919 ms, 58 FPS in this run.
- Universal macOS export, signature and `x86_64 arm64` checks: **passed**.
- Packaged data/campaign/save/battle replay probe: **passed**.
- Final packaged rendered acceptance: **passed** with the exact shipped source
  hashes, including the strengthened hidden-roster rendering safeguard.

The capture harness uses the existing project's forced-render pattern because
macOS may suppress frame-post-draw callbacks for an occluded QA window. This
changes screenshot capture only, not battle simulation.

QA outputs are outside Git:

- `/private/tmp/roma-live-source-acceptance/`
- `/private/tmp/roma-live-final-package-qa/`
- `/private/tmp/roma-live-map-qa/`

The final source suite log is `/private/tmp/roma-live-final-suite.log`.
Package verification logs and source hashes are retained in the build's
`verification/` and `provenance.json`.

## Build and scope

The universal Mac app and zip are in `build/roma-live-battles-20260927/`, version
`0.17.0-preview.20260927`. It is the full campaign app with Roma accessible from
the menu and from its owning campaign. Preview saves are isolated from the
production app. The source snapshot records the current dirty checkout; no
production release, tag or PR is implied.

This is a complete controllable formation battle for the Roma reference case.
Other cities and field battles retain their existing campaign resolver.
Individual-soldier collision/physics, multiplayer, siege towers and multiple
breaches are outside this implementation. The district is original procedural
art rather than a surveyed reconstruction.
