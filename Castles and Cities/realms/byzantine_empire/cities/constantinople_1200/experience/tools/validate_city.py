#!/usr/bin/env python3
"""Validate independent authoring data; optionally exercise the actual Godot layout.

No campaign tables, save files or runtime code are read. This tool verifies
consistency and physical exclusions, not the historical truth of a reconstruction.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import tempfile

try:
    import jsonschema
except ImportError:
    raise SystemExit("Install jsonschema in the Python environment to validate city data.")


ROOT = Path(__file__).resolve().parents[1]


def inside(point, polygon):
    x, y = point
    result = False
    previous = polygon[-1]
    for current in polygon:
        ax, ay = current
        bx, by = previous
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
            result = not result
        previous = current
    return result


def polygon_errors(label, polygon):
    errors = []
    area = sum(a[0] * b[1] - b[0] * a[1]
               for a, b in zip(polygon, polygon[1:] + polygon[:1])) / 2
    if abs(area) < 1:
        errors.append(f"{label}: degenerate polygon")

    def orient(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    edges = list(zip(polygon, polygon[1:] + polygon[:1]))
    for i, (a, b) in enumerate(edges):
        if a == b:
            errors.append(f"{label}: zero-length edge {i}")
        for j in range(i + 2, len(edges)):
            if i == 0 and j == len(edges) - 1:
                continue
            c, d = edges[j]
            if orient(a, b, c) * orient(a, b, d) < 0 and orient(c, d, a) * orient(c, d, b) < 0:
                errors.append(f"{label}: self-intersection at edges {i} and {j}")
    return errors


def validate(data, schema):
    errors = []
    validator = jsonschema.Draft202012Validator(schema)
    for error in sorted(validator.iter_errors(data), key=lambda e: str(list(e.path))):
        errors.append(f"{'/'.join(str(p) for p in error.path)}: {error.message}")
    if errors:
        return errors

    def finite(value, path="city"):
        if isinstance(value, float) and not math.isfinite(value):
            errors.append(f"{path}: non-finite number")
        elif isinstance(value, dict):
            for key, child in value.items():
                finite(child, f"{path}/{key}")
        elif isinstance(value, list):
            for i, child in enumerate(value):
                finite(child, f"{path}/{i}")
    finite(data)

    for table in ("roads", "walls", "districts", "landmarks", "sources", "stages", "fields", "harbors"):
        ids = [item["id"] for item in data[table]]
        if len(ids) != len(set(ids)):
            errors.append(f"{table}: duplicate IDs")
    source_ids = {source["id"] for source in data["sources"]}
    landmark_ids = {item["id"] for item in data["landmarks"]}
    if data["initial_focus"] not in landmark_ids:
        errors.append("initial_focus: missing landmark")
    if data["coordinate_system"]["source_id"] not in source_ids:
        errors.append("coordinate_system: missing source")
    boundary = data["site"]["boundary_m"]
    errors.extend(polygon_errors("site/boundary_m", boundary))
    for table in ("landmarks", "harbors"):
        for item in data[table]:
            missing = set(item["source_ids"]) - source_ids
            if missing:
                errors.append(f"{table}/{item['id']}: unknown sources {sorted(missing)}")
    for context in data["site"].get("context_land", []):
        errors.extend(polygon_errors(f"context_land/{context['id']}", context["polygon_m"]))
        if set(context["source_ids"]) - source_ids:
            errors.append(f"context_land/{context['id']}: unknown source")
    for item in data["landmarks"]:
        if not inside(item["position_m"], boundary):
            errors.append(f"landmark/{item['id']}: center outside modeled land")
        if item["kind"] == "gate":
            gx, gy = item["position_m"]
            aligned = False
            for wall in data["walls"]:
                for a, b in zip(wall["points_m"], wall["points_m"][1:]):
                    vx, vy = b[0] - a[0], b[1] - a[1]
                    length2 = vx * vx + vy * vy
                    if length2 == 0:
                        continue
                    t = max(0, min(1, ((gx - a[0]) * vx + (gy - a[1]) * vy) / length2))
                    distance = math.hypot(gx - a[0] - t * vx, gy - a[1] - t * vy)
                    tangent = math.degrees(math.atan2(vy, vx))
                    angle_error = abs((item["rotation_deg"] - tangent + 90) % 180 - 90)
                    if distance < 0.01 and angle_error < 0.01:
                        aligned = True
            if not aligned:
                errors.append(f"landmark/{item['id']}: gate must meet and follow an authored wall")
            if not any(math.hypot(gx - p[0], gy - p[1]) < 0.01
                       for road in data["roads"] for p in road["points_m"][1:-1]):
                errors.append(f"landmark/{item['id']}: road must pass through the gate center")
        dims = item["dimensions"]
        for flag in ("underground", "open_top"):
            if dims.get(flag, 0) and item["kind"] != "cistern":
                errors.append(f"landmark/{item['id']}: {flag} only valid for cisterns")
        if dims.get("underground", 0) and dims.get("open_top", 0):
            errors.append(f"landmark/{item['id']}: conflicting cistern profiles")
        if "column_grid_x" in dims and "column_grid_z" in dims:
            if dims["column_grid_x"] * dims["column_grid_z"] != dims.get("column_count"):
                errors.append(f"landmark/{item['id']}: column grid/count mismatch")
    for table in ("districts", "fields"):
        for item in data[table]:
            errors.extend(polygon_errors(f"{table}/{item['id']}", item["polygon_m"]))
    for table in ("roads", "walls"):
        for item in data[table]:
            points = item["points_m"]
            if any(a == b for a, b in zip(points, points[1:])):
                errors.append(f"{table}/{item['id']}: zero-length segment")
    stages = {stage["id"]: stage for stage in data["stages"]}
    expected = {"reference_1200", "serviced", "expanded"}
    if set(stages) != expected:
        errors.append("stages: expected one 1200 baseline and the serviced/expanded creative variants")
    else:
        if stages["reference_1200"]["hypothetical"] or stages["reference_1200"]["density_multiplier"] != 1:
            errors.append("stages: invalid reference baseline")
        if any(not stages[key]["hypothetical"] for key in ("serviced", "expanded")):
            errors.append("stages: creative development must be explicitly hypothetical")
        if not 1 < stages["serviced"]["density_multiplier"] < stages["expanded"]["density_multiplier"]:
            errors.append("stages: creative density multipliers must increase")
    layout_text = (ROOT / "src/layout.gd").read_text()
    if re.search(r"res://(?:src/core|data/(?:campaign|balance|factions)|.*save)", layout_text):
        errors.append("layout: campaign dependency is prohibited")
    if re.search(r"(?<![.\w])(?:randf|randi|randomize|seed)\s*\(", layout_text):
        errors.append("layout: use local seeded random generator only")
    return errors


def validate_presentation(visuals, visual_schema, ui, ui_schema, main_text):
    """Check independently authored visual budgets and the interface vocabulary."""
    errors = []
    for label, data, schema in (("visuals", visuals, visual_schema), ("ui", ui, ui_schema)):
        validator = jsonschema.Draft202012Validator(schema)
        for error in sorted(validator.iter_errors(data), key=lambda e: str(list(e.path))):
            path = "/".join(str(part) for part in error.path)
            errors.append(f"{label}/{path}: {error.message}")
    if errors:
        return errors

    # Only complete literal arguments count. Prefix expressions such as
    # _t("kit_" + kind) are covered by the schema's known dynamic vocabulary.
    # Strip GDScript comments without treating a # inside a string as a comment.
    code = re.sub(r"(\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')|#[^\n]*",
                  lambda match: match.group(1) or "", main_text)
    pattern = r"\b(?:_t|_button|_set_status)\s*\(\s*[\"']([a-z][a-z0-9_]*)[\"']\s*(?=[,)])"
    for key in sorted(set(re.findall(pattern, code))):
        if key not in ui:
            errors.append(f"ui/{key}: literal interface key referenced by main.gd is missing")
    return errors


def validate_architecture(config, schema, city, visuals):
    """Cross-reference interpretive types, evidence and active ward profiles."""
    errors = []
    validator = jsonschema.Draft202012Validator(schema)
    for error in sorted(validator.iter_errors(config), key=lambda e: str(list(e.path))):
        path = "/".join(str(part) for part in error.path)
        errors.append(f"architecture/{path}: {error.message}")
    if errors:
        return errors
    type_ids = [row["id"] for row in config["types"]]
    evidence_ids = [row["id"] for row in config["evidence"]]
    if len(type_ids) != len(set(type_ids)):
        errors.append("architecture/types: duplicate IDs")
    if len(evidence_ids) != len(set(evidence_ids)):
        errors.append("architecture/evidence: duplicate IDs")
    definitions = {row["id"]: row for row in config["types"]}
    for row in config["types"]:
        if row["evidence_id"] not in evidence_ids:
            errors.append(f"architecture/{row['id']}: missing evidence")
        if row["wall_material"] not in visuals["palette"]:
            errors.append(f"architecture/{row['id']}: missing material")
    for district in city["districts"]:
        if district["style"] not in config["district_profiles"]:
            errors.append(f"architecture/profiles: missing ward style {district['style']}")
    for profile, rows in config["district_profiles"].items():
        ids = [row["type_id"] for row in rows]
        if len(ids) != len(set(ids)):
            errors.append(f"architecture/profile/{profile}: repeated type")
        for row in rows:
            if row["type_id"] not in definitions:
                errors.append(f"architecture/profile/{profile}: unknown type {row['type_id']}")
            if not math.isfinite(row["weight"]):
                errors.append(f"architecture/profile/{profile}: non-finite weight")
    for kind, type_id in config["creative_defaults"].items():
        expected = "home" if kind == "house" else kind
        if type_id not in definitions or definitions[type_id]["kind"] != expected:
            errors.append(f"architecture/creative_defaults/{kind}: wrong or missing type")
    module = (ROOT / "src/architecture.gd").read_text()
    for row in config["types"]:
        if f'"{row["plan"]}"' not in module:
            errors.append(f"architecture/{row['id']}: plan has no geometry reader")
    if re.search(r"(?<![.\w])(?:randf|randi|randomize|seed)\s*\(", module):
        errors.append("architecture: unseeded random call is prohibited")
    return errors


def validate_neighborhood(config, schema, city):
    errors = []
    for error in jsonschema.Draft202012Validator(schema).iter_errors(config):
        errors.append(f"neighborhood/{list(error.path)}: {error.message}")
    if errors:
        return errors
    sources = {row["id"] for row in config["evidence"]}
    for table in ("blocks", "streets", "stops", "evidence"):
        ids = [row["id"] for row in config[table]]
        if len(ids) != len(set(ids)):
            errors.append(f"neighborhood/{table}: duplicate stable IDs")
    errors.extend(polygon_errors("neighborhood/boundary", config["boundary_m"]))
    parcels = set()
    for block in config["blocks"]:
        polygon = block["polygon_m"]
        errors.extend(polygon_errors(block["id"], polygon))
        if block["evidence_id"] not in sources:
            errors.append(f"neighborhood/{block['id']}: unknown evidence")
        # The analytic inward offset requires counterclockwise convex input.
        for i, a in enumerate(polygon):
            b, c = polygon[(i+1)%len(polygon)], polygon[(i+2)%len(polygon)]
            if (b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0]) <= 0:
                errors.append(f"neighborhood/{block['id']}: expected convex counterclockwise boundary")
            if not inside(a, config["boundary_m"]):
                errors.append(f"neighborhood/{block['id']}: block outside override boundary")
            count = max(2, math.floor(math.dist(a,b)/block["frontage_m"]+0.5))
            gaps = {(p["edge"], p["index"]) for p in block["passages"]}
            for j in range(count):
                if (i,j) not in gaps:
                    parcels.add(f"{block['id']}_e{i}_p{j}")
        for gap in block["passages"]:
            edge = gap["edge"]
            if edge >= len(polygon):
                errors.append(f"neighborhood/{block['id']}: passage edge out of range")
            elif gap["index"] >= max(2, math.floor(math.dist(polygon[edge], polygon[(edge+1)%len(polygon)])/block["frontage_m"]+0.5)):
                errors.append(f"neighborhood/{block['id']}: passage slot out of range")
    for stop in config["stops"]:
        if "parcel_id" in stop and stop["parcel_id"] not in parcels:
            errors.append(f"neighborhood/{stop['id']}: unknown or open passage parcel")
        if ("parcel_id" in stop) == ("point_m" in stop):
            errors.append(f"neighborhood/{stop['id']}: choose a parcel or a point")
    # Keep the gateway connected to the existing route, not a look-alike parallel road.
    origin = config["origin_m"]
    gateway = config["streets"][0]["points_m"][-1]
    absolute = [origin[0]+gateway[0], origin[1]+gateway[1]]
    approach = next(row for row in city["roads"] if row["id"] == "pantokrator_shore")
    if absolute not in approach["points_m"]:
        errors.append("neighborhood: approach no longer joins the preserved Pantokrator route")
    return errors


GODOT_PROBE = r'''extends SceneTree
const Layout = preload("res://src/layout.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok and failures.size() < 35:
		failures.append(message)

func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/city.json"))
	var before: String = JSON.stringify(data)
	var base: Dictionary = Layout.generate(data)
	var repeat: Dictionary = Layout.generate(data)
	var serviced: Dictionary = Layout.generate(data, "serviced")
	var expanded: Dictionary = Layout.generate(data, "expanded")
	check(var_to_bytes(base) == var_to_bytes(repeat), "Generation must be byte-identical")
	check(before == JSON.stringify(data), "Generation mutated authoring data")
	check(base.buildings.size() > 5000, "Reference must populate the whole city")
	check(expanded.buildings.size() <= int(data.site.generation.max_buildings), "Building budget exceeded")
	check(base.trees.size() <= int(data.site.generation.max_trees), "Tree budget exceeded")
	var original: Dictionary = {}
	for house: Dictionary in base.buildings:
		check(not original.has(house.id), "Duplicate house ID")
		original[house.id] = house
	for stage: Dictionary in [serviced, expanded]:
		var lookup: Dictionary = {}
		for house: Dictionary in stage.buildings:
			lookup[house.id] = house
		for id: String in original:
			check(lookup.has(id) and lookup[id] == original[id], "Creative variant altered reference plot " + id)
	check(serviced.buildings.size() > base.buildings.size(), "Serviced variant has no visual infill")
	check(expanded.buildings.size() > serviced.buildings.size(), "Expanded variant has no additional infill")
	var land := PackedVector2Array()
	for p: Array in data.site.boundary_m:
		land.append(Vector2(p[0], p[1]))
	var plot_buckets: Dictionary = {}
	# Independent geometry checks on the actual returned buildings.
	for house: Dictionary in expanded.buildings:
		var p := Vector2(house.position.x, -house.position.z)
		var radius: float = Vector2(house.size.x, house.size.z).length() * 0.5
		var outline := PackedVector2Array()
		for corner: Vector2 in [Vector2(-house.size.x, -house.size.z), Vector2(house.size.x, -house.size.z), Vector2(house.size.x, house.size.z), Vector2(-house.size.x, house.size.z)]:
			outline.append(p + (corner * 0.5).rotated(house.yaw))
		var bucket := Vector2i(floori(p.x / 40.0), floori(p.y / 40.0))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for neighbor: Dictionary in plot_buckets.get(bucket + Vector2i(dx, dy), []):
					if p.distance_squared_to(neighbor.point) < pow(radius + neighbor.radius, 2.0):
						check(Geometry2D.intersect_polygons(outline, neighbor.outline).is_empty(), "House footprints overlap: " + house.id + " / " + neighbor.id)
		if not plot_buckets.has(bucket):
			plot_buckets[bucket] = []
		plot_buckets[bucket].append({"id": house.id, "point": p, "radius": radius, "outline": outline})
		check(house.position.y > 0.0, "House underwater: " + house.id)
		for corner: Vector2 in [Vector2(-house.size.x, -house.size.z), Vector2(house.size.x, -house.size.z), Vector2(house.size.x, house.size.z), Vector2(-house.size.x, house.size.z)]:
			check(Geometry2D.is_point_in_polygon(p + (corner * 0.5).rotated(house.yaw), land), "House footprint crosses coast: " + house.id)
		for table: String in ["roads", "walls"]:
			for line: Dictionary in data[table]:
				for i in range(line.points_m.size() - 1):
					var a := Vector2(line.points_m[i][0], line.points_m[i][1])
					var b := Vector2(line.points_m[i + 1][0], line.points_m[i + 1][1])
					var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
					check(p.distance_to(nearest) >= radius + float(line.width_m) * 0.5, "House collides with " + table + ": " + house.id)
		for item: Dictionary in data.landmarks:
			var center := Vector2(item.position_m[0], item.position_m[1])
			var local: Vector2 = (p - center).rotated(-deg_to_rad(float(item.rotation_deg)))
			var half := Vector2(item.dimensions.width_m, item.dimensions.depth_m) * 0.5
			check(absf(local.x) >= half.x + radius or absf(local.y) >= half.y + radius, "House intersects landmark: " + house.id)
	check(Layout.height_at(data, -7200, 0) > 0, "Western countryside must continue beyond crop")
	check(Layout.height_at(data, 2000, 0) < 0, "Bosphorus water must remain outside land")
	for item: Dictionary in data.landmarks:
		if item.kind == "aqueduct":
			continue
		var center := Vector2(item.position_m[0], item.position_m[1])
		var corner: Vector2 = (Vector2(item.dimensions.width_m, item.dimensions.depth_m) * 0.49).rotated(deg_to_rad(item.rotation_deg))
		check(absf(Layout.height_at(data, center.x, center.y) - Layout.height_at(data, center.x + corner.x, center.y + corner.y)) < 0.1, "Monument foundation is not level: " + item.id)
	for message: String in failures:
		printerr("VALIDATION_FAILURE: " + message)
	print("LAYOUT_VALIDATION houses=%d serviced=%d expanded=%d trees=%d lanes=%d failures=%d" % [base.buildings.size(), serviced.buildings.size(), expanded.buildings.size(), base.trees.size(), base.lanes.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
'''


def validate_runtime(godot):
    with tempfile.TemporaryDirectory(prefix="constantinople-layout-") as folder:
        probe = Path(folder) / "probe.gd"
        log = Path(folder) / "godot.log"
        probe.write_text(GODOT_PROBE)
        command = [godot, "--headless", "--path", str(ROOT), "--log-file", str(log), "--script", str(probe)]
        process = subprocess.run(command, capture_output=True, text=True, timeout=90)
        output = process.stdout + process.stderr
        print(output.rstrip())
        if process.returncode or re.search(r"SCRIPT ERROR:|ERROR:|VALIDATION_FAILURE:", output):
            return False
        return "LAYOUT_VALIDATION" in output and "failures=0" in output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Also run independent layout/repeatability/physical-exclusion checks with this Godot executable")
    args = parser.parse_args()
    data = json.loads((ROOT / "data/city.json").read_text())
    schema = json.loads((ROOT / "schemas/city.schema.json").read_text())
    errors = validate(data, schema)
    try:
        visuals = json.loads((ROOT / "data/visuals.json").read_text())
        visual_schema = json.loads((ROOT / "schemas/visuals.schema.json").read_text())
        ui = json.loads((ROOT / "data/ui.json").read_text())
        ui_schema = json.loads((ROOT / "schemas/ui.schema.json").read_text())
        errors.extend(validate_presentation(visuals, visual_schema, ui, ui_schema,
                                            (ROOT / "src/main.gd").read_text()))
        architecture = json.loads((ROOT / "data/architecture.json").read_text())
        architecture_schema = json.loads((ROOT / "schemas/architecture.schema.json").read_text())
        errors.extend(validate_architecture(architecture, architecture_schema, data, visuals))
        neighborhood = json.loads((ROOT / "data/neighborhood.json").read_text())
        neighborhood_schema = json.loads((ROOT / "schemas/neighborhood.schema.json").read_text())
        errors.extend(validate_neighborhood(neighborhood, neighborhood_schema, data))
    except (OSError, ValueError) as error:
        errors.append(f"presentation configuration: {error}")
    for error in errors:
        print("ERROR:", error)
    print(f"City data: {len(data['landmarks'])} landmarks, {len(data['districts'])} districts, {len(data['sources'])} sources; {len(errors)} errors.")
    if errors:
        return 1
    print("Presentation config: visual budgets, palette, architecture types/evidence/ward profiles and UI vocabulary validated.")
    if args.godot and not validate_runtime(args.godot):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
