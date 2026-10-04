extends SceneTree
## Real camera, controls and terrain checks without constructing city buildings.
## Run with --headless --path <experience> --script res://tools/navigation_checks.gd.

class NavigationHarness extends "res://src/main.gd":
	func _ready() -> void:
		pass

var app: NavigationHarness
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)


func _run() -> void:
	app = NavigationHarness.new()
	root.add_child(app)
	app._words = app._read_dictionary("res://data/ui.json")
	app.data = app._read_dictionary("res://data/city.json")
	app.camera = Camera3D.new()
	app.camera.current = true
	app.add_child(app.camera)
	app.world = load("res://src/world.gd").new()
	app.add_child(app.world)
	app.world.data = app.data
	app.world.visuals = app._read_dictionary("res://data/visuals.json")
	app.world._materials()
	app.world._terrain()
	# Use production terrain interpolation for picking and walking. Architecture
	# and neighborhood collision are independently exercised by scene/route gates.
	app.world.neighborhood = load("res://src/neighborhood.gd").new()
	app.world.neighborhood.active = false
	app.world.add_child(app.world.neighborhood)
	app.world.urban.free()
	app.world.additions.free()
	app._index_data()
	app._build_ui()
	app.ready_for_capture = true
	app.set_camera_view(Vector3(-1800, 50, 0), 1000, 35, 42)
	var source_before := var_to_bytes(app.data)
	await process_frame
	await process_frame
	_test_zoom()
	_test_speed_and_travel()
	_test_hops()
	_test_camera_transitions()
	_test_draw_pick_alignment()
	_test_input_conflicts()
	_check(source_before == var_to_bytes(app.data), "navigation leaves city source data unchanged")
	_check(app.design_objects.is_empty() and app._undo.is_empty(), "navigation creates no editor objects or undo transactions")
	app._release_mouse()
	print("NAVIGATION: %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _wheel(up: bool, shifted: bool = false, factor: float = 1.0) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.shift_pressed = shifted
	event.factor = factor
	return event


func _test_zoom() -> void:
	app.set_camera_view(Vector3(-1800, 50, 0), 1000, 35, 42)
	var start: Vector3 = app.camera.position
	app._unhandled_input(_wheel(true))
	_check(app._orbit_distance < 800 and app.camera.position.distance_to(start) > 200, "one wheel notch meaningfully approaches the orbit target")
	app._unhandled_input(_wheel(false))
	_check(is_equal_approx(app._orbit_distance, 1000), "inward and outward wheel zoom are reciprocal")
	app._unhandled_input(_wheel(true, true))
	_check(app._orbit_distance < 600, "Shift wheel supplies faster distance-proportional zoom")
	app._unhandled_input(_wheel(false, true))
	_check(is_equal_approx(app._orbit_distance, 1000), "Shift wheel is reciprocal")
	app._unhandled_input(_wheel(true, false, 0.0))
	_check(app._orbit_distance < 800, "platforms without high-precision factors retain full wheel notches")
	app._unhandled_input(_wheel(false, false, 0.0))
	app._unhandled_input(_wheel(true, false, 0.25))
	_check(app._orbit_distance > 900 and app._orbit_distance < 1000, "trackpad fractional scroll keeps proportional precision")
	app._unhandled_input(_wheel(false, false, 0.25))
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 1.5
	app._unhandled_input(pinch)
	_check(app._orbit_distance < 520 and app._orbit_distance > 500, "pinch magnification zooms the actual camera faster")
	pinch.factor = 1.0 / 1.5
	app._unhandled_input(pinch)
	_check(is_equal_approx(app._orbit_distance, 1000), "reverse pinch restores distance")
	for invalid in [0.0, -1.0, NAN, INF]:
		app._zoom_orbit(invalid)
	_check(is_equal_approx(app._orbit_distance, 1000), "invalid zoom factors leave a finite camera unchanged")
	app._zoom_orbit(1.0e9)
	_check(app._orbit_distance == 8, "close zoom respects inspection limit")
	app._zoom_orbit(1.0e-9)
	_check(app._orbit_distance == 17000, "far zoom respects city limit")


func _test_speed_and_travel() -> void:
	_check(app._speed_picker.item_count == 5, "five visible flight speeds are offered")
	app._speed_picker.item_selected.emit(4)
	_check(app._fly_speed == 1000, "visible speed control reaches crossing speed")
	app._set_navigation(app.Navigation.FLY)
	_check(app._fly_speed == 1000, "entering free flight preserves chosen speed")
	app.camera.position = Vector3(-2200, 600, -500)
	app.camera.rotation = Vector3.ZERO
	app._move_camera(Vector3.FORWARD, 0.1, false)
	_check(app.camera.position.is_equal_approx(Vector3(-2200, 600, -600)), "crossing speed moves the actual camera 100 metres in a tenth second")
	app._move_camera(Vector3.FORWARD, 0.1, true)
	_check(app.camera.position.is_equal_approx(Vector3(-2200, 600, -1000)), "Shift boost moves the actual camera four times as far")
	app._unhandled_input(_wheel(false))
	_check(app._fly_speed == 400 and app._speed_picker.selected == 3, "flight wheel lowers speed and synchronizes the visible setting")
	app._unhandled_input(_wheel(true))
	_check(app._fly_speed == 1000, "flight wheel raises speed")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_BRACKETLEFT
	app._unhandled_input(key)
	_check(app._fly_speed == 400, "left bracket lowers speed without mouse capture changes")
	key.keycode = KEY_BRACKETRIGHT
	app._unhandled_input(key)
	_check(app._fly_speed == 1000, "right bracket raises speed")
	app.set_flight_speed(INF)
	_check(app._fly_speed == 1000, "non-finite flight speed is rejected")
	app.set_flight_speed(-100)
	_check(app._fly_speed == 8, "speed has a safe detail minimum")
	app.set_flight_speed(100000)
	_check(app._fly_speed == 1000, "speed has a bounded crossing maximum")
	app._set_navigation(app.Navigation.ORBIT)
	app._set_navigation(app.Navigation.FLY)
	_check(app._fly_speed == 1000, "camera mode round trip retains travel speed")
	app._outside_fly_speed = app._fly_speed
	app.set_flight_speed(8)
	app._inside_architecture = true
	app._set_navigation(app.Navigation.FLY)
	_check(app._fly_speed == 1000 and not app._inside_architecture, "leaving interior inspection restores preceding travel speed")
	app._set_navigation(app.Navigation.WALK)
	_check(app._speed_picker.disabled, "flight speed control is visibly disabled when walking")
	app.camera.position = Vector3(-2200, 70, -500)
	app.camera.rotation = Vector3.ZERO
	app._move_camera(Vector3.FORWARD, 1.0, false)
	_check(is_equal_approx(app.camera.position.z, -505), "crossing speed never turns terrain walking into high-speed flight")
	var height: float = app.world.walk_surface(app.camera.position)
	_check(is_equal_approx(app.camera.position.y, height + 1.68), "walking follows rendered terrain at the configured eye height")
	app._move_camera(Vector3.FORWARD, 1.0, true)
	_check(is_equal_approx(app.camera.position.z, -517), "walking Shift remains a bounded run")
	app._set_navigation(app.Navigation.FLY)
	_check(not app._speed_picker.disabled, "flight speed control returns when flying")
	app._move_camera(Vector3(1, -1, 1), 100.0, true)
	_check(app.camera.position.is_finite() and app.camera.position.x <= app._bounds.end.x + 400, "long boosted travel is clamped to study bounds")
	_check(app.camera.position.y >= app.world._surface_height(app.camera.position.x, -app.camera.position.z) + 2, "boosted flight cannot fall below the terrain")


func _test_hops() -> void:
	_check(app._district_picker.item_count == app.data.districts.size() + 1, "every authored district has a visible direct jump")
	for index in range(app.data.districts.size()):
		app._set_navigation(app.Navigation.FLY)
		app._placing = true
		app._district_picker.item_selected.emit(index + 1)
		_check(app._navigation == app.Navigation.FLY and app._fly_speed == 1000, "district jump retains free flight and travel speed: " + str(index))
		_check(app.camera.position.is_finite() and not app._placing, "district jump lands safely and cancels pending placement: " + str(index))
		_check(app._district_picker.selected == 0, "jump menu resets so the same district can be revisited: " + str(index))
		var center := Vector2.ZERO
		for pair in app.data.districts[index].polygon_m:
			center += Vector2(pair[0], pair[1])
		center /= float(app.data.districts[index].polygon_m.size())
		_check(Vector2(app._orbit_target.x, -app._orbit_target.z).distance_to(center) < 0.01, "district jump frames the requested authored polygon: " + str(index))
	var before: Transform3D = app.camera.transform
	app.jump_to_district(-1)
	app.jump_to_district(999)
	_check(app.camera.transform == before, "unknown districts cannot displace the camera")
	app._set_navigation(app.Navigation.WALK)
	app.jump_to_district(0)
	_check(app._navigation == app.Navigation.ORBIT, "jumping from walking frames a district above its buildings")
	app.set_camera_view(Vector3(-2000, 20, -100), 1000, 35, 42)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.double_click = true
	click.position = root.get_visible_rect().size * 0.5
	app._unhandled_input(click)
	_check(app._orbit_distance == 180, "double-click terrain approaches an arbitrary visible location")
	var key := InputEventKey.new()
	key.keycode = KEY_HOME
	key.pressed = true
	app._unhandled_input(key)
	_check(app._navigation == app.Navigation.ORBIT and app._orbit_distance > 5000, "Home returns immediately to the whole city")


func _test_input_conflicts() -> void:
	app.set_camera_view(Vector3(-1800, 50, 0), 1000, 35, 42)
	app._editing = true
	app._placing = false
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.double_click = true
	click.position = root.get_visible_rect().size * 0.5
	var before: Transform3D = app.camera.transform
	app._unhandled_input(click)
	_check(app.camera.transform == before, "workshop double-click selects rather than teleports")
	app._editing = false
	var wheel := _wheel(true)
	wheel.position = app._speed_picker.get_global_rect().get_center()
	root.push_input(wheel, true)
	_check(app._orbit_distance == 1000, "scrolling the sidebar does not also zoom the scene")
	app._placing = true
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	app._input(escape)
	_check(not app._placing and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape releases capture and pending placement")


func _test_camera_transitions() -> void:
	app._set_navigation(app.Navigation.FLY)
	app.camera.position = Vector3(-2000, 500, -100)
	app.camera.rotation = Vector3(0.8, 1.2, 0)
	var before: Vector3 = app.camera.position
	app._set_navigation(app.Navigation.ORBIT)
	_check(app.camera.position.distance_to(before) < 0.01, "skyward flight to orbit preserves camera position")
	_check((-app.camera.global_basis.z).y < 0, "skyward flight establishes a downward orbit immediately")
	var established: Transform3D = app.camera.transform
	app._zoom_orbit(1.0)
	_check(app.camera.transform.is_equal_approx(established), "first orbit update after skyward flight has no delayed camera jump")
	var landmark: Dictionary = app._landmarks[app._ordered_ids[0]]
	var target: Vector3 = app.Layout.world(app.data, landmark.position_m)
	app.set_camera_view(target, 1000, 35, 42)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = root.get_visible_rect().size * 0.5
	var original_hit = app._terrain_pick(click.position)
	_check(original_hit != null, "double-click regression starts over visible land")
	app._unhandled_input(click)
	_check(app._orbit_distance < 1000, "first click approaches a visible landmark immediately")
	click.double_click = true
	app._unhandled_input(click)
	_check(app._orbit_distance == 180, "second click performs terrain approach after landmark framing")
	_check(Vector2(app._orbit_target.x, -app._orbit_target.z).distance_to(original_hit) < 0.01, "double-click uses the first terrain ray even after landmark camera movement")


func _test_draw_pick_alignment() -> void:
	var additions := Node3D.new()
	additions.name = "CreativeVariant"
	app.world.add_child(additions)
	var single := MeshInstance3D.new()
	single.name = "design_000001"
	var single_mesh := BoxMesh.new()
	single_mesh.size = Vector3(10, 20, 12)
	single.mesh = single_mesh
	single.position = Vector3(-2000, 900, -100)
	single.scale = Vector3.ONE * 2.0
	single.rotation.y = 0.7
	additions.add_child(single)
	var nested := Node3D.new()
	nested.name = "design_000002"
	nested.position = Vector3(-2200, 1000, -100)
	nested.rotation.y = 0.9
	nested.scale = Vector3.ONE * 1.7
	additions.add_child(nested)
	for position in [Vector3(-3, 4, 0), Vector3(3, 16, 0)]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 2.0
		mesh.mesh = box
		mesh.position = position
		nested.add_child(mesh)
	app.design_objects = [
		{"id": "design_000001", "kind": "house", "position_m": [-2000, 100], "rotation_deg": 40, "scale": 2.0},
		{"id": "design_000002", "kind": "church", "position_m": [-2200, 100], "rotation_deg": 52, "scale": 1.7}
	]
	app.set_camera_view(single.global_position, 50, 35, 42)
	app._pick_design(app.camera.unproject_position(single.global_position))
	_check(app._selected_design == "design_000001", "selection follows actual raised and scaled display geometry, not analytic terrain")
	single.set_meta("grounded_footings",true)
	var above_ground:=single.global_position+Vector3.UP*10.0
	_check(app._design_visual_center(single).distance_to(above_ground)<0.01,"buried footing geometry cannot pull the pick center below the visible structure")
	app._pick_design(app.camera.unproject_position(above_ground))
	_check(app._selected_design=="design_000001","grounded structure remains selectable at its visible center")
	var nested_center := nested.to_global(Vector3(0, 10, 0))
	_check(app._design_visual_center(nested).distance_to(nested_center) < 0.01, "nested architecture picking includes child mesh centers, rotation and scale")
	app.set_camera_view(nested_center, 50, 35, 42)
	app._pick_design(app.camera.unproject_position(nested_center))
	_check(app._selected_design == "design_000002", "nested church assembly is selectable where it is drawn")
	app.design_objects.clear()
	app._selected_design = ""
	app._refresh_design_labels()
	additions.queue_free()
