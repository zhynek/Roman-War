# A Town That Works — 0.12.0 local verification

This record begins from fetched, clean `origin/main` `138561d`, the verified local
0.11 record. The 0.11 frozen payload `227eca3` and all existing artifacts are
preserved. No public release is authorized; the parent stable latest remains
`v0.14.2`. Final frozen/exact-app results and archive audits are recorded below.

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

Hosted [CI run 37705757701](https://github.com/zhynek/Roman-War/actions/runs/37705757701)
at `7153211` subsequently passed data, import and **705 tests, 0 failures**.
The AI campaign averaged **378.933 ms**, with a **527 ms** peak, against the unchanged
600 ms budget (Linux / AMD EPYC 9V45 / four processors / Godot 4.4.1). Its Ubuntu
24.04 image was `20260927.320.1`, distinct from the earlier failing image. This is
a successful hosted sample, not proof of a particular cause or a guarantee against
future variability. The full log is retained as `verification/remote-ci.log`.
This result is recorded in a separate documentation-only follow-up; the tested
implementation and frozen Mac payload are unchanged.

## Frozen delivery and exact application

**Verified local 0.12.0**, frozen from clean commit
`b6e387de3898f9be90fd364a483c900b901e2d81`. The builder completed every retained data,
import, rule, rendered and performance gate on source and the exported app.
The original implementation payload is `e344d81`; the final frozen commit also
corrects the opening panel's old “first transition only” wording. The interrupted
first candidate remains under `build/yenikapi-early-settlement-0.12.0-candidate-01`.
No source was edited inside the final snapshot after freezing.

The app has both **arm64 and x86_64** slices; strict deep signature verification
passes. It is ad-hoc signed and not notarized. Execution was tested on the local
M3 Max; no Intel execution or Intel performance claim is made.

Both source and exact app pass **36,908 rule assertions**. Exact-app rendered
walkthroughs pass **6,981 assertions**. All **267 exact-app captures** and **82
frozen-source captures** were inspected, plus all six parent map captures.
Full-size town inspection covered landscape, aerial, street, civic interior,
preparation store, provision room, planning board/easel and the 1024×768 interface.
Quotes show payment and actual remaining reserves; shortages show missing civic
workers, lost output and an attainable recovery while retaining Town rank.

| Exact-app rendered gate | Captures | Assertions |
|---|---:|---:|
| Reference | 14 | Render pass |
| Governance | 12 | 85 |
| Contacts | 10 | 58 |
| Households | 12 | 714 |
| Assets | 12 | 477 |
| Land | 19 | 918 |
| Living village | 21 | 839 |
| Incidents | 25 | 676 |
| Main interface | 26 | 392 |
| Construction | 34 | 672 |
| Original lifecycle | 29 | 437 |
| Town | 53 | 1713 |

All **60 town save/recipe/summary JSON files match byte for byte** between source
and exact app. The actual UI walkthrough separately records **87 public commands**,
ends at turn **49**, and replays exactly on both:
`77066813e531fb8cfc60dc7c2261f67406c96d264b71eb5ea7404961abe48c64`.
The fixture table above agrees with the delivered app, including both town-entry
strategies and the public-command stressed/recovered branches.

### Delivered interaction measurements

Milliseconds below are **callback / ready after rendered frames**. Source and app
use the same cameras and recipes, sequentially, without another Godot process.
These measured pauses are retained limitations, not benchmark guarantees.

| Scenario / operation | Frozen source ms | Exact app ms |
|---|---:|---:|
| Original lifecycle: open | 25.698 / 60.037 | 23.673 / 63.042 |
| Original lifecycle: reopen unchanged | 0.092 / 32.978 | 0.091 / 15.072 |
| Original lifecycle: commission | 499.702 / 546.035 | 436.960 / 472.324 |
| Original lifecycle: season refresh | 890.120 / 933.242 | 732.307 / 766.858 |
| Original lifecycle: civic completion | 1211.957 / 1266.389 | 1056.536 / 1080.965 |
| Original lifecycle: unchanged scene refresh | 16.042 / 33.077 | 14.051 / 24.615 |
| Town: open | 25.522 / 59.473 | 22.175 / 52.695 |
| Town: reopen unchanged | 0.121 / 33.215 | 0.101 / 33.212 |
| Town: commission | 483.882 / 533.349 | 383.800 / 433.539 |
| Town: season refresh | 1408.859 / 1458.254 | 1129.830 / 1166.728 |
| Town: civic completion | 1236.590 / 1294.730 | 978.313 / 1016.508 |
| Town: unchanged scene refresh | 29.135 / 49.657 | 26.574 / 49.519 |

The exact app's town commissioning is 383.800 ms; town seasonal refresh remains
1,129.830 ms and civic completion 978.313 ms. The frozen-source matched assembly
commissioning is 499.702 ms versus the unchanged baseline's 2,006.877 ms. Unchanged
panel reopening is 0.092 ms versus 12.453 ms. Completion is not claimed as a general
speedup: the matched source sample remains 1,211.957 ms versus 1,128.443 ms before.

Across the retained reference, campaign, contact, household, asset, land and living
frame samples, exact-app view medians span **8.134–8.443 ms**, with p95 values
**8.563–10.297 ms**. Source view medians span 8.254–8.364 ms and p95 values
8.478–9.761 ms. These 1600×1000 frame measurements are separate from the 1280×800
interaction profiles and the 10-FPS capture pacing. See each benchmark JSON for
camera, draw count, primitive count, warmup and sampling details.

### Archives and preservation

Local output: `build/yenikapi-early-settlement-0.12.0-local/`.
It contains the tested app, editable source, nine model archives, `provenance.json`,
`SHA256SUMS.txt` and all verification logs. All **11 ZIPs** pass integrity checks.
Every one of the **316** original source members was compared to the frozen Git
commit; archive members match the recorded frozen hashes, including the explicit
version overrides. The archived binary, resource pack and plist match the tested
unpacked application.

There are **44 GLBs**: all **41 retained model files** match the checksum-verified
0.11 archives byte for byte, plus three new Town room models. The older 0.11 archive
and provenance checksums still pass. All **16 published releases / 109 assets**
retain their IDs, names, sizes and digests. Stable latest remains **v0.14.2**.
No new release, tag or asset was published.

| Local artifact | Bytes | SHA-256 |
|---|---:|---|
| `Yenikapi-Early-Settlement-macOS-0.12.0.zip` | 58958475 | `1a97ef03efa4a482a51ca1042e7d1b72d36c12d64c69549a157578aaa94d9b2b` |
| `Yenikapi-Early-Settlement-Source-0.12.0.zip` | 783277 | `e57cbe8d7f66c5738957080e3c8ae5a4e75d708f7aaf15cfe53799313db2bca5` |
| `Yenikapi-Early-Settlement-Town-Models-0.12.0.zip` | 986328 | `2c4bfa4c03dca8ee6f16698647394aec9da9c502ad685ccdd0195e6a0ff6c59d` |

The remaining model-archive checksums are in `SHA256SUMS.txt` and provenance.
Independent readbacks are in `verification/archive-audit.json`,
`release-preservation.json` and `manual-review.json`. QA images are stored under
`/var/folders/31/vy1_xpsn5p58y89s48qrckcm0000gn/T/yenikapi-0.12.0-exact-qa-cyncrn57`.

### Review and remaining scope

Three adversarial review lenses covered saves/determinism, data/performance/
historical claims, and balance/effect readers. Resolved findings include malformed
adoption guards, pinning directly referenced operating data, readable worker
priorities, the independent service-worker shortage, actor destinations and strict
retained-model/completion gates. The final quote audit also added actual remaining
stocks to the shared panel and checks those values against public payment.

Town is playable; Large town and later city stages remain planned. The institution
and room adaptations remain explicitly interpretive. Town adds neither residential
density nor automatic repairs, supplies or upgrades. Current services depend on
staffing and condition; earned rank survives their failure. Profiles remain pinned
and old apps reject adopted town saves. Seasonal/completion pauses remain around
one second in the exact app. The old shared-runner CI timing variability remains
unexplained; the 600 ms assertion and replay/behavior checks remain intact.
This verification is committed separately from the frozen downloadable payload.
