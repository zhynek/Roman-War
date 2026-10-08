#!/usr/bin/env python3
"""Validate the explicitly adopted warfare profile and deterministic boundaries."""
import re
from pathlib import Path
from validate_defense import validate as defense_validate, load
from validate_fortifications import validate as fortification_validate
from validate_threats import validate as threat_validate
from validate_aftermath import validate as aftermath_validate
ROOT=Path(__file__).resolve().parents[1]

def validate(content,balance):
    errors=defense_validate(content,balance)
    errors.extend(fortification_validate(content,balance))
    errors.extend(threat_validate(content,balance))
    errors.extend(aftermath_validate(content,balance))
    if errors:return errors
    w,t=content['warfare'],balance['warfare']['tactics']
    if w['profile']!='village_warfare_v1':errors.append('warfare semantic profile')
    if t['spacing_cm']+2*t['wide_extra_cm']>=balance['defense']['range_cm']:errors.append('formations must reach across spacing')
    if t['fatigue_speed_percent']>100 or t['fatigue_damage_percent']>100:errors.append('fatigue must not improve movement or damage')
    if t['terrain_min_percent']>100 or t['cover_min_percent']>100:errors.append('terrain and cover bounds')
    if not 0<t['enemy_retreat_percent']<100:errors.append('bounded enemy retreat')
    if t['maximum_stat']!=100 or t['vector_scale']!=1000:errors.append('serialized tactical units')
    if t['enemy_objective_ticks']>=balance['defense']['limit_ticks']:errors.append('objective retreat precedes hard bound')
    core='\n'.join((ROOT/'src/core'/name).read_text() for name in ['warfare_rules.gd','tactical_sim.gd','defense_navigation.gd','battle_director.gd','threat_rules.gd'])
    for token in ['Time.', 'OS.', 'randf(', 'randi(', 'extends Node', 'get_tree(', 'FileAccess']:
        if token in core:errors.append('scene-free warfare: '+token)
    for key in t:
        if not re.search(r'\b'+re.escape(key)+r'\b',core):errors.append('unused tactical tuning: '+key)
    return errors
if __name__=='__main__':
    errors=validate(load('governance'),load('balance'))
    for error in errors:print(error)
    print(f'WARFARE DATA: {len(errors)} errors')
    raise SystemExit(bool(errors))
