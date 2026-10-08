#!/usr/bin/env python3
"""Village-specific battle content, reference, and deterministic-boundary gates."""
import json
import re
from pathlib import Path
from validate_governance import validate as base_validate, load
ROOT = Path(__file__).resolve().parents[1]

def validate(content, balance):
    errors = base_validate(content, balance, load('governance_ui'))
    if errors:
        return errors
    d, t = content['defense'], balance['defense']
    if d['profile'] != 'village_defense_v1' or d['scenario'] != 'stores_at_dawn':
        errors.append('unknown defense semantic profile')
    if [p['id'] for p in d['places']] != ['stores', 'north', 'landing', 'refuge']:
        errors.append('defense place identities')
    if not (t['tick_ms'] == 100 and t['step_cm'] < t['cell_cm'] and t['withdraw_step_cm'] < t['cell_cm']):
        errors.append('integer movement quantum')
    if t['range_cm'] >= t['acquire_cm'] or t['route_morale'] >= t['enemy_morale']:
        errors.append('combat ranges/morale')
    if t['capture_ticks'] >= t['limit_ticks'] or t['idle_ticks'] >= t['limit_ticks']:
        errors.append('bounded encounter')
    if t['maximum_defenders'] > 8 or t['group_size'] > 2 or t['enemy_people'] > 8:
        errors.append('small-group bounds')
    core = '\n'.join((ROOT/'src/core'/name).read_text() for name in ['defense_rules.gd','defense_navigation.gd','defense_sim.gd'])
    for token in ['Time.', 'OS.', 'randf(', 'randi(', 'extends Node', 'get_tree(', 'FileAccess']:
        if token in core:
            errors.append('scene-free rules: '+token)
    for key in t:
        if not re.search(r'\b'+re.escape(key)+r'\b', core+(ROOT/'src/defense_adapter.gd').read_text()+(ROOT/'src/defense_host.gd').read_text()):
            errors.append('unused defense tuning: '+key)
    return errors

if __name__ == '__main__':
    errors = validate(load('governance'),load('balance'))
    for error in errors: print(error)
    print(f'DEFENSE DATA: {len(errors)} errors')
    raise SystemExit(bool(errors))
