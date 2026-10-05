# Early Settlement 0.3.0 — neighbor contact verification

Verified October 4, 2026. Frozen payload commit:
`a7cd121467f576e8fdd587f8bc981755575a8a9e`. Later documentation commits record these results without
changing the frozen app, model or editable-source ZIPs.

## Gates and preservation

- Village, governance and contact schemas/cross-references pass; the data suites
  pass 14 reference cases, 22 governance cases and five contact test groups
  (including malformed community data, tuning, prose and chapter separation).
- Source and exact universal Mac app each pass **248 reference, 706 governance
  and 302 contact checks**. Contact coverage includes 80-season replay, finite
  two-sided escrow, crew costs, deterministic allowances, waiting, cancellation,
  authority, speaker succession, malformed extension fields and in-flight saves.
- Original rendered town tutorial: **85 checks, 12 captures**, town at season 21
  with 48 fictional residents. Contact tutorial: **58 checks, 10 captures**,
  chapter complete at turn 27. Actual viewport clicks exercise dispatch, season
  resolution, save/resume and small-window walking navigation. All 14 entrances/
  exits and eight curved paths pass; reference restoration returns nine buildings.
- Parent data/import, **705 campaign tests** and actual map playtest pass.
  Planning, marching, arrival and maximum 40× views were visually inspected.
  Combined stdout/stderr was scanned: no script errors or error diagnostics.
  The parent suite retains its existing Control-anchor warning.
- **624 campaign and Constantinople files** match starting main `9f08e86` byte
  for byte. The dated village mesh remains
  `7f1edbf6ec717d61357b58ffd2237806139cdb59950b9fe5c18c16ee172c689a`.
- Universal arm64/x86_64 structure and strict ad-hoc signature checks pass.
  All **18 GLBs** and **three ZIPs** pass structural/integrity checks. The prior
  **16 GLBs are byte-identical** to 0.2.0; the meeting room and hypothetical
  contact settlement are the only added GLBs.

Local results are separate from hosted CI. No parent campaign code, map
performance limit or CI configuration changed. Build logs, source preservation,
image hashes, measurements and artifacts are under
`build/yenikapi-early-settlement-0.3.0-final/`.

## Actual rendered inspection

All **36 exact-app captures** were reviewed: 14 reference, 12 original tutorial
and 10 contact views. Twenty-seven were inspected directly; seven reference and
two original tutorial captures match previously inspected 0.2.0 captures byte
for byte. Current contact views cover locked/active chapter, community ledger,
dispatch, resumed journey, completion, landscape, meeting-place street/interior,
and both upper and lower controls at 1280×800. The new room is furnished and
enterable; the approach joins the retained paths. Figures remain original stylized
procedural illustrations, not person-specific reconstructions or real-time cargo
agents. Animation cannot mutate authoritative state.

The initial source QA caught a simulated-click coordinate error after window
scaling. The harness now supplies viewport-local coordinates, per Godot's API;
the rerun and exact app pass. Source contact views were also inspected. QA PNGs
remain outside Git at `/var/folders/31/vy1_xpsn5p58y89s48qrckcm0000gn/T/yenikapi-0.3.0-exact-qa-q4b57fwm`; the
per-capture record is `verification/visual-review.json` in the local build.

## Performance

Godot 4.4.1, Metal Forward+, Apple M3 Max, 1600×1000, vsync disabled. Each camera
uses 120 warmup and 180 measured intervals, one forced draw per interval with the
automatic render loop disabled. Screenshot readback is excluded. No competing
Godot process ran during benchmark measurements. Intel rendering/performance
has not been measured; its executable architecture is verified.

### Dated reference

| View | Source median / p95 ms | Exact app median / p95 ms | App draw calls |
|---|---:|---:|---:|
| Landscape | 8.352 / 9.608 | 8.303 / 9.261 | 361 |
| Aerial | 8.312 / 9.441 | 8.240 / 9.456 | 526 |
| Street | 8.312 / 9.542 | 8.263 / 9.401 | 296 |
| Interior | 8.416 / 9.127 | 8.176 / 9.342 | 568 |

### Original hypothetical town

| View | Source median / p95 ms | Exact app median / p95 ms | App draw calls |
|---|---:|---:|---:|
| Landscape | 8.477 / 8.895 | 8.356 / 9.431 | 857 |
| Aerial | 8.407 / 9.425 | 8.363 / 9.305 | 1220 |
| Street | 8.261 / 9.345 | 8.153 / 9.437 | 696 |
| Interior | 8.220 / 9.407 | 8.125 / 10.057 | 171 |

### Contact settlement with animated workers

| View | Source median / p95 ms | Exact app median / p95 ms | App draw calls |
|---|---:|---:|---:|
| Landscape | 8.366 / 9.209 | 8.301 / 9.336 | 917 |
| Aerial | 8.283 / 9.251 | 8.266 / 9.506 | 1310 |
| Street | 8.271 / 9.277 | 8.185 / 9.620 | 707 |
| Interior | 8.451 / 8.830 | 8.359 / 9.350 | 1906 |

These are local measurements, not a hardware-independent frame-rate guarantee.
The contact interior uses the new meeting room; other modes retain their prior
camera definitions. Draw counts confirm that frames actually rendered.

## Evidence, saves and remaining work

The [evidence ledger](SOURCES.md) adds a regional Neolithic obsidian-exchange
comparison, explicitly not evidence for these local neighbors or barter terms.
Two fictional communities have finite stocks, reserve policies and speaker terms;
their modeled population is fixed and their villages are not explorable. General
regional diplomacy, warfare, demographic feedback in neighboring communities,
regional routes and further urban stages remain unfinished.

The dated reference is unchanged. Old seasonal saves gain inactive `contacts: {}`;
active-contact saves require wrapper version 2. Base rules and contact extension
are independently versioned at 1. Reserved cargo, remaining seasons, office terms
and stable community/mission identifiers survive exact replay. See
[GOVERNANCE.md](experience/GOVERNANCE.md) for the contract, original tutorial and
new chapter. Medieval creative and parent campaign saves are never migrated.
