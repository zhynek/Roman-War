extends RefCounted
## Original procedural geometry in Godot metres (+Y up, -Z north).
## Meshes are indexed and batched per material. Inputs are authoring parameters;
## geometry never reads campaign state, clocks, RNG, or a saved game.
## box/cylinder centers are at `at`; dome and roof bases are at `at`.
## arch: clear width X, total clear height Y, depth Z; `at` is ground center.
## triangle and quad accept CLOCKWISE front-face vertex order (Godot convention).

var materials: Dictionary
var _surfaces: Dictionary = {}
var vertex_count: int = 0

func _init(p_materials: Dictionary = {}) -> void:
	materials = p_materials

func _surface(material: String) -> SurfaceTool:
	if not _surfaces.has(material):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[material] = tool
	return _surfaces[material] as SurfaceTool

func _vertex(tool: SurfaceTool, point: Vector3, normal: Vector3) -> void:
	tool.set_normal(normal)
	tool.set_uv(Vector2(point.x, point.z))
	tool.add_vertex(point)
	vertex_count += 1

func triangle(a: Vector3, b: Vector3, c: Vector3, material: String) -> void:
	var normal: Vector3 = (c - a).cross(b - a).normalized()
	if normal.length_squared() < 0.5:
		return
	var tool: SurfaceTool = _surface(material)
	_vertex(tool, a, normal)
	_vertex(tool, b, normal)
	_vertex(tool, c, normal)

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, material: String) -> void:
	triangle(a, b, c, material)
	triangle(a, c, d, material)

func _oriented_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, material: String) -> void:
	if (c - a).cross(b - a).dot(outward) < 0.0:
		quad(d, c, b, a, material)
	else:
		quad(a, b, c, d, material)

func _smooth_dome_quad(points: Array[Vector3], at: Vector3, radius: float, height: float, inward: bool, material: String) -> void:
	var normals: Array[Vector3] = []
	for p in points:
		var local: Vector3 = p-at
		var normal := Vector3(local.x/(radius*radius),local.y/(height*height),local.z/(radius*radius)).normalized()
		normals.append(-normal if inward else normal)
	var order: Array[int] = [0,1,2,0,2,3]
	if (points[2]-points[0]).cross(points[1]-points[0]).dot(normals[0]) < 0.0:
		order = [2,1,0,3,2,0]
	var tool: SurfaceTool = _surface(material)
	for index in order:
		_vertex(tool,points[index],normals[index])

func box(at: Vector3, size: Vector3, material: String, rotation: Vector3 = Vector3.ZERO) -> void:
	var basis := Basis.from_euler(rotation)
	var h: Vector3 = size * 0.5
	var corners: Array[Vector3] = []
	for p in [Vector3(-h.x,-h.y,-h.z),Vector3(h.x,-h.y,-h.z),Vector3(h.x,h.y,-h.z),Vector3(-h.x,h.y,-h.z),Vector3(-h.x,-h.y,h.z),Vector3(h.x,-h.y,h.z),Vector3(h.x,h.y,h.z),Vector3(-h.x,h.y,h.z)]:
		corners.append(at + basis * p)
	var faces: Array = [[0,1,2,3,Vector3.BACK * -1.0],[5,4,7,6,Vector3.BACK],[4,0,3,7,Vector3.LEFT],[1,5,6,2,Vector3.RIGHT],[3,2,6,7,Vector3.UP],[4,5,1,0,Vector3.DOWN]]
	for f in faces:
		_oriented_quad(corners[f[0]],corners[f[1]],corners[f[2]],corners[f[3]],basis * f[4],material)

func cylinder(at: Vector3, radius: float, height: float, material: String, top_radius: float = -1.0) -> void:
	_frustum(at, radius, radius if top_radius < 0.0 else top_radius, height, material, Basis.IDENTITY, 20)

func rod(a: Vector3, b: Vector3, radius: float, material: String, top_radius: float = -1.0, segments: int = 10) -> void:
	var axis: Vector3 = b - a
	if axis.length_squared() < 0.000001:
		return
	var basis := Basis(Quaternion(Vector3.UP, axis.normalized()))
	_frustum((a + b) * 0.5, radius, radius if top_radius < 0.0 else top_radius, axis.length(), material, basis, segments)

func _frustum(at: Vector3, radius: float, top_radius: float, height: float, material: String, basis: Basis, segments: int) -> void:
	var tool: SurfaceTool = _surface(material)
	var slope: float = (radius - top_radius) / maxf(0.001, height)
	for i in range(segments):
		var aa: float = TAU * float(i) / segments
		var ab: float = TAU * float(i + 1) / segments
		var sa := Vector3(cos(aa),0,sin(aa))
		var sb := Vector3(cos(ab),0,sin(ab))
		var a: Vector3 = at + basis * (sa * radius + Vector3.DOWN * height * 0.5)
		var b: Vector3 = at + basis * (sb * radius + Vector3.DOWN * height * 0.5)
		var c: Vector3 = at + basis * (sb * top_radius + Vector3.UP * height * 0.5)
		var d: Vector3 = at + basis * (sa * top_radius + Vector3.UP * height * 0.5)
		var na: Vector3 = basis * Vector3(sa.x,slope,sa.z).normalized()
		var nb: Vector3 = basis * Vector3(sb.x,slope,sb.z).normalized()
		# This order is clockwise viewed from the exterior.
		for pair in [[a,na],[b,nb],[c,nb],[a,na],[c,nb],[d,na]]:
			_vertex(tool,pair[0],pair[1])
		triangle(at + basis * Vector3.DOWN * height * 0.5,b,a,material)
		if top_radius > 0.0:
			triangle(at + basis * Vector3.UP * height * 0.5,d,c,material)

func dome(at: Vector3, radius: float, height: float, material: String) -> void:
	dome_section(at,radius,height,material,0.0,TAU)

func dome_section(at: Vector3, radius: float, height: float, material: String, start_angle: float, end_angle: float, interior_material: String = "") -> void:
	# An open-bottom shell, not a filled hemisphere: interiors remain inspectable.
	var segments: int = maxi(12, int(48.0 * absf(end_angle - start_angle) / TAU))
	var rings: int = 12
	var inner: String = material if interior_material.is_empty() else interior_material
	for ring in range(rings):
		var pa: float = PI * 0.5 * float(ring) / rings
		var pb: float = PI * 0.5 * float(ring + 1) / rings
		for segment in range(segments):
			var ta: float = lerpf(start_angle,end_angle,float(segment) / segments)
			var tb: float = lerpf(start_angle,end_angle,float(segment + 1) / segments)
			var a: Vector3 = at + Vector3(cos(ta)*cos(pa)*radius,sin(pa)*height,sin(ta)*cos(pa)*radius)
			var b: Vector3 = at + Vector3(cos(tb)*cos(pa)*radius,sin(pa)*height,sin(tb)*cos(pa)*radius)
			var c: Vector3 = at + Vector3(cos(tb)*cos(pb)*radius,sin(pb)*height,sin(tb)*cos(pb)*radius)
			var d: Vector3 = at + Vector3(cos(ta)*cos(pb)*radius,sin(pb)*height,sin(ta)*cos(pb)*radius)
			_smooth_dome_quad([a,b,c,d],at,radius,height,false,material)
			# Offset inner lining maintains separate surfaces without z-fighting.
			var thickness: float = maxf(0.12,radius*0.018)
			var ia: Vector3 = a - (a-at).normalized()*thickness
			var ib: Vector3 = b - (b-at).normalized()*thickness
			var ic: Vector3 = c - (c-at).normalized()*thickness
			var id: Vector3 = d - (d-at).normalized()*thickness
			_smooth_dome_quad([ia,ib,ic,id],at,radius,height,true,inner)

func roof(at: Vector3, width: float, depth: float, rise: float, material: String) -> void:
	var a: Vector3 = at + Vector3(-width*0.5,0,-depth*0.5)
	var b: Vector3 = at + Vector3(width*0.5,0,-depth*0.5)
	var c: Vector3 = at + Vector3(width*0.5,0,depth*0.5)
	var d: Vector3 = at + Vector3(-width*0.5,0,depth*0.5)
	var e: Vector3 = at + Vector3(0,rise,-depth*0.5)
	var f: Vector3 = at + Vector3(0,rise,depth*0.5)
	_oriented_quad(a,d,f,e,Vector3(-rise,width*0.5,0),material)
	_oriented_quad(b,e,f,c,Vector3(rise,width*0.5,0),material)
	triangle(a,b,e,material)
	triangle(c,d,f,material)

func arch(at: Vector3, width: float, height: float, depth: float, thickness: float, material: String, rotation_y: float = 0.0) -> void:
	var basis := Basis(Vector3.UP,rotation_y)
	var radius: float = width * 0.5
	var spring: float = maxf(0.0,height-radius)
	if spring > 0.0:
		for side in [-1.0,1.0]:
			box(at+basis*Vector3(side*(radius+thickness*0.5),spring*0.5,0),Vector3(thickness,spring,depth),material,Vector3(0,rotation_y,0))
	var segments: int = 16
	for i in range(segments):
		var a: float = PI*float(i)/segments
		var b: float = PI*float(i+1)/segments
		var inner_a := Vector2(cos(a)*radius,sin(a)*radius+spring)
		var inner_b := Vector2(cos(b)*radius,sin(b)*radius+spring)
		var outer_a := Vector2(cos(a)*(radius+thickness),sin(a)*(radius+thickness)+spring)
		var outer_b := Vector2(cos(b)*(radius+thickness),sin(b)*(radius+thickness)+spring)
		var points: Array[Vector3] = []
		for p in [Vector3(inner_a.x,inner_a.y,-depth*0.5),Vector3(inner_b.x,inner_b.y,-depth*0.5),Vector3(outer_b.x,outer_b.y,-depth*0.5),Vector3(outer_a.x,outer_a.y,-depth*0.5),Vector3(inner_a.x,inner_a.y,depth*0.5),Vector3(inner_b.x,inner_b.y,depth*0.5),Vector3(outer_b.x,outer_b.y,depth*0.5),Vector3(outer_a.x,outer_a.y,depth*0.5)]:
			points.append(at+basis*p)
		var radial := Vector3(cos((a+b)*0.5),sin((a+b)*0.5),0)
		_oriented_quad(points[0],points[1],points[2],points[3],basis*Vector3.FORWARD,material)
		_oriented_quad(points[7],points[6],points[5],points[4],basis*Vector3.BACK,material)
		_oriented_quad(points[0],points[4],points[5],points[1],basis*-radial,material)
		_oriented_quad(points[2],points[6],points[7],points[3],basis*radial,material)
		# Visible voussoir joints are thin gaps, represented by modest end caps.
		if i == 0:
			_oriented_quad(points[3],points[7],points[4],points[0],basis*Vector3.DOWN,material)
		if i == segments-1:
			_oriented_quad(points[1],points[5],points[6],points[2],basis*Vector3.DOWN,material)

func finish() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var keys: Array = _surfaces.keys()
	keys.sort()
	for key in keys:
		var tool: SurfaceTool = _surfaces[key] as SurfaceTool
		tool.index()
		tool.commit(mesh)
		var index: int = mesh.get_surface_count()-1
		if materials.has(key):
			mesh.surface_set_material(index,materials[key] as Material)
		elif materials.has("stone"):
			mesh.surface_set_material(index,materials["stone"] as Material)
	return mesh
