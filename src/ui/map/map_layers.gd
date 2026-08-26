class_name MapLayers
## The campaign map's retained render layers. Each layer is a Node2D (or a
## Control for screen-space labels) drawing in WORLD pixels under MapView's
## _world_root, whose transform carries pan and zoom — so panning re-renders
## cached draw commands instead of re-recording them. Layers redraw only
## when MapView.refresh_state() diffs new campaign state, never per frame.
##
## Draw order (tree order): Terrain, Political, Fog, Units, Overlay — then
## LabelLayer on top in screen space.


class TerrainLayer:
	extends Node2D
	## Land fill, per-region terrain color, topography glyphs, roads, coast.

	var view: MapView

	func _draw() -> void:
		var geometry: MapGeometry = view.geometry
		if geometry == null or view.game == null:
			return
		# Shallow-water halo, then the parchment base that hides any hairline
		# seams between independently simplified province polygons.
		for mass in geometry.landmasses:
			_stroke_ring(mass["outline"], UiStyle.SEA_SHELF, 9.0)
		for mass in geometry.landmasses:
			for piece in mass["fills"]:
				draw_colored_polygon(piece, UiStyle.LAND_BASE)
		for region_id in geometry.cells:
			var terrain := _terrain_of(region_id)
			if terrain == "":
				continue
			var fill: Color = UiStyle.TERRAIN_FILL[terrain]
			fill.a = 0.92
			for piece in geometry.cells[region_id]["fills"]:
				draw_colored_polygon(piece, fill)
		_draw_roads(geometry)
		for region_id in geometry.cells:
			_draw_decor(region_id, _terrain_of(region_id))
		for mass in geometry.landmasses:
			_stroke_ring(mass["outline"], UiStyle.COAST_LINE, 2.2)

	func _terrain_of(region_id: String) -> String:
		return String(view.game.data.regions.get(region_id, {}).get("terrain", ""))

	func _stroke_ring(ring: PackedVector2Array, color: Color, width: float) -> void:
		var closed := PackedVector2Array(ring)
		closed.append(ring[0])
		draw_polyline(closed, color, width, true)

	func _draw_roads(geometry: MapGeometry) -> void:
		for key in geometry.edges:
			var path: PackedVector2Array = geometry.edges[key]
			var level := int(view.road_levels.get(key, 0))
			match level:
				0:
					for i in range(path.size() - 1):
						draw_dashed_line(path[i], path[i + 1],
							Color(UiStyle.ROAD, 0.30), 1.2, 7.0)
				1:
					draw_polyline(path, Color(UiStyle.ROAD, 0.55), 1.8, true)
				2:
					draw_polyline(path, Color(UiStyle.ROAD, 0.75), 2.6, true)
				_:
					draw_polyline(path, Color(UiStyle.ROAD, 0.9), 3.6, true)
					draw_polyline(path, Color(UiStyle.ROAD_PAVED_CORE, 0.8), 1.2, true)

	func _draw_decor(region_id: String, terrain: String) -> void:
		if terrain == "":
			return
		var color: Color = UiStyle.TERRAIN_GLYPH[terrain]
		for point in view.decor_points(region_id):
			match terrain:
				"mountains":
					draw_polyline(PackedVector2Array([
						point + Vector2(-11, 7), point + Vector2(0, -9), point + Vector2(11, 7),
					]), color, 2.2, true)
					draw_line(point + Vector2(0, -9), point + Vector2(4, -2),
						Color(0.93, 0.93, 0.95, 0.8), 1.6, true)
				"hills":
					draw_arc(point + Vector2(0, 3), 8.0, PI, TAU, 10, color, 2.0, true)
				"forest":
					draw_colored_polygon(PackedVector2Array([
						point + Vector2(-6, 3), point + Vector2(6, 3), point + Vector2(0, -9),
					]), color)
					draw_line(point + Vector2(0, 3), point + Vector2(0, 7), color, 1.6, true)
				"marsh":
					draw_line(point + Vector2(-6, 0), point + Vector2(6, 0), color, 1.6, true)
					draw_line(point + Vector2(-4, 4), point + Vector2(4, 4), color, 1.2, true)
				"desert":
					draw_circle(point, 1.6, color)
					draw_circle(point + Vector2(7, 4), 1.2, color)
				"steppe":
					draw_line(point + Vector2(-5, 0), point + Vector2(5, 0), color, 1.5, true)
				_:
					draw_line(point + Vector2(-3, 0), point + Vector2(3, 0), color, 1.2, true)


class PoliticalLayer:
	extends Node2D
	## Owner tints over explored territory; province borders everywhere.

	var view: MapView

	func _draw() -> void:
		var geometry: MapGeometry = view.geometry
		if geometry == null or view.game == null:
			return
		for region_id in geometry.cells:
			if not view.visible_cache.has(region_id):
				continue
			var owner_color = view.owner_colors.get(region_id)
			if owner_color == null:
				continue
			var tint: Color = owner_color
			tint.a = 0.30
			for piece in geometry.cells[region_id]["fills"]:
				draw_colored_polygon(piece, tint)
		for region_id in geometry.cells:
			for polygon in geometry.cells[region_id]["polys"]:
				var closed := PackedVector2Array(polygon)
				closed.append(polygon[0])
				draw_polyline(closed, UiStyle.PROVINCE_BORDER, 1.3, true)


class FogLayer:
	extends Node2D
	## A dark veil over unexplored provinces: the land shows, the life does not.

	var view: MapView

	func _draw() -> void:
		var geometry: MapGeometry = view.geometry
		if geometry == null or view.game == null or view.visible_cache.is_empty():
			return
		for region_id in geometry.cells:
			if view.visible_cache.has(region_id):
				continue
			for piece in geometry.cells[region_id]["fills"]:
				draw_colored_polygon(piece, UiStyle.FOG_VEIL)


class UnitsLayer:
	extends Node2D
	## Settlements, armies, sieges, the capital mark — the living map.

	var view: MapView

	func _draw() -> void:
		var game: Game = view.game
		if game == null:
			return
		var region_ids: Array = game.data.regions.keys()
		region_ids.sort()
		for region_id in region_ids:
			var region: Dictionary = game.data.regions[region_id]
			var anchor := view.world_pos(region)
			if not view.visible_cache.has(region_id):
				if view.geometry == null:
					# Fixture worlds have no fog veil polygons: keep the old
					# grey unknown-token so the map still reads.
					draw_circle(anchor, 9.0, Color(0.16, 0.16, 0.18))
					draw_arc(anchor, 9.0, 0, TAU, 24, Color(0.28, 0.28, 0.30), 1.5)
				continue
			_draw_settlement(region_id, anchor)
			_draw_armies(region_id, anchor)
		_draw_fleets()

	func _draw_settlement(region_id: String, anchor: Vector2) -> void:
		var game: Game = view.game
		var params := SettlementIcons.icon_params(game, region_id)
		if params.is_empty():
			draw_circle(anchor, 8.0, Color(0.5, 0.5, 0.5))
			return
		SettlementIcons.draw_settlement(self, anchor, params)

	func _draw_armies(region_id: String, anchor: Vector2) -> void:
		var game: Game = view.game
		var owners: Dictionary = view.army_groups.get(region_id, {})
		var owner_ids: Array = owners.keys()
		owner_ids.sort()
		var offset := 0
		for army_owner in owner_ids:
			var entry: Dictionary = owners[army_owner]
			var badge_color := Color.html(
				game.data.factions.get(army_owner, {}).get("color", "#808080"))
			SettlementIcons.draw_army_token(self,
				anchor + Vector2(24.0 + offset * 18.0, -14.0), badge_color,
				int(entry["units"]), bool(entry["has_general"]),
				bool(entry["fatigued"]), view.map_font)
			offset += 1

	func _draw_fleets() -> void:
		var game: Game = view.game
		var player_color := Color.html(game.data.factions.get(
			String(game.state["player_faction"]), {}).get("color", "#808080"))
		for zone_id in view.fleet_groups:
			var anchor_data: Dictionary = game.data.sea_zones.get(zone_id, {}).get("position", {})
			if anchor_data.is_empty():
				continue
			var at := Vector2(float(anchor_data["x"]), float(anchor_data["y"])) * MapView.WORLD_SCALE
			SettlementIcons.draw_fleet_token(self, at, player_color,
				int(view.fleet_groups[zone_id]), view.map_font)


class OverlayLayer:
	extends Node2D
	## Selection emphasis and the movement-range tint (highlight_regions).

	var view: MapView

	func _draw() -> void:
		var game: Game = view.game
		if game == null:
			return
		for region_id in view.highlight_regions:
			_paint_region(region_id, UiStyle.RANGE_TINT, UiStyle.RANGE_EDGE, 1.2)
		if view.hover_region != "" and view.hover_region != view.selected_region:
			_paint_region(view.hover_region, Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.55), 1.4)
		if view.selected_region != "":
			_paint_region(view.selected_region,
				Color(UiStyle.SELECTION, 0.06), UiStyle.SELECTION, 2.2)
		_draw_path_preview()

	func _draw_path_preview() -> void:
		var preview: Dictionary = view.path_preview
		if preview.is_empty():
			return
		var game: Game = view.game
		var previous: String = preview["from"]
		var legs: Array = preview["legs"]
		var ink := Color(0.98, 0.97, 0.92, 0.9)
		for leg in legs:
			var next: String = leg["region"]
			var segment := PackedVector2Array()
			if view.geometry != null:
				segment = view.geometry.edge_path(previous, next)
			if segment.is_empty():
				segment = PackedVector2Array([_anchor(previous), _anchor(next)])
			draw_polyline(segment, Color(0.08, 0.08, 0.1, 0.5), 5.0, true)
			draw_polyline(segment, ink, 2.6, true)
			previous = next
		if bool(preview.get("blocked", false)) and preview.has("target"):
			var from_anchor := _anchor(previous)
			var to_anchor := _anchor(String(preview["target"]))
			draw_dashed_line(from_anchor, to_anchor, UiStyle.SIEGE_RED, 2.4, 9.0)
			draw_arc(to_anchor, 14.0, 0, TAU, 24, UiStyle.SIEGE_RED, 2.2)
		# Per-leg cost chips, then the arrival flag.
		if view.map_font != null:
			for leg in legs:
				var at := _anchor(String(leg["region"])) + Vector2(0, -20.0)
				var cost_text := "%.1f" % float(leg["cost"])
				var width := view.map_font.get_string_size(
					cost_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9).x
				draw_circle(at, 7.5, Color(0.09, 0.09, 0.11, 0.85))
				draw_string(view.map_font, at + Vector2(-width / 2.0, 3.2), cost_text,
					HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(0.95, 0.93, 0.85))
			if not legs.is_empty():
				var turns := int(preview.get("turns", 1))
				var flag_text := "this turn" if turns <= 1 else "%d turns" % turns
				var end_at := _anchor(String(legs.back()["region"])) + Vector2(0, -36.0)
				var flag_width := view.map_font.get_string_size(
					flag_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 11).x
				draw_string_outline(view.map_font, end_at + Vector2(-flag_width / 2.0, 0), flag_text,
					HORIZONTAL_ALIGNMENT_CENTER, -1, 11, 4, UiStyle.LABEL_OUTLINE)
				draw_string(view.map_font, end_at + Vector2(-flag_width / 2.0, 0), flag_text,
					HORIZONTAL_ALIGNMENT_CENTER, -1, 11, UiStyle.CAPITAL_GOLD)

	func _anchor(region_id: String) -> Vector2:
		return view.world_pos(view.game.data.regions.get(region_id, {}))

	func _paint_region(region_id: String, fill: Color, edge: Color, width: float) -> void:
		var geometry: MapGeometry = view.geometry
		if geometry != null and geometry.cells.has(region_id) \
				and view.game.data.regions.has(region_id):
			var cell: Dictionary = geometry.cells[region_id]
			for piece in cell["fills"]:
				draw_colored_polygon(piece, fill)
			for polygon in cell["polys"]:
				var closed := PackedVector2Array(polygon)
				closed.append(polygon[0])
				draw_polyline(closed, edge, width, true)
		elif view.game.data.regions.has(region_id):
			var anchor := view.world_pos(view.game.data.regions[region_id])
			draw_arc(anchor, 16.0, 0, TAU, 32, edge, width + 1.0)


class LabelLayer:
	extends Control
	## Screen-space settlement names: fixed type size, outlined for contrast,
	## revealed by zoom in order of importance.

	var view: MapView

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var game: Game = view.game
		if game == null or view.map_font == null:
			return
		var zoom := view._zoom
		# Sea names at their authored anchors, faint and wide.
		if zoom >= 0.45:
			for zone_id in game.data.sea_zones:
				var anchor_data: Dictionary = game.data.sea_zones[zone_id].get("position", {})
				if anchor_data.is_empty():
					continue
				var sea_name: String = game.data.sea_zones[zone_id].get("name", zone_id)
				var at := view.to_screen(Vector2(
					float(anchor_data["x"]), float(anchor_data["y"])) * MapView.WORLD_SCALE)
				var sea_width := view.map_font.get_string_size(
					sea_name, HORIZONTAL_ALIGNMENT_CENTER, -1, 13).x
				draw_string(view.map_font, at + Vector2(-sea_width / 2.0, -14.0), sea_name,
					HORIZONTAL_ALIGNMENT_CENTER, -1, 13, UiStyle.SEA_LABEL)
		for region_id in view.visible_cache:
			var region: Dictionary = game.data.regions.get(region_id, {})
			if region.is_empty():
				continue
			var settlement: Dictionary = game.state["settlements"].get(region_id, {})
			var tier := 1
			if not settlement.is_empty():
				tier = Constants.level_index(
					SettlementRules.settlement_level(game.data, settlement)) + 1
			if zoom < _reveal_zoom(tier):
				continue
			var text: String = region.get("settlement_name", region_id)
			var font_size := 11 + tier
			var screen := view.to_screen(view.world_pos(region))
			var width := view.map_font.get_string_size(
				text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
			var at := screen + Vector2(-width / 2.0, (7.0 + 1.8 * tier) * zoom + 14.0)
			draw_string_outline(view.map_font, at, text,
				HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, 4, UiStyle.LABEL_OUTLINE)
			draw_string(view.map_font, at, text,
				HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, UiStyle.LABEL_INK)

	func _reveal_zoom(tier: int) -> float:
		match tier:
			6, 5: return 0.0
			4: return 0.4
			3: return 0.55
			2: return 0.7
			_: return 0.85
