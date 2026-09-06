class_name RealismUnitModels
extends RefCounted
## Public unit-art specifications only. Never resolve a rival's roster here.
static func build(tint: Color, kind: String, look: Dictionary = {}) -> ArrayMesh:
	if kind in ["cavalry", "horse_archer", "general_bodyguard"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(RealismModels.horse(), 0, Transform3D.IDENTITY)
		st.append_from(RealismModels.soldier(tint, look.get("shield", "") == "round", kind == "general_bodyguard", look), 0, Transform3D(Basis.IDENTITY, Vector3.UP))
		return st.commit()
	if kind not in ["elephant", "ship", "siege", "chariot"]:
		return RealismModels.soldier(tint, look.get("shield", "") == "round", false, look)
	var b := RealismModels.new()
	var wood := RealismModels.pigment("#63513a")
	var iron := RealismModels.pigment("#64695f", 0.6)
	var linen := RealismModels.pigment("#bdb498")
	tint.a = 0.0
	if kind == "elephant":
		var hide := RealismModels.pigment("#73736c")
		b.ellipsoid(Vector3(0, 1.5, 0), Vector3(0.8, 0.85, 1.35), hide)
		b.ellipsoid(Vector3(0, 2.0, -1.1), Vector3(0.65, 0.65, 0.6), hide)
		for side in [-1.0, 1.0]:
			b.ellipsoid(Vector3(side * 0.69, 2.0, -0.85), Vector3(0.14, 0.65, 0.45), hide.darkened(0.15))
			b.rod(Vector3(side * 0.42, 1.8, -1.4), Vector3(side * 0.43, 1.4, -2.3), 0.11, linen, 0.015)
			for z in [-0.8, 0.8]:
				b.rod(Vector3(side * 0.55, 0.1, z), Vector3(side * 0.55, 1.5, z), 0.24, hide)
		for i in range(7):
			var a := Vector3(0, 2.0 - i * 0.22, -1.57 - sin(i * 0.35) * 0.2)
			var c := Vector3(0, 2.0 - (i + 1) * 0.22, -1.57 - sin((i + 1) * 0.35) * 0.2)
			b.rod(a, c, 0.18 - i * 0.015, hide)
		b.box(Vector3(0, 2.5, 0.05), Vector3(1.05, 0.65, 1.4), wood)
		b.box(Vector3(0, 2.37, 0), Vector3(1.65, 0.12, 1.75), tint)
	elif kind == "ship":
		b.ellipsoid(Vector3(0, 0.38, 0), Vector3(0.65, 0.42, 2.7), wood)
		b.box(Vector3(0, 0.65, 0), Vector3(1.0, 0.12, 4.3), wood.lightened(0.2))
		b.rod(Vector3(0, 0.6, -0.1), Vector3(0, 3.8, -0.1), 0.08, wood)
		b.rod(Vector3(-1.35, 3.55, -0.1), Vector3(1.35, 3.55, -0.1), 0.06, wood)
		b.triangle(Vector3(-1.3, 3.5, -0.1), Vector3(1.3, 3.5, -0.1), Vector3(-1.1, 1.7, -0.3), linen)
		b.triangle(Vector3(1.3, 3.5, -0.1), Vector3(1.1, 1.7, -0.3), Vector3(-1.1, 1.7, -0.3), linen)
		for side in [-1.0, 1.0]:
			for i in range(10):
				b.rod(Vector3(side * 0.5, 0.45, i * 0.4 - 1.8), Vector3(side * 1.9, 0.08, i * 0.4 - 1.55), 0.035, wood)
		b.rod(Vector3(0, 0.24, -2.2), Vector3(0, 0.24, -3.0), 0.15, iron, 0.035)
	else:
		b.box(Vector3(0, 0.65, 0), Vector3(1.4, 0.25, 1.8), wood)
		for side in [-1.0, 1.0]:
			for z in [-0.55, 0.55]:
				b.ellipsoid(Vector3(side * 0.78, 0.45, z), Vector3(0.10, 0.43, 0.43), wood)
		if kind == "siege":
			b.rod(Vector3(-0.85, 1.2, -0.8), Vector3(0, 1.25, -0.3), 0.1, wood)
			b.rod(Vector3(0.85, 1.2, -0.8), Vector3(0, 1.25, -0.3), 0.1, wood)
			b.rod(Vector3(-0.8, 1.2, -0.8), Vector3(0.8, 1.2, -0.8), 0.02, linen)
			b.rod(Vector3(0, 1.25, 0.8), Vector3(0, 1.25, -1.8), 0.06, wood)
		else:
			b.box(Vector3(0, 1.1, -0.6), Vector3(1.4, 0.85, 0.15), tint)
			b.surface.append_from(RealismModels.horse(), 0, Transform3D(Basis.IDENTITY, Vector3(0, 0, -2.3)))
	return b.finish()
