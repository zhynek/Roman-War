class_name UiTheme
## The game's visual identity, built entirely in code (clean-room: no asset
## files). A dark campaign-tent palette — ink, old bronze, parchment — applied
## as one Godot Theme at the root so every panel, dialog, and button inherits
## it. Colors are named here and only here; panels reach for these constants
## instead of inventing their own.

const INK := Color("14100c")            # near-black ground
const PANEL := Color("241e15")          # dark leather panel
const PANEL_RAISED := Color("2e261a")   # hovered / raised surface
const PANEL_PRESSED := Color("1c1710")
const BORDER := Color("58472a")         # worn bronze edging
const BORDER_BRIGHT := Color("8a6d33")
const GOLD := Color("d4a938")           # accents, headers, the eagle's metal
const PARCHMENT := Color("e6d9b8")      # primary text
const PARCHMENT_DIM := Color("a4977c")  # secondary text
const BLOOD := Color("a03c2e")          # war, riots, loss
const LAUREL := Color("7fa15a")         # growth, good news
const SEA_DEEP := Color("0b141d")       # map water, deep
const SEA_SHALLOW := Color("142534")    # map water, near shore

const GOOD := Color(0.55, 0.78, 0.45)
const BAD := Color(0.85, 0.45, 0.38)
const WARN := Color(0.88, 0.68, 0.35)


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 13

	# Buttons: dark leather, bronze edge, gold text on hover.
	var button := _box(PANEL, BORDER, 1, 4, Vector2(10, 5))
	var button_hover := _box(PANEL_RAISED, BORDER_BRIGHT, 1, 4, Vector2(10, 5))
	var button_pressed := _box(PANEL_PRESSED, BORDER_BRIGHT, 1, 4, Vector2(10, 5))
	for state in ["normal", "focus"]:
		theme.set_stylebox(state, "Button", button)
	theme.set_stylebox("hover", "Button", button_hover)
	theme.set_stylebox("pressed", "Button", button_pressed)
	theme.set_stylebox("disabled", "Button", _box(INK, BORDER, 1, 4, Vector2(10, 5)))
	theme.set_color("font_color", "Button", PARCHMENT)
	theme.set_color("font_hover_color", "Button", GOLD)
	theme.set_color("font_pressed_color", "Button", GOLD)
	theme.set_color("font_disabled_color", "Button", PARCHMENT_DIM)

	for control in ["OptionButton", "MenuButton", "CheckBox"]:
		theme.set_stylebox("normal", control, button)
		theme.set_stylebox("hover", control, button_hover)
		theme.set_stylebox("pressed", control, button_pressed)
		theme.set_stylebox("focus", control, button)
		theme.set_stylebox("disabled", control, _box(INK, BORDER, 1, 4, Vector2(10, 5)))
		theme.set_color("font_color", control, PARCHMENT)
		theme.set_color("font_hover_color", control, GOLD)
		theme.set_color("font_pressed_color", control, GOLD)

	# Panels & dialogs: leather with a bronze frame.
	theme.set_stylebox("panel", "Panel", _box(PANEL, BORDER, 1, 6, Vector2(8, 8)))
	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, BORDER, 1, 6, Vector2(8, 8)))
	var dialog := _box(Color("1d1811"), BORDER_BRIGHT, 2, 8, Vector2(14, 12))
	theme.set_stylebox("panel", "AcceptDialog", dialog)
	theme.set_stylebox("panel", "ConfirmationDialog", dialog)
	theme.set_color("title_color", "AcceptDialog", GOLD)
	theme.set_color("title_color", "ConfirmationDialog", GOLD)
	theme.set_stylebox("panel", "PopupMenu", dialog)
	theme.set_color("font_color", "PopupMenu", PARCHMENT)
	theme.set_color("font_hover_color", "PopupMenu", GOLD)
	theme.set_stylebox("hover", "PopupMenu", _box(PANEL_RAISED, BORDER, 0, 2, Vector2(6, 3)))

	theme.set_color("font_color", "Label", PARCHMENT)
	theme.set_color("default_color", "RichTextLabel", PARCHMENT)
	theme.set_stylebox("normal", "RichTextLabel", _box(Color("191410"), BORDER, 1, 4, Vector2(10, 8)))

	var field := _box(Color("191410"), BORDER, 1, 3, Vector2(8, 4))
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", _box(Color("191410"), BORDER_BRIGHT, 1, 3, Vector2(8, 4)))
	theme.set_color("font_color", "LineEdit", PARCHMENT)
	theme.set_color("caret_color", "LineEdit", GOLD)

	theme.set_stylebox("panel", "ScrollContainer", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, Vector2(0, 0)))
	theme.set_color("separator", "HSeparator", BORDER)
	var separator_line := StyleBoxLine.new()
	separator_line.color = BORDER
	separator_line.thickness = 1
	theme.set_stylebox("separator", "HSeparator", separator_line)

	theme.set_stylebox("panel", "TooltipPanel", dialog)
	theme.set_color("font_color", "TooltipLabel", PARCHMENT)
	return theme


static func _box(bg: Color, border: Color, border_width: int, corner: int, content_margin: Vector2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(corner)
	box.content_margin_left = content_margin.x
	box.content_margin_right = content_margin.x
	box.content_margin_top = content_margin.y
	box.content_margin_bottom = content_margin.y
	return box
