# Preparedness Put to the Test — 0.8.0 verification

Baseline: clean `main`, fetched origin at
`5f8fdf95b9134c902f9af5df843af0cbfa464e80`. Version 0.8.0 was available.
Thirteen previous releases / 75 assets and stable latest `v0.14.2` were recorded
before editing in `/tmp/yenikapi-0.8-baseline/`, together with protected file hashes.
No real player save was opened or overwritten.

## Implemented loop and limits

Two explicitly hypothetical incidents test different existing investments:
upper-approach wear and uncertain waterside activity followed by bounded attempted
taking. Seasonal rules own signs, guaranteed warning, paid preparation, resolution,
persistent disruption and paid recovery. There is one unresolved incident, an
eight-season recovery interval and no recurrence after the two authored incidents.
The older household teaching episode remains separate. The ordinary project queue,
finite adult allocation, timber/prepared sets, household stress and equipment ledger
remain authoritative. No tactical combat, bows, individual work commands, free
supplies or new town threshold is introduced. See
[PREPAREDNESS.md](experience/PREPAREDNESS.md) for exact causal and wrapper-7 rules.

The 64-season same-start comparisons use public commands and identical external
incident strengths and schedules. Both competent strategies stay fed and recover.
Overview receives the first warning at turn 6, prepares in time, and takes approach
severity 3. Local inspection and a paid opportunity cost give the attentive strategy
notice at turn 4 and severity 2. Both protect waterside provisions and finish with
300 provisions; overview retains 192 timber, attentive 130. This demonstrates an
expensive information/preparation advantage, not an optimal strategy or an automatic
benefit to maximizing readiness. Underprepared play takes severity 5/7 and loses
28 provisions, then repairs through ordinary materials and crews without a grant.
It also remains fed. Repairs finish at turns 10 and 28 in these examples.

The expanded comparison retains 48-season compact/outward layouts, explicitly adopts
incidents, then resolves the same unprepared approach pressure. Compact has six
working places and severity 5; outward retains eight places but takes severity 6
and loses loaded approach service. No home, resident or older completed fabric is
removed. Separate checks cover watch focus, maintained equipment, finite work,
household cooperation, succession at resolution, inspection idempotence, duplicate
payments/refunds, malformed active saves, no passive recovery, and bounded overlap.

## Development checks and inspection

All retained independent-project schemas/negative tests and earlier rule/geometry
checks passed. The parent data/import/full **705-test** suite passed with
stderr scanned. The final incident suite passed **6,323 checks**, including explicit outcome/JSON
regression cases after correcting integer-factor validation across JSON readback
(JSON numbers are floats). Exact-app results are recorded below after freezing.

The first actual-input incident run passed **668 checks / 22 captures**, completing
the full guide, both layouts, pausing/resuming repair and normal-stock recovery.
Inspection found overlapping approach labels and narrow crew fields; these were
corrected. A second run passed the corrected labels and shared inspection path.
The final expanded harness also visits the actual authored waterside working area
and its maintained observation post, adding three captures. All screenshots remain
outside the repository. The expanded development run completed 25 captures / 671
checks, with two save assertions failing on the now-corrected JSON factor issue.
The frozen exact-app run repeats the complete harness before publication.
Failed/intermediate logs are retained for traceability.

## Pre-change performance

Fresh source baseline on this M3 Max, Godot 4.4.1 Forward+, 1600×1000:
opening assets 1,303 ms; opening living 4,396 ms; adaptation commission 285.560 ms;
priority 53.206 ms; site comparison 7.971 ms; watch reassignment 395.859 ms;
adaptation completion 3,890 ms; ordinary living season 731 ms; targeted inspections
16.196–16.543 ms; forced living routes 153 ms. These are direct single-run
interaction measurements, distinct from the published 0.7 exact-app record.
Logs split rule, world and UI time. Frame rates are not used as a substitute.

Final source/exact-app profiles and public artifact verification follow after the
frozen build. No Intel performance, Developer ID notarization, hydraulic simulation,
archaeologically documented incident or continuing Neolithic-to-medieval chronology
is claimed.

## Release-candidate rendering investigation

The first frozen attempt stopped on a model-exporter variable collision despite
Godot returning exit zero. The corrected candidate at `b0ceafe` then passed every
rule and actual-input assertion, but manual inspection rejected its outward-layout
views: earth-shader surfaces became black after a full world replacement. It was
never published. A focused six-rebuild probe retained shader identity when a
material reference was held; without it, shader resources were recreated each
time (CPU pigment values remained valid). The fault was intermittent rather than
a reproducible seasonal-state change.

The village now retains its three original shaders across world replacement.
No geometry, pigments or seasonal rules change. Five fixed, HUD-free interior
cameras also assert visible material luminance; this new regression check rejects
the two failed recovery interiors (sample means 0.067/0.065, versus 0.276–0.338
for the lit reference captures). The final build repeats all gates and manual
inspection; passing input checks alone do not authorize publication.

The corrected source acceptance completed **25 captures / 676 checks, zero
failures**. The outward landscape and both recovery interiors were reinspected
and retained their lit materials. Final frozen-app verification follows below.

The next candidate stopped twice in the older contact UI harness because its
synthetic season click left the journey unchanged. Two instrumented runs on the
same app delivered the click and passed all 57 checks. Source execution also
exposed an immediate assertion before deferred tab construction. The harness now
waits for that tab and keeps the native pointer aligned with its synthetic press
and release, without retries or direct state edits. The corrected source contact
run passed 58 checks / 10 captures. No seasonal rule was changed; the replacement
payload repeats the full frozen build instead of accepting the failed gate.

## Frozen release verification

Payload commit: `afe8e09897e9d41cf271c3416349a1b2eae1782e`. Build: `build/yenikapi-early-settlement-0.8.0-final4`.

All source and exact-app schemas/negative cases and **12,093 rule/geometry checks per executable** passed. The exact Mac application passed **3,767 rendered checks / 125 captures**, including **676 incident checks / 25 captures** and the lit-interior regression checks. Parent data/import/full **705 tests** and map playtest passed; every log was scanned for script errors, including zero-exit errors. The app is universal `arm64` / `x86_64` and passes strict ad-hoc signature verification.

External rendered acceptance: `/var/folders/31/vy1_xpsn5p58y89s48qrckcm0000gn/T/yenikapi-0.8.0-exact-qa-6ak6ty9s`. All 125 views were inspected, including warning, paid response, outcomes, recovery, both layouts, four viewing scales and smaller-window controls. Large 3D labels can still crowd at oblique angles; the persistent inspector provides full costs and outcome factors. No screenshot is a game asset.

The guide uses actual input controls and opening resources. The extended same-start comparison checks save/load at every season through warning, commitments, impact, recovery and quiet intervals, plus succession at resolution, duplicate charges/refunds, no passive recovery, no inspection/animation rewards, and bounded overlap. Repeated presentation steps at 0.001–1.0-second deltas and camera changes leave authoritative state unchanged.

## Final interaction measurements

Single-run observations on this M3 Max, Godot 4.4.1 Forward+, 1600×1000, with no competing Godot process. Command rows sum command, world refresh and UI refresh; timings are not universal guarantees. Quote comparison is explicitly rule-only.

| Interaction | Frozen source ms | Exact Mac app ms |
|---|---:|---:|
| Open incident chapter | 1517.000 | 1122.000 |
| Inspect warning | 15.526 | 11.601 |
| Compare two response quotes (rules only) | 0.355 | 0.291 |
| Commit paid response | 1526.777 | 1130.602 |
| Change watch priority | 564.669 | 420.614 |
| Change preparation priority | 171.934 | 130.623 |
| Resolve warning season | 641.000 | 469.000 |
| Resolve incident season | 790.000 | 602.000 |
| Commission recovery | 821.705 | 624.610 |
| Resolve recovery work | 472.000 | 360.000 |
| Resolve completed recovery | 241.000 | 186.000 |
| Force incident route rebuild | 345.000 | 266.000 |

| Existing interaction | Fresh 0.7 source baseline ms | Final source ms | Published 0.7 exact-app ms | Final exact-app ms |
|---|---:|---:|---:|---:|
| Adaptation completion | 3890 | 3993 | 3177 | 3296 |
| Ordinary living season | 731 | 739 | 598 | 589 |
| Forced living routes | 153 | 156 | 126 | 127 |
| Targeted woodland inspection | 16.196–16.543 (all four subjects) | 17.269 | approximately 13 | 13.581 |

Unchanged inspections retain routes and geometry. Rule calculations are a small fraction of the longer commands; route refresh dominates response/recovery commissioning. Full footprint changes still pause synchronously. The season button draws feedback and blocks duplicate queued input; repeated paid commissions are rejected by the authoritative ledger. Presentation never advances a season or resolves an incident.

All **36 GLBs** passed structural checks; the **33 prior model files** match 0.7.0 byte-for-byte. Nine ZIPs passed integrity checks, model partitions match exported bytes, and frozen-source hashes were rechecked. Eleven release files comprise the app, editable source, seven model partitions, provenance and checksums.

The completed build ran without resumed or skipped gates. The contact harness passed
58 exact-app checks. Seventy logs were scanned; the parent suite retains its existing
Control-anchor warning, with no script errors. Archive readback confirms that every
app member matches the tested bundle and every editable-source member matches the
frozen hash inventory. The visual review ledger is `/tmp/yenikapi08-review.json`.
