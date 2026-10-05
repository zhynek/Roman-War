# Household life 0.4.0 verification

Frozen payload: `797c8ef2204d80237d46075a91498433c60b9f13`. Built 2026-10-05T13:09:44.011949+00:00.
The separate early-settlement prerelease adds an optional, hypothetical eight-season
warning, restricted movement, recovery and learning chapter. It does not claim
an excavated siege, a documented army or a historical cultural revolution.

## Gates and actual rendering

- Parent data validation: zero errors; import and full **705 tests** passed.
  Both stdout and stderr were scanned for Godot errors, including exit-zero failures.
  Actual planning, marching, arrival and maximum-detail map views were inspected.
- Source and **exact universal Mac app**: **248 reference + 707 governance +
  302 neighbor + 310 household = 1,567 checks** passed per application.
  Negative data groups: 14 reference, 22 governance, 5 contacts and 7 households.
- Exact-app rendered acceptance: **85 original tutorial + 58 contact + 714
  household checks** passed. All **48 captures** were inspected: 14 reference,
  12 town tutorial, 10 contact and 12 household views. Controls fit 1600×1000 and
  1280×800; actual mouse input opens the chapter, applies preparations, resolves
  seasons, visits activities and selects a visible resident through the world.
- Household routes were tested at warning, danger, recovery, renewal and settled
  stages, plus the grown settlement with active contacts. Every living citizen is
  represented, with children outside the workforce and stationary wrapped infants.
  Door traversal and every route segment use actual walking collision. Indexed
  navigation was compared against the player's collision; overlay cleanup and
  repeated refresh retain the expected collision count. Animation cannot change state.
- Save tests cover wrappers 1/2 with missing inactive fields, wrapper 3 households
  with and without contacts, exact resume, strict malformed nested state and
  replay. Learning and safe-route benefits require actual available labor/capacity.

The first visual pass exposed a crowded care room and oversized head details;
these were corrected with reserved resting slots, a bounded shared-care group,
activity-facing figures and solid character geometry. QA pointer dispatch checks
state changes before retrying an unreceived native input, so tests cannot issue a
second successful order or advance an extra season. The first package was rejected
after missed synthetic pointer input and dark material groups in background-window
captures. Explicit pointer motion and actual rendered settling frames corrected
the capture tools. One fresh tutorial image still showed a partially initialized
material group, so that complete 12-view exact-app run was repeated with
`--max-fps 10`, allowing at least 1.2 seconds of drawn settling frames per image.
The replacement set passed the same 85 checks and was inspected again. Original
captures and both logs were retained. The app/archive bytes and uncapped performance
measurements were unchanged. Citizens remain stylized;
there is no individual inventory, dialogue, tactical siege AI or general evacuation.

## Performance

Godot 4.4.1, Forward+, **Apple M3 Max (Apple9)**, 1600×1000. VSync disabled;
120 warmup + 180 measured intervals per camera, exactly one forced draw per
interval. Screenshot readback is excluded. Benchmarks ran sequentially without
another Godot renderer. The household sample has 30 animated citizens in danger.
These are observations on one Apple Silicon machine, not hardware requirements.

| View | Source median / p95 ms | Exact app median / p95 ms |
|---|---:|---:|
| Landscape | 8.338 / 9.095 | 7.217 / 15.308 |
| Aerial | 8.315 / 14.845 | 8.011 / 13.600 |
| Street | 7.864 / 14.733 | 8.330 / 9.862 |
| Interior | 8.089 / 12.948 | 8.291 / 12.452 |

Exact-app initial reference startup was 4.06s;
fully prepared household-world readiness including rebuilding and route planning
was 11.01s from process start. First
route planning can pause the interface for several seconds; unchanged geometry
retains its route/cache data. All reference/town/contact measurements are also
recorded in release provenance. Intel code is included; Intel rendering/performance
was not measured. The app is ad-hoc signed, not Developer ID notarized.

## Preservation and artifacts

All **624** protected parent campaign and Constantinople files match starting
main `6fc347d3c580e768e974821ca74dbb9508cb5885` byte for byte. The dated village mesh retains
`7f1edbf6ec717d61357b58ffd2237806139cdb59950b9fe5c18c16ee172c689a`.
The old 21-season town tutorial and 27-season contact chapter remain intact.
All **18 previous GLBs** are byte-identical; six new hypothetical furnished-room
GLBs show three interiors at danger and renewal. All 24 models pass structural
and buffer validation. Five ZIPs pass integrity and model partitions match raw
exported bytes: Mac application, editable source, Foundation Models (16), Contact
Models (2) and Household Models (6). Provenance and SHA256SUMS accompany them.
Neutral GLB materials do not reproduce app lighting/shaders or citizen animation.

Build: `build/yenikapi-early-settlement-0.4.0-final/`.
External QA: `/var/folders/31/vy1_xpsn5p58y89s48qrckcm0000gn/T/yenikapi-0.4.0-exact-qa-b_5ap1we`.
Parent logs: `build/yenikapi-parent-gates-0.4.0/`.
No QA image is a repository asset. Public download verification appears below;
prior release bytes must not be replaced.

## Public download verification

Published [Household Life 0.4.0](https://github.com/zhynek/Roman-War/releases/tag/yenikapi-early-settlement-v0.4.0) as a separate prerelease,
never latest, targeting the frozen payload. Verified 2026-10-05T13:27:03.329560+00:00.
All seven URLs were fetched anonymously after publication; their bytes match
local files, GitHub digests and the checksum manifest. All five ZIPs pass integrity.
All nine earlier release IDs/assets/digests and latest stable `v0.14.2` are unchanged.

| Download | Bytes | SHA-256 |
|---|---:|---|
| [provenance.json](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.4.0/provenance.json) | 87050 | `b4225f13f8a6d1e1037172f618dff00ba5799d5d9ae94e91e681836114210269` |
| [SHA256SUMS.txt](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.4.0/SHA256SUMS.txt) | 655 | `5a0e14ccb784d9daa55dc01b2eb2dcfe43c415efc6bd5ea7538aaad587f41561` |
| [Yenikapi-Early-Settlement-Contact-Models-0.4.0.zip](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.4.0/Yenikapi-Early-Settlement-Contact-Models-0.4.0.zip) | 21913870 | `dabf200256aa179555483b1cbe2c99a3993af7d53a930ecf2543207a7611d79e` |
| [Yenikapi-Early-Settlement-Foundation-Models-0.4.0.zip](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.4.0/Yenikapi-Early-Settlement-Foundation-Models-0.4.0.zip) | 43556443 | `ed9e0aed5d7ab04538db3285a9824c48091c94d300e3ab57278f546cec177eaa` |
| [Yenikapi-Early-Settlement-Household-Models-0.4.0.zip](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.4.0/Yenikapi-Early-Settlement-Household-Models-0.4.0.zip) | 2736877 | `ea42f2c9e34d83982b88440b22ef82bd19ec5d142bcaf18ddf17ee0cac6bda58` |
| [Yenikapi-Early-Settlement-macOS-0.4.0.zip](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.4.0/Yenikapi-Early-Settlement-macOS-0.4.0.zip) | 58542037 | `09285aed5bfb7714febfaa306901332c35168258b1922da415364d9166ca3ba0` |
| [Yenikapi-Early-Settlement-Source-0.4.0.zip](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.4.0/Yenikapi-Early-Settlement-Source-0.4.0.zip) | 446354 | `91802fe6003fe9f39c6342bd3762efa58197be8828778ccebbd292289403affb` |
