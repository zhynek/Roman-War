#!/usr/bin/env python3
"""Validate bounded land, relationships, effects and the existing fabric vocabulary."""
import copy
import json
from pathlib import Path
import jsonschema
from validate_settlement import validate as validate_snapshot
ROOT=Path(__file__).resolve().parents[1]
def load(name):return json.loads((ROOT/'data'/f'{name}.json').read_text())
def validate(config,balance,governance,settlement):
    errors=[]
    for name,value in [('land',config),('balance',balance)]:
        errors.extend(f'{name} {e.json_path}: {e.message}' for e in jsonschema.Draft202012Validator(json.loads((ROOT/'schemas'/f'{name}.schema.json').read_text())).iter_errors(value))
    if errors:return errors
    sites={x['id']:x for x in config['sites']};proposals={x['id']:x for x in config['proposals']};projects={x['id']:x for x in config['projects']}
    old={x['id']:x for x in governance['projects']};records={x['id']:x for x in settlement['objects']}
    if len(sites)!=len(config['sites']) or len(proposals)!=len(config['proposals']) or len(projects)!=len(config['projects']):errors.append('duplicate spatial id')
    if projects.keys()!=proposals.keys() or projects.keys() & old.keys():errors.append('proposal/project identity mismatch')
    if not set(config['legacy_projects'])<=old.keys():errors.append('unknown legacy project')
    created=set(records)
    for project in config['projects']:
        if project['wood']<=0 or project['work']<=0 or project['role']!='steward':errors.append('invalid spatial commission')
        if not set(project['requires'])<=(projects.keys()|old.keys()):errors.append('unknown prerequisite')
        for change in project['changes']:
            if not set(change['before'])<=records.keys():errors.append('unknown predecessor')
            if change['kind']=='altered' and (len(change['after'])!=1 or change['before']!=[change['after'][0]['id']]):errors.append('adaptation lost identity')
            if change['kind'] not in ['added','altered','removed']:errors.append('unsupported land relationship')
            if change['kind']=='removed' and change['after']:errors.append('removal has successor')
            for record in change['after']:
                if change['kind']=='added' and record['id'] in created:errors.append('reused new object id')
                created.add(record['id'])
                sample=copy.deepcopy(settlement)
                sample['objects']=[x for x in sample['objects'] if x['id']!=record['id']]+[record]
                errors.extend(validate_snapshot(sample))
    for site in config['sites']:
        if not set(site['objects'])<=records.keys():errors.append('unknown existing use')
        if site['connection'] not in records and site['connection'] not in projects:errors.append('unknown connection')
        if any(v<=0 for v in site['size']) or any(abs(v)>150 for v in site['at']):errors.append('invalid footprint')
        if any(site[k]<0 for k in ['food','work','cooperation']):errors.append('negative initial use')
    for proposal in config['proposals']:
        if proposal['site'] not in sites:errors.append('unknown site');continue
        if proposal['asset'] not in ['homes','fields','yard','workroom']:errors.append('unknown responsible asset')
        if proposal['requires_access'] and 'land_outer_access' not in projects[proposal['id']]['requires']:errors.append('missing access dependency')
        if any(proposal[k]<0 for k in ['food','work','cooperation']):errors.append('negative full use')
        for change in projects[proposal['id']]['changes']:
            if not set(change['before'])<=set(sites[proposal['site']]['objects']):errors.append('change escapes claimed site')
    for home in config['households']:
        if home['requires'] not in projects or home['building_id'] not in created:errors.append('unknown accommodation')
        elif projects[home['requires']]['effects'].get('housing')!=balance['people_per_dwelling']:errors.append('housing effect differs from household places')
    for id,alternatives in config['alternatives'].items():
        if id not in old or not set(alternatives)<=projects.keys():errors.append('unknown milestone substitute')
    for key in ['access_workers','access_wood','minimum_reserve']:
        if balance['land'][key]<1:errors.append('unfunded access or provisions')
    if not 1<=balance['land']['access_priority']<=3:errors.append('access must precede dependent crews')
    visiting=set();done=set()
    def visit(id):
        if id in visiting:errors.append('dependency cycle');return
        if id in done:return
        visiting.add(id)
        for dep in projects.get(id,{}).get('requires',[]):visit(dep)
        visiting.remove(id);done.add(id)
    for id in projects:visit(id)
    return errors
if __name__=='__main__':
    errors=validate(*(load(n) for n in ['land','balance','governance','settlement']))
    for error in errors:print(error)
    print(f'LAND DATA: {len(errors)} errors')
    raise SystemExit(bool(errors))
