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
building conditions and everyday details remain approximate. Ordinary houses
use repeated architectural types and have exterior geometry. There are no
historically verified room inventories, animated urban economy, soundscape,
complete mosaics, or measured cadastral plan. Those limitations remain visible
in the authoring brief rather than being disguised as historical evidence.

## Explore

| Control | Action |
|---|---|
| Place list / Next place | Approach a landmark and read its evidence |
| Home view / Whole city / Plan view | Change the camera scale |
| Right drag / middle drag / wheel or trackpad scroll | Orbit / pan / zoom |
| Camera menu | Orbit, free flight or ground walking |
| Tab, then WASD and Q/E | Capture the mouse, move, descend or rise |
| Shift / Escape | Move faster / release mouse capture |
| Interior or courtyard | Enter the selected architecture at inspection speed |
| Reservoir cutaway | Reveal or cover the underground cistern |
| Sun slider | Change daylight and atmosphere |
| H / inspector − | Hide all panels / collapse the place inspector |
| F12 | Save a PNG screenshot outside the project |

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

## Model and extend

`data/city.json` is the source of landmark dimensions, positions, roads, walls,
wards, geography, development scenarios and source citations. `schemas/`
defines its contract. Coordinates are local metres: X east, Y up, **−Z north**
in Godot and glTF. The authoring JSON stores horizontal `[east, north]` pairs;
the origin is near Hagia Sophia. There is no certified geodetic datum.

`src/landmarks.gd` and `src/geometry.gd` build the architecture. `src/layout.gd`
deterministically places the urban fabric. `src/world.gd` assembles it and
groups repeated meshes for rendering. `data/visuals.json` controls rendering
budgets and palette. Change these locally and validate before exporting.

The model ZIP contains a whole-city GLB and a separate GLB for each landmark.
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
