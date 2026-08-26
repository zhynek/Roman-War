class_name UiStyle
## The single source of UI color, typography and cosmetic hashing. Every
## visual constant lives here, not scattered through panels — and all
## cosmetic randomness (terrain glyph jitter, tribal wall wobble) derives
## from stable ids through fnv(), never from the campaign RNG, so redrawing
## the map can never steer a game outcome.

## --- the map ---------------------------------------------------------------

const SEA_DEEP := Color(0.075, 0.165, 0.235)
const SEA_SHALLOW := Color(0.125, 0.255, 0.335)
const SEA_SHELF := Color(0.42, 0.62, 0.70, 0.30)  ## coastal shallows halo
const LAND_BASE := Color(0.804, 0.755, 0.639)     ## parchment under everything
const COAST_LINE := Color(0.246, 0.207, 0.155)
const PROVINCE_BORDER := Color(0.22, 0.18, 0.12, 0.30)
const FOG_VEIL := Color(0.055, 0.075, 0.105, 0.62)
const ROAD := Color(0.42, 0.325, 0.22)
const ROAD_PAVED_CORE := Color(0.87, 0.81, 0.68)
const SELECTION := Color(0.98, 0.95, 0.85)
const RANGE_TINT := Color(1.0, 0.93, 0.45, 0.20)
const RANGE_EDGE := Color(1.0, 0.93, 0.45, 0.75)
const SIEGE_RED := Color(0.86, 0.26, 0.16)
const CAPITAL_GOLD := Color(1.0, 0.87, 0.42)
const LABEL_INK := Color(0.965, 0.945, 0.895)
const LABEL_OUTLINE := Color(0.06, 0.07, 0.09, 0.85)
const SEA_LABEL := Color(0.72, 0.83, 0.90, 0.75)

const TERRAIN_FILL := {
	"plains": Color(0.727, 0.769, 0.575),
	"forest": Color(0.492, 0.606, 0.416),
	"hills": Color(0.780, 0.700, 0.512),
	"mountains": Color(0.700, 0.649, 0.580),
	"desert": Color(0.878, 0.808, 0.596),
	"steppe": Color(0.812, 0.769, 0.545),
	"marsh": Color(0.573, 0.671, 0.588),
}
const TERRAIN_GLYPH := {
	"plains": Color(0.55, 0.60, 0.40, 0.55),
	"forest": Color(0.27, 0.40, 0.24, 0.85),
	"hills": Color(0.55, 0.47, 0.31, 0.75),
	"mountains": Color(0.38, 0.34, 0.29, 0.9),
	"desert": Color(0.68, 0.60, 0.40, 0.6),
	"steppe": Color(0.60, 0.55, 0.35, 0.55),
	"marsh": Color(0.33, 0.44, 0.37, 0.8),
}

## --- shared chrome ---------------------------------------------------------

const PARCHMENT := Color(0.95, 0.9, 0.75)  ## the accent the panels share
const BG_DARK := Color(0.105, 0.10, 0.115)
const BG_PANEL := Color(0.155, 0.15, 0.17)
const BG_RAISED := Color(0.215, 0.205, 0.23)
const EDGE := Color(0.34, 0.32, 0.30, 0.55)
const ACCENT := Color(0.82, 0.66, 0.30)
const TEXT := Color(0.92, 0.90, 0.86)
const TEXT_DIM := Color(0.66, 0.64, 0.60)
const GOOD := Color(0.55, 0.78, 0.50)
const BAD := Color(0.86, 0.45, 0.38)


static func build_theme() -> Theme:
	## The one Theme for the whole campaign UI: flat dark chrome, warm
	## accents, rounded corners — set once on the campaign screen root, so
	## panels stop hand-styling every widget.
	var theme := Theme.new()

	var button := _flat(BG_RAISED, 5)
	button.set_content_margin_all(6.0)
	button.content_margin_left = 12.0
	button.content_margin_right = 12.0
	var button_hover := _flat(BG_RAISED.lightened(0.12), 5)
	button_hover.set_content_margin_all(6.0)
	button_hover.content_margin_left = 12.0
	button_hover.content_margin_right = 12.0
	button_hover.border_color = Color(ACCENT, 0.7)
	button_hover.set_border_width_all(1)
	var button_pressed := _flat(BG_DARK, 5)
	button_pressed.set_content_margin_all(6.0)
	button_pressed.content_margin_left = 12.0
	button_pressed.content_margin_right = 12.0
	theme.set_stylebox("normal", "Button", button)
	theme.set_stylebox("hover", "Button", button_hover)
	theme.set_stylebox("pressed", "Button", button_pressed)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", TEXT_DIM)
	theme.set_font_size("font_size", "Button", 12)

	var end_turn := _flat(ACCENT, 6)
	end_turn.set_content_margin_all(7.0)
	end_turn.content_margin_left = 18.0
	end_turn.content_margin_right = 18.0
	var end_turn_hover: StyleBoxFlat = end_turn.duplicate()
	end_turn_hover.bg_color = ACCENT.lightened(0.15)
	theme.add_type("EndTurnButton")
	theme.set_type_variation("EndTurnButton", "Button")
	theme.set_stylebox("normal", "EndTurnButton", end_turn)
	theme.set_stylebox("hover", "EndTurnButton", end_turn_hover)
	theme.set_stylebox("pressed", "EndTurnButton", _flat(ACCENT.darkened(0.25), 6))
	theme.set_color("font_color", "EndTurnButton", Color(0.12, 0.10, 0.06))
	theme.set_color("font_hover_color", "EndTurnButton", Color(0.10, 0.08, 0.04))
	theme.set_color("font_pressed_color", "EndTurnButton", Color(0.2, 0.17, 0.1))
	theme.set_font_size("font_size", "EndTurnButton", 14)

	var panel := _flat(BG_PANEL, 6)
	panel.set_content_margin_all(8.0)
	panel.border_color = EDGE
	panel.set_border_width_all(1)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", _flat(BG_PANEL, 0))

	var log_panel := _flat(Color(0.09, 0.088, 0.10), 6)
	log_panel.set_content_margin_all(8.0)
	theme.set_stylebox("normal", "RichTextLabel", log_panel)
	theme.set_color("default_color", "RichTextLabel", TEXT)

	theme.set_color("font_color", "Label", TEXT)
	theme.set_font_size("font_size", "Label", 12)

	var option := button.duplicate()
	theme.set_stylebox("normal", "OptionButton", option)
	theme.set_stylebox("hover", "OptionButton", button_hover.duplicate())
	theme.set_stylebox("pressed", "OptionButton", button_pressed.duplicate())
	theme.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	theme.set_font_size("font_size", "OptionButton", 12)

	var tab := _flat(BG_DARK, 0)
	theme.set_stylebox("panel", "ScrollContainer", tab)
	return theme


static func _flat(color: Color, corner: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(corner)
	return style


## --- cosmetic hashing ------------------------------------------------------

static func fnv(text: String, salt: int = 0) -> int:
	## 32-bit FNV-1a over a stable id — the one sanctioned source of UI
	## randomness. Engine-version-proof, unlike String.hash().
	var h := 2166136261
	for i in range(text.length()):
		h = ((h ^ text.unicode_at(i)) * 16777619) & 0xFFFFFFFF
	h = ((h ^ (salt & 0xFF)) * 16777619) & 0xFFFFFFFF
	h = ((h ^ ((salt >> 8) & 0xFF)) * 16777619) & 0xFFFFFFFF
	return h


static func jitter(text: String, salt: int = 0) -> float:
	## Deterministic [0, 1) from a stable id.
	return float(fnv(text, salt)) / 4294967296.0
