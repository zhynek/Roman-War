# Yenikapı · early settlement, circa 6000 BCE

A separate, walkable first village on the site of Istanbul's historic peninsula.
It is a **dated interpretive scenario**, with evidence and uncertainty available
inside the app. Read [SOURCES.md](SOURCES.md) before changing historical claims.
Circa 6000 BCE is an approximate setting within the attested Neolithic occupation,
not a foundation date or a claim to reconstruct the first village exactly.

Open [experience/project.godot](experience/project.godot) in Godot 4.4.1,
or use the separate [Yenikapı Early Settlement 0.1.0 prerelease](https://github.com/zhynek/Roman-War/releases/tag/yenikapi-early-settlement-v0.1.0).
Its verified downloads are the [Mac application](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.1.0/Yenikapi-Early-Settlement-macOS-0.1.0.zip),
[10 GLB models](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.1.0/Yenikapi-Early-Settlement-Models-0.1.0.zip)
and [editable source](https://github.com/zhynek/Roman-War/releases/download/yenikapi-early-settlement-v0.1.0/Yenikapi-Early-Settlement-Source-0.1.0.zip).
The circa-1200
Constantinople experience, its 17,561 reference plot records, Pantokrator district,
16 architectural types, 26 landmarks and all earlier downloads remain intact.
The prehistoric study is organized by site, without assigning a Byzantine realm
to Neolithic inhabitants. There is no campaign integration.

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
lineage system. Only the village is implemented. There is no timeline slider,
upgrade ladder, construction simulation or automatic population growth.

Run the independent data validator and tests, Godot import and `tools/checks.gd`.
Run `tools/preview.gd` with an external `out_dir`, inspect its 14 captures, and run
`tools/benchmark.gd` alone. The separate [release builder](../../tools/build_early_settlement.py)
repeats these against the exact Mac package. Parent campaign gates remain mandatory.
See [BUILDING.md](../../BUILDING.md) for the command and publication identity.
The [0.1.0 verification record](VERIFICATION.md) includes exact-app checks,
render inspection, performance measurements and preservation results.

## Present limits

This is detailed procedural art, not photorealism, a survey or a population model.
There are no people, animals, craft animations, soundscape, operable shutters,
farming mechanics or water simulation. Generic vegetation does not reconstruct
species or season. The walking controller is analytic and shares rendered wall,
furniture and floor geometry; free flight intentionally passes through geometry.
Far countryside is a lower-resolution backdrop beyond the walking envelope.
The model ZIP contains neutral-material GLBs, not shader appearance, lights,
walking physics, CAD solids or automatic future stages. Only Apple Silicon
rendering/performance is exercised locally; the package also includes Intel code.

The application is ad-hoc signed, not Developer ID notarized. macOS may require
Finder's **Open** action on first launch. It uses its own storage directory and
never reads or rewrites the medieval creative slot or any campaign save.
