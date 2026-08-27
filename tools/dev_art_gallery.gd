extends SceneTree
## Dev-only: renders every procedural illustration on one sheet for visual
## QA — 17 building kinds (roman, tier 2), one building across all cultures,
## and the 12 unit classes. One capture, then quit.
##
##   xvfb-run -a godot --path . --resolution 1500x980 --script res://tools/dev_art_gallery.gd


class GallerySheet:
	extends Control

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.125, 0.14))
		var font := ThemeDB.fallback_font
		var cell := 132.0
		var pad := 8.0

		var row := 0.0
		draw_string(font, Vector2(12, 24), "BUILDING KINDS (roman, tier 2)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.88, 0.8))
		for i in range(Illustrations.BUILDING_KINDS.size()):
			var kind: String = Illustrations.BUILDING_KINDS[i]
			var at := Vector2(12 + (i % 9) * (cell + pad), 34 + floorf(i / 9.0) * (cell + 26))
			draw_rect(Rect2(at, Vector2(cell, cell)), Color(0.185, 0.18, 0.20))
			Illustrations.draw_building(self, Rect2(at, Vector2(cell, cell)), kind, "roman", 2)
			draw_string(font, at + Vector2(4, cell + 14), kind, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.75, 0.73, 0.68))
		row = 34 + 2 * (cell + 26) + 14

		draw_string(font, Vector2(12, row), "ONE KIND ACROSS CULTURES (temple) + TIERS (government 1/3/5)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.88, 0.8))
		var cultures := ["roman", "greek", "eastern", "carthaginian", "egyptian", "barbarian", "neutral"]
		for i in range(cultures.size()):
			var at := Vector2(12 + i * (cell + pad), row + 10)
			draw_rect(Rect2(at, Vector2(cell, cell)), Color(0.185, 0.18, 0.20))
			Illustrations.draw_building(self, Rect2(at, Vector2(cell, cell)), "temple", cultures[i], 2)
			draw_string(font, at + Vector2(4, cell + 14), cultures[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.75, 0.73, 0.68))
		for i in range(3):
			var at := Vector2(12 + 7 * (cell + pad) + i * (cell * 0.62 + 4), row + 10)
			var tier := 1 + 2 * i
			draw_rect(Rect2(at, Vector2(cell * 0.62, cell)), Color(0.185, 0.18, 0.20))
			Illustrations.draw_building(self, Rect2(at, Vector2(cell * 0.62, cell)), "government", "roman", tier)
		row += cell + 40

		draw_string(font, Vector2(12, row), "UNIT CLASSES",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.88, 0.8))
		var unit_cultures := ["roman", "greek", "eastern", "carthaginian", "egyptian", "barbarian",
			"barbarian", "carthaginian", "roman", "greek", "roman", "neutral"]
		for i in range(Illustrations.UNIT_CLASSES.size()):
			var unit_class: String = Illustrations.UNIT_CLASSES[i]
			var at := Vector2(12 + i * (99.0 + 3), row + 10)
			draw_rect(Rect2(at, Vector2(99, 118)), Color(0.185, 0.18, 0.20))
			Illustrations.draw_unit(self, Rect2(at, Vector2(99, 118)), unit_class, unit_cultures[i])
			draw_string(font, at + Vector2(2, 118 + 13), unit_class, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(0.75, 0.73, 0.68))


var _frame := 0
var _sheet: GallerySheet


func _init() -> void:
	_sheet = GallerySheet.new()
	root.add_child(_sheet)


func _process(_delta: float) -> bool:
	_sheet.size = root.size
	_frame += 1
	if _frame == 16:
		var out := OS.get_environment("SCREENSHOT_DIR")
		if out == "":
			out = "/tmp"
		root.get_viewport().get_texture().get_image().save_png(out + "/art_gallery.png")
		print("saved art_gallery.png")
		quit(0)
		return true
	return false
