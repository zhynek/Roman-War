#!/usr/bin/env python3
"""Closed, bounded aftermath tuning and original-evidence/recovery contracts."""
import json
import math
import re
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parents[1]


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
    data = content.get('warfare', {}).get('aftermath')
    tuning = balance.get('warfare', {}).get('aftermath')
    if not _finite([data, tuning]):
        return ['non-finite aftermath data']
    errors = []
    for name, value in [('governance', data), ('balance', tuning)]:
        schema = json.loads((ROOT / 'schemas' / (name + '.schema.json')).read_text())
        schema = schema['properties']['warfare']['properties']['aftermath']
        errors.extend(f'{name} aftermath {error.json_path}: {error.message}'
                      for error in jsonschema.Draft202012Validator(schema).iter_errors(value))
    if errors:
        return errors
    if tuning['experience_per_engagement'] != 1:
        errors.append('one visible experience credit per engaged encounter')
    if tuning['maximum_experience'] > balance['warfare']['tactics']['max_skill'] * tuning['experience_per_skill']:
        errors.append('experience cannot exceed the defined tactical skill range')
    if tuning['maximum_experience'] < tuning['experience_per_skill']:
        errors.append('experience must allow an attainable skill improvement')
    if tuning['mild_recovery_seasons'] >= tuning['incapacitated_recovery_seasons']:
        errors.append('incapacitation must need more treatment than a mild wound')
    if tuning['mild_injury_hp_loss'] >= balance['defense']['hp_per_person']:
        errors.append('mild injury threshold must precede full incapacitation')
    if tuning['household_stress_injury'] > tuning['household_stress_incapacitated'] or tuning['household_stress_incapacitated'] > balance['households']['max_stock']:
        errors.append('household strain must follow severity within the retained stock limit')
    if tuning['equipment_repair_gain'] > tuning['equipment_initial_condition']:
        errors.append('one repair cannot exceed the defined condition range')
    if tuning['care_priority'] >= balance['warfare']['muster']['priority']:
        errors.append('treatment care must precede optional additional watch')
    if balance['living']['repair_wood'] <= 0 or balance['living']['repair_workers'] <= 0:
        errors.append('equipment restoration must retain ordinary paid material and labor costs')
    path = ROOT / 'src/core/aftermath_rules.gd'
    if not path.is_file():
        errors.append('missing deterministic aftermath implementation')
        return errors
    code = path.read_text()
    for token in ['Time.', 'OS.', 'randf(', 'randi(', 'extends Node', 'get_tree(', 'FileAccess']:
        if token in code:
            errors.append('scene-free aftermath: ' + token)
    for key in tuning:
        if not re.search(r'\b' + re.escape(key) + r'\b', code):
            errors.append('unused aftermath tuning: ' + key)
    return errors


if __name__ == '__main__':
    errors = validate(load('governance'), load('balance'))
    for error in errors:
        print(error)
    print(f'AFTERMATH DATA: {len(errors)} errors')
    raise SystemExit(bool(errors))
