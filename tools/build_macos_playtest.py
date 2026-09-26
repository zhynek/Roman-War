#!/usr/bin/env python3
"""Export macOS feedback builds or an approved release from a source snapshot.

Preview builds isolate saves. --release uses the standard campaign save identity.
Full regression and rendered playtest gates must be run separately before delivery.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import zipfile


ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIRECTORIES = ("src", "data", "schemas", "tests", "tools")
SOURCE_FILES = ("project.godot", "export_presets.cfg")
MODES = {
    "campaign": {
        "name": "Roman War Playtest",
        "bundle_id": "com.romanwar.playtest",
        "scene": "res://src/ui/main.tscn",
        "save_directory": "Roman War Playtest",
    },
    "route": {
        "name": "Roman War Route Playtest",
        "bundle_id": "com.romanwar.playtest.route",
        "scene": "res://src/ui/realism/development.tscn",
        "save_directory": "Roman War Route Playtest",
    },
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_hashes(project):
    return {
        str(path.relative_to(project)): sha256(path)
        for path in sorted(project.rglob("*"))
        if path.is_file() and ".godot" not in path.relative_to(project).parts
    }


def set_config(path, section, key, value):
    """Change a single setting without rewriting Godot's Variant syntax."""
    text = path.read_text()
    match = re.search(r"^\[" + re.escape(section) + r"\]\n(.*?)(?=^\[|\Z)",
                      text, flags=re.MULTILINE | re.DOTALL)
    if match is None:
        raise SystemExit(f"Missing [{section}] in {path}")
    body = match.group(1)
    setting = f"{key}={json.dumps(value)}"
    pattern = r"^" + re.escape(key) + r"=.*$"
    if re.search(pattern, body, flags=re.MULTILINE):
        body = re.sub(pattern, lambda _: setting, body, flags=re.MULTILINE)
    else:
        body = body.rstrip() + "\n" + setting + "\n\n"
    path.write_text(text[:match.start(1)] + body + text[match.end(1):])


def run(command, log, cwd, reject_errors=False):
    print(f"Checking {log.stem}...", flush=True)
    result = subprocess.run([str(part) for part in command], cwd=cwd,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True)
    log.write_text(result.stdout)
    if result.returncode or (reject_errors and
                            ("SCRIPT ERROR:" in result.stdout or "ERROR:" in result.stdout)):
        raise SystemExit(f"Check failed (exit {result.returncode}); inspect {log}")
    return result.stdout.strip()


def git_output(*arguments):
    result = subprocess.run(["git", *arguments], cwd=ROOT,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        raise SystemExit("Build from the repository checkout so source provenance is available.")
    return result.stdout.rstrip("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot"),
                        help="Godot editor executable with matching macOS export templates")
    parser.add_argument("--mode", choices=MODES, default="campaign")
    parser.add_argument("--version", default="0.14.1-preview.20260926")
    parser.add_argument("--release", action="store_true",
                        help="Use standard app identities; requires a numeric --version")
    parser.add_argument("--output", type=Path,
                        help="Fresh output directory (default: build/playtest-2026-09-26/<mode>)")
    parser.add_argument("--skip-package-probe", action="store_true",
                        help="Skip the packaged campaign/save probe; record that it was not run")
    args = parser.parse_args()
    if not args.godot:
        parser.error("Supply --godot with the Godot 4.4.1 editor executable")
    godot = Path(shutil.which(args.godot) or args.godot).expanduser().resolve()
    if not godot.is_file() or not os.access(godot, os.X_OK):
        parser.error(f"Godot is not executable: {godot}")
    version_match = re.fullmatch(r"(\d+\.\d+\.\d+)" if args.release else
                                r"(\d+\.\d+\.\d+)-preview\.[A-Za-z0-9.-]+", args.version)
    if version_match is None:
        parser.error("Use a numeric version with --release, otherwise an explicit -preview version")
    numeric_version = version_match.group(1)
    mode = MODES[args.mode].copy()
    if args.release:
        mode.update({"name": "Roman War" if args.mode == "campaign" else "Roman War Alpine Route",
                     "bundle_id": "com.romanwar.game" if args.mode == "campaign" else "com.romanwar.alpine-route",
                     "save_directory": "Godot/app_userdata/Roman War" if args.mode == "campaign" else "Roman War Alpine Route"})
    default_output = ROOT / "build" / (f"v{args.version}" if args.release else "playtest-2026-09-26") / args.mode
    destination = (args.output or default_output).expanduser().resolve()
    if destination.exists() and not destination.is_dir():
        parser.error(f"Output path must be a directory: {destination}")
    if destination.exists() and any(destination.iterdir()):
        parser.error(f"Output directory must be empty; preserve previous builds: {destination}")
    # Never put outputs inside a directory that will be included in the snapshot.
    for folder in SOURCE_DIRECTORIES:
        if destination == ROOT / folder or ROOT / folder in destination.parents:
            parser.error("Output directory cannot be inside a source directory")

    commit = git_output("rev-parse", "HEAD")
    status = git_output("status", "--porcelain=v1", "--untracked-files=all")
    if args.release and status:
        parser.error("Release builds require a clean committed checkout for exact tag provenance")
    destination.mkdir(parents=True, exist_ok=True)
    logs = destination / "verification"
    logs.mkdir()
    project = destination / "source"
    project.mkdir()
    # Copy only this project's complete runtime and validation inputs. There are
    # no separate fonts/assets directories; procedural art lives under src/data.
    ignore = shutil.ignore_patterns(".godot", "__pycache__", "*.pyc", ".DS_Store", "*.core")
    for folder in SOURCE_DIRECTORIES:
        shutil.copytree(ROOT / folder, project / folder, ignore=ignore)
    for filename in SOURCE_FILES:
        shutil.copy2(ROOT / filename, project / filename)
    original_hashes = source_hashes(project)

    config = project / "project.godot"
    for key, value in {
        "config/name": mode["name"], "config/version": args.version,
        "run/main_scene": mode["scene"], "config/use_custom_user_dir": not (args.release and args.mode == "campaign"),
        "config/custom_user_dir_name": mode["save_directory"],
    }.items():
        set_config(config, "application", key, value)
    presets = project / "export_presets.cfg"
    for key, value in {
        "application/bundle_identifier": mode["bundle_id"],
        "application/short_version": numeric_version,
        "application/version": numeric_version,
        "application/additional_plist_content":
            f"<key>RomanWarPlaytestVersion</key><string>{args.version}</string>",
        "binary_format/architecture": "universal",
        "codesign/codesign": 1, "notarization/notarization": 0,
    }.items():
        set_config(presets, "preset.0.options", key, value)
    if args.mode == "route":
        # The route scene explicitly overrides project storage before creating UI.
        # Patch only the snapshot; retain its disposable route-qa namespace.
        entry = project / "src/ui/realism/development_main.gd"
        text = entry.read_text()
        old = '"Roman War Campaign Route Development"'
        if text.count(old) != 1:
            raise SystemExit("Route storage entry changed; review save isolation before exporting.")
        entry.write_text(text.replace(old, json.dumps(mode["save_directory"])))
    frozen_hashes = source_hashes(project)
    snapshot = destination / "source-snapshot.zip"
    with zipfile.ZipFile(snapshot, "w", zipfile.ZIP_DEFLATED) as archive:
        for filename in frozen_hashes:
            archive.write(project / filename, filename)

    archive = destination / f"{mode['name'].replace(' ', '-')}-macOS-{args.version}.zip"
    provenance = {
        "version": args.version, "mode": args.mode, "development_only": not args.release,
        "built_at_utc": datetime.now(timezone.utc).isoformat(),
        "base_commit": commit, "source_dirty": bool(status), "source_status": status.splitlines(),
        "bundle_identifier": mode["bundle_id"], "entry_scene": mode["scene"],
        "save_directory": mode["save_directory"],
        "source_sha256_before_build_settings": original_hashes,
        "source_sha256": frozen_hashes, "source_snapshot_sha256": sha256(snapshot),
        "checks": {"full_suite": "Run separately before delivery",
                   "rendered_playtests": "Run separately before delivery"},
    }
    provenance_path = destination / "provenance.json"
    provenance_path.write_text(json.dumps(provenance, indent=2) + "\n")
    provenance["godot"] = run([godot, "--version"], logs / "godot-version.log", project)
    run([sys.executable, project / "tools/validate_data.py"], logs / "data-validation.log", project)
    provenance["checks"]["data_validation"] = "passed"
    run([godot, "--headless", "--path", project, "--import"], logs / "import.log", project, True)
    run([godot, "--headless", "--path", project, "--export-release", "macOS", archive],
        logs / "export.log", project, True)
    provenance["checks"]["import_and_release_export"] = "passed"
    changed = [name for name, digest in frozen_hashes.items()
               if not (project / name).is_file() or sha256(project / name) != digest]
    if changed:
        raise SystemExit(f"Staged source changed during build: {changed}")
    provenance["archive"] = archive.name
    provenance["archive_sha256"] = sha256(archive)
    provenance["archive_bytes"] = archive.stat().st_size
    provenance["checks"].update({"signature": "not run (requires macOS)",
                                  "architectures": "not run (requires macOS)",
                                  "package_probe": "not run"})
    if platform.system() == "Darwin":
        run(["ditto", "-x", "-k", archive, destination], logs / "unpack.log", project)
        app = destination / f"{mode['name']}.app"
        with (app / "Contents/Info.plist").open("rb") as source:
            info = plistlib.load(source)
        expected = {"CFBundleIdentifier": mode["bundle_id"],
                    "CFBundleShortVersionString": numeric_version,
                    "CFBundleVersion": numeric_version, "RomanWarPlaytestVersion": args.version}
        if any(info.get(key) != value for key, value in expected.items()):
            raise SystemExit("Exported app metadata does not match the requested playtest identity")
        binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
        run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", app],
            logs / "signature.log", project)
        architectures = run(["lipo", "-archs", binary], logs / "architectures.log", project).split()
        if set(architectures) != {"arm64", "x86_64"}:
            raise SystemExit(f"Expected both macOS architectures; found {architectures}")
        provenance["architectures"] = architectures
        provenance["checks"]["signature"] = "ad-hoc verified; not Developer ID notarized"
        provenance["checks"]["architectures"] = "passed"
        if not args.skip_package_probe:
            probe = run([binary, "--headless", "--script", "res://tools/build_probe.gd"],
                        logs / "package-probe.log", destination, True)
            if "probe OK" not in probe:
                raise SystemExit("Packaged campaign/save probe did not confirm success")
            provenance["checks"]["package_probe"] = "passed"
    provenance_path.write_text(json.dumps(provenance, indent=2) + "\n")
    (destination / "SHA256SUMS.txt").write_text(f"{sha256(archive)}  {archive.name}\n")
    print(archive)


if __name__ == "__main__":
    main()
