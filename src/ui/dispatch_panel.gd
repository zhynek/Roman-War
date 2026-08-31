class_name DispatchPanel
extends Control
## The Daily Dispatch: what the day amounted to, read once and dismissed.
##
## Four chapters, which are the four threads a player actually cares about —
## the wider world, our works, our coffers and people, and our cause — plus a
## headline strip for the two or three things anyone would repeat. Everything
## on it comes from the turn journal filtered through the fog of war, and every
## word from data/dispatch.json.

signal dismissed

const BACKDROP := Color(0.05, 0.05, 0.07, 0.94)

var _content: VBoxContainer
var _headline_box: VBoxContainer
var _date_label: Label
var _dismiss_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = BACKDROP
	add_child(backdrop)

	var frame := VBoxContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 60
	frame.offset_right = -60
	frame.offset_top = 34
	frame.offset_bottom = -26
	frame.add_theme_constant_override("separation", 8)
	add_child(frame)

	var title := Label.new()
	title.text = "THE DAY'S DISPATCH"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.96, 0.88, 0.62))
	frame.add_child(title)

	_date_label = Label.new()
	_date_label.add_theme_font_size_override("font_size", 14)
	_date_label.add_theme_color_override("font_color", Color(0.72, 0.70, 0.64))
	frame.add_child(_date_label)

	_headline_box = VBoxContainer.new()
	frame.add_child(_headline_box)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 4)
	scroll.add_child(_content)

	var footer := HBoxContainer.new()
	frame.add_child(footer)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_dismiss_button = Button.new()
	_dismiss_button.text = "BEGIN THE NEXT DAY"
	_dismiss_button.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_dismiss_button.pressed.connect(_on_dismiss)
	footer.add_child(_dismiss_button)


func open_for(game: Game, beats: Array) -> void:
	_clear(_content)
	_clear(_headline_box)
	_date_label.text = "%s — %s" % [
		DispatchFormat.date_line(game.state),
		String(game.data.factions.get(game.state["player_faction"], {}).get("name", "")),
	]

	for beat in DispatchRules.headlines(game.data, beats):
		var line := Label.new()
		line.text = "%s  %s" % [DispatchFormat.mark_of(game.data, beat),
			DispatchFormat.headline(game.data, game.state, beat)]
		line.add_theme_font_size_override("font_size", 17)
		line.add_theme_color_override("font_color", DispatchFormat.color_of(game.data, beat))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_headline_box.add_child(line)

	# Chapters print in the order data/dispatch.json declares them, so the day
	# always reads world-then-home-then-cause however the beats were emitted.
	var printed := 0
	for chapter in game.data.dispatch_chapters:
		var chapter_id: String = String(chapter["id"])
		var in_chapter: Array = []
		for beat in beats:
			var template := DispatchFormat.template_for(game.data, beat)
			if template.is_empty() or not bool(template["in_dispatch"]):
				continue
			if String(template["chapter"]) == chapter_id:
				in_chapter.append(beat)
		if in_chapter.is_empty():
			continue
		printed += in_chapter.size()
		_chapter_header(String(chapter["name"]), String(chapter["text"]))
		for beat in in_chapter:
			_beat_row(game, beat)

	if printed == 0:
		_chapter_header("A Quiet Day", "Nothing came in that the clerks thought worth writing down.")
	_show_and_focus()


func _show_and_focus() -> void:
	visible = true
	move_to_front()
	_dismiss_button.grab_focus()


func _chapter_header(name: String, text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	_content.add_child(spacer)
	var header := Label.new()
	header.text = name.to_upper()
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.90, 0.82, 0.55))
	_content.add_child(header)
	var blurb := Label.new()
	blurb.text = text
	blurb.add_theme_font_size_override("font_size", 12)
	blurb.add_theme_color_override("font_color", Color(0.60, 0.58, 0.54))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(blurb)


func _beat_row(game: Game, beat: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)

	var mark := Label.new()
	mark.text = DispatchFormat.mark_of(game.data, beat)
	mark.custom_minimum_size = Vector2(20, 0)
	mark.add_theme_color_override("font_color", DispatchFormat.color_of(game.data, beat))
	row.add_child(mark)

	var text := Label.new()
	text.text = DispatchFormat.headline(game.data, game.state, beat)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color", Color(0.88, 0.87, 0.83))
	row.add_child(text)


func _on_dismiss() -> void:
	visible = false
	dismissed.emit()


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
