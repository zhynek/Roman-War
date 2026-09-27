class_name RomaCityBattleCamera
extends RefCounted
## Presentation-only camera rig. Targets interpolate in real display time; no
## state, battle commands, RNG, collision or simulation clocks are accessed.
var camera: Camera3D
var focus := Vector3(0, 0.6, 38)
var target_focus := Vector3(0, 0.6, 38)
var yaw := 0.65
var target_yaw := 0.65
var elevation := deg_to_rad(57.0)
var target_elevation := deg_to_rad(57.0)
var span := 114.0
var target_span := 114.0
var limit := 84.0
var following := false

func attach(view_camera: Camera3D, extent: float) -> void:
	camera = view_camera
	limit = maxf(20.0, extent * 0.5 - 6.0)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 50.0
	camera.near = 0.15
	overview(true)

func overview(immediate: bool = false) -> void:
	following = false
	target_focus = Vector3(0, 0.6, 38)
	target_yaw = 0.65
	target_elevation = deg_to_rad(57.0)
	target_span = 114.0
	if immediate:
		focus = target_focus
		yaw = target_yaw
		elevation = target_elevation
		span = target_span
	_apply()

func inspect(at: Vector3, follow: bool = true) -> void:
	following = follow
	target_focus = _bounded(at)
	target_elevation = deg_to_rad(35.0)
	target_span = 22.0

func center(at: Vector3) -> void:
	following = false
	target_focus = _bounded(at)

func pan_ground(offset: Vector3) -> void:
	following = false
	target_focus = _bounded(target_focus + Vector3(offset.x, 0, offset.z))

func pan_view(direction: Vector2, delta: float) -> void:
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	pan_ground((right * direction.x - forward * direction.y) * target_span * delta * 0.62)

func orbit(relative: Vector2) -> void:
	following = false
	target_yaw -= relative.x * 0.007
	target_elevation = clampf(target_elevation + relative.y * 0.005, deg_to_rad(22), deg_to_rad(84))

func tilt() -> void:
	target_elevation = deg_to_rad(32) if target_elevation > deg_to_rad(50) else deg_to_rad(76)

func zoom(factor: float, anchor: Variant = null) -> void:
	following = false
	var next_span := clampf(target_span * factor, 10.0, 152.0)
	if anchor is Vector3:
		target_focus = _bounded(anchor + (target_focus - anchor) * (next_span / target_span))
	target_span = next_span

func update(delta: float, follow_position: Variant = null) -> void:
	if camera == null:
		return
	if following and follow_position is Vector3:
		target_focus = _bounded(follow_position)
	var weight := 1.0 - exp(-maxf(delta, 0.0) * 11.0)
	focus = focus.lerp(target_focus, weight)
	yaw = lerp_angle(yaw, target_yaw, weight)
	elevation = lerpf(elevation, target_elevation, weight)
	span = lerpf(span, target_span, weight)
	_apply()

func ground_at(pixel: Vector2) -> Variant:
	if camera == null:
		return null
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	if absf(direction.y) < 0.001:
		return null
	var distance := -origin.y / direction.y
	return origin + direction * distance if distance > 0 else null

func _bounded(at: Vector3) -> Vector3:
	return Vector3(clampf(at.x, -limit, limit), 0.6, clampf(at.z, -limit, limit))

func _apply() -> void:
	if camera == null:
		return
	# Keep the legacy size field meaningful for tools; perspective distance is
	# the smoothly interpolated visible ground span used by actual rendering.
	camera.size = target_span
	var distance := span / (2.0 * tan(deg_to_rad(camera.fov * 0.5)))
	var offset := Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * distance
	camera.position = focus + offset
	camera.look_at(focus)
