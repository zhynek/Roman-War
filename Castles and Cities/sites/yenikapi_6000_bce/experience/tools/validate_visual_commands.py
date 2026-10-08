#!/usr/bin/env python3
"""Validate presentation-only place cards against existing authoritative content."""
import json,copy
from pathlib import Path
import jsonschema
ROOT=Path(__file__).resolve().parents[1]
def load(n):return json.loads((ROOT/'data'/f'{n}.json').read_text())
def validate(d):
    errors=[e.message for e in jsonschema.Draft202012Validator(json.loads((ROOT/'schemas/visual_commands.schema.json').read_text())).iter_errors(d)]
    if errors:return errors
    assets={a['id'] for a in load('assets')['assets']}
    projects={a['id']:a for name in ['governance','land','living','incidents'] for a in load(name)['projects']}
    if len(d['assets'])!=len(assets) or {a['id'] for a in d['assets']}!=assets:errors.append('place identity mismatch')
    icons={'stores','homes','fields','landing','workroom','yard','watch','path','wood','blanks','people','kits','food','guide','growth','warning'}
    if any(a['icon'] not in icons for a in d['assets']+d['living_orders']):errors.append('unknown procedural icon')
    if not set(d['project_labels'])<=projects.keys():errors.append('unknown project label')
    for chain in d['chains']:
        if not set(chain['projects'])<=projects.keys():errors.append('unknown growth project');continue
        if len(chain['links'])!=len(chain['projects'])-1:errors.append('growth link count')
        for i,link in enumerate(chain['links']):
            if link=='arrow' and chain['projects'][i] not in projects[chain['projects'][i+1]]['requires']:errors.append('false prerequisite arrow')
    orders={'area':['west_wood','north_wood'],'prepare':[0,1,2],'cooperate':[False,True],'training':[False,True],'repair':[False,True],'patrol':['landing_post','north_post']}
    if {a['id'] for a in d['living_orders']}!=orders.keys():errors.append('missing living order')
    for a in d['living_orders']:
        if a['asset'] not in assets or a['values']!=orders.get(a['id']) or len(a['values'])!=len(a['labels']):errors.append('invalid standing choices')
    if any(a['asset'] not in assets for a in d['lessons']):errors.append('lesson place missing')
    destinations={'asset','lifecycle','defense','aftermath'}
    if any(a.get('destination','asset') not in destinations for a in d['lessons']):errors.append('unknown lesson destination')
    return errors
if __name__=='__main__':
    data=load('visual_commands');errors=validate(data)
    from validate_marcus import validate as validate_advisor
    errors.extend(validate_advisor(load('marcus')))
    for error in errors:print(error)
    negative=[]
    for mutate in [lambda d:d['assets'][0].update(id='missing'),lambda d:d['living_orders'][0].update(values=['free']),lambda d:d['chains'][0]['projects'].append('missing'),lambda d:d['assets'][0].update(icon='missing'),lambda d:d['chains'][2]['links'].__setitem__(0,'arrow'),lambda d:d.update(unexpected=True),lambda d:d['lessons'][0].update(destination='advance'),lambda d:d['lessons'][0].update(asset='missing')]:
        broken=copy.deepcopy(data);mutate(broken);negative.append(bool(validate(broken)))
    if not all(negative):errors.append('negative validation failed')
    print(f'VISUAL DATA: {len(errors)} errors; {sum(negative)}/{len(negative)} negative cases rejected');raise SystemExit(bool(errors))
