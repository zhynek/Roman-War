class_name BuildingArt
extends RefCounted
## Resolves a building level into a plate: an ordered, colour-resolved part list
## in normalised 0..1 stage coordinates, ready for ArtPainter. The game ships no
## image files, so this and the painter ARE the artwork.
##
## Pure by construction, on the MapGeometry pattern: RefCounted, no Node, no
## RNG, cached per GameData in a static dict. It may read GameData; it must
## never read GameState. Everything mutable — which tier stands, the season, the
## owner's colour, the region's terrain — arrives in an explicit `ctx`, which is
## what makes "the same building always looks the same" a one-line test.
##
## Tiers are cumulative deltas (add / drop / set plus a material), so a level-5
## barracks is a different building from a level-1 muster field rather than the
## same shape scaled up.

const MAX_PARTS := 72
const MAX_PLATE_CACHE := 512
const STAGE_ASPECT := 1.6
const LAYERS := {"back": 0, "main": 1, "front": 2}
const FALLBACK_TRACK := ["timber", "rubble", "rubble", "ashlar", "ashlar", "ashlar"]

static var _cache := {}

var materials := {}
var tracks := {}
var fragments := {}
var cults := {}
var emblems := {}
var recipes: Array = []
var load_errors: PackedStringArray = []

var _by_chain := {}
var _by_kind_culture := {}
var _by_kind := {}
var _generic := {}
var _plates := {}
var _shades := {}


static func for_data(data) -> BuildingArt:
	var key: int = data.get_instance_id()
	if not _cache.has(key):
		_cache.clear()
		var art := BuildingArt.new()
		art.load_from("res://data/building_art.json")
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
	materials = parsed.get("materials", {})
	tracks = parsed.get("tracks", {})
	fragments = parsed.get("fragments", {})
	cults = parsed.get("cults", {})
	emblems = parsed.get("emblems", {})
	recipes = parsed.get("recipes", [])
	for recipe in recipes:
		for chain_id in recipe.get("chains", []):
			_by_chain[chain_id] = recipe
		for kind in recipe.get("kinds", []):
			var cultures: Array = recipe.get("cultures", [])
			if cultures.is_empty():
				_by_kind[kind] = recipe
			else:
				for culture in cultures:
					_by_kind_culture["%s|%s" % [kind, culture]] = recipe
		if recipe["id"] == "generic":
			_generic = recipe
	if _generic.is_empty():
		load_errors.append("no recipe with id 'generic': nothing to fall back to")


func recipe_for(chain_id: String, kind: String, culture: String) -> Dictionary:
	## Most specific wins, and the last rung always exists.
	if _by_chain.has(chain_id):
		return _by_chain[chain_id]
	var pair := "%s|%s" % [kind, culture]
	if _by_kind_culture.has(pair):
		return _by_kind_culture[pair]
	if _by_kind.has(kind):
		return _by_kind[kind]
	return _generic


func building_plate(data, level_id: String, ctx: Dictionary) -> Dictionary:
	## ctx: {culture, terrain, fertility, season, tint: Color, progress: float,
	## damaged: bool, lod: int}. The panel assembles it; this class never looks
	## at GameState itself.
	var cache_key := _plate_key(level_id, ctx)
	if _plates.has(cache_key):
		return _plates[cache_key]

	var entry: Dictionary = data.building_levels.get(level_id, {})
	var chain_id: String = entry.get("chain", "")
	var chain: Dictionary = data.chains.get(chain_id, {})
	var kind: String = entry.get("kind", "")
	var culture := String(ctx.get("culture", ""))
	if culture == "":
		var cultures: Array = chain.get("cultures", [])
		culture = String(cultures[0]) if not cultures.is_empty() else "neutral"

	var recipe := recipe_for(chain_id, kind, culture)
	var levels: Array = chain.get("levels", [])
	var tier := clampi(int(entry.get("index", 1)), 1, maxi(levels.size(), 1))
	var title := String(entry.get("level", {}).get("name", level_id))

	var plate := {
		"key": cache_key,
		"kind": "building",
		"title": title,
		"recipe": String(recipe.get("id", "generic")),
		"scene": _scene_of(recipe, ctx),
		"lod": int(ctx.get("lod", 2)),
		"parts": _resolve(recipe, chain, tier, culture, ctx, level_id),
	}
	if _plates.size() >= MAX_PLATE_CACHE:
		# Bounded: re-resolving costs microseconds, a runaway dictionary does not.
		_plates.clear()
	_plates[cache_key] = plate
	return plate


func primitive_estimate(plate: Dictionary) -> int:
	## A rough draw-call count per plate, so a test can hold the budget without
	## rasterising anything.
	var total := 24  # sky, ground, horizon, shadow, chrome
	for part in plate.get("parts", []):
		total += _COST.get(String(part["part"]), 6)
		var p: Dictionary = part.get("p", {})
		for key in ["columns", "count", "courses", "ribs", "oars", "rows", "puffs", "piles"]:
			total += int(p.get(key, 0))
	return total


const _COST := {
	"column_row": 8, "arcade": 6, "crowd": 6, "figure": 14, "hull": 10,
	"posts": 4, "roof": 6, "box": 8, "field_strips": 4, "stones": 6,
}


func _plate_key(level_id: String, ctx: Dictionary) -> String:
	var tint: Color = ctx.get("tint", Color(0.6, 0.6, 0.6))
	return "%s|%s|%s|%d|%d|%s|%s" % [
		level_id, ctx.get("culture", ""), ctx.get("season", "summer"),
		int(ctx.get("lod", 2)), int(round(float(ctx.get("progress", 1.0)) * 4.0)),
		"d" if bool(ctx.get("damaged", false)) else "-", tint.to_html(false)]


func _scene_of(recipe: Dictionary, ctx: Dictionary) -> Dictionary:
	var scene: Dictionary = (recipe.get("scene", {}) as Dictionary).duplicate(true)
	scene["terrain"] = String(ctx.get("terrain", "plains"))
	scene["fertility"] = float(ctx.get("fertility", 1.5))
	scene["season"] = String(ctx.get("season", "summer"))
	scene["progress"] = float(ctx.get("progress", 1.0))
	scene["damaged"] = bool(ctx.get("damaged", false))
	if not scene.has("ground"):
		scene["ground"] = 0.80
	if not scene.has("horizon"):
		scene["horizon"] = 0.56
	if not scene.has("sky"):
		scene["sky"] = "clear"
	if not scene.has("flora"):
		scene["flora"] = "olive"
	if not scene.has("figures"):
		scene["figures"] = [[0.11, 0.87]]
	return scene


func _resolve(recipe: Dictionary, chain: Dictionary, tier: int, culture: String,
		ctx: Dictionary, seed_id: String) -> Array:
	var named := {}
	var order: Array = []
	for part in recipe.get("base", []):
		_admit(part.duplicate(true), named, order)

	var tiers: Array = recipe.get("tiers", [])
	var material := "$track"
	# Clamp rather than bail: a 6-tier government chain against a 5-tier recipe
	# repeats the top rung instead of resolving to nothing.
	for step in mini(tier, tiers.size()):
		var delta: Dictionary = tiers[step]
		material = String(delta.get("material", material))
		for name in delta.get("drop", []):
			named.erase(String(name))
			order.erase(String(name))
		var patches: Dictionary = delta.get("set", {})
		var patch_names: Array = patches.keys()
		patch_names.sort()
		for name in patch_names:
			if named.has(name):
				_merge(named[name], patches[name])
		for part in delta.get("add", []):
			_admit(part.duplicate(true), named, order)

	var archetype := String(chain.get("archetype", ""))
	if archetype != "" and cults.has(archetype):
		var cult: Dictionary = cults[archetype]
		if tier >= int(cult.get("from_tier", 1)):
			for part in cult.get("add", []):
				_admit(part.duplicate(true), named, order)

	var flat: Array = []
	for name in order:
		_flatten(named[name], flat, Rect2(0, 0, 1, 1), material, culture, tier,
			ctx, chain, seed_id, 0)
	# layer * 1000 + insertion index: Array.sort_custom is NOT stable, so
	# sorting on layer alone would reshuffle equal-layer parts run to run.
	flat.sort_custom(func(a, b): return int(a["z"]) < int(b["z"]))
	if flat.size() > MAX_PARTS:
		flat.resize(MAX_PARTS)
	return flat


func _admit(part: Dictionary, named: Dictionary, order: Array) -> void:
	var name := String(part.get("name", ""))
	if name == "":
		name = "_%d" % order.size()
		part["name"] = name
	if not named.has(name):
		order.append(name)
	named[name] = part


func _merge(part: Dictionary, patch: Dictionary) -> void:
	for key in patch:
		if key == "p":
			var params: Dictionary = part.get("p", {})
			for inner in patch["p"]:
				params[inner] = patch["p"][inner]
			part["p"] = params
		else:
			part[key] = patch[key]


func _flatten(part: Dictionary, out: Array, frame: Rect2, material: String,
		culture: String, tier: int, ctx: Dictionary, chain: Dictionary,
		seed_id: String, depth: int) -> void:
	var at: Array = part.get("at", [0.5, 0.8])
	var size: Array = part.get("size", [0.2, 0.2])
	# One anchor rule: `at` is the part's BOTTOM CENTRE, so buildings stand on
	# the ground and grow upward, and a floating temple is unauthorable.
	var local := Rect2(
		float(at[0]) - float(size[0]) * 0.5, float(at[1]) - float(size[1]),
		float(size[0]), float(size[1]))
	var rect := Rect2(frame.position + local.position * frame.size, local.size * frame.size)

	if part.has("use"):
		if depth >= 2:
			return  # fragments never nest deeper; the schema keeps them shallow too
		var fragment: Dictionary = fragments.get(String(part["use"]), {})
		if fragment.is_empty():
			return
		var params: Dictionary = (fragment.get("params", {}) as Dictionary).duplicate()
		for key in part.get("p", {}):
			params[key] = part["p"][key]
		for inner in fragment.get("parts", []):
			var bound := _substitute(inner.duplicate(true), params)
			if not bound.has("mat"):
				bound["mat"] = part.get("mat", material)
			if part.has("layer") and not bound.has("layer"):
				bound["layer"] = part["layer"]
			_flatten(bound, out, rect, material, culture, tier, ctx, chain, seed_id, depth + 1)
		return

	var mat := String(part.get("mat", material))
	if mat == "$track":
		mat = _track_material(culture, tier)
	var tint: Color = ctx.get("tint", Color(0.6, 0.6, 0.6))
	var winter := 1.0 if String(ctx.get("season", "summer")) == "winter" else 0.0

	out.append({
		"part": String(part.get("part", "box")),
		"rect": rect,
		"shade": shade_of(mat, tint, winter),
		"p": _resolve_params(part.get("p", {}), chain),
		"lod": int(part.get("lod", 0)),
		"z": int(LAYERS.get(String(part.get("layer", "main")), 1)) * 1000 + out.size(),
		"seed": "%s#%d" % [seed_id, out.size()],
	})


func _substitute(part: Dictionary, params: Dictionary) -> Dictionary:
	for key in ["mat", "part", "layer"]:
		if part.has(key) and typeof(part[key]) == TYPE_STRING \
				and String(part[key]).begins_with("$"):
			var name := String(part[key]).substr(1)
			if params.has(name):
				part[key] = params[name]
	var inner: Dictionary = part.get("p", {})
	var bound := {}
	for key in inner:
		var value = inner[key]
		if typeof(value) == TYPE_STRING and String(value).begins_with("$"):
			var name := String(value).substr(1)
			bound[key] = params.get(name, value)
		else:
			bound[key] = value
	part["p"] = bound
	return part


func _resolve_params(params: Dictionary, chain: Dictionary) -> Dictionary:
	## $emblem is the one late-bound token: it names the god of THIS temple
	## chain, so 35 gods cost 35 one-line entries rather than 35 recipes.
	var out := {}
	for key in params:
		var value = params[key]
		if typeof(value) == TYPE_STRING and String(value) == "$emblem":
			out[key] = String(emblems.get(chain.get("id", ""), {}).get("emblem", "disc"))
		else:
			out[key] = value
	return out


func _track_material(culture: String, tier: int) -> String:
	var lane: Array = tracks.get(culture, [])
	if lane.is_empty():
		lane = FALLBACK_TRACK
	return String(lane[clampi(tier - 1, 0, lane.size() - 1)])


func shade_of(material: String, tint: Color, winter: float) -> Dictionary:
	## The same five-key dictionary MapView._rebuild_ownership builds per
	## province, so a plate and the map read as one drawing. The numbers alone
	## do the work: timber gets a wide warm range, soft ink and five grain
	## strokes; marble a narrow pale range, hard ink and one.
	var key := "%s|%s|%d" % [material, tint.to_html(false), int(winter * 2.0)]
	if _shades.has(key):
		return _shades[key]
	var spec: Dictionary = materials.get(material, {})
	var mid := Color.html(String(spec.get("mid", "#8a8377")))
	var lit := Color.html(String(spec.get("lit", "#a49c8e")))
	var dark := Color.html(String(spec.get("shadow", "#544f47")))
	var pull := float(spec.get("tint", 0.0))
	if pull > 0.0:
		mid = mid.lerp(tint, pull)
		lit = lit.lerp(tint, pull)
		dark = dark.lerp(tint, pull)
	if winter > 0.0:
		var cold := Color(0.78, 0.83, 0.90)
		mid = mid.lerp(cold, 0.10 * winter)
		lit = lit.lerp(ReliefGlyphs.SNOW, 0.16 * winter)
		dark = dark.lerp(cold, 0.06 * winter)
	var grain := float(spec.get("grain", 0.5))
	var shade := {
		"lit": lit, "mid": mid, "shadow": dark,
		"ink": Color(mid.darkened(0.66), float(spec.get("ink", 0.5))),
		"grain": Color(mid.darkened(0.22), 0.08 + 0.24 * grain),
		"water": Color(0.259, 0.400, 0.451, 0.55),
		"furrow": Color(mid.darkened(0.30), 0.22),
		"edge": float(spec.get("edge", 0.8)),
		"strokes": int(round(grain * 6.0)),
		"snow": winter > 0.0,
	}
	_shades[key] = shade
	return shade
