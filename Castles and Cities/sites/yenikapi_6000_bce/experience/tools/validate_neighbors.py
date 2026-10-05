#!/usr/bin/env python3
"""Closed schemas and semantic links for the optional fictional contact chapter."""
import json
import re
from pathlib import Path
import jsonschema
ROOT=Path(__file__).resolve().parents[1]
def load(name):return json.loads((ROOT/'data'/f'{name}.json').read_text())
def validate(config,ui,balance,governance):
    errors=[]
    for name,data in [('neighbors',config),('neighbors_ui',ui)]:
        schema=json.loads((ROOT/'schemas'/f'{name}.schema.json').read_text())
        errors.extend(f'{name} {e.json_path}: {e.message}' for e in jsonschema.Draft202012Validator(schema).iter_errors(data))
    if errors:return errors
    tuning=balance['neighbors']
    ids=[n['id'] for n in config['neighbors']]
    if len(ids)!=len(set(ids)) or any(not re.fullmatch('[a-z][a-z0-9_]*',i) for i in ids):errors.append('unique stable community IDs required')
    projects={p['id']:p for p in governance['projects']}
    if config['project_id'] not in projects:errors.append('unknown contact project')
    else:
        project=projects[config['project_id']]
        if project['at']!=config['meeting_at']:errors.append('meeting point must match commissioned place')
        if config['project_id'] in governance['tutorial_projects']:errors.append('contact chapter must remain optional')
    for n in config['neighbors']:
        for resource in ['food','wood']:
            if not 0<=n[resource]<=n[resource+'_capacity'] or not 0<=n[resource+'_reserve']<=n[resource+'_capacity']:errors.append('invalid initial stocks or reserves')
        if not 1<=n['duration']<=8:errors.append('invalid seasonal journey')
        if not 0<=n['term_offset']<tuning['leader_term']:errors.append('invalid speaker offset')
        if n['population']<1:errors.append('community population must be positive')
        if n['offer']['give'] not in ['food','wood'] or n['offer']['receive'] not in ['food','wood'] or n['offer']['give']==n['offer']['receive']:errors.append('invalid exchange resources')
        if n['aid']['resource'] not in ['food','wood']:errors.append('invalid aid resource')
        if n['offer']['give_amount']<1 or n['offer']['receive_amount']<1 or n['aid']['amount']<1:errors.append('cargo must be positive')
        if len({p['name'] for p in n['leaders']})!=len(n['leaders']):errors.append('speaker profiles must be distinct')
    if tuning['carriers']<1 or tuning['leader_term']<1 or tuning['min_home_reserve']<1:errors.append('positive crew, term and reserve required')
    if not 0<=tuning['initial_escorts']<=tuning['max_escorts']:errors.append('invalid initial escort')
    for key in ['initial_trust','trust_floor','trust_trade_min','chapter_trust','max_loss_percent','neighbor_spoil_percent']:
        if not 0<=tuning[key]<=100:errors.append('percentage outside range: '+key)
    return errors
if __name__=='__main__':
    errors=validate(load('neighbors'),load('neighbors_ui'),load('balance'),load('governance'))
    for error in errors:print(error)
    print(f'NEIGHBOR DATA: {len(errors)} errors')
    raise SystemExit(bool(errors))
