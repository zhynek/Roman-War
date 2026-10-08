#!/usr/bin/env python3
"""Freeze the authorized dirty village worktree and export a separate local app.

No checkout/reset, commit, download, push, release replacement, or QA screenshots.
Run final verification on the returned exact binary, then --finalize to checksum
all delivery files (including the verification records copied into the folder).
"""
import argparse
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / 'Castles and Cities/sites/yenikapi_6000_bce/experience'
APP = 'Yenikapı — Early Settlement.app'
IGNORE = {'.godot', '__pycache__', '.DS_Store'}


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1048576), b''):
            value.update(chunk)
    return value.hexdigest()


def manifest(folder):
    return {str(p.relative_to(folder)): digest(p) for p in sorted(folder.rglob('*'))
            if p.is_file() and not any(x in IGNORE for x in p.relative_to(folder).parts)}


def run(args, log, cwd):
    result = subprocess.run([str(a) for a in args], cwd=cwd, capture_output=True, text=True)
    log.write_text(result.stdout + result.stderr)
    if result.returncode or re.search(r'SCRIPT ERROR|(?:^|\n)ERROR:', result.stdout + result.stderr):
        raise RuntimeError(f'Command failed or emitted Godot errors: {args}; see {log}')
    return result.stdout.strip()


def finalize(out):
    if not (out / '.local-warfare-build').is_file():
        raise RuntimeError('This is not a local warfare delivery directory')
    source = out / 'source'
    expected = json.loads((out / 'source-manifest.json').read_text())
    if manifest(source) != expected:
        raise RuntimeError('Frozen source changed; create a new local build before finalizing')
    with zipfile.ZipFile(out / 'Village-Warfare-source.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for relative in expected:
            archive.write(source / relative, 'source/' + relative)
    provenance = json.loads((out / 'provenance.json').read_text())
    provenance['delivery_recorded_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    provenance['source_manifest_sha256'] = digest(out / 'source-manifest.json')
    provenance['macos_archive_sha256'] = digest(out / 'Village-Warfare-macOS.zip')
    provenance['source_archive_sha256'] = digest(out / 'Village-Warfare-source.zip')
    provenance['app_files'] = manifest(out / APP)
    (out / 'provenance.json').write_text(json.dumps(provenance, indent=2, ensure_ascii=False) + '\n')
    paths = sorted(p for p in out.rglob('*') if p.is_file()
                   and not any(x in IGNORE for x in p.relative_to(out).parts)
                   and p.name != 'SHA256SUMS.txt')
    (out / 'SHA256SUMS.txt').write_text(''.join(f'{digest(p)}  {p.relative_to(out)}\n' for p in paths))
    print(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--finalize', action='store_true')
    args = parser.parse_args()
    out = args.out.resolve()
    if args.finalize:
        finalize(out)
        return
    if out.exists():
        raise RuntimeError('Refusing to replace any existing directory; choose a new local output')
    if not args.godot or not args.godot.is_file():
        raise RuntimeError('Pass an installed Godot 4.4.1 executable with --godot')
    godot = args.godot.resolve()
    out.mkdir(parents=True)
    (out / '.local-warfare-build').write_text('Unpublished local worktree snapshot; no release was replaced.\n')
    logs = out / 'verification'
    logs.mkdir()
    source = out / 'source'
    shutil.copytree(PROJECT, source, ignore=lambda _path, names: [n for n in names if n in IGNORE])
    frozen = manifest(source)
    (out / 'source-manifest.json').write_text(json.dumps(frozen, indent=2, ensure_ascii=False) + '\n')
    revision = run(['git', 'rev-parse', 'HEAD'], logs / 'source-revision.log', ROOT)
    branch = run(['git', 'branch', '--show-current'], logs / 'source-branch.log', ROOT)
    status = run(['git', 'status', '--porcelain=v1'], logs / 'source-worktree.log', ROOT)
    provenance = {'format': 'roman-war-local-village-build-v1',
                  'repository': 'https://github.com/zhynek/Roman-War',
                  'parent_revision': revision, 'branch': branch, 'worktree_dirty': bool(status),
                  'source_contract': 'Exact editable snapshot and per-file checksums; includes authorized uncommitted work.',
                  'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  'godot': str(godot), 'app': APP,
                  'verification': 'See verification logs and VERIFICATION-WARFARE.md; packaging alone does not assert tests passed.',
                  'art': 'Original procedural village and figures. No QA images or external game images bundled.'}
    (out / 'provenance.json').write_text(json.dumps(provenance, indent=2, ensure_ascii=False) + '\n')
    run([godot, '--headless', '--path', source, '--import'], logs / 'frozen-import.log', ROOT)
    if manifest(source) != frozen:
        raise RuntimeError('Import modified frozen source; import the working source first and use a new output directory')
    run([godot, '--headless', '--path', source, '--export-release', 'macOS', out / 'Village-Warfare-macOS.zip'], logs / 'export.log', ROOT)
    run(['ditto', '-x', '-k', out / 'Village-Warfare-macOS.zip', out], logs / 'unpack.log', ROOT)
    binary = out / APP / 'Contents/MacOS/Yenikapı — Early Settlement'
    run(['lipo', '-archs', binary], logs / 'architectures.log', ROOT)
    run(['codesign', '--verify', '--deep', '--strict', out / APP], logs / 'codesign.log', ROOT)
    finalize(out)
    print('Exact binary:', binary)


if __name__ == '__main__':
    main()
