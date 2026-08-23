class_name TutorialController
extends PanelContainer
## The guided opening (data/tutorial.json): a card over the map that walks a
## new player through their first seasons. Steps advance automatically the
## moment the player does the thing described (watched through existing UI
## signals plus a state poll on every refresh), or manually with Next; Skip
## ends the walkthrough. Read-only over the game — no RNG, no state writes.

var game: Game
var screen: CampaignScreen
var config_path: String = AdvisorConfig.DEFAULT_PATH

var current_step_index := 0
var _steps: Array = []
var _baseline: Dictionary = {}
var _events: Dictionary = {}

var _title_label: Label
var _body_label: RichTextLabel
var _progress_label: Label


static func create(new_game: Game, campaign_screen: CampaignScreen) -> TutorialController:
	var controller := TutorialController.new()
	controller.game = new_game
	controller.screen = campaign_screen
	return controller


static func load_steps(path: String = "res://data/tutorial.json") -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null or not (parsed is Dictionary):
		return []
	return parsed.get("tutorial", {}).get("steps", [])


func _ready() -> void:
	_steps = load_steps()
	_build_card()
	_wire_signals()
	if _steps.is_empty():
		queue_free()
		return
	_enter_step()


func _build_card() -> void:
	custom_minimum_size = Vector2(400, 0)
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 14
	offset_bottom = -14
	offset_top = -230
	offset_right = 414
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.PANEL, 0.96)
	style.border_color = UiTheme.GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.add_theme_color_override("font_color", UiTheme.GOLD)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)
	_progress_label = Label.new()
	_progress_label.add_theme_font_size_override("font_size", 11)
	_progress_label.add_theme_color_override("font_color", UiTheme.PARCHMENT_DIM)
	header.add_child(_progress_label)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.custom_minimum_size = Vector2(0, 90)
	_body_label.add_theme_font_size_override("normal_font_size", 12)
	_body_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	column.add_child(_body_label)

	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	var skip := Button.new()
	skip.text = "Skip tutorial"
	skip.add_theme_font_size_override("font_size", 11)
	skip.pressed.connect(_finish)
	buttons.add_child(skip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var next := Button.new()
	next.text = "Next  ▸"
	next.add_theme_font_size_override("font_size", 12)
	next.pressed.connect(_advance_step)
	buttons.add_child(next)


func _wire_signals() -> void:
	screen.map_view.region_clicked.connect(func(region_id: String):
		_events["region_selected_" + region_id] = true
		_evaluate())
	screen.region_panel.army_selected.connect(func(_army_id: String):
		_events["army_selected"] = true
		_evaluate())
	screen.region_panel.action_taken.connect(_evaluate)
	for pair in [["family", screen.family_panel], ["diplomacy", screen.diplomacy_panel],
			["senate", screen.senate_panel]]:
		var panel_name: String = pair[0]
		var panel: Window = pair[1]
		panel.visibility_changed.connect(func():
			if panel.visible:
				_events["panel_" + panel_name] = true
				_evaluate())


func on_refresh() -> void:
	_evaluate()


## --- Step machinery -------------------------------------------------------

func _enter_step() -> void:
	var step: Dictionary = _steps[current_step_index]
	_title_label.text = String(step["title"])
	_body_label.text = String(step["body"])
	_progress_label.text = "Step %d / %d" % [current_step_index + 1, _steps.size()]
	_events = {}
	_baseline = capture_baseline(step.get("advance", {}), game)

	var highlights := {}
	for region_id in step.get("highlight_regions", []):
		highlights[region_id] = true
	screen.map_view.highlight_regions = highlights
	if step.has("center_on"):
		screen.map_view.center_on(String(step["center_on"]))
	screen.map_view.queue_redraw()


func _evaluate() -> void:
	if current_step_index >= _steps.size():
		return
	var advance: Dictionary = _steps[current_step_index].get("advance", {})
	if condition_met(advance, game, _baseline, _events):
		_advance_step()


func _advance_step() -> void:
	current_step_index += 1
	if current_step_index >= _steps.size():
		_finish()
		return
	_enter_step()


func _finish() -> void:
	screen.map_view.highlight_regions = {}
	screen.map_view.queue_redraw()
	AdvisorConfig.mark_tutorial_seen(config_path)
	screen.tutorial = null
	queue_free()


## --- Pure condition logic (headless-testable) ------------------------------

static func capture_baseline(advance: Dictionary, current_game: Game) -> Dictionary:
	var baseline := {"turn": int(current_game.state["turn"])}
	var region := String(advance.get("region", ""))
	if region != "" and current_game.state["settlements"].has(region):
		var settlement: Dictionary = current_game.state["settlements"][region]
		baseline["tax_level"] = String(settlement["tax_level"])
		baseline["construction_queue"] = settlement["construction_queue"].size()
		baseline["recruitment_queue"] = settlement["recruitment_queue"].size()
		baseline["buildings"] = settlement["buildings"].size()
		baseline["garrison"] = settlement["garrison"].size()
	return baseline


static func condition_met(advance: Dictionary, current_game: Game, baseline: Dictionary, events: Dictionary) -> bool:
	var state: Dictionary = current_game.state
	var player := String(state["player_faction"])
	var region := String(advance.get("region", ""))
	match String(advance.get("kind", "manual")):
		"region_selected":
			return events.get("region_selected_" + region, false)
		"tax_changed":
			if not state["settlements"].has(region):
				return false
			return String(state["settlements"][region]["tax_level"]) != String(baseline.get("tax_level", ""))
		"building_queued":
			if not state["settlements"].has(region):
				return false
			var settlement: Dictionary = state["settlements"][region]
			return settlement["construction_queue"].size() > int(baseline.get("construction_queue", 0)) \
				or settlement["buildings"].size() > int(baseline.get("buildings", 0))
		"unit_queued":
			if not state["settlements"].has(region):
				return false
			var settlement: Dictionary = state["settlements"][region]
			return settlement["recruitment_queue"].size() > int(baseline.get("recruitment_queue", 0)) \
				or settlement["garrison"].size() > int(baseline.get("garrison", 0))
		"turn_ended":
			return int(state["turn"]) > int(baseline.get("turn", 0))
		"army_selected":
			return events.get("army_selected", false)
		"army_in_region":
			for army in state["armies"].values():
				if army["owner"] == player and army["region"] == region:
					return true
			return false
		"siege_laid":
			if not state["settlements"].has(region):
				return false
			var siege = state["settlements"][region]["siege"]
			if siege == null or not state["armies"].has(siege["besieger"]):
				return false
			return state["armies"][siege["besieger"]]["owner"] == player
		"agent_trained":
			var wanted := String(advance.get("agent_kind", ""))
			for agent in state.get("agents", {}).values():
				if agent["owner"] == player and (wanted == "" or agent["kind"] == wanted):
					return true
			return false
		"panel_opened":
			return events.get("panel_" + String(advance.get("panel", "")), false)
	return false
