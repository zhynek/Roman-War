# Building playable versions

Two commands produce a shippable build from a clean checkout. Requires
[Godot 4.4.x](https://godotengine.org/download) plus its **export templates**
(Editor → Manage Export Templates → Download, or the
`Godot_v4.4.1-stable_export_templates.tpz` file from the Godot release page,
unzipped into `~/.local/share/godot/export_templates/4.4.1.stable/`).

```sh
godot --headless --path . --import                                   # build the class cache
godot --headless --path . --export-release "macOS"   ../build/RomanWar-macOS.zip
godot --headless --path . --export-release "Windows" ../build/RomanWar-Windows/RomanWar.exe
godot --headless --path . --export-release "Linux"   ../build/RomanWar-Linux/RomanWar.x86_64
```

The presets live in `export_presets.cfg` (tracked in git deliberately). Notes
that cost time to learn:

- **Apple Silicon requires a signature.** arm64 macOS refuses to launch a fully
  unsigned binary ("damaged and can't be opened"). The macOS preset therefore
  has `codesign/codesign=1` — Godot's built-in **ad-hoc** signer, which works
  even when exporting from Linux. Players still get the one-time Gatekeeper
  "unidentified developer" prompt (see PLAYING.md); real distribution later
  means an Apple Developer ID and notarization.
- **The macOS architecture must stay `universal`.** The stock export template
  only ships a universal (Intel+ARM) binary; thinning it to arm64-only needs
  Apple's `lipo`, which does not exist on Linux, so an arm64-only export fails
  with "template binary not found".
- **`import_etc2_astc=true`** in `project.godot` is required by the macOS
  export (arm64 wants that texture format available); without it the export
  refuses with a configuration error.
- Verify a build without owning every platform: the Linux export shares the
  same `.pck`, so
  `./RomanWar.x86_64 --headless --script <a probe script that runs Game.new_campaign and end_turn>`
  proves the package is complete and playable.

## No-build alternative (good for playtesters)

Install Godot 4.4+ from godotengine.org (drag to Applications), download this
repository as a ZIP (GitHub → green **Code** button → Download ZIP), unzip,
open Godot, **Import** the folder, press **Play** (▶). No coding involved —
Godot acts purely as a launcher.
