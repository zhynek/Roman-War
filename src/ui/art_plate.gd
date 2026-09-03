class_name ArtPlate
extends Control
## One picture: a hero plate, a ladder thumbnail, a unit card. The plate
## Dictionary arrives fully resolved from BuildingArt, so this Control owns
## nothing but its rect — which matters, because the panels that hold it are
## destroyed and rebuilt on every player order.

var plate: Dictionary = {}
var _font: Font


func _ready() -> void:
	_font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_plate(new_plate: Dictionary) -> void:
	if plate.get("key", "") == new_plate.get("key", "_"):
		return  # the same picture: nothing to redraw
	plate = new_plate
	tooltip_text = String(plate.get("title", ""))
	queue_redraw()


static func of(data, level_id: String, ctx: Dictionary, min_size: Vector2) -> ArtPlate:
	var view := ArtPlate.new()
	view.custom_minimum_size = min_size
	view.set_plate(BuildingArt.for_data(data).building_plate(data, level_id, ctx))
	return view


func _draw() -> void:
	ArtPainter.paint(self, plate, Rect2(Vector2.ZERO, size), _font)


static func house_key(c: Color) -> Color:
	## A faction's banner colour pushed into a range that reads on painted
	## stone: greys keep their value, everything else gets usable saturation.
	## Lived on the other branch's MapView; it is a colour helper, not a
	## renderer detail, so it belongs with the art.
	if c.s < 0.08:
		return Color(c.v, c.v, c.v).lerp(Color(0.86, 0.87, 0.90), 0.35)
	return Color.from_hsv(c.h, clampf(c.s, 0.40, 0.92), clampf(c.v, 0.52, 0.92))
