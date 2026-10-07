# City lifecycle — 0.11.0 candidate verification

Implementation starts from fetched `origin/main`
`096f1fb9444d15d3260c44e4c3e6a9c781a5d4f5`, after the 0.10 construction work.
The earlier architecture audit is retained in `docs/CITY_LIFECYCLE.md`.
This record concerns a local candidate; no 0.11 release has been published.

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

## Packaging gate

The builder includes all retained data, rule, geometry, rendered and performance
checks, plus lifecycle gates on source and the exact universal Mac application.
It compares command recipes and resulting digests, preserves the 41 earlier model
exports, verifies signatures/architectures and checks archive integrity.
Exact-app results will be recorded after the frozen candidate completes these
gates. No Intel execution or Developer ID notarization is claimed.
