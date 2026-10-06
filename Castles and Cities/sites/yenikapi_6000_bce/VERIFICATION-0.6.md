# Land, Growth, and Lasting Consequences — 0.6.0 verification

Baseline: clean main, fetched origin at
`211f7ec4ee4ba3507fc9c13bc708f3cbb4b65518`. Frozen payload: `b97106278e96d3561df63de800d2fc89edeebbd1`.
The build and subsequent publication checks below identify the exact artifacts.

## Implemented acceptance

Seven bounded sites, eight initiatives, existing uses and explicit connections
share the original construction ledger and finite stores/adults. Conversion
reserves a site and removes its former contribution immediately; pause retains
the claim, cancellation releases unfinished use, and completion is permanent.
Compact homes trade shared working space for cheaper existing access. Outer homes
preserve it but need continuing access support. Cultivation and provisioning
compete for the west field. A useful workroom adaptation preserves stable building
identity and older furnishings. No occupied house is removed or silently relocated.

From identical 30-person/100-provision/30-timber starts, public-command strategies
reach the existing town milestone in season 24 and remain fed through season 80.
At season 80 both have 48 residents and 300 provisions. Compact development has
six construction places, 555 timber and a -4 land cooperation factor; outward
has eight places, 468 timber and continuing one-adult/one-timber access support.
These are reproducible example strategies, not assertions of a universal optimum.
No hidden supplies, arrival-based production or second construction economy exist.

Rule checks cover world/overview command identity, blocked access and land
conflicts, provisions, exclusive workforce including neighbor carriers, competing
projects, priority/pause/cancellation, forecast identity, adaptation lineage,
residential accommodation rejection, office authority and succession, legacy
paid queues, additive opt-in saves, deterministic replay, poor-choice recovery,
and presentation independence. The source gates pass 248 reference, 709 governance,
302 neighbor, 310 household, 608 asset, 779 land checks and 438 land geometry checks.
Land negative tests exercise 13 malformed relationships/content mutations and four
invalid seasonal tuning values. Every retained data gate also passes.

Final source rendered acceptance passes **19 captures and 918 checks**, including
actual world/overview selection, asset-to-land navigation, commissioning, pause,
small-window upkeep recovery, both layouts and the provisioning conversion.
The paced input run records opening 11.157 s, comparison 10–11 ms, commission
3.208 s (including click/settling waits), ordinary reserve change 12 ms, unchanged
refresh 1 ms, route rebuild 336 ms and the sampled noncompletion season 1.731 s.
These source observations are distinct from the exact-app results below.

Parent data and import pass; the full campaign suite reports 705 tests, zero
failures. The rendered map gate passes. Logs retain stdout/stderr and require
script-error scanning in addition to exit codes. QA images remain outside git.

Development inspection found and corrected: an overwide eight-tab panel; project
labels and staging intruding into the workroom view; two compact footprints
obstructing the actual curved west/field paths. Full path walking was added to the
gate, alongside household doorway and citizen route checks. Both corrected
layouts and the converted provisioning yard pass 438 geometry checks. These
failures are retained in external development logs rather than hidden as passes.
The first packaging attempt also caught an access-test fixture that had not yet
completed its prerequisite. It now constructs access through paid seasons before
testing disabled upkeep, then commissions a real outer project before asserting
zero work without opening timber. The corrected land suite passes 779 checks.

## Performance baseline and limits

Measured again on this Apple M3 Max before edits: the 0.5 actual-input asset guide
opened in 15.439 seconds, its representative reserve-order change took 1.350 s,
forced routes 287 ms and unchanged refresh 0 ms. Its uncapped prepared-scene
benchmark reached asset readiness in 13.868 s from process start, reference startup
4.924 s; frame medians about 8.31–8.34 ms. The earlier published 0.5 observations
(11.814 s readiness, 1.194 s order, 276 ms routes) remain valid observations of
that run, not universal targets.

The new code avoids rebuilding unchanged reference geometry when opening a
chapter, rebuilds only visible interface tabs, and uses actual assignment/visible
state fingerprints and collider-invalidated route caches. Compare interaction
profiles separately from paced input tests and steady frame-time benchmarks.
Major fabric changes still require synchronous geometry and initial route work.
There is no claim of stall-free interaction or measured Intel performance.

The phase remains hypothetical gameplay associated with the village. Direct site
evidence, regional building-continuity analogy and gameplay interpretation are
separated in SOURCES.md and LAND_GROWTH.md. No recovered land tenure, continuous
city genealogy, new monarchy or tactical combat is implied. General relocation,
free placement, household negotiation, individual hauling and crowd avoidance
remain outside this phase. Mac signing is ad hoc; it is not notarized.


## Exact packaged application

Frozen source and the exact exported universal Mac app each pass **3,394 checks**:
248 reference + 709 governance + 302 neighbor + 310 household + 608 asset +
779 land + 438 spatial geometry. All retained and new schema/negative tests pass.
The parent has 705 passing tests and a passing rendered map. The exact app's
ad-hoc signature and both `arm64` / `x86_64` architectures were verified.
All final logs were scanned for script errors, including stderr on zero exits.

Exact-app acceptance passes **2,252 interaction/navigation checks** (85 tutorial,
58 contact, 714 household, 477 asset, 918 land), plus the dated-reference render
gate. All **79 captures** were manually inspected: 14 reference, 12 tutorial,
10 contact, 12 household, 12 asset and 19 land. They cover both spatial layouts,
paid staging, adaptation and retained furnishings, paths/entrances, ordinary life,
pressure, recovery, lost cultivation and restored food margin, and 1280×800
controls. Final captures required no fallback or packaged-code modification.

The source/packaged reference mesh hash is unchanged:
`7f1edbf6ec717d61357b58ffd2237806139cdb59950b9fe5c18c16ee172c689a`.
The 572-file protected hash manifest passes. A complete diff boundary check also
confirms no parent code/data/test or medieval source changes. All **27 retained
GLBs are byte-identical** to 0.5.0. Three new neutral specimens bring the total to
30. Seven ZIPs pass integrity checks; model partition members match raw exports.

A supplemental external driver ran against the unchanged exact app and passed
**12 further checks and two reviewed captures** at 1280×800. It built the compact
settlement using public commands, reviewed all five planning steps through actual
buttons, and displayed growth readiness and guide completion. No project, resource
or tutorial progress was injected into the state. Driver/log/captures are under
`/tmp/yenikapi-land-guide-acceptance.gd` and `/tmp/yenikapi-0.6-exact-guide*`.

## Final interaction measurements

Same M3 Max, Godot 4.4.1 Forward+, 1600×1000. These are observations, not universal
requirements. Paced acceptance uses 10 FPS to settle background Metal materials;
benchmark frame timing is uncapped with 120 warmup and 180 measured intervals per
view and screenshot readback excluded. The runs used no competing Godot renderer.

| Asset observation | Published exact 0.5 | Exact 0.6 |
|---|---:|---:|
| Prepared sample from process start | 11.814 s | 11.506 s |
| Actual-input chapter opening, including waits | 13.582 s | 9.491 s |
| Representative reserve order | 1.194 s | 1.077 s |
| Forced route rebuild | 276 ms | 170 ms |
| Unchanged refresh | 0 ms | 1 ms |

The fresh source baseline was 13.868 s to the prepared asset sample; frozen 0.6
source was 13.800 s. Opening an ordinary chapter benefits from reusing unchanged
reference geometry; constructing a different prepared sample still requires a
full rebuild. Changed duties remain substantially slower than inspection or an
order whose resulting assignments are unchanged.

Land actual-input timings: `{"change_order_ms": 10, "commission_input_ms": 3074, "compare_grown_ms": 8, "compare_ms": 9, "open_ready_ms": 9548, "route_rebuild_ms": 273, "season_ms": 1413, "unchanged_refresh_ms": 1}` (milliseconds).
Commission includes click and frame-settling waits; the sampled season does not
complete a building.

Direct interaction profiles separate command, world and UI work. Totals below
exclude scripted click waits.

| Action | Source ms | Exact app ms |
|---|---:|---:|
| Open assets after reference startup | 3740.000 | 3053.000 |
| Compare a site | 7.800 | 6.683 |
| Commission retained workroom adaptation | 649.435 | 534.381 |
| Change project crew/priority | 99.139 | 82.464 |
| Reserve change with unchanged assignments | 11.804 | 9.707 |
| Watch change with reassignment | 963.790 | 774.558 |
| Season completing adaptation / rebuilding fabric | 9414.000 | 7711.000 |

The outward 48-resident land sample has the following frame results. Steady
frames do not remove the startup, reassignment or completion stalls above.

| View | Source median / p95 ms | Exact app median / p95 ms |
|---|---:|---:|
| landscape | 8.109 / 9.389 | 8.192 / 9.069 |
| aerial | 8.146 / 9.290 | 8.423 / 8.932 |
| street | 8.115 / 9.400 | 8.193 / 9.251 |
| interior | 8.696 / 9.143 | 8.572 / 8.959 |

Land sample readiness from process start: source **20.367 s**,
exact app **16.648 s**. The direct completion profile demonstrates
a remaining synchronous geometry/route stall; further incremental rebuilding is
future work. Intel rendering and performance remain unmeasured.

## Artifact identity

Frozen payload: `b97106278e96d3561df63de800d2fc89edeebbd1`. Build time: `2026-10-06T01:01:58.826474+00:00`.

| Download | Bytes | SHA-256 |
|---|---:|---|
| Yenikapi-Early-Settlement-macOS-0.6.0.zip | 58649918 | `38b095181a25fbdbc6f39a25f027fdbf76232f5d3a7dc73138016188dee3c70f` |
| Yenikapi-Early-Settlement-Source-0.6.0.zip | 534697 | `2ab346718c67f601cf6186dfc94058b9540df009703c090756f1839211ec9e08` |
| Yenikapi-Early-Settlement-Foundation-Models-0.6.0.zip | 43556451 | `5141b82e8b693b3956175d92e3da997b6c9f7322c1471cfcb23daafd0d2e32ee` |
| Yenikapi-Early-Settlement-Contact-Models-0.6.0.zip | 21913878 | `7d0e2ad1830c07d21065ed78988b1cb266d23858766af02bb568c18a0b0bbdb0` |
| Yenikapi-Early-Settlement-Household-Models-0.6.0.zip | 2736899 | `a97b4b50101742c7efebd3a947e83d487b110ad4e0b62b6661769b5221f60140` |
| Yenikapi-Early-Settlement-Asset-Models-0.6.0.zip | 1460163 | `c805ea1cbbe36f3ff774ab29ac13b96eba5f38b9f05035aa81781f59da386260` |
| Yenikapi-Early-Settlement-Land-Models-0.6.0.zip | 40375868 | `c84b60e0b12ad46ae88de040da5d085e620dca0df05cd36fa77727ba883e6a7e` |

QA directory (outside git): `/var/folders/31/vy1_xpsn5p58y89s48qrckcm0000gn/T/yenikapi-0.6.0-exact-qa-7q37a6ow`.
Verification logs: `build/yenikapi-early-settlement-0.6.0-final/verification/`.
Public download verification follows.


## Public publication and preservation

Published **2026-10-06T01:28:29Z** as
[Yenikapı Early Settlement 0.6.0 — Land, Growth, and Lasting Consequences](https://github.com/zhynek/Roman-War/releases/tag/yenikapi-early-settlement-v0.6.0).
Release ID `404219295`, tag `yenikapi-early-settlement-v0.6.0`, prerelease true,
draft false. Its target is frozen payload `b97106278e96d3561df63de800d2fc89edeebbd1`;
main additionally carries the verification and publication record. All nine
uploads matched local size and GitHub digest before publication.

All **nine public files** were then downloaded through ordinary unauthenticated
HTTPS requests. Every byte count and SHA-256 matches the tested local artifact
and GitHub digest; all seven downloaded ZIPs pass integrity checks, and all eight
checksum-manifest entries match. The public Mac ZIP is therefore the exact app
that passed the gates, and the source/model ZIPs are the tested frozen exports.
The two manifest files have these identities:

- `provenance.json`: 81490 bytes, SHA-256 `cbc70a04d3cee304db2ba6ab2bec52cb74d17e00e02ef880afd5c68a22c6b3c0`.
- `SHA256SUMS.txt`: 884 bytes, SHA-256 `dc37ab46b874bbb7309bddcdc53581b4ec316a394b6f5dd12208482f27ee089f`.

All **11 previous releases** retain their IDs, tags, names, bodies, prerelease
status and every asset's ID, name, size, digest, timestamps and download URL.
The stable latest endpoint still returns **`v0.14.2`**. No older release was edited
or replaced. Medieval creative saves and village/campaign user saves were not
opened or overwritten; QA used explicit temporary save paths.

Public verification artifacts/logs: `/tmp/yenikapi-public-0.6.0/verification.json`
and `/tmp/yenikapi-0.6-public-verification.log`. Earlier release metadata and
protected-file hashes were captured before implementation and compared afterward.
