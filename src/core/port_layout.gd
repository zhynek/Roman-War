class_name PortLayout
## Reusable local-meter geometry. No scene, physics body or presentation state.
## Rendering and future navigation consume these exact footprints.

static func rectangle(values: Array) -> Rect2:
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))

static func build(data: GameData, region: String, architecture: Dictionary) -> Dictionary:
	var source: Dictionary = data.ports["layout"]
	var rank := int(architecture.get("stage", 0))
	var setting: String = architecture.get("setting", PortRules.site(data, region).get("setting", "riverbank"))
	var out := {"region": region, "stage": rank, "setting": setting, "bounds": source["bounds"].duplicate(),
		"land": source["land"].duplicate(), "water": source["water"].duplicate(), "structures": [], "walkable": [source["land"].duplicate()],
		"obstacles": [], "routes": [], "berths": [], "channels": [], "bridges": [], "entrances": [], "gates": [], "ramps": [], "dock_edges": [],
		"land_water_boundary": [[-60,8],[60,8]], "objectives": []}
	for feature in source["structures"]:
		if int(feature["stage"]) > rank or (feature["facility"] != "" and not architecture.get("facilities", []).has(feature["facility"])):
			continue
		if setting == "riverbank" and feature["kind"] in ["breakwater", "beacon"]:
			continue
		var placed: Dictionary = feature.duplicate(true)
		out["structures"].append(placed)
		var rect: Array = placed["rect"]
		var kind: String = placed["kind"]
		if kind in ["road", "court", "pier", "quay", "ramp", "breakwater", "bridge"]:
			out["walkable"].append(rect.duplicate())
		else:
			out["obstacles"].append({"id": placed["id"], "rect": rect.duplicate(), "height": placed["height"]})
		if kind in ["pier", "quay", "ramp"]:
			out["dock_edges"].append({"id": placed["id"], "rect": rect.duplicate()})
		if kind == "bridge":
			out["bridges"].append({"id": placed["id"], "rect": rect.duplicate(), "height": placed["height"]})
		if kind == "ramp":
			out["ramps"].append({"id": placed["id"], "rect": rect.duplicate(), "rise": placed["height"]})
		if kind in ["arsenal", "warehouse", "hall", "barracks"]:
			out["objectives"].append({"id": placed["id"], "at": [rect[0] + rect[2] * 0.5, rect[1] + rect[3] + 1]})
	for route in source["routes"]:
		if int(route["stage"]) <= rank:
			out["routes"].append(route.duplicate(true))
	for channel in source.get("channels", []):
		if int(channel["stage"]) <= rank:
			out["channels"].append(channel.duplicate(true))
	for berth in source["berths"]:
		if int(berth["stage"]) <= rank:
			out["berths"].append(berth.duplicate(true))
	if rank > 0:
		out["entrances"].append({"id": "settlement", "rect": [-4,-45,8,3]})
	if rank >= 2:
		out["gates"].append({"id": "road_gate", "rect": [-4,-33,8,6], "open": true})
	return out

static func walkable_at(layout: Dictionary, point: Vector2) -> bool:
	var supported := false
	for footprint in layout.get("walkable", []):
		if rectangle(footprint).has_point(point):
			supported = true
			break
	if not supported:
		return false
	for channel in layout.get("channels", []):
		if rectangle(channel["rect"]).has_point(point):
			var crossing := false
			for bridge in layout.get("bridges", []):
				crossing = crossing or rectangle(bridge["rect"]).has_point(point)
			if not crossing:
				return false
	for obstacle in layout.get("obstacles", []):
		if rectangle(obstacle["rect"]).has_point(point):
			return false
	return true
