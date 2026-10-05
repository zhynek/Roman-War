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
  --version 0.3.0 --parent-gates build/yenikapi-parent-gates
```

It freezes the authoring workspace, validates both registered studies and the
village data, runs negative cases and source geometry/walking/save/lineage checks,
benchmarks the source, exports and checks the universal ad-hoc signed Mac app,
then repeats checks, 36 rendered views (14 reference, 12 tutorial and 10 contact) and the same benchmark in the **exact app**.
Inspect all images at the external `render_capture_directory` before publishing.
Source/package geometry hashes must match. Eighteen GLBs, three ZIPs and SHA-256
checksums are validated. Parent stderr is checked as well as success markers.

Artifacts use `Yenikapi-Early-Settlement-{macOS,Models,Source}-0.3.0.zip`.
Publish under **`yenikapi-early-settlement-v0.3.0`**, `--prerelease --latest=false`,
with the frozen commit target. Do not replace Constantinople or campaign assets.
Never change bytes under an existing release version. Model material appearance
is a neutral derivative; editable source retains shaders, data and original code.
The new app bundle/save namespace is independent of Constantinople's v1 creative
save and all campaign saves. See its authoring guide for the new view format.

The 0.3.0 builder also validates governance content and its 22 negative cases,
runs the 706-check seasonal/save/leadership suite and 302 contact checks on source and exact app, and
plays the tutorial through real controls to the town milestone. It benchmarks
reference, grown and contact worlds separately; the grown benchmark includes animated
workers. Inspect every reference/tutorial capture and scan stderr. The separate
campaign save format is described in the site's `experience/GOVERNANCE.md`.
Preserve 0.1.0 bytes and downloads; that tag remains the original village release.

The contact chapter also has closed data schemas, five negative-case test groups,
58 rendered interaction/navigation checks and in-flight save replay. Keep all
0.1.0 and 0.2.0 release assets unchanged. Wrapper v2 is for active contacts only.


For the 0.3.0 public release, repeated TLS upload failures on the combined model
ZIP required two delivery archives: Foundation Models (the retained 16 GLBs) and
Contact Models (the two additions). The local builder's combined ZIP remains the
verification source. Each split member must match it byte for byte, both ZIPs must
pass integrity checks, and provenance/artifact hashes must describe the actual
published downloads. Never modify the tested Mac archive or GLB bytes to work
around transport failures. See the site's VERIFICATION-0.3.md for this delivery.


## Household life release (0.4.0)

Use `build_early_settlement.py --version 0.4.0` with fresh parent gate logs and a
clean committed checkout. The builder adds household schema/negative tests and
rules checks, then repeats them inside the exact exported Mac application. It
captures **48 views**: 14 reference, 12 tutorial, 10 contact and 12 household.
The last set checks all resident routes at warning, danger, recovery, renewal and
settled stages; doors, save resume, original reference restoration and small-window
controls. Inspect every image outside the repository. Benchmark reference, town,
contacts and household life sequentially with no competing Godot render process.
The chapter capture tools settle actual rendered frames after mesh/material
replacement; passive process frames can leave background macOS captures with
unready materials. Synthetic pointer motion must precede a click after UI layout
or scrolling. Neither QA accommodation changes simulation or production lighting.
If Metal captures still show partially initialized material groups, repeat the
affected exact-app capture script with `--max-fps 10` before `--script`. Its twelve
drawn settling frames then allow at least 1.2 seconds per capture. Preserve the
first captures/logs, record the repeat command, and inspect the complete replacement
set. This pacing is for screenshots only; never apply it to performance benchmarks.

The model exporter retains all 18 previous GLBs and adds six separately named
hypothetical furnished rooms (three each at danger and renewal). The builder
checks all 24 models and packages **Foundation Models** (16), **Contact Models**
(2) and **Household Models** (6) separately, with source and Mac ZIPs. Model
partitions are checked against raw exported bytes, avoiding a large combined
upload. Publish all five ZIPs plus provenance/checksums under
`yenikapi-early-settlement-v0.4.0`, prerelease and never latest. Verify public
download hashes and all earlier releases by asset ID, not array order.

## Asset governance release (0.5.0)

Build with `build_early_settlement.py --version 0.5.0` using fresh parent gates.
It adds asset schema/negative tests, `asset_checks.gd`, and twelve actual-interface
`asset_preview.gd` captures to all retained gates. Source and exact app each run
all five rule/geometry suites. The exact app produces **60 captures**; inspect all
at the external provenance path. Captures are paced at 10 FPS to allow background
Metal setup, while all five benchmarks remain uncapped and run sequentially.
Asset capture reports also measure chapter opening, changing orders and route
rebuilding. Never infer Intel performance from Apple Silicon results.

The exporter preserves 24 existing GLBs and adds three clearly named asset
specimens: stocked store, empty store and neglected workroom under repair.
The last two use explicit authored comparison states, documented in provenance.
These are hypothetical arrangements, not dated inventories. The builder packages
six ZIPs: Mac, editable source, Foundation (16), Contact (2), Household (6), and
Asset (3) Models, plus provenance and checksums. Publish as
`yenikapi-early-settlement-v0.5.0`, prerelease and never latest. Verify public hashes
and retain all earlier release IDs/assets and campaign stable `v0.14.2`.
