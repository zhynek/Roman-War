#!/usr/bin/env python3
"""Verify the packed local macOS app, without pointing it at editable source.

Each suite runs sequentially, with separate stdout/stderr and binary hashes.
Rendered QA output must be outside the repository. A failing process, missing
assertion summary, test failure or Godot error makes the gate fail.
"""
import argparse
import hashlib
import json
import re
import subprocess
import time
from pathlib import Path

RETAINED = ['defense_checks', 'visual_checks', 'construction_checks', 'checks',
            'governance_checks', 'neighbor_checks', 'household_checks', 'asset_checks',
            'land_checks', 'land_geometry_checks', 'living_checks', 'incident_checks',
            'fabric_lifecycle_checks', 'lifecycle_checks', 'town_checks']
NEW = ['tactical_checks', 'warfare_checks', 'fortification_checks', 'encounter_checks',
       'threat_checks', 'muster_checks', 'modes_checks', 'modes_host_checks',
       'aftermath_checks', 'command_budget_checks', 'readiness_presentation_checks',
       'tactical_scenarios_preview', 'defense_presentation_checks', 'fortification_presentation_checks']
RENDER = ['defense_preview', 'tactical_preview', 'tactical_camera_checks',
          'fortification_preview', 'modes_preview', 'aftermath_preview',
          'tactical_scenarios_preview']


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1048576), b''):
            value.update(chunk)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--only', nargs='+')
    args = parser.parse_args()
    app, out = args.app.resolve(), args.out.resolve()
    root = Path(__file__).resolve().parents[2]
    if args.render and (out == root or root in out.parents):
        raise RuntimeError('Rendered QA images must be outside the repository')
    if out.exists():
        raise RuntimeError('Use a new evidence directory; prior results are preserved')
    out.mkdir(parents=True)
    binary = app / 'Contents/MacOS/Yenikapı — Early Settlement'
    authority = [binary] + sorted(app.rglob('*.pck'))
    hashes = {str(p.relative_to(app)): digest(p) for p in authority}
    (out / 'app-manifest.json').write_text(json.dumps(hashes, indent=2) + '\n')
    results = []
    names = args.only or (RENDER if args.render else RETAINED + NEW)
    for name in names:
        if not re.fullmatch(r'[a-z_]+', name):
            raise RuntimeError('Invalid suite name')
        cmd = [str(binary)]
        cmd += ['--max-fps', '30'] if args.render else ['--headless']
        cmd += ['--script', 'res://tools/' + name + '.gd']
        if args.render or name in ['lifecycle_checks', 'town_checks', 'tactical_scenarios_preview']:
            cmd += ['--', 'out_dir=' + str(out / (name + '-artifacts'))]
            if args.render and name == 'tactical_scenarios_preview':
                cmd += ['render']
        print('START', name, flush=True)
        began = time.monotonic()
        with (out / (name + '.stdout.log')).open('w') as stdout, (out / (name + '.stderr.log')).open('w') as stderr:
            try:
                result = subprocess.run(cmd, cwd=out, stdout=stdout, stderr=stderr, timeout=900)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = 124
        stdout = (out / (name + '.stdout.log')).read_text()
        stderr = (out / (name + '.stderr.log')).read_text()
        combined = stdout + '\n' + stderr
        summaries = [{'checks': int(a), 'failures': int(b)} for a, b in
                     re.findall(r'(\d+) checks, (\d+) failures', combined, re.I)]
        errors = [line for line in combined.splitlines() if
                  re.search(r'SCRIPT ERROR|Parse Error|ERROR:|^FAIL\b|^FAILED\b', line)]
        entry = {'name': name, 'command': cmd, 'exit_code': code,
                 'seconds': round(time.monotonic() - began, 3), 'summaries': summaries,
                 'errors': errors, 'stderr_bytes': len(stderr.encode()),
                 'passed': code == 0 and not errors and bool(summaries)
                           and all(s['failures'] == 0 for s in summaries)}
        results.append(entry)
        (out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
        print('END', name, entry['seconds'], 'seconds', summaries, 'PASS' if entry['passed'] else 'FAIL', flush=True)
    unchanged = hashes == {str(p.relative_to(app)): digest(p) for p in authority}
    summary = {'packed_app': str(app), 'suites': len(results),
               'checks': sum(s['checks'] for r in results for s in r['summaries']),
               'failed': [r['name'] for r in results if not r['passed']],
               'app_unchanged': unchanged,
               'stderr_suites': [r['name'] for r in results if r['stderr_bytes']]}
    (out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary), flush=True)
    raise SystemExit(1 if summary['failed'] or not unchanged else 0)


if __name__ == '__main__':
    main()
