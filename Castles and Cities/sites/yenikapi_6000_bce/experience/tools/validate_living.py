#!/usr/bin/env python3
"""Closed content, real site/household/project relationships and consumed tuning."""
import json,re,copy
from pathlib import Path
import jsonschema
from validate_settlement import validate as validate_snapshot
ROOT=Path(__file__).resolve().parents[1]
def load(n):return json.loads((ROOT/'data'/f'{n}.json').read_text())
def validate(d,b,g,land):
    errors=[]
    for name,value in [('living',d),('balance',b)]:
        errors += [f'{name} {e.json_path}: {e.message}' for e in jsonschema.Draft202012Validator(json.loads((ROOT/'schemas'/f'{name}.schema.json').read_text())).iter_errors(value)]
    if errors:return errors
    ids=[x['id'] for x in d['areas']+d['posts']+d['households']]+['workroom','store']
    if len(ids)!=len(set(ids)):errors.append('duplicate subject')
    projects={x['id']:x for x in g['projects']+land['projects']+d['projects']}
    if len(projects)!=len(g['projects']+land['projects']+d['projects']):errors.append('duplicate project')
    homes={x['id'] for x in g['households']+land['households']}
    for h in d['households']:
        if h['id'] not in homes:errors.append('unknown household')
        if any(not 0<=h[k]<=b['living']['experience_max'] for k in ['woodland','shaping']):errors.append('invalid experience')
    for a in d['areas']:
        if len(a['at'])!=2 or any(abs(x)>150 for x in a['at']):errors.append('invalid woodland position')
        if a['capacity']<=0 or not 0<a['recovery']<=a['capacity'] or not 0<=a['distance_cost']<a['yield']:errors.append('invalid woodland limits')
    for a in d['posts']:
        if a['project'] not in projects or projects[a['project']]['role']!='watch':errors.append('unknown watch initiative')
    for a in d['projects']:
        if a['wood']<=0 or a['work']<=0 or not set(a['requires'])<=projects.keys():errors.append('invalid project cost or prerequisite')
        for change in a['changes']:
            sample=load('settlement');sample['objects']+=copy.deepcopy(change['after']);errors.extend(validate_snapshot(sample))
    for a in d['discoveries']:
        if not a['subjects'] or not set(a['subjects'])<=set(ids):errors.append('unknown discovery subject')
        if a['condition'] not in ['always','woodland','shaping','meeting','wear']:errors.append('unknown discovery prerequisite')
    if len({x['id'] for x in d['discoveries']})!=len(d['discoveries']):errors.append('duplicate discovery')
    if len(d['households'])!=b['living']['shared_workers']:errors.append('shared capacity must fit partners')
    if b['living']['kit_inputs']>b['living']['blank_capacity']:errors.append('unreachable equipment inputs')
    for k,v in b['living'].items():
        if v<0 or (k!='initial_blanks' and v==0):errors.append('invalid tuning '+k)
        if not re.search(r'\b'+k+r'\b',(ROOT/'src/core/living_rules.gd').read_text()):errors.append('unused tuning '+k)
    return errors
if __name__=='__main__':
    errors=validate(*(load(n) for n in ['living','balance','governance','land']))
    for e in errors:print(e)
    print(f'LIVING DATA: {len(errors)} errors');raise SystemExit(bool(errors))
