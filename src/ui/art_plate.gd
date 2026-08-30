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
