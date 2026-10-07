# City lifecycle — 0.11.0 local build verification

Implementation starts from fetched `origin/main`
`096f1fb9444d15d3260c44e4c3e6a9c781a5d4f5`, after the 0.10 construction work.
The earlier architecture audit is retained in `docs/CITY_LIFECYCLE.md`.
This record concerns the verified local build. This work does not publish a release.

## Implemented scope

Slices A+B of the lifecycle plan provide ordered physical revisions, explicit
adoption, sustained named readiness, one paid Small village → Large village
civic transition, and two separately paid improvements. The later ladder through
Metropolis is visible as planned scope. No later civic transition or explorable
neighboring city is implemented. The dated Yenikapı reference, medieval
Constantinople study and parent campaign retain their identities and saves.

The assembly shelter uses the existing paid queue, finite seasonal adult allocator,
materials, pause and cancellation. Its civic obligation starts in the following
season. Commissioning checks post-payment food and fuel reserves. Completion
unlocks commissions; it does not grant buildings or restore resources. The store
and working room retain their object IDs, position, doors, furnishings and asset
condition through revisions 2 → 3. Previous land choices and access costs persist.

Wrapper 8 is active only after explicit lifecycle adoption. Wrappers 1–7 retain
their meanings. Legacy town achievement receives explicit recognition without
inventing a civic building. Semantic definitions are hashed; incompatible active
profiles are rejected rather than silently reinterpreted. Paid contracts, contact
journeys, incident response, household practice and offices survive adoption and
save/load. The older reversible town-support milestone keeps its existing readers.

## Source acceptance

Frozen payload `227eca38b2919d7d0abea1820b5823958a2460ba` passes **25,334 assertions** across all retained and new
source suites, including 12,247 lifecycle, 66 physical-continuity and 81 visual
checks. All data gates and the ten lifecycle authoring tests pass. Godot import
and logs were checked for script errors independently of process exit status.

Both compact and outward strategies use ordinary commands and opening resources.
The lifecycle checks follow each for 80 seasons, save at stage boundaries and
partial work, and compare uninterrupted and resumed state. Coverage includes
authority, query purity, rejected commands, finite labor, cancellation, post-payment
reserves, readiness resets, cumulative effects, predecessor revisions, malformed
saves, legacy town recognition, contacts and incident recovery. Separate fabric
checks compare legacy layouts exactly and exercise stale or conflicting revisions.

The parent data validator reports zero errors and warnings; Godot import, all
705 tests, and the rendered map playtest pass. Planning, marching, arrival and
maximum zoom were visually inspected. Logs are in
`build/yenikapi-lifecycle-gates/`; map QA is outside the repository at
`/private/tmp/yenikapi-lifecycle-parent-map`.

The first complete source input walkthrough passes 437 checks with 29 captures
at 1280×800. It uses actual UI input and compares each resulting state with the
public command boundary: adoption, blocked and ready requirements, quotes,
current/planned models, paid seasonal work, pause/save/resume, civic completion,
separate upgrades, retained interiors and idle purity. It finishes in season 33
without injected resources or progress. QA images and report are outside the
repository at `/private/tmp/yenikapi-lifecycle-source-qa`.

The frozen candidate repeats all 437 input checks and 29 captures successfully
after the final title-wrapping and benefit-copy corrections. Its authoritative
command sequence contains 49 commands and ends in season 33. Frozen-build logs
are under `build/yenikapi-early-settlement-0.11.0-local/verification/`.

## Review findings

Adversarial review identified four authoring-validation gaps: missing functional
site proposals, backward civic edges, unchecked cumulative benefit promises and
incorrect authored successor revisions. These are closed with explicit coverage,
forward stage ordering, structured benefit contracts and revision checks, with
negative regression cases. Benefit numbers are rendered from actual tuning/site
definitions so displayed increments and totals cannot drift from the rules.

Runtime review found no additional command-path bypass after checking civic
prerequisites, reserves, duplicate commissions, cancellation, legacy recognition,
shared staffing and contact gates. This is bounded review, not an exhaustive proof.

## Exact universal Mac acceptance

The builder includes all retained data, rule, geometry, rendered and performance
checks, plus lifecycle gates on source and the exact universal Mac application.
It compares command recipes and resulting digests, preserves the 41 earlier model
exports, verifies signatures/architectures and checks archive integrity.
All builder gates pass, including ten ZIP integrity checks. No Intel execution
or Developer ID notarization is claimed.

The exported **0.11.0** application passes all **25,334 assertions**, matching
the source across thirteen rule/read-model suites. Its bundle identifier is
`com.romanwar.yenikapi.earlysettlement`; it contains `arm64` and `x86_64` and
passes `codesign --verify --deep --strict`. Source and exact-app command recipes,
final state digests and strategy summaries match byte for byte.

| Ordinary-command strategy | Civic completion | Store completion | Workroom completion | Season-80 population / provisions / timber | Work places |
|---|---:|---:|---:|---|---:|
| Compact | 28 | 31 | 33 | 48 / 360 / 205 | 8 |
| Outward | 33 | 36 | 39 | 48 / 360 / 121 | 14 |

Both remain fed through season 80. Different completion times and retained work
places reflect the preceding development choices, not different opening grants.
The outward strategy retains its access obligation. This is evidence for two
authored strategies, not an exhaustive balance claim.

`verification/source-lifecycle-states/` and `packaged-lifecycle-states/` contain
commission, promotion, paused-work, recognized-town, active-contact and
active-incident saves plus recipes. These are generated through ordinary commands
and the actual save writer for isolated stage work; no player save is overwritten.

| Exact-app rendered suite | Captures | Checks | Failures |
|---|---:|---:|---:|
| Reference | 14 | — | 0 |
| Tutorial | 12 | 85 | 0 |
| Neighbors | 10 | 58 | 0 |
| Households | 12 | 714 | 0 |
| Assets | 12 | 477 | 0 |
| Land | 19 | 918 | 0 |
| Living village | 21 | 839 | 0 |
| Incidents | 25 | 676 | 0 |
| Visual commands | 26 | 392 | 0 |
| Construction | 34 | 672 | 0 |
| Lifecycle | 29 | 437 | 0 |

All **214 exact-app captures** and **29 frozen-source lifecycle captures** were
visually reviewed, using contact sheets and full-size key views. The exact app
passes **5,268 rendered assertions**. Its lifecycle command sequence, capture
names and final season 33 match source exactly; timings are excluded from that
comparison. Requirements, full offer titles, numeric benefits, paid work,
revision lineage, remaining reserves, planned stages and retained furnishings
are readable at 1280×800. The retained compact/outward, incident, construction,
interior, path and smaller-window flows remain intact. No blocking visual finding
remains. QA is outside the repository at
`/var/folders/31/vy1_xpsn5p58y89s48qrckcm0000gn/T/yenikapi-0.11.0-exact-qa-8io7bau8`.

All **41 previous GLBs are byte-identical** to the verified 0.10.0 local exports.
No campaign, medieval study or dated reference data changed from the starting
commit. Final log scanning found no Godot error diagnostics. The acceptance
summary and per-model hashes are in `verification/final-acceptance.json`.

## Performance and limits

On the local Apple M3 Max / Metal 3.2, the final 1280×800 lifecycle walkthrough
records these last-observed synchronous callbacks: adoption 16.895 ms, panel
opening 1,157.273 ms, commissioning 999.926 ms, seasonal resolution/refresh
161.867 ms. This walkthrough is capped at ten frames per second for input QA;
these are callback samples, not maximum latency or uncapped frame-rate claims.

The retained uncapped construction profile at 1600×1000 measures new-building
completion at 1,511.447 ms to rendered readiness, adaptation completion at
553.360 ms, and an ordinary season at 516.589 ms. Physical scene and route
rebuilding still cause visible pauses. This feature does not claim a performance
improvement or establish a rendering budget for later city-scale populations.
Full source/exact-app benchmark JSON and interaction logs accompany the build.

## Local artifacts

Build directory: `build/yenikapi-early-settlement-0.11.0-local/`.
The runnable bundle is `Yenikapı — Early Settlement.app`; the Mac ZIP is
`Yenikapi-Early-Settlement-macOS-0.11.0.zip` (58,908,902 bytes).
Its SHA-256 is
`baadb8e6e84a4293383c9b32746db01d580848fcace3ad0993f821e58c85459a`.
The source archive, eight model archives, provenance, checksums and verification
logs are retained alongside it. No release tag or public download was created.
