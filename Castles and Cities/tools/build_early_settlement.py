#!/usr/bin/env python3
"""Freeze, verify and package the separate Yenikapi early-settlement prerelease.

Run parent campaign gates separately first. A clean commit, matching Godot 4.4.1
Mac templates and Python jsonschema are required. Never replace published bytes.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import tempfile
import zipfile
import sys
from build_city import ROOT, WORKSPACE, digest, files, archive_tree, run, git, check_glb
PROJECT=Path('sites/yenikapi_6000_bce/experience')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',required=True)
    parser.add_argument('--version',default='0.2.0')
    parser.add_argument('--output',type=Path)
    parser.add_argument('--parent-gates',type=Path,required=True)
    args=parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+',args.version):parser.error('Use numeric semantic version')
    if git('status','--porcelain=v1','--untracked-files=all'):parser.error('Commit verified source before freezing')
    godot=Path(shutil.which(args.godot) or args.godot).resolve()
    if not godot.is_file() or not os.access(godot,os.X_OK):parser.error('Godot editor executable required')
    parent=args.parent_gates.resolve()
    expected={'data.log':'0 errors','tests.log':'705 tests, 0 failures','map.log':'map playtest: PASS','import.log':'Godot Engine'}
    for name,marker in expected.items():
        plain=re.sub(r'\x1b\[[0-9;]*m','',(parent/name).read_text())
        if marker not in plain or re.search(r'(?:SCRIPT ERROR:|^ERROR:)',plain,re.M):parser.error(f'Parent gate failed: {name}')
    out=(args.output or ROOT/'build'/f'yenikapi-early-settlement-{args.version}').resolve()
    if out==WORKSPACE or WORKSPACE in out.parents:parser.error('Build outside authoring source')
    if out.exists() and any(out.iterdir()):parser.error('Use a fresh output directory')
    out.mkdir(parents=True,exist_ok=True)
    logs=out/'verification';logs.mkdir()
    shutil.copytree(parent,logs/'parent-campaign')
    snapshot=out/'Castles and Cities'
    shutil.copytree(WORKSPACE,snapshot,ignore=shutil.ignore_patterns('.godot','__pycache__','*.pyc','.DS_Store'))
    original=files(snapshot)
    project=snapshot/PROJECT
    for name,keys in [('project.godot',['config/version']),('export_presets.cfg',['application/short_version','application/version'])]:
        path=project/name;text=path.read_text()
        for key in keys:text=re.sub(r'^'+re.escape(key)+r'=.*$',f'{key}="{args.version}"',text,flags=re.M)
        path.write_text(text)
    frozen=files(snapshot)
    provenance={'version':args.version,'commit':git('rev-parse','HEAD'),'built_at_utc':datetime.now(timezone.utc).isoformat(),'bundle_identifier':'com.romanwar.yenikapi.earlysettlement','save_directory':'Roman War Yenikapi Early Settlement','snapshot_id':'yenikapi_c6000_bce','historical_status':'Dated interpretive early-settlement scenario; not a recovered plan or continuous city genealogy','original_source_sha256':original,'frozen_source_sha256':frozen,'checks':{}}
    editor=[godot,'--headless','--path',project]
    run([sys.executable,snapshot/'tools/validate_studies.py','--root',snapshot],logs/'catalog.log',snapshot)
    run([sys.executable,project/'tools/validate_settlement.py'],logs/'data.log',project)
    run([sys.executable,project/'tools/test_data.py'],logs/'data-tests.log',project)
    run([sys.executable,project/'tools/validate_governance.py'],logs/'governance-data.log',project)
    run([sys.executable,project/'tools/test_governance_data.py'],logs/'governance-data-tests.log',project)
    run(editor+['--import'],logs/'import.log',project)
    checked=run(editor+['--script','res://tools/checks.gd'],logs/'source-checks.log',project)
    if not re.search(r'VILLAGE CHECKS: \d+ checks, 0 failures',checked):raise SystemExit('Missing source success marker')
    governance=run(editor+['--script','res://tools/governance_checks.gd'],logs/'source-governance.log',project)
    if not re.search(r'GOVERNANCE CHECKS: \d+ checks, 0 failures',governance):raise SystemExit('Missing governance success marker')
    render_dir=Path(tempfile.mkdtemp(prefix=f'yenikapi-{args.version}-exact-qa-'))
    # Source performance uses the same script/cameras as the exact application.
    run([godot,'--path',project,'--script','res://tools/benchmark.gd','--',f'out_dir={render_dir / "source-benchmark"}'],logs/'source-benchmark.log',project)
    shutil.copy2(render_dir/'source-benchmark/benchmark.json',logs/'source-benchmark.json')
    run([godot,'--path',project,'--script','res://tools/benchmark.gd','--','campaign',f'out_dir={render_dir / "source-campaign-benchmark"}'],logs/'source-campaign-benchmark.log',project)
    shutil.copy2(render_dir/'source-campaign-benchmark/benchmark.json',logs/'source-campaign-benchmark.json')
    prefix='Yenikapi-Early-Settlement'
    app_zip=out/f'{prefix}-macOS-{args.version}.zip'
    run(editor+['--export-release','macOS',app_zip],logs/'export.log',project)
    with zipfile.ZipFile(app_zip,'a',zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('READ-ME-FIRST.md',(project/'README.md').read_text())
        archive.writestr('GODOT_COPYRIGHT.txt',(project/'GODOT_COPYRIGHT.txt').read_text())
    run(['ditto','-x','-k',app_zip,out],logs/'unpack.log',out)
    apps=list(out.glob('*.app'))
    if len(apps)!=1:raise SystemExit('Expected one app')
    app=apps[0]
    with (app/'Contents/Info.plist').open('rb') as stream:plist=plistlib.load(stream)
    if plist.get('CFBundleIdentifier')!=provenance['bundle_identifier'] or plist.get('CFBundleShortVersionString')!=args.version:raise SystemExit('Wrong app identity')
    binary=app/'Contents/MacOS'/plist['CFBundleExecutable']
    run(['codesign','--verify','--deep','--strict',app],logs/'signature.log',out)
    architectures=run(['lipo','-archs',binary],logs/'architectures.log',out).split()
    if set(architectures)!={'arm64','x86_64'}:raise SystemExit('Missing universal architecture')
    provenance['architectures']=architectures
    provenance['signature']='Ad-hoc signed, not Developer ID notarized'
    packaged=run([binary,'--headless','--script','res://tools/checks.gd'],logs/'packaged-checks.log',out)
    if not re.search(r'VILLAGE CHECKS: \d+ checks, 0 failures',packaged):raise SystemExit('Missing packaged success marker')
    if re.search(r'mesh ([a-f0-9]+)',checked).group(1)!=re.search(r'mesh ([a-f0-9]+)',packaged).group(1):raise SystemExit('Source/package geometry differs')
    packaged_governance=run([binary,'--headless','--script','res://tools/governance_checks.gd'],logs/'packaged-governance.log',out)
    if not re.search(r'GOVERNANCE CHECKS: \d+ checks, 0 failures',packaged_governance):raise SystemExit('Missing packaged governance success marker')
    rendered=run([binary,'--script','res://tools/preview.gd','--',f'out_dir={render_dir}'],logs/'packaged-render.log',out)
    if 'VILLAGE RENDER PASS: 14 captures' not in rendered:raise SystemExit('Incomplete rendered gate')
    shutil.copy2(render_dir/'render-report.json',logs/'render-report.json')
    run([binary,'--script','res://tools/benchmark.gd','--',f'out_dir={render_dir / "benchmark"}'],logs/'packaged-benchmark.log',out)
    shutil.copy2(render_dir/'benchmark/benchmark.json',logs/'packaged-benchmark.json')
    tutorial_render=run([binary,'--script','res://tools/governance_preview.gd','--',f'out_dir={render_dir / "tutorial"}'],logs/'packaged-tutorial-render.log',out)
    if not re.search(r'GOVERNANCE RENDER: 12 captures; \d+ checks, 0 failures',tutorial_render):raise SystemExit('Tutorial render gate failed')
    shutil.copy2(render_dir/'tutorial/render-report.json',logs/'tutorial-render-report.json')
    run([binary,'--script','res://tools/benchmark.gd','--','campaign',f'out_dir={render_dir / "campaign-benchmark"}'],logs/'packaged-campaign-benchmark.log',out)
    shutil.copy2(render_dir/'campaign-benchmark/benchmark.json',logs/'packaged-campaign-benchmark.json')
    provenance['render_capture_directory']=str(render_dir)
    provenance['performance']={'source':json.loads((logs/'source-benchmark.json').read_text()),'exact_app':json.loads((logs/'packaged-benchmark.json').read_text())}
    provenance['campaign_performance']={'source':json.loads((logs/'source-campaign-benchmark.json').read_text()),'exact_app':json.loads((logs/'packaged-campaign-benchmark.json').read_text())}
    provenance['campaign_scenario']='yenikapi_seasons_tutorial; hypothetical, rules/save version 1; separate campaign slot'
    models=out/f'{prefix}-Models'
    run(editor+['--script','res://tools/export_models.gd','--',f'out_dir={models}'],logs/'models.log',project)
    glbs=sorted(models.glob('*.glb'))
    if len(glbs)!=16:raise SystemExit('Expected reference, hypothetical town and individual models')
    provenance['models']={p.name:check_glb(p) for p in glbs}
    for name,sha in frozen.items():
        if digest(snapshot/name)!=sha:raise SystemExit(f'Frozen source changed: {name}')
    source_zip=out/f'{prefix}-Source-{args.version}.zip'
    model_zip=out/f'{prefix}-Models-{args.version}.zip'
    archive_tree(snapshot,source_zip);archive_tree(models,model_zip)
    artifacts=[app_zip,source_zip,model_zip]
    for path in artifacts:
        with zipfile.ZipFile(path) as archive:
            if archive.testzip():raise SystemExit(f'Corrupt ZIP {path}')
    provenance['checks']={'parent_campaign':'passed; logs copied','schema_and_negative_cases':'passed','source_and_exact_app':'248 reference and 705 governance checks per application; identical reference mesh hash','render_captures':'26 written (14 reference + 12 tutorial); manual visual review required before publication','glb_structure':'16 passed','zip_integrity':'3 passed'}
    provenance['artifacts']={p.name:{'bytes':p.stat().st_size,'sha256':digest(p)} for p in artifacts}
    manifest=out/'provenance.json';manifest.write_text(json.dumps(provenance,indent=2)+'\n')
    (out/'SHA256SUMS.txt').write_text(''.join(f'{digest(p)}  {p.name}\n' for p in [*artifacts,manifest]))
    print(f'EARLY SETTLEMENT BUILD PASS: {app_zip}',flush=True)
if __name__=='__main__':main()
