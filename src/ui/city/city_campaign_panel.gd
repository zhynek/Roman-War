class_name RomaCityCampaignPanel
extends PanelContainer
## A window onto the same campaign as the strategic map. All advancement and
## construction enter through Game; charts and historical browsing are reads.
var city: RomaCityScreen
var body: VBoxContainer
var tab := "overview"
var last_message := ""
var history_page := 0


func configure(screen: RomaCityScreen) -> void:
	city = screen
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 42
	offset_right = -42
	offset_top = 74
	offset_bottom = -126
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	hide()


func present() -> void:
	show()
	move_to_front()
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var report := city.game.city_campaign_status(city.REGION)
	var header := HBoxContainer.new()
	body.add_child(header)
	var heading := city._label(city.w("calendar_title"), 24)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	header.add_child(city._button(city.w("calendar_resume"), hide))
	city._paragraph(city.campaign_date(), body, 18).modulate = UiStyle.ACCENT
	var navigation := HBoxContainer.new()
	body.add_child(navigation)
	for key in ["overview", "history", "build"]:
		var button := city._button(city.w("calendar_tab_" + key), _choose.bind(key))
		button.disabled = key == tab
		navigation.add_child(button)
	navigation.add_child(city._button(city.w("campaign_map"), city._request_campaign))
	if last_message != "":
		city._paragraph(last_message, body).modulate = UiStyle.ACCENT
	match tab:
		"history": _history(report)
		"build": _construction(report)
		_: _overview(report)


func _choose(key: String) -> void:
	tab = key
	present()


func _overview(report: Dictionary) -> void:
	city._paragraph(city.w("calendar_help"), body, 15)
	city._paragraph(city.w("calendar_civic") % int(city.game.data.balance["city_campaign"]["civic_days_per_season"]), body)
	city._paragraph(city.w("calendar_span") % [_year(int(report.get("start_year", -270))), _year(int(report.get("end_year", 14)))], body).modulate = UiStyle.TEXT_DIM
	city._paragraph(city.w("calendar_snapshot") % [report.get("population", 0), report.get("treasury", 0), report.get("garrison_soldiers", 0)], body, 17)
	var controls := HBoxContainer.new()
	body.add_child(controls)
	for entry in [["next_season", 1], ["next_year", int(report.get("turns_per_year", 2))]]:
		var button := city._button(city.w(entry[0]), city.advance_season.bind(entry[1]))
		button.disabled = not report.get("can_advance", false)
		controls.add_child(button)
	if not report.get("can_advance", false):
		city._paragraph(city.w("reason_" + String(report.get("advance_reason", "battle_active"))), body)
	var charts := HBoxContainer.new()
	charts.add_theme_constant_override("separation", 16)
	body.add_child(charts)
	for metric in ["population", "treasury", "garrison_soldiers"]:
		var chart := HistoryChart.new()
		chart.records = report.get("history", []).duplicate(true)
		chart.metric = metric
		chart.caption = city.w("calendar_garrison" if metric == "garrison_soldiers" else "calendar_" + metric)
		chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chart.custom_minimum_size = Vector2(200, 140)
		charts.add_child(chart)
	city._paragraph(city.w("calendar_history_empty") if report.get("history", []).is_empty() else city.w("calendar_ready"), body, 12)


func _history(report: Dictionary) -> void:
	city._paragraph(city.w("calendar_annals"), body, 18).modulate = UiStyle.ACCENT
	var annals: Array = report.get("recent_chronicle", [])
	if annals.is_empty():
		city._paragraph(city.w("calendar_annals_empty"), body)
	for entry in annals:
		city._paragraph(_year(int(entry.get("year", 0))) + " · " + ChronicleRules.render_entry(city.game.data, city.game.state, entry), body)
	city._paragraph(city.w("calendar_history"), body, 18).modulate = UiStyle.ACCENT
	var history: Array = report.get("history", [])
	if history.is_empty():
		city._paragraph(city.w("calendar_history_empty"), body)
	var pages := maxi(1, ceili(history.size() / 100.0))
	history_page = clampi(history_page, 0, pages - 1)
	if pages > 1:
		var paging := HBoxContainer.new()
		body.add_child(paging)
		var newer := city._button(city.w("calendar_newer"), _page.bind(-1))
		newer.disabled = history_page == 0
		paging.add_child(newer)
		paging.add_child(city._label(city.w("calendar_page") % [history_page + 1, pages]))
		var older := city._button(city.w("calendar_older"), _page.bind(1))
		older.disabled = history_page == pages - 1
		paging.add_child(older)
	# Page the complete saved ledger, keeping control count bounded after centuries.
	var newest := history.size() - 1 - history_page * 100
	for index in range(newest, maxi(-1, newest - 100), -1):
		var entry: Dictionary = history[index]
		city._paragraph(city.w("calendar_history_row") % [_year(int(entry.get("year", 0))), city.w("calendar_" + String(entry.get("season", "summer"))), int(entry.get("population", 0)), int(entry.get("treasury", 0)), int(entry.get("garrison_soldiers", 0))], body, 13)


func _page(direction: int) -> void:
	history_page += direction
	present()


func _construction(report: Dictionary) -> void:
	city._paragraph(city.w("calendar_construction"), body, 18).modulate = UiStyle.ACCENT
	if report.get("owner", "") != city.game.state["player_faction"]:
		city._paragraph(city.w("calendar_lost"), body)
		return
	var settlement: Dictionary = city.game.state["settlements"][city.REGION]
	city._paragraph(city.w("calendar_queue"), body, 16)
	if settlement["construction_queue"].is_empty():
		city._paragraph(city.w("calendar_no_jobs"), body)
	for job in settlement["construction_queue"]:
		city._paragraph(city.w("calendar_job") % [city.game.data.chains[job["chain"]]["name"], int(job["turns_left"])], body)
	for project in ConstructionRules.available_projects(city.game.data, city.game.state, city.REGION):
		var button := city._button(city.w("calendar_build") % [project["name"], int(project["cost"]), int(project["build_turns"])], _build.bind(String(project["chain"])))
		button.disabled = int(report.get("treasury", 0)) < int(project["cost"]) or CityBattleRules.locked(city.game.state)
		body.add_child(button)


func _build(chain: String) -> void:
	if city.game.queue_building(city.REGION, chain):
		last_message = city.w("calendar_queued") % city.game.data.chains[chain]["name"]
	else:
		last_message = city.w("refused")
	city.refresh_city()
	present()


func _year(value: int) -> String:
	return city.w("calendar_bc") % -value if value < 0 else city.w("calendar_ad") % value


class HistoryChart extends Control:
	var records: Array = []
	var metric := "population"
	var caption := ""

	func _draw() -> void:
		draw_style_box(UiStyle._flat(Color("#172421"), 6), Rect2(Vector2.ZERO, size))
		draw_string(ThemeDB.fallback_font, Vector2(12, 24), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiStyle.TEXT)
		if records.is_empty():
			return
		var low := float(records[0].get(metric, 0))
		var high := low
		for record in records:
			low = minf(low, float(record.get(metric, 0)))
			high = maxf(high, float(record.get(metric, 0)))
		var points := PackedVector2Array()
		for index in range(records.size()):
			var x := 14.0 + float(index) / maxf(1, records.size() - 1) * (size.x - 28)
			var y := size.y - 22 - (float(records[index].get(metric, 0)) - low) / maxf(1, high - low) * (size.y - 72)
			points.append(Vector2(x, y))
		if points.size() > 1:
			draw_polyline(points, UiStyle.ACCENT, 2, true)
		draw_circle(points[-1], 3, UiStyle.ACCENT)
		draw_string(ThemeDB.fallback_font, Vector2(12, 44), str(int(records[-1].get(metric, 0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiStyle.ACCENT)
