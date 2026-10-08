#!/usr/bin/env python3
"""Run source-only independent village gates; never build, export or publish.

All suites are sequential because retained tests share temporary save slots.
Logs, source checksums and rendered QA belong outside the repository.
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
from pathlib import Path

from verify_village_warfare_export import RETAINED, NEW

ROOT = Path(__file__).resolve().parents[2]
EXPERIENCE = ROOT / 'Castles and Cities/sites/yenikapi_6000_bce/experience'
RENDER = ['lifecycle_preview', 'town_preview', 'defense_preview',
          'tactical_preview', 'tactical_camera_checks', 'fortification_preview',
          'modes_preview', 'aftermath_preview', 'tactical_scenarios_preview',
          'integration_guide_preview']
ERROR = re.compile(r'SCRIPT ERROR|Parse Error|ERROR:|^FAIL\b|^FAILED\b|Traceback', re.M)


def source_manifest():
    return {str(p.relative_to(EXPERIENCE)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(EXPERIENCE.rglob('*')) if p.is_file()
            and p.suffix in ['.gd', '.json', '.py', '.godot', '.tscn', '.tres', '.cfg']
            and not any(part.startswith('.') or part == '__pycache__'
                        for part in p.relative_to(EXPERIENCE).parts)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--python', default=sys.executable)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--phase', choices=['data', 'headless', 'render', 'all'], default='all',
                        help='all means data and headless; rendered checks require an explicit render phase')
    parser.add_argument('--only', nargs='+', help='Restrict to named gates in the selected phase')
    args = parser.parse_args()
    out = args.out.resolve()
    if out == ROOT or ROOT in out.parents:
        parser.error('Evidence must be outside the repository')
    if out.exists():
        parser.error('Choose a new evidence directory; previous logs are never overwritten')
    out.mkdir(parents=True)
    godot = str(Path(args.godot).resolve()) if '/' in args.godot else args.godot
    # Keep the virtualenv executable path: resolving its symlink loses site-packages.
    python = str(Path(args.python).absolute()) if '/' in args.python else args.python
    manifest = source_manifest()
    (out / 'source-sha256.json').write_text(json.dumps(manifest, indent=2) + '\n')
    gates = []
    if args.phase in ['data', 'all']:
        gates.append(('catalog', [python, str(ROOT / 'Castles and Cities/tools/validate_studies.py'),
                                  '--root', str(ROOT / 'Castles and Cities')], 'data'))
        for pattern in ['validate_*.py', 'test_*.py']:
            for path in sorted((EXPERIENCE / 'tools').glob(pattern)):
                gates.append((path.stem, [python, str(path)], 'data'))
    if args.phase in ['headless', 'all']:
        gates.append(('village_import', [godot, '--headless', '--path', str(EXPERIENCE), '--import'], 'import'))
        names = {'checks', 'tactical_scenarios_preview'} | {
            p.stem for p in (EXPERIENCE / 'tools').glob('*_checks.gd')
            if p.stem != 'tactical_camera_checks'}
        missing = set(RETAINED + NEW) - names
        missing.update(name for name in names if not (EXPERIENCE / 'tools' / (name + '.gd')).is_file())
        if missing:
            parser.error('Required suites are missing: ' + ', '.join(sorted(missing)))
        for name in sorted(names):
            gates.append((name, [godot, '--headless', '--path', str(EXPERIENCE),
                                '--script', 'res://tools/' + name + '.gd', '--',
                                'out_dir=' + str(out / (name + '-artifacts'))], 'suite'))
    if args.phase == 'render':
        for name in RENDER:
            cmd = [godot, '--path', str(EXPERIENCE), '--max-fps', '30',
                   '--script', 'res://tools/' + name + '.gd', '--',
                   'out_dir=' + str(out / (name + '-artifacts'))]
            if name == 'tactical_scenarios_preview':
                cmd.append('render')
            gates.append((name, cmd, 'suite'))
    if args.only:
        unknown = set(args.only) - {g[0] for g in gates}
        if unknown:
            parser.error('Unknown gates: ' + ', '.join(sorted(unknown)))
        gates = [g for g in gates if g[0] in args.only]
    results = []
    for name, cmd, kind in gates:
        print('START', name, flush=True)
        began = time.monotonic()
        with (out / (name + '.stdout.log')).open('w') as stdout, (out / (name + '.stderr.log')).open('w') as stderr:
            try:
                code = subprocess.run(cmd, cwd=EXPERIENCE, stdout=stdout, stderr=stderr, timeout=1200).returncode
            except subprocess.TimeoutExpired:
                code = 124
        stdout = (out / (name + '.stdout.log')).read_text()
        stderr = (out / (name + '.stderr.log')).read_text()
        combined = stdout + '\n' + stderr
        summaries = [{'checks': int(a), 'failures': int(b)} for a, b in
                     re.findall(r'(\d+) checks, (\d+) failures', combined, re.I)]
        errors = [line for line in combined.splitlines() if ERROR.search(line)]
        result = {'name': name, 'kind': kind, 'command': cmd, 'exit_code': code,
                  'seconds': round(time.monotonic() - began, 3), 'summaries': summaries,
                  'python_tests': sum(map(int, re.findall(r'Ran (\d+) tests? in', combined))),
                  'errors': errors, 'stderr_bytes': len(stderr.encode()),
                  'warnings': [line for line in combined.splitlines() if 'WARNING:' in line],
                  'passed': code == 0 and not errors and (bool(summaries) or kind != 'suite')
                            and all(s['checks'] > 0 and s['failures'] == 0 for s in summaries)}
        results.append(result)
        (out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
        print('END', name, result['seconds'], 'seconds', summaries,
              'PASS' if result['passed'] else 'FAIL', flush=True)
        if errors:
            print('\n'.join(errors[:12]), flush=True)
    unchanged = manifest == source_manifest()
    summary = {'phase': args.phase, 'runs': len(results),
               'suites': sum(r['kind'] == 'suite' for r in results),
               'checks': sum(s['checks'] for r in results for s in r['summaries']),
               'python_tests': sum(r['python_tests'] for r in results),
               'failed': [r['name'] for r in results if not r['passed']],
               'source_unchanged': unchanged,
               'stderr_runs': [r['name'] for r in results if r['stderr_bytes']],
               'warning_runs': [r['name'] for r in results if r['warnings']]}
    (out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary), flush=True)
    raise SystemExit(1 if summary['failed'] or not unchanged else 0)


if __name__ == '__main__':
    main()
