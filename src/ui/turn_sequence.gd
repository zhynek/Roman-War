class_name TurnSequence
extends Control
## The day, played out. An overlay above the map that walks the turn journal
## one beat at a time, panning the map to each one, under a light that runs
## from dawn to dusk.
##
## IMPORTANT: nothing here resolves any rules. The turn is already over by the
## time play() is called — game.end_turn() ran to completion and wrote the
## journal — so this is pure replay of an immutable record. That is what keeps
## the engine deterministic and what lets the test suite drive a turn
## synchronously by leaving playback switched off.

signal finished

const DAWN_TINT := Color(0.16, 0.22, 0.38, 0.34)
const NOON_TINT := Color(0.98, 0.86, 0.58, 0.10)
const DUSK_TINT := Color(0.42, 0.16, 0.14, 0.36)
const CARD_BACKDROP := Color(0.07, 0.07, 0.09, 0.90)

var game: Game
var map_view: MapView

var _beats: Array = []
var _frames: Array = []   # bookend markers and beats, in playing order
var _index := -1
var _elapsed := 0.0
var _hold := 0.0
var _speed := 1.0
var _running := false
var _chapter := ""

var _tint: ColorRect
var _meter: Control
var _card: PanelContainer
var _chapter_label: Label
var _mark_label: Label
var _headline_label: Label
var _body_label: Label
var _counter_label: Label
var _speed_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	_build()


func _build() -> void:
	# A wash of colour over the map is the whole "dawn to dusk" effect: the art
	# is placeholder circles, so the day is told with light, not with assets.
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.color = DAWN_TINT
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tint)

	_meter = Control.new()
	_meter.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_meter.custom_minimum_size = Vector2(0, 10)
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter.draw.connect(_draw_meter)
	add_child(_meter)

	_chapter_label = Label.new()
	_chapter_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_chapter_label.offset_top = 26
	_chapter_label.offset_left = -300
	_chapter_label.offset_right = 300
	_chapter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chapter_label.add_theme_font_size_override("font_size", 20)
	_chapter_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.72))
	_chapter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chapter_label)

	# Controls, top right: the player can always go faster or leave.
	var controls := HBoxContainer.new()
	controls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	controls.offset_left = -190
	controls.offset_top = 14
	controls.offset_right = -12
	add_child(controls)
	_counter_label = Label.new()
	_counter_label.add_theme_font_size_override("font_size", 12)
	_counter_label.add_theme_color_override("font_color", Color(0.80, 0.78, 0.70))
	controls.add_child(_counter_label)
	_speed_button = Button.new()
	_speed_button.pressed.connect(_cycle_speed)
	controls.add_child(_speed_button)
	var skip := Button.new()
	skip.text = "SKIP"
	skip.pressed.connect(skip_to_end)
	controls.add_child(skip)

	_card = PanelContainer.new()
	_card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_card.offset_left = -330
	_card.offset_right = 330
	_card.offset_top = -132
	_card.offset_bottom = -30
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BACKDROP
	style.set_content_margin_all(12)
	style.set_corner_radius_all(4)
	style.border_width_left = 4
	style.border_color = Color(0.8, 0.7, 0.4)
	_card.add_theme_stylebox_override("panel", style)
	add_child(_card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_card.add_child(row)
	_mark_label = Label.new()
	_mark_label.add_theme_font_size_override("font_size", 28)
	_mark_label.custom_minimum_size = Vector2(34, 0)
	_mark_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_mark_label)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_column)
	_headline_label = Label.new()
	_headline_label.add_theme_font_size_override("font_size", 17)
	_headline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_column.add_child(_headline_label)
	_body_label = Label.new()
	_body_label.add_theme_font_size_override("font_size", 13)
	_body_label.add_theme_color_override("font_color", Color(0.78, 0.76, 0.70))
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_column.add_child(_body_label)


## --- Playing --------------------------------------------------------------

func play(current_game: Game, beats: Array, view: MapView) -> void:
	game = current_game
	map_view = view
	_beats = beats
	# Every day opens at dawn and closes at dusk, however little happened in
	# between. A quiet season should still feel like a day that was got through,
	# not like a button that did nothing.
	_frames = [{"bookend": "dawn"}]
	for beat in beats:
		_frames.append({"beat": beat})
	_frames.append({"bookend": "dusk"})
	_index = -1
	_elapsed = 0.0
	_hold = 0.0
	_chapter = ""
	_running = true
	visible = true
	_update_speed_button()
	set_process(true)
	_advance()


func skip_to_end() -> void:
	if not _running:
		return
	_finish()


func is_playing() -> bool:
	return _running


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta * _speed
	_tint.color = _light_at(_progress())
	_meter.queue_redraw()
	if _elapsed >= _hold:
		_advance()


func _advance() -> void:
	_index += 1
	if _index >= _frames.size():
		_finish()
		return
	var rules: Dictionary = game.data.balance["dispatch"]
	_elapsed = 0.0
	var frame: Dictionary = _frames[_index]
	_counter_label.text = "  %d / %d  " % [_index + 1, _frames.size()]
	if frame.has("bookend"):
		_show_bookend(String(frame["bookend"]), rules)
	else:
		_show_beat(frame["beat"], rules)


func _show_bookend(chapter_id: String, rules: Dictionary) -> void:
	var chapter: Dictionary = game.data.dispatch_chapter(chapter_id)
	_chapter = chapter_id
	_chapter_label.text = String(chapter.get("name", ""))
	_hold = float(rules["chapter_header_seconds"]) + float(rules["beat_seconds"])
	_mark_label.text = DispatchFormat.DAWN_MARK if chapter_id == "dawn" else DispatchFormat.DUSK_MARK
	_mark_label.add_theme_color_override("font_color", Color(0.95, 0.86, 0.58))
	_headline_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.74))
	if chapter_id == "dawn":
		_headline_label.text = DispatchFormat.date_line(game.state)
	else:
		# The tally is numbers, not prose — the sentence beside it is authored
		# in data/dispatch.json like every other line on screen.
		_headline_label.text = "%s — %d %s" % [DispatchFormat.date_line(game.state),
			_beats.size(), "report" if _beats.size() == 1 else "reports"]
	_body_label.text = String(chapter.get("text", ""))
	if map_view != null:
		map_view.highlight_regions = {}
		var capital: String = String(
			game.state["factions"][game.state["player_faction"]]["capital"])
		if game.data.regions.has(capital):
			map_view.pan_to(capital, float(rules["camera_pan_seconds"]))


func _show_beat(beat: Dictionary, rules: Dictionary) -> void:
	_hold = float(rules["beat_seconds"])
	var chapter_id := DispatchRules.chapter_of(game.data, beat)
	if chapter_id != _chapter:
		_chapter = chapter_id
		var chapter: Dictionary = game.data.dispatch_chapter(chapter_id)
		_chapter_label.text = String(chapter.get("name", ""))
		_hold += float(rules["chapter_header_seconds"])

	_mark_label.text = DispatchFormat.mark_of(game.data, beat)
	_mark_label.add_theme_color_override("font_color", DispatchFormat.color_of(game.data, beat))
	_headline_label.text = DispatchFormat.headline(game.data, game.state, beat)
	_headline_label.add_theme_color_override("font_color", DispatchFormat.color_of(game.data, beat))
	_body_label.text = DispatchFormat.body(game.data, game.state, beat)

	var region_id: String = String(beat["region"])
	if map_view != null and region_id != "" and game.data.regions.has(region_id):
		map_view.pan_to(region_id, float(rules["camera_pan_seconds"]))
		map_view.highlight_regions = {region_id: true}


func _finish() -> void:
	_running = false
	set_process(false)
	visible = false
	if map_view != null:
		map_view.highlight_regions = {}
		map_view.queue_redraw()
	finished.emit()


func _progress() -> float:
	if _frames.is_empty():
		return 1.0
	return clampf(float(_index) / float(maxi(_frames.size() - 1, 1)), 0.0, 1.0)


func _light_at(progress: float) -> Color:
	## Morning cold, midday warm, evening red. One lerp through three stops.
	if progress < 0.5:
		return DAWN_TINT.lerp(NOON_TINT, progress * 2.0)
	return NOON_TINT.lerp(DUSK_TINT, (progress - 0.5) * 2.0)


func _cycle_speed() -> void:
	var multipliers: Array = game.data.balance["dispatch"]["speed_multipliers"]
	var index := multipliers.find(_speed)
	_speed = float(multipliers[(index + 1) % multipliers.size()])
	_update_speed_button()


func _update_speed_button() -> void:
	_speed_button.text = "%dx" % int(_speed)


func _draw_meter() -> void:
	## The day meter: a thin band across the top that fills as the day burns
	## down. No art, just the same dawn-to-dusk ramp the map is washed in.
	var width := _meter.size.x
	var steps := 48
	for i in range(steps):
		var t := float(i) / float(steps)
		var band := _light_at(t)
		band.a = 0.85
		_meter.draw_rect(Rect2(width * t, 0, width / float(steps) + 1.0, 6.0), band)
	var head := width * _progress()
	_meter.draw_rect(Rect2(head - 1.0, 0, 3.0, 10.0), Color(1, 0.95, 0.80))
