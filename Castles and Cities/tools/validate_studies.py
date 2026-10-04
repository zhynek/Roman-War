#!/usr/bin/env python3
"""Validate independent authoring metadata without importing or changing the game.

Only manifests registered in catalog.json are studies. The intentionally
incomplete templates/study.template.json is a starter, so it is not discovered
or validated automatically. Registering a copy makes all study checks apply.

Usage:
    python3 'Castles and Cities/tools/validate_studies.py'
    python3 'Castles and Cities/tools/validate_studies.py' --root /tmp/city-probe

--root selects the directory containing catalog.json. Schemas always come from
the workspace beside this script. This command performs no writes and does not
validate geometry, historical truth, copyright permissions or visual quality.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import Any


WORKSPACE = Path(__file__).resolve().parents[1]
SOURCE_HEADING = re.compile(r"^### `([a-z][a-z0-9]*(?:_[a-z0-9]+)*)`(?:[ \t].*)?$")
READ_FAILED = object()


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key {key!r}")
        result[key] = value
    return result


def reject_nonfinite(value: str) -> None:
    raise ValueError(f"non-finite value {value!r} is not valid JSON")


def pointer(parts: Any) -> str:
    """Use JSON Pointer for stable, unambiguous diagnostic locations."""
    return "".join("/" + str(part).replace("~", "~0").replace("/", "~1") for part in parts)


class Audit:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.errors: list[str] = []

    def error(self, location: str, message: str) -> None:
        self.errors.append(f"{location}: {message}")

    def label(self, path: Path) -> str:
        try:
            return path.relative_to(self.root).as_posix()
        except ValueError:
            return str(path)

    def load_json(self, path: Path) -> Any:
        try:
            return json.loads(
                path.read_text(encoding="utf-8"),
                object_pairs_hook=reject_duplicate_keys,
                parse_constant=reject_nonfinite,
            )
        except json.JSONDecodeError as exc:
            self.error(self.label(path), f"invalid JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}")
        except (OSError, UnicodeError, ValueError) as exc:
            self.error(self.label(path), f"cannot read JSON: {exc}")
        return READ_FAILED

    def file(self, base: Path, relative: str, location: str) -> Path | None:
        """Enforce containment even for symlinks and paths supplied by a probe."""
        try:
            candidate = (base / relative).resolve()
            if Path(relative).is_absolute() or not candidate.is_relative_to(base):
                self.error(location, f"file {relative!r} escapes its allowed directory {self.label(base)!r}")
                return None
            if not candidate.is_file():
                self.error(location, f"referenced file does not exist: {relative!r}")
                return None
            return candidate
        except (OSError, RuntimeError, ValueError) as exc:
            self.error(location, f"cannot resolve file {relative!r}: {exc}")
            return None

    def validate(self, value: Any, validator: Any, location: str) -> bool:
        errors = sorted(validator.iter_errors(value), key=lambda error: (pointer(error.absolute_path), error.message))
        for error in errors:
            self.error(location + "#" + pointer(error.absolute_path), error.message)
        return not errors

    def unique_ids(self, records: list[dict[str, Any]], location: str) -> set[str]:
        seen: dict[str, int] = {}
        for index, record in enumerate(records):
            identity = record["id"]
            if identity in seen:
                self.error(f"{location}/{index}/id", f"duplicate id {identity!r}; first used at {location}/{seen[identity]}/id")
            else:
                seen[identity] = index
        return set(seen)

    def source_ids(self, path: Path) -> set[str] | None:
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeError) as exc:
            self.error(self.label(path), f"cannot read source register: {exc}")
            return None
        sources: dict[str, int] = {}
        # Fenced examples are not actual source entries.
        fence_character = ""
        fence_length = 0
        for line_number, line in enumerate(lines, start=1):
            fence = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line)
            if fence:
                marker, suffix = fence.groups()
                if not fence_character:
                    fence_character, fence_length = marker[0], len(marker)
                elif marker[0] == fence_character and len(marker) >= fence_length and not suffix.strip():
                    fence_character = ""
                continue
            if fence_character:
                continue
            match = SOURCE_HEADING.fullmatch(line.rstrip())
            if not match:
                continue
            identity = match.group(1)
            if identity in sources:
                self.error(f"{self.label(path)}:{line_number}", f"duplicate source heading {identity!r}; first appears on line {sources[identity]}")
            else:
                sources[identity] = line_number
        if not sources:
            self.error(self.label(path), "no source headings found; use ### `source_id` — description")
        return set(sources)

    def study(self, path: Path, entry: dict[str, Any], validator: Any) -> None:
        study = self.load_json(path)
        location = self.label(path)
        if study is READ_FAILED or not self.validate(study, validator, location):
            return
        for key in ("id", "realm_id"):
            if study[key] != entry[key]:
                self.error(f"{location}#/{key}", f"{study[key]!r} does not match catalog value {entry[key]!r}")

        documents = {}
        for key, relative in sorted(study["documents"].items()):
            document = self.file(path.parent, relative, f"{location}#/documents/{key}")
            if document is not None:
                documents[key] = document
        sources = self.source_ids(documents["sources"]) if "sources" in documents else None
        capability_ids = self.unique_ids(study["capabilities"], f"{location}#/capabilities")
        self.unique_ids(study["districts"], f"{location}#/districts")
        snapshot_ids = self.unique_ids(study["historical_snapshots"], f"{location}#/historical_snapshots")
        self.unique_ids(study["creative_variants"], f"{location}#/creative_variants")

        for index, district in enumerate(study["districts"]):
            for reference_index, identity in enumerate(district["capability_ids"]):
                if identity not in capability_ids:
                    self.error(f"{location}#/districts/{index}/capability_ids/{reference_index}", f"unknown capability id {identity!r}")
        if sources is not None:
            for table in ("districts", "historical_snapshots"):
                for index, record in enumerate(study[table]):
                    for reference_index, identity in enumerate(record["source_ids"]):
                        if identity not in sources:
                            self.error(f"{location}#/{table}/{index}/source_ids/{reference_index}", f"source id {identity!r} has no ### `source_id` heading in {study['documents']['sources']}")

        active = [snapshot for snapshot in study["historical_snapshots"] if snapshot["status"] == "active_reference"]
        if len(active) != 1:
            self.error(f"{location}#/historical_snapshots", f"expected exactly one active_reference snapshot, found {len(active)}")
        else:
            if active[0]["id"] != study["active_snapshot_id"]:
                self.error(f"{location}#/active_snapshot_id", f"must name the active_reference snapshot {active[0]['id']!r}")
            if active[0]["year_ce"] != study["reference_year_ce"]:
                self.error(f"{location}#/reference_year_ce", f"must match active snapshot year {active[0]['year_ce']}")
        if study["active_snapshot_id"] not in snapshot_ids:
            self.error(f"{location}#/active_snapshot_id", f"unknown snapshot id {study['active_snapshot_id']!r}")
        for index, variant in enumerate(study["creative_variants"]):
            if variant["base_snapshot_id"] not in snapshot_ids:
                self.error(f"{location}#/creative_variants/{index}/base_snapshot_id", f"unknown snapshot id {variant['base_snapshot_id']!r}")
            self.file(path.parent, variant["brief"], f"{location}#/creative_variants/{index}/brief")

    def catalog(self, catalog_validator: Any, study_validator: Any) -> tuple[int, int]:
        path = self.file(self.root, "catalog.json", "catalog.json")
        if path is None:
            return 0, 0
        catalog = self.load_json(path)
        if catalog is READ_FAILED or not self.validate(catalog, catalog_validator, "catalog.json"):
            return 0, 0
        realm_ids = self.unique_ids(catalog["realms"], "catalog.json#/realms")
        self.unique_ids(catalog["studies"], "catalog.json#/studies")
        for index, realm in enumerate(catalog["realms"]):
            self.file(self.root, realm["brief"], f"catalog.json#/realms/{index}/brief")
        manifests: dict[Path, int] = {}
        for index, entry in enumerate(catalog["studies"]):
            location = f"catalog.json#/studies/{index}"
            if entry["realm_id"] not in realm_ids:
                self.error(location + "/realm_id", f"unknown realm id {entry['realm_id']!r}")
            manifest = self.file(self.root, entry["manifest"], location + "/manifest")
            if manifest is None:
                continue
            if manifest in manifests:
                self.error(location + "/manifest", f"duplicate manifest; first registered at catalog.json#/studies/{manifests[manifest]}/manifest")
                continue
            manifests[manifest] = index
            self.study(manifest, entry, study_validator)
        return len(catalog["realms"]), len(catalog["studies"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=WORKSPACE, help="workspace containing catalog.json (default: folder beside this script's tools directory)")
    args = parser.parse_args()
    try:
        from jsonschema import Draft202012Validator
        from jsonschema.exceptions import SchemaError
    except ImportError:
        print("City-study validation needs the Python package 'jsonschema'. Install it in your Python environment with: python3 -m pip install jsonschema", file=sys.stderr)
        return 2
    try:
        root = args.root.expanduser().resolve()
    except (OSError, RuntimeError) as exc:
        print(f"ERROR: cannot resolve workspace: {exc}", file=sys.stderr)
        return 2
    audit = Audit(root)
    if not root.is_dir():
        audit.error(str(root), "workspace directory does not exist")
    validators = {}
    for name in ("catalog", "study"):
        path = WORKSPACE / "schemas" / f"{name}.schema.json"
        schema = audit.load_json(path)
        if schema is READ_FAILED:
            continue
        try:
            Draft202012Validator.check_schema(schema)
            validators[name] = Draft202012Validator(schema)
        except SchemaError as exc:
            audit.error(audit.label(path) + "#" + pointer(exc.absolute_path), f"invalid schema: {exc.message}")
    realms, studies = 0, 0
    if not audit.errors:
        realms, studies = audit.catalog(validators["catalog"], validators["study"])
    for error in audit.errors:
        print("ERROR: " + error, file=sys.stderr)
    print(f"City-study validation: {realms} realm(s), {studies} registered study/studies, {len(audit.errors)} error(s).")
    print("Templates are intentionally incomplete starters; only catalog-registered manifests are validated.")
    return 1 if audit.errors else 0


if __name__ == "__main__":
    sys.exit(main())
