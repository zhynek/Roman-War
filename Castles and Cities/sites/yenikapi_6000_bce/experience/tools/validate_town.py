#!/usr/bin/env python3
"""Town extends the retained lifecycle; validate physical chains and real readers."""
import copy
import json
from validate_lifecycle import load, validate, ROOT


def validate_town(data, balance):
    errors = validate(data, balance)
    if errors:
        return errors
    if 'town' not in data or 'town_lifecycle' not in balance:
        return ['missing town contract']
    town, tuning = data['town'], balance['town_lifecycle']
    ids = {p['id'] for p in town['projects']}
    if ids != {'town_civic', 'town_preparation', 'town_provision'}:
        return ['town needs the civic house and both implemented operational investments']
    if set(tuning['projects']) != ids:
        return ['town project tuning mismatch']
    merged = copy.deepcopy(data)
    merged.pop('town')
    for key in ['projects', 'sites', 'proposals']:
        merged[key] += copy.deepcopy(town[key])
    merged['stages'][2]['status'] = 'playable'
    # Use the existing graph/physical validator, with the same pre-town
    # foundation edges. Numeric support is read directly at runtime, not copied.
    transition = copy.deepcopy(town['transition'])
    transition['readiness'] = {'all': [{'id': 'population', 'kind': 'population', 'tuning': 'population'}], 'any': []}
    for id in balance['town_required_projects']:
        equivalents = [id] + load('land')['alternatives'].get(id, [])
        merged['factors'][id] = id
        transition['readiness']['any'].append({'id': id, 'predicates': [{'id': x, 'kind': 'project', 'project': x} for x in equivalents]})
    merged['transitions'].append(transition)
    full_balance = copy.deepcopy(balance)
    full_balance['lifecycle']['projects'].update(tuning['projects'])
    errors += validate(merged, full_balance, operational={'town_preparation', 'town_provision'}, check_schema=False)
    predecessors = {(o['id'], o['revision']): o for o in load('settlement')['objects']}
    for project in data['projects'] + load('governance')['projects'] + load('land')['projects']:
        for change in project['changes']:
            for obj in change['after']:
                predecessors[(obj['id'], obj['revision'])] = obj
    for project in town['projects']:
        if project['id'] == 'town_civic' and data['civic_project'] not in project['requires']:
            errors.append('civic house requires the paid assembly predecessor')
        if tuning['projects'][project['id']]['effects']:
            errors.append('town operational effects must not also grant passive effects')
        if project['id'] != 'town_civic' and 'town_civic' not in project['requires']:
            errors.append('investment requires paid civic fabric')
        tokens = {'town_civic': ['workers'], 'town_preparation': ['delta', 'total', 'shared_total', 'wood', 'places'], 'town_provision': ['delta', 'total', 'workers']}[project['id']]
        if any('{'+x+'}' not in project['presentation']['benefit'] for x in tokens):
            errors.append('operational benefit must render actual tuning')
        for change in project['changes']:
            if change['kind'] != 'altered' or any(o['use'] == 'dwelling' for o in change['after']):
                errors.append('town is bounded to nonresidential alterations')
            for obj in change['after']:
                before = predecessors.get((obj['id'], change['expected_revisions'].get(obj['id'])))
                if before and before.get('use') != obj.get('use'):
                    errors.append('town preserves the existing nonresidential use')
    if tuning['civic_workers'] <= balance['lifecycle']['civic_workers']:
        errors.append('town obligation must quote increased total staffing')
    if tuning['service_priority'] < tuning['civic_priority']:
        errors.append('service allocation must follow civic duty')
    core = (ROOT/'src/core/lifecycle_rules.gd').read_text()
    for key in set(tuning) - {'projects'}:
        if 'town_balance.'+key not in core:
            errors.append('unused town tuning '+key)
    return errors


if __name__ == '__main__':
    errors = validate_town(load('lifecycle'), load('balance'))
    for error in errors: print(error)
    print(f'TOWN DATA: {len(errors)} errors')
    raise SystemExit(bool(errors))
