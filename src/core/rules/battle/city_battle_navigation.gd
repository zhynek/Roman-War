class_name CityBattleNavigation
## Deterministic street navigation in centimetres. No scene/physics query.
## Streets and the Forum are traversable; buildings, fountain and walls are not.

static func point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func packed(value: Vector2) -> Array:
	return [roundi(value.x), roundi(value.y)]

static func clear(layout: Dictionary, tuning: Dictionary, p: Vector2, breached: bool = true) -> bool:
	var m := p / 100.0
	var pad := float(tuning["clearance_cm"]) / 100.0
	var wall := float(layout["walls"]["half_extent"])
	var spatial: Dictionary = layout["battle"]["spatial"]
	var wall_depth := float(spatial["wall_half_depth_cm"])/100.0
	if absf(m.x) >= wall - pad or m.y <= -wall + pad or m.y > float(layout["extent"]) * 0.5 - pad:
		return false
	if m.y >= wall - wall_depth and (absf(m.x) > float(layout["walls"]["gate_width"]) * 0.5 - pad or not breached):
		if m.y < wall + wall_depth:
			return false
	for building in layout["buildings"]:
		var at := point(building["position"])
		var half := point(building["size"]) * 0.5 + Vector2.ONE * pad
		if absf(m.x-at.x) < half.x and absf(m.y-at.y) < half.y:
			return false
	if m.distance_to(point(layout["water_position"])) < float(spatial["fountain_radius_cm"])/100.0 + pad:
		return false
	var forum: Dictionary = layout["forum"]
	var fp := point(forum["position"])
	var fs := point(forum["size"]) * 0.5 - Vector2.ONE * pad
	if absf(m.x-fp.x) <= fs.x and absf(m.y-fp.y) <= fs.y:
		return true
	# Deployment ground immediately outside the south gate, on existing terrain.
	if m.y >= wall + wall_depth and absf(m.x) <= float(spatial["approach_half_width_cm"])/100.0:
		return true
	if absf(m.x) <= float(layout["walls"]["gate_width"]) * 0.5-pad and m.y >= wall-float(spatial["gate_join_cm"])/100.0:
		return true
	for road in layout["roads"]:
		for index in range(road["points"].size()-1):
			var a := point(road["points"][index])
			var b := point(road["points"][index+1])
			var along := clampf((m-a).dot(b-a) / maxf(0.01, (b-a).length_squared()), 0.0, 1.0)
			if m.distance_to(a+(b-a)*along) <= float(road["width"])*0.5-pad:
				return true
	return false

static func build(layout: Dictionary, tuning: Dictionary) -> Dictionary:
	var grid := int(tuning["grid_cm"])
	var cells := {}
	var bound := ceili(float(layout["extent"]) * 50.0 / grid)
	for y in range(-bound, bound+1):
		for x in range(-bound, bound+1):
			var at := Vector2(x*grid, y*grid)
			if clear(layout, tuning, at):
				cells[Vector2i(x,y)] = true
	return {"grid": grid, "cells": cells, "layout":layout, "tuning":tuning}

static func cell(nav: Dictionary, p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x/nav["grid"]), roundi(p.y/nav["grid"]))

static func route(nav: Dictionary, start: Vector2, finish: Vector2) -> Array:
	var a := _nearest_cell(nav,start)
	var b := _nearest_cell(nav,finish)
	var cells: Dictionary = nav["cells"]
	if not cells.has(a) or not cells.has(b):
		return []
	if a == b:
		return [[a.x*nav["grid"],a.y*nav["grid"]],packed(finish)]
	var queue: Array[Vector2i] = [a]
	var previous := {a:a}
	var cursor := 0
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]
		cursor += 1
		for offset in [Vector2i(0,-1),Vector2i(-1,0),Vector2i(1,0),Vector2i(0,1)]:
			var next: Vector2i = current+offset
			if not cells.has(next) or previous.has(next):
				continue
			previous[next] = current
			if next == b:
				var result: Array = [packed(finish)]
				var back := b
				while back != a:
					result.push_front([back.x*nav["grid"],back.y*nav["grid"]])
					back = previous[back]
				result.push_front([a.x*nav["grid"],a.y*nav["grid"]])
				return result
			queue.append(next)
	return []

static func line_clear(layout: Dictionary, tuning: Dictionary, a: Vector2, b: Vector2, breached: bool) -> bool:
	var samples := maxi(1, ceili(a.distance_to(b)/float(tuning["projectile_sample_cm"])))
	# Projectiles can cross open ground between streets, but never a house or wall.
	for i in range(1,samples):
		var p := a.lerp(b,float(i)/samples)/100.0
		for building in layout["buildings"]:
			var at := point(building["position"])
			var half := point(building["size"])*0.5
			if absf(p.x-at.x)<half.x and absf(p.y-at.y)<half.y:
				return false
		var wall := float(layout["walls"]["half_extent"])
		if absf(p.y-wall)<float(layout["battle"]["spatial"]["wall_half_depth_cm"])/100.0 and (not breached or absf(p.x)>float(layout["walls"]["gate_width"])*0.5):
			return false
	return true

static func _nearest_cell(nav: Dictionary, p: Vector2) -> Vector2i:
	var center:=cell(nav,p)
	var result:=Vector2i(100000,100000)
	var best:=INF
	# Connect exact clicked ground to a nearby grid point only if the entire
	# connector is walkable; this handles valid positions at street edges.
	for y in range(-1,2):
		for x in range(-1,2):
			var at:=center+Vector2i(x,y)
			if not nav["cells"].has(at):continue
			var end:=Vector2(at.x*nav["grid"],at.y*nav["grid"])
			var distance:=p.distance_to(end)
			if distance>=best:continue
			var valid:=true
			var samples:=maxi(1,ceili(distance/int(nav["tuning"]["projectile_sample_cm"])))
			for i in range(samples+1):
				if not clear(nav["layout"],nav["tuning"],p.lerp(end,float(i)/samples)):
					valid=false
					break
			if valid:
				best=distance
				result=at
	return result
