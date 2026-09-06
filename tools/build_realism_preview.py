#!/usr/bin/env python3
"""Build a separate macOS development app without editing production settings.

python3 tools/build_realism_preview.py --godot /path/to/Godot
The source tree (including local edits) is copied into a temporary project.
The normal main scene, release name, app bundle and user saves are untouched.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def run_godot(binary, args, log):
    result = subprocess.run([binary, *args], stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    log.write_text(result.stdout)
    if result.returncode or "SCRIPT ERROR:" in result.stdout or "ERROR:" in result.stdout:
        raise SystemExit(f"Godot failed; inspect {log}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot"))
    parser.add_argument("--campaign", action="store_true", help="Build the integrated terrain development app")
    args = parser.parse_args()
    if not args.godot:
        parser.error("Supply --godot with the local Godot 4.4+ executable")
    destination = ROOT / "build" / ("terrain-preview" if args.campaign else "realism-study")
    name = "Roman War Terrain Preview" if args.campaign else "Roman War Realism Study"
    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / (name.replace(" ", "-") + ".zip")
    with tempfile.TemporaryDirectory(prefix="roman-realism-export-") as temp:
        project = Path(temp) / "project"
        shutil.copytree(ROOT, project, ignore=shutil.ignore_patterns(
            ".git", ".godot", "build", ".venv", "__pycache__", ".DS_Store"))
        config = project / "project.godot"
        config.write_text(config.read_text()
                          .replace('config/name="Roman War"',
                                   f'config/name="{name}"')
                          .replace('run/main_scene="res://src/ui/main.tscn"',
                                   'run/main_scene="res://src/ui/realism/development.tscn"'))
        presets = project / "export_presets.cfg"
        presets.write_text(presets.read_text().replace(
            'application/bundle_identifier="com.romanwar.game"',
            'application/bundle_identifier="com.romanwar.terrain-preview"' if args.campaign else 'application/bundle_identifier="com.romanwar.realism-study"'))
        run_godot(args.godot, ["--headless", "--path", str(project), "--import"],
                  destination / "import.log")
        run_godot(args.godot, ["--headless", "--path", str(project),
                              "--export-debug", "macOS", str(archive)],
                  destination / "export.log")
    print(archive)


if __name__ == "__main__":
    main()
