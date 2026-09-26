# Roman War — macOS feedback release audit, 2026-09-26

Publication follow-up: the owner subsequently approved both apps as the new Mac
standard. See [production release 0.14.1](../releases/0.14.1.md). Statements below
about an unpublished preview describe the audit checkpoint before that approval.

## Source and scope

Fetched `origin/main` and verified GitHub's default branch and latest release.
Both main and the current branch's base are
`3670aac8f684d02551fa5be778ba076c1f7c60e7`, the **v0.14.0** release from September 6.
The occupied `codex/campaign-route` worktree contains newer uncommitted Alpine
route, concealment and procedural rendering changes. Those changes were
preserved and included in the new preview; no historical branch was substituted.

This audit covers architecture and gameplay boundaries, saves, AI and victory
logic, current content, rendering, Mac packaging and the actual CI/release
status. It is not an exhaustive proof of every balance formula or a claim of
commercial-game feature parity. See [the roadmap](../ROADMAP.md) for the ordered
development plan and acceptance gates.

The feedback build is **0.14.1-preview.20260926**. The production project version
and GitHub v0.14.0 release are unchanged. The preview is a local deliverable,
not a published production release.

## Assessment

Keep the deterministic campaign engine, data/schema discipline, additive saves
and BattleResolver boundary. The project already has 70 provinces, 21 faction
records, 92 unit templates, 70 techniques, 9 edicts, construction, recruitment,
society, political offices, diplomacy, force management and procedural 3D
campaign presentation. The current route also has working forest concealment
and patrol counterplay. Forts and watchtowers are implemented, despite older
roadmap text listing them as future work.

The largest gap toward the original Rome-inspired experience is **playable
tactical combat**. The present battle screen replays an already resolved battle.
Campaign AI depth, naval warfare, campaign-goal clarity, and finished visual/audio
presentation follow closely. Adding more regions or unit records first would
leave those gaps intact.

## Changes made for this feedback build

- Added structural save validation, verified staging before replacement,
  previous-good-save backups and read-only backup recovery. Invalid input no
  longer immediately reaches migration or truncates the current slot. Version 2
  remains the format and missing additive fields remain supported. This is a
  structural boundary, not exhaustive validation of every content ID or nested
  gameplay value. Recovery currently uses the ordinary Load success message;
  explicit recovery UX remains follow-up work.
- Added a dedicated macOS feedback builder with separate campaign/route names,
  bundle IDs, persistent save folders, accurate native and in-game versions,
  release-mode export and recorded source snapshots. It rejects Godot error
  diagnostics even when the process returns zero, verifies Mac signatures and
  architecture slices, and probes the packaged game/save replay.
- Added an exported-app QA entry that drives the actual campaign menu, ends a
  turn, saves, exits, then reloads the exact campaign in a second process. QA
  storage stays separate from playable saves.
- Fixed stale map tooltips after camera movement and added a regression. A
  tooltip now clears when the camera transform changes, so it cannot continue
  describing the province that used to be beneath a stationary pointer.

## Findings to carry into development

| Priority | Finding and evidence | Next action |
|---|---|---|
| P1 | Player attacks check remaining movement and adjacent crossing affordability in `src/core/game.gd`; AI marches then calls `CombatRules.attack_army` through `ai_military.gd` without the same budget guard. Successful attacks do zero movement, so this is permission to attack after exhausting a march, not evidence of unlimited attacks. | Share the legal-action/cost rule, add symmetric scenarios and rebaseline campaign pacing. |
| P2 | `ai_assess.gd` uses cost 1 for land edges while execution pays terrain, roads and crossings. Attack planning mostly compares opponent-independent strength; recruitment favors raw power. | Use the execution cost contract and opponent-aware estimator; keep deterministic tie-breaking and bounded search. |
| P2 | `ai_policy.gd` reads `ai.min_order` with default 200, but no writer provides it. Provincial edicts and several persona controls have no AI users; persistent-objective machinery is unused. | Connect real unrest, then implement policy and persona decisions with tests proving changed behavior. |
| P2 | `VictoryRules.progress` exposes region count and a boolean; satisfaction also requires named provinces, defeated rivals and sometimes civil-war completion. The header only shows regions. | Add a complete objective checklist. A Julii player reaching 15 provinces must also see the short campaign's named provinces and Gaul requirement. |
| P2 | Fleet-dependent embarkation, naval combat, interception and economic blockades are absent; army sea crossing remains abstract. AI does not recruit ships or plan hostile-island invasions. | Build the strategic naval loop and AI together. Start with naval auto-resolution. |
| P2 | The current synchronous resolver mutates unit arrays; `BattleScreen` is result playback. | Design pending-battle/single-commit lifecycle and deterministic tactical state before interactive field combat. Preserve auto-resolve. |
| P2 | A fixed 600 ms timing assertion made the latest tag CI run fail at 603 ms, despite other assertions passing. | Separate portable correctness from a reviewed performance baseline or calibrated guard; do not hide it by increasing the threshold. |
| P2 | CI validates data and engine tests but does not export/test Mac releases. Current distribution is ad-hoc signed and not notarized. | Automate the local release gates on a Mac runner, then configure Developer ID/notarization for production distribution. |
| P3 | Old `build_realism_preview.py` modes all enter the route scene and its one save directory; old native bundle versions can read 1.0.0. | Use `build_macos_playtest.py` for this delivery; retire or repair the older modes deliberately. |

AI remains omniscient; forest concealment does not make it a fog-limited
opponent. Supply currently reports connectivity, without food stocks or
attrition. The art remains visibly procedural and stylized. No audio playback
system was found in the current source. These are explicit scope boundaries for
the roadmap, not bugs to conceal with additional visual animation.

## CI evidence

GitHub Actions is running again; the historical handoff's account-blocked note
is no longer current. The September 6 commit run succeeded; the subsequent tag
run [34042259766](https://github.com/zhynek/Roman-War/actions/runs/34042259766)
ran 516 tests with one failure: `test_ai_campaign.gd::test_map_changes_hands`,
because average turn time was 603 ms against the 600 ms limit. Data validation
and import passed. The failure log was retained for this audit. This does not
establish that future CI is green, nor does local Mac success replace that
unresolved portability issue.

## Rendering observations

The real Mac renderer was exercised on an Apple M3 Max using Godot 4.4.1's
Compatibility renderer. The general map harness completed planning, issuing,
march playback, arrival and 9× maximum zoom. The authored route exercised the
bridge, marsh causeway, mountain passes, concealed enemy and paid reveal, with
state/RNG equivalence checks and classic-view comparison.

Inspected screenshots show recognizable troop columns, terrain and crossings,
but repeated settlement blocks, schematic province edges and abrupt fog borders
remain conspicuous. The command strip and long right panel occupy substantial
space. One initial arrival capture placed the army beneath the controls, but an
independent instrumented reproduction kept the followed army centered throughout
travel and arrival. No speculative camera change was made. The reproducible
stale-tooltip defect was fixed. A more compact command layout, retained panel
state and camera checks across display sizes belong ahead of a broad art
expansion.

QA screenshots are outside the repository under
`/tmp/roman-war-audit-20260926/`; they are not game assets. Short local timing
samples are observations on this machine, not hardware-wide performance claims.

Two current 100-turn soaks (seeds 42 and 1234, idle Julii player) completed without
Godot errors. They produced 121/124 conquests, 17/15 surviving factions, no
surviving factions in debt, and 333/331 ms average turn times. The Senate survived
both, so the older warning that it can collapse is not established for these
runs. Neither run generated a civil war or any AI provincial edict; 110/112
chronicle revolt entries warrant pacing investigation. These are diagnostic
observations, not proof of balance or an engaged player's experience.

## Delivery verification

The final full suite passed **536 tests, zero failures**, with no engine error
diagnostics. One inherited unequal-anchor warning remains. Both exported apps
passed packaged replay checks, and final rendered map/route/entry checks passed.
The final packaged arrival view kept the army centered, and the route arrival
no longer displayed the stale tooltip. Every recorded original source hash
matches the final checkout's runtime/build inputs.

Final test totals, packaged checks and artifact instructions are recorded in
[the preview release notes](../releases/0.14.1-preview.20260926.md) and each build's
`verification/` and `provenance.json`. The manifest includes the original and
configured source hashes, frozen source ZIP hash, base commit, dirty-source
status and final app archive checksum. Reproducing the same input source is
supported; bit-identical signed ZIP output is not claimed.

Intel and Apple Silicon slices are checked in each universal bundle. Execution
was verified on Apple Silicon only; Intel hardware testing and notarized
download/Gatekeeper validation remain production-release work.
