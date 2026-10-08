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

After pushing the completed implementation and local verification record at
`7153211`, [run 37705757701](https://github.com/zhynek/Roman-War/actions/runs/37705757701)
passed data, import and **705 tests, 0 failures**. Its unchanged 60-turn assertion
measured **378.933 ms average / 527 ms peak**, against the same **600 ms** budget.
The reported environment was Linux, Godot 4.4.1, AMD EPYC 9V45, four processors,
Ubuntu 24.04 image `20260927.320.1`. This differs from the earlier failing image;
the new pass does not isolate the cause or eliminate future shared-runner variance.
The complete log is retained in the local 0.12 build's
`verification/remote-ci.log`. The following documentation-only commit records this
result without changing the tested implementation or the frozen Mac payload.

## October 8 city/warfare integration follow-up

The preserved checkpoint `5e4a441` failed
[run 37775919093](https://github.com/zhynek/Roman-War/actions/runs/37775919093)
at **657.283 ms average / 935 ms peak**. Integrated source `ad38185` failed
[run 37780542170](https://github.com/zhynek/Roman-War/actions/runs/37780542170)
at **637.917 ms / 896 ms**. Both reported Godot 4.4.1, Linux, AMD EPYC 7763,
four processors. The first completed 705 tests and the second 711; each had
only the retained campaign timing failure, with behavioral assertions passing.
Parent core and the campaign timing test remain identical to `8589fe9`.

The final integrated local parent gate passed 711 tests, averaging 322.050 ms
with a 453 ms peak on M3 Max. An isolated baseline/candidate experiment reused
one redundant threat calculation and per-sort unit powers. All 60 canonical
states and report hashes matched, but time improved only 320.385 → 316.918 ms
(1.08% in one sequential pair). That experiment is **not merged** and does not
credibly explain or fix the hosted gap. Evidence is retained outside the tree
at `/tmp/roman-war-ai-pure-probe/`. The 600 ms gate remains unchanged; broader
profiling must justify any targeted optimization before source integration.

The additional trade experiments also preserved all 60 canonical states and
reports but showed no useful improvement: connection-first 317.098 → 316.921 ms;
diplomacy-first 317.098 → 325.897 ms. All candidates remain unmerged. Costs are
distributed across economy, public order, society and cartography; no persistent
cache or changed gameplay rule was introduced. The full disposition is retained
at `/tmp/roman-war-integration-qa/ai-performance-experiment-disposition.md`.

The pre-integration audit main `8589fe9` itself failed
[run 37734286616](https://github.com/zhynek/Roman-War/actions/runs/37734286616):
625.733 ms average / 895 ms peak on Xeon Platinum 8370C, four processors. Its
705-test suite had the same sole timing failure. This is independent evidence
that the integration did not introduce it, not a passing performance result.

Zach's subsequent weekly testing policy ends further repeated testing and CI
monitoring in this development cycle. `weekly-tests.yml` retains the unchanged
600 ms gate for weekly/manual execution; no push/PR test trigger remains.
The inherited performance limitation is open for weekly review. No candidate
was merged merely to influence the reported CI status.
