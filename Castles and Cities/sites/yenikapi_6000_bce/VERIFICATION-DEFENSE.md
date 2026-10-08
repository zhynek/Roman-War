# Village defense · local 0.13.0 · October 7, 2026

The work began from a clean worktree on freshly fetched `origin/main` (`2885f38`)
and is on `codex/village-defense`. No release, tag, remote push or parent battle
implementation was changed. This is a local preview with a frozen source manifest.

The scenario connects ordinary paid preparation, actual watch assignments,
deployment on the existing village, continuous orders, reports and continued
seasonal life. [Controls, boundaries and limitations](experience/DEFENSE.md).

## Local launch

The delivery directory is:

`/Users/zacharyhynek/Documents/ChatGPT/Roman-War/build/village-defense-0.13.0-delivery/`

Launch the universal app:

```sh
open "/Users/zacharyhynek/Documents/ChatGPT/Roman-War/build/village-defense-0.13.0-delivery/Yenikapı — Early Settlement.app"
```

Choose **New village** or **Load saved village**, then **Defend the village**.
Prepare materials, commission the watch shelter and kits, and train before
mobilizing. The first encounter can also be practiced without changing the village.
The app uses the existing independent village save directory; battle adoption
uses wrapper 9. Older wrappers load without adopting battle rules. Older apps
cannot read an adopted save. Parent campaign and viewing bookmarks are separate.

To launch editable source using the installed editor:

```sh
cd "/Users/zacharyhynek/Documents/ChatGPT/Roman-War"
"build/constantinople-toolchain/Godot.app/Contents/MacOS/Godot" \
  --path "Castles and Cities/sites/yenikapi_6000_bce/experience"
```

The delivery includes `Village-Defense-macOS.zip`, `Village-Defense-source.zip`,
an editable `source/`, `provenance.json`, `SHA256SUMS.txt` and verification logs.
Both CPU architectures and the ad-hoc signature are checked. Execution/rendering
is tested on Apple M3 Max; the app is not Developer ID notarized. Prior builds,
model archives and published releases remain unchanged.

## Validation

| Gate | Result |
|---|---|
| All retained village data validators and negative data tests, plus defense data tests | Passed |
| Retained village rule/geometry suites on source | 36,910 checks, zero failures |
| New battle rules on source and exact delivery app | 724 checks each, zero failures |
| Retained village rule/geometry suites on exact delivery app | 36,910 checks, zero failures |
| Rendered source walkthrough | 95 actual-input/outcome checks, zero failures; 11 captures |
| Rendered exact delivery walkthrough | 95 actual-input/outcome checks, zero failures; all 11 captures inspected |
| Parent data/schema/cross-reference validation | Zero errors, zero warnings |
| Parent Godot import and complete suite | 705 tests, zero failures |
| Parent rendered map | Planning, marching, arrival and maximum zoom passed |
| Universal export, signature and ZIP integrity | Passed |

Godot 4.4.1 was used. Logs were checked for script/engine errors in addition to
exit status. The inherited parent anchored-control warning remains non-failing.
Source and app checks retain the original reference mesh digest
`7f1edbf6ec717d61357b58ffd2237806139cdb59950b9fe5c18c16ee172c689a`.
No new image asset is included. No claim is made that all 44 optional model
archives were re-exported for this preview; their authoring geometry is unchanged.

The new checks cover actual adult membership, mobilization cost, command/season
locks, atomic rejected multi-group orders, hidden-target rejection, deterministic
mid-battle replay, deployment/live/ended/report save round trips, commit-once,
kit/roster reconciliation, ordinary care recovery, positioning, facing, equipment,
range, morale, withdrawal, undefended defeat, victory, bounded termination,
malformed extensions and a worker progressing while the main thread is blocked.

The rendered walkthrough uses pointer/key input for paid preparation, deployment,
click/Shift/rectangle selection, all seven orders, pause/resume, speed, camera
zoom, observed-enemy attack, active and ended-report save/resume, practice
withdrawal, victory, defeat, report acceptance and another ordinary village season.
It uses isolated `/tmp` saves. The defeat branch restores an earlier QA state;
it never modifies a user's continuing save. The source and final exported app
both passed the complete 95-check walkthrough. Each passed 37,634 village
rule/geometry checks including the new defense suite.

The prepared two-person rule fixture defends the store in 76.5 simulated seconds,
with one incapacitated resident and one lost kit. Undefended stores fall after
72.2 seconds, losing 24 provisions. Immediate refuge withdrawal also loses 24.
These are deterministic authored examples, not balance guarantees for every
village. The actual UI preparation strategy mobilizes three adults, including
one adult allocated to watch practice, with its earned equipment and readiness.

QA images and isolated saves are outside the repository:

- `/private/tmp/village-defense-final-render/` — source walkthrough.
- `/private/tmp/village-defense-delivery-verified/` — exact final app walkthrough.
- `/private/tmp/village-defense-map/` — required campaign-map surfaces.
- `/private/tmp/village-defense-qa/` — source and parent gate logs.

The parent map sample measured 8.212 ms median and 9.442 ms p95 frame time on this
machine, at final zoom 40×. This is an observation, not a cross-platform guarantee.

## Review fixes and practical limits

An early report-key-count validation failure and a legacy manual-plan validation
regression were found by the suites and corrected. Final review retained existing
injuries in practice copies, aligned equipment losses with the exact surviving
resident roster, and corrected the practice report's hypothetical ration total.
Earlier candidates remain separate from the delivery directory.

This release has one consequential fictional encounter per village, repeatable
practice, small group combat, recoverable incapacitation and supply/kit losses.
It has no permanent combat death, ranged weapons, building destruction, sound,
physical weapon collision or general invasion campaign. A conservative one-meter
navigation grid can reject narrow civilian passages, and groups can overlap one
another. Navigation capture and existing major village rebuilds can briefly pause
the UI. The live simulation still advances independently of rendering afterward.

`build_early_settlement.py` now includes the defense data, source/app rule and
source/app rendered gates for future full artifact releases. This local preview
used a separate frozen-source export and directly ran its gates; the entire
legacy model-archive/publication pipeline was not rerun or published.
