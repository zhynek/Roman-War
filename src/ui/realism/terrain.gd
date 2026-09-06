class_name RealismTerrain
extends RefCounted
## Cosmetic height field; no access to Game, state, pathfinding or campaign RNG.
## The authored routes describe this study only, not new campaign geography.
var spec: Dictionary
var noise := FastNoiseLite.new()
var route: Curve3D
var flank: Curve3D

func _init(settings: Dictionary) -> void:
	spec = settings
	noise.seed = int(spec.seed)
	noise.frequency = 0.045
	noise.fractal_octaves = 5
	route = _curve(spec.route)
	flank = _curve(spec.flank_route)

func ellipse(p: Vector2, area: Dictionary) -> float:
	return ((p - Vector2(area.center[0], area.center[1])) / Vector2(area.radii[0], area.radii[1])).length()

func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := 1.8 + noise.get_noise_2d(x, z) * 2.4
	for peak in spec.mountains:
		var d := p.distance_to(Vector2(peak[0], peak[1])) / float(peak[3])
		h += float(peak[2]) * exp(-d * d * 1.25) * (0.86 + noise.get_noise_2d(x * 2, z * 2) * 0.30)
	var lake := ellipse(p, spec.lake)
	h = lerpf(-1.3, h, smoothstep(0.78, 1.15, lake))
	var marsh := ellipse(p, spec.marsh)
	h = lerpf(0.91 + noise.get_noise_2d(x * 4, z * 4) * 0.38, h, smoothstep(0.5, 1.13, marsh))
	# The study track is a raised dry surface beside the marsh, with a soft verge.
	if h<1.24 and lake>1.05:
		h = lerpf(maxf(h,1.24),h,smoothstep(1.8,3.2,road_distance(p)))
	return h

func ground(p: Vector3, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, height(p.x, p.z) + lift, p.z)

func road_distance(p: Vector2) -> float:
	var d := 10000.0
	for i in range(spec.route.size() - 1):
		var a := Vector2(spec.route[i][0], spec.route[i][1])
		var b := Vector2(spec.route[i + 1][0], spec.route[i + 1][1])
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return d

func sample(path: Curve3D, distance: float, side: float = 0.0) -> Transform3D:
	var length := path.get_baked_length()
	var at := path.sample_baked(clampf(distance, 0.0, length), true)
	var tangent := path.sample_baked(minf(distance + 0.3, length), true) - path.sample_baked(maxf(distance - 0.3, 0.0), true)
	tangent.y = 0
	if tangent.length_squared() < 0.0001:
		tangent = Vector3.FORWARD
	tangent = tangent.normalized()
	at += Vector3(-tangent.z, 0, tangent.x) * side
	return Transform3D(Basis(Vector3.UP, atan2(-tangent.x, -tangent.z)), ground(at, 0.035))

func _curve(points: Array) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 0.25
	for i in range(points.size()):
		var p := Vector3(points[i][0], 0, points[i][1])
		var before := Vector3(points[maxi(i - 1, 0)][0], 0, points[maxi(i - 1, 0)][1])
		var after := Vector3(points[mini(i + 1, points.size() - 1)][0], 0, points[mini(i + 1, points.size() - 1)][1])
		var tangent := (after - before).normalized() * minf(p.distance_to(before), p.distance_to(after)) * 0.22
		curve.add_point(p, -tangent, tangent)
	return curve

func build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := int(spec.grid)
	var extent := float(spec.extent)
	var step := extent / cells
	for z in range(cells + 1):
		for x in range(cells + 1):
			var px := x * step - extent * 0.5
			var pz := z * step - extent * 0.5
			var y := height(px, pz)
			var n := Vector3(height(px - 0.2, pz) - height(px + 0.2, pz), 0.4, height(px, pz - 0.2) - height(px, pz + 0.2)).normalized()
			st.set_normal(n)
			st.set_uv(Vector2(px, pz))
			st.add_vertex(Vector3(px, y, pz))
	for z in range(cells):
		for x in range(cells):
			var a := z * (cells + 1) + x
			for index in [a, a + 1, a + cells + 1, a + 1, a + cells + 2, a + cells + 1]:
				st.add_index(index)
	return st.commit()
