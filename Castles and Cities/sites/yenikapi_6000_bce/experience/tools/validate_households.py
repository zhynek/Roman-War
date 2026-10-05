#!/usr/bin/env python3
"""Closed content schema, tuning and stable interior links for household scenarios."""
import json
from pathlib import Path
import jsonschema
ROOT = Path(__file__).resolve().parents[1]
ORDER_IDS = ['secure_stores', 'refuge', 'safe_routes', 'learning']
STAGE_IDS = ['warning', 'danger', 'recovery', 'renewal', 'settled']
def load(name):
    return json.loads((ROOT / 'data' / f'{name}.json').read_text())
def validate(config, balance, governance, settlement):
    errors = []
    for name, data in [('households', config), ('balance', balance)]:
        schema = json.loads((ROOT / 'schemas' / f'{name}.schema.json').read_text())
        errors.extend(f'{name} {e.json_path}: {e.message}' for e in jsonschema.Draft202012Validator(schema).iter_errors(data))
    if errors:
        return errors
    tuning = balance['households']
    if [s['id'] for s in config['stages']] != STAGE_IDS:
        errors.append('stages must preserve explicit authored order')
    if [s['id'] for s in config['orders']] != ORDER_IDS:
        errors.append('orders must preserve stable action identifiers')
    if [s['role'] for s in config['orders']] != ['steward', 'steward', 'watch', 'steward']:
        errors.append('household and route authorities must remain explicit')
    stations = {s['id']: s for s in config['stations']}
    if len(stations) != len(config['stations']) or {s['use'] for s in config['stations']} != {'home', 'store', 'workshop'}:
        errors.append('three distinct home, store and workshop stations required')
    buildings = {o['id']: o for o in settlement['objects'] if o['kind'] == 'building'}
    for station in config['stations']:
        building = buildings.get(station['building'])
        if building is None:
            errors.append('unknown reference interior: ' + station['building'])
        elif building['use'] != {'home': 'dwelling', 'store': 'storage', 'workshop': 'work'}[station['use']]:
            errors.append('station use does not match its reference building')
    for order in config['orders']:
        if order['station'] not in stations:
            errors.append('unknown action station')
    homes = governance['households']
    if len({h['id'] for h in homes}) != len(homes):
        errors.append('household memories require unique governance household IDs')
    for key in ['stage_seasons', 'max_stock', 'care_minimum', 'store_care_minimum', 'watch_minimum', 'stress_wellbeing_divisor', 'stress_cooperation_divisor', 'practice_affinity_span']:
        if tuning[key] < 1:
            errors.append('positive household tuning required: ' + key)
    if tuning['max_stock'] != 100:
        errors.append('household memory display requires a 0..100 stock')
    for key in ['learning_food', 'stress_hunger', 'learning_cooperation', 'secure_food_relief', 'route_food_relief', 'route_security', 'store_security', 'refuge_wellbeing', 'practice_affinity_step', 'recovery_practice', 'renewal_practice', 'settled_practice']:
        if tuning[key] < 0:
            errors.append('nonnegative household tuning required: ' + key)
    if tuning['refuge_stress'] > 0:
        errors.append('care must not increase stress')
    if any(v < 0 for v in tuning['costs'].values()):
        errors.append('preparation costs cannot grant wood')
    if any(s['food_penalty'] < 0 for s in tuning['stages'].values()):
        errors.append('circumstances cannot create food')
    if any(tuning['stages'][s]['stress'] >= 0 for s in ['recovery', 'renewal', 'settled']):
        errors.append('recovery must permit household stress to ease')
    return errors
if __name__ == '__main__':
    errors = validate(load('households'), load('balance'), load('governance'), load('settlement'))
    for error in errors:
        print(error)
    print(f'HOUSEHOLD DATA: {len(errors)} errors')
    raise SystemExit(bool(errors))
