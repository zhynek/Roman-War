# A Town That Works — 0.12.0 local verification

This record begins from fetched, clean `origin/main` `138561d`, the verified local
0.11 record. The 0.11 frozen payload `227eca3` and all existing artifacts are
preserved. No public release is authorized; the parent stable latest remains
`v0.14.2`. Final frozen/exact-app results are recorded after packaging below.

## Playable scope

Slice C extends one continuing settlement from Small village through Large village
to Town. Paid work adapts the existing assembly shelter into a civic house. Town
opens a material-preparation store and shared provision service, purchased
separately. All three alterations preserve occupied fabric, entrances, furnishings,
household associations and prior land costs. No dwelling or density is added.

Town duty is two adults total, replacing the earlier one. The preparation bonus
consumes extra timber and work space; the service needs another adult and reduces
actual spoilage. Both depend on civic staffing and maintained stores. Understaffing
or neglect suspends output while earned rank and paid work remain. The shared
site/main/planning-board system supplies the same quote and controls.

The base `village_lifecycle_v1` semantic hash remains
`a4694114cc755d8f5a2113daabf71370a8b85824acc1317dbe973c3555f1fe35`.
Explicit town adoption pins `town_responsibilities_v1` separately:
`a5c1d5628d3e0a2950bdada2ae781ede5ea9c6e5071a864397887d30acdbd48c`.
Wrapper 8 remains appropriate; wrappers 1–7 keep their meanings. The actual frozen
0.11 partial paid-save fixture loads unchanged. Legacy recognized towns retain rank
and pay through missing civic fabric without repeated promotion benefits.
Town saves require 0.12; older apps deliberately reject that extension.

## Source acceptance before freezing

All retained independent data/negative/import/rule/save/geometry suites pass.
The final complete source run passed **36,908 checks**, including malformed
adoption history and referenced-data semantic pinning. Both strategies use ordinary
public commands, no grants, foreign trade or state-edited promotion.

| Strategy | Civic house | Preparation | Provision | Season 100 population / food / timber / work places |
|---|---:|---:|---:|---|
| Compact | 39 | 41 | 43 | 48 / 360 / 225 / 8 |
| Outward | 46 | 51 | 56 | 48 / 360 / 121 / 14 |

Town rule gates save before commissioning, partial work, entry and operation;
replay every fixture recipe exactly; test proportional cancellation, pause/resume,
once-only spending, finite adults, current/required sustained readiness, blocked
entry and recovery, active contacts, and both incidents with active/paused paid
sites. Malformed hashes, adoption history and turns are rejected without script
errors. Old lifecycle recipes still have their original milestones and stocks.

The final source real-input town walkthrough passed **53 captures / 1,713 checks**,
with no failures or script errors. It commissions civic work through the physical easel,
manages partial sites through mesh picking, cancels/loads the partial civic branch,
purchases both facilities through ordinary cards, inspects operation, and produces
an understaffed town followed by recovery. It checks doors, routes, cold-build
geometry, planning-room continuity, save/load, pure inspection and repeated input.
Its recorded continuing UI recipe must replay exactly and match the exact app.
Earlier failed QA runs remain in `build/yenikapi-0.12-baseline`: a disabled already-
selected model button, a material-pile click hidden behind the dock, and an
incorrect assumption that the extra service adult would be available in winter.
A later source run (retained under `build/yenikapi-0.12-source-gates`) also
missed a native physical-plan click; the helper now verifies
the selected plan and camera, retrying only while simulation is unchanged. The
acceptance tool uses valid visible controls and waits for ordinary staffed
operation; the interface explicitly explains the independently missing service adult.

## Reproducible public-command fixtures

Run `town_checks.gd -- out_dir=/tmp/yenikapi-town-states` as documented in
[LIFECYCLE.md](experience/LIFECYCLE.md). Each named save has a matching
`-recipe.json` with every public command and its turn. `fixtures.json` records
state digests; these are SHA-256 of the canonical Godot state serialization,
not of the wrapper file. The gate replays every recipe from the ordinary new-game
state, compares it exactly, and compares all source/exact-app fixture bytes.

| Fixture | Turn | State SHA-256 |
|---|---:|---|
| `town-readiness-blocked` | 28 | `3d71269b795b0562f66dc8f79c305194a27571332628cb7d26e1e8d2aaf0df27` |
| `town-readiness-recovered` | 32 | `21f8e0aa1af68be602010824db91189cf4e365a70a858c3f3fb4c0e692ed55de` |
| `compact-town-ready` | 35 | `d01415fbfdaf891505937fa6e2d1a7e4c95a2ce2467fc1dbfaec58a1f990ee76` |
| `compact-town-entry` | 39 | `51e9e12ffbe028324ac7c8db8ee19a941087a2d82848daca4966d7ff3bd1cf4e` |
| `outward-town-entry` | 46 | `c1f5fd39effe0b8abc69ec99ea9849e4a2fb1acf2f6208f981f34e8a360b8130` |
| `stressed-town` | 43 | `9c384c994e76e4cf3fd130a1950e3f67f63222524b0a5113b4290374c6f2e8b1` |
| `recovered-town` | 44 | `b55906b43e6758dc5a6de3a70214745e1802ab8526882700cbb988de9c31de78` |

The stress branch commissions the available exchange-place project with three
adults at priority 1, competing with civic duty; the recovery branch pauses that
paid work after a season. Neither branch edits stocks or rank. The actual UI
walkthrough separately combines paid learning duties and construction to produce
and recover from a civic shortage at its later season. Its own full command trace
and final digest are preserved in the render report.

## Performance and CI investigation

All measurements below are local Godot 4.4.1, Metal 3.2, Apple M3 Max at 1280×800,
with no concurrent Godot benchmark/render process. Callback time is distinct from
readiness after rendered frames. These are observations, not universal budgets.

| Matched retained lifecycle operation | Baseline callback ms | Revised callback ms |
|---|---:|---:|
| Open lifecycle | 28.717 | 28.269 |
| Reopen unchanged panel | 12.453 | 0.109 |
| Commission assembly | 2006.877 | 510.081 |
| Ordinary seasonal refresh | 1131.414 | 895.027 |
| Civic completion | 1128.443 | 1216.819 |
| Unchanged world refresh | 14.943 | 15.482 |

The commissioning journey component fell from 1803.737 to 315.657 ms. Reuse takes an
existing searched path from the same origin only when its nearby endpoint has a
collision-clear connector. Geometry changes revalidate routes; no simulation or
assignment is cached. Unchanged UI content is retained. Completion remains a
material pause and was slightly slower in this sample; it is not claimed as an
improvement. The new town scenario measured 507.849 ms commissioning, 1500.592 ms
ordinary refresh and 1259.285 ms civic completion. Source/exact build profiles below
supersede these development samples for the delivered payload.

The linked parent CI failure predates the work. Unchanged local baseline averages
were 314, 317, 313 ms against 600 ms. Identical parent code passed and failed on the
same Ubuntu image; specific runner contention is unproven. A separate diagnostic
commit prints timing/environment on passes as well as failures and preserves the
budget and all replay/behavioral assertions. The final parent gate passed all
705 tests at 311.233 ms average (439 ms peak), plus data/import/map inspection. See
[the investigation](../../../docs/reviews/2026-10-ai-ci-performance.md).
No speculative AI/cartography optimization or assertion relaxation is included.

## Frozen delivery and exact application

Pending the clean frozen build and its required exact-app/manual image checks.
This section is completed in a separate verification commit; the source payload
must not be edited after freezing. The builder enforces all retained gates, town
fixture/actual-UI equivalence, universal architecture, 41 retained model bytes,
three new Town GLBs, archive integrity and source hashes. QA images remain outside
the repository. No release publication is part of this delivery.
