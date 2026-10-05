#!/usr/bin/env python3
"""Closed schema and authoritative cross-links for the optional asset mode."""
import json
from pathlib import Path
import jsonschema
ROOT=Path(__file__).resolve().parents[1]
def load(name):return json.loads((ROOT/'data'/f'{name}.json').read_text())
def validate(config,balance,governance,settlement,households):
    errors=[]
    for name,value in [('assets',config),('balance',balance)]:
        schema=json.loads((ROOT/'schemas'/f'{name}.schema.json').read_text())
        errors += [f'{name} {e.json_path}: {e.message}' for e in jsonschema.Draft202012Validator(schema).iter_errors(value)]
    if errors:return errors
    assets={a['id']:a for a in config['assets']}
    if len(assets)!=len(config['assets']):errors.append('duplicate asset')
    if set(assets)!={'stores','homes','fields','landing','workroom','yard','watch'}:errors.append('published asset identities required')
    objects={o['id'] for o in settlement['objects']}
    for project in governance['projects']:
        for change in project['changes']:
            objects.update(o['id'] for o in change.get('after',[]))
    projects={p['id']:p for p in governance['projects']}
    orders={o['id']:o for o in households['orders']}
    seen_objects=set();seen_projects=set();seen_orders=set()
    for asset in config['assets']:
        if asset['role'] not in ['steward','watch']:errors.append('invalid office')
        for key,valid,seen in [('objects',objects,seen_objects),('projects',projects,seen_projects),('orders',orders,seen_orders)]:
            for id in asset[key]:
                if id not in valid:errors.append(f'unknown {key}: {id}')
                if id in seen:errors.append(f'ambiguous {key}: {id}')
                seen.add(id)
                if key in ['projects','orders'] and id in valid and valid[id]['role']!=asset['role']:errors.append('office mismatch')
    if seen_projects!=set(projects):errors.append('each existing project must have exactly one target asset')
    if seen_orders!=set(orders):errors.append('each existing order must have exactly one target asset')
    if [p['id'] for p in config['principles']]!=['reserve','upkeep','care','watch','welcome','learning']:errors.append('six stable principles required')
    for principle in config['principles']:
        if principle['asset'] not in assets:errors.append('unknown principle asset')
        elif principle['role']!=assets[principle['asset']]['role']:errors.append('principle authority mismatch')
    for step in config['tutorial']:
        if step['asset'] not in assets:errors.append('unknown tutorial asset')
        if step['condition'] not in ['inspect','principle','commission','season','pressure','learning','growth']:errors.append('unknown tutorial gate')
    for id in config['housing_steps']:
        if id not in projects:errors.append('unknown coordinated project')
    if config['housing_steps']!=['field_extension','north_lane','north_home','east_home']:errors.append('preserve housing dependencies')
    tuning=balance['assets']
    for key in ['repair_workers','repair_gain','repair_wood','reserve_recovery_seasons','max_crew','condition_max']:
        if tuning[key]<1:errors.append('positive allocation tuning required: '+key)
    if not 0<tuning['condition_threshold']<tuning['repair_threshold']<=tuning['condition_max']:errors.append('condition thresholds unordered')
    if not 1<=tuning['initial_reserve']<=3 or not 1<=tuning['initial_watch']<=2:errors.append('invalid default principle')
    if tuning['work_yield_loss']>=balance['work_yield']:errors.append('repairable workroom must allow useful work')
    if tuning['storage_loss_percent']>=100:errors.append('neglect must leave usable storage')
    return errors
if __name__=='__main__':
    errors=validate(*(load(n) for n in ['assets','balance','governance','settlement','households']))
    for error in errors:print(error)
    print(f'ASSET DATA: {len(errors)} errors')
    raise SystemExit(bool(errors))
