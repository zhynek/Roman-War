#!/usr/bin/env python3
"""Validate the hypothetical campaign's data, links, balance and fabric definitions."""
import copy
import json
import math
import re
from pathlib import Path
import jsonschema
from validate_settlement import validate as validate_snapshot
ROOT=Path(__file__).resolve().parents[1]
def load(name):return json.loads((ROOT/'data'/f'{name}.json').read_text())
def validate(content,balance,ui):
    errors=[]
    for name,data in [('governance',content),('balance',balance),('governance_ui',ui)]:
        schema=json.loads((ROOT/'schemas'/f'{name}.schema.json').read_text())
        errors.extend(f'{name} {e.json_path}: {e.message}' for e in jsonschema.Draft202012Validator(schema).iter_errors(data))
    if errors:return errors
    def finite(v):
        if isinstance(v,float):return math.isfinite(v)
        if isinstance(v,list):return all(finite(x) for x in v)
        if isinstance(v,dict):return all(finite(x) for x in v.values())
        return True
    if not all(finite(v) for v in [content,balance,ui]):return ['non-finite content']
    negative={'wellbeing_hunger','wellbeing_crowded','wellbeing_tight','cooperation_hunger','cooperation_crowded','cooperation_tight','overwork_cost'}
    for key,value in balance.items():
        if isinstance(value,int) and ((key in negative and value>0) or (key not in negative and value<0)):errors.append('wrong balance sign: '+key)
    if any(y<=0 for y in balance['food_yields']):errors.append('food yield must be positive')
    if any(not re.fullmatch('[a-z][a-z0-9_]*',p['id']) for p in content['projects']+content['initial_citizens']+content['households']):errors.append('invalid stable id')
    projects={p['id']:p for p in content['projects']}
    if len(projects)!=len(content['projects']):errors.append('duplicate project')
    if content['kind']!='hypothetical' or content['base_snapshot_id']!='yenikapi_c6000_bce':errors.append('wrong scenario boundary')
    people={p['id'] for p in content['initial_citizens']}
    if len(people)!=len(content['initial_citizens']):errors.append('duplicate person')
    if not set(content['initial_leaders'].values())<=people:errors.append('unknown leader')
    if len(set(content['initial_leaders'].values()))!=2:errors.append('offices share leader')
    if not set(content['tutorial_projects'])<=projects.keys() or not set(balance['town_required_projects'])<=projects.keys():errors.append('unknown tutorial project')
    if len(balance['food_yields'])!=4 or len(balance['annual_pressure'])!=8:errors.append('season tables must span four/eight seasons')
    for key in ['term_seasons','adult_age','retirement_age','death_age','birth_credit_threshold','steward_work_divisor','town_sustained_seasons','food_per_person']:
        if balance[key]<=0:errors.append('nonpositive '+key)
    if not balance['adult_age']<balance['retirement_age']<balance['death_age']:errors.append('invalid life ages')
    snapshot=load('settlement');records={o['id']:o for o in snapshot['objects']}
    complete=set()
    for project in content['projects']:
        if project['wood']<0 or project['work']<=0:errors.append('invalid project cost')
        if not set(project['requires'])<=complete:errors.append('project dependency cycle or order')
        complete.add(project['id'])
        for change in project['changes']:
            if change['kind']=='altered' and (len(change['after'])!=1 or change['before']!=[change['after'][0]['id']]):errors.append('alteration lost identity')
            if not set(change['before'])<=records.keys():errors.append('unknown predecessor')
            for record in change['after']:
                if change['kind']=='added' and record['id'] in records:errors.append('new object reused id')
                records[record['id']]=copy.deepcopy(record)
    snapshot['objects']=list(records.values())
    errors.extend(validate_snapshot(snapshot))
    if any(len(p['at'])!=2 or any(abs(v)>160 for v in p['at']) for p in content['projects']):errors.append('project site outside walking envelope')
    households={h['id']:h for h in content['households']}
    if len(households)!=len(content['households']):errors.append('duplicate household')
    for h in content['households']:
        if h['building_id'] not in records or records[h['building_id']].get('use')!='dwelling':errors.append('household needs a dwelling')
        if h['requires'] and h['requires'] not in projects:errors.append('unknown household project')
    for person in content['initial_citizens']:
        if person['household'] not in households:errors.append('unknown household membership')
    for key in ['steward','watch']:
        for person in content['initial_citizens']:
            if person['id']==content['initial_leaders'][key] and not balance['adult_age']<=person['age']<balance['retirement_age']:errors.append('ineligible initial leader')
    return errors
if __name__=='__main__':
    errors=validate(load('governance'),load('balance'),load('governance_ui'))
    if not errors:
        from validate_neighbors import validate as validate_contacts
        errors.extend(validate_contacts(load("neighbors"),load("neighbors_ui"),load("balance"),load("governance")))
    if not errors:
        from validate_households import validate as validate_household_life
        errors.extend(validate_household_life(load("households"),load("balance"),load("governance"),load("settlement")))
    for error in errors:print(error)
    print(f'GOVERNANCE DATA: {len(errors)} errors')
    raise SystemExit(bool(errors))
