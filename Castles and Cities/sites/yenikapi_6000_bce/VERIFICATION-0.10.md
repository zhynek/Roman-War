# Buildings That Show Their Work — 0.10.0 verification

Baseline: fetched `origin/main` at
`257fb72149a9db3d05cab079a5c640175231f4c1`, the published 0.9.0 village.
Version 0.10.0 was unused. The fifteen prior releases and their assets were recorded
in `/tmp/yenikapi-0.10-releases-before.json`; stable latest was `v0.14.2`.
Unrelated city-lifecycle draft work was preserved outside the feature commit.
The release is frozen from an isolated clean checkout of committed feature source.

## Boundaries and acceptance

The saved queue and completed IDs still own projects. Existing asset initiatives
own staffing, priority and pause, with the existing finite allocator, payment and
refund rules. No core, balance, wrapper, household relationship, historical claim,
dated reference or previous release is intentionally changed. Portable board/easel
furniture is an explicit gameplay interpretation in the existing working room.
There is no new facility benefit, delivery economy or construction damage system.

The construction read model, site meshes, matching picking/collision, small status
marks and room plans derive from those records. The dock, exact site and enlarged
easel all open `visual_commands.gd`'s project review and public command boundary.
Actual original occupied buildings also select their ongoing adaptation. Pausing
preserves the partial geometry and investment; only explicit seasonal resolution
can add forecast work. Cancellation uses the unchanged unused-fraction refund.

The construction checks cover all quarter stages, actual assigned citizens,
intermediate saves, old manual-workforce forecasts, authority, finite competing
crews, zero staffing, missing prerequisites, disabled access, both active/paused
incident lifecycles and deterministic replay. Completed geometry is compared with
a fresh build object-by-object. Citizen routes are walked through actual collision.
Retained rendered suites cover complete compact/outward development.

The new real-input walkthrough begins with ordinary resources. It commissions
through board → selected easel → enlarged controls, then changes the same project
through overview and physical site, saves/loads partial work, pauses/resumes, reaches
completion, compares competing investments, cancels legitimately, inspects a blocked
outer home, and checks 1024×768 controls. Both incidents are resolved with active
and paused projects after pre-incident saves, then replayed and loaded after the
outcome. Screenshots include landscape, aerial, street and working-room interiors.
No progress, resources or completed work are injected into these scenarios.

## Findings during development

Numeric-equivalent footprint arrays from authored JSON and canonical saved records
were comparing unequal, forcing needless world replacement. Explicit numeric
footprints fix that. Real footprint changes now patch local terrain triangles and
reuse unchanged buildings. Route caches are retained only after height/collision
revalidation. New terrain vertices must extend tangent arrays too; an early render
caught and corrected that mismatch. Exact cold-build face comparisons guard the
result. Finite authored building changes append a small number of terrain vertices;
this is not an unlimited terrain editing API.

Room inspection caught tiny plan labels, an edge-on easel and clipped controls;
these were corrected. The acceptance harness originally assumed the care project
would finish during winter, despite the allocator correctly forecasting zero work.
It now records that shortage and waits for actual completion. Native/deferred UI
events exposed stale test-control references; clicks now use atomic pointer input
and re-find controls, retrying only when no command or state change occurred.
Failed development runs are not release acceptance.

## Before-edit profiling

Exact 0.9.0 Mac application, Godot 4.4.1, Apple M3 Max, Metal 3.2 Forward+,
1600×1000, measured before source changes. Times include the callback and two
rendered settling frames; these are local samples, not guarantees.

| Existing visual-profile operation | Ready time |
|---|---:|
| Select a place | 37.987 ms |
| Cached project model | 19.461 ms |
| Compare growth | 38.009 ms |
| Change priority | 53.149 ms |
| Adaptation-completion season | 3,061.817 ms |
| Fresh living season | 670.770 ms |
| Ordinary season in that sequence | 189.971 ms |

Logs: `build/yenikapi-0.10-baseline/visual-profile.log` and
`detail-corrected.log`. A separate diagnostic measured authoritative resolution at
0.993 ms and showed route rebuilding dominating scene refresh. New planning-room
operations did not exist in 0.9.0, so no fabricated pre-feature timings are given.
The new profile records each required site, oversight, board, easel, comparison,
staffing, priority, pause/resume, seasonal, completion and route operation.
Exact-package measurements and final acceptance/public byte results are appended
after the frozen build. No Intel performance or Developer ID notarization is claimed.


## Source candidate and parent acceptance

Initial feature candidate: `0f44d23`. Source validation and all retained suites pass
**13,001 assertions**, including **841 construction checks**. The final normal-stock
construction input sequence passed **661 checks / 33 captures**. Parent data
validation reports zero errors/warnings; import, all **705 tests**, and the rendered
map playtest pass. Planning, marching, arrival and maximum zoom were inspected.
Every log was scanned for script errors independently of exit status.

Logs are under `build/yenikapi-0.10-source-gates/` and
`build/yenikapi-0.10-parent-gates/`; source screenshots are outside the repository
at `/tmp/yenikapi-construction-final-source/` and `/tmp/yenikapi-0.10-parent-map/`.
The clean release source is `/tmp/yenikapi-0.10-release-source/`. Source UI
inspection covered all 33 views; exact packaged acceptance remains the release gate.

A final coexistence review separated two workroom adaptations onto opposite sides
of the retained building, and incident preparation/repair displays along their
shared site edge. Their positions depend on stable identity, never queue order,
so later commissioning cannot move a paused project. Five additional checks prove
coexisting workroom displays are distinct and individually selectable (846 total
construction checks); the rendered gate adds their normal-stock coexistence view.
The first candidate build was stopped before publication and superseded.


## Exact universal Mac acceptance

Frozen payload `60d91066975e1143252ce24a4fe34bf40d082664`, built as **0.10.0**. Both source and the exact
application pass **13,006 assertions**, including **846 construction checks**.
The bundle contains `arm64` and `x86_64` and passes `codesign --verify --deep
--strict`. It is ad-hoc signed, not Developer ID notarized. The dated reference
mesh hash remains `7f1edbf6ec717d61357b58ffd2237806139cdb59950b9fe5c18c16ee172c689a`.

| Exact-app rendered suite | Captures | Checks | Failures |
|---|---:|---:|---:|
| asset | 12 | 477 | 0 |
| construction | 34 | 672 | 0 |
| household | 12 | 714 | 0 |
| incident | 25 | 676 | 0 |
| land | 19 | 918 | 0 |
| living | 21 | 839 | 0 |
| neighbor | 10 | 58 | 0 |
| reference | 14 | — | 0 |
| tutorial | 12 | 85 | 0 |
| visual | 26 | 392 | 0 |

All **185 captures** were inspected, with full-size review of the new plan,
site-stage and small-window controls. Every retained layout, path, interior and
new construction/incident sequence passes. Screenshots are outside the repository:
`/var/folders/31/vy1_xpsn5p58y89s48qrckcm0000gn/T/yenikapi-0.10.0-exact-qa-2tqskzy2`.
Logs, benchmark JSON and local/public artifact checks are in
`build/yenikapi-early-settlement-0.10.0-final2/verification/`.

## Exact-app responsiveness

Same local Apple M3 Max / Metal 3.2 / 1600×1000 procedure as the baseline.
Callback time is synchronous work; readiness includes two rendered frames.
No competing Godot process ran during these samples.

| New construction operation | Callback ms | Ready ms |
|---|---:|---:|
| select site | 14.624 | 45.448 |
| central oversight | 16.241 | 101.791 |
| enter room | 2.546 | 33.506 |
| select board plan | 1.158 | 32.752 |
| enlarge easel | 38.356 | 68.856 |
| compare project | 37.365 | 68.260 |
| crew limit | 47.539 | 82.551 |
| priority | 6.821 | 35.801 |
| pause | 20.292 | 51.716 |
| resume | 20.318 | 51.093 |
| construction season | 835.556 | 867.708 |
| new building completion | 1410.565 | 1451.526 |
| adaptation completion | 512.691 | 546.293 |
| ordinary season | 469.134 | 499.288 |

| Retained comparable visual-profile operation | 0.9 ready ms | 0.10 ready ms |
|---|---:|---:|
| select place | 37.987 | 33.218 |
| preview cached | 19.461 | 36.547 |
| compare growth | 38.009 | 39.096 |
| priority | 53.149 | 78.454 |
| commission | 226.352 | 509.452 |
| completion season | 3061.817 | 667.616 |
| fresh living season | 670.770 | 150.420 |
| ordinary season | 189.971 | 173.348 |
| open | 1240.588 | 1194.289 |

The comparable adaptation completion is 78.2% faster in this sample.
This is not a claim that every operation improved: commissioning now creates real
site collision and routes, and its measured delay increased. New-building
completion still takes 1.45 seconds. Its citizen refresh
takes 0.81 seconds, including 0.69 seconds in journeys;
these are presentation costs, not authoritative seasonal work. Static inspection
and plan controls remain much cheaper. Intel performance has not been measured.

## Artifact preservation

All 36 prior GLBs are byte-identical to 0.9.0; five new Construction specimens
bring the total to 41. Ten ZIPs pass integrity checks. Every file in the editable
source archive matches the frozen source hash map. Parent core/data, medieval
Constantinople, dated village data, village core and save reader are identical
Git objects to the baseline. Twelve artifacts are published as the separate village prerelease. Public byte
verification and prior-release preservation are recorded below.


## Public release and preservation

The [0.10.0 prerelease](https://github.com/zhynek/Roman-War/releases/tag/yenikapi-early-settlement-v0.10.0) is public. Its tag pins the exact tested payload
`60d91066975e1143252ce24a4fe34bf40d082664`; main also records final acceptance
and publication. All **12 artifacts** were downloaded anonymously and match
local SHA-256 hashes, sizes and GitHub digests. All **10 ZIPs** pass integrity
checks; every entry in the downloaded checksum manifest matches its file.

All **15 previous releases / 97 assets** retain their metadata, identities and
digests (download counters excluded). The parent campaign's stable latest remains
**v0.14.2**. The frozen-source comparison, retained GLB comparison and public
verification reports are in the build's `verification/` directory. The downloaded
files are at `/tmp/yenikapi-0.10-public-downloads/`. No old archive, dated reference,
medieval city or save contract was replaced. Unrelated city-lifecycle drafts remain
uncommitted and untouched.

| Public artifact | Bytes | SHA-256 |
|---|---:|---|
| `SHA256SUMS.txt` | 1,250 | `c588d76702550a978a7329e3695b69020f55f0cd9c58d76ec734ddf153588092` |
| `Yenikapi-Early-Settlement-Asset-Models-0.10.0.zip` | 1,460,205 | `594ed8b1e98d3bad772f71843a8fc9de5a655df29bde49fc95cd205067efe626` |
| `Yenikapi-Early-Settlement-Construction-Models-0.10.0.zip` | 437,808 | `d55df3f7cb6564eb111e423bfafa9dd981e64f8c8e85233c4c0aec7cdec85803` |
| `Yenikapi-Early-Settlement-Contact-Models-0.10.0.zip` | 21,913,893 | `ad77259bf1d89653e340a67943d1a68490583c18fe1257222ff11c2035582907` |
| `Yenikapi-Early-Settlement-Foundation-Models-0.10.0.zip` | 43,556,467 | `efdda314bbefafe76d701ad6cb77ce903a1960439973cb6dd60b32f01ae5dc73` |
| `Yenikapi-Early-Settlement-Household-Models-0.10.0.zip` | 2,736,923 | `fd5af3a96fe5e81ea7fa54f68a1c24a634f31840ab48ab241f3ef431634100aa` |
| `Yenikapi-Early-Settlement-Incident-Models-0.10.0.zip` | 20,445 | `f1a92a66675ca47540994ef359db3f9e4d7fdcc481fbba1b7c08faedae9e3435` |
| `Yenikapi-Early-Settlement-Land-Models-0.10.0.zip` | 40,375,897 | `45fd0497f937c70e9d0c8194f653034a852f937314555ceefa583be101ad5346` |
| `Yenikapi-Early-Settlement-Living-Models-0.10.0.zip` | 20,610,371 | `1b9d12f18eb69a104312dbc2f1347677b32092dcd2afda939e45a6cbacc8212e` |
| `Yenikapi-Early-Settlement-Source-0.10.0.zip` | 693,688 | `ba93f7ab640c32e5b329509fa8d6346ce6c842d8a91ac90cb9a67fb028d02045` |
| `Yenikapi-Early-Settlement-macOS-0.10.0.zip` | 58,851,669 | `67a23a094868a6c5c320203ba9cfbbb81fe5fc76bee014de9096e549dbcf9def` |
| `provenance.json` | 105,650 | `c1e101173b1ecb9ec6d7c1114105198931d31acaaf2255d1391bf967d05cf3ba` |
