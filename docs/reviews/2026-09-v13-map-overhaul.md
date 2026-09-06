# v0.13 — commanders, scouting and direct map orders

This pass responds to the v0.12 playtest: generic tiny commanders, uniform
army movement, little reason to position scouts, missing enemy march replay,
and awkward selection/drag behavior. It continues the occupied
`codex/map-gameplay` worktree and preserves the prior v0.12 work. The initial
cross-agent review remains in `2026-09-map-experience.md`; `CLAUDE.md` remains
the shared architecture contract.

## What changed

- **Individual commanders.** `CommanderArt` resolves stable face proportions,
  complexion, hair, age, beard, scars and horse coat from the character id.
  All 21 factions have authored helmet, armor, cloak and accent choices in
  `unit_art.commanders`. The force panel and map show the same person.
- **Cultural formations.** Own troop miniatures reuse the existing UnitArt
  culture kits, class definitions and template overrides. Infantry shields,
  bows, pikes, cavalry, chariots, elephants and artillery have distinct marks.
  Enemy formations use public cultural dress, never their hidden unit list.
- **Mobility by composition.** The slowest company sets the army's base pace.
  Normal base points are 2 for spear/pike/artillery/elephant/peasant, 2.5 for
  infantry/missiles, 3 for chariots, 3.5 for cavalry/bodyguards, and 4 for horse
  archers. Existing general, faction and knowledge bonuses still apply. Two
  points remain sufficient to cross a mountain; heavy units cannot get stuck
  forever behind a two-point step. Transfer, merge, split, hiring and general
  changes cap remaining movement without refunding a completed march.
- **Observation infrastructure.** A player army can build a watchtower in its
  own province for 600 denarii and 1 movement, then fortify it for another
  1,200 and 1 movement. Towers see two land steps, forts three. A fortified
  post gives defending field armies there +20% strength through the same
  BattleResolver context used by the preview; AI assessment accounts for it.
  Posts stay active after the army leaves, while their builder owns the land.
- **Positioned scouts.** Ordinary armies and towns see one land step; pure
  mounted columns and spies see two. The coverage overlay visualizes actual
  visibility, and observed towns show garrison headcount and wall tier.
- **Enemy march intelligence.** Movement, amphibious travel, field-battle
  advances and siege entry record sightings at the relocation choke point.
  Snapshots contain commander identity, counts and observed endpoints only.
  The turn journal replays visible enemy marches even if the army later
  merged or disappeared. Entering/leaving sight shows only the known endpoint;
  it never reconstructs a hidden endpoint using final-turn visibility.
  Last-known contacts retain their observation date and expire after three
  seasons. These reports are private to the observer.
- **Direct orders.** Click an army/commander, then a reachable destination.
  Dragging an army previews the road; release orders it. Longer journeys open
  a pinned plan for review. Combat retains its existing confirmation. A
  different friendly army can be selected while a plan is open.
- **Gesture and layout fixes.** Empty land, middle-drag and Space-drag pan.
  Window focus loss, modal openings and out-of-map releases clear mouse grabs.
  Drops over panels or their nested controls are rejected. Fractional wheel
  input is respected. Portrait layout is shared with picking and separates
  colliding cards. Command labels receive a wrapping width before height is
  measured, preventing a transient enormous panel that swallowed drops. Labels
  retain readable heights. The army roster has compact strength bars.

## Preserved boundaries

The scene-free engine remains deterministic. No timers, tweens, drawing code
or UI frames relocate a force, spend movement, resolve combat or consume
campaign RNG. `watchposts` and `recon` are additive state keys initialized in
NewGame, backfilled for old saves and included in fixtures. SAVE_VERSION stays
2. No external or generated bitmap game assets were added: portraits, troops,
posts and settlements are original procedural drawings.

Movement and observation still use the province graph. This does not introduce
arbitrary tactical coordinates, terrain-height occlusion, individual soldier
AI, or a real-time combat engine. Enemy composition remains private. Posts
are player-built infrastructure; the AI understands their defense but does
not yet budget for constructing its own. Mobility and scouting values are an
initial playable balance pass, not a completed campaign balance study.

## Verification

- Data validation: **0 errors, 0 warnings**.
- Complete release suite: **502 tests, 0 failures**, with no script/error
  diagnostics. One pre-existing non-equal-anchor warning remains in a UI test.
- Final focused map/order/force checks: **43 tests, 0 failures**.
- Storage isolation plus UI smoke and v0.13 gameplay checks: **47 tests,
  0 failures**. This includes the new storage guard, bringing the discoverable
  suite to 503 cases. The full run above preceded that guard; its changes only
  isolate test storage.
- Source rendering: planning, marching, arrival and maximum detail passed;
  all screenshots were written outside the repository.
- Reconnaissance rendering: watchtower construction, fort upgrade, extended
  visibility, observed enemy movement, immutable replay and the 21-faction
  commander sheet passed. Visual inspection also caught and corrected an
  interaction between wrapped labels and ellipsis sizing.
- Universal macOS v0.13 export and strict code-signature verification passed.
  Final package probes and reconnaissance rendering also passed. A final
  26-case layout/storage check passed. Exported-package verification is recorded in `build/v0.13/BUILD-INFO.json`.

QA scripts: `tools/map_playtest.gd` and `tools/recon_playtest.gd`. Development
filter: `-- suite=map_v13,map_orders,map_experience,ui_forces,ui_smoke,pathfinding`.
Check stderr as well as exit status. Output belongs in `/tmp`; it is not art
content to commit.

## Test-storage issue found during release checks

The inherited UI tests called the normal Save/Load buttons using the live
`user://roman_war_save.json` slot, and the test run wrote its fixture there
before this was identified. A previously saved campaign could have been
replaced by that fixture. The v0.12 app was initially at its start menu; later
inspection found an active Cornelii campaign. Before launching v0.13, that
campaign was saved through the actual Save button and copied to
`build/v0.13/Cornelii-before-v13.json` (Cornelii, seed 42, turn 0). The old app
was left running. This preserves the current campaign; it does not recover
any different save that existed before the tests.

The test runner, package probe and both rendered QA entry points now select
separate, per-process Godot user directories before creating any campaign UI.
The isolation test guards this contract. A subsequent 47-test run left the
normal campaign save's modification time and size unchanged. Normal gameplay
continues to use its existing save location, so this fix does not migrate or
rename a player's save.
