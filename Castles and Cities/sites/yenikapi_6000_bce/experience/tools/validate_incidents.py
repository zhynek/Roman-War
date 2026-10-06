#!/usr/bin/env python3
"""Closed incident content and live references; no free-form event catalogue."""
import json,re
from pathlib import Path
import jsonschema
ROOT=Path(__file__).resolve().parents[1]
def load(name):return json.loads((ROOT/'data'/f'{name}.json').read_text())
def validate(d,b):
    errors=[]
    for name,value in [('incidents',d),('balance',b)]:
        errors += [f'{name} {e.json_path}: {e.message}' for e in jsonschema.Draft202012Validator(json.loads((ROOT/'schemas'/f'{name}.schema.json').read_text())).iter_errors(value)]
    if errors:return errors
    living=load('living');governance=load('governance');land=load('land');assets=load('assets')
    subjects={x['id'] for x in living['areas']+living['posts']+living['households']}|{'store','workroom'}
    homes={x['id'] for x in governance['households']+land['households']}
    # All authored households can be inspected through the incident overview.
    subjects|=homes|{x["id"] for x in assets["assets"]}
    projects={x['id']:x for x in d['projects']}
    if len(projects)!=len(d['projects']):errors.append('duplicate project')
    if len({x['id'] for x in d['incidents']})!=len(d['incidents']):errors.append('duplicate incident')
    if len(d['incidents'])!=2 or {x['kind'] for x in d['incidents']}!={'approach','stores'}:errors.append('two scoped kinds required')
    referenced=[]
    for e in d['incidents']:
        if e['place'] not in subjects or e['post'] not in {x['id'] for x in living['posts']} or e['asset'] not in {x['id'] for x in assets['assets']}:errors.append('invalid place/post/asset')
        if not set(e['households'])<=homes or not set(e['subjects'])<=subjects:errors.append('invalid household/subject')
        locations={x['id']:x['at'] for x in living['areas']+living['posts']+assets['assets']}
        if e['at']!=locations.get(e['place']):errors.append('place coordinates disagree with authored subject')
        if e['place'] not in e['subjects'] or e['strength']>b['incidents']['maximum_severity']:errors.append('invalid exposure')
        for mode in ['prepare','repair']:
            referenced.append(e[mode])
            if e[mode] not in projects:errors.append('missing project')
            elif projects[e[mode]]['at']!=e['at']:errors.append('project/place mismatch')
    if set(referenced)!=set(projects) or len(referenced)!=len(set(referenced)):errors.append('nonunique initiative relationship')
    old={x['id'] for x in governance['projects']+land['projects']+living['projects']}
    for q in d['projects']:
        if q['id'] in old or not q['id'].startswith('incident_') or min(q['wood'],q['work'],q['blanks'])<=0 or q['blanks']>b['living']['blank_capacity']:errors.append('invalid project/inputs')
    source=(ROOT/'src/core/incident_rules.gd').read_text()
    for k in b['incidents']:
        if not re.search(r'\b'+k+r'\b',source):errors.append('unused tuning '+k)
    if b['incidents']['warning_seasons']<2 or b['incidents']['quiet_seasons']<b['incidents']['warning_seasons']:errors.append('unfair timing')
    return errors
if __name__=='__main__':
    errors=validate(load('incidents'),load('balance'))
    for e in errors:print(e)
    print(f'INCIDENT DATA: {len(errors)} errors');raise SystemExit(bool(errors))
