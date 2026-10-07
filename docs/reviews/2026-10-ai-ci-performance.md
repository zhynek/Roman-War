# AI campaign CI performance investigation — 2026-10-07

The town task began at clean `138561d`; fetching origin confirmed that baseline.
The failed [run 37684305609](https://github.com/zhynek/Roman-War/actions/runs/37684305609)
tested that unchanged commit: 705 tests, one failure, the 60-turn AI campaign
average of 652 ms against its retained 600 ms budget. Behavioral assertions passed.

The parent `src`, `tests`, `data`, `schemas`, `.github` and `project.godot` are
identical from `52a3695` through `138561d`. The same parent code passed all 705
checks in [run 37583119390](https://github.com/zhynek/Roman-War/actions/runs/37583119390)
and failed at 632 ms in
[run 37583370424](https://github.com/zhynek/Roman-War/actions/runs/37583370424).
The successful run and linked failure used Godot 4.4.1 and the same Ubuntu 24.04
runner image `20261004.327.1`. Passing logs did not record the measured average.

Before any task edits, three isolated local calls of the unchanged acceptance
test averaged **314, 317 and 313 ms**, on the M3 Max with Godot 4.4.1. Logs are
`build/yenikapi-0.12-baseline/ai-campaign.log`. This establishes a pre-existing,
environment-sensitive failure; it does **not** prove runner contention specifically
or predict Ubuntu performance from macOS measurements.

This separate diagnostic change prints the average, slowest turn, budget, Godot
version, OS and CPU on successful runs too. It retains all 60 turns, deterministic
replay, world/behavioral assertions and the 600 ms budget. No timing assertion is
skipped or retried into success. Timing is outside saved game state and RNG.

Static investigation found redundant threat evaluation during AI recruitment and
repeated pure power evaluation while sorting armies. Neither was changed without
isolated evidence of impact. The last relevant observation work (`52a3695`)
added architecture snapshots to cartography. Before/after movement observations
must preserve reports before a force leaves; removing them casually would change
behavior. No speculative global cache is introduced.

Further CI timing remains a limitation: a future shared runner can still fail
the unchanged budget. The additional diagnostics make that failure reviewable;
they do not claim to repair unidentified runner resource variation.


The final local parent gate passed **705 tests, 0 failures** with this diagnostic:
311.233 ms average, 439 ms peak, 60 turns, M3 Max / 14 processors. Parent data,
headless import and actual planning/marching/arrival/maximum-zoom rendering passed
with no script errors. This is consistent with the unchanged local baseline;
it does not resolve the shared Ubuntu runner limitation.
