# A Living, Readable Village — 0.7.0 verification

Baseline: clean main, fetched origin at
`cb78922e0c6545074c8d2e7355f8fd3998fa5ac0`. Twelve prior releases and 644 protected
file hashes were recorded before editing under `/tmp/yenikapi-0.7-baseline/`.
Version 0.7.0 was available; stable latest was `v0.14.2`.

## Implementation and strategy evidence

Two stable woodland areas, persistent household experience and discoveries,
shared preparation, finite wooden watch kits, post focus, training and upkeep use
the existing seasonal economy and finite allocator. Opening-stock commitments,
next-season forecasts and actual reports are separate. The shared room alone
produces no knowledge or material bonus. See LIVING_VILLAGE.md for exact rules,
tradeoffs, historical limits and wrapper-6 adoption.

The public-command 40-season comparison starts identically. Both strategies invest
in cultivation, storage and watch, remain fed, and finish with 300 provisions,
three serviceable kits, readiness 4 and protection 77. Overview retains 149 timber;
the attentive strategy retains 279 after paying for shared preparation and northern
observation/access, supporting the discovered relationship and rotating woodland.
This example demonstrates an informed paid advantage, not an optimality claim or
an inspection reward. Replay/save checks include succession at season 32.
The initial new suite passed 2,374 checks; final counts are recorded below.

## Development inspection and performance

Fresh M3 Max/Godot 4.4.1 direct baseline: asset opening 3.743 s, site comparison
7.838 ms, adaptation commission 649.584 ms, priority 103.231 ms, unchanged reserve
7.874 ms, watch reassignment 946.910 ms and adaptation-completion season 9.409 s.
Logs include command, world and UI components. These differ from the published
0.6 exact-app 7.7-second completion measurement and should not be conflated.

An initial after run measured opening 1.222 s, watch reassignment 375.660 ms and
completion 3.687 s. A remaining record-order mismatch was then fixed so identical
ground footprints can use incremental fabric replacement. Final source/exact-app
profiles supersede this intermediate observation below. No Intel performance is
claimed. Frame medians cannot substitute for interaction latency.

Rendered development checks found and corrected an empty-hit occlusion error in
woodland picking, a northern-post rack crossing the outward housing footpath,
and hidden-HUD test input while reviewing the guide. The post was moved and its
approach authored explicitly. Failed development logs/captures remain outside git.
All earlier independent source gates passed on the first complete run; the parent
705-test gate passed with stdout and stderr captured.

## Final gates and publication

Source gates pass 5,769 checks (248 reference, 710 governance, 302 neighbor,
310 household, 608 asset, 779 land, 438 land geometry, 2,374 living), plus all
schemas and negative tests. Source rendered acceptance passes 839 checks and
21 reviewed captures including the complete seven-step guide, both layouts,
pressure, recovery and 1280×800 controls. Parent data/import/705 tests and actual
map playtest pass; all six map captures were reviewed. Logs were scanned for
script errors as well as nonzero status. All 643 protected non-document files
remain unchanged; the protected build guide has its intended new release section.

Frozen exact-application and retained-model verification passed as recorded below.
Public downloads and preservation also pass; the publication record follows below.


## Exact packaged application

Frozen payload: `041c161c708969b06f9599beda37029c62bd9f94`. Build time: `2026-10-06T02:49:38.231406+00:00`.
Frozen source and the exact Mac app each pass **5,769 checks**. Every retained
schema and negative gate passes. The universal app's `arm64` and `x86_64`
architectures and strict ad-hoc signature verification pass. It is not Developer
ID notarized. Apple Silicon is tested; Intel performance is unmeasured.

Exact rendered acceptance passes **3,090 checks**: 85 tutorial, 57 contacts,
714 household, 477 assets, 918 land and 839 living. All **100 captures** were
manually reviewed: 14 reference, 12 tutorial, 10 contacts, 12 household,
12 assets, 19 land and 21 living. This includes the actual-input seven-step guide,
resource workers, shared-room activity, prepared materials, maintained posts,
compact/outward development, pressure/recovery, interiors and 1280×800 controls.
Logs capture stderr and were scanned for script errors.

An external driver against the unchanged app adds **7 passing checks and three
reviewed 1280×800 captures**: retained discoveries, actual seasonal results with
finite assignments, and the material-store interior. It constructs its state
through the public-command living driver, with no injected materials or progress.
Driver/log/captures are `/tmp/yenikapi-0.7-record-preview.gd` and
`/tmp/yenikapi-0.7-exact-record*`. Viewing and scrolling preserve the state exactly.

The reference mesh hash remains
`7f1edbf6ec717d61357b58ffd2237806139cdb59950b9fe5c18c16ee172c689a`.
All **30 retained GLBs are byte-identical** to 0.6.0. Three new original specimens
(living village, shared working room, northern post) bring the export count to 33.
All eight ZIPs pass integrity checks and every model partition member matches its
raw export. The 229 frozen source-file hashes still match after verification.
The app and frozen source archive were not modified to satisfy acceptance.

## Final interaction measurements

M3 Max, Godot 4.4.1 Forward+, 1600×1000; no competing Godot renderer during
profiles or benchmarks. Direct profiles exclude artificial click waits; season
measurements include synchronous presentation and the visible busy feedback.
Chapter-opening rows start after an existing scene, not from process launch.
The first table's older exact-app values are the published 0.6 observations;
the fresh source baseline is recorded earlier. These are individual measured
runs, not statistical performance guarantees.

| Action | Published 0.6 exact ms | Frozen 0.7 source ms | Exact 0.7 app ms |
|---|---:|---:|---:|
| Open assets after reference startup | 3053.000 | 1281.000 | 1005.000 |
| Compare a land proposal | 6.683 | 7.902 | 6.578 |
| Commission workroom adaptation | 534.381 | 276.172 | 221.472 |
| Change project priority/crew | 82.464 | 52.988 | 43.543 |
| Grown reserve order; unchanged assignments | 9.707 | 12.052 | 10.002 |
| Watch order; changed assignments | 774.558 | 390.557 | 321.713 |
| Season completing adaptation | 7711.000 | 3861.000 | 3177.000 |
| Open living chapter after existing scenario | — | 4363.000 | 3609.000 |
| Inspect household | — | 15.852 | 13.074 |
| Inspect woodland | — | 16.267 | 13.224 |
| Inspect watch post | — | 16.155 | 13.186 |
| Inspect shared-work relationship | — | 16.471 | 13.401 |
| Change preparation priority | — | 76.132 | 63.791 |
| Ordinary living season | — | 716.000 | 598.000 |
| Force living route rebuild | — | 152.000 | 126.000 |

New living prepared-sample readiness from process start is **7.132 s source /
5.877 s exact app**, including reference startup (2.410 / 1.994 s). The retained
outward land sample is 7.944 / 6.438 s, compared with published exact 0.6's
16.648 s. Terrain sampling and unchanged-footprint reuse reduce rebuilding;
actual changed routes and major geometry still cost time. A 3.177-second completion
pause remains visible. Unchanged-order UI refresh has not uniformly improved.

Uncapped frame benchmark: 120 warmup and 180 measured intervals per view, forced
draw, vsync disabled, screenshot readback excluded. Frame rates do not erase
interaction stalls.

| Living view | Source median / p95 ms | Exact app median / p95 ms |
|---|---:|---:|
| landscape | 8.189 / 9.460 | 7.997 / 9.939 |
| aerial | 8.304 / 9.329 | 8.227 / 9.400 |
| street | 8.496 / 8.902 | 8.282 / 9.365 |
| interior | 8.180 / 9.201 | 8.527 / 9.011 |


## Artifact identity

| Download | Bytes | SHA-256 |
|---|---:|---|
| Yenikapi-Early-Settlement-macOS-0.7.0.zip | 58694045 | `e5b04a04d69b16c863c80c10bc2180fe67dd62ecc3d042fa949b286063df05e3` |
| Yenikapi-Early-Settlement-Source-0.7.0.zip | 573857 | `2b224b4b704bc424d101ea942264ac3249c4802ee6796ac553281888fc225688` |
| Yenikapi-Early-Settlement-Foundation-Models-0.7.0.zip | 43556458 | `dd621fdc6b66c30692848260029fa69bbc82cea62ebf1be3a940052532988882` |
| Yenikapi-Early-Settlement-Contact-Models-0.7.0.zip | 21913884 | `08b29ef3966358da69b25c9866e8cf947dae536f1b9b0c392e46ccc245d2d9c5` |
| Yenikapi-Early-Settlement-Household-Models-0.7.0.zip | 2736911 | `eb169686c58dfde53553b5fb723f95626c48f2fea516b4c3b6f00775ac1492f2` |
| Yenikapi-Early-Settlement-Asset-Models-0.7.0.zip | 1460184 | `9684dc75df99b74cdd2fb127a9cc62c35d7f31ea9839605322fdb77aca9d9679` |
| Yenikapi-Early-Settlement-Land-Models-0.7.0.zip | 40375882 | `484225e0e41698631fdb575360d86e9e32b93d8edba459c5486e9fce59d4b03a` |
| Yenikapi-Early-Settlement-Living-Models-0.7.0.zip | 20610363 | `afb17b86bb4fb0d3fbf3c27fb8a69198b28b89bd68170fd9cde05d8dd88f4b19` |

QA directory (outside git): `/var/folders/31/vy1_xpsn5p58y89s48qrckcm0000gn/T/yenikapi-0.7.0-exact-qa-h3k45unx`.
Logs: `build/yenikapi-early-settlement-0.7.0-final/verification/`.
The release tag targets the frozen payload; main additionally records completed
verification and publication. No tactical combat, individual hauling, bow recipe,
new population milestone or continuous historical development is claimed.


## Public publication and preservation

Published **2026-10-06T03:12:21Z** as
[Yenikapı Early Settlement 0.7.0 — A Living, Readable Village](https://github.com/zhynek/Roman-War/releases/tag/yenikapi-early-settlement-v0.7.0).
Release ID `404272867`, tag `yenikapi-early-settlement-v0.7.0`, prerelease true,
draft false. The remote tag and release target both identify frozen payload
`041c161c708969b06f9599beda37029c62bd9f94`. Main additionally carries verification and this
publication record; release bytes remain frozen.

All **ten uploads** matched the tested local size and GitHub SHA-256 digest before
publication. GitHub interrupted several uploads with TLS/connection errors;
retries completed in the new draft, without editing older releases or changing
local artifacts. All **ten public files** were then downloaded by unauthenticated
HTTPS. Their byte counts and SHA-256 values match the tested local artifacts and
GitHub digests. All eight downloaded ZIPs pass integrity tests and all nine
checksum-manifest entries match. Thus the public Mac app, models and editable
source are exactly the tested downloads. Manifest identities:

- `provenance.json`: 89790 bytes, SHA-256 `4a1d914ac4926e35975a805f2d787d251b3596cecfbbbd9197b11b909570392a`.
- `SHA256SUMS.txt`: 1000 bytes, SHA-256 `333b5d8cf237594874074a39dbdd1d0a8e26356e434ad6d927552bb12f3563ba`.

All **12 previous releases and 65 previous assets** retain their IDs, names,
bodies, tags, publication flags, sizes, digests, timestamps and download URLs
(where applicable). The stable latest endpoint still returns **`v0.14.2`**.
The new tag targets the frozen payload rather than the later documentation commit.
No earlier download was replaced. Parent, medieval creative and village saves
were never opened or overwritten; acceptance used explicit temporary save paths.

Anonymous verification: `/tmp/yenikapi-public-0.7.0/verification.json`.
Preservation snapshots: `/tmp/yenikapi-0.7-baseline/releases.json`,
`/tmp/yenikapi-0.7-releases-after.json`, and
`/tmp/yenikapi-0.7-latest-after.json`.
