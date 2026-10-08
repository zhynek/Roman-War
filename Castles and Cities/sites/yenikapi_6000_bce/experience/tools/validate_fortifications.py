#!/usr/bin/env python3
"""Closed fortification content, paid-project, evidence and geometry contracts."""
import copy
import json
import math
import re
from pathlib import Path

import jsonschema
from validate_settlement import validate as validate_snapshot

ROOT = Path(__file__).resolve().parents[1]
PROJECTS = {
    'warfare_store_screen': [[[6, 20], [6, 27]], [[6, 34], [6, 40]]],
    'warfare_landing_screen': [[[26, 5], [26, 12]], [[26, 20], [26, 27]]],
}
POSITIONS = {
    'watch_assembly': [22, -10], 'stores': [-3, 31], 'north': [15, -37],
    'landing': [30, 12], 'refuge': [-30, 16], 'store_gate': [6, 31],
    'store_stand': [3, 31], 'landing_gate': [26, 16], 'landing_stand': [29, 16],
}


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
    data = content.get('warfare', {}).get('fortifications')
    tuning = balance.get('warfare', {}).get('fortifications')
    if not _finite([data, tuning]):
        return ['non-finite fortification data']
    errors = []
    for name, value in [('governance', data), ('balance', tuning)]:
        schema = json.loads((ROOT / 'schemas' / (name + '.schema.json')).read_text())
        schema = schema['properties']['warfare']['properties']['fortifications']
        errors.extend(f'{name} fortifications {error.json_path}: {error.message}'
                      for error in jsonschema.Draft202012Validator(schema).iter_errors(value))
    if errors:
        return errors
    projects = {project['id']: project for project in data['projects']}
    if len(projects) != len(data['projects']) or set(projects) != set(PROJECTS):
        errors.append('exactly the two named screen projects are required')
    if set(tuning['projects']) != set(projects):
        errors.append('fortification project tuning references')
    existing_projects = {project['id'] for name in ['governance', 'land', 'living', 'incidents']
                         for project in load(name)['projects']}
    existing_projects.update(project['id'] for project in load('lifecycle')['projects'])
    if set(projects) & existing_projects or 'watch_shelter' not in existing_projects:
        errors.append('fortification project identity or shelter prerequisite')
    snapshot = copy.deepcopy(load('settlement'))
    authored_ids = {record['id'] for record in snapshot['objects']}
    for project in data['projects']:
        if project['tuning'] != project['id'] or project['tuning'] not in tuning['projects']:
            errors.append('fortification project cost reference')
        segments = [change['after'][0]['points'] for change in project['changes']]
        if segments != PROJECTS.get(project['id']):
            errors.append('screen segments must preserve the checked open entrance')
        for change in project['changes']:
            record = change['after'][0]
            if record['id'] in authored_ids:
                errors.append('screen must have a new stable fabric identity')
            authored_ids.add(record['id'])
            snapshot['objects'].append(record)
    errors.extend(validate_snapshot(snapshot))
    positions = {position['id']: position['at'] for position in data['positions']}
    if len(positions) != len(data['positions']) or positions != POSITIONS:
        errors.append('planning positions must match checked village ground')
    if not set(data['slots'].values()) <= positions.keys():
        errors.append('unknown default planning position')
    for legacy in content.get('defense', {}).get('places', []):
        if positions.get(legacy['id']) != legacy['at']:
            errors.append('legacy defense place must remain unchanged')
    defenses = {item['project']: item['position'] for item in data['defenses']}
    if len(defenses) != len(data['defenses']) or defenses != {
            'warfare_store_screen': 'store_stand', 'warfare_landing_screen': 'landing_stand'}:
        errors.append('each paid screen must protect its checked inner stand')
    if tuning['protection'] < balance.get('warfare', {}).get('tactics', {}).get('cover_min_percent', 100):
        errors.append('screen protection exceeds tactical limit')
    gap_cm = min(math.dist(segments[0][-1], segments[1][0]) * 100
                 for segments in PROJECTS.values())
    if tuning['radius_cm'] > gap_cm / 2:
        errors.append('protected stand must remain local to its open entrance')
    code = (ROOT / 'src/core/fortification_rules.gd').read_text()
    for token in ['Time.', 'OS.', 'randf(', 'randi(', 'extends Node', 'get_tree(', 'FileAccess']:
        if token in code:
            errors.append('scene-free fortifications: ' + token)
    for key in ['projects', 'wood', 'work', 'effects', 'radius_cm', 'protection']:
        if not re.search(r'\b' + re.escape(key) + r'\b', code):
            errors.append('unused fortification tuning: ' + key)
    return errors


if __name__ == '__main__':
    errors = validate(load('governance'), load('balance'))
    for error in errors:
        print(error)
    print(f'FORTIFICATION DATA: {len(errors)} errors')
    raise SystemExit(bool(errors))
