# Early settlement 0.1.0 — release verification

Verified October 4, 2026. The release payload is frozen at
`b4c7e8a5997993f14065225515d4b41ba9feab4d`; later documentation commits record
the results without changing those application, model or source ZIP bytes.
The separate tag is `yenikapi-early-settlement-v0.1.0`.

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
