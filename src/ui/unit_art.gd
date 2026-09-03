class_name UnitArt
extends RefCounted
## Resolves a unit template into the same plate shape BuildingArt produces, so
## one painter draws both. Class and culture are orthogonal — the class sets
## pose, weapon, mount and formation, the culture sets shield, helmet, armour
## and standard — so 12 class templates and 7 kits dress all 91 units without a
## picture authored per unit.
##
## The soldier count never becomes a figure count. It picks a rank-and-file
## band, and the ranks behind the first are drawn with less and less fidelity,
## fading toward the sky: a cohort of 240 costs about twenty marks and reads as
## a mass because the back of it is hazy, not because it is crowded.

const MAX_PLATE_CACHE := 256

static var _cache := {}

var classes := {}
var kits := {}
var overrides := {}
var attributes := {}
var load_errors: PackedStringArray = []

var _plates := {}


static func for_data(data) -> UnitArt:
	var key: int = data.get_instance_id()
	if not _cache.has(key):
		_cache.clear()
		var art := UnitArt.new()
		art.load_from("res://data/unit_art.json")
		_cache[key] = art
	return _cache[key]


func load_from(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		load_errors.append("missing or empty: " + path)
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		load_errors.append("not a JSON object: " + path)
		return
	for row in parsed.get("classes", []):
		classes[String(row["id"])] = row
	for row in parsed.get("kits", []):
		kits[String(row["id"])] = row
	for row in parsed.get("units", []):
		overrides[String(row["id"])] = row
	attributes = parsed.get("attributes", {})


static func files_for(soldiers: int) -> int:
	## Bands, not a headcount: twelve elephants and two hundred and forty
	## farmhands both have to fit the same small picture.
	if soldiers <= 24:
		return 1
	if soldiers <= 60:
		return 3
	if soldiers <= 120:
		return 4
	if soldiers <= 180:
		return 5
	return 6


func unit_plate(data, template_id: String, ctx: Dictionary) -> Dictionary:
	var unit: Dictionary = data.units.get(template_id, {})
	var key := "%s|%s|%d|%d|%d" % [template_id, ctx.get("season", "summer"),
		int(ctx.get("lod", 2)), int(ctx.get("experience", 0)),
		int(ctx.get("strength_pct", 100))]
	if _plates.has(key):
		return _plates[key]
	if unit.is_empty():
		return {"key": key, "kind": "unit", "title": template_id, "scene": {}, "lod": 0, "parts": []}

	var template: Dictionary = classes.get(String(unit["class"]), {})
	var kit: Dictionary = kits.get(String(unit["culture"]), kits.get("neutral", {}))
	var over: Dictionary = overrides.get(template_id, {})

	var look := {
		"stance": String(over.get("stance", template.get("stance", "guard"))),
		"weapon": String(over.get("weapon", template.get("weapon", "spear"))),
		"shield": String(over.get("shield", kit.get("shield", "round"))),
		"helmet": String(over.get("helmet", kit.get("helmet", "cap"))),
		"armour": String(over.get("armour", kit.get("armour", "tunic"))),
	}
	var formation := String(template.get("formation", "line"))
	var scene: Dictionary = (template.get("scene", {}) as Dictionary).duplicate(true)
	var standard := String(kit.get("standard", "disc"))
	var cues: Array = []
	for name in unit.get("attributes", []):
		var cue: Dictionary = attributes.get(String(name), {})
		if cue.is_empty():
			continue
		cues.append(String(cue["note"]))
		if cue.has("formation"):
			formation = String(cue["formation"])
		if cue.has("stance"):
			look["stance"] = String(cue["stance"])
		if cue.has("flora"):
			scene["flora"] = String(cue["flora"])
		if cue.has("sky"):
			scene["sky"] = String(cue["sky"])
		if cue.has("standard"):
			standard = String(cue["standard"])

	scene["terrain"] = String(ctx.get("terrain", "plains"))
	scene["fertility"] = float(ctx.get("fertility", 1.5))
	scene["season"] = String(ctx.get("season", "summer"))
	scene["progress"] = 1.0
	scene["damaged"] = false
	scene["figures"] = []            # the unit IS the figures here
	if not scene.has("ground"):
		scene["ground"] = 0.84
	if not scene.has("horizon"):
		scene["horizon"] = 0.56
	if not scene.has("flora"):
		scene["flora"] = "olive"
	if not scene.has("sky"):
		scene["sky"] = "clear"

	var art := BuildingArt.for_data(data)
	var tint: Color = ctx.get("tint", Color(0.6, 0.6, 0.6))
	var winter := 1.0 if String(ctx.get("season", "summer")) == "winter" else 0.0
	var cloth := art.shade_of(_tunic_material(art, kit), tint, winter)
	var steel := art.shade_of("iron", tint, winter)
	var timber := art.shade_of("timber", tint, winter)
	var banner := art.shade_of("cloth", tint, winter)

	var files := files_for(int(unit["soldiers"]))
	var ranks := int(template.get("ranks", 2))
	var parts: Array = []
	var z := 0

	func_add_ranks(parts, formation, files, ranks, look, cloth, steel, timber,
		String(template.get("mount", "none")), template_id,
		int(ctx.get("strength_pct", 100)))
	if bool(template.get("standard", false)) or formation in ["line", "hedge", "wall"]:
		parts.append(_part("standard", Rect2(0.86, 0.56, 0.05, 0.28), banner,
			{"finial": standard, "fly": 0.5, "count": 1}, 2, template_id))
	var chevrons := int(ctx.get("experience", 0))
	if chevrons > 0:
		parts.append(_part("chevrons", Rect2(0.04, 0.88, 0.30, 0.07), steel,
			{"count": chevrons}, 2, template_id))
	for i in parts.size():
		parts[i]["z"] = int(parts[i]["z"]) * 1000 + i

	var plate := {
		"key": key, "kind": "unit", "title": String(unit["name"]),
		"scene": scene, "lod": int(ctx.get("lod", 2)), "parts": parts, "cues": cues,
	}
	if _plates.size() >= MAX_PLATE_CACHE:
		_plates.clear()
	_plates[key] = plate
	return plate


func func_add_ranks(parts: Array, formation: String, files: int, ranks: int,
		look: Dictionary, cloth: Dictionary, steel: Dictionary, timber: Dictionary,
		mount: String, seed: String, strength_pct: int) -> void:
	match formation:
		"single":
			parts.append(_part("hull", Rect2(0.14, 0.62, 0.72, 0.22), timber,
				{"oars": 13, "mast": true, "sail": true, "ram": true, "shields": 7}, 1, seed))
			parts.append(_part("crowd", Rect2(0.30, 0.56, 0.40, 0.06), cloth,
				{"count": 7, "depth": 1}, 1, seed))
			return
		"beast":
			parts.append(_part("beasts", Rect2(0.26, 0.54, 0.46, 0.30), timber,
				{"kind": "elephant", "count": 1}, 1, seed))
			parts.append(_part("figure", Rect2(0.44, 0.38, 0.08, 0.18), cloth, look, 1, seed))
			parts.append(_part("crowd", Rect2(0.06, 0.78, 0.18, 0.06), cloth,
				{"count": 3, "depth": 1}, 1, seed))
			return
		"mounted":
			for k in files:
				var x := 0.16 + 0.30 * float(k)
				parts.append(_part("beasts", Rect2(x, 0.68, 0.27, 0.17), timber,
					{"kind": "horse", "count": 1}, 1, seed))
				parts.append(_part("figure", Rect2(x + 0.10, 0.53, 0.085, 0.19), cloth, look, 1, seed))
			return
		"crewed":
			parts.append(_part("posts", Rect2(0.34, 0.62, 0.32, 0.22), timber,
				{"count": 4, "cap": "cross", "rails": 2}, 1, seed))
			parts.append(_part("crowd", Rect2(0.16, 0.78, 0.30, 0.06), cloth,
				{"count": 3, "depth": 1}, 1, seed))
			return
	# Ranked foot. The front rank is drawn as people; everything behind it is a
	# crowd, which already fades with depth.
	var whole := maxi(1, int(ceil(float(files) * float(strength_pct) / 100.0)))
	for k in files:
		var x := 0.10 + 0.78 * (float(k) + 0.5) / float(files)
		if k < whole:
			parts.append(_part("figure", Rect2(x - 0.042, 0.62, 0.084, 0.22), cloth, look, 0, seed))
			if formation == "hedge":
				parts.append(_part("posts", Rect2(x - 0.01, 0.34, 0.02, 0.50), steel,
					{"count": 1, "cap": "point", "rails": 0, "lean": 0.05}, 0, seed))
		else:
			# The gaps in a battered cohort are real information, so show them.
			parts.append(_part("rubble", Rect2(x - 0.03, 0.81, 0.06, 0.03), steel,
				{"count": 2}, 0, seed))
	if ranks > 1:
		parts.append(_part("crowd", Rect2(0.08, 0.76, 0.84, 0.06), cloth,
			{"count": files * (ranks - 1), "depth": maxi(1, ranks - 1), "scale": 1.7,
			 "ranked": formation != "loose", "ragged": formation == "loose"}, 0, seed))
	if formation == "roof":
		parts.append(_part("crest", Rect2(0.12, 0.66, 0.76, 0.04), steel,
			{"style": "ridge", "count": files + 2}, 0, seed))
	if formation == "wall":
		parts.append(_part("crest", Rect2(0.10, 0.80, 0.80, 0.05), steel,
			{"style": "crenel", "count": files + 1}, 0, seed))


func _tunic_material(art: BuildingArt, kit: Dictionary) -> String:
	## Kits carry a tunic colour; the shared material table carries the surface.
	## Homespun is the closest and keeps the house tint faint, which is right:
	## soldiers wear their own cloth, banners wear the family's.
	return "homespun" if art.materials.has("homespun") else "cloth"


func _part(name: String, rect: Rect2, shade: Dictionary, params: Dictionary,
		layer: int, seed: String) -> Dictionary:
	return {
		"part": name, "rect": rect, "shade": shade, "p": params,
		"lod": 0, "z": layer, "seed": "%s#%s" % [seed, name],
	}
