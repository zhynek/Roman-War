# Village warfare 0.14.0 — local verification and delivery

## October 8 city-audit source integration addendum

The original local-app evidence below remains tied to its frozen payload. The
entire worktree was subsequently preserved in `5e4a441`, then integrated with
audit `8589fe9` in `a88ca25`. Current source adds Town-support and finite-duty
explanations, honest illustrative-learning copy, related Homes/service discovery,
eleven guide lessons and reproducible public-command comparisons. Published
semantic hashes and the paid 0.11 fixture remain unchanged; no new save extension
was needed. Original defense uses wrapper 9, adopted warfare wrapper 10.

All seven battle walkthroughs were repeated: **1,636 checks, zero failures,
50 inspected captures, empty stderr**. Lifecycle, Town and the new guide were
also rendered. Current quick-mode controls measured 300/200/399 ms for
stores/landing/probe on M3 Max, within the retained two-second target. The matched
audit demonstrates useful equipment/repair consumers while retaining the mature
Town food-surplus and civic-ceiling limits.

See [the integration verification](../../../docs/reviews/2026-10-city-warfare-verification.md)
for all source/parent gates, CI, provenance paths and the updated-source launch.
This later task authorizes source commits and pushes to main, but builds or
publishes no release. The app/ZIPs described below are unchanged and do not contain
the new integration guide/copy. No new exact-export claim is made.

## Original local delivery record

Date: October 8, 2026. This milestone extends the preserved local, uncommitted
0.13 defense implementation on `codex/village-defense`, based on `2885f38`.
The separately fetched `origin/main` audit `8589fe9` was inspected; this work did
not reset, discard or merge over the user's existing defense changes. No push,
published release or older local delivery was replaced.

## Source release gates

| Gate | Result |
|---|---|
| Independent village catalog and validators | Catalog plus 17 validators pass |
| Python negative/data tests | 103 unit tests and 14 embedded negative cases pass |
| Retained village engine suites | 15 suites, 37,636 checks, zero failures |
| New tactical/warfare suites | 14 headless suites, 13,234 checks, zero failures |
| Complete village headless gate | 29 suites, 50,870 checks, zero failures |
| Final rendered camera gate | 20 checks, zero failures; screenshot inspected |
| Village import and selected suite stderr | Clean import; exit 0 and empty stderr |
| Parent data validation | Zero errors and zero warnings |
| Parent Godot import | Clean; 4.691 seconds |
| Complete parent suite | 705 tests, zero failures; 465.171 seconds |
| Campaign map rendering | Planning, marching, arrival and maximum zoom inspected; clean stderr |

The parent suite retains its existing opposite-anchor/size warning. It produced
no script errors. The parent game sources, data and schemas remain unchanged.
Two initial final-sweep failures exposed a minimal rules constructor without a
watch asset. The guarded registration fix passed governance, neighbor, base,
defense, construction and visual rechecks. Original failed logs remain preserved
as rejected runs. A rendered journal test also exposed unmapped work-order names;
the corrected journal passed the final UI and affected source checks. Passing
status is based on assertions **and** stdout/stderr, not process exit alone.

A subsequent adversarial review found and fixed forged original mobilization
capabilities and a full-command-log softlock. The adopted validation now derives
roster, equipment, readiness, cost, starting morale and enemy starting health;
48 new integration assertions reject those edits and relocated authored objectives/deployment bounds. The command safety-reserve gate
adds 4,614 checks for start/pause/withdraw, exact replay, saves and bounded finish.
The affected suites were rerun after these fixes. The original 45,061-check
sweep remains an identifiable pre-review record; the table reports the selected
final 50,870 headless checks plus 20 rendered camera checks.

Source gate records: `/tmp/village-warfare-qa/final-village/final-summary.json`,
`final-results.json`, `final-source.json`, per-run source hashes and split logs.
Parent records: `/tmp/village-warfare-qa/final-parent/`. Map captures and hashes:
`/tmp/village-warfare-qa/final-parent-map/`; parent source remained unchanged.
The capture harness reported median 8.327 ms / p95 8.765 ms and an FPS snapshot
of 6.0; this screenshot harness is not a sustained gameplay FPS benchmark.

## Phase checks and actual controls

Phase 1 exercised sampled navigation, collision and spacing, automatic filing,
opposing traffic and passing places, routed traffic, reachable pursuit, atomic
blocked-order rejection, contact expiry, fatigue, facing, protection, morale,
bounded termination and JSON replay. Final tactical rules: 1,492 checks.
Actual controls covered all seven orders, selection, pause, speed, camera
separation, active save/resume and return to village life. An early pinch-floor
failure was corrected; the targeted final camera gate passed 20 rendered checks.
Original procedural articulation checks verify that animation changes no state
and cannot reveal hidden enemies. A later dedicated synthetic-arena rendered
walkthrough adds 1,149 checks and six inspected captures: matching physical/nav
obstacles, congestion cleared at tick 129, blocked-order rejection, pursuit into
melee at tick 62, damage-triggered morale retreat at tick 26 and an untouched
700-tick idle stalemate. These clearly labeled QA arenas supplement the actual
village walkthroughs rather than claiming artificial obstacles are village fabric.

Phase 2 paid both screen projects through finite seasonal labor, checked every
ordinary route and building entrance in three layouts, maintenance loss/restoration,
paused unrelated work, cancellation/refunds, plan persistence and free-protection
rejection: 2,379 rule checks. Presentation covered both screens at all five stages:
1,273 rendered checks and 22 inspected captures. The actual-control preparation,
plans, deployment and continuing-life walkthrough passed 63 checks.

Phase 3 uses a shared fixed-tick engine for direct, delegated and batched runs.
The equivalence/save/mode gate passes 852 checks in the completed four-phase
source; worker cancellation/pause passes 32. The actual-mode walkthrough passed
116 checks, including three objective cycles, real muster competition, mid-fight
handoff/takeback, quick cancellation, active/ended saves and practice isolation.
Preparing six actual residents with four ordinary kits and both maintained screens
won all three objectives; an unprepared two-resident watch lost all three.
No hidden mode bonus or independent casualty formula is used.

Phase 4 passes 277 checks covering six actual cycles, earned skill, named injuries,
finite fed care, paid full-pool repair, older-save adoption, natural lifecycle
history and exact-once acceptance. The final rendered walkthrough passes 116
checks with clean stderr and seven inspected captures. One battle produced three
recovering residents (two incapacitations, one wound), two lost kits and condition
100→70. Disabling care/repair prevented recovery; enabling ordinary finite care
and paid repair restored the residents and condition. The household and journal
views retained the consequences, post-history practice left the ongoing state
identical, the next landing encounter was accepted and unrelated paid work finished.
Small-window history was inspected at 1280×800.

Accepted rendered records include `/tmp/village-warfare-qa/phase2-controls-final/`,
`/tmp/village-modes-controls-verified/`, `/tmp/village-aftermath-controls-final/`
and the focused presentation paths recorded in their logs. Rejected intermediate
runs are not counted as delivery passes. QA PNGs are outside the repository and
are not included in the game or editable-source assets.

## Performance contract

Practical target: the standard prepared six-resident encounters complete in under
two seconds on the local Apple M3 Max test machine. The final Phase 3 actual-mode
pass measured stores 343 ms / 420 ticks, landing 199 ms / 195 ticks and probe
454 ms / 347 ticks. Later aftermath mode checks measured 280–695 ms for the three
objectives. Tick counts can differ when player orders differ. These are local
measurements, not a claim about every computer or arbitrary battle fixture.

Quick mode omits battlefield rendering, retains a progress display and offers
**Stop & pause**. Bounded worker batches release the lock after at most 16 ticks
or 12 ms, so cancellation leaves a coherent resumable fight. A deliberately slowed
pacing wrapper verifies the progress/cancellation controls without changing the
rules. Every objective has a deadline; idle and total-tick bounds prevent endless
resolution. The exact exported-app measurements are recorded below after testing.

## Final local artifact gate

The final app is in `build/village-warfare-0.14.0-delivery/` with a separate
editable `source/`, `Village-Warfare-source.zip`, `Village-Warfare-macOS.zip`,
`source-manifest.json`, `provenance.json`, `SHA256SUMS.txt`, `CONTROLS.md`,
`LAUNCH.txt` and copied verification records. All 304 frozen source files match
the independent village workspace. The macOS app has arm64 and x86_64 slices;
`codesign --verify --deep --strict` passes. A normal Launch Services launch
opened the app window successfully after the test runs.

Exact launch command from this machine:

```sh
open -n "/Users/zacharyhynek/Documents/ChatGPT/Roman-War/build/village-warfare-0.14.0-delivery/Yenikapı — Early Settlement.app"
```

Choose **New village** or **Load saved village**, then **Defend the village →
Enable village warfare**. Use `CONTROLS.md` for paid preparation, recurring
threats, command modes, saving and recovery. Source opens as a standalone Godot
4.4.1 project; it has no parent campaign or external art runtime dependency.

| Final packed-app gate | Result |
|---|---|
| Complete headless rule/presentation suite | 29 suites; 50,870 checks; zero failures; 269.366 seconds |
| Actual legacy defense controls | 95 checks, zero failures |
| Tactical controls and target framing | 87 checks, zero failures |
| Camera, drag selection and facing | 20 checks, zero failures |
| Paid fortification and plans controls | 63 checks, zero failures |
| Direct/delegated/quick modes and repeated threats | 116 checks, zero failures |
| Named aftermath, treatment, paid repair and continuing work | 106 checks, zero failures |
| Synthetic navigation, pursuit, morale and stalled termination | 1,149 checks, zero failures |
| All seven rendered suites | 1,636 checks; zero failures; 50 screenshots covered |
| Process/stderr and artifact identity | Every run exit 0; stderr empty; executable/PCK unchanged |
| Final catalog/data/Python recheck | Catalog, 17 validators, 103 unit tests and 14 embedded negatives pass |

Forty-one final PNGs were inspected directly; nine were SHA-256 identical to
previously inspected candidate captures. The final report and individual image
hashes are in `final-export-render/visual-inspection.json` and
`inspected-captures.sha256`. QA images remain in
`/tmp/village-warfare-qa/final-export-render/`, outside the repository. Rule logs
are in `final-export-headless/`, and final data logs in `final-export-data/`;
non-image records are copied into the delivery's `verification/` folder.

On Apple M3 Max, macOS 26.6.1, Godot 4.4.1 / Metal, prepared delegated victories
measured **219.181 ms stores**, **152.628 ms landing**, and **332.234 ms probe**.
The worker gate measured **195 ms / 395 ticks** for its typical quick fight and
**0 ms at millisecond resolution** for cancellation. Actual rendered mode controls
measured **255 ms stores**, **167 ms landing**, and **327 ms probe**. These elapsed
quick portions exclude earlier live-command time; final battle ticks include it.
All are below the practical two-second target. Normal, batched and resumed
identical command streams remain exactly equivalent in the rule gate. Other
player command streams can produce different battle lengths and injuries.

The first export candidate had a test click under the bottom HUD. Diagnostics
confirmed the enemy was correctly pickable and the UI correctly consumed the
click; the test now frames it through actual middle-drag camera input and verifies
that paused state is unchanged. A recovery summary was also corrected to include
mild wounds accurately. The final export was rebuilt and all packed gates repeated.
Rejected candidate logs remain separate from accepted final results. The initial
freeze guard also caught two missing generated script UIDs before export; the
working project was imported and the final freeze verified byte-for-byte.

Reproduction tools live in `Castles and Cities/tools/`:
`build_village_warfare_local.py` refuses existing output directories;
`verify_village_warfare_export.py` runs the packed app without a source `--path`
override. Build provenance records the dirty worktree honestly. No Git commit,
push, public release or existing release replacement was performed.

## Deliberate limits

- Groups, one-metre sampled navigation and allocated group-health injuries are
  abstractions. They are not independent per-person physics or medical modeling.
- Combat injuries are recoverable. Permanent combat death is not integrated;
  ordinary natural lifecycle deaths and household history remain intact.
- Woven screens are original hypothetical preparations. They retain open access,
  need ordinary maintenance and have no cosmetic or authoritative battle collapse.
- Terrain/obstacles and maintained defensive positions matter; elevation physics,
  complex weapon simulation and a separate military/diplomacy economy are absent.
- Recurring objectives are a bounded repeating sequence with fixed capability,
  explicit warning and recovery intervals, not an unlimited dynamic war generator.
- Broad overhead figures and labels remain small; close view provides detail.
  Ordinary civilian shared work spots can still cluster residents. Verification
  includes fixed-tick checks and sampled rendered animation, not motion capture.
- The local universal macOS app is ad-hoc signed, not notarized. Performance is
  measured on Apple Silicon; the Intel slice is packaged but not benchmarked here.
