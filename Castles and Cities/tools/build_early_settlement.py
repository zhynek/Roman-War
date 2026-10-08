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

def profile(command, log, cwd, marker):
    output=run(command,log,cwd)
    records=[line[len(marker):] for line in output.splitlines() if line.startswith(marker)]
    if len(records)!=1:raise SystemExit('Missing interaction profile: '+str(log))
    measured=json.loads(records[0])
    if measured.get('completed') is not True:raise SystemExit('Civic profile never completed: '+str(log))
    for key in ['lifecycle_open','lifecycle_reopen','commission','seasonal_refresh','civic_completion','unchanged_refresh']:
        if any(measured[key][field]<0 for field in ['callback_us','ready_us']):raise SystemExit('Invalid timing: '+str(log))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',required=True)
    parser.add_argument('--version',default='0.12.0')
    parser.add_argument('--output',type=Path)
    parser.add_argument('--retained-build',type=Path,required=True,help='Prior verified build whose model bytes must remain unchanged')
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
    run([sys.executable,project/'tools/test_neighbor_data.py'],logs/'neighbor-data-tests.log',project)
    run([sys.executable,project/'tools/validate_households.py'],logs/'household-data.log',project)
    run([sys.executable,project/'tools/test_household_data.py'],logs/'household-data-tests.log',project)
    run([sys.executable,project/'tools/validate_assets.py'],logs/'asset-data.log',project)
    run([sys.executable,project/'tools/test_asset_data.py'],logs/'asset-data-tests.log',project)
    run([sys.executable,project/'tools/validate_land.py'],logs/'land-data.log',project)
    run([sys.executable,project/'tools/test_land_data.py'],logs/'land-data-tests.log',project)
    run([sys.executable,project/'tools/validate_living.py'],logs/'living-data.log',project)
    run([sys.executable,project/'tools/test_living_data.py'],logs/'living-data-tests.log',project)
    run([sys.executable,project/'tools/validate_incidents.py'],logs/'incident-data.log',project)
    run([sys.executable,project/'tools/test_incident_data.py'],logs/'incident-data-tests.log',project)
    run([sys.executable,project/'tools/validate_visual_commands.py'],logs/'visual-data.log',project)
    run([sys.executable,project/'tools/validate_construction.py'],logs/'construction-data.log',project)
    run([sys.executable,project/'tools/validate_lifecycle.py'],logs/'lifecycle-data.log',project)
    run([sys.executable,project/'tools/test_lifecycle_data.py'],logs/'lifecycle-data-tests.log',project)
    run([sys.executable,project/'tools/validate_town.py'],logs/'town-data.log',project)
    run([sys.executable,project/'tools/test_town_data.py'],logs/'town-data-tests.log',project)
    run([sys.executable,project/'tools/validate_defense.py'],logs/'defense-data.log',project)
    run([sys.executable,project/'tools/test_defense_data.py'],logs/'defense-data-tests.log',project)
    run(editor+['--import'],logs/'import.log',project)
    defense=run(editor+['--script','res://tools/defense_checks.gd'],logs/'source-defense.log',project)
    if not re.search(r'VILLAGE DEFENSE: \d+ checks, 0 failures',defense):raise SystemExit('Defense rule checks failed')
    visual=run(editor+['--script','res://tools/visual_checks.gd'],logs/'source-visual.log',project)
    if not re.search(r'VISUAL CHECKS: \d+ checks, 0 failures',visual):raise SystemExit('Visual command checks failed')
    construction=run(editor+['--script','res://tools/construction_checks.gd'],logs/'source-construction.log',project)
    if not re.search(r'CONSTRUCTION CHECKS: \d+ checks, 0 failures',construction):raise SystemExit('Construction checks failed')
    checked=run(editor+['--script','res://tools/checks.gd'],logs/'source-checks.log',project)
    if not re.search(r'VILLAGE CHECKS: \d+ checks, 0 failures',checked):raise SystemExit('Missing source success marker')
    governance=run(editor+['--script','res://tools/governance_checks.gd'],logs/'source-governance.log',project)
    if not re.search(r'GOVERNANCE CHECKS: \d+ checks, 0 failures',governance):raise SystemExit('Missing governance success marker')
    neighbor=run(editor+['--script','res://tools/neighbor_checks.gd'],logs/'source-neighbors.log',project)
    if not re.search(r'NEIGHBOR CHECKS: \d+ checks, 0 failures',neighbor):raise SystemExit('Missing contact success marker')
    household=run(editor+['--script','res://tools/household_checks.gd'],logs/'source-households.log',project)
    if not re.search(r'HOUSEHOLD CHECKS: \d+ checks, 0 failures',household):raise SystemExit('Missing household success marker')
    assets=run(editor+['--script','res://tools/asset_checks.gd'],logs/'source-assets.log',project)
    if not re.search(r'ASSET CHECKS: \d+ checks, 0 failures',assets):raise SystemExit('Missing asset success marker')
    land=run(editor+['--script','res://tools/land_checks.gd'],logs/'source-land.log',project)
    if not re.search(r'LAND CHECKS: \d+ checks, 0 failures',land):raise SystemExit('Missing land success marker')
    geometry=run(editor+['--script','res://tools/land_geometry_checks.gd'],logs/'source-land-geometry.log',project)
    if not re.search(r'LAND GEOMETRY CHECKS: \d+ checks, 0 failures',geometry):raise SystemExit('Missing land geometry success marker')
    living=run(editor+['--script','res://tools/living_checks.gd'],logs/'source-living.log',project)
    if not re.search(r'LIVING CHECKS: \d+ checks, 0 failures',living):raise SystemExit('Missing living success marker')
    incidents=run(editor+['--script','res://tools/incident_checks.gd'],logs/'source-incidents.log',project)
    if not re.search(r'INCIDENT CHECKS: \d+ checks, 0 failures',incidents):raise SystemExit('Missing incident success marker')
    fabric_lifecycle=run(editor+['--script','res://tools/fabric_lifecycle_checks.gd'],logs/'source-fabric-lifecycle.log',project)
    if not re.search(r'Fabric lifecycle checks: \d+ checks, 0 failures',fabric_lifecycle):raise SystemExit('Missing fabric lifecycle success marker')
    lifecycle=run(editor+['--script','res://tools/lifecycle_checks.gd','--',f'out_dir={logs / "source-lifecycle-states"}'],logs/'source-lifecycle.log',project)
    if not re.search(r'LIFECYCLE CHECKS: \d+ checks, 0 failures',lifecycle):raise SystemExit('Missing lifecycle success marker')
    town=run(editor+['--script','res://tools/town_checks.gd','--',f'out_dir={logs / "source-town-states"}'],logs/'source-town.log',project)
    if not re.search(r'TOWN CHECKS: \d+ checks, 0 failures',town):raise SystemExit('Missing town success marker')
    render_dir=Path(tempfile.mkdtemp(prefix=f'yenikapi-{args.version}-exact-qa-'))
    defense_render=run([godot,'--path',project,'--max-fps','30','--script','res://tools/defense_preview.gd','--',f'out_dir={render_dir / "source-defense"}'],logs/'source-defense-render.log',project)
    if not re.search(r'DEFENSE RENDER: \d+ checks, 0 failures',defense_render):raise SystemExit('Source defense render failed')
    shutil.copy2(render_dir/'source-defense/report.json',logs/'source-defense-render-report.json')
    source_lifecycle_render=run([godot,'--path',project,'--max-fps','10','--script','res://tools/lifecycle_preview.gd','--',f'out_dir={render_dir / "source-lifecycle"}'],logs/'source-lifecycle-render.log',project)
    if not re.search(r'LIFECYCLE RENDER: \d+ captures; \d+ checks, 0 failures',source_lifecycle_render):raise SystemExit('Source lifecycle render gate failed')
    shutil.copy2(render_dir/'source-lifecycle/render-report.json',logs/'source-lifecycle-render-report.json')
    source_town_render=run([godot,'--path',project,'--max-fps','10','--script','res://tools/town_preview.gd','--',f'out_dir={render_dir / "source-town"}'],logs/'source-town-render.log',project)
    if not re.search(r'TOWN RENDER: \d+ captures; \d+ checks, 0 failures',source_town_render):raise SystemExit('Source town render gate failed')
    shutil.copy2(render_dir/'source-town/render-report.json',logs/'source-town-render-report.json')
    # Source performance uses the same script/cameras as the exact application.
    run([godot,'--path',project,'--script','res://tools/benchmark.gd','--',f'out_dir={render_dir / "source-benchmark"}'],logs/'source-benchmark.log',project)
    shutil.copy2(render_dir/'source-benchmark/benchmark.json',logs/'source-benchmark.json')
    run([godot,'--path',project,'--script','res://tools/benchmark.gd','--','campaign',f'out_dir={render_dir / "source-campaign-benchmark"}'],logs/'source-campaign-benchmark.log',project)
    shutil.copy2(render_dir/'source-campaign-benchmark/benchmark.json',logs/'source-campaign-benchmark.json')
    run([godot,'--path',project,'--script','res://tools/benchmark.gd','--','contacts',f'out_dir={render_dir / "source-contact-benchmark"}'],logs/'source-contact-benchmark.log',project)
    shutil.copy2(render_dir/'source-contact-benchmark/benchmark.json',logs/'source-contact-benchmark.json')
    run([godot,'--path',project,'--script','res://tools/benchmark.gd','--','households',f'out_dir={render_dir / "source-household-benchmark"}'],logs/'source-household-benchmark.log',project)
    shutil.copy2(render_dir/'source-household-benchmark/benchmark.json',logs/'source-household-benchmark.json')
    run([godot,'--path',project,'--script','res://tools/benchmark.gd','--','assets',f'out_dir={render_dir / "source-asset-benchmark"}'],logs/'source-asset-benchmark.log',project)
    shutil.copy2(render_dir/'source-asset-benchmark/benchmark.json',logs/'source-asset-benchmark.json')
    run([godot,'--path',project,'--script','res://tools/benchmark.gd','--','land',f'out_dir={render_dir / "source-land-benchmark"}'],logs/'source-land-benchmark.log',project)
    shutil.copy2(render_dir/'source-land-benchmark/benchmark.json',logs/'source-land-benchmark.json')
    run([godot,'--path',project,'--script','res://tools/profile_interactions.gd'],logs/'source-interactions.log',project)
    run([godot,'--path',project,'--script','res://tools/benchmark.gd','--','living',f'out_dir={render_dir / "source-living-benchmark"}'],logs/'source-living-benchmark.log',project)
    shutil.copy2(render_dir/'source-living-benchmark/benchmark.json',logs/'source-living-benchmark.json')
    prefix='Yenikapi-Early-Settlement'
    run([godot,'--path',project,'--script','res://tools/incident_profile.gd'],logs/'source-incident-interactions.log',project)
    run([godot,'--path',project,'--script','res://tools/visual_profile.gd'],logs/'source-visual-interactions.log',project)
    run([godot,'--path',project,'--script','res://tools/construction_profile.gd'],logs/'source-construction-interactions.log',project)
    profile([godot,'--path',project,'--script','res://tools/lifecycle_profile.gd'],logs/'source-lifecycle-interactions.log',project,'LIFECYCLE PROFILE ')
    profile([godot,'--path',project,'--script','res://tools/town_profile.gd'],logs/'source-town-interactions.log',project,'TOWN PROFILE ')
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
    packaged_defense=run([binary,'--headless','--script','res://tools/defense_checks.gd'],logs/'packaged-defense.log',out)
    if not re.search(r'VILLAGE DEFENSE: \d+ checks, 0 failures',packaged_defense):raise SystemExit('Packaged defense rule checks failed')
    packaged_defense_render=run([binary,'--max-fps','30','--script','res://tools/defense_preview.gd','--',f'out_dir={render_dir / "packaged-defense"}'],logs/'packaged-defense-render.log',out)
    if not re.search(r'DEFENSE RENDER: \d+ checks, 0 failures',packaged_defense_render):raise SystemExit('Packaged defense render failed')
    shutil.copy2(render_dir/'packaged-defense/report.json',logs/'packaged-defense-render-report.json')
    packaged=run([binary,'--headless','--script','res://tools/checks.gd'],logs/'packaged-checks.log',out)
    if not re.search(r'VILLAGE CHECKS: \d+ checks, 0 failures',packaged):raise SystemExit('Missing packaged success marker')
    if re.search(r'mesh ([a-f0-9]+)',checked).group(1)!=re.search(r'mesh ([a-f0-9]+)',packaged).group(1):raise SystemExit('Source/package geometry differs')
    packaged_governance=run([binary,'--headless','--script','res://tools/governance_checks.gd'],logs/'packaged-governance.log',out)
    if not re.search(r'GOVERNANCE CHECKS: \d+ checks, 0 failures',packaged_governance):raise SystemExit('Missing packaged governance success marker')
    packaged_neighbor=run([binary,'--headless','--script','res://tools/neighbor_checks.gd'],logs/'packaged-neighbors.log',out)
    if not re.search(r'NEIGHBOR CHECKS: \d+ checks, 0 failures',packaged_neighbor):raise SystemExit('Missing packaged contact success marker')
    packaged_household=run([binary,'--headless','--script','res://tools/household_checks.gd'],logs/'packaged-households.log',out)
    if not re.search(r'HOUSEHOLD CHECKS: \d+ checks, 0 failures',packaged_household):raise SystemExit('Missing packaged household success marker')
    packaged_assets=run([binary,'--headless','--script','res://tools/asset_checks.gd'],logs/'packaged-assets.log',out)
    if not re.search(r'ASSET CHECKS: \d+ checks, 0 failures',packaged_assets):raise SystemExit('Missing packaged asset success marker')
    packaged_land=run([binary,'--headless','--script','res://tools/land_checks.gd'],logs/'packaged-land.log',out)
    if not re.search(r'LAND CHECKS: \d+ checks, 0 failures',packaged_land):raise SystemExit('Missing packaged land success marker')
    packaged_geometry=run([binary,'--headless','--script','res://tools/land_geometry_checks.gd'],logs/'packaged-land-geometry.log',out)
    if not re.search(r'LAND GEOMETRY CHECKS: \d+ checks, 0 failures',packaged_geometry):raise SystemExit('Missing packaged land geometry success marker')
    packaged_incidents=run([binary,'--headless','--script','res://tools/incident_checks.gd'],logs/'packaged-incidents.log',out)
    if not re.search(r'INCIDENT CHECKS: \d+ checks, 0 failures',packaged_incidents):raise SystemExit('Missing packaged incident success marker')
    packaged_living=run([binary,'--headless','--script','res://tools/living_checks.gd'],logs/'packaged-living.log',out)
    if not re.search(r'LIVING CHECKS: \d+ checks, 0 failures',packaged_living):raise SystemExit('Missing packaged living success marker')
    packaged_visual=run([binary,'--headless','--script','res://tools/visual_checks.gd'],logs/'packaged-visual.log',out)
    if not re.search(r'VISUAL CHECKS: \d+ checks, 0 failures',packaged_visual):raise SystemExit('Packaged visual checks failed')
    packaged_construction=run([binary,'--headless','--script','res://tools/construction_checks.gd'],logs/'packaged-construction.log',out)
    if not re.search(r'CONSTRUCTION CHECKS: \d+ checks, 0 failures',packaged_construction):raise SystemExit('Packaged construction checks failed')
    packaged_fabric_lifecycle=run([binary,'--headless','--script','res://tools/fabric_lifecycle_checks.gd'],logs/'packaged-fabric-lifecycle.log',out)
    if not re.search(r'Fabric lifecycle checks: \d+ checks, 0 failures',packaged_fabric_lifecycle):raise SystemExit('Missing packaged fabric lifecycle success marker')
    packaged_lifecycle=run([binary,'--headless','--script','res://tools/lifecycle_checks.gd','--',f'out_dir={logs / "packaged-lifecycle-states"}'],logs/'packaged-lifecycle.log',out)
    if not re.search(r'LIFECYCLE CHECKS: \d+ checks, 0 failures',packaged_lifecycle):raise SystemExit('Missing packaged lifecycle success marker')
    for name in ['compact-recipe.json','outward-recipe.json','strategies.json']:
        if (logs/'source-lifecycle-states'/name).read_bytes()!=(logs/'packaged-lifecycle-states'/name).read_bytes():raise SystemExit('Source/package lifecycle replay differs: '+name)
    packaged_town=run([binary,'--headless','--script','res://tools/town_checks.gd','--',f'out_dir={logs / "packaged-town-states"}'],logs/'packaged-town.log',out)
    if not re.search(r'TOWN CHECKS: \d+ checks, 0 failures',packaged_town):raise SystemExit('Missing packaged town success marker')
    for path in (logs/'source-town-states').glob('*.json'):
        if path.read_bytes()!=(logs/'packaged-town-states'/path.name).read_bytes():raise SystemExit('Source/package town state or recipe differs: '+path.name)
    rendered=run([binary,'--max-fps','10','--script','res://tools/preview.gd','--',f'out_dir={render_dir}'],logs/'packaged-render.log',out)
    if 'VILLAGE RENDER PASS: 14 captures' not in rendered:raise SystemExit('Incomplete rendered gate')
    shutil.copy2(render_dir/'render-report.json',logs/'render-report.json')
    run([binary,'--script','res://tools/benchmark.gd','--',f'out_dir={render_dir / "benchmark"}'],logs/'packaged-benchmark.log',out)
    shutil.copy2(render_dir/'benchmark/benchmark.json',logs/'packaged-benchmark.json')
    tutorial_render=run([binary,'--max-fps','10','--script','res://tools/governance_preview.gd','--',f'out_dir={render_dir / "tutorial"}'],logs/'packaged-tutorial-render.log',out)
    if not re.search(r'GOVERNANCE RENDER: 12 captures; \d+ checks, 0 failures',tutorial_render):raise SystemExit('Tutorial render gate failed')
    shutil.copy2(render_dir/'tutorial/render-report.json',logs/'tutorial-render-report.json')
    run([binary,'--script','res://tools/benchmark.gd','--','campaign',f'out_dir={render_dir / "campaign-benchmark"}'],logs/'packaged-campaign-benchmark.log',out)
    shutil.copy2(render_dir/'campaign-benchmark/benchmark.json',logs/'packaged-campaign-benchmark.json')
    neighbor_render=run([binary,'--max-fps','10','--script','res://tools/neighbor_preview.gd','--',f'out_dir={render_dir / "neighbors"}'],logs/'packaged-neighbor-render.log',out)
    if not re.search(r'NEIGHBOR RENDER: 10 captures; \d+ checks, 0 failures',neighbor_render):raise SystemExit('Contact render gate failed')
    shutil.copy2(render_dir/'neighbors/render-report.json',logs/'neighbor-render-report.json')
    run([binary,'--script','res://tools/benchmark.gd','--','contacts',f'out_dir={render_dir / "contact-benchmark"}'],logs/'packaged-contact-benchmark.log',out)
    shutil.copy2(render_dir/'contact-benchmark/benchmark.json',logs/'packaged-contact-benchmark.json')
    household_render=run([binary,'--max-fps','10','--script','res://tools/household_preview.gd','--',f'out_dir={render_dir / "households"}'],logs/'packaged-household-render.log',out)
    if not re.search(r'HOUSEHOLD RENDER: 12 captures; \d+ checks, 0 failures',household_render):raise SystemExit('Household render gate failed')
    shutil.copy2(render_dir/'households/render-report.json',logs/'household-render-report.json')
    run([binary,'--script','res://tools/benchmark.gd','--','households',f'out_dir={render_dir / "household-benchmark"}'],logs/'packaged-household-benchmark.log',out)
    shutil.copy2(render_dir/'household-benchmark/benchmark.json',logs/'packaged-household-benchmark.json')
    asset_render=run([binary,'--max-fps','10','--script','res://tools/asset_preview.gd','--',f'out_dir={render_dir / "assets"}'],logs/'packaged-asset-render.log',out)
    if not re.search(r'ASSET RENDER: 12 captures; \d+ checks, 0 failures',asset_render):raise SystemExit('Asset render gate failed')
    shutil.copy2(render_dir/'assets/render-report.json',logs/'asset-render-report.json')
    run([binary,'--script','res://tools/benchmark.gd','--','assets',f'out_dir={render_dir / "asset-benchmark"}'],logs/'packaged-asset-benchmark.log',out)
    shutil.copy2(render_dir/'asset-benchmark/benchmark.json',logs/'packaged-asset-benchmark.json')
    land_render=run([binary,'--max-fps','10','--script','res://tools/land_preview.gd','--',f'out_dir={render_dir / "land"}'],logs/'packaged-land-render.log',out)
    if not re.search(r'LAND RENDER: 19 captures; \d+ checks, 0 failures',land_render):raise SystemExit('Land render gate failed')
    shutil.copy2(render_dir/'land/render-report.json',logs/'land-render-report.json')
    run([binary,'--script','res://tools/benchmark.gd','--','land',f'out_dir={render_dir / "land-benchmark"}'],logs/'packaged-land-benchmark.log',out)
    shutil.copy2(render_dir/'land-benchmark/benchmark.json',logs/'packaged-land-benchmark.json')
    run([binary,'--script','res://tools/profile_interactions.gd'],logs/'packaged-interactions.log',out)
    living_render=run([binary,'--max-fps','10','--script','res://tools/living_preview.gd','--',f'out_dir={render_dir / "living"}'],logs/'packaged-living-render.log',out)
    if not re.search(r'LIVING RENDER: \d+ captures; \d+ checks, 0 failures',living_render):raise SystemExit('Living render gate failed')
    shutil.copy2(render_dir/'living/render-report.json',logs/'living-render-report.json')
    run([binary,'--script','res://tools/benchmark.gd','--','living',f'out_dir={render_dir / "living-benchmark"}'],logs/'packaged-living-benchmark.log',out)
    shutil.copy2(render_dir/'living-benchmark/benchmark.json',logs/'packaged-living-benchmark.json')
    incident_render=run([binary,'--max-fps','10','--script','res://tools/incident_preview.gd','--',f'out_dir={render_dir / "incidents"}'],logs/'packaged-incident-render.log',out)
    if not re.search(r'INCIDENT RENDER: \d+ captures; \d+ checks, 0 failures',incident_render):raise SystemExit('Incident render gate failed')
    shutil.copy2(render_dir/'incidents/render-report.json',logs/'incident-render-report.json')
    run([binary,'--script','res://tools/incident_profile.gd'],logs/'packaged-incident-interactions.log',out)
    visual_render=run([binary,'--max-fps','10','--script','res://tools/visual_preview.gd','--',f'out_dir={render_dir / "visual"}'],logs/'packaged-visual-render.log',out)
    if not re.search(r'VISUAL RENDER: \d+ captures; \d+ checks, 0 failures',visual_render):raise SystemExit('Visual command render gate failed')
    shutil.copy2(render_dir/'visual/render-report.json',logs/'visual-render-report.json')
    run([binary,'--script','res://tools/visual_profile.gd'],logs/'packaged-visual-interactions.log',out)
    construction_render=run([binary,'--max-fps','10','--script','res://tools/construction_preview.gd','--',f'out_dir={render_dir / "construction"}'],logs/'packaged-construction-render.log',out)
    if not re.search(r'CONSTRUCTION RENDER: \d+ captures; \d+ checks, 0 failures',construction_render):raise SystemExit('Construction rendered gate failed')
    shutil.copy2(render_dir/'construction/render-report.json',logs/'construction-render-report.json')
    run([binary,'--script','res://tools/construction_profile.gd'],logs/'packaged-construction-interactions.log',out)
    lifecycle_render=run([binary,'--max-fps','10','--script','res://tools/lifecycle_preview.gd','--',f'out_dir={render_dir / "lifecycle"}'],logs/'packaged-lifecycle-render.log',out)
    if not re.search(r'LIFECYCLE RENDER: \d+ captures; \d+ checks, 0 failures',lifecycle_render):raise SystemExit('Lifecycle rendered gate failed')
    shutil.copy2(render_dir/'lifecycle/render-report.json',logs/'lifecycle-render-report.json')
    town_render=run([binary,'--max-fps','10','--script','res://tools/town_preview.gd','--',f'out_dir={render_dir / "town"}'],logs/'packaged-town-render.log',out)
    if not re.search(r'TOWN RENDER: \d+ captures; \d+ checks, 0 failures',town_render):raise SystemExit('Town rendered gate failed')
    shutil.copy2(render_dir/'town/render-report.json',logs/'town-render-report.json')
    source_report=json.loads((logs/'source-town-render-report.json').read_text())
    app_report=json.loads((logs/'town-render-report.json').read_text())
    if source_report['commands']!=app_report['commands'] or source_report['sha256']!=app_report['sha256']:raise SystemExit('Actual UI source/package town recipes differ')
    profile([binary,'--script','res://tools/lifecycle_profile.gd'],logs/'packaged-lifecycle-interactions.log',out,'LIFECYCLE PROFILE ')
    profile([binary,'--script','res://tools/town_profile.gd'],logs/'packaged-town-interactions.log',out,'TOWN PROFILE ')
    provenance['town']={'profile':'town_responsibilities_v1','wrapper':8,'adoption':'explicit extension; published village_lifecycle_v1 remains pinned','source_fixtures':'verification/source-town-states','exact_app_fixtures':'verification/packaged-town-states','source_render_report':'verification/source-town-render-report.json','exact_app_render_report':'verification/town-render-report.json','replay':'all fixture bytes and real-UI command recipes/digests match source and exact app'}
    provenance['lifecycle']={'profile':'village_lifecycle_v1','wrapper':8,'scope':'small village to large village; explicitly adopted town extension; later stages planned','source_render_report':'verification/source-lifecycle-render-report.json','exact_app_render_report':'verification/lifecycle-render-report.json','source_fixtures':'verification/source-lifecycle-states','exact_app_fixtures':'verification/packaged-lifecycle-states','replay':'source and exact-app command recipes, state digests and strategy summaries match'}
    provenance['living_performance']={'source':json.loads((logs/'source-living-benchmark.json').read_text()),'exact_app':json.loads((logs/'packaged-living-benchmark.json').read_text())}
    provenance['land_performance']={'source':json.loads((logs/'source-land-benchmark.json').read_text()),'exact_app':json.loads((logs/'packaged-land-benchmark.json').read_text())}
    provenance['asset_performance']={'source':json.loads((logs/'source-asset-benchmark.json').read_text()),'exact_app':json.loads((logs/'packaged-asset-benchmark.json').read_text())}
    provenance['household_performance']={'source':json.loads((logs/'source-household-benchmark.json').read_text()),'exact_app':json.loads((logs/'packaged-household-benchmark.json').read_text())}
    provenance['contact_performance']={'source':json.loads((logs/'source-contact-benchmark.json').read_text()),'exact_app':json.loads((logs/'packaged-contact-benchmark.json').read_text())}
    provenance['render_capture_directory']=str(render_dir)
    provenance['performance']={'source':json.loads((logs/'source-benchmark.json').read_text()),'exact_app':json.loads((logs/'packaged-benchmark.json').read_text())}
    provenance['campaign_performance']={'source':json.loads((logs/'source-campaign-benchmark.json').read_text()),'exact_app':json.loads((logs/'packaged-campaign-benchmark.json').read_text())}
    provenance['campaign_scenario']='yenikapi_seasons_tutorial; hypothetical; base rules 1, optional contacts 1, households 1, assets 1, land 1, living 1, incidents 1, lifecycle 1; wrappers 1 (inactive) / 2 (contacts) / 3 (households) / 4 (assets) / 5 (land) / 6 (living) / 7 (incidents) / 8 (lifecycle); separate campaign slot'
    models=out/f'{prefix}-Models'
    run(editor+['--script','res://tools/export_models.gd','--',f'out_dir={models}'],logs/'models.log',project)
    glbs=sorted(models.glob('*.glb'))
    if len(glbs)!=44:raise SystemExit('Expected reference, hypothetical town and individual models')
    provenance['models']={p.name:{**check_glb(p),'sha256':digest(p)} for p in glbs}
    if args.retained_build:
        previous=args.retained_build.resolve()
        old_manifest=json.loads((previous/'provenance.json').read_text())
        old_models=previous/f'{prefix}-Models'
        expected_retained={p.name for p in glbs if not p.name.startswith('town-')}
        if len(old_manifest['models'])!=41 or set(old_manifest['models'])!=expected_retained:raise SystemExit('Expected all 41 original model names in retained build')
        for name in old_manifest['models']:
            if digest(old_models/name)!=digest(models/name):raise SystemExit('Retained model bytes changed: '+name)
        provenance['retained_models']={'build':str(previous),'count':len(old_manifest['models']),'result':'byte-identical'}
    for name,sha in frozen.items():
        if digest(snapshot/name)!=sha:raise SystemExit(f'Frozen source changed: {name}')
    source_zip=out/f'{prefix}-Source-{args.version}.zip'
    archive_tree(snapshot,source_zip)
    # Small independent archives preserve existing GLBs and avoid oversized uploads.
    contact={'growth_exchange_house.glb','Yenikapi-Hypothetical-Contact-Settlement.glb','hypothetical-contact-provenance.json'}
    artifacts=[app_zip,source_zip]
    for group,count in [('Foundation',16),('Contact',2),('Household',6),('Asset',3),('Land',3),('Living',3),('Incident',3),('Construction',5),('Town',3)]:
        members=[]
        for path in models.iterdir():
            category='Town' if path.name.startswith('town-') else 'Construction' if path.name.startswith('construction-') else 'Incident' if path.name.startswith('incident-') else 'Living' if path.name.startswith('living-') else 'Land' if path.name.startswith('land-') else 'Asset' if path.name.startswith('asset-') else 'Household' if path.name.startswith('household-') else ('Contact' if path.name in contact else 'Foundation')
            if path.is_file() and category==group:members.append(path)
        if len([p for p in members if p.suffix=='.glb'])!=count:raise SystemExit('Wrong model partition '+group)
        target=out/f'{prefix}-{group}-Models-{args.version}.zip'
        with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
            for path in sorted(members):archive.write(path,f'Yenikapi-{group}-Models/{path.name}')
        with zipfile.ZipFile(target) as archive:
            for path in members:
                if archive.read(f'Yenikapi-{group}-Models/{path.name}')!=path.read_bytes():raise SystemExit('Model partition changed bytes')
        artifacts.append(target)
    for path in artifacts:
        with zipfile.ZipFile(path) as archive:
            if archive.testzip():raise SystemExit(f'Corrupt ZIP {path}')
    provenance['checks']={'parent_campaign':'passed; logs copied','schema_and_negative_cases':'passed','source_and_exact_app':'All reference/governance/contact/household/asset/land/living/incident/visual/construction/fabric-lifecycle/lifecycle/town/defense checks passed on source and exact app; counts in verification logs; identical reference mesh hash','render_captures':str(125+len(json.loads((logs/'visual-render-report.json').read_text())['captures'])+len(json.loads((logs/'construction-render-report.json').read_text())['captures'])+len(json.loads((logs/'lifecycle-render-report.json').read_text())['captures']))+' exact-app captures plus '+str(len(json.loads((logs/'source-lifecycle-render-report.json').read_text())['captures']))+' source lifecycle captures plus '+str(len(source_report['captures']))+' source town and '+str(len(app_report['captures']))+' exact-app town captures written; manual visual review required before publication','glb_structure':'44 passed','zip_integrity':'11 passed; model partitions match exported bytes'}
    provenance['artifacts']={p.name:{'bytes':p.stat().st_size,'sha256':digest(p)} for p in artifacts}
    manifest=out/'provenance.json';manifest.write_text(json.dumps(provenance,indent=2)+'\n')
    (out/'SHA256SUMS.txt').write_text(''.join(f'{digest(p)}  {p.name}\n' for p in [*artifacts,manifest]))
    print(f'EARLY SETTLEMENT BUILD PASS: {app_zip}',flush=True)
if __name__=='__main__':main()
