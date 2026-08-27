class_name UiStyle
extends RefCounted
## The campaign UI's one visual vocabulary: the palette every panel shares,
## the terrain tints the map paints with, the built Theme that styles every
## control, and the FNV-1a hash that is the single sanctioned source of
## cosmetic jitter (never state.rng_state — determinism lives in the core).

const PARCHMENT := Color(0.95, 0.9, 0.75)
const PARCHMENT_BRIGHT := Color(1.0, 0.97, 0.86)
const INK := Color(0.85, 0.85, 0.85)
const INK_DIM := Color(0.62, 0.64, 0.66)
const GOOD := Color(0.55, 0.85, 0.55)
const BAD := Color(0.9, 0.55, 0.5)
const GOLD := Color(1.0, 0.85, 0.4)
const PANEL_BG := Color(0.125, 0.115, 0.105)
const PANEL_EDGE := Color(0.34, 0.30, 0.22)
const BUTTON_BG := Color(0.21, 0.19, 0.16)
const BUTTON_HOVER := Color(0.29, 0.26, 0.20)
const BUTTON_PRESSED := Color(0.15, 0.14, 0.12)
const END_TURN_BG := Color(0.36, 0.26, 0.10)
const END_TURN_HOVER := Color(0.46, 0.34, 0.13)
const TOOLTIP_BG := Color(0.07, 0.08, 0.10, 0.94)

const TERRAIN_TINTS := {
	"plains": Color(0.62, 0.68, 0.42, 0.5),
	"forest": Color(0.38, 0.52, 0.33, 0.5),
	"hills": Color(0.68, 0.62, 0.40, 0.5),
	"mountains": Color(0.58, 0.54, 0.50, 0.55),
	"desert": Color(0.80, 0.72, 0.48, 0.55),
	"steppe": Color(0.70, 0.68, 0.45, 0.5),
	"marsh": Color(0.46, 0.58, 0.47, 0.5),
}


static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 13

	theme.set_stylebox("normal", "Button", _box(BUTTON_BG, PANEL_EDGE))
	theme.set_stylebox("hover", "Button", _box(BUTTON_HOVER, PANEL_EDGE.lightened(0.15)))
	theme.set_stylebox("pressed", "Button", _box(BUTTON_PRESSED, PANEL_EDGE))
	theme.set_stylebox("disabled", "Button", _box(Color(0.16, 0.16, 0.16), Color(0.25, 0.25, 0.25)))
	theme.set_stylebox("focus", "Button", _box(BUTTON_BG, GOLD, 1))
	theme.set_color("font_color", "Button", PARCHMENT)
	theme.set_color("font_hover_color", "Button", PARCHMENT_BRIGHT)
	theme.set_color("font_pressed_color", "Button", PARCHMENT)
	theme.set_color("font_disabled_color", "Button", INK_DIM)
	theme.set_font_size("font_size", "Button", 12)

	theme.set_type_variation("EndTurnButton", "Button")
	theme.set_stylebox("normal", "EndTurnButton", _box(END_TURN_BG, GOLD))
	theme.set_stylebox("hover", "EndTurnButton", _box(END_TURN_HOVER, GOLD.lightened(0.2)))
	theme.set_stylebox("pressed", "EndTurnButton", _box(END_TURN_BG.darkened(0.25), GOLD))
	theme.set_color("font_color", "EndTurnButton", GOLD)
	theme.set_color("font_hover_color", "EndTurnButton", Color(1.0, 0.92, 0.6))
	theme.set_font_size("font_size", "EndTurnButton", 15)

	for options_type in ["OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", options_type, _box(BUTTON_BG, PANEL_EDGE))
		theme.set_stylebox("hover", options_type, _box(BUTTON_HOVER, PANEL_EDGE.lightened(0.15)))
		theme.set_stylebox("pressed", options_type, _box(BUTTON_PRESSED, PANEL_EDGE))
		theme.set_color("font_color", options_type, PARCHMENT)
		theme.set_font_size("font_size", options_type, 12)

	theme.set_stylebox("panel", "PanelContainer", _box(TOOLTIP_BG, PANEL_EDGE))
	theme.set_color("font_color", "Label", INK)
	theme.set_color("default_color", "RichTextLabel", INK)
	theme.set_color("separator", "HSeparator", PANEL_EDGE)
	return theme


static func _box(background: Color, edge: Color, border_width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = edge
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(4)
	box.content_margin_left = 9.0
	box.content_margin_right = 9.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	return box


static func fnv(text: String) -> int:
	## FNV-1a over the id's bytes: stable across runs, saves, and platforms.
	var hash_value := 2166136261
	for byte in text.to_utf8_buffer():
		hash_value = ((hash_value ^ byte) * 16777619) & 0xFFFFFFFF
	return hash_value


static func fnv_step(seed_hash: int, step: int) -> int:
	return ((seed_hash ^ (step * 2654435761)) * 16777619) & 0xFFFFFFFF
