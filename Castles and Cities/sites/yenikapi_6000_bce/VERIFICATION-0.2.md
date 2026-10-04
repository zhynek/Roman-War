# Early Settlement 0.2.0 — seasonal tutorial verification

Verified October 4, 2026. The release payload is frozen at
`3fc10baa1af1f958ccef12fa532336a652b50a13`. Later documentation commits record verification
without changing the three frozen ZIPs. The separate prerelease tag is
`yenikapi-early-settlement-v0.2.0`.

## Publication and download verification

The [separate 0.2.0 prerelease](https://github.com/zhynek/Roman-War/releases/tag/yenikapi-early-settlement-v0.2.0)
is public, and its tag resolves to the frozen commit above. All **five public
browser download URLs** were downloaded anonymously after publication. GitHub's
asset digests, local tested files, downloaded SHA-256 manifest and ZIP integrity
checks agree. The downloaded Mac archive is byte-identical to the exact app
verified below. The [study README](README.md) links the app, models and source.

All **seven prior releases** retain their IDs, prerelease status and original
asset IDs/names/sizes/digests. Latest stable remains **`v0.14.2`**;
Constantinople 0.3.0 and the original early village 0.1.0 are preserved. Uploads
were sequential into a draft, verified by release ID before publication, then
verified again through the public links. Local evidence is
`build/yenikapi-early-settlement-0.2.0-final/verification/publication.json`.

## Gates and preservation

- Village and governance schemas pass, with **14 + 22 data regression cases**.
- Source and the exact universal Mac application each pass **248 reference checks**
  and **705 governance checks**, including 40-year deterministic save replay,
  succession, mortality, office permissions, household occupancy, project costs,
  cancellations, forecasts, negative inputs and population contraction.
- Both source and exact-app rendered tutorials pass **85 checks** through actual
  viewport clicks and public UI actions. The demonstrated town is reached in
  **21 seasons with 48 fictional residents**, eight dwellings and 13 buildings.
  All 13 entrances/exits and all seven curved paths remain navigable.
- Parent data/import and **705 campaign tests** pass. Actual planning, marching,
  arrival and maximum 40× map views were inspected. The retained Constantinople
  neighborhood passes **374 checks**.
- All **523 baseline campaign/medieval files**, including all 54 medieval experience
  files, match starting main `6db7f0e` byte for byte. The original village mesh hash
  remains `7f1edbf6ec717d61357b58ffd2237806139cdb59950b9fe5c18c16ee172c689a`.
- Universal `arm64`/`x86_64` structure and strict ad-hoc signature verification pass.
  All **16 GLB containers** and **three ZIPs** pass structural/integrity checks.
  The ten original village GLBs remain byte-identical to 0.1.0.
- Combined stdout/stderr logs were inspected, with no script errors. The parent
  suite emits its existing Control-anchor warning; it has no failed assertions.

The local campaign result is distinct from hosted CI. No parent campaign engine,
performance threshold or CI configuration is changed by this release.

## Rendered inspection

All **26 exact-app views** were inspected: 14 reference views covering the
landscape, aerial/plan, street, furnished dwelling/work/storage/round interiors,
landing, fields, roof construction, evidence and small-window interface; and
12 tutorial views covering introduction, guide, workforce, citizens, projects,
leadership succession, town milestone, journal/save resume, grown aerial, new
households, new interior and the 1280×800 controls. Seven final reference captures
and two tutorial captures are byte-identical to already inspected captures;
all other final captures were inspected directly. Source tutorial captures were also inspected.

The exact app restores the original nine-building reference and resumes the
13-building hypothetical town. Animation cannot mutate authoritative state.
Citizens are stylized original figures with local collision-aware movement,
not a full logistics simulation. Procedural building appearance is unchanged.
QA PNGs remain outside the repository under the temporary directory recorded in
`provenance.json`; these local paths are not durable public image links.

## Performance

Godot 4.4.1, Apple M3 Max (Apple9), 1600×1000. Each camera has 120 warmup intervals
and 180 measured intervals, one explicit draw per interval with the automatic
render loop disabled, VSync off, and screenshot readback excluded. Source and
exact app run separately, with no competing Godot process. This includes frame
pacing and animated citizens; it is not isolated GPU time or a portable FPS claim.

An initial benchmark could continue process frames while macOS suppressed redraws.
That result was discarded. The corrected frozen benchmark explicitly draws every
sample, records camera coordinates and reads fresh render counters. The final
measurements below use only that method; they should not be directly compared
with the earlier release's process-only timing method.

Reference village:

| View | Source median / p95 ms | Exact app median / p95 ms | App draw calls |
|---|---:|---:|---:|
| Landscape | 8.335 / 9.060 | 8.325 / 9.106 | 361 |
| Aerial | 8.317 / 9.207 | 8.307 / 9.224 | 526 |
| Street | 8.338 / 9.333 | 8.327 / 9.186 | 296 |
| Interior | 8.346 / 9.138 | 8.348 / 9.336 | 568 |

Hypothetical town, season 21, 48 residents and 30 animated workers:

| View | Source median / p95 ms | Exact app median / p95 ms | App draw calls |
|---|---:|---:|---:|
| Landscape | 8.271 / 8.978 | 8.273 / 9.028 | 857 |
| Aerial | 8.276 / 9.003 | 8.289 / 8.998 | 1220 |
| Street | 8.297 / 9.142 | 8.306 / 9.240 | 696 |
| Interior | 8.312 / 8.910 | 8.324 / 9.197 | 171 |

Reference startup: source **4.813 s**, exact app
**4.011 s**. Benchmark town ready (including startup,
21 simulated seasons and world construction): source
**11.155 s**, exact app
**9.239 s**. Intel code is included;
Intel rendering/performance was not exercised locally.

## Boundaries and remaining work

The dated circa-6000 BCE reference is preserved. The playable scenario uses
fictional people, offices, life-course rates, supply pressure and town criteria.
[SOURCES.md](SOURCES.md) distinguishes archaeological evidence, regional comparison
and game invention; [GOVERNANCE.md](experience/GOVERNANCE.md) documents the rules,
role tradeoffs, authoring interfaces and independent campaign save version 1.
No medieval bookmark, creative slot or parent campaign save is read or migrated.

Only one settlement and two offices are playable. There is no multi-town map,
trade/diplomacy, standing army or field-battle gameplay, arbitrary building
placement, later urban stage, calibrated population model or RPG possession.
Older buildings survive population contraction. Explicit demolition, abandonment
orders, general household subdivision and richer institutions remain future work.
The Mac application is ad-hoc signed, not Developer ID notarized.

## Artifact fingerprints

- `Yenikapi-Early-Settlement-macOS-0.2.0.zip` (58,436,358 bytes):
  `cb9fa1586e154f1d0bff7f9b0d66a9d9998a56ce8c9327c8fcf8bc21ecdc4615`
- `Yenikapi-Early-Settlement-Source-0.2.0.zip` (363,324 bytes):
  `6672592b11755b807e3a8a471f397b938163d87bd458f26c1fbfe906bfcb7b9b`
- `Yenikapi-Early-Settlement-Models-0.2.0.zip` (43,556,516 bytes):
  `c48b9cd00362f98333597af141415ff1527dc9cb171e507f5a49aa219e423b68`
