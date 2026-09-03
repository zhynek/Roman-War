extends RefCounted
## The soldier figures: every unit resolves, the class and culture tables cover
## the roster, a cohort of 240 does not cost 240 figures, and new data cannot
## render as nothing.

const CTX := {"culture": "roman", "terrain": "plains", "fertility": 2.0,
	"season": "summer", "lod": 2, "experience": 0, "strength_pct": 100}


func test_every_unit_resolves(t) -> void:
	var data := GameData.load_from("res://data")
	var art := UnitArt.for_data(data)
	t.check(art.load_errors.is_empty(), "unit_art.json loads clean: " + ", ".join(art.load_errors))
	var seen := 0
	for template_id in data.units:
		var plate := art.unit_plate(data, template_id, CTX)
		t.check((plate["parts"] as Array).size() >= 2,
			"%s draws a unit (%d parts)" % [template_id, (plate["parts"] as Array).size()])
		t.check_eq(String(plate["title"]), String(data.units[template_id]["name"]),
			"%s is titled" % template_id)
		seen += 1
	# Against the table, not a magic number: a merge that adds a unit should
	# fail because the unit has no picture, not because a constant went stale.
	t.check_eq(seen, data.units.size(), "every unit template has a picture")


func test_every_class_and_culture_is_dressed(t) -> void:
	var data := GameData.load_from("res://data")
	var art := UnitArt.for_data(data)
	for template_id in data.units:
		var unit: Dictionary = data.units[template_id]
		t.check(art.classes.has(String(unit["class"])),
			"a template exists for the %s class" % unit["class"])
		t.check(art.kits.has(String(unit["culture"])),
			"a kit exists for %s troops" % unit["culture"])


func test_a_cohort_is_suggested_not_counted(t) -> void:
	## 240 men must not become 240 figures. The count picks a band, and the
	## ranks behind the first are one crowd.
	t.check_eq(UnitArt.files_for(12), 1, "a dozen elephants are one beast")
	t.check_eq(UnitArt.files_for(60), 3, "sixty men are a small line")
	t.check_eq(UnitArt.files_for(240), 6, "and two hundred and forty are a wide one")
	var data := GameData.load_from("res://data")
	var art := UnitArt.for_data(data)
	var big := art.unit_plate(data, "rural_levies", CTX)
	var figures := 0
	for part in big["parts"]:
		if String(part["part"]) == "figure":
			figures += 1
	t.check(figures <= 8, "the widest unit still draws at most a handful of men (%d)" % figures)
	t.check((big["parts"] as Array).size() <= 20, "and the whole plate stays small")


func test_experience_and_losses_show(t) -> void:
	var data := GameData.load_from("res://data")
	var art := UnitArt.for_data(data)
	var green := CTX.duplicate()
	var veteran := CTX.duplicate()
	veteran["experience"] = 7
	t.check(_names(art.unit_plate(data, "roman_hastati", veteran)).has("chevrons"),
		"a veteran cohort wears its chevrons")
	t.check(not _names(art.unit_plate(data, "roman_hastati", green)).has("chevrons"),
		"a raw one does not")
	var battered := CTX.duplicate()
	battered["strength_pct"] = 40
	var whole := art.unit_plate(data, "roman_hastati", green)
	var thin := art.unit_plate(data, "roman_hastati", battered)
	t.check(_count(thin, "figure") < _count(whole, "figure"),
		"a battered cohort has gaps in its line")


func test_every_attribute_has_a_cue(t) -> void:
	## New data must not render as nothing: an attribute with no visual cue is
	## a silent omission, so fail on it here rather than shipping it.
	var data := GameData.load_from("res://data")
	var art := UnitArt.for_data(data)
	var used := {}
	for template_id in data.units:
		for name in data.units[template_id].get("attributes", []):
			used[String(name)] = true
	for name in used:
		t.check(art.attributes.has(name), "the '%s' attribute has a visual cue" % name)
	t.check(used.size() >= 8, "the roster actually exercises the attribute table")
	var phalanx := art.unit_plate(data, "phalanx_pikemen", CTX)
	t.check(not (phalanx["cues"] as Array).is_empty(), "and the cue is reported to the panel")


func test_unit_resolution_is_deterministic(t) -> void:
	var data := GameData.load_from("res://data")
	var first := UnitArt.new()
	first.load_from("res://data/unit_art.json")
	var second := UnitArt.new()
	second.load_from("res://data/unit_art.json")
	for template_id in data.units:
		t.check_eq(_fingerprint(first.unit_plate(data, template_id, CTX)),
			_fingerprint(second.unit_plate(data, template_id, CTX)),
			"%s resolves identically twice" % template_id)


func test_unit_parts_are_implemented_and_on_the_plate(t) -> void:
	var implemented := {}
	for method in (ArtPainter as Script).get_script_method_list():
		implemented[String(method["name"])] = true
	var bounds := Rect2(-0.20, -0.20, 1.40, 1.40)
	var data := GameData.load_from("res://data")
	var art := UnitArt.for_data(data)
	for template_id in data.units:
		for part in art.unit_plate(data, template_id, CTX)["parts"]:
			t.check(implemented.has("_" + String(part["part"])),
				"ArtPainter implements the '%s' part" % part["part"])
			t.check(bounds.encloses(part["rect"]),
				"%s: %s stays on the plate" % [template_id, part["part"]])


func _names(plate: Dictionary) -> Dictionary:
	var found := {}
	for part in plate["parts"]:
		found[String(part["part"])] = true
	return found


func _count(plate: Dictionary, name: String) -> int:
	var total := 0
	for part in plate["parts"]:
		if String(part["part"]) == name:
			total += 1
	return total


func _fingerprint(plate: Dictionary) -> String:
	var text := String(plate["title"])
	for part in plate["parts"]:
		var r: Rect2 = part["rect"]
		text += "|%s@%.4f,%.4f,%.4f,%.4f#%d" % [part["part"], r.position.x, r.position.y,
			r.size.x, r.size.y, int(part["z"])]
	return text
