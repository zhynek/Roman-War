# Yenikapı · early settlement, circa 6000 BCE

A separate, walkable first village on the site of Istanbul's historic peninsula.
It is a **dated interpretive scenario**, with evidence and uncertainty available
inside the app. Read [SOURCES.md](SOURCES.md) before changing historical claims.
Circa 6000 BCE is an approximate setting within the attested Neolithic occupation,
not a foundation date or a claim to reconstruct the first village exactly.

Open [experience/project.godot](experience/project.godot) in Godot 4.4.1,
or use the separate [Yenikapı Early Settlement 0.4.0 — Household Life prerelease](https://github.com/zhynek/Roman-War/releases/tag/yenikapi-early-settlement-v0.4.0).
Verified downloads:
[Mac application](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.4.0/Yenikapi-Early-Settlement-macOS-0.4.0.zip),
[16 foundation models](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.4.0/Yenikapi-Early-Settlement-Foundation-Models-0.4.0.zip),
[two contact models](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.4.0/Yenikapi-Early-Settlement-Contact-Models-0.4.0.zip),
[six furnished household models](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.4.0/Yenikapi-Early-Settlement-Household-Models-0.4.0.zip),
[editable source](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.4.0/Yenikapi-Early-Settlement-Source-0.4.0.zip).
All seven public assets were downloaded anonymously and verified against SHA-256
digests; the three model bundles contain 24 GLBs. The 18 previous GLBs retain
identical bytes. [Provenance](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.4.0/provenance.json) and
[checksums](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.4.0/SHA256SUMS.txt) identify the tested package.
The [0.3.0 contact chapter](https://github.com/zhynek/Roman-War/releases/tag/yenikapi-early-settlement-v0.3.0),
[0.2.0 seasonal tutorial](https://github.com/zhynek/Roman-War/releases/tag/yenikapi-early-settlement-v0.2.0)
and [original 0.1.0 village](https://github.com/zhynek/Roman-War/releases/tag/yenikapi-early-settlement-v0.1.0)
remain available with unchanged downloads.
The circa-1200 Constantinople experience, its 17,561 reference plot records, Pantokrator district,
16 architectural types, 26 landmarks and all earlier downloads remain intact.
The prehistoric study is organized by site, without assigning a Byzantine realm
to Neolithic inhabitants. There is no campaign integration.

## Household life in 0.4.0

Start the seasonal tutorial, open **Households**, and begin the optional chapter
as God. It can start in the first village, before the town or neighbor milestones.
Over eight explicit seasons, an authored warning leads to restricted movement,
recovery and a learning circle. Steward preparations and watch duty change the
forecast; household stress and uptake of a shared practice persist in the save.
This is fictional adversity and cultural change, not a reconstructed army or siege.

Three interiors gain original procedural racks, covers, tied bundles, woven
partitions, repair materials and a handwork frame. Every living resident, including
children, has a named activity and a collision-checked route through real doorways.
Use the resident picker to visit an activity. Portable furnishings and human poses
are interpretive, and the original dated reference remains available unchanged.
[Household controls, rules, evidence and save contract](experience/HOUSEHOLD_LIFE.md)
explain the distinctions and remaining limits. Active household saves use wrapper 3;
older inactive tutorials and contact saves still load.

## Neighbor contact in 0.3.0

After the town milestone, commission **Prepare a meeting and exchange place**,
then choose **Neighbors → Begin neighboring communities**. Two fictional partners
have finite supplies, reserve policies and changing speakers. Exchange and aid
commit carriers; the watch leader's escorts compete with protection at home.
God coordinates both offices. An accessible furnished meeting room and its path
add to the existing settlement; the partners' own villages are not yet modeled.
[Rules, tutorial and save compatibility](experience/GOVERNANCE.md) explain the
new chapter. Historical snapshots and the original tutorial remain separate.

## Explore

The village has six dwelling models, a working room, two stores, a shared outdoor
hearth, cultivation and a stream-bank landing. All nine interiors can be entered.
The six household groups are authoring identities, never archaeological people,
family counts or population estimates. Houses differ in plan, size, earthen finish,
roof profile and furnishing. Openings, structural posts, roof undersides, footing
stones, worn thresholds, woven screens and household materials work at foot scale.

WASD or arrow keys move. Hold the right mouse button, or press **Tab**, to look.
**F** switches walking and flight; **Q/E** changes elevation in flight. **Shift**
moves faster; the wheel changes flight speed from 3 to 120 m/s. **0** surveys the
village; **1–8** visit the named stops. **I** opens evidence; **H** hides the
interface; **Escape** releases the mouse. Click a building to inspect its stable
ID and interpretation label. The walking limit protects the water and distant
backdrop; flight can inspect the broader setting. Landing from flight selects a
safe nearby point or returns to the village approach.

Household thresholds connect to the shared yard, working area, fields and landing.
Footpaths are curved, terrain-following worn earth. The canoe and fishing rack
are interpretive, as are the crop plots and local shore. The stream and southern
sea express a plausible resource relationship without reproducing the modern
coast or the later Theodosian harbor.

## Authoring and growth

[AUTHORING.md](experience/AUTHORING.md) explains metre coordinates, collisions,
geometry, stable IDs and saves. [STAGES.md](STAGES.md) describes the small explicit
lineage system. The dated village remains unchanged. The [0.2.0 seasonal tutorial](experience/GOVERNANCE.md)
adds explicit work projects, fictional household demography, local leaders and a
reversible town milestone in a separate hypothetical scenario. No date or
population automatically upgrades buildings.

Run the independent data validators and their tests, Godot import,
`tools/checks.gd`, `tools/governance_checks.gd`, `tools/neighbor_checks.gd` and
`tools/household_checks.gd`. Run the household data validator and negative tests too.
Run `tools/preview.gd` with an external `out_dir`, inspect its 14 captures, and run
`tools/benchmark.gd` alone. The separate [release builder](../../tools/build_early_settlement.py)
repeats these, the 12-view `tools/governance_preview.gd` tutorial and the
10-view `tools/neighbor_preview.gd` contact chapter, and 12-view
`tools/household_preview.gd` against the exact Mac package. Parent campaign gates remain mandatory.
See [BUILDING.md](../../BUILDING.md) for the command and publication identity.
The [0.4.0 verification record](VERIFICATION-0.4.md) covers household rules, all 48
reviewed exact-app views, measured performance, preservation and seven public downloads.
The [0.3.0 verification record](VERIFICATION-0.3.md) covers the contact chapter,
exact app, performance, model packaging and six verified public downloads.
The [0.2.0 verification record](VERIFICATION-0.2.md) covers the original seasonal tutorial.
The [0.1.0 verification record](VERIFICATION.md) includes exact-app checks,
render inspection, performance measurements and preservation results.

## Present limits

This is detailed procedural art, not photorealism, a survey or a historical population estimate.
The tutorial adds stylized citizens and seasonal food/work mechanics. Animals,
detailed craft animations, soundscape, operable shutters and water simulation
remain unimplemented. Generic vegetation does not reconstruct
species or season. The walking controller is analytic and shares rendered wall,
furniture and floor geometry; free flight intentionally passes through geometry.
Far countryside is a lower-resolution backdrop beyond the walking envelope.
The model ZIPs contain neutral-material GLBs, not shader appearance, lights,
walking physics, CAD solids or automatic future stages. The 0.4.0 model downloads
retain the 16 foundation and two contact GLBs, adding three furnished rooms each
at danger and renewal for 24 in total. Only Apple Silicon
rendering/performance is exercised locally; the package also includes Intel code.

The application is ad-hoc signed, not Developer ID notarized. macOS may require
Finder's **Open** action on first launch. It uses its own storage directory and
never reads or rewrites the medieval creative slot or any campaign save.
