class_name RomaCityDawn
extends Control
## Acknowledges an already-resolved civic day. No callback advances gameplay.
signal dismissed

var words: Dictionary = {}
var report: Dictionary = {}
var sound_enabled := true
var sound_button: Button
var continue_button: Button
var curtain: ColorRect
var panel: PanelContainer
var audio: AudioStreamPlayer
var _reveal: Tween
var _gong: AudioStreamWAV

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	audio = AudioStreamPlayer.new()
	audio.volume_db = -13
	add_child(audio)
	hide()

func w(key: String) -> String:
	return String(words.get(key, key))

func present(day_report: Dictionary, glossary: Dictionary, ceremonial: bool = true) -> void:
	if day_report.is_empty():
		return
	report = day_report.duplicate(true)
	words = glossary
	if _reveal != null:
		_reveal.kill()
	for child in get_children():
		if child != audio:
			remove_child(child)
			child.queue_free()
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	curtain = ColorRect.new()
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.color = Color(0.035, 0.045, 0.06, 0.96 if ceremonial else 0.80)
	add_child(curtain)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 180
	panel.offset_right = -180
	panel.offset_top = 58
	panel.offset_bottom = -58
	add_child(panel)
	var margins := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + edge, 20)
	panel.add_child(margins)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	margins.add_child(body)
	var heading := HBoxContainer.new()
	body.add_child(heading)
	var title := _label(w("dawn_title") % int(report.get("day_after", 1)), 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	sound_button = _button("", _toggle_sound)
	heading.add_child(sound_button)
	_update_sound_label()
	_text(w("dawn_subtitle"), body, 15)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	var metrics := GridContainer.new()
	metrics.columns = 4
	metrics.add_theme_constant_override("h_separation", 18)
	content.add_child(metrics)
	for stock in ["treasury", "unrest", "grievance", "legitimacy"]:
		var block := VBoxContainer.new()
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		metrics.add_child(block)
		block.add_child(_label(w("metric_" + stock), 14))
		var before := float(report.get("before", {}).get(stock, 0))
		var after := float(report.get("after", {}).get(stock, 0))
		var delta := after - before
		block.add_child(_label(("%.0f → %.0f" if stock == "treasury" else "%.2f → %.2f") % [before, after], 18))
		var change := _label("%+.2f" % delta, 16)
		change.modulate = Color("b9ceaa") if (delta >= 0 if stock in ["treasury", "legitimacy"] else delta <= 0) else Color("dba583")
		block.add_child(change)
	_text(w("dawn_expenses") % [int(report.get("order_cost", 0)), int(report.get("treasury_spent", 0))], content, 13)
	var orders: Array = report.get("orders_issued", [])
	if not orders.is_empty():
		content.add_child(_label(w("dawn_orders"), 17))
		for order in orders:
			_text(w("dawn_order") % [w("action_" + String(order.get("id", ""))), int(order.get("count", 1)), int(order.get("cost", 0))], content, 13)
	var events: Array = report.get("events", [])
	if not events.is_empty():
		content.add_child(_label(w("dawn_events"), 17))
		for event in events:
			_text(event_text(event, words), content, 14).modulate = UiStyle.ACCENT
	content.add_child(_label(w("dawn_causes"), 17))
	var factors := GridContainer.new()
	factors.columns = 3
	factors.add_theme_constant_override("h_separation", 24)
	factors.add_theme_constant_override("v_separation", 6)
	content.add_child(factors)
	for key in ["cause", "grievance", "legitimacy"]:
		factors.add_child(_label(w("metric_" + key), 13))
	var causes := {}
	for stock in ["grievance", "legitimacy"]:
		for factor in report.get("flows", {}).get(stock, []):
			var id := String(factor["label"])
			if not causes.has(id):
				causes[id] = {"grievance": 0.0, "legitimacy": 0.0}
			causes[id][stock] += float(factor["value"])
	for id in causes:
		_text(w("factor_" + id), factors, 13).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for stock in ["grievance", "legitimacy"]:
			factors.add_child(_label("%+.2f" % float(causes[id][stock]), 13))
	_text(w("dawn_cause_note"), content, 12).modulate = UiStyle.TEXT_DIM
	body.add_child(HSeparator.new())
	continue_button = _button(w("dawn_continue"), dismiss)
	continue_button.theme_type_variation = "EndTurnButton"
	continue_button.custom_minimum_size.y = 42
	body.add_child(continue_button)
	if ceremonial:
		panel.modulate.a = 0
		_reveal = create_tween().set_parallel(true)
		_reveal.tween_property(curtain, "color", Color(0.19, 0.135, 0.075, 0.78), 1.1)
		_reveal.tween_property(panel, "modulate:a", 1.0, 0.65).set_delay(0.25)
		play_gong()

static func event_text(event: Dictionary, glossary: Dictionary) -> String:
	var kind := String(event.get("kind", ""))
	var phrase := String(glossary.get("event_" + kind, kind))
	var params: Dictionary = event.get("params", {})
	if kind in ["project_completed", "program_paused"]:
		return phrase % String(glossary.get("project_" + String(params.get("project", "")), params.get("project", "")))
	if kind in ["troops_trained", "troops_equipped"]:
		return phrase % int(params.get("count", 0))
	return phrase

func dismiss() -> void:
	if _reveal != null:
		_reveal.kill()
	audio.stop()
	hide()
	dismissed.emit()

func _toggle_sound() -> void:
	sound_enabled = not sound_enabled
	if not sound_enabled:
		audio.stop()
	_update_sound_label()

func _update_sound_label() -> void:
	sound_button.text = w("dawn_sound_on" if sound_enabled else "dawn_sound_off")

func play_gong() -> void:
	if not sound_enabled:
		return
	if _gong == null:
		_gong = synthesize_gong()
	audio.stream = _gong
	audio.play()

static func synthesize_gong() -> AudioStreamWAV:
	# Original inharmonic bronze strike. Deterministic DSP; no recorded asset.
	var rate := 22050
	var frames := int(rate * 3.0)
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	var ratios := [1.0, 1.47, 2.09, 2.81, 3.93, 5.37]
	for i in range(frames):
		var t := float(i) / rate
		var attack := minf(1.0, t * 90.0)
		var sample := 0.0
		for partial in range(ratios.size()):
			var decay := exp(-t * (1.1 + partial * 0.42))
			sample += sin(TAU * 118.0 * ratios[partial] * t + sin(t * 4.7) * 0.12) * decay / (1.0 + partial * 1.3)
		sample *= attack * 0.39 * minf(1.0, (3.0 - t) * 8.0)
		pcm.encode_s16(i * 2, int(clampf(sample, -0.94, 0.94) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = pcm
	return stream

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _text(text: String, parent: Control, font_size: int) -> Label:
	var label := _label(text, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 34
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button
