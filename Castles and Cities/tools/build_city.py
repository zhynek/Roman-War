#!/usr/bin/env python3
"""Freeze, verify and export the isolated Constantinople city study for macOS.

Requires Godot 4.4.1 with matching universal macOS export templates, jsonschema,
and a clean committed repository. Full campaign regression gates run separately.
Generated binaries, models and logs stay under ignored build/. QA images are
written to a temporary directory outside the repository.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

WORKSPACE = Path(__file__).resolve().parents[1]
ROOT = WORKSPACE.parent
EXPERIENCE = Path("realms/byzantine_empire/cities/constantinople_1200/experience")


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def files(folder):
    return {str(p.relative_to(folder)): digest(p) for p in sorted(folder.rglob("*"))
            if p.is_file() and not any(part in (".godot", "__pycache__")
                                       for part in p.relative_to(folder).parts)}


def archive_tree(folder, target):
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name in files(folder):
            archive.write(folder / name, str(Path(folder.name) / name))


def run(command, log, cwd):
    print(f"Checking {log.stem}...", flush=True)
    result = subprocess.run([str(x) for x in command], cwd=cwd, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900)
    log.write_text(result.stdout)
    plain = re.sub(r"\x1b\[[0-9;]*m", "", result.stdout)
    if result.returncode or re.search(r"(?:SCRIPT ERROR:|^ERROR:)", plain, re.M):
        raise SystemExit(f"Failed {log.stem} (exit {result.returncode}): {log}")
    return result.stdout


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def check_glb(path):
    # Verify the complete GLB container plus position/index buffer bounds, not
    # just its extension or a successful exporter exit status.
    content = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", content)
    if magic != b"glTF" or version != 2 or length != len(content):
        raise ValueError(f"Malformed GLB: {path}")
    json_length, chunk_type = struct.unpack_from("<II", content, 12)
    if chunk_type != 0x4E4F534A:
        raise ValueError(f"Missing glTF JSON: {path}")
    model = json.loads(content[20:20 + json_length])
    if not model.get("meshes") or not model.get("nodes"):
        raise ValueError(f"Empty model: {path}")
    buffers = model.get("buffers", [])
    views = model.get("bufferViews", [])
    for view in views:
        if view.get("byteOffset", 0) + view["byteLength"] > buffers[view["buffer"]]["byteLength"]:
            raise ValueError(f"Out-of-bounds glTF buffer view: {path}")
    for accessor in model.get("accessors", []):
        if accessor.get("count", 0) <= 0:
            raise ValueError(f"Empty glTF accessor: {path}")
    return {"bytes": len(content), "meshes": len(model["meshes"]), "nodes": len(model["nodes"])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--version", default="0.2.0")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("Use a numeric semantic version")
    godot = Path(shutil.which(args.godot) or args.godot).expanduser().resolve()
    if not godot.is_file() or not os.access(godot, os.X_OK):
        parser.error("Godot must be an executable editor with macOS templates")
    if git("status", "--porcelain=v1", "--untracked-files=all"):
        parser.error("Commit the verified source first; downloadable releases require a clean checkout")
    out = (args.output or ROOT / "build" / f"constantinople-{args.version}").resolve()
    if out == WORKSPACE or WORKSPACE in out.parents:
        parser.error("Do not put build products inside their source workspace")
    if out.exists() and any(out.iterdir()):
        parser.error("Use a fresh output directory to preserve earlier artifacts")
    out.mkdir(parents=True, exist_ok=True)
    logs = out / "verification"
    logs.mkdir()
    snapshot = out / "Castles and Cities"
    shutil.copytree(WORKSPACE, snapshot,
                    ignore=shutil.ignore_patterns(".godot", "__pycache__", "*.pyc", ".DS_Store"))
    project = snapshot / EXPERIENCE
    original = files(snapshot)
    config = project / "project.godot"
    config.write_text(re.sub(r'^config/version=.*$', f'config/version="{args.version}"',
                            config.read_text(), flags=re.M))
    preset = project / "export_presets.cfg"
    text = preset.read_text()
    for key in ("application/short_version", "application/version"):
        text = re.sub(r"^" + re.escape(key) + r"=.*$", f'{key}="{args.version}"', text, flags=re.M)
    preset.write_text(text)
    frozen = files(snapshot)
    provenance = {"version": args.version, "commit": git("rev-parse", "HEAD"),
                  "built_at_utc": datetime.now(timezone.utc).isoformat(),
                  "bundle_identifier": "com.romanwar.constantinople.study",
                  "save_directory": "Roman War Constantinople Study",
                  "original_source_sha256": original, "frozen_source_sha256": frozen,
                  "checks": {}, "historical_status": "Interpretive reconstruction; not a survey"}
    editor = [godot, "--headless", "--path", project]
    run([sys.executable, project / "tools/validate_city.py", "--godot", godot],
        logs / "city-validation.log", project)
    run(editor + ["--import"], logs / "import.log", project)
    run(editor + ["--script", "res://tools/smoke.gd"], logs / "source-smoke.log", project)
    focused_gates = ("navigation_checks", "landmark_checks", "surface_checks")
    for gate in focused_gates:
        run(editor + ["--script", f"res://tools/{gate}.gd"], logs / f"source-{gate}.log", project)
    provenance["checks"]["source_validation_and_smoke"] = "passed"
    app_zip = out / f"Constantinople-1200-macOS-{args.version}.zip"
    run(editor + ["--export-release", "macOS", app_zip], logs / "export.log", project)
    with zipfile.ZipFile(app_zip, "a", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("READ-ME-FIRST.md", (project / "README.md").read_text())
        archive.writestr("GODOT_COPYRIGHT.txt", (project / "GODOT_COPYRIGHT.txt").read_text())
    run(["ditto", "-x", "-k", app_zip, out], logs / "unpack.log", out)
    applications = list(out.glob("*.app"))
    if len(applications) != 1:
        raise SystemExit("Expected exactly one exported Mac app")
    app = applications[0]
    with (app / "Contents/Info.plist").open("rb") as stream:
        plist = plistlib.load(stream)
    if (plist.get("CFBundleIdentifier") != provenance["bundle_identifier"] or
            plist.get("CFBundleShortVersionString") != args.version):
        raise SystemExit("Packaged app identity/version mismatch")
    binary = app / "Contents/MacOS" / plist["CFBundleExecutable"]
    run(["codesign", "--verify", "--deep", "--strict", app], logs / "signature.log", out)
    arch = run(["lipo", "-archs", binary], logs / "architectures.log", out).split()
    if set(arch) != {"arm64", "x86_64"}:
        raise SystemExit(f"Not a universal Mac app: {arch}")
    provenance["architectures"] = arch
    provenance["signature"] = "Ad-hoc signed; not Developer ID notarized"
    output = run([binary, "--headless", "--script", "res://tools/smoke.gd"],
                 logs / "packaged-smoke.log", out)
    if "CITY SMOKE PASS" not in output:
        raise SystemExit("Packaged smoke test did not confirm success")
    for gate in focused_gates:
        run([binary, "--headless", "--script", f"res://tools/{gate}.gd"],
            logs / f"packaged-{gate}.log", out)
    render_dir = Path(tempfile.mkdtemp(prefix=f"constantinople-{args.version}-qa-"))
    run([binary, "--script", "res://tools/preview.gd", "--", f"out_dir={render_dir}"],
        logs / "packaged-render.log", out)
    shutil.copy2(render_dir / "render-report.json", logs / "render-report.json")
    provenance["render_capture_directory"] = str(render_dir)
    provenance["checks"]["exact_packaged_smoke_and_render"] = "passed"
    models = out / "Constantinople-1200-Models"
    run(editor + ["--script", "res://tools/export_models.gd", "--", f"out_dir={models}"],
        logs / "model-export.log", project)
    model_files = sorted(models.glob("*.glb"))
    city_data = json.loads((project / "data/city.json").read_text())
    architecture = json.loads((project / "data/architecture.json").read_text())
    if len(model_files) != len(city_data["landmarks"]) + len(architecture["types"]) + 1:
        raise SystemExit("Missing city, landmark or architectural type models")
    provenance["models"] = {p.name: check_glb(p) for p in model_files}
    provenance["checks"]["glb_structure"] = "passed"
    changed = [name for name, sha in frozen.items() if digest(snapshot / name) != sha]
    if changed:
        raise SystemExit(f"Frozen source changed during export: {changed}")
    source_zip = out / f"Constantinople-1200-Source-{args.version}.zip"
    model_zip = out / f"Constantinople-1200-Models-{args.version}.zip"
    archive_tree(snapshot, source_zip)
    archive_tree(models, model_zip)
    artifacts = [app_zip, source_zip, model_zip]
    provenance["artifacts"] = {p.name: {"bytes": p.stat().st_size, "sha256": digest(p)} for p in artifacts}
    manifest = out / "provenance.json"
    manifest.write_text(json.dumps(provenance, indent=2) + "\n")
    (out / "SHA256SUMS.txt").write_text("".join(f"{digest(p)}  {p.name}\n" for p in [*artifacts, manifest]))
    print(f"CITY BUILD PASS: {app_zip}", flush=True)


if __name__ == "__main__":
    main()
