# Constantinople · circa 1200

A separate, explorable 3D city study within Roman War. Open `project.godot`
in **Godot 4.4.1**, or launch the universal Mac application supplied with the
city release. The campaign does not load this project or its saved designs.

The reference scene contains the peninsula and opposite context shores, 26
landmark assemblies, inhabited wards, curved local lanes, arterial streets,
fortification circuits, harbors and vessels, fields and vegetation. Hagia
Sophia has an inspectable nave; the Basilica Cistern has a covered vaulted
interior and an optional exterior cutaway. Monument geometry, surface shaders,
buildings, vegetation and vessels are original procedural constructions.

This is a substantial interpretive reconstruction, **not a finished
photorealistic or surveyed reproduction of the city in 1200**. The landmark
list has an evidence register; most measurements, street plots, relief,
building conditions and everyday details remain approximate. Outside the detailed Pantokrator neighborhood, ordinary houses
use repeated architectural types and primarily exterior geometry. There are no
historically verified room inventories, animated urban economy, soundscape,
complete mosaics, or measured cadastral plan. Those limitations remain visible
in the authoring brief rather than being disguised as historical evidence.

## Connected neighborhood · 0.3.0

**Explore Pantokrator neighborhood** opens six connected irregular blocks
southwest of the monastery. **Walk: choose a starting place** puts you at the
approach, courtyard home, baking workshop, store room or garden. Tab captures
mouse look; WASD walks, Shift hurries, Escape releases the pointer. Street doors
lead through real wall openings into rooms and rear courts. Walk through the
home and turn right in its court to climb the stair to its upper gallery/room.

The 108 occupied parcels share boundaries and street frontages, with unequal
rooflines, twelve open passages, enclosed yards, gardens, shelters and water
points. Thick walls, recessed windows, open door leaves, roof undersides and
rafters, level floors, terrain-reaching foundations, shallow threshold steps,
repairs, plaster variation and drainage strips replace isolated pads in this
area. Three principal ground-floor interiors and the home's upper room are
furnished. Other rooms are mostly empty shells. All geometry and materials are
original procedural work. There is no urban activity or fluid simulation.

The surviving Pantokrator churches and 1136 foundation document provide a
strong local anchor for provisioning, baking, gardening and drain maintenance.
The **local street plan, house positions, equipment and finishes are authored
interpretations**, not excavated properties. The court/stair analogy comes from
an eleventh-century house at Corinth. Later Frankish shops and Ottoman house
forms are excluded. See [NEIGHBORHOOD.md](NEIGHBORHOOD.md) for the evidence,
authoring contract, migration and measured performance.

The v0.2 generator and all 17,561 stable baseline plot records remain intact;
78 local building presentations are hidden while the 108 new parcels are shown.
**Use v0.2 neighborhood fabric** restores the old presentation. Loading a v1
creative save with additions in this area automatically selects that mode and
keeps every saved identifier and coordinate. The detailed neighborhood can be
re-enabled with its exploration button. Flight speeds and district jumps remain
available throughout.

## Architectural variety · preserved from 0.2.0

The 17,561 reference urban plots now draw from **16 architectural types**:
six domestic plans, shop houses, storehouses, weaving/pottery/smithing/baking
courts, two neighborhood church forms, well courts and market shelters.
L-shaped and three-sided courts have actual open space, uneven wings and
independent roofs. Shutters, galleries, stairs, awnings, jars, hand looms,
hearths and ovens distinguish close inspection. District profiles weight types
deterministically; the two infill scenarios keep each reference plot's type.

Sergius and Bacchus uses an octagonal, two-level gallery assembly; Pantokrator
has unequal flanking churches and a narrow double-domed central chapel; the
Holy Apostles uses a cruciform five-domed interpretation. These are original
interpretations of cited building forms, not measured reconstructions of every
lost phase. Domestic comparanda from Corinth are explicitly distinguished from
Constantinople evidence; later shop remains are not dated to 1200 by analogy.
See `data/architecture.json` and the parent study's `SOURCES.md`.

Roads and plot surfaces now follow the actual terrain triangles. Matching
close/distant batches share bounds, detailed geometry remains within its plot,
and the procedural material patterns are filtered to reduce distant shimmer.

## Explore

| Control | Action |
|---|---|
| Place list / Next place | Approach a landmark and read its evidence |
| Home view / Whole city / Plan view | Change the camera scale |
| Right drag / middle drag / wheel or pinch | Orbit / pan / faster proportional zoom |
| Shift + wheel | Double the zoom step |
| Explore Pantokrator / Walk menu | Detailed district overview / five walking starts |
| Use v0.2 neighborhood fabric | Restore the earlier local presentation for saved designs |
| Jump to district / double-click terrain | Hop to a neighborhood / approach a chosen spot |
| Home key | Whole-city overview |
| Camera menu | Orbit, free flight or ground walking |
| Tab, then WASD and Q/E | Capture the mouse, move, descend or rise |
| Flight speed menu | Detail 8, street 35, district 120, city 400 or crossing 1,000 metres/second |
| Wheel in flight / [ and ] | Change flight speed |
| Shift / Escape | Fourfold flight boost / release mouse capture |
| Interior or courtyard | Enter the selected architecture at inspection speed |
| Reservoir cutaway | Reveal or cover the underground cistern |
| Sun slider | Change daylight and atmosphere |
| H / inspector − | Hide all panels / collapse the place inspector |
| F12 | Save a PNG screenshot outside the project |

Flight keeps your selected speed when you change views or jump between districts.
Entering a landmark slows to inspection speed; leaving restores the travel
speed. Double-click travel is disabled while using the creative workshop, and
scrolling over panels does not move the camera.

The first launch constructs the city and compiles its shaders. Give the window
time to finish. **Enhanced atmosphere** can be disabled on slower computers;
this reduces shadows and ambient effects. The program requires a desktop GPU
supported by Godot's Forward+ renderer. The Mac package contains Apple Silicon
and Intel executables; local rendering verification used Apple Silicon.

## Create a variant

The city-state menu includes the reference and two **hypothetical infill
designs**. They preserve reference buildings while adding capacity to the
same authoring site. Their names are design scenarios, not dated historical
stages or changes to the Roman War simulation.

Open **Creative workshop**, choose a house, workshop, church or tower, enable
placement, and click terrain. Rotate, scale, remove and undo edits before
saving. Baseline architecture is protected; the editor manages your additions.
**Save design** and **Load design** use the study's separate user directory,
`~/Library/Application Support/Roman War Constantinople Study/` on macOS.
**Open study folder** opens that directory. It contains `creative_variant_v1.json`
and screenshots. Copy the JSON to preserve or share a design. Maximum saved
additions: 500. The save loader validates every object before replacing a design.

## Future campaign connection

A future integration should open this city through a read-only presentation
adapter carrying a public settlement identifier, visible development report,
scenario date and return-camera state. Campaign rules would continue to own
construction and time; the city would derive appearance from that report.
The circa-1200 reference needs an explicitly selected historical scenario,
not an automatic substitution into the Roman campaign chronology. That
connection is a later phase; this application and its creative saves remain
independent today.

## Model and extend

`data/city.json` is the source of landmark dimensions, positions, roads, walls,
wards, geography, development scenarios and source citations. `schemas/`
defines its contract. Coordinates are local metres: X east, Y up, **−Z north**
in Godot and glTF. The authoring JSON stores horizontal `[east, north]` pairs;
the origin is near Hagia Sophia. There is no certified geodetic datum.

`data/architecture.json` defines the typology catalogue, historical confidence,
district weights and dimensions; its schema and cross-reference checks reject
unknown types, evidence and materials. `src/architecture.gd` constructs the
ordinary architecture. `src/landmarks.gd` and `src/geometry.gd` build the monuments. `src/layout.gd`
deterministically places the urban fabric. `src/world.gd` assembles it and
groups repeated meshes for rendering. `data/visuals.json` controls rendering
budgets and palette. Change these locally and validate before exporting.

The model ZIP contains **44 GLBs**: a whole-city model, 26 landmarks, 16
fully detailed nominal architectural prototypes (`type-*.glb`) and a separate
detailed `district-pantokrator.glb`. The district origin is documented in the
model provenance; its coordinates are centered on the district’s local ground datum.
They use neutral PBR materials, economical whole-city houses and metric mesh
geometry. Procedural application shaders are not baked into those derivatives.
Import them into Blender or another glTF-capable authoring tool; CAD workflows
may require a mesh import/conversion step. They are **meshes, not STEP solids**.
Individual landmark files are centered on their own local ground datum;
the city file preserves the complete coordinate frame.

From this experience directory:

```sh
python3 tools/validate_city.py --godot /path/to/godot
/path/to/godot --headless --path . --import
/path/to/godot --headless --path . --script res://tools/smoke.gd
/path/to/godot --headless --path . --script res://tools/navigation_checks.gd
/path/to/godot --headless --path . --script res://tools/landmark_checks.gd
/path/to/godot --headless --path . --script res://tools/surface_checks.gd
python3 tools/test_neighborhood_data.py
/path/to/godot --headless --path . --script res://tools/neighborhood_checks.gd
/path/to/godot --path . --script res://tools/benchmark.gd -- out_dir=/tmp/constantinople-benchmark
/path/to/godot --path . --script res://tools/preview.gd -- out_dir=/tmp/constantinople-qa
/path/to/godot --headless --path . --script res://tools/export_models.gd -- out_dir=/tmp/constantinople-models
```

Python validation requires `jsonschema`. Keep generated meshes and QA images
outside the repository. The release builder at
`Castles and Cities/tools/build_city.py` freezes a clean committed checkout,
validates it, exports a universal Mac app, verifies the exact packaged app,
exports all models, and records source hashes and download checksums.

The macOS package is ad-hoc signed and not Apple-notarized. If macOS blocks
the download, use **System Settings → Privacy & Security → Open Anyway** for
this app after reviewing its source and release checksums.

This application uses [Godot Engine under the MIT license](https://godotengine.org/license).
The accompanying `GODOT_COPYRIGHT.txt` contains the official 4.4.1 engine and
third-party notices. City geometry and surface shaders are original project
work; cited historical sources do not grant permission to copy their imagery.
