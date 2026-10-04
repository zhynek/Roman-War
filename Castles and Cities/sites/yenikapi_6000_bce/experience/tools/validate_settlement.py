#!/usr/bin/env python3
"""Closed schema + cross-reference/identity/geometry checks, independent of campaign."""
import json
import math
from pathlib import Path
import jsonschema
ROOT=Path(__file__).resolve().parents[1]

def validate(data):
    def finite(value):
        if isinstance(value,float):return math.isfinite(value)
        if isinstance(value,list):return all(finite(v) for v in value)
        if isinstance(value,dict):return all(finite(v) for v in value.values())
        return True
    if not finite(data):return ['non-finite number']
    errors=[f'{e.json_path}: {e.message}' for e in jsonschema.Draft202012Validator(json.loads((ROOT/'schemas/settlement.schema.json').read_text()),format_checker=jsonschema.FormatChecker()).iter_errors(data)]
    if errors:return errors
    sources={s['id'] for s in data['sources']}
    ids=set()
    for record in data['objects']:
        if record['id'] in ids:errors.append('duplicate object id: '+record['id'])
        ids.add(record['id'])
        if not set(record['source_ids'])<=sources:errors.append('unknown evidence reference')
        if record['kind']=='building':
            fids=set()
            for f in record['furniture']:
                if f['id'] in fids:errors.append('duplicate furniture id')
                fids.add(f['id'])
                if any(abs(f['at'][i])>record['size'][i]/2-.22 for i in range(2)):errors.append('furniture outside room')
        if 'points' in record:
            for a,b in zip(record['points'],record['points'][1:]):
                if math.dist(a,b)<.5:errors.append('degenerate route or screen')
    if len(sources)!=len(data['sources']):errors.append('duplicate source id')
    for key in ['id','key']:
        if len({s[key] for s in data['stops']})!=len(data['stops']):errors.append('duplicate stop '+key)
    if len(data['stops'])!=8:errors.append('eight navigation stops required')
    return errors

if __name__=='__main__':
    errors=validate(json.loads((ROOT/'data/settlement.json').read_text()))
    for error in errors:print(error)
    print(f'SETTLEMENT DATA: {len(errors)} errors')
    raise SystemExit(bool(errors))
