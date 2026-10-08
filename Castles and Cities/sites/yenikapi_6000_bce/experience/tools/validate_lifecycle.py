#!/usr/bin/env python3
"""Validate civic progression, upgrade identity, authored gates and their readers."""
import copy
import json
import re
from pathlib import Path

import jsonschema
from validate_settlement import validate as validate_snapshot

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    return json.loads((ROOT / 'data' / f'{name}.json').read_text())


def validate(data, balance, operational=(), check_schema=True):
    errors = []
    for name, value in ([('lifecycle', data), ('balance', balance)] if check_schema else []):
        schema = json.loads((ROOT / 'schemas' / f'{name}.schema.json').read_text())
        errors += [f'{name} {e.json_path}: {e.message}' for e in jsonschema.Draft202012Validator(schema).iter_errors(value)]
    if errors:
        return errors
    stages = {s['id']: s for s in data['stages']}
    transitions = data['transitions']
    tuning = balance['lifecycle']
    legacy = [p for name in ['governance', 'land', 'living', 'incidents'] for p in load(name)['projects']]
    projects = {p['id']: p for p in legacy + data['projects']}
    new = {p['id']: p for p in data['projects']}
    asset_ids = {a['id'] for a in load('assets')['assets']}
    sites = {s['id']: s for s in load('land')['sites'] + data['sites']}
    proposals = {p['id']: p for p in load('land')['proposals'] + data['proposals']}
    identifiers = [s['id'] for s in data['stages']]
    if len(stages) != len(identifiers): errors.append('duplicate stage')
    if len(projects) != len(legacy) + len(new) or len(new) != len(data['projects']): errors.append('duplicate project')
    if len({t['id'] for t in transitions}) != len(transitions): errors.append('duplicate transition')
    if len({t['from'] for t in transitions}) != len(transitions): errors.append('ambiguous next transition')
    if len(sites) != len(load('land')['sites']) + len(data['sites']): errors.append('duplicate site')
    if len(proposals) != len(load('land')['proposals']) + len(data['proposals']): errors.append('duplicate proposal')
    if {p['id'] for p in data['proposals']} != set(new): errors.append('lifecycle proposal coverage mismatch')
    for id in list(stages) + list(new) + [t['id'] for t in transitions]:
        if not re.fullmatch('[a-z][a-z0-9_]*', id): errors.append('invalid identifier ' + id)
    if data['initial_stage'] not in stages or data['recognized_stage'] not in stages: errors.append('unknown profile stage')
    if set(tuning['projects']) != set(new): errors.append('project tuning mismatch')
    if any(s['status'] not in ['playable', 'planned'] for s in stages.values()): errors.append('invalid stage status')
    if len({t['project'] for t in transitions}) != len(transitions): errors.append('civic project reused')
    civic_project = new.get(data['civic_project'])
    if not civic_project or not any(t['project'] == data['civic_project'] and stages.get(t['to'], {}).get('status') == 'playable' for t in transitions):
        errors.append('civic project must reference an active transition project')
    elif civic_project['asset'] not in asset_ids:
        errors.append('civic project has unknown asset')
    stage_order = {id: index for index, id in enumerate(identifiers)}
    transition_order = [stage_order[t['from']] for t in transitions if t['from'] in stages]
    if transition_order != sorted(transition_order): errors.append('transitions must follow stage order')

    def predicates(transition):
        ready = transition['readiness']
        return ready['all'] + [p for group in ready['any'] for p in group['predicates']]

    for transition in transitions:
        if transition['from'] not in stages or transition['to'] not in stages: errors.append('unknown transition stage')
        else:
            if stages[transition['to']]['status'] != 'playable': errors.append('planned stage has active transition')
            if stage_order[transition['to']] <= stage_order[transition['from']]: errors.append('civic transition must advance stage')
        if transition['project'] not in new: errors.append('unknown civic project')
        elif new[transition['project']]['stage_requires'] != transition['from']: errors.append('civic predecessor mismatch')
        factor_ids = [p['id'] for p in transition['readiness']['all']] + [g['id'] for g in transition['readiness']['any']]
        if len(set(factor_ids)) != len(factor_ids): errors.append('duplicate readiness factor')
        if not set(factor_ids) <= data['factors'].keys(): errors.append('missing factor copy')
        for group in transition['readiness']['any']:
            if not group['predicates']: errors.append('empty alternative group')
        for predicate in predicates(transition):
            kind = predicate['kind']
            if kind == 'project' and predicate['project'] not in projects: errors.append('unknown readiness project')
            elif kind == 'site' and predicate['site'] not in sites: errors.append('unknown readiness site')
            elif kind not in ['project', 'site'] and predicate.get('tuning') not in tuning['readiness']: errors.append('unknown readiness tuning')
            if kind == 'stock' and predicate['tuning'] not in ['wellbeing', 'cooperation', 'security']: errors.append('unknown stock reader')
            if kind == 'knowledge' and predicate['tuning'] != 'shaping': errors.append('unknown knowledge reader')

    snapshot = load('settlement')
    records = {o['id']: o for o in snapshot['objects']}
    for p in legacy:
        for change in p['changes']:
            for obj in change['after']:
                previous = records.get(obj['id'], {})
                record = copy.deepcopy(obj)
                record['revision'] = previous.get('revision', 0) + 1 if change['kind'] == 'altered' else 1
                records[obj['id']] = record
    for project in data['projects']:
        project_error_count = len(errors)
        if project['stage_requires'] not in stages: errors.append('unknown project stage')
        if project['asset'] not in asset_ids: errors.append('unknown asset')
        related = project['presentation'].get('related_assets', [])
        if any(a not in asset_ids or a == project['asset'] for a in related): errors.append('invalid related presentation asset')
        if not set(project['requires']) <= projects.keys(): errors.append('unknown prerequisite')
        price = tuning['projects'].get(project['tuning'], {})
        if price.get('wood', 0) <= 0 or price.get('work', 0) <= 0: errors.append('invalid paid project')
        if any(k not in ['housing', 'storage', 'food_yield', 'wellbeing', 'security', 'cooperation'] for k in price.get('effects', {})): errors.append('effect has no existing reader')
        if project['presentation']['treatment'] not in ['building', 'adapt']: errors.append('unknown construction treatment')
        for change in project['changes']:
            expected = change['expected_revisions']
            if set(expected) != set(change['before']) or any(type(v) is not int or v < 1 for v in expected.values()): errors.append('invalid expected revisions')
            if change['kind'] == 'added':
                if change['before'] or expected: errors.append('addition cannot name a predecessor')
                if any(obj['revision'] != 1 for obj in change['after']): errors.append('addition must start at revision 1')
            if change['kind'] == 'altered':
                if len(change['before']) != 1 or len(change['after']) != 1 or change['before'][0] != change['after'][0]['id']: errors.append('alteration identity mismatch')
                if project['presentation']['treatment'] != 'adapt': errors.append('alteration needs adaptation presentation')
                for after in change['after']:
                    if after['revision'] != expected.get(after['id'], 0) + 1: errors.append('invalid successor revision')
                    before = records.get(after['id'])
                    if not before: errors.append('missing physical predecessor'); continue
                    if expected.get(after['id']) != before['revision']: errors.append('stale authored predecessor')
                    for key in ['at', 'yaw', 'size', 'household']:
                        if before.get(key) != after.get(key): errors.append('bounded upgrade moves or displaces existing fabric')
                    furnishings = {f['id']: f for f in after.get('furniture', [])}
                    if any(furnishings.get(f['id']) != f for f in before.get('furniture', [])): errors.append('upgrade loses furnishings')
            sample = copy.deepcopy(snapshot)
            replacements = {o['id'] for o in change['after']}
            sample['objects'] = [o for o in sample['objects'] if o['id'] not in replacements] + copy.deepcopy(change['after'])
            # The immutable dated snapshot schema requires revision 1. Reuse
            # its physical/evidence validator without weakening that contract.
            for obj in sample['objects']: obj['revision'] = 1
            errors += validate_snapshot(sample)
        # Projects are authored in their replay order. Only a whole valid
        # transaction exposes its new revisions to the next project; changes
        # inside one project cannot borrow one another's future predecessors.
        if len(errors) == project_error_count:
            for change in project['changes']:
                for obj in change['after']:
                    records[obj['id']] = copy.deepcopy(obj)
    for proposal in data['proposals']:
        if proposal['site'] not in sites or proposal['id'] not in new: errors.append('unknown site/project proposal')
        if proposal['asset'] != new.get(proposal['id'], {}).get('asset'): errors.append('proposal asset mismatch')
        previous = proposal['predecessor']
        if previous:
            if previous not in proposals or proposals[previous]['site'] != proposal['site']: errors.append('invalid site successor')
            if previous not in new.get(proposal['id'], {}).get('requires', []): errors.append('site successor lacks completed prerequisite')

    # A target describes the cumulative benefit of this physical chain, not a
    # second grant. Effects are incremental; site proposals replace prior totals.
    # UI values are derived from these same definitions, never literal promises.
    def effect_total(id, key, seen=None):
        seen = set() if seen is None else seen
        if id in seen or id not in projects:
            return None
        seen.add(id)
        project = projects[id]
        effects = tuning['projects'].get(project['tuning'], {}).get('effects', {}) if id in new else project['effects']
        if key not in effects:
            return None
        total = effects[key]
        target = project.get('benefit_target')
        if target:
            if target['kind'] != 'effect_total' or target['key'] != key:
                return None
            prior = effect_total(target['predecessor'], key, seen)
            if prior is None:
                return None
            total += prior
        return total

    civic_projects = {t['project'] for t in transitions}
    for project in data['projects']:
        target = project.get('benefit_target')
        if target is None:
            if project['id'] not in civic_projects and project['id'] not in operational: errors.append('improvement lacks benefit target')
            continue
        key, predecessor = target['key'], target['predecessor']
        if predecessor not in project['requires']: errors.append('benefit predecessor lacks completed prerequisite')
        if not all(token in project['presentation']['benefit'] for token in ['{delta}', '{total}']): errors.append('benefit copy must render derived values')
        if target['kind'] == 'effect_total':
            total = effect_total(project['id'], key)
            delta = tuning['projects'].get(project['tuning'], {}).get('effects', {}).get(key, 0)
        else:
            proposal, prior = proposals.get(project['id'], {}), proposals.get(predecessor, {})
            if not prior or proposal.get('predecessor') != predecessor or proposal.get('site') != prior.get('site'):
                errors.append('benefit target must follow the same site predecessor')
            total = proposal.get(key)
            delta = total - prior.get(key, 0) if total is not None else 0
        if total != target['total'] or delta <= 0: errors.append('cumulative benefit target mismatch')

    # A monotonic closure respects all-of / any-of without treating valid
    # alternatives as mandatory. Stages unlock projects; civic readiness can
    # never depend solely on an improvement that it unlocks itself.
    reachable_projects, reachable_stages = set(), {data['initial_stage']}
    for _ in range(len(projects) + len(stages) + 1):
        before = (len(reachable_projects), len(reachable_stages))
        for id, project in projects.items():
            if not set(project['requires']) <= reachable_projects: continue
            if id in new and project['stage_requires'] not in reachable_stages: continue
            civic = next((t for t in transitions if t['project'] == id), None)
            if civic:
                qualifies = lambda p: p['kind'] != 'project' or p['project'] in reachable_projects
                if not all(qualifies(p) for p in civic['readiness']['all']): continue
                if not all(any(qualifies(p) for p in g['predicates']) for g in civic['readiness']['any']): continue
            reachable_projects.add(id)
        for transition in transitions:
            if transition['project'] in reachable_projects: reachable_stages.add(transition['to'])
        if before == (len(reachable_projects), len(reachable_stages)): break
    if not set(new) <= reachable_projects: errors.append('unreachable or cyclic lifecycle prerequisites')
    core_paths = [ROOT / 'src/core/lifecycle_rules.gd', ROOT / 'src/core/asset_rules.gd']
    core = '\n'.join(p.read_text() for p in core_paths if p.exists())
    for key in set(tuning) - {'readiness', 'projects'}:
        if not re.search(r'\b' + re.escape(key) + r'\b', core): errors.append('unused lifecycle tuning ' + key)
    return errors


if __name__ == '__main__':
    problems = validate(load('lifecycle'), load('balance'))
    for problem in problems: print(problem)
    print(f'LIFECYCLE DATA: {len(problems)} errors')
    raise SystemExit(bool(problems))
