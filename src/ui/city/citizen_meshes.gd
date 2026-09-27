class_name RomaCitizenMeshes
extends RefCounted
## Original reusable articulated anatomy. Every joint has its own local origin.
## Vertex alpha tags opaque surface types for the procedural citizen material.

const Models = preload("res://src/ui/realism/models.gd")
const CLOTH := ["#d1c4a1", "#a95742", "#6d7980", "#ba945d", "#8a7755", "#7d665f", "#acb09c", "#79636d"]
const SKIN := ["#bf8c65", "#a87151", "#d3a580", "#93674d", "#b5805f", "#c59b79"]
const HAIR := ["#332a23", "#59422b", "#372f2b", "#777267", "#292521", "#604e36"]

static func build(role: String, variant: int) -> Dictionary:
	var skin := _pigment(SKIN[variant % SKIN.size()], 0.10)
	var cloth := _pigment(CLOTH[variant % CLOTH.size()], 0.30)
	var hair := _pigment(HAIR[variant % HAIR.size()], 0.50)
	var guard := role == "guard"
	var carrying := role == "porter"
	var long_tunic := not guard and variant % 3 == 1
	if guard:
		cloth = _pigment("#934435", 0.30)
	var torso := Models.new()
	var leather := _pigment("#584230", 0.65)
	var linen := _pigment("#d6c7a2", 0.30)
	var bronze := _pigment("#a78c59", 0.82)
	var iron := _pigment("#737a78", 0.90)
	var hem := 0.23 if long_tunic else 0.65
	# A single cloth surface follows shoulders, ribs, waist and hips. Its depth
	# is independent of width; a circular cylinder reads as a bell-shaped toy.
	_form(torso, [[hem, 0.24, 0.14, 0.0], [hem + 0.08, 0.235, 0.145, 0.0],
		[0.89, 0.20, 0.14, 0.0], [1.01, 0.168, 0.112, 0.0],
		[1.14, 0.181, 0.125, -0.002], [1.28, 0.201, 0.123, 0.0],
		[1.36, 0.196, 0.098, 0.0], [1.407, 0.087, 0.065, 0.0]], cloth, 0.009, 32)
	_form(torso, [[0.994, 0.177, 0.120, 0.0], [1.025, 0.177, 0.120, 0.0]], leather, 0.0, 32)
	torso.box(Vector3(0, 1.009, -0.124), Vector3(0.035, 0.036, 0.013), bronze)
	# The neckline and lower seam sit flush with the cloth, rather than forming
	# separate spherical parts on the body.
	_form(torso, [[hem + 0.002, 0.241, 0.142, 0.0], [hem + 0.02, 0.240, 0.144, 0.0]], cloth.darkened(0.16), 0.004, 32)
	# Clavi, a merchant's apron, and shoulder wraps distinguish livelihoods.
	if role == "merchant":
		torso.box(Vector3(0, 0.83, -0.15), Vector3(0.28, 0.36, 0.012), linen.darkened(0.10))
		torso.rod(Vector3(-0.095, 1.385, -0.07), Vector3(0.10, 1.03, -0.12), 0.014, linen)
	elif not guard and variant % 4 == 0:
		for side in [-1.0, 1.0]:
			torso.box(Vector3(side * 0.093, 1.19, -0.12), Vector3(0.017, 0.31, 0.009), cloth.darkened(0.34))
	elif not guard and variant % 4 == 2:
		_drape(torso, cloth.darkened(0.22))
		_face(torso, Vector3(-0.195, 1.374, -0.052), Vector3(-0.155, 1.324, -0.102), Vector3(0.138, 1.127, -0.137), cloth.darkened(0.20))
		_face(torso, Vector3(-0.195, 1.374, -0.052), Vector3(0.138, 1.127, -0.137), Vector3(0.164, 1.18, -0.118), cloth.darkened(0.18))
	if guard:
		_form(torso, [[1.035, 0.178, 0.119, 0.0], [1.14, 0.19, 0.139, 0.0],
			[1.29, 0.21, 0.135, 0.0], [1.35, 0.192, 0.115, 0.0], [1.39, 0.095, 0.074, 0.0]], iron, 0.002, 24)
		for row in range(5):
			for col in range(6):
				torso.ellipsoid(Vector3(-0.144 + col * 0.057 + (row % 2) * 0.008, 1.07 + row * 0.057, -0.137), Vector3(0.018, 0.018, 0.012), iron.lightened(0.15 if row % 2 else 0.0))
		torso.box(Vector3(0, 1.26, -0.153), Vector3(0.14, 0.14, 0.019), bronze)
		_drape(torso, cloth.darkened(0.16))
	# The face is built with ears, eyelids, a projecting nose, lips and jaw.
	torso.rod(Vector3(0, 1.395, 0.013), Vector3(0, 1.515, 0.013), 0.043, skin, 0.048)
	var head := Models.new()
	var face_width := 0.083 + (variant % 3) * 0.004
	_head(head, face_width, skin, hair, variant)
	# Eyelids follow an almond aperture embedded in the brow and cheek surface.
	for side in [-1.0, 1.0]:
		head.ellipsoid(Vector3(side * face_width, 1.583, 0.008), Vector3(0.012, 0.027, 0.017), skin)
		head.ellipsoid(Vector3(side * (face_width + 0.006), 1.584, 0.003), Vector3(0.005, 0.017, 0.009), skin.darkened(0.13))
		var eye_x: float = side * 0.033
		head.ellipsoid(Vector3(eye_x, 1.608, -0.080), Vector3(0.014, 0.0047, 0.0065), _pigment("#bdb4a2", 0.10))
		head.ellipsoid(Vector3(eye_x, 1.608, -0.086), Vector3(0.0042, 0.0040, 0.0016), _pigment("#403c30", 0.10))
		head.ellipsoid(Vector3(eye_x, 1.608, -0.0872), Vector3(0.0020, 0.0026, 0.0010), _pigment("#191917", 0.10))
		for segment in range(8):
			var u := float(segment) / 8.0
			var v := float(segment + 1) / 8.0
			for upper in [true, false]:
				var amplitude := 0.0053 if upper else -0.0034
				var a := Vector3(eye_x + lerpf(-0.016, 0.016, u), 1.608 + sin(u * PI) * amplitude, -0.078 - sin(u * PI) * 0.009)
				var b := Vector3(eye_x + lerpf(-0.016, 0.016, v), 1.608 + sin(v * PI) * amplitude, -0.078 - sin(v * PI) * 0.009)
				head.rod(a, b, 0.0017, skin.darkened(0.07 if upper else 0.025))
			var brow_a := Vector3(eye_x + lerpf(-0.017, 0.017, u), 1.627 + sin(u * PI) * 0.003, -0.080 - sin(u * PI) * 0.005)
			var brow_b := Vector3(eye_x + lerpf(-0.017, 0.017, v), 1.627 + sin(v * PI) * 0.003, -0.080 - sin(v * PI) * 0.005)
			head.rod(brow_a, brow_b, 0.0018, hair)
			head.rod(brow_a, brow_a + Vector3(side * 0.002, 0.003, -0.001), 0.0008, hair)
		head.ellipsoid(Vector3(side * 0.010, 1.570, -0.112), Vector3(0.0028, 0.0020, 0.002), skin.darkened(0.45))
	# The mouth line has a slight central dip and two tapered lips.
	for side in [-1.0, 1.0]:
		head.rod(Vector3(0, 1.540, -0.092), Vector3(side * 0.015, 1.539, -0.088), 0.0018, skin.darkened(0.38), 0.0008)
		head.ellipsoid(Vector3(side * 0.007, 1.542, -0.091), Vector3(0.008, 0.0027, 0.003), skin.darkened(0.10))
	head.ellipsoid(Vector3(0, 1.536, -0.090), Vector3(0.013, 0.0030, 0.003), skin.darkened(0.06))
	_hair(head, face_width, hair, variant)
	if not guard and variant % 4 == 1:
		head.ellipsoid(Vector3(0, 1.621, 0.106), Vector3(0.043, 0.041, 0.040), hair)
	if guard:
		head.ellipsoid(Vector3(0, 1.686, 0.014), Vector3(0.108, 0.068, 0.109), bronze)
		head.ellipsoid(Vector3(0, 1.657, 0.019), Vector3(0.115, 0.011, 0.12), bronze)
		for side in [-1.0, 1.0]:
			head.box(Vector3(side * 0.096, 1.589, -0.018), Vector3(0.012, 0.12, 0.052), bronze)
	elif role == "porter" and variant % 2 == 0:
		head.ellipsoid(Vector3(0, 1.697, 0.015), Vector3(0.104, 0.040, 0.109), cloth.darkened(0.18))
	if carrying:
		# Amphora with neck, rolled lip, handles and a pointed base.
		var clay := _pigment("#bd7d50", 0.72)
		torso.ellipsoid(Vector3(0.05, 1.00, -0.32), Vector3(0.145, 0.245, 0.145), clay)
		torso.rod(Vector3(0.05, 1.17, -0.32), Vector3(0.05, 1.35, -0.32), 0.048, clay)
		torso.rod(Vector3(0.05, 1.34, -0.32), Vector3(0.05, 1.365, -0.32), 0.065, clay.lightened(0.10))
		torso.rod(Vector3(0.05, 0.68, -0.32), Vector3(0.05, 0.86, -0.32), 0.018, clay, 0.09)
		for side in [-1.0, 1.0]:
			torso.rod(Vector3(0.05 + side * 0.05, 1.29, -0.32), Vector3(0.05 + side * 0.16, 1.19, -0.32), 0.016, clay)
			torso.rod(Vector3(0.05 + side * 0.16, 1.19, -0.32), Vector3(0.05 + side * 0.125, 1.08, -0.32), 0.016, clay)
	var upper_arm := _upper_arm(skin, cloth)
	var forearm := _forearm(skin)
	var upper_leg := _upper_leg(skin)
	var calf := _calf(skin, guard, long_tunic)
	var foot := _foot(skin, leather)
	return {
		"body": torso.finish(), "head": head.finish(),
		"left_arm": upper_arm, "right_arm": upper_arm,
		"left_forearm": forearm, "right_forearm": forearm,
		"left_hand": _hand(-1.0, skin, guard or carrying),
		"right_hand": _hand(1.0, skin, guard or carrying),
		"left_leg": upper_leg, "right_leg": upper_leg, "calf": calf, "foot": foot,
		"shield": _shield(cloth, bronze) if guard else null,
		"spear": _spear(leather, iron) if guard else null,
		"equipment": _equipment(bronze, leather) if guard else null,
		"long_tunic": long_tunic,
	}

static func _pigment(hex: String, surface_kind: float) -> Color:
	var color := Color.html(hex)
	color.a = surface_kind
	return color

static func _upper_arm(skin: Color, cloth: Color) -> ArrayMesh:
	var b := Models.new()
	_form(b, [[-0.281, 0.037, 0.039, 0.0], [-0.235, 0.042, 0.044, 0.003],
		[-0.18, 0.049, 0.046, 0.002], [-0.11, 0.053, 0.049, 0.0]], skin, 0.0, 24)
	_form(b, [[-0.145, 0.061, 0.06, 0.0], [-0.10, 0.062, 0.062, 0.0],
		[-0.02, 0.066, 0.060, 0.0], [0.009, 0.060, 0.055, 0.0],
		[0.035, 0.037, 0.034, 0.0], [0.046, 0.008, 0.008, 0.0]], cloth, 0.0035, 28)
	_form(b, [[-0.148, 0.062, 0.061, 0.0], [-0.137, 0.062, 0.061, 0.0]], cloth.darkened(0.14), 0.002, 28)
	return b.finish()

static func _forearm(skin: Color) -> ArrayMesh:
	var b := Models.new()
	_form(b, [[-0.246, 0.026, 0.022, -0.002], [-0.205, 0.029, 0.026, -0.001],
		[-0.13, 0.039, 0.033, 0.001], [-0.065, 0.044, 0.038, 0.001],
		[-0.015, 0.037, 0.037, 0.0], [0.021, 0.031, 0.034, 0.0]], skin, 0.0, 24)
	# The elbow and ulna are subtle relief, continuous with the arm silhouette.
	b.ellipsoid(Vector3(0, 0.0, 0.028), Vector3(0.029, 0.027, 0.018), skin.darkened(0.025))
	return b.finish()

static func _hand(side: float, skin: Color, gripping: bool) -> ArrayMesh:
	var b := Models.new()
	_form(b, [[-0.071, 0.030, 0.014, 0.0], [-0.040, 0.034, 0.018, 0.0],
		[-0.010, 0.027, 0.020, 0.0], [0.014, 0.025, 0.020, 0.0]], skin, 0.0, 20)
	for finger in range(4):
		var x := (-0.024 + finger * 0.016) * side
		var length := float([0.038, 0.050, 0.047, 0.035][finger])
		var bend := 0.035 if gripping else 0.009
		var a := Vector3(x, -0.059, -0.002)
		var joint := Vector3(x, -0.071 - length * 0.50, -bend * 0.48)
		var tip := Vector3(x, -0.069 - length * (0.52 if gripping else 0.94), -bend)
		b.rod(a, joint, 0.008, skin, 0.007)
		b.ellipsoid(joint, Vector3(0.0075, 0.008, 0.0075), skin)
		b.rod(joint, tip, 0.007, skin, 0.0055)
		b.ellipsoid(tip, Vector3(0.0055, 0.006, 0.0055), skin)
	b.rod(Vector3(-side * 0.026, -0.018, 0.0), Vector3(-side * 0.043, -0.047, -0.014), 0.011, skin, 0.009)
	b.rod(Vector3(-side * 0.043, -0.047, -0.014), Vector3(-side * 0.034, -0.073, -0.021), 0.009, skin, 0.007)
	return b.finish()

static func _upper_leg(skin: Color) -> ArrayMesh:
	var b := Models.new()
	_form(b, [[-0.388, 0.044, 0.048, 0.0], [-0.34, 0.049, 0.051, -0.002],
		[-0.245, 0.063, 0.059, -0.002], [-0.10, 0.076, 0.067, 0.0],
		[0.024, 0.078, 0.076, 0.0]], skin, 0.0, 28)
	return b.finish()

static func _calf(skin: Color, guard: bool, long_tunic: bool) -> ArrayMesh:
	var b := Models.new()
	if long_tunic:
		# The garment covers knee and upper calf. Omitting covered skin prevents
		# an articulated knee from piercing an unskinned long cloth surface.
		_form(b, [[-0.409, 0.029, 0.027, 0.0], [-0.35, 0.031, 0.031, 0.005],
			[-0.29, 0.037, 0.037, 0.009]], skin, 0.0, 24)
		return b.finish()
	_form(b, [[-0.409, 0.029, 0.027, 0.0], [-0.35, 0.031, 0.031, 0.005],
		[-0.23, 0.045, 0.045, 0.015], [-0.13, 0.058, 0.052, 0.012],
		[-0.055, 0.050, 0.046, 0.004], [0.018, 0.042, 0.042, 0.0]], skin, 0.0, 28)
	b.ellipsoid(Vector3(0, -0.002, -0.035), Vector3(0.034, 0.037, 0.019), skin)
	if guard:
		var bronze := _pigment("#8c7651", 0.82)
		b.ellipsoid(Vector3(0, -0.18, -0.043), Vector3(0.054, 0.146, 0.024), bronze)
	return b.finish()

static func _foot(skin: Color, leather: Color) -> ArrayMesh:
	var b := Models.new()
	b.ellipsoid(Vector3(0, -0.035, -0.048), Vector3(0.048, 0.035, 0.106), skin)
	b.ellipsoid(Vector3(0, -0.061, -0.058), Vector3(0.055, 0.012, 0.124), leather)
	b.ellipsoid(Vector3(0, -0.024, 0.021), Vector3(0.034, 0.042, 0.042), skin)
	for toe in range(5):
		b.ellipsoid(Vector3(-0.032 + toe * 0.014, -0.042, -0.153 + toe * 0.005), Vector3(0.009 - toe * 0.0007, 0.014, 0.020 - toe * 0.0017), skin)
	for row in range(3):
		b.rod(Vector3(-0.046, -0.014, -0.024 - row * 0.029), Vector3(0.046, -0.014, -0.043 - row * 0.029), 0.0055, leather)
		b.rod(Vector3(-0.046, -0.014, -0.043 - row * 0.029), Vector3(0.046, -0.014, -0.024 - row * 0.029), 0.0055, leather)
	_form(b, [[0.007, 0.035, 0.032, 0.01], [0.020, 0.035, 0.032, 0.01]], leather, 0, 20)
	return b.finish()

static func _shield(cloth: Color, bronze: Color) -> ArrayMesh:
	var b := Models.new()
	b.ellipsoid(Vector3(0, 0, -0.063), Vector3(0.24, 0.415, 0.062), bronze)
	b.ellipsoid(Vector3(0, 0, -0.099), Vector3(0.221, 0.393, 0.035), cloth.darkened(0.12))
	b.box(Vector3(0, 0, -0.134), Vector3(0.02, 0.72, 0.012), bronze)
	for direction in [-1.0, 1.0]:
		b.box(Vector3(direction * 0.095, 0.15, -0.129), Vector3(0.15, 0.021, 0.012), bronze, Vector3(0, 0, direction * 0.45))
		b.box(Vector3(direction * 0.095, -0.15, -0.129), Vector3(0.15, 0.021, 0.012), bronze, Vector3(0, 0, -direction * 0.45))
	b.ellipsoid(Vector3(0, 0, -0.155), Vector3(0.076, 0.077, 0.035), bronze.darkened(0.2))
	return b.finish()

static func _spear(leather: Color, iron: Color) -> ArrayMesh:
	var b := Models.new()
	b.rod(Vector3(0, -0.93, -0.025), Vector3(0, 0.95, -0.025), 0.012, leather)
	b.rod(Vector3(0, 0.95, -0.025), Vector3(0, 1.23, -0.025), 0.026, iron, 0)
	return b.finish()

static func _equipment(bronze: Color, leather: Color) -> ArrayMesh:
	var b := Models.new()
	# Publicly visible issue of maintained armour; never derives an enemy roster.
	_form(b, [[1.04, 0.180, 0.126, -0.004], [1.18, 0.195, 0.148, -0.005],
		[1.29, 0.212, 0.145, 0.0], [1.345, 0.19, 0.126, 0.0]], bronze.darkened(0.05), 0, 32)
	for side in [-1.0, 1.0]:
		b.rod(Vector3(side * 0.115, 1.25, -0.132), Vector3(side * 0.155, 1.365, 0.08), 0.015, leather)
	return b.finish()

static func _form(builder: RealismModels, rings: Array, color: Color, folds: float, sides: int) -> void:
	# Loft elliptical body sections with shared smooth normals. Small geometric
	# folds and pigment changes survive side light without looking like piping.
	var vertices: Array = []
	var normals: Array = []
	for row in range(rings.size()):
		var ring: Array = rings[row]
		var points: Array[Vector3] = []
		for column in range(sides):
			var angle := TAU * column / sides
			var fold := sin(angle * 8.0 + row * 0.28) * folds * (0.5 if float(ring[0]) > 1.3 else 1.0)
			points.append(Vector3(cos(angle) * (float(ring[1]) + fold), float(ring[0]), sin(angle) * (float(ring[2]) + fold) + float(ring[3])))
		vertices.append(points)
	for row in range(rings.size()):
		var row_normals: Array[Vector3] = []
		for column in range(sides):
			var above: Vector3 = vertices[mini(row + 1, rings.size() - 1)][column]
			var below: Vector3 = vertices[maxi(row - 1, 0)][column]
			var next: Vector3 = vertices[row][(column + 1) % sides]
			var previous: Vector3 = vertices[row][(column - 1 + sides) % sides]
			row_normals.append((above - below).cross(next - previous).normalized())
		normals.append(row_normals)
	for row in range(rings.size() - 1):
		for column in range(sides):
			var next := (column + 1) % sides
			for coordinate in [Vector2i(row, column), Vector2i(row + 1, next), Vector2i(row + 1, column),
				Vector2i(row, column), Vector2i(row, next), Vector2i(row + 1, next)]:
				var angle: float = TAU * coordinate.y / sides
				var tint := color.darkened((0.035 + 0.035 * sin(angle * 8.0 + coordinate.x * 0.28)) if folds > 0 else 0.0)
				builder.surface.set_color(tint)
				builder.surface.set_normal(normals[coordinate.x][coordinate.y])
				builder.surface.add_vertex(vertices[coordinate.x][coordinate.y])
				builder.vertex_count += 1
	var lower := Vector3(0, float(rings[0][0]), float(rings[0][3]))
	var upper := Vector3(0, float(rings[-1][0]), float(rings[-1][3]))
	for column in range(sides):
		_face(builder, vertices[0][column], vertices[0][(column + 1) % sides], lower, color)
		_face(builder, vertices[-1][column], upper, vertices[-1][(column + 1) % sides], color)

static func _drape(builder: RealismModels, color: Color) -> void:
	# Woven mantle hanging across the back, with a real shoulder edge and folds.
	for column in range(12):
		var x0 := -0.19 + float(column) / 12.0 * 0.37
		var x1 := -0.19 + float(column + 1) / 12.0 * 0.37
		var top_a := Vector3(x0, 1.365 - absf(x0) * 0.08, 0.102)
		var top_b := Vector3(x1, 1.365 - absf(x1) * 0.08, 0.102)
		var low_a := Vector3(x0 * 0.96, 0.81 + x0 * 0.28, 0.148 + sin(column * 2.3) * 0.016)
		var low_b := Vector3(x1 * 0.96, 0.81 + x1 * 0.28, 0.148 + sin((column + 1) * 2.3) * 0.016)
		_face(builder, top_a, low_a, low_b, color.darkened((column % 3) * 0.035))
		_face(builder, top_a, low_b, top_b, color.darkened((column % 3) * 0.035))

static func _head(builder: RealismModels, face_width: float, skin: Color, hair: Color, variant: int) -> void:
	var sections := [[1.482, 0.039, 0.047, -0.016], [1.509, face_width * 0.77, 0.065, -0.009],
		[1.547, face_width * 0.94, 0.079, 0.001], [1.578, face_width, 0.084, 0.006],
		[1.609, face_width * 0.98, 0.086, 0.007], [1.654, face_width * 0.97, 0.083, 0.008],
		[1.692, face_width * 0.75, 0.067, 0.01], [1.718, 0.013, 0.022, 0.014]]
	var vertices: Array = []
	var tints: Array = []
	var sides := 64
	for row in range(43):
		var y := lerpf(1.482, 1.718, float(row) / 42.0)
		var section := 0
		while section < sections.size() - 2 and y > float(sections[section + 1][0]):
			section += 1
		var a: Array = sections[section]
		var b: Array = sections[section + 1]
		var amount := clampf((y - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
		var width := lerpf(float(a[1]), float(b[1]), amount)
		var depth := lerpf(float(a[2]), float(b[2]), amount)
		var center_z := lerpf(float(a[3]), float(b[3]), amount)
		var points: Array[Vector3] = []
		var colors: Array[Color] = []
		for column in range(sides):
			var angle := TAU * column / sides
			var x := cos(angle) * width
			var front := pow(maxf(0.0, -sin(angle)), 5.0)
			var z := center_z + sin(angle) * depth
			var relief := -0.025 * _bump(x, y, 0, 1.594, 0.010, 0.032)
			relief -= 0.028 * _bump(x, y, 0, 1.575, 0.016, 0.010)
			relief -= 0.010 * _bump(x, y, 0, 1.541, 0.030, 0.017)
			relief -= 0.009 * _bump(x, y, 0, 1.504, 0.035, 0.015)
			for side in [-1.0, 1.0]:
				relief += 0.006 * _bump(x, y, side * 0.034, 1.609, 0.020, 0.010)
				relief -= 0.007 * _bump(x, y, side * 0.035, 1.629, 0.027, 0.008)
				relief -= 0.006 * _bump(x, y, side * 0.052, 1.577, 0.026, 0.019)
				relief -= 0.007 * _bump(x, y, side * 0.015, 1.570, 0.008, 0.007)
			points.append(Vector3(x, y, z + relief * front))
			var color := skin
			var cheek := _bump(absf(x), y, 0.046, 1.568, 0.028, 0.023) * front
			color = color.lerp(Color(skin.r * 1.025, skin.g * 0.96, skin.b * 0.96, skin.a), cheek * 0.5)
			if variant % 4 == 3 and y < 1.565:
				var beard := clampf((1.565 - y) * 13.0, 0, 0.50) * maxf(0, -sin(angle))
				color = color.lerp(hair, beard)
			color.a = 0.10
			colors.append(color)
		vertices.append(points)
		tints.append(colors)
	_grid_surface(builder, vertices, tints)

static func _bump(x: float, y: float, cx: float, cy: float, width: float, height: float) -> float:
	var u := (x - cx) / width
	var v := (y - cy) / height
	return exp(-2.0 * (u * u + v * v))

static func _hair(builder: RealismModels, face_width: float, color: Color, variant: int) -> void:
	var vertices: Array = []
	var tints: Array = []
	var sides := 48
	var rows := 12
	for row in range(rows + 1):
		var points: Array[Vector3] = []
		var colors: Array[Color] = []
		for column in range(sides):
			var angle := TAU * column / sides
			var latitude := float(row) / rows * PI * 0.5
			var edge := 1.600 + maxf(0, -sin(angle)) * 0.065 - maxf(0, sin(angle)) * 0.025
			var clump := sin(angle * 13.0 + row * 0.25 + variant) * 0.0018
			points.append(Vector3(cos(angle) * (face_width + 0.005 + clump) * cos(latitude),
				lerpf(edge, 1.725, sin(latitude)), 0.013 + sin(angle) * (0.092 + clump) * cos(latitude)))
			colors.append(color.lightened(0.02 if (column + variant) % 3 == 0 else 0.0))
		vertices.append(points)
		tints.append(colors)
	_grid_surface(builder, vertices, tints)
	# Combed strands follow the scalp; the silhouette remains close-cut rather
	# than ending in floating spikes or an independent helmet-like shell.
	for strand in range(24):
		var base_angle := TAU * float(strand) / 24.0
		for segment in range(6):
			var line: Array[Vector3] = []
			for end in [segment, segment + 1]:
				var latitude := 0.025 + float(end) / 6.0 * 1.24
				var angle := base_angle + sin(latitude) * (0.18 if variant % 2 == 0 else -0.18)
				var edge := 1.600 + maxf(0, -sin(angle)) * 0.065 - maxf(0, sin(angle)) * 0.025
				var clump := sin(angle * 13.0 + latitude * rows / (PI * 0.5) * 0.25 + variant) * 0.0018
				line.append(Vector3(cos(angle) * (face_width + 0.006 + clump) * cos(latitude),
					lerpf(edge, 1.726, sin(latitude)), 0.013 + sin(angle) * (0.093 + clump) * cos(latitude)))
			builder.rod(line[0], line[1], 0.0007, color.lightened(0.035 if strand % 3 == 0 else 0.012), 0.0005)

static func _grid_surface(builder: RealismModels, vertices: Array, tints: Array) -> void:
	var rows := vertices.size()
	var sides: int = vertices[0].size()
	var normals: Array = []
	for row in range(rows):
		var row_normals: Array[Vector3] = []
		for column in range(sides):
			var above: Vector3 = vertices[mini(row + 1, rows - 1)][column]
			var below: Vector3 = vertices[maxi(row - 1, 0)][column]
			var next: Vector3 = vertices[row][(column + 1) % sides]
			var previous: Vector3 = vertices[row][(column - 1 + sides) % sides]
			row_normals.append((above - below).cross(next - previous).normalized())
		normals.append(row_normals)
	for row in range(rows - 1):
		for column in range(sides):
			var next := (column + 1) % sides
			for coordinate in [Vector2i(row, column), Vector2i(row + 1, next), Vector2i(row + 1, column),
				Vector2i(row, column), Vector2i(row, next), Vector2i(row + 1, next)]:
				builder.surface.set_color(tints[coordinate.x][coordinate.y])
				builder.surface.set_normal(normals[coordinate.x][coordinate.y])
				builder.surface.add_vertex(vertices[coordinate.x][coordinate.y])
				builder.vertex_count += 1

static func _face(builder: RealismModels, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	# Godot's front-face order is clockwise: its primitive meshes have a
	# negative dot product between geometric cross product and vertex normal.
	# Keep the intended outward normal while reversing the emitted winding.
	var normal := (b - a).cross(c - a).normalized()
	for point in [a, c, b]:
		builder.surface.set_color(tint)
		builder.surface.set_normal(normal)
		builder.surface.add_vertex(point)
		builder.vertex_count += 1
