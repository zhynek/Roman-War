class_name AnnalsPanel
extends AcceptDialog
## The annals: the chronicle rendered as prose, newest season first,
## filterable by the scribes' rough divisions. Every line comes from
## data/annals.json templates over the structured entries — the same feed
## a future narrator would read.

const FILTERS := ["All", "Wars", "Court", "Wisdom & World"]
const WAR_KINDS := ["war_declared", "battle", "city_taken", "city_sacked",
	"city_revolted", "peace_made", "war_summary", "faction_destroyed", "civil_war"]
const COURT_KINDS := ["alliance_made", "edict_enacted", "edict_lapsed",
	"leader_died", "succession", "reign_summary", "epithet_earned", "office_taken"]

var game: Game
var _content: VBoxContainer
var _filter: OptionButton


func _init() -> void:
	title = "The Annals"
	min_size = Vector2i(560, 560)
	var root := VBoxContainer.new()
	_filter = OptionButton.new()
	for label in FILTERS:
		_filter.add_item(label)
	_filter.item_selected.connect(func(_index): _rebuild())
	root.add_child(_filter)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(530, 470)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	root.add_child(scroll)
	add_child(root)


func open_for(current_game: Game) -> void:
	game = current_game
	_rebuild()
	popup_centered()


func _rebuild() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	var entries: Array = game.state.get("chronicle", [])
	if entries.is_empty():
		_line("The scribes have nothing yet to record.", Color(0.6, 0.6, 0.6))
		return

	var wanted := _filter.selected
	var shown := 0
	var last_date := ""
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		if not _passes_filter(String(entry["kind"]), wanted):
			continue
		var date := "%s, %s" % [ChronicleRules.year_text(int(entry["year"])),
			String(entry["season"]).capitalize()]
		if date != last_date:
			_line("— %s —" % date, Color(0.95, 0.9, 0.75))
			last_date = date
		_line("  " + ChronicleRules.render_entry(game.data, game.state, entry),
			_color_for(String(entry["kind"])))
		shown += 1
		if shown >= 300:
			_line("  … the older scrolls rest in the archive.", Color(0.6, 0.6, 0.6))
			break


func _passes_filter(kind: String, wanted: int) -> bool:
	match wanted:
		1: return WAR_KINDS.has(kind)
		2: return COURT_KINDS.has(kind)
		3: return not WAR_KINDS.has(kind) and not COURT_KINDS.has(kind)
		_: return true


func _color_for(kind: String) -> Color:
	if kind in ["city_sacked", "faction_destroyed", "disaster", "civil_war"]:
		return Color(0.9, 0.55, 0.5)
	if kind in ["technique_adopted", "technique_originated"]:
		return Color(0.6, 0.75, 0.9)
	if kind in ["epithet_earned", "reign_summary", "war_summary"]:
		return Color(0.85, 0.8, 0.6)
	return Color(0.8, 0.8, 0.8)


func _line(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)
