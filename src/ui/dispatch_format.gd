class_name DispatchFormat
extends RefCounted
## Turns a content-free journal beat into the words and colours the player
## sees. Every sentence comes from data/dispatch.json; this class only resolves
## the {tokens} in it against the game's own names, and maps a tone and an icon
## key to something drawable with no art assets.
##
## It lives under src/ui/ on purpose: src/core/ must never build a display
## string. Nothing here is a Node, so the headless test suite can call it
## directly.

const TONE_COLORS := {
	"good": Color(0.55, 0.80, 0.50),
	"bad": Color(0.88, 0.38, 0.32),
	"warning": Color(0.90, 0.68, 0.32),
	"neutral": Color(0.72, 0.74, 0.80),
}

## The art is placeholder — coloured circles on a map — so an icon is a short
## mark drawn in the interface font rather than a sprite. Every one of these is
## checked against the interface font by test_dispatch.gd: the engine's default
## face (Open Sans) has no Miscellaneous Symbols block, so the obvious choices
## (a sword, a wreath, a star) render as empty boxes. Tone carries the meaning;
## the mark is a visual anchor.
const ICON_MARKS := {
	"hammer": "#", "spear": "†", "coin": "¤", "fire": "‡",
	"wall": "¶", "plague": "÷", "capital": "◊", "sword": "×",
	"olive": "=", "clasp": "&", "amphora": "¢", "skull": "¬",
	"boot": "»", "siege": "¦", "banner": "^", "scroll": "§",
	"quake": "~", "fasces": "‰", "wreath": "®", "map": "+",
	"laurel": "*", "cradle": "©", "urn": "…",
}

## The day's own two frames, which are not journal beats.
const DAWN_MARK := "°"
const DUSK_MARK := "•"

const FALLBACK_MARK := "-"


static func template_for(data: GameData, beat: Dictionary) -> Dictionary:
	return data.dispatch_beats.get(String(beat["kind"]), {})


static func headline(data: GameData, state: Dictionary, beat: Dictionary) -> String:
	return _fill(data, state, beat, String(template_for(data, beat).get("headline", "")))


static func body(data: GameData, state: Dictionary, beat: Dictionary) -> String:
	return _fill(data, state, beat, String(template_for(data, beat).get("body", "")))


static func color_of(data: GameData, beat: Dictionary) -> Color:
	return TONE_COLORS.get(String(template_for(data, beat).get("tone", "neutral")),
		TONE_COLORS["neutral"])


static func mark_of(data: GameData, beat: Dictionary) -> String:
	return String(ICON_MARKS.get(String(template_for(data, beat).get("icon", "")), FALLBACK_MARK))


static func bbcode_line(data: GameData, state: Dictionary, beat: Dictionary) -> String:
	## One line for the side log, coloured by tone.
	return "[color=#%s]%s %s[/color]" % [
		color_of(data, beat).to_html(false), mark_of(data, beat),
		headline(data, state, beat),
	]


static func date_line(state: Dictionary) -> String:
	var year := int(state["year"])
	var year_text := "%d BC" % -year if year < 0 else "AD %d" % year
	return "%s, %s" % [year_text, String(state["season"]).capitalize()]


## --- Token substitution ---------------------------------------------------

static func _fill(data: GameData, state: Dictionary, beat: Dictionary, template: String) -> String:
	if template == "":
		return String(beat["kind"]).replace("_", " ")
	var region_id: String = String(beat["region"])
	var region: Dictionary = data.regions.get(region_id, {})
	var value = beat["value"]
	var numeric: float = float(value) if (value is int or value is float) else 0.0
	var replacements := {
		"{faction}": _faction_name(data, String(beat["faction"])),
		"{other_faction}": _faction_name(data, String(beat["other"])),
		"{region}": String(region.get("name", region_id)),
		"{settlement}": String(region.get("settlement_name", region.get("name", region_id))),
		"{subject}": _subject_name(data, state, beat),
		"{detail}": _detail_name(data, beat),
		"{value}": _signed(numeric) if numeric < 0.0 else str(int(numeric)),
		"{value_abs}": str(int(absf(numeric))),
		"{turn}": str(int(state.get("turn", 0))),
		"{year}": date_line(state),
		"{season}": String(state.get("season", "")).capitalize(),
	}
	var text := template
	for token in replacements:
		text = text.replace(token, String(replacements[token]))
	return text


static func _signed(value: float) -> String:
	return "%d" % int(value)


static func _faction_name(data: GameData, faction_id: String) -> String:
	if faction_id == "":
		return "an unknown power"
	return String(data.factions.get(faction_id, {}).get("name", faction_id))


static func _subject_name(data: GameData, state: Dictionary, beat: Dictionary) -> String:
	## What the beat is ABOUT — resolved per kind, because the same field holds
	## a building level, a unit, a mission, an event or a person depending on
	## what happened. This is lookup, not prose: the sentence around it always
	## comes from the data table.
	var subject: String = String(beat["subject"])
	if subject == "":
		return ""
	match String(beat["kind"]):
		"building_completed":
			return String(data.building_levels.get(subject, {}).get("level", {}).get("name", subject))
		"unit_mustered":
			return String(data.units.get(subject, {}).get("name", subject))
		"settlement_grew", "settlement_shrank":
			return subject.replace("_", " ").capitalize()
		"world_event":
			for event in data.events:
				if String(event["id"]) == subject:
					return String(event["name"])
			return subject.replace("_", " ")
		"disaster":
			for disaster in data.disasters:
				if String(disaster["id"]) == subject:
					return String(disaster["name"])
			return subject.replace("_", " ")
		"mission_issued", "mission_progress", "mission_complete", "mission_failed":
			return String(data.missions.get(subject, {}).get("name", subject))
		"advance_gained", "advance_lost":
			return String(data.advances.get(subject, {}).get("name", subject))
	if state.get("characters", {}).has(subject):
		return String(state["characters"][subject].get("name", subject))
	return subject.replace("_", " ")


static func _detail_name(data: GameData, beat: Dictionary) -> String:
	var detail: String = String(beat.get("extra", {}).get("detail", ""))
	if detail == "":
		return ""
	if data.traits.has(detail):
		var levels: Array = data.traits[detail].get("levels", [])
		var index := clampi(int(beat["value"]) - 1, 0, maxi(levels.size() - 1, 0))
		if not levels.is_empty():
			return String(levels[index].get("name", data.traits[detail].get("name", detail)))
		return String(data.traits[detail].get("name", detail))
	if data.ancillaries.has(detail):
		return String(data.ancillaries[detail].get("name", detail))
	return detail.replace("_", " ")
