# Governing the village 0.5.0 verification

Frozen payload: `7d7de8dc3828a2cc1797fae34bbd909b1ab2c0c3`.
Built 2026-10-05T14:25:22.509910+00:00 from clean main, starting at
`6cd651ddee7d9d06fa219b14eef15730fe5a62a6` after fetching origin.
This separate early-settlement prerelease adds explicit asset governance to the
hypothetical village. Its offices, grouped assets, principles and authored danger
remain gameplay interpretation. No new archaeological institutional claim is made.

## Gates and actual rendering

- Parent data: zero errors. Godot import and the full **705 tests** pass. Actual
  planning, marching, arrival and maximum-zoom map captures were inspected.
- Frozen source and **exact universal Mac application** each pass **248 reference
  + 708 governance + 302 neighbor + 310 household + 608 asset = 2,176 checks**.
  Schema/reference validation passes; negative data groups contain 14 reference,
  22 governance, 5 contact, 7 household and 11 asset cases. Catalog: two studies,
  zero errors. Logs include stdout and stderr and were scanned for script errors
  even where Godot returned zero.
- Exact-app rendered acceptance passes **85 tutorial + 58 contact + 714 household
  + 477 asset = 1,334 checks**. All **60 captures** were visually reviewed:
  14 reference, 12 tutorial, 10 contact, 12 household and 12 asset views. These
  include landscape, aerial, street, ordinary and pressure interiors, recovery,
  construction, asset panels and controls at 1600×1000 and 1280×800.
- The asset guide uses actual viewport clicks, shared commands and finite initial
  stocks. It commissions cultivation, compares the exact forecast with the report,
  prepares care/stores/routes, handles pressure and learning, coordinates access
  and two homes, finishes growth readiness, saves/resumes and opens the same store
  management panel through actual world picking. It finishes at turn 11 with
  continuing choices; guide completion is not a new town threshold.
- Additional exact-app inspection passes seven checks with four external captures:
  paid north housing at 13/24 work, a workroom repair crew after six ordinary
  seasons of wear, the improved room after resolution, and an explicitly synthetic
  zero-stock rendering fixture. Construction/repair use ordinary commands and
  finite stocks; the zero-stock fixture is only a visual boundary check, not a
  tutorial resource change. No packaged bytes were modified for this inspection.
- Rule checks exercise exclusive adult work, competing crews, priorities, pause,
  cancellation/refunds, blocked costs, reserve tradeoffs, neglect and recovery,
  leader authority/succession, neighboring carriers/escorts, sustainable town
  growth, 100-season JSON replay and forecast/outcome identity. Older inactive
  wrappers 1/2/3 retain manual strategy. Wrapper 4 retains projects, principles,
  author attribution, household memories and exact allocation on resume.
- Actual routes and every segment share walking collision; all tested citizens
  have reachable stations. Camera changes and different animation deltas cannot
  mutate authoritative state. Animation remains presentation. The old town,
  contacts and household chapters continue to pass their original flows.

Development capture checks caught a QA tab-transition retry and a physical versus
logical window-size comparison; both were corrected before freezing. Screenshot
runs use a 10 FPS cap to allow background Metal material readiness. Benchmarks
remain uncapped. No final rendered gate failed. All QA images are outside git.

## Performance and remaining limits

Godot 4.4.1 Forward+, Apple M3 Max (Apple9), 1600×1000, 36 animated citizens in the
asset scenario. VSync disabled; 120 warmup and 180 measured frame intervals per
camera, one forced draw each, screenshot readback excluded. Source and exact-app
benchmarks ran sequentially without a competing Godot renderer.

| View | Source median / p95 ms | Exact app median / p95 ms |
|---|---:|---:|
| Landscape | 8.155 / 12.620 | 8.445 / 9.007 |
| Aerial | 8.286 / 12.040 | 8.244 / 9.147 |
| Street | 8.293 / 9.409 | 8.462 / 9.103 |
| Interior | 8.340 / 9.039 | 8.296 / 9.154 |

Exact-app initial reference startup: **4.288 s**. Preparing the asset sample,
including rebuilding the world and routes, took **11.814 s from process start**.
The actual UI acceptance run measured **13.582 s** to open readiness, including
scripted input/frame waits; it is not a pure startup measurement. Changing a
reserve order in the completed guide took **1.194 s**, unchanged refresh **0 ms**,
and forced route rebuilding **276 ms**. These are single-machine observations,
not hardware requirements or a claim of stall-free interaction. Relevant-state
fingerprints retain unchanged routes/geometry; cached citizen templates avoid
reconstructing identical meshes. First scene construction and changed orders can
still pause the interface. Intel architecture is included but its rendering and
performance were not measured. Signing is ad hoc, not Developer ID notarization.

Citizens remain stylized. Asset condition is grouped, not per wall. Seasonal
accounting has no item-by-item hauling, individual civilian commands or tactical
combat. Crowd avoidance, general evacuation, possession, dialogue and regional
warfare remain unfinished. Household practices remain heterogeneous. Authored
danger ends by chapter transition, never a simulated military victory.

## Preservation and artifacts

All **641** protected parent campaign/Constantinople files retain their starting
bytes. The dated village data and mesh are unchanged; mesh hash:
`7f1edbf6ec717d61357b58ffd2237806139cdb59950b9fe5c18c16ee172c689a`.
All **24 previous GLBs are byte-identical**. Three new hypothetical asset specimens
(stocked store, empty store, repairing workroom) bring the total to **27** across
Foundation (16), Contact (2), Household (6) and Asset (3) archives. GLB structural
and buffer checks pass. All six ZIPs pass integrity; model partitions match raw
exports. Mac application and editable source complete the six archives.
Provenance and SHA256SUMS accompany them. Neutral GLBs omit app shaders, lighting,
simulation and animation. No earlier release bytes are replaced.

Build and logs: `build/yenikapi-early-settlement-0.5.0-final/`.
Main QA: `/var/folders/31/vy1_xpsn5p58y89s48qrckcm0000gn/T/yenikapi-0.5.0-exact-qa-ws2wq5a1`.
Additional QA: `/tmp/yenikapi-0.5-asset-detail`, driven by
`/tmp/yenikapi-asset-detail-qa.gd` against the extracted exact app.
Parent gates: `build/yenikapi-parent-gates-0.5.0/`; map QA:
`/tmp/yenikapi-0.5-parent-map`.

Public verification is recorded after publication below. The release target is
this frozen payload; subsequent documentation commits do not change the archive.

## Public download verification

Published [Governing the Village 0.5.0](https://github.com/zhynek/Roman-War/releases/tag/yenikapi-early-settlement-v0.5.0) as a separate prerelease,
never latest, targeting the frozen payload. Verified 2026-10-05T14:57:24.719779+00:00.
All eight URLs were fetched anonymously after publication and match local tested
bytes, GitHub digests and the checksum manifest; all six ZIPs pass integrity.
All 10 earlier release IDs, asset IDs, names, sizes, digests and download URLs
remain unchanged. Stable latest remains `v0.14.2`.

The initial concurrent upload returned a duplicate-name response after accepting
four correct files. Their digests were checked before uploading only the missing
files. No uploaded or previous release asset was overwritten.

| Download | Bytes | SHA-256 |
|---|---:|---|
| [provenance.json](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.5.0/provenance.json) | 71897 | `5b46010f1aecff23bb99e8a8a3d315766be66020011d302a419c2b8cd3512769` |
| [SHA256SUMS.txt](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.5.0/SHA256SUMS.txt) | 770 | `d4a1ab0dd1715ba64499b25100bc347fbde1240d259bc643742bcff473218351` |
| [Yenikapi-Early-Settlement-Asset-Models-0.5.0.zip](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.5.0/Yenikapi-Early-Settlement-Asset-Models-0.5.0.zip) | 1460092 | `175c50a9df46cb01da3bbc689cda4d6f30de4e09b4fd6f489541839627ab28da` |
| [Yenikapi-Early-Settlement-Contact-Models-0.5.0.zip](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.5.0/Yenikapi-Early-Settlement-Contact-Models-0.5.0.zip) | 21913874 | `a9a20bac155aa4146389162a31a165623841707f70f20b23985f048fedf6440a` |
| [Yenikapi-Early-Settlement-Foundation-Models-0.5.0.zip](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.5.0/Yenikapi-Early-Settlement-Foundation-Models-0.5.0.zip) | 43556447 | `ef097e5a5a3cb6895eacb1c9780e34b678b2427b630ebca1e849b37559994ace` |
| [Yenikapi-Early-Settlement-Household-Models-0.5.0.zip](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.5.0/Yenikapi-Early-Settlement-Household-Models-0.5.0.zip) | 2736886 | `b8dccfd57aa3db9031ae86d0e7a8887d6a1b4fcdd6da18c494aa5b328e6b866b` |
| [Yenikapi-Early-Settlement-macOS-0.5.0.zip](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.5.0/Yenikapi-Early-Settlement-macOS-0.5.0.zip) | 58601101 | `3912d76043ad8f046d1c7a70705b109a50798db000c409f4bdb07bf5d247e4e1` |
| [Yenikapi-Early-Settlement-Source-0.5.0.zip](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.5.0/Yenikapi-Early-Settlement-Source-0.5.0.zip) | 488896 | `51e7c6aaf92914fbf024f7343b235b006a76250ed8d9b015e9537b01f0a0cd8c` |
