#!/usr/bin/env python3
"""Bounded threat objectives, explicit adoption and serialized scheduler contract."""
import json
import math
import re
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parents[1]
CONFIGURATIONS = {'stores': ('occupy', 'stores'), 'landing': ('snatch', 'landing'), 'probe': ('probe', 'north')}


def load(name):
    return json.loads((ROOT / 'data' / (name + '.json')).read_text())


def _finite(value):
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, dict):
        return all(_finite(item) for item in value.values())
    if isinstance(value, list):
        return all(_finite(item) for item in value)
    return True


def validate(content, balance):
    data = content.get('warfare', {}).get('threats')
    tuning = balance.get('warfare', {}).get('threats')
    if not _finite([data, tuning]):
        return ['non-finite threat data']
    errors = []
    for name, value in [('governance', data), ('balance', tuning)]:
        schema = json.loads((ROOT / 'schemas' / (name + '.schema.json')).read_text())
        schema = schema['properties']['warfare']['properties']['threats']
        errors.extend(f'{name} threats {error.json_path}: {error.message}'
                      for error in jsonschema.Draft202012Validator(schema).iter_errors(value))
    if errors:
        return errors
    if [entry['id'] for entry in data['encounters']] != list(CONFIGURATIONS):
        errors.append('stable stores, landing, probe cycle required')
    if set(tuning['encounters']) != set(CONFIGURATIONS):
        errors.append('encounter tuning references')
    places = {entry['id'] for entry in content['defense']['places']}
    bounds = content['defense']['bounds']
    cell = balance['defense']['cell_cm']
    for entry in data['encounters']:
        if (entry['kind'], entry['place']) != CONFIGURATIONS.get(entry['id']):
            errors.append('objectives must differ in rules and protected place')
        if entry['place'] not in places:
            errors.append('unknown battle place')
        if entry['origins'][0] == entry['origins'][1]:
            errors.append('distinct approach origins required')
        for x, z in entry['origins']:
            if not bounds[0] <= x * 100 < bounds[0] + bounds[2] * cell or not bounds[1] <= z * 100 < bounds[1] + bounds[3] * cell:
                errors.append('encounter origin outside authoritative navigation')
    for key, spec in tuning['encounters'].items():
        if not spec['capture_ticks'] < spec['deadline_ticks'] <= balance['defense']['limit_ticks']:
            errors.append('objective duration must precede deadline and hard bound')
        if spec['supply_loss'] > balance['defense']['supply_loss']:
            errors.append('new raids must not exceed the retained loss ceiling')
        if key == 'probe' and spec['supply_loss'] != 0:
            errors.append('probe must not take stored supplies')
    if tuning['encounters']['probe']['capture_ticks'] < 300:
        errors.append('northern probe must leave deployment traversal time')
    code = (ROOT / 'src/core/threat_rules.gd').read_text()
    for token in ['Time.', 'OS.', 'randf(', 'randi(', 'extends Node', 'get_tree(', 'FileAccess']:
        if token in code:
            errors.append('scene-free threats: ' + token)
    for key in ['quiet_seasons', 'warning_seasons', 'contact_warning', 'recovery_food_seasons']:
        if not re.search(r'\b' + key + r'\b', code):
            errors.append('unused scheduler tuning: ' + key)
    return errors


if __name__ == '__main__':
    errors = validate(load('governance'), load('balance'))
    for error in errors:
        print(error)
    print(f'THREAT DATA: {len(errors)} errors')
    raise SystemExit(bool(errors))
