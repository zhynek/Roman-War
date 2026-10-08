#!/usr/bin/env python3
"""Validate Marcus presentation content and links to the existing village guide."""
import json
import re
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parents[1]


def validate(content):
    schema = json.loads((ROOT / "schemas/marcus.schema.json").read_text())
    errors = [
        f"marcus {error.json_path}: {error.message}"
        for error in jsonschema.Draft202012Validator(schema).iter_errors(content)
    ]
    if errors:
        return errors
    guide = json.loads((ROOT / "data/visual_commands.json").read_text())
    if len(content["lesson_counsel"]) != len(guide["lessons"]):
        errors.append("Marcus needs one counsel entry for each existing guide lesson")
    ids = [page["id"] for page in content["intro"]]
    if len(ids) != len(set(ids)):
        errors.append("duplicate Marcus opening page id")
    assets = {asset["id"] for asset in guide["assets"]}
    for lesson in guide["lessons"]:
        if lesson["asset"] not in assets:
            errors.append("Marcus guide references an unknown village place")
        if lesson.get("destination", "asset") not in {"asset", "lifecycle", "defense", "aftermath"}:
            errors.append("Marcus guide references an unsupported destination")
    source = (ROOT / "src/marcus_panel.gd").read_text()
    for key in re.findall(r'\bw\("([a-z_]+)"\)', source):
        if key not in content["ui"]:
            errors.append(f"missing Marcus UI copy: {key}")
    transport = (ROOT / "src/marcus_voice.gd").read_text()
    for key in re.findall(r'\b(?:_set_status|_fail)\("([a-z_]+)"\)', transport):
        if key not in content["status"]:
            errors.append(f"missing Marcus connection status: {key}")
    for key, parameters in {"progress": {"number", "total"}, "question_too_long": {"limit"}}.items():
        if set(re.findall(r"\{([a-z_]+)\}", content["ui"][key])) != parameters:
            errors.append(f"invalid Marcus placeholders: {key}")
    return errors


if __name__ == "__main__":
    problems = validate(json.loads((ROOT / "data/marcus.json").read_text()))
    for problem in problems:
        print(problem)
    print(f"MARCUS DATA: {len(problems)} errors")
    raise SystemExit(bool(problems))
