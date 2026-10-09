#!/usr/bin/env python3
"""Validate every data table against its JSON Schema, then cross-check the
references JSON Schema cannot see (ids across files, graph symmetry, campaign
coherence). Exits nonzero on any error. Run from anywhere:

    python3 tools/validate_data.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import jsonschema
except ImportError:  # pragma: no cover
    print("pip install jsonschema", file=sys.stderr)
    sys.exit(2)

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
SCHEMAS = ROOT / "schemas"

# data file -> schema file (buildings and temples share one schema)
TABLES = {
    "marcus.json": "marcus.schema.json",
    "lucius.json": "marcus.schema.json",
    "advisors.json": "advisors.schema.json",
    "patronage.json": "patronage.schema.json",
    "council.json": "council.schema.json",
    "waterways.json": "waterways.schema.json",
    "campaign_terrain.json": "campaign_terrain.schema.json",
    "realism_study.json": "realism_study.schema.json",
    "balance.json": "balance.schema.json",
    "city_governance.json": "city_governance.schema.json",
    "roma_city.json": "roma_city.schema.json",
    "ai.json": "ai.schema.json",
    "agents.json": "agents.schema.json",
    "techniques.json": "techniques.schema.json",
    "edicts.json": "edicts.schema.json",
    "epithets.json": "epithets.schema.json",
    "annals.json": "annals.schema.json",
    "cultures.json": "cultures.schema.json",
    "factions.json": "factions.schema.json",
    "buildings.json": "buildings.schema.json",
    "temples.json": "buildings.schema.json",
    "units.json": "units.schema.json",
    "regions.json": "regions.schema.json",
    "campaign.json": "campaign.schema.json",
    "traits.json": "traits.schema.json",
    "ancillaries.json": "ancillaries.schema.json",
    "events.json": "events.schema.json",
    "wonders.json": "wonders.schema.json",
    "missions.json": "missions.schema.json",
    "offices.json": "offices.schema.json",
    "win_conditions.json": "win_conditions.schema.json",
    "names.json": "names.schema.json",
    "mercenaries.json": "mercenaries.schema.json",
    "unit_classes.json": "unit_classes.schema.json",
    "map_geometry.json": "map_geometry.schema.json",
    "glossary.json": "glossary.schema.json",
    "advances.json": "advances.schema.json",
    "society.json": "society.schema.json",
    "edicts.json": "edicts.schema.json",
    "dispatch.json": "dispatch.schema.json",
    "sites.json": "sites.schema.json",
    "guided_campaign.json": "guided_campaign.schema.json",
    "effects_glossary.json": "effects_glossary.schema.json",
    "building_art.json": "building_art.schema.json",
    "unit_art.json": "unit_art.schema.json",
}

LIVE_MISSION_KINDS: set[str] = set()  # filled from SenateRules at startup

LEVELS = ["village", "town", "large_town", "minor_city", "large_city", "huge_city"]

# Trigger kinds authored ahead of the system that will fire them. Everything
# else the engine never fires is flagged as dead content. (Empty since the
# Phase 7 senate offices woke office_gained.)
FORWARD_TRIGGERS: set[str] = set()

# Mission kinds authored ahead of the systems that resolve them. SenateRules
# judges only LIVE_KINDS; port blockades are the Phase 3 remainder, so they
# are forward content, not dead content.
FORWARD_MISSION_KINDS = {"blockade_port"}

# The only substitutions src/ui/dispatch_format.gd knows how to make. A token
# outside this set would print as a literal brace on the player's screen.
DISPATCH_TOKENS = {
    "faction", "other_faction", "region", "settlement", "subject",
    "value", "value_abs", "turn", "year", "season", "detail",
}
# Mission kinds authored ahead of their systems, same idea: port blockades are
# the Phase 3 naval remainder.
FORWARD_MISSIONS = {"blockade_port"}

# Effect keys a schema admits ahead of their engine reader. Anything else in a
# closed effects vocabulary that no rules module reads is dead content.
FORWARD_EFFECTS: set[str] = set()

errors: list[str] = []
warnings: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def load_tables() -> dict[str, dict]:
    tables: dict[str, dict] = {}
    for name, schema_name in TABLES.items():
        path = DATA / name
        if not path.exists():
            err(f"{name}: missing")
            continue
        try:
            document = json.loads(path.read_text())
        except json.JSONDecodeError as exc:
            err(f"{name}: invalid JSON: {exc}")
            continue
        schema = json.loads((SCHEMAS / schema_name).read_text())
        validator = jsonschema.Draft202012Validator(schema)
        for violation in sorted(validator.iter_errors(document), key=str):
            path_str = "/".join(str(p) for p in violation.absolute_path)
            err(f"{name}: {path_str}: {violation.message[:200]}")
        tables[name] = document
    return tables


def _patronage_checks(t: dict[str, dict]) -> None:
    profiles = t.get("patronage.json", {}).get("patrons", [])
    ids = [profile.get("id") for profile in profiles]
    if len(ids) != len(set(ids)):
        err("patronage: duplicate patron id")
    chains = {chain["id"]: chain for chain in t.get("temples.json", {}).get("chains", [])}
    for profile in profiles:
        for chain_id in profile.get("temple_chains", []):
            if chain_id not in chains or chains[chain_id].get("kind") != "temple":
                err(f"patronage: unknown temple chain {chain_id}")
        if not set(re.findall(r"\{([a-z_]+)\}", profile.get("mission", ""))) <= {"target", "minimum_order"}:
            err("patronage: unsupported mission placeholder")


def _advisor_checks(t: dict[str, dict]) -> None:
    advisors = t.get("advisors.json", {}).get("advisors", [])
    ids = [a.get("id") for a in advisors]
    if len(ids) != len(set(ids)):
        err("advisors: duplicate advisor id")
    chains = t.get("buildings.json", {}).get("chains", [])
    for advisor in advisors:
        content = t.get(advisor.get("id", "") + ".json", {})
        if content.get("id") != advisor.get("id") or content.get("name") != advisor.get("name"):
            err("advisors: missing or mismatched advisor content")
        unlock = advisor.get("unlock", {})
        for culture in t.get("cultures.json", {}).get("cultures", []):
            if not any(c.get("kind") == unlock.get("building_kind") and culture["id"] in c.get("cultures", [])
                       and len(c.get("levels", [])) >= unlock.get("min_level", 0) for c in chains):
                err(f"advisors: {advisor.get('id')} prerequisite unreachable for {culture['id']}")


def _marcus_checks(t: dict[str, dict], name="marcus.json") -> None:
    content = t.get(name, {})
    if len(content.get("lesson_counsel", [])) != len(content.get("lessons", [])):
        err("marcus: each campaign lesson needs a counsel entry")
    for section in ("intro", "lessons"):
        ids = [page.get("id") for page in content.get(section, [])]
        if len(ids) != len(set(ids)):
            err(f"marcus: duplicate {section} id")
    shared = ROOT / "Castles and Cities/sites/yenikapi_6000_bce/experience/src"
    for key in re.findall(r'\bw\("([a-z_]+)"\)', (shared / "marcus_panel.gd").read_text()):
        if key not in content.get("ui", {}):
            err(f"marcus: missing UI copy {key}")
    for key in re.findall(r'\b(?:_set_status|_fail)\("([a-z_]+)"\)', (shared / "marcus_voice.gd").read_text()):
        if key not in content.get("status", {}):
            err(f"marcus: missing connection status {key}")
    for key, parameters in {"progress": {"number", "total"}, "question_too_long": {"limit"}}.items():
        if set(re.findall(r"\{([a-z_]+)\}", content.get("ui", {}).get(key, ""))) != parameters:
            err(f"marcus: invalid placeholders in {key}")


def cross_checks(t: dict[str, dict]) -> None:
    _city_checks(t)
    _marcus_checks(t)
    _marcus_checks(t, "lucius.json")
    _advisor_checks(t)
    _patronage_checks(t)
    cultures = {c["id"] for c in t.get("cultures.json", {}).get("cultures", [])}
    factions = {f["id"]: f for f in t.get("factions.json", {}).get("factions", [])}

    # --- factions ---------------------------------------------------------
    for faction in factions.values():
        if faction["culture"] not in cultures:
            err(f"factions: {faction['id']}: unknown culture {faction['culture']}")
    if sum(1 for f in factions.values() if f.get("is_rebel")) != 1:
        err("factions: exactly one rebel faction required")
    if sum(1 for f in factions.values() if f.get("is_senate")) != 1:
        err("factions: exactly one senate faction required")

    # --- ai personas ------------------------------------------------------
    personas = {p["id"]: p for p in t.get("ai.json", {}).get("personas", [])}
    if "default" not in personas:
        err("ai: a persona with id 'default' is required (the engine's fallback)")
    referenced = set()
    for faction in factions.values():
        persona_id = faction.get("ai_persona")
        if persona_id is None:
            continue
        if persona_id not in personas:
            err(f"factions: {faction['id']}: unknown ai_persona {persona_id}")
        else:
            referenced.add(persona_id)
    for persona_id in personas:
        if persona_id != "default" and persona_id not in referenced:
            warn(f"ai: persona {persona_id} is referenced by no faction")

    # --- agents -----------------------------------------------------------
    agent_kinds = {a["id"]: a for a in t.get("agents.json", {}).get("agents", [])}
    for required_kind in ("diplomat", "spy", "assassin"):
        if required_kind not in agent_kinds:
            err(f"agents: kind {required_kind} missing (the engine expects all three)")


    # --- buildings + temples ---------------------------------------------
    chains: dict[str, dict] = {}
    level_ids: dict[str, str] = {}  # level id -> chain id
    for source in ("buildings.json", "temples.json"):
        for chain in t.get(source, {}).get("chains", []):
            if chain["id"] in chains:
                err(f"{source}: duplicate chain id {chain['id']}")
            chains[chain["id"]] = chain
            previous = -1
            for level in chain["levels"]:
                if level["id"] in level_ids:
                    err(f"{source}: duplicate building level id {level['id']}")
                level_ids[level["id"]] = chain["id"]
                rank = LEVELS.index(level["min_settlement_level"])
                if rank < previous:
                    err(f"{source}: {chain['id']}: min_settlement_level goes backwards at {level['id']}")
                previous = rank
            if source == "temples.json" and chain["kind"] != "temple":
                err(f"temples.json: {chain['id']}: kind must be temple")
            if chain["kind"] == "temple" and ("god" not in chain or "archetype" not in chain):
                err(f"{source}: {chain['id']}: temple chains need god and archetype")

    for culture in sorted(cultures):
        government = [c for c in chains.values()
                      if c["kind"] == "government" and culture in c["cultures"]]
        if len(government) != 1:
            err(f"buildings: culture {culture} needs exactly one government chain, has {len(government)}")
        else:
            tiers = len(government[0]["levels"])
            cap = next((c["max_settlement_level"] for c in
                        t.get("cultures.json", {}).get("cultures", []) if c["id"] == culture), None)
            if cap and tiers != LEVELS.index(cap) + 1:
                err(f"buildings: {culture} government chain has {tiers} tiers but culture cap is {cap} "
                    f"(needs {LEVELS.index(cap) + 1})")
        for kind in ("walls", "farms", "barracks", "armoury"):
            if not any(c["kind"] == kind and culture in c["cultures"] for c in chains.values()):
                if culture != "neutral":
                    warn(f"buildings: culture {culture} has no {kind} chain")

    # A chain's building prerequisite must be a kind every culture it serves can
    # actually raise to that tier — within its settlement cap — or the chain is
    # unbuildable for them; and a chain cannot require its own kind.
    caps = {c["id"]: c["max_settlement_level"] for c in t.get("cultures.json", {}).get("cultures", [])}

    def can_build(culture: str, kind: str, level: int) -> bool:
        cap = LEVELS.index(caps.get(culture, LEVELS[-1]))
        return any(c["kind"] == kind and culture in c["cultures"] and len(c["levels"]) >= level
                   and LEVELS.index(c["levels"][level - 1]["min_settlement_level"]) <= cap
                   for c in chains.values())

    for chain in chains.values():
        required = chain.get("requires_building")
        if not required:
            continue
        if required["kind"] == chain["kind"]:
            err(f"buildings: {chain['id']}: requires its own kind")
        for culture in chain["cultures"]:
            if not can_build(culture, required["kind"], required["level"]):
                err(f"buildings: {chain['id']}: requires {required['kind']} L{required['level']}, "
                    f"which culture {culture} can never build")
        for agent_kind in agent_kinds.values():
            satisfiable = any(
                c["kind"] == agent_kind["building_kind"]
                and len(c["levels"]) >= agent_kind["building_level"]
                and culture in c["cultures"]
                for c in chains.values())
            if not satisfiable and culture != "neutral":
                warn(f"agents: {agent_kind['id']} gate {agent_kind['building_kind']} "
                     f"L{agent_kind['building_level']} unsatisfiable for culture {culture}")

    # --- units ------------------------------------------------------------
    units = {u["id"]: u for u in t.get("units.json", {}).get("units", [])}
    for unit in units.values():
        if unit["culture"] not in cultures:
            err(f"units: {unit['id']}: unknown culture {unit['culture']}")
        for owner in unit["factions"]:
            if owner not in factions and owner not in ("all", "mercenary"):
                err(f"units: {unit['id']}: unknown faction {owner}")
        need = unit["requirements"]
        satisfiable = any(
            c["kind"] == need["building_kind"]
            and len(c["levels"]) >= need["building_level"]
            and (unit["culture"] in c["cultures"] or unit["factions"] == ["mercenary"])
            and (need.get("temple_god", "") in ("", c.get("god", "")))
            for c in chains.values())
        if not satisfiable:
            err(f"units: {unit['id']}: requirement {need['building_kind']} L{need['building_level']} "
                f"unsatisfiable for culture {unit['culture']}")
        if unit.get("era", "any") != "any" and unit["culture"] != "roman":
            warn(f"units: {unit['id']}: era gating on a non-roman unit")

    # --- unit classes -----------------------------------------------------
    # Every class and attribute the units schema admits needs a record (and
    # vice versa): the resolver reads the matrix for every unit it meets.
    units_schema = json.loads((SCHEMAS / "units.schema.json").read_text())
    unit_props = units_schema["properties"]["units"]["items"]["properties"]
    class_enum = set(unit_props["class"]["enum"])
    attribute_enum = set(unit_props["attributes"]["items"]["enum"])
    class_table = t.get("unit_classes.json", {})
    class_records = {c["id"]: c for c in class_table.get("classes", [])}
    attribute_records = {a["id"]: a for a in class_table.get("attributes", [])}
    for class_id in sorted(class_enum - set(class_records)):
        err(f"unit_classes: no record for unit class '{class_id}'")
    for class_id in sorted(set(class_records) - class_enum):
        err(f"unit_classes: class '{class_id}' is not in the units schema")
    for attribute_id in sorted(attribute_enum - set(attribute_records)):
        err(f"unit_classes: no record for unit attribute '{attribute_id}'")
    for attribute_id in sorted(set(attribute_records) - attribute_enum):
        err(f"unit_classes: attribute '{attribute_id}' is not in the units schema")
    if len(class_records) != len(class_table.get("classes", [])):
        err("unit_classes: duplicate class id")
    if len(attribute_records) != len(class_table.get("attributes", [])):
        err("unit_classes: duplicate attribute id")
    class_ids = sorted(class_records)
    for index, mine in enumerate(class_ids):
        matchups = class_records[mine].get("matchups", {})
        if mine in matchups:
            warn(f"unit_classes: {mine} lists a matchup against itself (ignored by the resolver)")
        for theirs in class_ids[index + 1:]:
            product = float(matchups.get(theirs, 1.0)) \
                * float(class_records[theirs].get("matchups", {}).get(mine, 1.0))
            if product < 0.85 or product > 1.15:
                warn(f"unit_classes: {mine} vs {theirs} matchups multiply to {product:.2f} "
                     f"(authoring band 0.85-1.15; the net counter is their ratio)")

    for faction_id, faction in factions.items():
        if faction.get("is_rebel"):
            continue
        recruitable = [u for u in units.values()
                       if faction_id in u["factions"] or "all" in u["factions"]]
        if len(recruitable) < 3:
            err(f"units: faction {faction_id} can recruit only {len(recruitable)} unit types")

    # --- techniques -------------------------------------------------------
    techniques = {}
    for technique in t.get("techniques.json", {}).get("techniques", []):
        if technique["id"] in techniques:
            err(f"techniques: duplicate id {technique['id']}")
        techniques[technique["id"]] = technique

    all_resources = set()
    all_hidden = set()
    for region in t.get("regions.json", {}).get("regions", []):
        all_resources.update(region.get("resources", []))
        all_hidden.update(region.get("hidden_resources", []))

    for technique in techniques.values():
        tid = technique["id"]
        for fid in technique["start_adopted"].get("factions", []):
            if fid not in factions:
                err(f"techniques: {tid}: unknown start_adopted faction {fid}")
        prereq = technique["prerequisites"]
        for dependency in prereq.get("techniques", []):
            if dependency not in techniques:
                err(f"techniques: {tid}: unknown prerequisite technique {dependency}")
        if prereq["resource"] and prereq["resource"] not in all_resources:
            err(f"techniques: {tid}: prerequisite resource {prereq['resource']} "
                f"appears in no region")
        if prereq["hidden_resource"] and prereq["hidden_resource"] not in all_hidden:
            err(f"techniques: {tid}: prerequisite hidden_resource "
                f"{prereq['hidden_resource']} appears in no region")

    # Prerequisite graph must be acyclic (DFS with colors).
    color = {}  # 0 unvisited, 1 in-stack, 2 done

    def visit(tid: str) -> bool:
        if color.get(tid, 0) == 1:
            return False
        if color.get(tid, 0) == 2:
            return True
        color[tid] = 1
        for dependency in techniques.get(tid, {}).get("prerequisites", {}).get("techniques", []):
            if dependency in techniques and not visit(dependency):
                err(f"techniques: prerequisite cycle through {tid} -> {dependency}")
                return False
        color[tid] = 2
        return True

    for tid in sorted(techniques):
        visit(tid)

    # Per-culture reachability: warn when a technique names a culture as
    # originator or starting holder whose building tree can never satisfy the
    # institution gate (history has holes, but authored ones should be meant).
    for technique in techniques.values():
        need_kind = technique["prerequisites"]["building_kind"]
        need_level = technique["prerequisites"]["building_level"]
        if not need_kind or need_level <= 0:
            continue
        for culture in set(technique["origin_cultures"]) | set(technique["start_adopted"]["cultures"]):
            satisfiable = any(
                c["kind"] == need_kind and len(c["levels"]) >= need_level
                and culture in c["cultures"]
                for c in chains.values())
            if not satisfiable and culture != "neutral":
                warn(f"techniques: {technique['id']}: culture {culture} is named as "
                     f"origin/holder but can never build {need_kind} L{need_level}")

    # Warcraft: a technique must DO something (flat effects or a war block); a
    # closed tradition names real courts and only they may start with it; the
    # war-record keys are sane; and a technique whose only effects name unit
    # classes a court never fields is a null purchase — which the AI will buy.
    war_tables = ("class_stats", "matchups", "terrain", "upkeep_pct", "recruit_xp")
    for technique in techniques.values():
        tid = technique["id"]
        war = technique.get("war", {})
        if not technique["effects"] and not war:
            err(f"techniques: {tid}: neither effects nor a war block — it does nothing")
        closed = technique.get("factions", [])
        for fid in closed:
            if fid not in factions:
                err(f"techniques: {tid}: unknown faction {fid} in its factions list")
        for fid in technique["start_adopted"].get("factions", []):
            if closed and fid not in closed:
                err(f"techniques: {tid}: {fid} starts with a tradition closed to it")
        if closed and technique["start_adopted"].get("cultures"):
            err(f"techniques: {tid}: a closed tradition cannot be a whole culture's endowment")
        prereq = technique["prerequisites"]
        if prereq.get("era") == "post_marian" and technique["start_adopted"].get("factions"):
            err(f"techniques: {tid}: starts adopted but needs the post-marian era")
        if war:
            targets = {entry["class"] for key in war_tables for entry in war.get(key, [])}
            if targets and "all" not in targets and not technique["effects"] and not war.get("fatigue_immune"):
                eligible = [fid for fid, f in sorted(factions.items())
                            if not f.get("is_rebel") and (not closed or fid in closed)
                            and (not technique["origin_cultures"] or f["culture"] in technique["origin_cultures"])]
                for fid in eligible:
                    fielded = {u["class"] for u in units.values() if fid in u["factions"] or "all" in u["factions"]}
                    if not targets & fielded:
                        warn(f"techniques: {tid}: {fid} may originate it but fields none of "
                             f"{sorted(targets)} (null purchase)")
    for culture in sorted(cultures):
        if culture == "neutral":
            continue
        count = sum(1 for tq in techniques.values()
                    if tq["domain"] == "warcraft" and (not tq["origin_cultures"] or culture in tq["origin_cultures"]))
        if count < 3:
            warn(f"techniques: culture {culture} has only {count} warcraft techniques to devise")

    # Every effect key the techniques schema admits must be read by some rules
    # module (a quoted literal in code, not a comment): a closed vocabulary must
    # not rot silently.
    readers = _reader_source()
    technique_effect_keys = _schema_effect_keys("techniques.schema.json", "techniques")
    for key in sorted(technique_effect_keys):
        if key in FORWARD_EFFECTS:
            continue
        if f'"{key}"' not in readers:
            err(f"techniques.schema.json: effect key '{key}' has no engine reader under src/core "
                f"(dead content — implement it or list it in FORWARD_EFFECTS)")
    building_effect_keys = _schema_effect_keys("buildings.schema.json", "chains", "levels")
    for key in sorted(building_effect_keys):
        if key in FORWARD_EFFECTS:
            continue
        if f'"{key}"' not in readers:
            err(f"buildings.schema.json: effect key '{key}' has no engine reader under src/core "
                f"(dead content — implement it or list it in FORWARD_EFFECTS)")
    for key in sorted(FORWARD_EFFECTS):
        if key not in technique_effect_keys | building_effect_keys:
            warn(f"validator: FORWARD_EFFECTS lists '{key}', which no schema admits")

    # requires_technique gates on units and building levels must resolve.
    for unit in units.values():
        gate = unit.get("requires_technique", "")
        if gate and gate not in techniques:
            err(f"units: {unit['id']}: unknown requires_technique {gate}")
    for chain in chains.values():
        for level in chain["levels"]:
            gate = level.get("requires_technique", "")
            if gate and gate not in techniques:
                err(f"buildings: {level['id']}: unknown requires_technique {gate}")

    # The edicts cross-checks that lived here belonged to the OTHER edicts
    # engine (prerequisites/tensions/decree-vs-standing). main kept the
    # provincial-edicts table instead, whose own checks run further down, so
    # these validated a shape data/edicts.json does not have.

    # --- epithets and annals ----------------------------------------------
    epithet_ids = set()
    for epithet in t.get("epithets.json", {}).get("epithets", []):
        if epithet["id"] in epithet_ids:
            err(f"epithets: duplicate id {epithet['id']}")
        epithet_ids.add(epithet["id"])

    # Annals templates: placeholders must be resolvable — subject names, the
    # date, or a detail key the engine actually writes for that kind.
    ANNALS_TOKENS = {
        "faction", "other_faction", "character", "region", "technique",
        "edict", "epithet", "office", "year", "season",
        # detail keys per the recording sites:
        "winner", "attacker_soldiers", "defender_soldiers", "occupation",
        "loot", "population", "assault", "turns", "battles",
        "cities_taken_a", "cities_taken_b", "age", "battles_won",
        "cities_taken", "techniques_completed", "edicts_enacted", "disaster",
        "index",
    }
    for kind, variants in t.get("annals.json", {}).get("templates", {}).items():
        for template in variants:
            for token in re.findall(r"\{([a-z_]+)\}", template):
                if token not in ANNALS_TOKENS:
                    err(f"annals: {kind}: unknown placeholder {{{token}}}")

    # Hidden resources must be referenced by SOMETHING (event or technique) —
    # and vice versa the events check below already validates its own refs.
    referenced_hidden = {technique["prerequisites"]["hidden_resource"]
                         for technique in techniques.values()
                         if technique["prerequisites"]["hidden_resource"]}
    for event in t.get("events.json", {}).get("events", []):
        hidden = event.get("trigger", {}).get("hidden_resource", "")
        if hidden:
            referenced_hidden.add(hidden)
            if hidden not in all_hidden:
                err(f"events: {event['id']}: hidden_resource {hidden} appears in no region")
    for hidden in sorted(all_hidden - referenced_hidden):
        warn(f"regions: hidden resource {hidden} is referenced by no event or technique")

    # Repeatable events must rest (a cooldown-less once:false event would fire
    # every single turn its condition holds), and scripted technique grants
    # must name real crafts.
    for event in t.get("events.json", {}).get("events", []):
        if event.get("once", True) is False and "cooldown_turns" not in event:
            err(f"events: {event['id']}: once:false requires cooldown_turns")
        granted = event.get("effects", {}).get("grant_technique", "")
        if granted and granted not in techniques:
            err(f"events: {event['id']}: unknown grant_technique {granted}")
        target = event.get("trigger", {}).get("faction", "")
        if target and target not in factions:
            err(f"events: {event['id']}: unknown trigger faction {target}")

    # --- regions ----------------------------------------------------------
    regions = {r["id"]: r for r in t.get("regions.json", {}).get("regions", [])}
    zones = {z["id"]: z for z in t.get("regions.json", {}).get("sea_zones", [])}
    for region in regions.values():
        for neighbor in region["adjacent"]:
            if neighbor == region["id"]:
                err(f"regions: {region['id']} adjacent to itself")
            elif neighbor not in regions:
                err(f"regions: {region['id']}: unknown neighbor {neighbor}")
            elif region["id"] not in regions[neighbor]["adjacent"]:
                err(f"regions: adjacency not symmetric: {region['id']} -> {neighbor}")
        for zone in region.get("sea_zones", []):
            if zone not in zones:
                err(f"regions: {region['id']}: unknown sea zone {zone}")
    for zone in zones.values():
        for neighbor in zone["adjacent"]:
            if neighbor == zone["id"]:
                err(f"sea_zones: {zone['id']} adjacent to itself")
            elif neighbor not in zones:
                err(f"sea_zones: {zone['id']}: unknown neighbor {neighbor}")
            elif zone["id"] not in zones[neighbor]["adjacent"]:
                err(f"sea_zones: adjacency not symmetric: {zone['id']} -> {neighbor}")

    if regions:
        # Connectivity over land adjacency + shared sea zones.
        reachable = set()
        frontier = [next(iter(regions))]
        zone_members: dict[str, list[str]] = {}
        for region in regions.values():
            for zone in region.get("sea_zones", []):
                zone_members.setdefault(zone, []).append(region["id"])
        zone_links = {z["id"]: z["adjacent"] for z in zones.values()}
        while frontier:
            current = frontier.pop()
            if current in reachable:
                continue
            reachable.add(current)
            frontier.extend(regions[current]["adjacent"])
            for zone in regions[current].get("sea_zones", []):
                for linked_zone in [zone, *zone_links.get(zone, [])]:
                    frontier.extend(zone_members.get(linked_zone, []))
        unreachable = set(regions) - reachable
        if unreachable:
            err(f"regions: unreachable from {next(iter(regions))}: {sorted(unreachable)[:10]}")

    waterways = t.get("waterways.json", {})
    water_nodes = set(zones)
    for node in waterways.get("river_nodes", []):
        if node["id"] in water_nodes:
            err(f"waterways: duplicate node {node['id']}")
        water_nodes.add(node["id"])
        for region in node["regions"]:
            if region not in regions:
                err(f"waterways: unknown landing region {region}")
    water_edges = set()
    for link in waterways.get("links", []):
        key = tuple(sorted([link["a"], link["b"]]))
        if link["a"] not in water_nodes or link["b"] not in water_nodes or link["a"] == link["b"] or key in water_edges:
            err(f"waterways: invalid or duplicate link {key}")
        water_edges.add(key)
    for zone in zones.values():
        for other in zone["adjacent"]:
            if tuple(sorted([zone["id"], other])) not in water_edges:
                err(f"waterways: sea lane missing distance {zone['id']} / {other}")
    for unit in [waterways.get("transport_template"), *waterways.get("shallow_templates", [])]:
        if unit not in units or units[unit].get("class") != "ship":
            err(f"waterways: unknown ship template {unit}")

    # --- map positions ----------------------------------------------------
    for region in regions.values():
        position = region.get("position")
        if not position:
            continue  # schema already errors; avoid cascading
        for other in regions.values():
            if other["id"] <= region["id"] or not other.get("position"):
                continue
            dx = position["x"] - other["position"]["x"]
            dy = position["y"] - other["position"]["y"]
            distance = (dx * dx + dy * dy) ** 0.5
            if distance < 1.2:
                err(f"regions: {region['id']} and {other['id']} overlap on the map "
                    f"(distance {distance:.2f})")
            elif other["id"] in region["adjacent"] and distance > 35:
                warn(f"regions: adjacent {region['id']} and {other['id']} are far apart "
                     f"on the map (distance {distance:.1f})")

    # --- map geometry -----------------------------------------------------
    geometry = t.get("map_geometry.json", {})
    if geometry and regions:
        cells = {c["region"]: c for c in geometry.get("cells", [])}
        for region_id in cells:
            if region_id not in regions:
                err(f"map_geometry: cell for unknown region {region_id}")
        for region_id in regions:
            if region_id not in cells:
                err(f"map_geometry: region {region_id} has no cell")
        if len(cells) != len(geometry.get("cells", [])):
            err("map_geometry: duplicate region cells")

        def point_in_ring(x: float, y: float, ring: list) -> bool:
            inside = False
            for i in range(len(ring)):
                x1, y1 = ring[i]
                x2, y2 = ring[(i + 1) % len(ring)]
                if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                    inside = not inside
            return inside

        def ring_area(ring: list) -> float:
            total = 0.0
            for i in range(len(ring)):
                x1, y1 = ring[i]
                x2, y2 = ring[(i + 1) % len(ring)]
                total += x1 * y2 - x2 * y1
            return abs(total) / 2.0

        for region_id, cell in cells.items():
            if region_id not in regions:
                continue
            position = regions[region_id]["position"]
            if not any(point_in_ring(position["x"], position["y"], ring)
                       for ring in cell["polygons"]):
                err(f"map_geometry: {region_id}'s position lies outside its own territory")
            if sum(ring_area(ring) for ring in cell["polygons"]) < 0.5:
                warn(f"map_geometry: {region_id}'s territory is degenerately small")

        adjacent_pairs = {tuple(sorted((r["id"], n)))
                          for r in regions.values() for n in r["adjacent"] if n in regions}
        edge_pairs = []
        for edge in geometry.get("edges", []):
            pair = (edge["a"], edge["b"])
            edge_pairs.append(pair)
            if edge["a"] >= edge["b"]:
                err(f"map_geometry: edge {pair} not ordered a < b")
            if pair not in adjacent_pairs:
                err(f"map_geometry: edge {pair} joins regions that are not adjacent")
            else:
                for end, region_id in ((edge["path"][0], edge["a"]), (edge["path"][-1], edge["b"])):
                    position = regions[region_id]["position"]
                    dx, dy = end[0] - position["x"], end[1] - position["y"]
                    if (dx * dx + dy * dy) ** 0.5 > 1.5:
                        err(f"map_geometry: edge {pair} does not end at {region_id}'s position")
        if len(edge_pairs) != len(set(edge_pairs)):
            err("map_geometry: duplicate edges")
        for pair in sorted(adjacent_pairs - set(edge_pairs)):
            err(f"map_geometry: adjacent pair {pair} has no road edge")

    # --- wonders ----------------------------------------------------------
    wonders = {w["id"]: w for w in t.get("wonders.json", {}).get("wonders", [])}
    for wonder in wonders.values():
        if wonder["region"] not in regions:
            err(f"wonders: {wonder['id']}: unknown region {wonder['region']}")
        elif regions[wonder["region"]].get("wonder") != wonder["id"]:
            err(f"wonders: {wonder['id']}: region {wonder['region']} does not back-reference it")
    for region in regions.values():
        if "wonder" in region and region["wonder"] not in wonders:
            err(f"regions: {region['id']}: unknown wonder {region['wonder']}")

    # --- campaign ---------------------------------------------------------
    campaign = t.get("campaign.json", {})
    settled: dict[str, str] = {}
    character_ids: set[str] = set()
    campaign_factions = {f["id"] for f in campaign.get("factions", [])}
    for faction in factions.values():
        if faction.get("is_rebel"):
            continue
        if faction["id"] not in campaign_factions:
            err(f"campaign: faction {faction['id']} missing from start state")
    for faction_id in campaign_factions:
        if faction_id not in factions:
            err(f"campaign: unknown faction {faction_id}")

    balance = t.get("balance.json", {})
    thresholds = {e["id"]: e["min_population"] for e in balance.get("settlement_levels", [])}

    def check_settlement(setup: dict, owner: str) -> None:
        region_id = setup["region"]
        if region_id not in regions:
            err(f"campaign: settlement in unknown region {region_id}")
            return
        if region_id in settled:
            err(f"campaign: region {region_id} settled twice ({settled[region_id]} and {owner})")
        settled[region_id] = owner
        owner_culture = factions.get(owner, {}).get("culture")
        seen_chains: set[str] = set()
        tier_by_kind: dict[str, int] = {}
        government_tier = 0
        for level_id in setup.get("buildings", []):
            if level_id not in level_ids:
                err(f"campaign: {region_id}: unknown building level {level_id}")
                continue
            chain = chains[level_ids[level_id]]
            if chain["id"] in seen_chains:
                err(f"campaign: {region_id}: two levels of chain {chain['id']}")
            seen_chains.add(chain["id"])
            tier = next(i for i, lv in enumerate(chain["levels"], 1) if lv["id"] == level_id)
            tier_by_kind[chain["kind"]] = max(tier_by_kind.get(chain["kind"], 0), tier)
            if chain["kind"] == "government":
                government_tier = tier
                if owner_culture not in chain["cultures"]:
                    warn(f"campaign: {region_id}: government building is foreign to {owner}")
            if chain.get("requires_coastal") and not regions[region_id].get("sea_zones"):
                err(f"campaign: {region_id}: {level_id} requires a coast")
            resource = chain.get("requires_resource")
            if resource and resource not in regions[region_id].get("resources", []):
                err(f"campaign: {region_id}: {level_id} requires resource {resource}")
        for chain_id in sorted(seen_chains):
            required = chains[chain_id].get("requires_building")
            if required and tier_by_kind.get(required["kind"], 0) < required["level"]:
                err(f"campaign: {region_id}: {chain_id} needs {required['kind']} L{required['level']} at start")
        if government_tier == 0:
            err(f"campaign: {region_id}: no government building at start")
        else:
            needed = thresholds.get(LEVELS[government_tier - 1], 0)
            if setup["population"] < needed:
                err(f"campaign: {region_id}: population {setup['population']} below its tier "
                    f"threshold {needed}")
        for unit in setup.get("garrison", []):
            check_unit_instance(unit, owner, region_id, "garrison")
        harbour = setup.get("harbour", [])
        if harbour and not regions[region_id].get("sea_zones"):
            err(f"campaign: {region_id}: a harbour on a landlocked region")
        for unit in harbour:
            check_unit_instance(unit, owner, region_id, "harbour")

    def check_unit_instance(instance: dict, owner: str, where: str, slot: str = "army") -> None:
        template = units.get(instance["template"])
        if template is None:
            err(f"campaign: {where}: unknown unit template {instance['template']}")
            return
        if owner != "rebels" and owner not in template["factions"] and "all" not in template["factions"]:
            warn(f"campaign: {where}: {owner} holds foreign unit {instance['template']}")
        # Ships wait in harbours and sail in fleets; they never stand on walls
        # or march in a column (ForceRules refuses the transfers at runtime).
        is_ship = template.get("class") == "ship"
        if slot in ("garrison", "army") and is_ship:
            err(f"campaign: {where}: ship {instance['template']} in a {slot} — ships belong in a harbour or a fleet")
        if slot in ("harbour", "fleet") and not is_ship:
            err(f"campaign: {where}: {instance['template']} is not a ship and cannot be in a {slot}")

    for faction_setup in campaign.get("factions", []):
        fid = faction_setup["id"]
        own_regions = {s["region"] for s in faction_setup.get("settlements", [])}
        if faction_setup["capital"] not in own_regions:
            err(f"campaign: {fid}: capital {faction_setup['capital']} is not an owned settlement")
        for setup in faction_setup.get("settlements", []):
            check_settlement(setup, fid)
        for army in faction_setup.get("armies", []):
            if army["region"] not in regions:
                err(f"campaign: {fid}: army in unknown region {army['region']}")
            for unit in army["units"]:
                check_unit_instance(unit, fid, army["region"], "army")
        for fleet in faction_setup.get("fleets", []):
            if fleet["sea_zone"] not in zones:
                err(f"campaign: {fid}: fleet in unknown sea zone {fleet['sea_zone']}")
            elif not any(fleet["sea_zone"] in r.get("sea_zones", []) for r in regions.values()):
                err(f"campaign: {fid}: fleet in sea zone {fleet['sea_zone']} that touches no coast")
            for ship in fleet["ships"]:
                check_unit_instance(ship, fid, fleet["sea_zone"], "fleet")
        roles = [c["role"] for c in faction_setup.get("characters", [])]
        if factions.get(fid, {}).get("is_rebel") is not True and roles.count("leader") != 1:
            err(f"campaign: {fid}: needs exactly one leader, has {roles.count('leader')}")
        if roles.count("heir") > 1:
            err(f"campaign: {fid}: more than one heir")
        come_of_age = int(balance.get("characters", {}).get("come_of_age", 16))
        females = 0
        for character in faction_setup.get("characters", []):
            if character["id"] in character_ids:
                err(f"campaign: duplicate character id {character['id']}")
            character_ids.add(character["id"])
            location = character.get("location", "")
            if location and location not in regions:
                err(f"campaign: character {character['id']}: unknown location {location}")
            gender = character.get("gender", "female" if character["role"] == "spouse" else "male")
            if gender == "female":
                females += 1
            # Only BOYS must be re-roled by coming of age: the engine keeps
            # daughters as role "child" past 16 until a suitor marries in, so a
            # seeded 16-17-year-old marriageable daughter is legal data.
            if character["role"] == "child" and gender == "male" \
                    and int(character["age"]) >= come_of_age:
                err(f"campaign: character {character['id']}: a boy of {character['age']} "
                    f"is past coming of age ({come_of_age}) — seed him as 'family'")
            if character["role"] == "spouse" and gender == "male":
                warn(f"campaign: character {character['id']}: a male spouse will confuse "
                     f"the family tree (marriage brings husbands in as 'family')")
            if character["role"] in ("leader", "heir") and gender == "female":
                err(f"campaign: character {character['id']}: a female {character['role']} "
                    f"breaks succession (the engine only seats adult men)")
            location = character.get("location", "")
            if location and location in regions and location not in own_regions:
                err(f"campaign: character {character['id']}: stands in {location}, "
                    f"which {fid} does not hold at start")
        known = {c["id"]: c for c in faction_setup.get("characters", [])}
        for character in faction_setup.get("characters", []):
            father = character.get("father")
            if father and father not in known:
                err(f"campaign: character {character['id']}: unknown father {father}")
            elif father and int(known[father]["age"]) - int(character["age"]) < 16:
                err(f"campaign: character {character['id']}: father {father} is only "
                    f"{int(known[father]['age']) - int(character['age'])} years older")
        if faction_setup.get("characters", []) and females == 0:
            warn(f"campaign: {fid}: a house seeded with no women bootstraps its "
                 f"family tree very slowly")
        for army in faction_setup.get("armies", []):
            general = army.get("general")
            if general and general not in known:
                err(f"campaign: {fid}: army general {general} not in the family")
        for entry in faction_setup.get("diplomacy", []):
            if entry["faction"] not in factions:
                err(f"campaign: {fid}: diplomacy with unknown faction {entry['faction']}")

    for setup in campaign.get("rebel_settlements", []):
        check_settlement(setup, "rebels")
    for army in campaign.get("rebel_armies", []):
        if army["region"] not in regions:
            err(f"campaign: rebel army in unknown region {army['region']}")
        for unit in army["units"]:
            check_unit_instance(unit, "rebels", army["region"])

    unsettled = set(regions) - set(settled)
    if unsettled:
        err(f"campaign: regions with no settlement: {sorted(unsettled)[:10]}"
            + (f" (+{len(unsettled) - 10} more)" if len(unsettled) > 10 else ""))

    # --- win conditions ---------------------------------------------------
    seen_conditions: set[tuple[str, str]] = set()
    for condition in t.get("win_conditions.json", {}).get("conditions", []):
        key = (condition["faction"], condition["campaign"])
        if key in seen_conditions:
            err(f"win_conditions: duplicate for {key}")
        seen_conditions.add(key)
        if condition["faction"] not in factions:
            err(f"win_conditions: unknown faction {condition['faction']}")
        for region_id in condition.get("must_hold_regions", []):
            if region_id not in regions:
                err(f"win_conditions: unknown region {region_id}")
        for faction_id in condition.get("outlive_factions", []):
            if faction_id not in factions:
                err(f"win_conditions: unknown faction to outlive {faction_id}")
    for faction_id, faction in factions.items():
        if faction["playable"] in ("playable", "unlockable"):
            for mode in ("long", "short"):
                if (faction_id, mode) not in seen_conditions:
                    err(f"win_conditions: {faction_id} missing {mode} campaign goals")

    # --- events / missions / mercenaries / names / traits ----------------
    for event in t.get("events.json", {}).get("events", []):
        for region_id in event.get("trigger", {}).get("exclude_regions", []):
            if region_id not in regions:
                err(f"events: {event['id']}: unknown region {region_id}")
    for disaster in t.get("events.json", {}).get("disasters", []):
        for region_id in disaster["regions"]:
            if region_id not in regions:
                err(f"events: {disaster['id']}: unknown region {region_id}")

    # --- offices (the cursus honorum) ------------------------------------
    offices = t.get("offices.json", {}).get("offices", [])
    office_ids: set[str] = set()
    office_ranks: dict[int, str] = {}
    for office in offices:
        if office["id"] in office_ids:
            err(f"offices: duplicate id {office['id']}")
        office_ids.add(office["id"])
        if office["rank"] in office_ranks:
            err(f"offices: {office['id']}: rank {office['rank']} is already "
                f"{office_ranks[office['rank']]}'s — the ladder needs a strict order")
        office_ranks[office["rank"]] = office["id"]
        if not str(office.get("historical_basis", "")).strip():
            err(f"offices: {office['id']}: historical_basis is required — invented history is a bug")
    if offices and sorted(office_ranks) != list(range(1, len(offices) + 1)):
        err("offices: ranks must run 1..N without gaps")
    for office in offices:
        needs = int(office.get("requires_prior_rank", 0))
        if needs and (needs not in office_ranks or needs >= int(office["rank"])):
            err(f"offices: {office['id']}: requires_prior_rank {needs} must name a "
                f"lower existing rank")
        if not office.get("effects"):
            err(f"offices: {office['id']}: an office that buys nothing is not an office")
    if offices and not any(int(o.get("requires_prior_rank", 0)) == 0 for o in offices):
        err("offices: no office is open without a prior rank — the ladder has no first rung")
    min_rank = int(t.get("balance.json", {}).get("senate", {}).get("annals_office_min_rank", 1))
    if offices and not 1 <= min_rank <= len(offices):
        err(f"offices: balance.senate.annals_office_min_rank {min_rank} names no rank on the ladder")
    eponymous = [o["id"] for o in offices if o.get("eponymous", False)]
    if offices and len(eponymous) != 1:
        err(f"offices: exactly one office names the year (eponymous); found {eponymous}")

    for mission in t.get("missions.json", {}).get("missions", []):
        for unit_reward in mission.get("reward", {}).get("units", []):
            if unit_reward["template"] not in units:
                err(f"missions: {mission['id']}: unknown unit {unit_reward['template']}")

    for pool in t.get("mercenaries.json", {}).get("pools", []):
        for region_id in pool["regions"]:
            if region_id not in regions:
                err(f"mercenaries: {pool['id']}: unknown region {region_id}")
        for entry in pool["units"]:
            if entry["template"] not in units:
                err(f"mercenaries: {pool['id']}: unknown unit {entry['template']}")

    pools = t.get("names.json", {}).get("pools", {})
    for culture in cultures:
        if culture != "neutral" and culture not in pools:
            err(f"names: no name pool for culture {culture}")

    trait_defs = {tr["id"]: tr for tr in t.get("traits.json", {}).get("traits", [])}
    for trait in trait_defs.values():
        anti = trait.get("anti_trait")
        if anti and anti not in trait_defs:
            err(f"traits: {trait['id']}: unknown anti_trait {anti}")

    # Trigger kinds the engine actually fires. Anything else is dead content,
    # so a warning names it rather than letting it rot silently.
    fired_kinds = set()
    engine_dir = ROOT / "src" / "core"
    for source in engine_dir.rglob("*.gd"):
        text = source.read_text()
        for kind in ("turn_end_governing", "turn_end_idle", "turn_end_campaigning",
                     "battle_won", "battle_lost", "siege_won", "settlement_captured",
                     "settlement_exterminated", "settlement_enslaved", "office_gained",
                     "came_of_age"):
            if f'"{kind}"' in text:
                fired_kinds.add(kind)
    for source_name, key in (("traits.json", "traits"), ("ancillaries.json", "ancillaries")):
        for entry in t.get(source_name, {}).get(key, []):
            for trigger in entry.get("triggers", []):
                if trigger["when"] in fired_kinds or trigger["when"] in FORWARD_TRIGGERS:
                    continue
                warn(f"{source_name}: {entry['id']}: trigger '{trigger['when']}' is never "
                     f"fired by any engine call site (dead content)")

    # Same discipline for mission kinds: every kind must either be issued by an
    # engine call site or be explicitly forward-authored.
    issued_kinds = set()
    for source in engine_dir.rglob("*.gd"):
        text = source.read_text()
        for kind in ("take_region", "make_alliance", "reach_trade_agreement",
                     "assassinate_leader", "blockade_port", "leader_suicide"):
            if f'"{kind}"' in text:
                issued_kinds.add(kind)
    for mission in t.get("missions.json", {}).get("missions", []):
        if mission["kind"] not in issued_kinds and mission["kind"] not in FORWARD_MISSIONS:
            warn(f"missions: {mission['id']}: kind '{mission['kind']}' is never "
                 f"issued by any engine call site (dead content)")
    for faction_setup in campaign.get("factions", []):
        for character in faction_setup.get("characters", []):
            for trait_id in character.get("traits", []):
                if trait_id not in trait_defs:
                    err(f"campaign: character {character['id']}: unknown trait {trait_id}")

    # --- glossary ---------------------------------------------------------
    # The UI's vocabulary must cover exactly what the data uses: a missing
    # entry shows the player a raw id; an unused entry is dead content.
    glossary = t.get("glossary.json", {})
    used_by_section = {
        "unit_classes": {u["class"] for u in units.values()},
        "attributes": {a for u in units.values() for a in u.get("attributes", [])},
        "effects": {k for c in chains.values() for lv in c["levels"] for k in lv.get("effects", {})},
        "building_kinds": {c["kind"] for c in chains.values()},
    }
    for section, used in used_by_section.items():
        entries = [e["id"] for e in glossary.get(section, [])]
        for duplicate in sorted({e for e in entries if entries.count(e) > 1}):
            err(f"glossary: {section}: duplicate entry '{duplicate}'")
        for missing in sorted(used - set(entries)):
            err(f"glossary: {section}: '{missing}' is used in the data but has no entry")
        for dead in sorted(set(entries) - used):
            warn(f"glossary: {section}: entry '{dead}' matches nothing in the data (dead content)")
    # --- society, advances, and effect-key liveness -------------------------
    KINDS = {chain["kind"] for chain in chains.values()}
    society = t.get("society.json", {})
    patterns = {p["id"] for p in society.get("patterns", [])}
    axis_ids = {a["id"] for a in society.get("axes", [])}
    # The axes table is what the UI names; it must describe the stocks that exist.
    ENGINE_STOCKS = {"legitimacy", "grievance", "assimilation", "expectation",
                     "elite_pressure", "martial_ethos", "knowledge", "spoils"}
    for missing in sorted(ENGINE_STOCKS - axis_ids):
        err(f"society: no axis entry for the engine stock '{missing}'")
    for extra in sorted(axis_ids - ENGINE_STOCKS):
        err(f"society: axis '{extra}' does not correspond to any engine stock")

    advance_ids: set[str] = set()
    for advance in t.get("advances.json", {}).get("advances", []):
        if advance["id"] in advance_ids:
            err(f"advances: duplicate id {advance['id']}")
        advance_ids.add(advance["id"])
        culture = advance.get("culture")
        if culture and culture not in cultures:
            err(f"advances: {advance['id']}: unknown culture {culture}")
    # Every culture must be able to reach a first advance, or Craft is inert for it.
    for culture in sorted(cultures):
        reachable = [a for a in t.get("advances.json", {}).get("advances", [])
                     if a.get("culture", culture) == culture]
        if not reachable:
            err(f"advances: culture {culture} can reach no advance at all")

    edict_ids: set[str] = set()
    for edict in t.get("edicts.json", {}).get("edicts", []):
        if edict["id"] in edict_ids:
            err(f"edicts: duplicate id {edict['id']}")
        edict_ids.add(edict["id"])
        if edict["min_settlement_level"] not in LEVELS:
            err(f"edicts: {edict['id']}: unknown settlement level {edict['min_settlement_level']}")
        kind = edict.get("requires_building_kind")
        if kind and kind not in KINDS:
            err(f"edicts: {edict['id']}: unknown building kind {kind}")
        for culture in edict.get("cultures", []):
            if culture not in cultures:
                err(f"edicts: {edict['id']}: unknown culture {culture}")
        pattern = edict.get("pattern")
        if pattern and pattern not in patterns:
            err(f"edicts: {edict['id']}: unknown society pattern {pattern}")
        # The whole premise of this layer is that everything trades. An edict
        # with no cost at all is a free good and does not belong here.
        effects = edict.get("effects", {})
        costly_when_negative = ("civic", "law", "growth", "health", "trade_pct", "income_pct")
        costly_when_positive = ("burden", "coercion", "elite_pressure")
        pays = (edict.get("upkeep_per_1000_pop", 0) > 0
                or any(effects.get(k, 0) < 0 for k in costly_when_negative)
                or any(effects.get(k, 0) > 0 for k in costly_when_positive))
        if not pays:
            err(f"edicts: {edict['id']} costs nothing — every edict must trade "
                f"something, in denarii or in one of the societal stocks")
    # A village must have at least one order available to it, or the lever does
    # not exist for a player who has just lost everything but one province.
    if not any(e["min_settlement_level"] == "village"
               for e in t.get("edicts.json", {}).get("edicts", [])):
        err("edicts: no edict is available at village level — the fast lever "
            "disappears exactly when a player most needs one")

    for event in t.get("events.json", {}).get("events", []):
        pattern = event.get("pattern")
        if pattern and pattern not in patterns:
            err(f"events: {event['id']}: unknown society pattern {pattern}")
        trigger = event.get("trigger", {})
        if trigger.get("condition") == "society_stat":
            if not trigger.get("stat"):
                err(f"events: {event['id']}: society_stat trigger needs a 'stat'")
            if "min" not in trigger and "max" not in trigger:
                err(f"events: {event['id']}: society_stat trigger needs a 'min' or a 'max'")
            if not event.get("pattern"):
                warn(f"events: {event['id']}: a society-driven event with no 'pattern' "
                     f"teaches the player nothing about what just happened")

    # Every effect key the data authors must have an engine reader. This is the
    # check that would have caught weapon_upgrade and armor_upgrade sitting dead
    # in 34 building levels across two phases.
    authored_effects = set()
    for source in ("buildings.json", "temples.json"):
        for chain in t.get(source, {}).get("chains", []):
            for level in chain.get("levels", []):
                authored_effects.update(level.get("effects", {}))
    engine_text = "\n".join(source.read_text() for source in (ROOT / "src").rglob("*.gd"))
    for effect in sorted(authored_effects):
        if f'"{effect}"' not in engine_text:
            err(f"buildings: effect key '{effect}' is authored in the data but no "
                f"engine code reads it (dead content)")
    for effect in sorted(a for adv in t.get("advances.json", {}).get("advances", [])
                         for a in adv.get("effects", {})):
        if f'"{effect}"' not in engine_text:
            err(f"advances: effect key '{effect}' is authored but no engine code reads it")
    for effect in sorted(e for edict in t.get("edicts.json", {}).get("edicts", [])
                         for e in edict.get("effects", {})):
        if f'"{effect}"' not in engine_text:
            err(f"edicts: effect key '{effect}' is authored but no engine code reads it")
    route = t.get("campaign_terrain.json", {}).get("development_route", {})
    route_regions = route.get("regions", [])
    for unit in route.get("contact_units", []):
        if unit["template"] not in units:
            err(f"campaign route: unknown contact unit {unit['template']}")
    for region in route_regions + [route.get("contact_region", "")]:
        if region not in regions:
            err(f"campaign route: unknown region {region}")
    for faction in route.get("peace_with", []) + [route.get("player", ""), route.get("contact_owner", ""), route.get("map_grantor", "")]:
        if faction not in factions:
            err(f"campaign route: unknown faction {faction}")
    for a, b in zip(route_regions, route_regions[1:]):
        if b not in regions.get(a, {}).get("adjacent", []):
            err(f"campaign route: non-adjacent leg {a}/{b}")
        for crossing in t.get("campaign_terrain.json", {}).get("crossings", []):
            if {a, b} == {crossing["a"], crossing["b"]} and crossing["kind"] in {"river", "ridge", "water"}:
                err(f"campaign route: impassable leg {a}/{b}")

    # --- dispatch: prose and engine must name the same beats ---------------
    dispatch = t.get("dispatch.json", {})
    chapter_ids = {c["id"] for c in dispatch.get("chapters", [])}
    beats = {b["id"]: b for b in dispatch.get("beats", [])}
    if len(beats) != len(dispatch.get("beats", [])):
        err("dispatch: duplicate beat id")

    engine_kinds = _journal_kinds()
    if engine_kinds is None:
        err("dispatch: could not read KINDS from src/core/turn_journal.gd")
    else:
        for kind in sorted(engine_kinds - set(beats)):
            err(f"dispatch: the engine emits {kind} but no beat template says what to print")
        for kind in sorted(set(beats) - engine_kinds):
            err(f"dispatch: {kind} has prose but no engine call site emits it (dead content)")

    for beat_id, beat in sorted(beats.items()):
        if beat["chapter"] not in chapter_ids:
            err(f"dispatch: {beat_id}: unknown chapter {beat['chapter']}")
        if not beat["in_sequence"] and not beat["in_dispatch"]:
            err(f"dispatch: {beat_id}: shown in neither the sequence nor the dispatch")
        for field in ("headline", "body"):
            for token in re.findall(r"\{([a-z_]*)\}", beat[field]):
                if token not in DISPATCH_TOKENS:
                    err(f"dispatch: {beat_id}: {field} uses unknown token {{{token}}}")

    # --- missions: every kind is either judged or knowingly deferred -------
    for mission in t.get("missions.json", {}).get("missions", []):
        kind = mission["kind"]
        if kind not in LIVE_MISSION_KINDS and kind not in FORWARD_MISSION_KINDS:
            err(f"missions: {mission['id']}: kind {kind} is neither judged by "
                f"SenateRules nor listed in FORWARD_MISSION_KINDS as content "
                f"authored ahead of the system that will resolve it")
    # Development art references are public templates, never live enemy rosters.
    terrain_routes = t.get("campaign_terrain.json", {})
    region_defs = {r["id"]: r for r in t["regions.json"]["regions"]}
    seen_crossings = set()
    for crossing in terrain_routes.get("crossings", []):
        a, b = crossing["a"], crossing["b"]
        key = tuple(sorted((a, b)))
        if key in seen_crossings:
            err(f"campaign_terrain: duplicate crossing {a}/{b}")
        seen_crossings.add(key)
        if a not in region_defs or b not in region_defs or b not in region_defs.get(a, {}).get("adjacent", []):
            err(f"campaign_terrain: crossing must join adjacent regions: {a}/{b}")
    study = t.get("realism_study.json", {})
    if study.get("friendly_template") not in units:
        err("realism_study: unknown friendly template")
    culture_ids = {c["id"] for c in t.get("cultures.json", {}).get("cultures", [])}
    if study.get("opposing_culture") not in culture_ids:
        err("realism_study: unknown opposing culture")
    camera_ids = [c["id"] for c in study.get("cameras", [])]
    if set(camera_ids) != {"overview", "column", "woods", "pass"} or len(camera_ids) != 4:
        err("realism_study: camera presets must each occur once")
    half_extent = study.get("extent", 0) / 2
    for route in ["route", "flank_route"]:
        for point in study.get(route, []):
            if any(abs(value) > half_extent for value in point):
                err(f"realism_study: {route} leaves the terrain extent")

    # --- sites ------------------------------------------------------------
    built_kinds = {c["kind"] for c in chains.values()}
    all_faction_templates = {u["id"] for u in t.get("units.json", {}).get("units", [])
                             if "all" in u.get("factions", [])}

    def check_reward_units(reward: dict, label: str) -> None:
        for grant in reward.get("units", []):
            if grant["template"] not in units:
                err(f"{label}: unknown unit {grant['template']}")
            elif grant["template"] not in all_faction_templates:
                err(f"{label}: unit {grant['template']} is not an all-faction template "
                    f"(the player can be any faction)")

    site_ids: set[str] = set()
    site_regions: set[str] = set()
    for site in t.get("sites.json", {}).get("sites", []):
        if site["id"] in site_ids:
            err(f"sites: duplicate id {site['id']}")
        site_ids.add(site["id"])
        if site["region"] not in regions:
            err(f"sites: {site['id']}: unknown region {site['region']}")
        if site["region"] in site_regions:
            err(f"sites: {site['id']}: region {site['region']} already has a site")
        site_regions.add(site["region"])
        for outcome in site["outcomes"]:
            check_reward_units(outcome.get("reward", {}), f"sites: {site['id']}")

    # --- guided campaign --------------------------------------------------
    stages = t.get("guided_campaign.json", {}).get("stages", [])
    stage_ids: set[str] = set()
    for stage in stages:
        if stage["id"] in stage_ids:
            err(f"guided_campaign: duplicate stage id {stage['id']}")
        stage_ids.add(stage["id"])
    starts: list[str] = []
    reachable: set[str] = set()
    roman_only_ids = {s["id"] for s in stages if s["trigger"].get("roman_only")}
    for stage in stages:
        sid = stage["id"]
        trigger = stage["trigger"]
        if trigger["kind"] == "after":
            if not trigger.get("stages"):
                err(f"guided_campaign: {sid}: 'after' trigger needs a stages list")
        elif "stages" in trigger:
            err(f"guided_campaign: {sid}: trigger.stages only belongs on kind 'after'")
        if trigger["kind"] == "start":
            starts.append(sid)
            reachable.add(sid)
        for ref in trigger.get("stages", []) + trigger.get("requires", []):
            if ref not in stage_ids:
                err(f"guided_campaign: {sid}: unknown stage reference {ref}")
            elif ref == sid:
                err(f"guided_campaign: {sid}: references itself — it can never open")
            elif ref in roman_only_ids and not trigger.get("roman_only"):
                warn(f"guided_campaign: {sid}: gated behind roman-only stage {ref} "
                     f"but is not roman_only itself — dead for every other faction")
        if stage.get("repeatable"):
            if "cooldown_turns" not in stage:
                err(f"guided_campaign: {sid}: repeatable stages need cooldown_turns")
            if stage.get("reward", {}).get("boon"):
                err(f"guided_campaign: {sid}: repeatable stages must not grant boons "
                    f"(permanent bonuses would stack forever)")
        elif "cooldown_turns" in stage:
            err(f"guided_campaign: {sid}: cooldown_turns without repeatable is dead data")
        for objective in stage["objectives"]:
            if objective["kind"] == "treasury_at_least":
                if "amount" not in objective:
                    err(f"guided_campaign: {sid}: treasury_at_least needs an amount")
            elif "amount" in objective:
                err(f"guided_campaign: {sid}: 'amount' only belongs on treasury_at_least "
                    f"(counted objectives use 'count')")
            if objective["kind"] == "no_siege_on_target" \
                    and trigger["kind"] != "player_settlement_besieged":
                err(f"guided_campaign: {sid}: no_siege_on_target only works on "
                    f"player_settlement_besieged stages (it needs the recorded target)")
            kind_ref = objective.get("building_kind")
            if kind_ref is not None:
                if objective["kind"] != "queue_building":
                    err(f"guided_campaign: {sid}: building_kind only belongs on queue_building")
                elif kind_ref not in built_kinds:
                    err(f"guided_campaign: {sid}: unknown building kind {kind_ref}")
        check_reward_units(stage.get("reward", {}), f"guided_campaign: {sid}")
    if stages and not starts:
        err("guided_campaign: no stage with a 'start' trigger — the trail can never begin")
    # Every 'after' stage must be reachable from a start stage.
    grew = True
    while grew:
        grew = False
        for stage in stages:
            sid = stage["id"]
            if sid in reachable or stage["trigger"]["kind"] != "after":
                continue
            if all(parent in reachable for parent in stage["trigger"].get("stages", [])):
                reachable.add(sid)
                grew = True
    for stage in stages:
        if stage["trigger"]["kind"] == "after" and stage["id"] not in reachable:
            err(f"guided_campaign: {stage['id']}: unreachable from any start stage")

    # --- effects glossary -------------------------------------------------
    # The drawer may only describe effects the data actually uses, and may only
    # claim an effect works if some engine call site reads it. Both halves are
    # checked here; the runtime twin lives in tests/test_building_info.gd.
    glossary = t.get("effects_glossary.json", {})
    described = {row["key"]: row for row in glossary.get("effects", [])}
    used_effects: set[str] = set()
    for chain in chains.values():
        for level in chain["levels"]:
            used_effects.update(level.get("effects", {}))
    for key in sorted(used_effects):
        if key not in described:
            err(f"effects_glossary: no wording for effect '{key}', which the data uses")
    for key, row in described.items():
        if key not in used_effects:
            warn(f"effects_glossary: '{key}' is described but no building grants it")
        if row["status"] == "inert" and not row.get("note"):
            err(f"effects_glossary: inert effect '{key}' must carry a note")
    # Aggregation has to mirror the engine, or the drawer sums what the engine maxes.
    # (weapon/armor upgrades are summed across a town's forges and armouries
    # since the military layer — see RecruitmentRules.upgrade_level.)
    max_aggregated = {"recruit_xp", "wall_level", "road_level", "port_level"}
    for key, row in described.items():
        expected = "max" if key in max_aggregated else "sum"
        if row["aggregation"] != expected:
            err(f"effects_glossary: '{key}' is aggregated as {row['aggregation']}, "
                f"but SettlementRules treats it as {expected}")
    heading_ids = {h["id"] for h in glossary.get("headings", [])}
    for key, row in described.items():
        if row["heading"] not in heading_ids:
            err(f"effects_glossary: '{key}' files under unknown heading '{row['heading']}'")
        for derived in row.get("derived", []):
            if derived["heading"] not in heading_ids:
                err(f"effects_glossary: derived '{derived['id']}' files under "
                    f"unknown heading '{derived['heading']}'")
    # Every blocker ConstructionRules can emit needs a sentence.
    blocker_kinds = {b["kind"] for b in glossary.get("blockers", [])}
    for kind in ("culture", "settlement", "population", "coastal", "resource",
                 "temple", "queued", "predecessor", "culture_cap",
                 "already_built", "no_such_tier", "requires_building"):
        if kind not in blocker_kinds:
            err(f"effects_glossary: no sentence for the '{kind}' blocker")
    for message in knowledge_wording_errors(glossary.get("knowledge", {})):
        err(message)
    for note in glossary.get("kind_notes", []):
        if note["kind"] not in built_kinds:
            err(f"effects_glossary: kind_note names unknown building kind '{note['kind']}'")

    # --- building art -----------------------------------------------------
    # The game ships no images, so every level must reach a recipe or it draws
    # nothing. The schema closes the part vocabulary; these checks close the
    # cross-file references the schema cannot see.
    art = t.get("building_art.json", {})
    art_materials = set(art.get("materials", {}))
    art_fragments = set(art.get("fragments", {}))

    def walk_parts(container):
        for part in container.get("base", []):
            yield part
        for tier in container.get("tiers", []):
            for part in tier.get("add", []):
                yield part
        for part in container.get("add", []):
            yield part

    def check_material(name, where):
        if name and name not in ("$track",) and name not in art_materials:
            err(f"building_art: {where}: unknown material '{name}'")

    recipe_ids: set[str] = set()
    generic = 0
    for recipe in art.get("recipes", []):
        rid = recipe["id"]
        if rid in recipe_ids:
            err(f"building_art: duplicate recipe id '{rid}'")
        recipe_ids.add(rid)
        if rid == "generic":
            generic += 1
        for chain_id in recipe.get("chains", []):
            if chain_id not in chains:
                err(f"building_art: {rid}: unknown chain '{chain_id}'")
        for kind in recipe.get("kinds", []):
            if kind not in built_kinds:
                err(f"building_art: {rid}: unknown building kind '{kind}'")
        for culture in recipe.get("cultures", []):
            if culture not in cultures:
                err(f"building_art: {rid}: unknown culture '{culture}'")
        check_material(recipe.get("scene", {}).get("ground_mat"), f"{rid}: scene")
        for tier in recipe.get("tiers", []):
            check_material(tier.get("material"), f"{rid}: tier material")
            for name in tier.get("set", {}):
                check_material(tier["set"][name].get("mat"), f"{rid}: set {name}")
        for part in walk_parts(recipe):
            check_material(part.get("mat"), f"{rid}: part {part.get('part', part.get('use'))}")
            if "use" in part and part["use"] not in art_fragments:
                err(f"building_art: {rid}: unknown fragment '{part['use']}'")
    if generic != 1:
        err("building_art: exactly one recipe with id 'generic' is required, "
            "or an unrecipe'd level draws nothing")
    for archetype, cult in art.get("cults", {}).items():
        for part in walk_parts(cult):
            check_material(part.get("mat"), f"building_art: cult {archetype}")
    for culture in sorted(cultures):
        lane = art.get("tracks", {}).get(culture, [])
        if len(lane) != 6:
            err(f"building_art: tracks.{culture} needs one material per tier (6)")
        for material in lane:
            check_material(material, f"tracks.{culture}")

    # Coverage: resolve every chain the way BuildingArt.recipe_for does.
    by_chain = {c: r for r in art.get("recipes", []) for c in r.get("chains", [])}
    by_kind_culture, by_kind = {}, {}
    for recipe in art.get("recipes", []):
        for kind in recipe.get("kinds", []):
            if recipe.get("cultures"):
                for culture in recipe["cultures"]:
                    by_kind_culture[(kind, culture)] = recipe
            else:
                by_kind[kind] = recipe
    for chain in chains.values():
        for culture in chain["cultures"]:
            picked = (by_chain.get(chain["id"])
                      or by_kind_culture.get((chain["kind"], culture))
                      or by_kind.get(chain["kind"]))
            if picked is None:
                err(f"building_art: no recipe reaches {chain['id']} as {culture}")
            elif len(picked.get("tiers", [])) < len(chain["levels"]):
                warn(f"building_art: {picked['id']} gives {len(picked.get('tiers', []))} tiers "
                     f"for {chain['id']}'s {len(chain['levels'])} levels — the top ones repeat")
    for chain_id in art.get("emblems", {}):
        if chain_id not in chains:
            err(f"building_art: emblem for unknown chain '{chain_id}'")
        elif chains[chain_id]["kind"] != "temple":
            err(f"building_art: emblem on non-temple chain '{chain_id}'")

    # --- unit art ---------------------------------------------------------
    # Class and culture are orthogonal, so the roster is covered by two small
    # tables. Anything they miss would draw nothing at all.
    unit_art = t.get("unit_art.json", {})
    commander_ids = [c["id"] for c in unit_art.get("commanders", [])]
    if set(commander_ids) != set(factions) or len(commander_ids) != len(set(commander_ids)):
        errors.append("unit_art.json: commanders must dress every faction exactly once")
    class_ids = {c["id"] for c in unit_art.get("classes", [])}
    kit_ids = {k["id"] for k in unit_art.get("kits", [])}
    cue_ids = set(unit_art.get("attributes", {}))
    for unit in units.values():
        if unit["class"] not in class_ids:
            err(f"unit_art: no template for the {unit['class']} class "
                f"(needed by {unit['id']})")
        if unit["culture"] not in kit_ids:
            err(f"unit_art: no kit for {unit['culture']} troops (needed by {unit['id']})")
        for attribute in unit.get("attributes", []):
            if attribute not in cue_ids:
                err(f"unit_art: the '{attribute}' attribute has no visual cue "
                    f"(needed by {unit['id']})")
    for override in unit_art.get("units", []):
        if override["id"] not in units:
            err(f"unit_art: signature for unknown unit '{override['id']}'")
    for cue in cue_ids:
        if not any(cue in unit.get("attributes", []) for unit in units.values()):
            warn(f"unit_art: the '{cue}' cue is authored but no unit carries it")

    # --- balance sanity ---------------------------------------------------
    ordered = [e["min_population"] for e in balance.get("settlement_levels", [])]
    if ordered != sorted(ordered):
        err("balance: settlement level thresholds must be ascending")

    # The stack cap has one home (balance.recruitment.army_unit_cap) and the
    # campaign schema's maxItems must agree with it, or authored armies and
    # fleets could exceed the rule the engine enforces. Garrisons and harbours
    # are uncapped, like a city's walls.
    army_cap = balance.get("recruitment", {}).get("army_unit_cap")
    if army_cap is None:
        err("balance: recruitment.army_unit_cap missing")
    campaign_schema = json.loads((SCHEMAS / "campaign.schema.json").read_text(encoding="utf-8"))
    defs = campaign_schema.get("$defs", {})
    for def_name, field in (("army", "units"), ("fleet", "ships")):
        schema_cap = defs.get(def_name, {}).get("properties", {}).get(field, {}).get("maxItems")
        if schema_cap != army_cap:
            err(f"balance: recruitment.army_unit_cap ({army_cap}) disagrees with "
                f"campaign.schema.json $defs.{def_name}.{field}.maxItems ({schema_cap})")
    forces = balance.get("forces", {})
    if "disband_population_return_pct" not in forces:
        err("balance: forces.disband_population_return_pct missing")
    elif not 0 <= float(forces["disband_population_return_pct"]) <= 100:
        err("balance: forces.disband_population_return_pct must be within 0-100")
    for table_name in ("build_priority", "frontier_build_bonus"):
        for kind in balance.get("ai", {}).get(table_name, {}):
            if kind not in built_kinds:
                err(f"balance: ai.{table_name} names unknown building kind '{kind}'")

    # Terrain tables must cover the terrain enum exactly: movement.gd indexes
    # terrain_cost directly, so a missing key is a runtime crash, and an extra
    # key in either table is dead data.
    regions_schema = json.loads((SCHEMAS / "regions.schema.json").read_text())
    terrain_enum = set(
        regions_schema["properties"]["regions"]["items"]["properties"]["terrain"]["enum"])
    for section, table_key in (("movement", "terrain_cost"),
                               ("battle", "terrain_defense_multiplier")):
        keys = set(balance.get(section, {}).get(table_key, {}))
        for missing in sorted(terrain_enum - keys):
            err(f"balance: {section}.{table_key} missing terrain '{missing}'")
        for extra in sorted(keys - terrain_enum):
            err(f"balance: {section}.{table_key} has unknown terrain '{extra}'")

    # The round-log tables are indexed per phase by AutoResolver.ROUND_PHASES
    # (skirmish/charge/melee/break/pursuit — 5 entries): a short array is a
    # runtime crash, a long one dead data. Casualty shares must be sane
    # slices summing to 1, the loser's morale must fall monotonically and
    # zero exactly at the break (index 3 — the phase the log pins the break
    # to), and the two winner-morale scalars are hard-indexed by the engine.
    round_phase_count = 5
    break_phase_index = 3
    battle = balance.get("battle", {})
    for table_key in ("round_winner_casualty_shares", "round_loser_casualty_shares",
                      "round_loser_morale_track", "round_winner_morale_progress"):
        entries = battle.get(table_key, [])
        if len(entries) != round_phase_count:
            err(f"balance: battle.{table_key} needs exactly {round_phase_count} "
                f"entries (one per battle round phase), has {len(entries)}")
    for table_key in ("round_winner_casualty_shares", "round_loser_casualty_shares"):
        entries = battle.get(table_key, [])
        total = sum(entries)
        if abs(total - 1.0) > 0.001:
            err(f"balance: battle.{table_key} must sum to 1.0, sums to {total}")
        if any(not 0.0 <= float(v) <= 1.0 for v in entries):
            err(f"balance: battle.{table_key} entries must sit in [0, 1] — "
                "a phase can neither heal men nor spend more than the whole battle")
    track = battle.get("round_loser_morale_track", [])
    if any(not 0.0 <= float(v) <= 100.0 for v in track):
        err("balance: battle.round_loser_morale_track entries must sit in [0, 100]")
    if any(track[i] < track[i + 1] for i in range(len(track) - 1)):
        err("balance: battle.round_loser_morale_track must never rise — the loser is losing")
    if len(track) == round_phase_count and track[break_phase_index] != 0:
        err("balance: battle.round_loser_morale_track must hit exactly 0 at the "
            f"break phase (index {break_phase_index}) — the log names the break there")
    progress = battle.get("round_winner_morale_progress", [])
    if any(not 0.0 <= float(v) <= 1.0 for v in progress):
        err("balance: battle.round_winner_morale_progress entries must sit in [0, 1]")
    for scalar_key in ("round_winner_morale_min", "round_winner_morale_max"):
        if scalar_key not in battle:
            err(f"balance: battle.{scalar_key} is missing — the first battle of "
                "any campaign would crash on it")
    if battle.get("round_winner_morale_min", 0) > battle.get("round_winner_morale_max", 100):
        err("balance: battle.round_winner_morale_min must not exceed round_winner_morale_max")
    society_rules = balance.get("society", {})
    # Hysteresis is the point: a province must not settle the moment it ignites.
    for ignite, extinguish in (("restive_ignite", "restive_extinguish"),
                               ("revolt_ignite", "revolt_extinguish")):
        if society_rules.get(ignite, 0) <= society_rules.get(extinguish, 0):
            err(f"balance: society.{ignite} must be above society.{extinguish} — "
                f"without the gap there is no hysteresis and a crisis simply "
                f"reverses when its cause does")
    if society_rules.get("restive_ignite", 0) >= society_rules.get("revolt_ignite", 0):
        err("balance: society.restive_ignite must be below society.revolt_ignite")
    if society_rules.get("grievance_relief_rate", 0) >= society_rules.get("grievance_charge_rate", 0):
        warn("balance: grievance relieves at least as fast as it charges, so "
             "accumulated resentment costs the player nothing to undo")
    for advance in t.get("advances.json", {}).get("advances", []):
        if advance["knowledge_threshold"] > society_rules.get("knowledge_max", 100):
            err(f"advances: {advance['id']} threshold is above society.knowledge_max "
                f"and can never be reached")


def _city_battle_checks(t: dict[str, dict], city: dict) -> None:
    """Tactical routes share the visible district's streets and gate aperture."""
    battle = city.get("battle", {})
    nodes = {node["id"]: node for node in battle.get("nodes", [])}
    if len(nodes) != len(battle.get("nodes", [])):
        err("roma battle: duplicate node id")
    words = t.get("effects_glossary.json", {}).get("city_battle", {})
    for key in ("attacker_entry", "defender_entry", "objective"):
        if battle.get(key) not in nodes:
            err(f"roma battle: {key} references an unknown node")
    if sum(node.get("role") == "gate" for node in nodes.values()) != 1:
        err("roma battle: exactly one gate is required")
    if nodes.get(battle.get("objective"), {}).get("role") != "objective":
        err("roma battle: objective must reference the objective node")
    for node_id in battle.get("deployment_nodes", []):
        if node_id not in nodes or nodes[node_id].get("role") in ("approach", "gate"):
            err(f"roma battle: invalid defender deployment node {node_id}")
    if battle.get("defender_entry") not in battle.get("deployment_nodes", []):
        err("roma battle: defender entry must allow deployment")
    units = {unit["id"]: unit for unit in t.get("units.json", {}).get("units", [])}
    realtime = t.get("balance.json", {}).get("city_battle", {}).get("realtime", {})
    specialists = t.get("balance.json", {}).get("city_battle", {}).get("specialists", {})
    tactics = t.get("balance.json", {}).get("city_battle", {}).get("tactics", {})
    for template in tactics.get("drill_units", []):
        if template not in units:
            err(f"roma tactics: unknown drill template {template}")
    if any(tactics.get(clock, 0) % realtime.get("tick_ms", 100) for clock in ("reform_ms", "ai_reform_cooldown_ms")):
        err("roma tactics: formation clock must match tick quantum")
    if tactics.get("rear_dot", 0) >= tactics.get("front_dot", 0):
        err("roma tactics: rear and front arcs must be ordered")
    if tactics.get("frontage_min_cm", 0) >= tactics.get("frontage_max_cm", 0):
        err("roma tactics: invalid frontage limits")
    if tactics.get("phalanx_experience", 0) > t.get("balance.json", {}).get("recruitment", {}).get("experience_max", 0):
        err("roma tactics: unreachable phalanx training")
    if not any(tactics.get("phalanx_attribute") in u.get("attributes", []) for u in units.values()):
        err("roma tactics: missing phalanx-capable unit")
    for key in ("split", "line", "column", "phalanx", "face", "assault_line", "tactics_help", "split_help", "phalanx_help", "column_help"):
        if key not in words:
            err(f"roma tactics: missing prose {key}")
    escort_limit = t.get("balance.json", {}).get("recruitment", {}).get("city_escort_limit", 0)
    if not isinstance(escort_limit, int) or escort_limit < 1:
        err("roma specialists: city_escort_limit must be a positive integer")
    for unit in units.values():
        if unit.get("class") == "general_bodyguard" and unit.get("city_recruit_only") and unit.get("cost", 0) <= 0:
            err(f"roma specialists: city escort {unit['id']} must have a recruitment cost")
    for template in specialists.get("templates", {}):
        if template not in units:
            err(f"roma specialists: unknown template {template}")
    for unit_class in specialists.get("classes", {}):
        if unit_class not in realtime.get("roles", {}):
            err(f"roma specialists: unknown class {unit_class}")
    for ability, profile in specialists.get("profiles", {}).items():
        for key in ("specialty_", "ability_"):
            if key + ability not in words:
                err(f"roma specialists: missing prose {key + ability}")
        if "ability_" + ability + "_help" not in words:
            err(f"roma specialists: missing ability help {ability}")
        if profile["duration_ms"] >= profile["cooldown_ms"]:
            err(f"roma specialists: {ability} needs recovery after its duration")
        for clock in ("duration_ms", "cooldown_ms"):
            if profile[clock] % realtime.get("tick_ms", 100):
                err(f"roma specialists: {ability} {clock} must match the tick quantum")
    roles = realtime.get("roles", {})
    for unit in units.values():
        if unit.get("class") not in roles:
            err(f"roma battle: missing tactical role for {unit.get('class')}")
    if realtime.get("beats") != {"archer": "cavalry", "cavalry": "soldier", "soldier": "archer"}:
        err("roma battle: tactical counter cycle must remain archers > cavalry > soldiers > archers")
    spatial = battle.get("spatial", {})
    objective = nodes.get(battle.get("objective"), {}).get("position", [])
    if spatial.get("objective_cm") != [round(v*100) for v in objective]:
        err("roma battle: spatial objective must match the displayed Forum objective")
    if spatial.get("gate_cm") != [0, round(city.get("walls", {}).get("half_extent", 0)*100)]:
        err("roma battle: spatial gate must match the actual wall opening")
    if 1000 % realtime.get("tick_ms", 100) != 0:
        err("roma battle: tick quantum must divide a second exactly")
    for role in ("soldier", "archer", "cavalry"):
        if "role_" + role not in words or role not in realtime.get("profiles", {}):
            err(f"roma battle: missing profile or role prose for {role}")
    for unit_id in battle.get("practice_attackers", []):
        if unit_id not in units or units[unit_id].get("class") == "ship":
            err(f"roma battle: invalid practice unit {unit_id}")
    extent = float(city.get("extent", 0)) / 2
    wall = float(city.get("walls", {}).get("half_extent", 0))
    gate_half_width = float(city.get("walls", {}).get("gate_width", 0)) / 2
    for node_id, node in nodes.items():
        if "node_" + node_id not in words:
            err(f"roma battle: missing node prose node_{node_id}")
        if any(abs(value) > extent for value in node["position"]):
            err(f"roma battle: node {node_id} outside district")
        for neighbor_id in node["neighbors"]:
            neighbor = nodes.get(neighbor_id)
            if neighbor is None or neighbor_id == node_id:
                err(f"roma battle: invalid edge {node_id} to {neighbor_id}")
                continue
            if node_id not in neighbor["neighbors"]:
                err(f"roma battle: edge {node_id} to {neighbor_id} is not bidirectional")
            # Sample the complete route, with a metre of formation clearance,
            # against the actual authored houses; endpoints alone miss corners.
            a, b = node["position"], neighbor["position"]
            samples = max(1, int(((b[0]-a[0])**2 + (b[1]-a[1])**2)**0.5 * 2))
            for i in range(samples + 1):
                point = [a[axis] + (b[axis]-a[axis])*i/samples for axis in (0, 1)]
                if abs(point[0]) >= wall - 1.2 or point[1] <= -wall + 1.2 or (point[1] >= wall - 1.2 and abs(point[0]) >= gate_half_width - 1):
                    err(f"roma battle: edge {node_id} to {neighbor_id} crosses a solid wall")
                    break
                if any(all(abs(point[axis]-building["position"][axis]) < building["size"][axis]/2 + 1 for axis in (0, 1)) for building in city.get("buildings", [])):
                    err(f"roma battle: edge {node_id} to {neighbor_id} intersects a building")
                    break
                fountain = city.get("water_position", [0, 0])
                if (point[0]-fountain[0])**2 + (point[1]-fountain[1])**2 < 16:
                    err(f"roma battle: edge {node_id} to {neighbor_id} intersects the fountain")
                    break
    seen, frontier = set(), [battle.get("attacker_entry")]
    while frontier:
        node_id = frontier.pop()
        if node_id in seen or node_id not in nodes:
            continue
        seen.add(node_id)
        frontier.extend(nodes[node_id]["neighbors"])
    if seen != set(nodes):
        err("roma battle: tactical graph must be connected")


def _city_checks(t: dict[str, dict]) -> None:
    """The walkable district and civic rules share region/site and prose IDs."""
    city = t.get("roma_city.json", {})
    _city_battle_checks(t, city)
    governance = t.get("city_governance.json", {})
    rules = t.get("balance.json", {}).get("city", {})
    words = t.get("effects_glossary.json", {}).get("city_view", {})
    region_ids = {r["id"] for r in t.get("regions.json", {}).get("regions", [])}
    if city.get("region") not in region_ids:
        err(f"roma city: unknown region {city.get('region')}")
    for region in governance.get("regions", []):
        if region not in region_ids:
            err(f"city governance: unknown region {region}")
        if region != city.get("region"):
            err(f"city governance: region {region} has no walkable city geometry")
    site_ids = {site["id"] for site in city.get("sites", [])}
    for collection in ("sites", "buildings", "roads", "citizen_routes", "people_anchors"):
        ids = [item["id"] for item in city.get(collection, [])]
        if len(ids) != len(set(ids)):
            err(f"roma city: duplicate {collection} id")
    actions = governance.get("actions", [])
    action_ids = {a["id"] for a in actions}
    if len(action_ids) != len(actions):
        err("city governance: duplicate action id")
    for site in city.get("sites", []):
        for field in ("name_key", "description_key"):
            if site[field] not in words:
                err(f"roma city: {site['id']} has no city_view prose for {site[field]}")
    projects = set()
    for action in actions:
        aid = action["id"]
        if action["site"] not in site_ids:
            err(f"city governance: {aid} references unknown site {action['site']}")
        for prefix in ("action_", "help_"):
            if prefix + aid not in words:
                err(f"city governance: {aid} has no city_view prose {prefix + aid}")
        kind = action["kind"]
        if kind == "project":
            projects.add(aid)
        elif kind == "policy":
            vocabulary = {"patrols": {"normal", "heavy"}, "taverns": {"open", "closed"},
                          "workforce": {"normal", "paid", "requisition"}}
            policy = action.get("policy", "")
            if action.get("value") not in vocabulary.get(policy, set()):
                err(f"city governance: {aid} has invalid policy/value")
        elif kind == "tax" and action.get("value") not in rules.get("daily_cost_by_tax", {}):
            err(f"city governance: {aid} has an unsupported tax level")
    if action_ids != set(rules.get("action_costs", {})):
        err("city governance: every action needs exactly one balance cost")
    if projects != set(rules.get("project_days", {})):
        err("city governance: project ids and balance project_days disagree")
    for table in ("project_maintenance", "project_effects"):
        if projects != set(rules.get(table, {})):
            err(f"city governance: project ids and balance {table} disagree")
    profiles = governance.get("building_profiles", [])
    profile_sites = [profile["site"] for profile in profiles]
    if len(profile_sites) != len(set(profile_sites)) or set(profile_sites) != site_ids:
        err("city governance: every site needs exactly one building profile")
    profile_projects = [profile["project"] for profile in profiles]
    programs = set(governance.get("military_programs", []))
    defenses = set(governance.get("defense_projects", []))
    if len(profile_projects) != len(set(profile_projects)) or set(profile_projects) | programs | defenses != projects or set(profile_projects) & programs or defenses & (programs | set(profile_projects)):
        err("city governance: every project needs exactly one building profile or military programme")
    inspection_ids = set()
    for point in governance.get("defense_inspections", []):
        if point["id"] in inspection_ids:
            err("city governance: duplicate defense inspection")
        inspection_ids.add(point["id"])
        if not set(point["projects"]) <= projects:
            err("city governance: inspection references unknown project")
        for key in ("defense_" + point["id"], "defense_" + point["id"] + "_help"):
            if key not in words:
                err(f"city governance: missing inspection prose {key}")
    if programs != set(rules.get("project_military_effects", {})):
        err("city governance: military programmes and balance effects disagree")
    for kind in ("project_completed", "relief_expired", "troops_trained", "troops_equipped", "program_paused"):
        if "event_" + kind not in words:
            err(f"city governance: daily event has no city_view prose event_{kind}")
    for policy in rules.get("workforce_rate", {}):
        if "factor_workforce_" + policy not in words:
            err(f"city governance: workforce flow has no city_view prose factor_workforce_{policy}")
    action_by_id = {action["id"]: action for action in actions}
    for action in actions:
        prerequisite = action.get("requires_project")
        if prerequisite is not None and (prerequisite not in projects or prerequisite == action["id"]):
            err(f"city governance: {action['id']} has invalid project prerequisite")
        visited = {action["id"]}
        while prerequisite in action_by_id:
            if prerequisite in visited:
                err(f"city governance: {action['id']} has a cyclic project prerequisite")
                break
            visited.add(prerequisite)
            prerequisite = action_by_id[prerequisite].get("requires_project")
    for profile in profiles:
        project_id = profile["project"]
        if action_by_id.get(project_id, {}).get("site") != profile["site"]:
            err(f"city governance: {project_id} building profile belongs to the wrong site")
        for key in profile["stages"].values():
            if key not in words:
                err(f"city governance: building stage has no city_view prose {key}")
    for project_id in projects:
        for prefix in ("project_", "factor_"):
            if prefix + project_id not in words:
                err(f"city governance: project has no city_view prose {prefix + project_id}")
        if rules.get("action_costs", {}).get(project_id, 0) <= 0:
            err(f"city governance: {project_id} requires a paid construction cost")
        if rules.get("project_maintenance", {}).get(project_id, 0) <= 0:
            err(f"city governance: {project_id} requires recurring maintenance")
        effects = rules.get("project_effects", {}).get(project_id, {})
        if not any(value != 0 for value in effects.values()):
            err(f"city governance: {project_id} must have a readable civic effect")
    if not (0 < rules.get("restive_threshold", 0) < rules.get("rebellious_threshold", 0) <= 100):
        err("city governance: mood thresholds must increase within 0–100")
    for metric in ("cleanliness", "street_condition"):
        initial, complete = rules.get("initial_" + metric, 0), rules.get("completed_" + metric, 0)
        if not 0 <= initial < complete <= 100:
            err(f"city governance: {metric} must improve within 0–100")
    extent = float(city.get("extent", 0)) / 2
    def check_point(point: list, location: str) -> None:
        if any(abs(float(value)) > extent for value in point):
            err(f"roma city: {location} outside district bounds")
    for site in city.get("sites", []):
        check_point(site["position"], f"site {site['id']}")
        check_point(site["approach"], f"site approach {site['id']}")
    spawn = city.get("spawn", [0, 0, 0])
    check_point([spawn[0], spawn[2]], "spawn")
    for building in city.get("buildings", []):
        if any(float(size) <= 0 for size in building["size"]):
            err(f"roma city: {building['id']} has a non-positive footprint")
        if building["enterable"] and float(building["door_width"]) >= float(building["size"][0]):
            err(f"roma city: {building['id']} door is wider than its facade")
        for sx, sz in ((-1, -1), (1, 1)):
            check_point([building["position"][0] + sx * building["size"][0] / 2,
                         building["position"][1] + sz * building["size"][1] / 2],
                        f"building {building['id']} footprint")
    for collection in ("roads", "citizen_routes"):
        for path in city.get(collection, []):
            for index, point in enumerate(path["points"]):
                check_point(point, f"{path['id']} waypoint {index}")
            for a, b in zip(path["points"], path["points"][1:]):
                if a == b:
                    err(f"roma city: {path['id']} has a zero-length waypoint segment")
    for anchor in city.get("people_anchors", []):
        check_point(anchor["position"], f"people anchor {anchor['id']}")
    for collection in ("trees", "market_stalls", "rubbish", "repair_areas"):
        for index, point in enumerate(city.get(collection, [])):
            check_point(point, f"{collection} {index}")
    check_point(city.get("water_position", [0, 0]), "water position")


def main() -> int:
    global LIVE_MISSION_KINDS
    LIVE_MISSION_KINDS = _live_mission_kinds()
    tables = load_tables()
    if not errors:
        cross_checks(tables)
    for message in warnings:
        print(f"WARN  {message}")
    for message in errors:
        print(f"ERROR {message}")
    # balance.json is sections of constants, not entities — keep it out of the
    # entity summary (its "agents" section would otherwise miscount).
    counts = {name: (0 if name == "balance.json" else _entity_count(doc))
              for name, doc in tables.items()}
    summary = ", ".join(f"{name.removesuffix('.json')}={count}" for name, count in counts.items() if count)
    print(f"\n{len(errors)} errors, {len(warnings)} warnings [{summary}]")
    return 1 if errors else 0


def knowledge_wording_errors(wording: dict) -> list[str]:
    """Keep the knowledge panel's templates aligned with its actual inputs."""
    required_tokens = {
        "tradition": {"factions"},
        "building": {"building_kind", "level", "have"},
        "resource": {"resource"}, "hidden_resource": {"resource"},
        "coastal": set(), "technique": {"name"}, "era": {"era"},
        "battles_won": {"needs", "battles", "have"},
        "battles_lost": {"needs", "battles", "have"},
        "faced": {"needs", "battles", "unit_class", "have"},
    }
    found: list[str] = []
    source = (ROOT / "src/core/rules/knowledge.gd").read_text()
    emitted = set(re.findall(r'blockers\.append\(\{"kind": "([a-z_]+)"', source))
    templates = wording.get("blockers", {})
    if set(templates) != emitted or set(required_tokens) != emitted:
        found.append("effects_glossary: knowledge wording must cover exactly the emitted blocker kinds")
    fields = {"wants": {"requirements"}, "none": set(), "separator": set(),
              "unknown": set(), "battle_one": set(), "battle_many": set()}
    for key, expected in list(fields.items()) + list(required_tokens.items()):
        line = str((wording if key in fields else templates).get(key, ""))
        tokens = set(re.findall(r"\{([a-z_]+)\}", line))
        remainder = re.sub(r"\{[a-z_]+\}", "", line)
        if tokens != expected or "{" in remainder or "}" in remainder:
            found.append(f"effects_glossary: knowledge '{key}' must use exactly {sorted(expected)} tokens")
    return found


def _reader_source() -> str:
    """Every GDScript under src/core with comment lines removed, so a quoted
    effect key counts as read only where code actually reads it."""
    text = "\n".join(path.read_text() for path in sorted((ROOT / "src" / "core").rglob("*.gd")))
    return "\n".join(line for line in text.splitlines() if not line.strip().startswith("#"))


def _schema_effect_keys(schema_name: str, *array_path: str) -> set[str]:
    """Keys of the `effects` object reached by descending the given array properties."""
    node = json.loads((SCHEMAS / schema_name).read_text())
    for name in array_path:
        node = node["properties"][name]["items"]
    return set(node["properties"]["effects"]["properties"])


def _journal_kinds() -> set[str] | None:
    """The beat kinds the engine can emit, read straight out of TurnJournal so
    the prose table can never drift from the code that fills it."""
    source = ROOT / "src" / "core" / "turn_journal.gd"
    if not source.exists():
        return None
    match = re.search(r"const KINDS[^=]*=\s*\[(.*?)\]", source.read_text(), re.S)
    if not match:
        return None
    return set(re.findall(r'"([a-z_]+)"', match.group(1)))


def _live_mission_kinds() -> set[str]:
    """LIVE_KINDS from SenateRules — the kinds it actually judges."""
    source = ROOT / "src" / "core" / "rules" / "senate.gd"
    match = re.search(r"const LIVE_KINDS[^=]*=\s*\[(.*?)\]", source.read_text(), re.S)
    return set(re.findall(r'"([a-z_]+)"', match.group(1))) if match else set()


def _entity_count(document: dict) -> int:
    # The glossary is four parallel sections; every other table has one list.
    if "unit_classes" in document:
        return sum(len(document.get(key, [])) for key in
                   ("unit_classes", "attributes", "effects", "building_kinds"))
    for key in ("actions", "cultures", "factions", "chains", "units", "classes", "regions",
                "traits", "ancillaries", "events", "wonders", "missions",
                "conditions", "pools", "cells", "advances", "axes",
                "edicts", "sites", "stages", "effects", "recipes",
                "personas", "agents", "techniques", "epithets", "offices",
                "templates"):
        if key in document:
            return len(document[key])
    return len(document.get("beats", []))


if __name__ == "__main__":
    sys.exit(main())
