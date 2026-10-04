# Early settlement 0.1.0 — release verification

Verified October 4, 2026. The release payload is frozen at
`b4c7e8a5997993f14065225515d4b41ba9feab4d`; later documentation commits record
the results without changing those application, model or source ZIP bytes.
The separate tag is `yenikapi-early-settlement-v0.1.0`.

## Publication and downloads

The [prerelease](https://github.com/zhynek/Roman-War/releases/tag/yenikapi-early-settlement-v0.1.0)
is public. Its tag resolves to the frozen commit above. All five actual public
browser download URLs were downloaded anonymously after publication; GitHub's
asset digests, local package hashes and the downloaded checksum manifest match.
The three downloaded ZIPs pass integrity checks. The Mac archive is therefore
byte-identical to the exact application package tested below.

All six pre-existing releases retain their release IDs, prerelease flags and
asset IDs/names/sizes/SHA-256 digests. The latest stable release remains
`v0.14.2`; Constantinople `v0.3.0` retains all five original download assets.
The local publication report is `verification/publication.json` in the build
directory. The initial concurrent upload failed with a TLS transport error;
GitHub removed the incomplete attempt. The final publication used a draft,
sequential HTTP/1.1 uploads and digest verification before becoming public.

## Gates and preservation

- Closed data schema and all **14 data regression cases** pass.
- Source and the **exact exported Mac application** each pass **248 checks**:
  all nine entrances/exits, swept wall collision, picking, continuous routes,
  terrain agreement, keyboard navigation, safe flight landing, deterministic
  geometry, explicit lineage and real bookmark saves/invalid-save rejection.
- Source/package mesh hash agrees:
  `7f1edbf6ec717d61357b58ffd2237806139cdb59950b9fe5c18c16ee172c689a`.
- Parent data and Godot import are clean; the full campaign suite passes
  **705 tests, zero failures**. Planning, marching, arrival and 40× map renders
  were inspected. Combined stdout/stderr logs were checked for script errors.
- The retained Constantinople neighborhood passes **374 checks, zero failures**.
  All 54 tracked medieval experience files match the starting `48a50b8` baseline
  byte for byte, including data, creative-save logic and export configuration.
- Universal `arm64`/`x86_64` application structure and ad-hoc signature pass.
  All **10 GLB containers**, **three ZIPs** and artifact SHA-256 hashes pass.

The local full-suite pass above is distinct from hosted Linux CI. The starting
main baseline's [CI run](https://github.com/zhynek/Roman-War/actions/runs/37225845821)
failed the existing campaign-turn speed assertion at 603 ms average. No campaign
engine, timing threshold or CI configuration is changed by this village work.

## Render inspection

All 14 exact-app captures were inspected: arrival controls, landscape, aerial,
plan, shared yard, dwelling interior, working interior, storage interior,
round dwelling, stream landing, cultivation, roof construction, evidence pane
and the 1280×800 interface. Interior captures enter through the same collision
controller used by walking. The source's corresponding 14 views were also
inspected. QA images remain outside the repository, not among game assets.

The package captures are in the external directory recorded by the downloadable
`provenance.json`. Local build logs, raw measurements and preservation hashes
are under `build/yenikapi-early-settlement-0.1.0-publish/verification/`.
Parent map images are in `/tmp/yenikapi-parent-map`; source captures are in
`/tmp/yenikapi-final-qa`. Temporary paths are local QA records, not durable links.

## Measured performance

Godot 4.4.1, Apple M3 Max (Apple9), 1600×1000. Each view uses 120 warmup frames
then 180 process-frame samples, VSync disabled, no screenshot readback, with
source and package measured separately. Startup: source **4.811 s**, exact app
**4.014 s**. These are local observations, not general performance guarantees.

| View | Source median / p95 ms | Exact app median / p95 ms | App draw calls |
|---|---:|---:|---:|
| Landscape | 8.292 / 9.352 | 8.320 / 9.107 | 361 |
| Aerial | 8.323 / 9.133 | 3.156 / 4.117 | 526 |
| Street | 8.376 / 9.166 | 2.647 / 3.427 | 296 |
| Interior | 8.324 / 9.226 | 2.612 / 3.387 | 568 |

Frame pacing varied across successive local runs, including near-8.3 ms pacing.
The source/package difference is not evidence of an optimization or a portable
speedup. Intel code is included but Intel rendering was not exercised locally.

## Scope and remaining work

The evidence ledger separates site archaeology, regional comparison and authored
interpretation. The nine buildings/six households are content counts, not a
recovered plan or population estimate. No uninterrupted settlement genealogy is
asserted. There is no growth UI or later settlement stage; the deterministic
lineage resolver is tested with hypothetical fixtures only.

The art is stylized procedural geometry. People, animals, animated crafts,
sound, farming mechanics, water simulation and species/season reconstruction
remain unfinished. Neutral-material GLBs omit application shaders and navigation.
The app is ad-hoc signed, **not Developer ID notarized**. Its independent version-1
view bookmark does not read, migrate or rewrite medieval or campaign saves.
