#!/usr/bin/env python3
"""Validate every data table against its JSON Schema, then cross-check the
references JSON Schema cannot see (ids across files, graph symmetry, campaign
coherence). Exits nonzero on any error. Run from anywhere:

    python3 tools/validate_data.py
"""
from __future__ import annotations

import json
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
    "balance.json": "balance.schema.json",
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
    "win_conditions.json": "win_conditions.schema.json",
    "names.json": "names.schema.json",
    "mercenaries.json": "mercenaries.schema.json",
    "agents.json": "agents.schema.json",
    "offices.json": "offices.schema.json",
    "tutorial.json": "tutorial.schema.json",
    "advisor.json": "advisor.schema.json",
}

LEVELS = ["village", "town", "large_town", "minor_city", "large_city", "huge_city"]

# Trigger kinds authored ahead of the system that will fire them. Everything
# else the engine never fires is flagged as dead content.
FORWARD_TRIGGERS: set[str] = set()  # nothing authored ahead of the engine right now

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


def cross_checks(t: dict[str, dict]) -> None:
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
        for kind in ("walls", "farms", "barracks"):
            if not any(c["kind"] == kind and culture in c["cultures"] for c in chains.values()):
                if culture != "neutral":
                    warn(f"buildings: culture {culture} has no {kind} chain")

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

    for faction_id, faction in factions.items():
        if faction.get("is_rebel"):
            continue
        recruitable = [u for u in units.values()
                       if faction_id in u["factions"] or "all" in u["factions"]]
        if len(recruitable) < 3:
            err(f"units: faction {faction_id} can recruit only {len(recruitable)} unit types")

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
            if chain["kind"] == "government":
                government_tier = tier
                if owner_culture not in chain["cultures"]:
                    warn(f"campaign: {region_id}: government building is foreign to {owner}")
            if chain.get("requires_coastal") and not regions[region_id].get("sea_zones"):
                err(f"campaign: {region_id}: {level_id} requires a coast")
            resource = chain.get("requires_resource")
            if resource and resource not in regions[region_id].get("resources", []):
                err(f"campaign: {region_id}: {level_id} requires resource {resource}")
        if government_tier == 0:
            err(f"campaign: {region_id}: no government building at start")
        else:
            needed = thresholds.get(LEVELS[government_tier - 1], 0)
            if setup["population"] < needed:
                err(f"campaign: {region_id}: population {setup['population']} below its tier "
                    f"threshold {needed}")
        for unit in setup.get("garrison", []):
            check_unit_instance(unit, owner, region_id)

    def check_unit_instance(instance: dict, owner: str, where: str) -> None:
        template = units.get(instance["template"])
        if template is None:
            err(f"campaign: {where}: unknown unit template {instance['template']}")
            return
        if owner != "rebels" and owner not in template["factions"] and "all" not in template["factions"]:
            warn(f"campaign: {where}: {owner} holds foreign unit {instance['template']}")

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
                check_unit_instance(unit, fid, army["region"])
        for fleet in faction_setup.get("fleets", []):
            if fleet["sea_zone"] not in zones:
                err(f"campaign: {fid}: fleet in unknown sea zone {fleet['sea_zone']}")
            for ship in fleet["ships"]:
                check_unit_instance(ship, fid, fleet["sea_zone"])
        roles = [c["role"] for c in faction_setup.get("characters", [])]
        if factions.get(fid, {}).get("is_rebel") is not True and roles.count("leader") != 1:
            err(f"campaign: {fid}: needs exactly one leader, has {roles.count('leader')}")
        if roles.count("heir") > 1:
            err(f"campaign: {fid}: more than one heir")
        for character in faction_setup.get("characters", []):
            if character["id"] in character_ids:
                err(f"campaign: duplicate character id {character['id']}")
            character_ids.add(character["id"])
            location = character.get("location", "")
            if location and location not in regions:
                err(f"campaign: character {character['id']}: unknown location {location}")
        known = {c["id"] for c in faction_setup.get("characters", [])}
        for character in faction_setup.get("characters", []):
            father = character.get("father")
            if father and father not in known:
                err(f"campaign: character {character['id']}: unknown father {father}")
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
    for faction_setup in campaign.get("factions", []):
        for character in faction_setup.get("characters", []):
            for trait_id in character.get("traits", []):
                if trait_id not in trait_defs:
                    err(f"campaign: character {character['id']}: unknown trait {trait_id}")

    # --- balance sanity ---------------------------------------------------
    ordered = [e["min_population"] for e in balance.get("settlement_levels", [])]
    if ordered != sorted(ordered):
        err("balance: settlement level thresholds must be ascending")

    # --- agents -----------------------------------------------------------
    agent_kinds = t.get("agents.json", {}).get("kinds", [])
    seen_agent_ids: set[str] = set()
    for kind in agent_kinds:
        if kind["id"] in seen_agent_ids:
            err(f"agents: duplicate kind {kind['id']}")
        seen_agent_ids.add(kind["id"])
    for kind in agent_kinds:
        req_kind = kind["requirements"]["building_kind"]
        matched = any(c.get("kind") == req_kind
                      for c in t.get("buildings.json", {}).get("chains", [])
                      + t.get("temples.json", {}).get("chains", []))
        if not matched:
            err(f"agents: {kind['id']} requires building kind '{req_kind}' that no chain provides")
    for wanted in ("diplomat", "spy", "assassin"):
        if wanted not in seen_agent_ids:
            err(f"agents: kind '{wanted}' missing — the engine expects all three")

    # --- offices ----------------------------------------------------------
    offices = t.get("offices.json", {}).get("offices", [])
    office_ids: set[str] = set()
    ranks: list[int] = []
    for office in offices:
        if office["id"] in office_ids:
            err(f"offices: duplicate id {office['id']}")
        office_ids.add(office["id"])
        ranks.append(office["rank"])
    if len(set(ranks)) != len(ranks):
        err("offices: ranks must be unique — the ladder needs a strict order")

    # --- tutorial ---------------------------------------------------------
    tutorial = t.get("tutorial.json", {}).get("tutorial", {})
    region_ids = {r["id"] for r in t.get("regions.json", {}).get("regions", [])}
    steps = tutorial.get("steps", [])
    step_ids: set[str] = set()
    for step in steps:
        if step["id"] in step_ids:
            err(f"tutorial: duplicate step id {step['id']}")
        step_ids.add(step["id"])
        for region in [step.get("center_on")] + step.get("highlight_regions", []) \
                + [step.get("advance", {}).get("region")]:
            if region is not None and region not in region_ids:
                err(f"tutorial: step {step['id']}: unknown region {region}")
    tutorial_faction = tutorial.get("faction")
    faction_def = factions.get(tutorial_faction)
    if faction_def is None:
        err(f"tutorial: unknown faction {tutorial_faction}")
    elif faction_def.get("playable") not in ("playable", "unlockable"):
        err(f"tutorial: faction {tutorial_faction} is not playable")
    if steps and not (8 <= len(steps) <= 20):
        warn(f"tutorial: {len(steps)} steps — outside the expected 8-20 range")

    # --- advisor knowledge pack -------------------------------------------
    advisor = t.get("advisor.json", {}).get("advisor", {})
    advisor_ids: set[str] = set()
    for system in advisor.get("systems", []):
        if system["id"] in advisor_ids:
            err(f"advisor: duplicate system id {system['id']}")
        advisor_ids.add(system["id"])
    for wanted in ("naval_combat", "ai_agents", "realtime_battles", "balance"):
        if wanted not in advisor_ids:
            warn(f"advisor: known-gap entry '{wanted}' missing from the systems ledger")

    # --- AI tunables ------------------------------------------------------
    ai = balance.get("ai", {})
    chain_kinds = {c.get("kind") for c in t.get("buildings.json", {}).get("chains", [])} \
        | {c.get("kind") for c in t.get("temples.json", {}).get("chains", [])}
    for kind in ai.get("build_priority", {}):
        if kind not in chain_kinds:
            warn(f"balance: ai.build_priority names kind '{kind}' with no building chain")
    garrison_targets = ai.get("garrison_units_by_level", [])
    if len(garrison_targets) != len(balance.get("settlement_levels", [])):
        err("balance: ai.garrison_units_by_level needs one entry per settlement level")


def main() -> int:
    tables = load_tables()
    if not errors:
        cross_checks(tables)
    for message in warnings:
        print(f"WARN  {message}")
    for message in errors:
        print(f"ERROR {message}")
    counts = {name: _entity_count(doc) for name, doc in tables.items()}
    summary = ", ".join(f"{name.removesuffix('.json')}={count}" for name, count in counts.items() if count)
    print(f"\n{len(errors)} errors, {len(warnings)} warnings [{summary}]")
    return 1 if errors else 0


def _entity_count(document: dict) -> int:
    for key in ("cultures", "factions", "chains", "units", "regions", "traits",
                "ancillaries", "events", "wonders", "missions", "conditions", "pools"):
        if key in document:
            return len(document[key])
    return 0


if __name__ == "__main__":
    sys.exit(main())
