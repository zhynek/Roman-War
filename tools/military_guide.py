#!/usr/bin/env python3
"""Regenerate the data-driven sections of docs/MILITARY_STRATEGY.md.

The guide's prose is hand-written; its tables (odds, the counter matrix, ground,
walls, kit, the military chains, the warcraft catalogue) are read from the data
tables so the guide can never disagree with the engine. Run after retuning:

    python3 tools/military_guide.py          # rewrites the generated sections in place
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
GUIDE = ROOT / "docs" / "MILITARY_STRATEGY.md"

CULTURE_NAMES = {
    "roman": "Roman", "greek": "Hellenistic (Greek)", "eastern": "Eastern",
    "carthaginian": "Carthaginian", "egyptian": "Egyptian", "barbarian": "Tribal (barbarian)",
}
CULTURE_ORDER = ["roman", "greek", "eastern", "carthaginian", "egyptian", "barbarian"]
STAT_NAMES = {"attack": "attack", "defense": "defense", "morale": "morale", "charge": "charge",
              "missile_attack": "missile"}
FLAT_NAMES = {
    "battle_strength_pct": "strength {v:+d}%", "attacking_pct": "attacking {v:+d}%",
    "assault_pct": "storming walls {v:+d}%", "wall_defense_pct": "holding walls {v:+d}%",
    "pursuit_pct": "pursuit {v:+d}%", "escape_pct": "escape {v:+d}%",
    "upgrade_cap": "kit cap {v:+d}", "siege_equipment_turns_delta": "siege works {v:+d} turn",
    "garrison_order_pct": "garrison order {v:+d}%", "levy_strain_pct": "levy strain {v:+d}%",
    "movement_points": "march {v:+.2f}", "mercenary_cost_pct": "mercenary cost {v:+d}%",
    "weapon_upgrade": "weapons +{v}", "armor_upgrade": "armour +{v}", "recruit_xp": "recruits +{v} xp",
    "wall_level_bonus": "walls +{v} tier", "naval_movement_pct": "sailing {v:+d}%",
}


def load(name: str) -> dict:
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def win_chance(ratio: float, spread: float, steps: int = 256) -> float:
    """Mirror of BattleResolver.win_chance: P(ratio * X > Y) for X, Y ~ U[1-p, 1+p]."""
    low, high = 1.0 - spread, 1.0 + spread
    threshold = 1.0 / ratio
    width = (high - low) / steps
    area = 0.0
    for i in range(steps):
        y = low + (i + 0.5) * width
        area += max(0.0, high - max(low, threshold * y))
    return min(1.0, max(0.0, area * width / ((high - low) ** 2)))


def humanize(token: str) -> str:
    return token.replace("_", " ")


def odds_table(balance: dict) -> str:
    spread = float(balance["battle"]["randomness_pct"]) / 100.0
    rows = ["| Paper odds | Chance to win |", "|---|---|"]
    for ratio in (0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5, 2.0):
        rows.append(f"| {ratio:.1f}:1 | {round(win_chance(ratio, spread) * 100):d}% |")
    return "\n".join(rows)


def war_effect_text(technique: dict) -> str:
    parts: list[str] = []
    war = technique.get("war", {})
    for entry in war.get("class_stats", []):
        deltas = [f"{STAT_NAMES[k]} {entry[k]:+d}" for k in STAT_NAMES if k in entry]
        parts.append(f"{humanize(entry['class'])} " + ", ".join(deltas))
    for entry in war.get("matchups", []):
        parts.append(f"{humanize(entry['class'])} vs {humanize(entry['versus'])} {entry['pct']:+d}%")
    for entry in war.get("terrain", []):
        parts.append(f"{humanize(entry['class'])} on {entry['terrain']} {entry['pct']:+d}%")
    for entry in war.get("upkeep_pct", []):
        parts.append(f"{humanize(entry['class'])} upkeep {entry['pct']:+d}%")
    for entry in war.get("recruit_xp", []):
        parts.append(f"{humanize(entry['class'])} recruits +{entry['xp']} xp")
    if war.get("fatigue_immune"):
        parts.append("tireless on a forced march")
    for key, value in technique.get("effects", {}).items():
        template = FLAT_NAMES.get(key, key.replace("_", " ") + " {v}")
        try:
            parts.append(template.format(v=value))
        except (ValueError, TypeError):
            parts.append(f"{humanize(key)} {value}")
    return "; ".join(parts)


def requires_text(technique: dict, techniques: dict) -> str:
    prereq = technique["prerequisites"]
    wants: list[str] = []
    if prereq.get("era"):
        wants.append(f"{prereq['era'].replace('_', '-')} era")
    for needed in prereq.get("techniques", []):
        wants.append(f"after {techniques[needed]['name'].lower()}")
    if prereq.get("building_kind"):
        wants.append(f"{humanize(prereq['building_kind'])} tier {prereq['building_level']}")
    if prereq.get("resource"):
        wants.append(f"{prereq['resource']} region")
    if prereq.get("battles_won"):
        n = prereq["battles_won"]
        wants.append(f"{n} battle{'s' if n != 1 else ''} won")
    if prereq.get("battles_lost"):
        n = prereq["battles_lost"]
        wants.append(f"{n} battle{'s' if n != 1 else ''} lost")
    if prereq.get("faced"):
        faced = prereq["faced"]
        wants.append(f"faced {humanize(faced['class'])} in {faced['battles']} battle{'s' if faced['battles'] != 1 else ''}")
    return ", ".join(wants) if wants else "nothing"


def warcraft_section(techniques_doc: dict, factions: dict) -> str:
    techniques = {t["id"]: t for t in techniques_doc["techniques"]}
    military = [t for t in techniques.values()
                if t["domain"] in ("warcraft", "military_engineering", "metallurgy_craft")
                and (t.get("war") or set(t["effects"]) & set(FLAT_NAMES))]
    lines: list[str] = []
    by_culture: dict[str, list[dict]] = {c: [] for c in CULTURE_ORDER}
    shared: list[dict] = []
    for technique in sorted(military, key=lambda t: (t["adoption"]["cost"], t["id"])):
        origins = technique["origin_cultures"]
        if len(origins) == 1 and origins[0] in by_culture:
            by_culture[origins[0]].append(technique)
        else:
            shared.append(technique)
    for culture in CULTURE_ORDER:
        if not by_culture[culture]:
            continue
        lines.append(f"### {CULTURE_NAMES[culture]}\n")
        lines.append("| technique | cost / turns | requires | effects | history |")
        lines.append("|---|---|---|---|---|")
        for technique in by_culture[culture]:
            lines.append(_row(technique, techniques, factions))
        lines.append("")
    if shared:
        lines.append("### Devised by more than one people\n")
        lines.append("| technique | cost / turns | requires | effects | history |")
        lines.append("|---|---|---|---|---|")
        for technique in shared:
            lines.append(_row(technique, techniques, factions))
        lines.append("")
    return "\n".join(lines).rstrip("\n") + "\n"


def _row(technique: dict, techniques: dict, factions: dict) -> str:
    name = f"**{technique['name']}**"
    notes: list[str] = []
    if technique.get("factions"):
        notes.append(", ".join(technique["factions"]) + " only")
    starters = technique["start_adopted"].get("factions", [])
    if starters:
        notes.append("practised from the start by " + ", ".join(starters))
    if len(technique["origin_cultures"]) > 1:
        notes.append("devised by " + ", ".join(technique["origin_cultures"]))
    if notes:
        name += " (" + "; ".join(notes) + ")"
    adoption = technique["adoption"]
    return (f"| {name} | {adoption['cost']} / {adoption['turns']} | {requires_text(technique, techniques)} | "
            f"{war_effect_text(technique)} | {technique['historical_basis']} |")


def replace_between(text: str, start_marker: str, end_marker: str, body: str) -> str:
    pattern = re.compile(re.escape(start_marker) + r".*?" + re.escape(end_marker), re.S)
    assert pattern.search(text), start_marker
    return pattern.sub(lambda _: start_marker + "\n" + body + end_marker, text, count=1)


def main() -> None:
    balance = load("balance.json")
    techniques_doc = load("techniques.json")
    factions = {f["id"]: f for f in load("factions.json")["factions"]}
    text = GUIDE.read_text(encoding="utf-8")
    text = replace_between(text, "<!-- odds:begin -->", "<!-- odds:end -->", odds_table(balance) + "\n")
    text = replace_between(text, "<!-- warcraft:begin -->", "<!-- warcraft:end -->",
                           warcraft_section(techniques_doc, factions))
    GUIDE.write_text(text, encoding="utf-8")
    print("regenerated", GUIDE.relative_to(ROOT))


if __name__ == "__main__":
    main()
