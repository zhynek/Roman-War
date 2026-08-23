extends SceneTree
## Headless test runner:  godot --headless --path . --script res://tests/run_tests.gd
## Discovers every tests/test_*.gd script, runs its methods starting with
## "test_", and exits nonzero on any failure. Each test method receives a
## TestContext with assertion helpers.

const TEST_DIR := "res://tests"


func _init() -> void:
	var failures := 0
	var total := 0
	var scripts := _find_test_scripts()
	scripts.sort()
	for script_path in scripts:
		var script: GDScript = load(script_path)
		if script == null:
			push_error("could not load " + script_path)
			failures += 1
			continue
		var suite: RefCounted = script.new()
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			total += 1
			var context := TestContext.new()
			context.current = "%s :: %s" % [script_path.get_file(), method_name]
			suite.call(method_name, context)
			if context.checks_run == 0:
				# A script error aborts the method without failing anything;
				# zero recorded assertions is the tell.
				context.failed = true
				context.messages.append("no assertions ran (script error inside the test?)")
			if context.failed:
				failures += 1
				print("FAIL  %s" % context.current)
				for message in context.messages:
					print("      %s" % message)
			else:
				print("ok    %s" % context.current)

	print("\n%d tests, %d failures" % [total, failures])
	quit(1 if (failures > 0 or total == 0) else 0)


func _find_test_scripts() -> Array:
	var found: Array = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return found
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			found.append(TEST_DIR + "/" + file_name)
		file_name = dir.get_next()
	return found


class TestContext:
	extends RefCounted
	var current := ""
	var failed := false
	var checks_run := 0
	var messages: Array = []

	func check(condition: bool, message: String) -> void:
		checks_run += 1
		if not condition:
			failed = true
			messages.append(message)

	func check_eq(actual, expected, message: String) -> void:
		checks_run += 1
		if not _loose_eq(actual, expected):
			failed = true
			messages.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])

	func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
		checks_run += 1
		if absf(actual - expected) > tolerance:
			failed = true
			messages.append("%s (expected %f ± %f, got %f)" % [message, expected, tolerance, actual])

	func _loose_eq(a, b) -> bool:
		if (a is float or a is int) and (b is float or b is int):
			return absf(float(a) - float(b)) < 0.000001
		return a == b
