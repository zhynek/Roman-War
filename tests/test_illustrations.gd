extends RefCounted
## The procedural art source (R1): every building kind and unit class in the
## data must have a composition, so new content cannot ship invisible — and
## the module's own registries must never drift from the data's vocabulary.


func test_every_data_kind_and_class_has_art(t) -> void:
	var data := GameData.load_from("res://data")
	var kinds := {}
	for chain in data.chains.values():
		kinds[chain["kind"]] = true
	for kind in kinds:
		t.check(Illustrations.has_building(String(kind)), "building art exists for kind: " + String(kind))
	var classes := {}
	for unit in data.units.values():
		classes[unit["class"]] = true
	for unit_class in classes:
		t.check(Illustrations.has_unit(String(unit_class)), "unit art exists for class: " + String(unit_class))


func test_registries_carry_no_dead_art(t) -> void:
	var data := GameData.load_from("res://data")
	var kinds := {}
	for chain in data.chains.values():
		kinds[chain["kind"]] = true
	for kind in Illustrations.BUILDING_KINDS:
		t.check(kinds.has(kind), "no orphan building composition: " + String(kind))
	var classes := {}
	for unit in data.units.values():
		classes[unit["class"]] = true
	for unit_class in Illustrations.UNIT_CLASSES:
		t.check(classes.has(unit_class), "no orphan unit composition: " + String(unit_class))


func test_palettes_cover_every_culture(t) -> void:
	var data := GameData.load_from("res://data")
	var culture_ids: Array = data.cultures.keys()
	culture_ids.sort()
	var seen := {}
	for culture_id in culture_ids:
		var palette := Illustrations.culture_palette(String(culture_id))
		for key in ["primary", "stone", "roof"]:
			t.check(palette.has(key), "palette key %s for %s" % [key, culture_id])
		seen[palette["primary"]] = true
	t.check(seen.size() >= culture_ids.size() - 1,
		"cultures are visually distinct (only the fallback may repeat)")
