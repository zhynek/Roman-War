# City and warfare integration verification — 2026-10-08

This record covers the source integration of the preserved warfare checkpoint
`5e4a441` and city audit `8589fe9`, merged as `a88ca25`. Implementation commits
are `7024feb` (parent knowledge explanations), `4ab4811` (village explanations
and guide), and `ad38185` (retained comparisons and source CI). The
[dated audit follow-up](2026-10-city-progression-coherence-audit.md#8-follow-up--2026-10-08-merged-city-progression-and-warfare)
records every finding and measured tradeoff; the
[combined plan](2026-10-city-warfare-integration.md) records scope decisions.

No release, tag, export, model archive or existing app was rebuilt or replaced
in this integration. Earlier 0.13/0.14 exact-app results remain historical
evidence for those frozen payloads. Run the source below to use the new guide
and explanations; the earlier local app does not contain these changes.

## Local gates

Godot 4.4.1 and the project's Python/jsonschema virtual environment were used on
Apple M3 Max, macOS 26.6.1. Process status and stderr were inspected separately.

| Gate | Result |
|---|---|
| Village catalog and all 17 data validators | Passed, zero errors |
| All 16 village negative-test programs | 106 Python tests plus 16 embedded negative cases passed |
| Village import and complete headless suites | 32 suites, 53,586 checks, zero failures; unchanged source manifest; empty stderr |
| Lifecycle controls and rendering | 437 checks, 29 captures |
| Town controls and rendering | 1,713 checks, 53 captures; retained 87-command route |
| Legacy defense, tactical controls/cameras, paid fortifications, modes, aftermath and tactical scenarios | 1,636 checks, 50 captures |
| Civic/defense guide through actual controls | 104 checks, 14 captures |
| Final priority and learning-cost copy | 2 checks, 2 captures; read/navigation leave state unchanged |
| Total integration rendered checks | 3,892, zero failures; all 148 village captures inspected |
| Parent data and glossary negative tests | Zero errors/warnings; 6 negative-test methods passed |
| Parent import, complete suite and boot | 711 tests, zero failures; 467.490 seconds for the suite |
| Parent campaign map | Planning, marching, arrival and maximum zoom passed; all six captures inspected |

Village Godot stderr was empty. Python unittest summaries intentionally use
stderr and all report `OK`. The parent suite retains its existing non-failing
anchored-control warning; no script errors were found. The local parent AI
sample averaged 322.050 ms, peak 453 ms, against its unchanged 600 ms budget.
The map's deliberately capped 30 fps sample was 33.330 ms median, 34.878 ms p95
at maximum zoom 40; this is not an uncapped performance comparison.

The current rendered quick-mode samples took 300 ms for stores, 200 ms for
landing and 399 ms for the probe, below the local two-second target. Progress,
Stop & pause, handoff/takeback, active resume and exactly-once acceptance were
exercised. Different commands legitimately change ticks and consequences; the
headless gates compare identical command streams for mode/resume equivalence.

The first combined runner attempt exposed a verification-tool bug: resolving
the virtualenv Python symlink lost its installed jsonschema package. The tool
now preserves that path, and the complete final data gate passed. All original
headless and rendered suite assertions passed, but their source-freeze guards
correctly rejected concurrent guide/copy edits. Those runs are not represented
as clean aggregate passes. Final data and headless gates use frozen source;
guide and two last copy captures separately cover the affected rendered views.
No simulation code changed during the rendered sequence.

## Compatibility and audit coverage

The 2,106-check public-command audit reproduces layouts, reserve principles,
preparation/maintenance/welcome alternatives, incident preparation, watch
investment and paid-screen comparisons, plus acceptance and ordinary recovery.
The 481-check integration workforce suite covers priorities, unique named
assignments, factor totals, optional lifecycle, unpaid/invalid actions and saves.
The 104-check guide suite covers destinations, ownership aliases, finite-duty
copy, pending-battle locks, old profiles and guide state neutrality. These are
included in the complete headless total, not additional counts.

Published lifecycle, town, defense and warfare semantic hashes are unchanged.
The paid 0.11 fixture is byte-identical, SHA-256
`b0e0af7a47ffe5febe15d189bce0d4ffcb988180112dbf0412da293d607ae872`.
Older saves load inactive extensions; explicit adoption selects wrapper 8 for
lifecycle alone, 9 for defense and 10 for warfare. Warfare needs Living village
and its prerequisites, not lifecycle. No settlement code calls the parent
campaign; `BattleResolver` is unchanged. No image files were added.

Local evidence remains outside the repository:

- `/tmp/roman-war-integration-qa/village-data-verified/`: final data logs and source hashes.
- `/tmp/roman-war-integration-qa/village-headless-frozen/`: final complete source gate.
- `/tmp/roman-war-integration-qa/village-final-rechecks/`: retained measurement reports, recipes and replay saves.
- `/tmp/roman-war-integration-qa/village-render/`: nine sequential walkthroughs.
- `/tmp/village-integration-guide-render-verified/`: guide/control inspection and image hashes.
- `/tmp/roman-war-integration-qa/final-copy-render/`: the two final copy views.
- `/tmp/roman-war-integration-qa/parent/`: parent logs, source hashes and map captures.
- `/tmp/roman-war-integration-qa/civic-inspection.md` and `battle-inspection.md`: per-image inspection manifests.

## Reproduction and source launch

From the repository root, choose new evidence directories for each run:

```sh
build/constantinople-toolchain/venv/bin/python \
  "Castles and Cities/tools/verify_village_source.py" \
  --godot build/constantinople-toolchain/Godot.app/Contents/MacOS/Godot \
  --phase all --out /tmp/roman-war-integration-source-new
build/constantinople-toolchain/venv/bin/python \
  "Castles and Cities/tools/verify_village_source.py" \
  --godot build/constantinople-toolchain/Godot.app/Contents/MacOS/Godot \
  --phase render --out /tmp/roman-war-integration-render-new
```

The source runner never builds or exports. `all` means data and headless;
rendering is a separate explicit phase. The CI workflow runs the same data and
headless gates and retains evidence artifacts. Parent gates remain separate.

Launch the updated playable source:

```sh
cd "/Users/zacharyhynek/Documents/ChatGPT/Roman-War"
build/constantinople-toolchain/Godot.app/Contents/MacOS/Godot \
  --path "Castles and Cities/sites/yenikapi_6000_bce/experience"
```

Choose **New village** or **Load saved village**, then **How to play** for the
11 lessons. Explicit chapter adoption remains under village setup. **Defend
the village** supplies preparation, paid screens, the three command modes and
persistent aftermath. See [the controls guide](../../Castles%20and%20Cities/sites/yenikapi_6000_bce/experience/WARFARE-CONTROLS.md).

## Remaining limits and hosted CI

Town is the highest playable civic rank. Large town, conquest, army recruitment,
the settlement-development report, parent military integration and permanent
combat deaths are not implemented. Mature food surplus remains substantial.
Household practice is illustrative; watch training and combat experience are
the actual battle readers. Localized label overlap, compact-width ellipses,
some scrolling and minor singular/plural wording remain. No new exported-app,
Intel-performance or release-publication claim is made for this integration.

The preserved WIP's hosted run
[37775919093](https://github.com/zhynek/Roman-War/actions/runs/37775919093)
failed only the existing 600 ms campaign timing assertion: 657.283 ms average,
935 ms peak on a four-processor AMD EPYC 7763. The 705-test suite had that one
timing failure; behavioral assertions passed. Parent simulation and that test were unchanged
from the audit baseline. This matches the documented environment-sensitive
[CI limitation](2026-10-ai-ci-performance.md); it does not prove contention or
justify raising the threshold.

The integrated source at `ad38185` then completed
[run 37780542170](https://github.com/zhynek/Roman-War/actions/runs/37780542170):
parent/village data and negative checks passed; the 711-test parent suite had
the same sole timing failure, **637.917 ms average / 896 ms peak**, on EPYC 7763.
The existing sequential workflow skipped village headless after that failure;
the independent final local 53,586-check result above is not presented as a
hosted pass. Main was held at that checkpoint while the inherited timing issue
was investigated, with its 600 ms guard intact.

## Final policy change and source delivery

Zach supplied the weekly testing policy before final delivery. It supersedes
further repeated checks and post-push CI monitoring. `AGENTS.md` contains the
shared policy; the sole workflow is now `weekly-tests.yml`, scheduled Monday
13:00 UTC and manually dispatched, with no push/PR trigger. It retains both
projects' full data/headless gates and diagnostic artifacts. No threshold,
behavioral assertion or game rule was relaxed.

The audited main commit `8589fe9` had already failed
[run 37734286616](https://github.com/zhynek/Roman-War/actions/runs/37734286616)
at 625.733 ms average / 895 ms peak on a four-processor Xeon Platinum 8370C.
This confirms the hosted failure predates the integration. Isolated profiling
preserved every full state/report but found no worthwhile small optimization;
all candidates remain unmerged. Parent core and the timing test are unchanged.

The subsequent expanded push workflow
[37784725191](https://github.com/zhynek/Roman-War/actions/runs/37784725191),
at `3726615`, was still running when monitoring stopped. Its final result is
unverified. Cancellation was rejected by automatic approval review because it
was not explicitly authorized; the run was left alone. The final policy commit
will not start another push-triggered suite, and its CI will not be polled.

The redundant `/tmp/roman-war-integration-qa/village-render-frozen/` repetition
was stopped under the new policy. Only its lifecycle inspection completed;
it is not an aggregate pass and does not replace the earlier complete inspected
walkthroughs. All completed local results listed above remain unchanged.

Verified by: Ruby/Psych parse of weekly-tests.yml and direct trigger inspection. Tests: not run (weekly review policy).

This final line applies to the policy/workflow change. Earlier tests were run
under the user's explicit request and retain their actual results. Source is
delivered through main and `codex/village-defense`; no app or release is built.
