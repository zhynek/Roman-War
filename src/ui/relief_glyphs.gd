class_name ReliefGlyphs
extends RefCounted
## The map's terrain marks, lifted out of MapView so a building plate can put
## the SAME mountains on its horizon as the province it stands in. Pure move —
## every body below is verbatim from map_view.gd, only `func` became
## `static func` and the implicit `self` became an explicit `ci`.
##
## Each takes (ci, p, s, roll, shade): a canvas item, the mark's base point, a
## scale, a hashed 0..1 roll for variation, and the lit/mid/shadow/ink shade
## dictionary MapView._rebuild_ownership builds per province.

const SNOW := Color(0.906, 0.894, 0.855, 0.88)


static func mountain(ci, p: Vector2, s: float, roll: float, shade: Dictionary, north: bool) -> void:
	var half := 12.0 * s * (0.86 + roll * 0.30)
	var high := 20.0 * s * (0.80 + roll * 0.44)
	var skew := (roll - 0.5) * 0.6
	var apex := p + Vector2(skew * half, -high)
	var foot_l := p + Vector2(-half, 0.0)
	var foot_r := p + Vector2(half, 0.0)
	var foot_m := p + Vector2(skew * half * 0.34, 0.0)
	ci.draw_colored_polygon(PackedVector2Array([foot_l, apex, foot_m]), shade["lit"])
	ci.draw_colored_polygon(PackedVector2Array([foot_m, apex, foot_r]), shade["shadow"])
	if north and roll > 0.62 and shade.get("snow", true):
		var cap := high * 0.30
		ci.draw_colored_polygon(PackedVector2Array([
			apex,
			apex + Vector2(-half * 0.36, cap),
			apex + Vector2(-half * 0.10, cap * 0.62),
			apex + Vector2(half * 0.14, cap * 0.94),
			apex + Vector2(half * 0.34, cap * 0.55),
		]), SNOW)
	ci.draw_polyline(PackedVector2Array([foot_l, apex, foot_r]), shade["ink"], -1.0)


static func tree(ci, p: Vector2, s: float, roll: float, shade: Dictionary) -> void:
	var r := 8.0 * s * (0.82 + roll * 0.36)
	ci.draw_line(p, p + Vector2(0.0, -r * 0.55), shade["ink"], -1.0)
	for tier in 3:
		var ty := -r * (0.42 + 0.40 * float(tier))
		var tw := r * (0.98 - 0.24 * float(tier))
		var mid := p + Vector2(0.0, ty)
		var col: Color = shade["shadow"]
		if tier == 1:
			col = shade["mid"]
		elif tier == 2:
			col = shade["lit"]
		ci.draw_colored_polygon(PackedVector2Array([
			mid + Vector2(-tw, 0.0), mid + Vector2(tw, 0.0),
			mid + Vector2(0.0, -r * 0.66)]), col)


static func hill(ci, p: Vector2, s: float, roll: float, shade: Dictionary) -> void:
	var half := 9.0 * s * (0.82 + roll * 0.38)
	var high := 5.4 * s * (0.80 + roll * 0.45)
	var arc := PackedVector2Array()
	for k in 7:
		var t := float(k) / 6.0
		arc.append(p + Vector2(lerpf(-half, half, t), -high * sin(PI * t)))
	ci.draw_polyline(arc, shade["lit"], 1.6 * s, true)
	var under := PackedVector2Array()
	for point in arc:
		under.append(point + Vector2(0.0, 1.8 * s))
	ci.draw_polyline(under, shade["shadow"], 1.2 * s, true)


static func dune(ci, p: Vector2, s: float, roll: float, shade: Dictionary) -> void:
	var half := 15.0 * s * (0.80 + roll * 0.45)
	var sag := 5.0 * s
	var crest := PackedVector2Array()
	for k in 7:
		var t := float(k) / 6.0
		crest.append(p + Vector2(lerpf(-half, half, t), -sag * sin(PI * t)))
	ci.draw_polyline(crest, shade["lit"], 2.2 * s, true)
	var lee := PackedVector2Array()
	for point in crest:
		lee.append(point + Vector2(0.0, sag * 0.45))
	ci.draw_polyline(lee, shade["shadow"], 1.4 * s, true)


static func reed(ci, p: Vector2, s: float, roll: float, shade: Dictionary) -> void:
	ci.draw_line(p + Vector2(-5.5 * s, 1.2 * s), p + Vector2(4.5 * s, 1.2 * s),
		shade["water"], 1.4 * s)
	for k in 3:
		var base := p + Vector2((float(k) - 1.0) * 3.4 * s, 0.0)
		var high := 7.0 * s * (0.7 + roll * 0.6)
		ci.draw_line(base, base + Vector2((roll - 0.5) * 4.0 * s, -high), shade["lit"], -1.0)


static func tuft(ci, p: Vector2, s: float, roll: float, shade: Dictionary) -> void:
	for k in 3:
		var ang := -PI * 0.5 + (roll - 0.5) * 0.7 + (float(k) - 1.0) * 0.44
		ci.draw_line(p, p + Vector2(cos(ang), sin(ang)) * 5.6 * s, shade["lit"], -1.0)


static func furrow(ci, p: Vector2, s: float, roll: float, shade: Dictionary) -> void:
	var ang := roll * PI
	var dir := Vector2(cos(ang), sin(ang))
	var nrm := dir.orthogonal()
	for k in 3:
		var off := nrm * (float(k) - 1.0) * 3.2 * s
		ci.draw_line(p + off - dir * 5.6 * s, p + off + dir * 5.6 * s, shade["furrow"], -1.0)

