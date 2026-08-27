class_name MapLayers
extends RefCounted
## The campaign map's retained draw layers, bottom to top: terrain (land,
## tints, decor, coasts, roads), political (owner tints, borders, settlement
## icons), fog, units, overlay (selection, range, path), and a screen-space
## label layer. Each is a Node2D that reads the owning MapView's caches and
## redraws only when that view marks it dirty — pan and zoom never re-record
## a single draw call, they only move the parent transform.

const LAND_COLOR := Color(0.76, 0.70, 0.56)
const COAST_COLOR := Color(0.47, 0.57, 0.62, 0.85)
const SEA_LANE_COLOR := Color(0.30, 0.46, 0.58, 0.30)
const ROAD_DIRT := Color(0.46, 0.38, 0.27, 0.65)
const ROAD_PAVED := Color(0.60, 0.55, 0.44, 0.9)
const BORDER_ALPHA := 0.85
const OWNER_TINT_ALPHA := 0.28
const FOG_VEIL := Color(0.10, 0.11, 0.14, 0.62)
const FOG_TOKEN := Color(0.16, 0.16, 0.18)

const TERRAIN_TINTS := {
	"plains": Color(0.62, 0.68, 0.42, 0.5),
	"forest": Color(0.38, 0.52, 0.33, 0.5),
	"hills": Color(0.68, 0.62, 0.40, 0.5),
	"mountains": Color(0.58, 0.54, 0.50, 0.55),
	"desert": Color(0.80, 0.72, 0.48, 0.55),
	"steppe": Color(0.70, 0.68, 0.45, 0.5),
	"marsh": Color(0.46, 0.58, 0.47, 0.5),
}
const DECOR_DENSITY := {  # glyph count per cell by terrain, scaled by zoom bucket
	"mountains": 5, "hills": 4, "forest": 5, "marsh": 3, "desert": 4, "steppe": 2, "plains": 2,
}


class TerrainLayer:
	extends Node2D
	var view  # MapView

	func _draw() -> void:
		var geometry = view.geometry()
		if geometry == null:
			_draw_fallback()
			return
		for landmass in geometry.landmasses:
			for tri in landmass["tris"]:
				draw_colored_polygon(tri, MapLayers.LAND_COLOR)
		for region_id in view.sorted_region_ids():
			_draw_cell_terrain(geometry, region_id)
		for landmass in geometry.landmasses:
			for tri in landmass["hole_tris"]:
				draw_colored_polygon(tri, view.SEA_COLOR)
			draw_polyline(_closed(landmass["outline"]), MapLayers.COAST_COLOR, 1.6)
			for hole in landmass["holes"]:
				draw_polyline(_closed(hole), MapLayers.COAST_COLOR, 1.2)
		_draw_sea_lanes()
		_draw_roads(geometry)

	func _draw_cell_terrain(geometry, region_id: String) -> void:
		var cell: Dictionary = geometry.cells.get(region_id, {})
		if cell.is_empty():
			return
		var terrain: String = view.game.data.regions[region_id].get("terrain", "plains")
		var tint: Color = MapLayers.TERRAIN_TINTS.get(terrain, MapLayers.TERRAIN_TINTS["plains"])
		for tri in cell["tris"]:
			draw_colored_polygon(tri, tint)
		_draw_decor(cell, region_id, terrain)

	func _draw_decor(cell: Dictionary, region_id: String, terrain: String) -> void:
		var bucket: int = view.zoom_bucket()
		if bucket <= 0:
			return
		var budget: int = MapLayers.DECOR_DENSITY.get(terrain, 2)
		if bucket >= 2:
			budget += budget / 2 + 1
		var bounds: Rect2 = cell["bounds"]
		var seed_hash := SettlementIcons._fnv(region_id)
		var placed := 0
		var attempt := 0
		while placed < budget and attempt < budget * 4:
			var fx := float(SettlementIcons._fnv_step(seed_hash, attempt * 2) % 1000) / 1000.0
			var fy := float(SettlementIcons._fnv_step(seed_hash, attempt * 2 + 1) % 1000) / 1000.0
			attempt += 1
			var spot := bounds.position + Vector2(bounds.size.x * fx, bounds.size.y * fy)
			var inside := false
			for polygon in cell["polygons"]:
				if Geometry2D.is_point_in_polygon(spot, polygon):
					inside = true
					break
			if not inside:
				continue
			_draw_glyph(terrain, spot, SettlementIcons._fnv_step(seed_hash, attempt))
			placed += 1

	func _draw_glyph(terrain: String, spot: Vector2, jitter: int) -> void:
		var size := 4.0 + float(jitter % 30) / 10.0
		match terrain:
			"mountains":
				var ink := Color(0.42, 0.38, 0.35, 0.85)
				draw_polyline(PackedVector2Array([
					spot + Vector2(-size, size * 0.5), spot + Vector2(0, -size * 0.7),
					spot + Vector2(size, size * 0.5)]), ink, 1.4)
				draw_line(spot + Vector2(0, -size * 0.7), spot + Vector2(size * 0.28, -size * 0.2),
					Color(0.9, 0.9, 0.92, 0.8), 1.2)  # snow flank
			"hills":
				draw_arc(spot, size * 0.7, PI, TAU, 10, Color(0.5, 0.44, 0.3, 0.8), 1.3)
			"forest":
				var green := Color(0.24, 0.38, 0.22, 0.9)
				draw_colored_polygon(PackedVector2Array([
					spot + Vector2(-size * 0.55, size * 0.4), spot + Vector2(size * 0.55, size * 0.4),
					spot + Vector2(0, -size * 0.8)]), green)
				draw_line(spot + Vector2(0, size * 0.4), spot + Vector2(0, size * 0.75),
					Color(0.35, 0.27, 0.18, 0.9), 1.1)
			"marsh":
				var reed := Color(0.3, 0.45, 0.4, 0.8)
				for i in range(3):
					var y := spot.y + float(i) * 1.6 - 1.6
					draw_line(Vector2(spot.x - size * 0.6 + float(i % 2), y),
						Vector2(spot.x + size * 0.6 - float(i % 2), y), reed, 1.0)
			"desert":
				var sand := Color(0.62, 0.52, 0.34, 0.8)
				for i in range(4):
					var offset := Vector2(float(i % 2) * 2.4 - 1.2, floorf(i / 2.0) * 2.2 - 1.1)
					draw_circle(spot + offset, 0.7, sand)
			"steppe", "plains":
				var grass := Color(0.42, 0.5, 0.28, 0.7)
				draw_line(spot + Vector2(-1.4, 1.0), spot + Vector2(-0.8, -1.2), grass, 1.0)
				draw_line(spot + Vector2(0.6, 1.0), spot + Vector2(1.2, -1.2), grass, 1.0)

	func _draw_sea_lanes() -> void:
		var drawn := {}
		var zone_ids: Array = view.game.data.sea_zones.keys()
		zone_ids.sort()
		for zone_id in zone_ids:
			var anchor: Vector2 = view.zone_anchor(zone_id)
			for other_id in view.game.data.sea_zones[zone_id].get("adjacent", []):
				var key: String = zone_id + "|" + other_id if zone_id < String(other_id) else String(other_id) + "|" + zone_id
				if drawn.has(key):
					continue
				drawn[key] = true
				draw_dashed_line(anchor, view.zone_anchor(other_id), MapLayers.SEA_LANE_COLOR, 1.2, 10.0)

	func _draw_roads(geometry) -> void:
		var keys: Array = geometry.edges.keys()
		keys.sort()
		for key in keys:
			var ends: PackedStringArray = String(key).split("|")
			var level: int = maxi(view.road_level(ends[0]), view.road_level(ends[1]))
			var path: PackedVector2Array = geometry.edges[key]
			if level <= 0:
				for i in range(path.size() - 1):
					draw_dashed_line(path[i], path[i + 1], MapLayers.ROAD_DIRT, 1.1, 6.0)
			else:
				draw_polyline(path, MapLayers.ROAD_PAVED, 1.2 + 0.4 * level)

	func _draw_fallback() -> void:
		# No geometry (synthetic fixture worlds): plain adjacency roads.
		var region_ids: Array = view.game.data.regions.keys()
		region_ids.sort()
		for region_id in region_ids:
			var region: Dictionary = view.game.data.regions[region_id]
			for neighbor in region.get("adjacent", []):
				if String(neighbor) < String(region_id):
					continue
				draw_line(view.world_pos(region), view.world_pos(view.game.data.regions[neighbor]),
					Color(0.45, 0.38, 0.28, 0.5), 1.5)

	func _closed(points: PackedVector2Array) -> PackedVector2Array:
		var loop := points.duplicate()
		loop.append(points[0])
		return loop


class PoliticalLayer:
	extends Node2D
	var view

	func _draw() -> void:
		var geometry = view.geometry()
		for region_id in view.sorted_region_ids():
			if not view.visible_cache().has(region_id):
				continue
			var settlement: Dictionary = view.game.state["settlements"].get(region_id, {})
			if settlement.is_empty():
				continue
			var owner_color: Color = view.faction_color(settlement["owner"])
			if geometry != null:
				var cell: Dictionary = geometry.cells.get(region_id, {})
				var tint := owner_color
				tint.a = MapLayers.OWNER_TINT_ALPHA
				for tri in cell.get("tris", []):
					draw_colored_polygon(tri, tint)
				var border := owner_color.darkened(0.2)
				border.a = MapLayers.BORDER_ALPHA
				for polygon in cell.get("polygons", []):
					var loop: PackedVector2Array = polygon.duplicate()
					loop.append(polygon[0])
					draw_polyline(loop, border, 1.3)
				var params: Dictionary = view.icon_cache().get(region_id, {})
				if not params.is_empty():
					SettlementIcons.draw_settlement(self, view.world_pos(view.game.data.regions[region_id]),
						params, owner_color)
			else:
				_draw_token(region_id, settlement, owner_color)

	func _draw_token(region_id: String, settlement: Dictionary, owner_color: Color) -> void:
		# Fixture fallback: the classic tiered disc.
		var center: Vector2 = view.world_pos(view.game.data.regions[region_id])
		var tier: int = Constants.level_index(SettlementRules.settlement_level(view.game.data, settlement)) + 1
		var radius := 7.0 + 1.8 * tier
		draw_circle(center, radius, owner_color)
		draw_arc(center, radius, 0, TAU, 32, Color(0, 0, 0, 0.55), 1.5)
		if settlement.get("siege") != null:
			draw_arc(center, radius + 7.0, 0, TAU, 32, Color(0.9, 0.25, 0.15), 2.5)


class FogLayer:
	extends Node2D
	var view

	func _draw() -> void:
		var geometry = view.geometry()
		for region_id in view.sorted_region_ids():
			if view.visible_cache().has(region_id):
				continue
			if geometry != null:
				var cell: Dictionary = geometry.cells.get(region_id, {})
				for tri in cell.get("tris", []):
					draw_colored_polygon(tri, MapLayers.FOG_VEIL)
			else:
				var center: Vector2 = view.world_pos(view.game.data.regions[region_id])
				draw_circle(center, 9.0, MapLayers.FOG_TOKEN)
				draw_arc(center, 9.0, 0, TAU, 24, Color(0.28, 0.28, 0.30), 1.5)


class UnitsLayer:
	extends Node2D
	var view

	func _draw() -> void:
		var font: Font = view.map_font()
		var region_ids: Array = view.sorted_region_ids()
		for region_id in region_ids:
			if not view.visible_cache().has(region_id):
				continue
			var stacks := {}
			var army_ids: Array = view.game.state["armies"].keys()
			army_ids.sort()
			for army_id in army_ids:
				var army: Dictionary = view.game.state["armies"][army_id]
				if army["region"] != region_id:
					continue
				var stack: Dictionary = stacks.get(army["owner"],
					{"units": 0, "general": false, "fatigued": false})
				stack["units"] += army["units"].size()
				stack["general"] = stack["general"] or army["general"] != null
				stack["fatigued"] = stack["fatigued"] or bool(army.get("forced_march", false))
				stacks[army["owner"]] = stack
			var center: Vector2 = view.world_pos(view.game.data.regions[region_id])
			var params: Dictionary = view.icon_cache().get(region_id, {})
			var radius := SettlementIcons.footprint_radius(int(params.get("level", 0))) + 6.0
			var owner_ids: Array = stacks.keys()
			owner_ids.sort()
			var slot := 0
			for owner in owner_ids:
				var stack: Dictionary = stacks[owner]
				SettlementIcons.draw_army_token(self,
					center + Vector2(radius + 8.0 + 16.0 * slot, -radius * 0.4),
					view.faction_color(owner), int(stack["units"]),
					bool(stack["general"]), bool(stack["fatigued"]), font)
				slot += 1
		_draw_fleets(font)

	func _draw_fleets(font: Font) -> void:
		# Own fleets only: fog never tracks the open sea, so nothing else may
		# be shown without leaking.
		var player: String = view.game.state["player_faction"]
		var by_zone := {}
		var fleet_ids: Array = view.game.state["fleets"].keys()
		fleet_ids.sort()
		for fleet_id in fleet_ids:
			var fleet: Dictionary = view.game.state["fleets"][fleet_id]
			if fleet["owner"] != player:
				continue
			var zone: String = fleet["sea_zone"]
			by_zone[zone] = int(by_zone.get(zone, 0)) + fleet["ships"].size()
		var zone_ids: Array = by_zone.keys()
		zone_ids.sort()
		for zone_id in zone_ids:
			SettlementIcons.draw_fleet_token(self, view.zone_anchor(zone_id),
				view.faction_color(player), int(by_zone[zone_id]), font)


class OverlayLayer:
	extends Node2D
	var view

	func _draw() -> void:
		var geometry = view.geometry()
		for region_id in view.sorted_highlight_ids():
			var kind: String = str(view.highlight_regions[region_id])
			var glow := Color(1.0, 0.95, 0.6, 0.24) if kind != "forced" else Color(1.0, 0.62, 0.35, 0.18)
			_fill_region(geometry, region_id, glow)
		var path: PackedVector2Array = view.path_preview_points()
		if path.size() >= 2:
			draw_polyline(path, Color(0.12, 0.09, 0.04, 0.8), 4.4)
			draw_polyline(path, Color(0.97, 0.84, 0.38, 0.95), 2.2)
			draw_circle(path[path.size() - 1], 3.4, Color(0.97, 0.84, 0.38))
		if view.path_preview_blocked().size() >= 2:
			var blocked: PackedVector2Array = view.path_preview_blocked()
			for i in range(blocked.size() - 1):
				draw_dashed_line(blocked[i], blocked[i + 1], Color(0.95, 0.35, 0.25, 0.95), 2.4, 7.0)
		if view.hover_region != "" and view.hover_region != view.selected_region:
			_stroke_region(geometry, view.hover_region, Color(1, 1, 1, 0.45), 1.6)
		if view.selected_region != "":
			_stroke_region(geometry, view.selected_region, Color.WHITE, 2.4)
		for zone_id in view.sorted_zone_highlight_ids():
			var anchor: Vector2 = view.zone_anchor(zone_id)
			if str(view.highlight_zones[zone_id]) == "selected":
				draw_arc(anchor, 16.0, 0, TAU, 28, Color(1, 1, 1, 0.95), 2.4)
			else:
				draw_arc(anchor, 18.0, 0, TAU, 28, Color(0.95, 0.9, 0.55, 0.75), 2.0)

	func _fill_region(geometry, region_id: String, color: Color) -> void:
		if geometry != null:
			for tri in geometry.cells.get(region_id, {}).get("tris", []):
				draw_colored_polygon(tri, color)
		elif view.game.data.regions.has(region_id):
			var solid := color
			solid.a = minf(1.0, color.a * 3.0)
			draw_arc(view.world_pos(view.game.data.regions[region_id]), 16.0, 0, TAU, 24, solid, 2.0)

	func _stroke_region(geometry, region_id: String, color: Color, width: float) -> void:
		if not view.game.data.regions.has(region_id):
			return
		if geometry != null:
			for polygon in geometry.cells.get(region_id, {}).get("polygons", []):
				var loop: PackedVector2Array = polygon.duplicate()
				loop.append(polygon[0])
				draw_polyline(loop, color, width)
		else:
			draw_arc(view.world_pos(view.game.data.regions[region_id]), 18.0, 0, TAU, 32, color, width)


class LabelLayer:
	extends Node2D
	## Screen-space: text keeps its size while the world zooms under it.
	var view

	func _draw() -> void:
		var font: Font = view.map_font()
		if font == null:
			return
		var zoom: float = view._zoom
		if zoom >= 0.4:
			var zone_ids: Array = view.game.data.sea_zones.keys()
			zone_ids.sort()
			for zone_id in zone_ids:
				var zone_name: String = view.game.data.sea_zones[zone_id].get("name", zone_id)
				var at: Vector2 = view.to_screen(view.zone_anchor(zone_id))
				var width := font.get_string_size(zone_name, HORIZONTAL_ALIGNMENT_CENTER, -1, 11).x
				draw_string(font, at + Vector2(-width / 2.0, 0), zone_name,
					HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(0.55, 0.68, 0.78, 0.75))
		if zoom < 0.55:
			return
		for region_id in view.sorted_region_ids():
			if not view.visible_cache().has(region_id):
				continue
			if not view.game.state["settlements"].has(region_id):
				continue
			var region: Dictionary = view.game.data.regions[region_id]
			var label: String = region.get("settlement_name", region_id)
			var params: Dictionary = view.icon_cache().get(region_id, {})
			var radius := SettlementIcons.footprint_radius(int(params.get("level", 0)))
			var at: Vector2 = view.to_screen(view.world_pos(region)) + Vector2(0, (radius + 6.0) * zoom + 11.0)
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12).x
			draw_string(font, at + Vector2(-width / 2.0, 0), label,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.94, 0.90, 0.80))
			if params.get("capital", false):
				draw_string(font, at + Vector2(width / 2.0 + 3.0, 0), "★",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.85, 0.4))
		for chip in view.path_chips():
			var chip_text: String = chip["text"]
			var chip_at: Vector2 = view.to_screen(chip["at"]) + Vector2(7, -7)
			var chip_width := font.get_string_size(chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_rect(Rect2(chip_at + Vector2(-3, -10), Vector2(chip_width + 6, 14)),
				Color(0.04, 0.07, 0.1, 0.7))
			draw_string(font, chip_at, chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.98, 0.94, 0.7))
