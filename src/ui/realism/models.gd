class_name RealismModels
extends RefCounted
## Original procedural geometry, assembled into batched meshes. Material alpha
## encodes metallic response here, not transparency. No imported bitmap assets.
var vertex_count := 0
var surface := SurfaceTool.new()

func _init() -> void:
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

func add(mesh: PrimitiveMesh, at: Vector3, scale_by: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO) -> void:
	var arrays := mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var basis := Basis.from_euler(rotation).scaled(scale_by)
	var normal_basis := basis.inverse().transposed()
	for j in range(indices.size() if not indices.is_empty() else vertices.size()):
		var i: int = indices[j] if not indices.is_empty() else j
		surface.set_color(color)
		surface.set_normal((normal_basis * normals[i]).normalized())
		surface.add_vertex(at + basis * vertices[i])
		vertex_count += 1

func ellipsoid(at: Vector3, size: Vector3, color: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 16
	sphere.rings = 9
	sphere.radius = 1
	sphere.height = 2
	add(sphere, at, size, color)

func box(at: Vector3, size: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO) -> void:
	add(BoxMesh.new(), at, size, color, rotation)

func rod(a: Vector3, b: Vector3, radius: float, color: Color, top_radius: float = -1.0) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius if top_radius < 0 else top_radius
	cylinder.bottom_radius = radius
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = 8
	cylinder.rings = 1
	var direction := (b - a).normalized()
	var rotation := Quaternion(Vector3.UP, direction).get_euler()
	add(cylinder, (a + b) * 0.5, Vector3.ONE, color, rotation)

func triangle(a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	for p in [a,b,c]:
		surface.set_color(tint)
		surface.set_normal(normal)
		surface.add_vertex(p)
		vertex_count += 1

func finish() -> ArrayMesh:
	return surface.commit()

static func scatter(key: String, salt: int = 0) -> float:
	# FNV's final adjacent salts are correlated in 2D. Avalanche the bits before
	# using separate channels as positions; otherwise forests form diagonal rows.
	var h := UiStyle.fnv(key,salt)
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xffffffff
	h = h ^ (h >> 16)
	return float(h)/4294967296.0

static func pigment(hex: String, metal: float = 0.0) -> Color:
	var c := Color.html(hex)
	c.a = metal
	return c

static func soldier(cape: Color, round_shield: bool = false, commander: bool = false, look: Dictionary = {}) -> ArrayMesh:
	var b := RealismModels.new()
	var skin: Color = look.get("face", pigment("#a47e62"))
	skin.a = 0.0
	var iron := pigment("#666c68", 0.83)
	var bronze := pigment("#88744f", 0.68)
	var leather := pigment("#493627")
	var linen := pigment("#c3b797")
	cape.a = 0.0
	# Sandals, calves, thighs and the layered tunic skirt.
	for side in [-1.0,1.0]:
		b.ellipsoid(Vector3(side*0.12,0.075,-0.045),Vector3(0.083,0.068,0.15),leather)
		b.rod(Vector3(side*0.12,0.15,0),Vector3(side*0.12,0.61,0),0.063,skin,0.075)
		b.rod(Vector3(side*0.12,0.60,0),Vector3(side*0.115,0.9,0),0.087,linen,0.10)
		for strap in range(3):
			b.box(Vector3(side*0.12,0.13+strap*0.033,-0.075),Vector3(0.14,0.015,0.10),leather)
		if not round_shield:
			b.ellipsoid(Vector3(side*0.12,0.38,-0.04),Vector3(0.071,0.20,0.044),bronze)
	b.rod(Vector3(0,0.77,0),Vector3(0,1.05,0),0.265,cape,0.19)
	b.ellipsoid(Vector3(0,1.17,0),Vector3(0.238,0.32,0.14),linen if round_shield else iron)
	b.box(Vector3(0,0.99,-0.01),Vector3(0.43,0.06,0.29),leather)
	b.box(Vector3(0,0.99,-0.16),Vector3(0.07,0.055,0.02),bronze)
	# Mail rings are relief, with a breast plate over the front.
	if not round_shield:
		for row in range(7):
			for col in range(7):
				b.ellipsoid(Vector3(-0.16+col*0.053+(row%2)*0.009,1.08+row*0.043,-0.133),Vector3(0.019,0.016,0.013),iron.lightened(0.1 if row%2 else 0.0))
		b.box(Vector3(0,1.24,-0.16),Vector3(0.205,0.19,0.017),bronze)
	# Neck, face, nose, ears, brow and helmet dome/cheek guards.
	b.rod(Vector3(0,1.39,0),Vector3(0,1.52,0),0.065,skin)
	b.ellipsoid(Vector3(0,1.61,-0.014),Vector3(0.109 * float(look.get("face_width", 1.0)),0.145,0.103),skin)
	b.ellipsoid(Vector3(0,1.615,-0.113),Vector3(0.022,0.043,0.031),skin)
	for side in [-1.0,1.0]:
		b.ellipsoid(Vector3(side*0.109,1.61,0),Vector3(0.018,0.042,0.023),skin)
		b.box(Vector3(side*0.043,1.651,-0.106),Vector3(0.025,0.01,0.008),leather)
	b.ellipsoid(Vector3(0,1.7,0.003),Vector3(0.123,0.095,0.123),bronze if not round_shield else iron)
	b.ellipsoid(Vector3(0,1.663,0.02),Vector3(0.137,0.022,0.142),bronze if not round_shield else iron)
	for side in [-1.0,1.0]:
		b.box(Vector3(side*0.105,1.575,-0.027),Vector3(0.021,0.136,0.07),bronze if not round_shield else iron,Vector3(0,0,side*0.11))
	if commander:
		b.ellipsoid(Vector3(0,1.82,0),Vector3(0.041,0.16,0.20),cape)
		b.ellipsoid(Vector3(0,1.24,0.175),Vector3(0.25,0.43,0.035),cape)
	else:
		b.rod(Vector3(-0.045,1.76,0.03),Vector3(-0.045,1.94,0.045),0.018,cape,0.009)
		b.rod(Vector3(0.045,1.76,0.03),Vector3(0.045,1.94,0.045),0.018,cape,0.009)
	# Shield arm and weapon arm; wood shaft, iron shank and point.
	for side in [-1.0,1.0]:
		b.ellipsoid(Vector3(side*0.255,1.34,0),Vector3(0.087,0.085,0.09),cape)
		b.rod(Vector3(side*0.27,1.31,0),Vector3(side*0.32,1.09,-0.09),0.067,skin)
		b.rod(Vector3(side*0.32,1.09,-0.09),Vector3(side*0.33,1.13,-0.22),0.052,skin)
	var weapon := String(look.get("weapon", "spear"))
	if weapon in ["spear", "pike", "javelin"]:
		var length := 3.7 if weapon == "pike" else 2.5
		b.rod(Vector3(0.34,0.3,-0.21),Vector3(0.34,length-0.4,-0.21),0.016,leather)
		b.rod(Vector3(0.34,length-0.4,-0.21),Vector3(0.34,length,-0.21),0.02,iron,0)
	elif weapon in ["bow", "sling"]:
		for i in range(8):
			var a := Vector3(0.34, 0.7 + i * 0.1, -0.21 - sin(float(i) / 8 * PI) * 0.18)
			var c := Vector3(0.34, 0.7 + (i+1) * 0.1, -0.21 - sin(float(i+1) / 8 * PI) * 0.18)
			b.rod(a, c, 0.017, leather)
		b.rod(Vector3(0.34,0.7,-0.21),Vector3(0.34,1.5,-0.21),0.006,linen)
	else:
		b.box(Vector3(0.34, 1.36, -0.24), Vector3(0.045, 0.48, 0.018), iron)
		b.box(Vector3(0.34, 1.12, -0.24), Vector3(0.13, 0.04, 0.05), bronze)

	if round_shield:
		b.ellipsoid(Vector3(-0.33,1.02,-0.28),Vector3(0.30,0.32,0.046),bronze)
		b.ellipsoid(Vector3(-0.33,1.02,-0.319),Vector3(0.275,0.295,0.015),cape)
	else:
		b.ellipsoid(Vector3(-0.33,1.02,-0.28),Vector3(0.245,0.44,0.068),bronze)
		b.ellipsoid(Vector3(-0.33,1.02,-0.322),Vector3(0.226,0.418,0.035),cape)
		b.box(Vector3(-0.33,1.02,-0.36),Vector3(0.022,0.72,0.013),bronze)
		for side in [-1.0,1.0]:
			b.box(Vector3(-0.33+side*0.092,1.14,-0.358),Vector3(0.15,0.023,0.012),bronze,Vector3(0,0,side*0.45))
			b.box(Vector3(-0.33+side*0.092,0.88,-0.358),Vector3(0.15,0.023,0.012),bronze,Vector3(0,0,-side*0.45))
	b.ellipsoid(Vector3(-0.33,1.02,-0.38),Vector3(0.087,0.083,0.04),iron)
	return b.finish()

static func horse() -> ArrayMesh:
	var b := RealismModels.new()
	var coat := pigment("#654536")
	var dark := pigment("#252423")
	b.ellipsoid(Vector3(0,1.05,0),Vector3(0.34,0.40,0.70),coat)
	b.ellipsoid(Vector3(0,1.45,-0.54),Vector3(0.23,0.52,0.27),coat)
	b.ellipsoid(Vector3(0,1.82,-0.79),Vector3(0.17,0.23,0.36),coat)
	b.ellipsoid(Vector3(0,1.74,-1.04),Vector3(0.16,0.15,0.13),dark)
	for side in [-1.0,1.0]:
		for end in [-1.0,1.0]:
			b.rod(Vector3(side*0.23,0.16,end*0.44),Vector3(side*0.23,1.03,end*0.42),0.075,coat,0.12)
			b.box(Vector3(side*0.23,0.09,end*0.44-0.04),Vector3(0.15,0.14,0.21),dark)
		b.rod(Vector3(side*0.105,1.96,-0.67),Vector3(side*0.12,2.16,-0.64),0.047,coat,0.015)
		b.ellipsoid(Vector3(side*0.15,1.88,-0.83),Vector3(0.018,0.028,0.023),dark)
	b.rod(Vector3(0,1.27,0.57),Vector3(0,0.50,0.95),0.11,dark,0.04)
	b.ellipsoid(Vector3(0,1.44,-0.28),Vector3(0.08,0.39,0.11),dark)
	b.box(Vector3(0,1.41,0.06),Vector3(0.58,0.09,0.68),pigment("#762e28"))
	return b.finish()

static func tree(variant: int) -> ArrayMesh:
	var b := RealismModels.new()
	var bark := pigment("#514b3a")
	b.rod(Vector3.ZERO,Vector3(0.08,4.6,0.04),0.25,bark,0.09)
	for i in range(9):
		var theta := i * 2.399 + variant
		var center := Vector3(cos(theta)*1.55,3.3+i*0.29,sin(theta)*1.55)
		b.rod(Vector3(0,2.3+i*0.22,0),center,0.08,bark,0.015)
		# Hundreds of small leaves give a broken, organic silhouette and real shadows.
		for j in range(65):
			var key := "%s/%s/%s" % [variant,i,j]
			var u := RealismModels.scatter(key,0)
			var v := RealismModels.scatter(key,1)
			var phi := u*TAU
			var y := v*2.0-1.0
			var radial := sqrt(maxf(0,1-y*y))
			var p := center+Vector3(cos(phi)*radial*1.7,y*1.15,sin(phi)*radial*1.7)*(0.4+RealismModels.scatter(key,2)*0.6)
			var tint := pigment("#3d5126").lerp(pigment("#879054"),RealismModels.scatter(key,3)*0.65)
			var length := 0.12+RealismModels.scatter(key,4)*0.17
			var across := Vector3(cos(phi),0.12,sin(phi))*length
			var along := Vector3(-sin(phi),0.55,cos(phi))*length*1.25
			b.triangle(p-along,p-across,p+Vector3(0,0.12,0),tint)
			b.triangle(p-across,p+along,p+Vector3(0,0.12,0),tint)
			b.triangle(p+along,p+across,p+Vector3(0,0.12,0),tint)
			b.triangle(p+across,p-along,p+Vector3(0,0.12,0),tint)
	return b.finish()

static func grass(reed: bool = false) -> ArrayMesh:
	var b := RealismModels.new()
	for i in range(7):
		var angle := i*2.399
		var h := (0.2+(i%3)*0.08)*(3.0 if reed else 1.0)
		var p := Vector3(cos(angle)*0.12,0,sin(angle)*0.12)
		var side := Vector3(cos(angle),0,sin(angle))*0.025
		var tip := p+Vector3(sin(angle)*0.14,h,cos(angle)*0.14)
		var tint := pigment("#777d44") if reed else pigment("#737547")
		b.triangle(p-side,p+side,tip,tint)
		if reed:
			b.rod(tip,tip+Vector3.UP*0.14,0.02,pigment("#574333"))
	return b.finish()
