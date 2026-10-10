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
		"banks": source.get("banks",{}).get(setting,[]).duplicate(true), "land": source["land"].duplicate(), "water": source["water"].duplicate(), "structures": [], "walkable": [source["land"].duplicate()],
		"obstacles": [], "routes": [], "berths": [], "channels": [], "bridges": [], "entrances": [], "gates": [], "ramps": [], "dock_edges": [],
		"land_water_boundary": [[-60,8],[60,8]], "objectives": []}
	for feature in source["structures"]:
		if int(feature["stage"]) > rank or (feature["facility"] != "" and not architecture.get("facilities", []).has(feature["facility"])):
			continue
		if setting == "riverbank" and (feature["kind"] in ["breakwater", "beacon"] or feature.get("coastal_only",false)):
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
	if rank >= 4:
		out["gates"].append({"id": "landward_gate", "rect": [-4,-43,8,2], "open": true})
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

static func elevation_at(layout: Dictionary, point: Vector2) -> float:
	var height := 0.0
	for f in layout.get("structures", []):
		var r := rectangle(f["rect"])
		if not r.has_point(point):
			continue
		if f["kind"] == "ramp":
			height = maxf(height,float(f["height"])*clampf((point.y-r.position.y)/r.size.y,0,1))
		elif f["kind"] == "bridge":
			height = maxf(height,float(f["height"])*minf(1,minf(point.x-r.position.x,r.end.x-point.x)/2))
		elif f["kind"] in ["pier","quay","breakwater"]:
			height = maxf(height,float(f["height"]))
	return height

static func vessel_at(layout: Dictionary, point: Vector2, beam: float = 1.0) -> bool:
	# Public geometry query for future vessel routing. Bridges have no navigable
	# underpass in this phase; waterway suitability still belongs to PortRules.
	for offset in [Vector2.ZERO,Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		var p: Vector2 = point + offset*beam*0.5
		var wet := rectangle(layout["water"]).has_point(p)
		for channel in layout.get("channels", []):
			wet = wet or rectangle(channel["rect"]).has_point(p)
		for bank in layout.get("banks",[]):
			if rectangle(bank).has_point(p):
				wet = false
		if not wet:
			return false
		for f in layout["structures"]:
			if f["kind"] in ["road","court"]:
				continue # The channel cuts these ground-level paving overlays.
			if rectangle(f["rect"]).has_point(p):
				return false
	return true

static func battle_sites(layout: Dictionary) -> Array:
	# Public stable IDs + geometry only. Never append rosters or ownership here.
	var result: Array = []
	for group in ["entrances","gates","bridges","ramps","berths"]:
		for f in layout[group]:
			result.append({"id":f["id"],"role":group,"rect":f["rect"].duplicate()})
	for f in layout["structures"]:
		if f["kind"] in ["court","arsenal","warehouse","hall","barracks"]:
			result.append({"id":f["id"],"role":"deployment" if f["kind"]=="court" else "objective", "rect":f["rect"].duplicate(),
				"district":"military" if f["kind"] in ["arsenal","barracks","court"] else "commercial"})
	return result
