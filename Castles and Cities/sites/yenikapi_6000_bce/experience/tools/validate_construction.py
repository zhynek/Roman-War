#!/usr/bin/env python3
"""Validate read-only construction presentation and physical planning furniture."""
import copy,json
from pathlib import Path
import jsonschema
ROOT=Path(__file__).resolve().parents[1]
def load(n):return json.loads((ROOT/'data'/f'{n}.json').read_text())
def validate(d):
    schema=json.loads((ROOT/'schemas/construction.schema.json').read_text())
    errors=[e.message for e in jsonschema.Draft202012Validator(schema).iter_errors(d)]
    if errors:return errors
    projects={x['id']:x for n in ['governance','land','living','incidents'] for x in load(n)['projects']}
    if set(d['projects'])!=set(projects):errors.append('every project needs exactly one treatment and benefit')
    buildings={x['id']:x for x in load('settlement')['objects'] if x['kind']=='building'}
    room=buildings.get(d['room']['building'])
    if not room or room['use']!='work':errors.append('planning room must reuse an existing working room')
    else:
        for k in ['board_at','easel_at']:
            x,y,z=d['room'][k]
            if abs(x)>=room['size'][0]/2 or abs(z)>=room['size'][1]/2 or not 0<y<room['wall_height']:errors.append('plan furniture outside room')
    for id,entry in d['projects'].items():
        if id not in projects:continue
        changes=projects[id]['changes']
        if entry['treatment']=='building' and not any(c['kind']=='added' and any(a['kind']=='building' for a in c['after']) for c in changes):errors.append('new structure treatment requires a new building')
        if any(c['kind']=='altered' and any(a['kind']=='building' for a in c['after']) for c in changes) and entry['treatment']!='adapt':errors.append('retained building must use adaptation treatment')
    return errors
if __name__=='__main__':
    d=load('construction');errors=validate(d);rejected=0
    mutations=[lambda x:x['projects'].pop('shared_store'),lambda x:x['projects'].update(fake={'treatment':'building','benefit':'bad'}),lambda x:x['projects']['shared_store'].update(treatment='building'),lambda x:x['projects']['incident_stores_repair'].update(treatment='building'),lambda x:x['room'].update(building='yk_house_01'),lambda x:x['room'].update(easel_at=[0,1,99]),lambda x:x.update(economy={}),lambda x:x['stages']['building'].pop()]
    for mutate in mutations:
        bad=copy.deepcopy(d);mutate(bad);rejected+=bool(validate(bad))
    if rejected!=len(mutations):errors.append('negative cases not rejected')
    for error in errors:print(error)
    print(f'CONSTRUCTION DATA: {len(errors)} errors; {rejected}/{len(mutations)} negative cases rejected')
    raise SystemExit(bool(errors))
