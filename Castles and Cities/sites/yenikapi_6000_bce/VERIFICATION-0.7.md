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
7.805 ms, adaptation commission 649.584 ms, priority 103.231 ms, unchanged reserve
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

Frozen exact-application gates, retained model bytes and public downloads are
verified after packaging below. This sentence does not assert publication.
