class_name BattleScreen
extends Control
## The battle played back (R4): the resolver's round log rendered as an
## animated field — class-shaped unit blocks that advance, grind and shrink
## round by round, morale draining until one side breaks and streams away,
## ridden down in the pursuit. Pure theatre: the outcome was decided by
## BattleResolver before the curtain rose, and this screen reads only the
## result's rounds[] and unit reports — it never touches game state or the
## RNG. Skippable at any moment.

signal closed

const ROUND_SECONDS := 1.7
const FIELD_SIZE := Vector2(880, 430)
const BLOCK := 74.0
## Normalized field x: where each side forms up, how near the lines meet,
## and how far past its own start line the routed side streams away.
const ATTACKER_BASE_X := 0.16
const DEFENDER_BASE_X := 0.84
const CONTACT_GAP := 0.065
const ROUT_DISTANCE := 0.30

const PHASE_CAPTIONS := {
	"skirmish": "Skirmishers loose — javelins and arrows open the day.",
	"charge": "The lines close at a run and meet with a roar.",
	"melee": "Shield against shield: the long, grinding press.",
	"break": "The line of the %s shatters — the field turns.",
	"pursuit": "The routers are ridden down. The day is decided.",
}

var game: Game
var result: Dictionary = {}
var attacker_name := "Attackers"
var defender_name := "Defenders"

var _t := 0.0
var _rounds: Array = []
var _blocks: Array = []
var _break_index := -1
var _approach_end := 0
var _loser := ""
var _field: Control
var _caption: Label
var _button: Button
var _shown_caption := ""


static func create(current_game: Game, battle_result: Dictionary,
		attacker_label: String, defender_label: String) -> BattleScreen:
	var screen := BattleScreen.new()
	screen.game = current_game
	screen.result = battle_result
	screen.attacker_name = attacker_label
	screen.defender_name = defender_label
	return screen


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # modal: the campaign waits

	_rounds = result.get("rounds", [])
	for i in range(_rounds.size()):
		if String(_rounds[i].get("breaking", "")) != "":
			_break_index = i
			_loser = String(_rounds[i]["breaking"])
		if String(_rounds[i].get("phase", "")) == "charge":
			_approach_end = i
	for side in ["attacker", "defender"]:
		var report: Array = result.get(side + "_report", [])
		for i in range(report.size()):
			var entry: Dictionary = report[i]
			var template: Dictionary = game.data.units.get(entry["template"], {})
			_blocks.append({
				"side": side,
				"unit_class": String(template.get("class", "infantry")),
				"culture": String(template.get("culture", "neutral")),
				"strength_before": int(entry["strength_before"]),
				"strength_after": int(entry["strength_after"]),
				"row": i,
				"rows": report.size(),
			})

	var scrim := ColorRect.new()
	scrim.color = Color(0.04, 0.03, 0.05, 0.82)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)

	var headline := Label.new()
	headline.text = "%s against %s" % [attacker_name, defender_name]
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.add_theme_font_size_override("font_size", 15)
	headline.add_theme_color_override("font_color", UiStyle.PARCHMENT)
	column.add_child(headline)

	_field = FieldView.new()
	_field.screen = self
	_field.custom_minimum_size = FIELD_SIZE
	column.add_child(_field)

	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 12)
	_caption.add_theme_color_override("font_color", UiStyle.TEXT)
	column.add_child(_caption)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(button_row)
	_button = Button.new()
	_button.pressed.connect(_on_button)
	button_row.add_child(_button)
	_refresh_chrome()


func _process(delta: float) -> void:
	if is_finished():
		return
	_t += delta
	_field.queue_redraw()
	_refresh_chrome()


## --- the timeline (pure step logic; the tests drive it headless) -----------

func total_time() -> float:
	return _rounds.size() * ROUND_SECONDS


func is_finished() -> bool:
	return _t >= total_time() - 0.0001


func skip() -> void:
	_t = total_time()
	if _field != null:
		_field.queue_redraw()
	_refresh_chrome()


func round_now() -> Dictionary:
	## The moment _t as the playback sees it: the round in progress, morale
	## lerped from the previous round's values (the battle opens at 100/100).
	if _rounds.is_empty():
		return {}
	var when := clampf(_t, 0.0, total_time() - 0.0001)
	var index := mini(int(when / ROUND_SECONDS), _rounds.size() - 1)
	var fraction := clampf((when - index * ROUND_SECONDS) / ROUND_SECONDS, 0.0, 1.0)
	var entry: Dictionary = _rounds[index]
	var previous: Dictionary = _rounds[index - 1] if index > 0 \
		else {"attacker_morale": 100.0, "defender_morale": 100.0}
	return {
		"index": index,
		"phase": String(entry["phase"]),
		"fraction": fraction,
		"attacker_morale": lerpf(float(previous["attacker_morale"]),
			float(entry["attacker_morale"]), fraction),
		"defender_morale": lerpf(float(previous["defender_morale"]),
			float(entry["defender_morale"]), fraction),
		"breaking": String(entry.get("breaking", "")),
	}


func casualty_fraction(side: String, index: int, fraction: float) -> float:
	## Share of the side's whole battle loss suffered by (round, fraction-
	## through): 0 at the first arrow, exactly 1 when the log runs out.
	if _rounds.is_empty():
		return 1.0
	var total := 0.0
	for entry in _rounds:
		total += float(entry[side + "_casualty_pct"])
	if total <= 0.0:
		return clampf((float(index) + fraction) / float(_rounds.size()), 0.0, 1.0)
	var spent := 0.0
	for i in range(index):
		spent += float(_rounds[i][side + "_casualty_pct"])
	spent += float(_rounds[index][side + "_casualty_pct"]) * fraction
	return clampf(spent / total, 0.0, 1.0)


func unit_states() -> Array:
	## Every block's place, size and situation at the playing moment — the
	## step logic the field draws and the headless tests read. Blocks appear
	## in report order: the attacker's units, then the defender's.
	var now := round_now()
	if now.is_empty():
		return []
	var index := int(now["index"])
	var fraction := float(now["fraction"])
	var states: Array = []
	for block in _blocks:
		var side := String(block["side"])
		var lost := float(int(block["strength_before"]) - int(block["strength_after"]))
		var strength := float(block["strength_before"]) \
			- lost * casualty_fraction(side, index, fraction)
		var fallen: bool = int(block["strength_after"]) == 0 and strength < 10.0
		var routing: bool = _break_index >= 0 and side == _loser and not fallen \
			and (float(index) + fraction) > (float(_break_index) + 0.25)
		var rows := int(block["rows"])
		var spread := minf(0.16, 0.62 / float(maxi(rows, 1)))
		states.append({
			"side": side,
			"unit_class": String(block["unit_class"]),
			"culture": String(block["culture"]),
			"strength": strength,
			"fallen": fallen,
			"routing": routing,
			"x": _block_x(side, index, fraction, routing),
			"y": 0.5 + (float(block["row"]) - float(rows - 1) * 0.5) * spread,
		})
	return states


func _block_x(side: String, index: int, fraction: float, routing: bool) -> float:
	var base := ATTACKER_BASE_X if side == "attacker" else DEFENDER_BASE_X
	var contact := 0.5 - CONTACT_GAP if side == "attacker" else 0.5 + CONTACT_GAP
	# March: both lines close to contact by the end of the charge round.
	var advance := clampf((float(index) + fraction) / float(_approach_end + 1), 0.0, 1.0)
	var x := lerpf(base, contact, advance)
	var moment := float(index) + fraction
	if routing:
		# The routed stream back through their own start line and away.
		var rout_start := float(_break_index) + 0.25
		var flee := clampf((moment - rout_start) / maxf(float(_rounds.size()) - rout_start, 0.5), 0.0, 1.0)
		var away := base - ROUT_DISTANCE if side == "attacker" else base + ROUT_DISTANCE
		x = lerpf(x, away, flee)
	elif _break_index >= 0 and side != _loser and moment > float(_break_index):
		# The victors roll forward over the abandoned ground.
		x = lerpf(x, 0.5, clampf(moment - float(_break_index), 0.0, 1.0) * 0.6)
	return x


## --- chrome ----------------------------------------------------------------

func _on_button() -> void:
	if is_finished():
		closed.emit()
	else:
		skip()


func _refresh_chrome() -> void:
	if _caption == null:
		return
	var text := ""
	if _rounds.is_empty() or is_finished():
		var winner_label := attacker_name if String(result.get("winner", "")) == "attacker" \
			else defender_name
		text = "The day belongs to %s — losses %d%% against %d%%." % [winner_label,
			int(round(float(result.get("attacker_casualty_pct", 0.0)))),
			int(round(float(result.get("defender_casualty_pct", 0.0))))]
		_button.text = "Close"
	else:
		var phase := String(round_now()["phase"])
		text = String(PHASE_CAPTIONS.get(phase, phase.capitalize()))
		if text.contains("%s"):
			text = text % (attacker_name if _loser == "attacker" else defender_name)
		_button.text = "Skip the fighting"
	if text != _shown_caption:
		_shown_caption = text
		_caption.text = text


## --- the field -------------------------------------------------------------

class FieldView:
	extends Control
	## Draws whatever unit_states() says, every frame while the clock runs:
	## dusk ground, the blocks through Illustrations, strength strips under
	## the living, dark stains for the fallen, morale bars in the corners.
	var screen: BattleScreen

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.14, 0.12, 0.095))
		draw_rect(Rect2(Vector2(0, size.y * 0.12), Vector2(size.x, size.y * 0.76)),
			Color(0.17, 0.145, 0.11))
		for state in screen.unit_states():
			var at := Vector2(float(state["x"]) * size.x, float(state["y"]) * size.y)
			if state["fallen"]:
				draw_rect(Rect2(at - Vector2(BattleScreen.BLOCK * 0.32, 3.0),
					Vector2(BattleScreen.BLOCK * 0.64, 6.0)), Color(0.1, 0.07, 0.06, 0.8))
				continue
			var strength := clampf(float(state["strength"]), 0.0, 100.0)
			var block := BattleScreen.BLOCK * (0.62 + 0.38 * sqrt(strength / 100.0))
			Illustrations.draw_unit(self,
				Rect2(at - Vector2(block / 2.0, block * 0.82), Vector2(block, block)),
				String(state["unit_class"]), String(state["culture"]))
			draw_set_transform_matrix(Transform2D.IDENTITY)
			var strip := Vector2(block * 0.8, 3.0)
			draw_rect(Rect2(at + Vector2(-strip.x / 2.0, 6.0), strip), Color(0, 0, 0, 0.5))
			draw_rect(Rect2(at + Vector2(-strip.x / 2.0, 6.0),
				Vector2(strip.x * strength / 100.0, strip.y)), Color(0.55, 0.75, 0.4))

		var now := screen.round_now()
		if now.is_empty():
			return
		var font := get_theme_default_font()
		_morale_bar(Rect2(14, 12, 210, 9), float(now["attacker_morale"]),
			Color(0.72, 0.28, 0.22))
		_morale_bar(Rect2(size.x - 224, 12, 210, 9), float(now["defender_morale"]),
			Color(0.30, 0.44, 0.66))
		draw_string(font, Vector2(14, 36), screen.attacker_name,
			HORIZONTAL_ALIGNMENT_LEFT, 210, 11, UiStyle.PARCHMENT)
		draw_string(font, Vector2(size.x - 224, 36), screen.defender_name,
			HORIZONTAL_ALIGNMENT_RIGHT, 210, 11, UiStyle.PARCHMENT)

	func _morale_bar(rect: Rect2, morale: float, color: Color) -> void:
		draw_rect(rect, Color(0, 0, 0, 0.5))
		draw_rect(Rect2(rect.position,
			Vector2(rect.size.x * clampf(morale, 0.0, 100.0) / 100.0, rect.size.y)), color)
		draw_rect(rect, Color(0.9, 0.85, 0.7, 0.35), false, 1.0)
