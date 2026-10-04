# Build a city release

Constantinople is an independent Godot project. Its source is under
`realms/byzantine_empire/cities/constantinople_1200/experience/`. The parent
workspace's `.gdignore` keeps the medieval study outside Roman War imports,
campaign resources, saves and builds.

From the repository root on macOS, with **Godot 4.4.1**, its matching macOS
export templates, and Python's `jsonschema` installed:

```sh
python3 'Castles and Cities/tools/validate_studies.py'
python3 'Castles and Cities/tools/build_city.py' \
  --godot /path/to/Godot.app/Contents/MacOS/Godot \
  --version 0.3.0
```

The builder requires a clean committed checkout and a fresh output directory.
It freezes this entire authoring workspace under `build/constantinople-0.3.0/`,
checks data and the actual scene, exports and ad-hoc signs a universal Mac app,
verifies its signature and Apple Silicon/Intel architectures, and runs both
headless and rendered checks inside the **exact exported application**.
Inspect the 32 screenshots in the external temporary directory recorded as
`render_capture_directory` in `provenance.json`; an exit code alone cannot
establish visual quality. The builder also measures the exact app at three
fixed cameras, recording frame times and hardware in `verification/benchmark.json`.
Do not run competing Godot processes during that measurement. Full Roman War regression and map
acceptance remain separate repository release gates.

Download artifacts are produced only after the checks finish:

| File | Contents |
|---|---|
| `Constantinople-1200-macOS-0.3.0.zip` | Universal application and controls/readme |
| `Constantinople-1200-Models-0.3.0.zip` | Whole-city GLB, 26 local landmark GLBs 16 detailed architectural types, a separate detailed district, model provenance |
| `Constantinople-1200-Source-0.3.0.zip` | Frozen editable project, historical briefs, schemas and tools |
| `provenance.json` | Commit, source hashes, verification results, asset sizes/hashes |
| `SHA256SUMS.txt` | SHA-256 hashes for all three ZIPs and provenance |

Model materials are neutral PBR derivatives. Shader appearance is available in
the app and editable source; it is not baked into the GLBs. Mesh interchange
does not produce native CAD solids or historical survey accuracy.

Publish the study under its own `constantinople-v<version>` GitHub prerelease
with `--latest=false`, so it does not replace the campaign's stable download.
Use the frozen commit as the release target. Preserve earlier downloads and
never rebuild different bytes under an already published version.

The city gates include schema/layout validation, eight negative neighborhood-data
tests, smoke/editor/save checks, navigation, landmarks, terrain coverage and
374 neighborhood geometry/collision/route/save checks. Both source and exported
app run the Godot gates. Inspect aerial, street, three ground-floor interiors,
court, upper gallery and roof/upper-room captures, plus the existing 23 views.
Run parent data validation, clean import, the complete campaign suite and
`tools/map_playtest.gd` separately; inspect planning, marching, arrival and
maximum zoom and check stderr even when exit status is zero. Keep
`build/.gdignore` present so generated exports cannot enter campaign imports.

## Separate Yenikapı early-settlement prerelease

The new site project is `sites/yenikapi_6000_bce/experience/`. Use its independent
builder from a clean committed checkout after parent data/import/full-suite/map
checks. Parent logs must be named `data.log`, `import.log`, `tests.log`, `map.log`.

```sh
python3 'Castles and Cities/tools/build_early_settlement.py' \
  --godot /path/to/Godot.app/Contents/MacOS/Godot \
  --version 0.1.0 --parent-gates build/yenikapi-parent-gates
```

It freezes the authoring workspace, validates both registered studies and the
village data, runs negative cases and source geometry/walking/save/lineage checks,
benchmarks the source, exports and checks the universal ad-hoc signed Mac app,
then repeats checks, 14 rendered views and the same benchmark in the **exact app**.
Inspect all images at the external `render_capture_directory` before publishing.
Source/package geometry hashes must match. Ten GLBs, three ZIPs and SHA-256
checksums are validated. Parent stderr is checked as well as success markers.

Artifacts use `Yenikapi-Early-Settlement-{macOS,Models,Source}-0.1.0.zip`.
Publish under **`yenikapi-early-settlement-v0.1.0`**, `--prerelease --latest=false`,
with the frozen commit target. Do not replace Constantinople or campaign assets.
Never change bytes under an existing release version. Model material appearance
is a neutral derivative; editable source retains shaders, data and original code.
The new app bundle/save namespace is independent of Constantinople's v1 creative
save and all campaign saves. See its authoring guide for the new view format.
