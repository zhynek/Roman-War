class_name PortModel
extends RefCounted
## Original batched architecture. Every major solid uses PortLayout's footprint;
## plank joints, masonry courses and rigging are presentation details only.
var model := RealismModels.new()
var stone := Color("b7aa8d")
var timber := Color("73523a")
var roof := Color("a55338")
var linen := Color("d8c7a0")
var fine := true
var illustrative := true

static func build(layout: Dictionary, navigation: bool = false, detail: bool = true) -> ArrayMesh:
	var art := PortModel.new()
	art.fine = detail
	art.illustrative = layout.get("illustrative", false)
	art._build(layout, navigation)
	return art.model.finish()

func slab(rect: Array, y: float, height: float, color: Color) -> void:
	model.box(Vector3(rect[0] + rect[2] * 0.5, y, rect[1] + rect[3] * 0.5), Vector3(rect[2], height, rect[3]), color)

func _build(layout: Dictionary, navigation: bool) -> void:
	slab(layout["water"], -0.65, 0.3, Color("285866"))
	slab(layout["land"], -0.6, 1.2, Color("a99570"))
	for bank in layout.get("banks",[]):
		slab(bank,-0.2,1.0,Color("6c7855") if layout["setting"]=="riverbank" else Color("a59879"))
	# Shallow shore wash and a continuous, readable land-water boundary.
	slab([-60,6,120,2], -0.35, 0.12, Color("688b85"))
	if fine:
		for z in range(12,48,5):
			for x in range(-52,54,13):
				model.box(Vector3(x + sin(z) * 2, -0.46, z), Vector3(5,0.035,0.10), Color("497b85"))
	for channel in layout.get("channels", []):
		slab(channel["rect"],0.09,0.1,Color("285866"))
	for feature in layout["structures"]:
		_feature(feature)
	# Berths are docking envelopes, not walls. Reference boats are illustrative
	# fittings of the port diorama, never a hidden fleet roster.
	for berth in layout["berths"]:
		if not illustrative:
			continue
		var r: Array = berth["rect"]
		_boat(Vector3(r[0]+r[2]*0.5, 0.1, r[1]+r[3]*0.5), minf(12, r[3]*0.75), int(layout["stage"]) >= 3)
	if int(layout["stage"]) > 0:
		for x in [-19,-8]:
			model.rod(Vector3(x,0,4),Vector3(x,1.7,4),0.18,timber)
			if fine:
				model.rod(Vector3(x,1.1,4),Vector3(-9,0.5,13),0.045,linen)
	if int(layout["stage"]) >= 3:
		_crane(Vector3(-41,1,7))
	if int(layout["stage"]) >= 5:
		_crane(Vector3(-6,1.1,15))
	if navigation:
		for area in layout["walkable"]:
			slab(area, 1.06, 0.04, Color("659e7c"))
		for channel in layout.get("channels", []):
			slab(channel["rect"],1.10,0.04,Color("285866"))
		for bridge in layout.get("bridges", []):
			slab(bridge["rect"],1.14,0.04,Color("c9bd8b"))
		for obstacle in layout["obstacles"]:
			slab(obstacle["rect"], float(obstacle["height"])+0.2, 0.08, Color("b57359"))
		for route in layout["routes"]:
			var points: Array = route["points"]
			for i in range(points.size()-1):
				model.rod(Vector3(points[i][0],1.3,points[i][1]),Vector3(points[i+1][0],1.3,points[i+1][1]),0.30,Color("f2d180"))
		for gate in layout["gates"]:
			slab(gate["rect"], 1.2, 0.12, Color("b8dfce"))

func _feature(f: Dictionary) -> void:
	var r: Array = f["rect"]
	var kind: String = f["kind"]
	var h := float(f["height"])
	var center := Vector3(r[0]+r[2]*0.5, 0, r[1]+r[3]*0.5)
	if kind in ["road", "court"]:
		slab(r,0.04,0.10,Color("b9ad90") if kind=="court" else Color("8e856d"))
		if fine:
			for z in range(ceili(r[1]), floori(r[1]+r[3]), 2):
				model.box(Vector3(center.x,0.11,z),Vector3(r[2],0.025,0.045),Color("786e5c"))
		return
	if kind in ["pier", "ramp", "quay", "breakwater", "bridge"]:
		var wood := kind in ["pier", "ramp", "bridge"]
		if kind in ["ramp", "bridge"]:
			# Walking and rendering use the same sloping surface.
			var sections := 16
			for i in range(sections):
				var z0: float = r[1]+r[3]*i/sections
				var z1: float = r[1]+r[3]*(i+1)/sections
				if kind == "ramp":
					var a := Vector3(r[0],h*i/sections,z0)
					var b := Vector3(r[0]+r[2],h*i/sections,z0)
					var c := Vector3(r[0]+r[2],h*(i+1)/sections,z1)
					var d := Vector3(r[0],h*(i+1)/sections,z1)
					model.triangle(a,c,b,timber)
					model.triangle(a,d,c,timber)
				else:
					var x0: float = r[0]+r[2]*i/sections
					var x1: float = r[0]+r[2]*(i+1)/sections
					var h0: float = h*minf(1,minf(x0-r[0],r[0]+r[2]-x0)/2)
					var h1: float = h*minf(1,minf(x1-r[0],r[0]+r[2]-x1)/2)
					model.triangle(Vector3(x0,h0,r[1]),Vector3(x1,h1,r[1]+r[3]),Vector3(x1,h1,r[1]),timber)
					model.triangle(Vector3(x0,h0,r[1]),Vector3(x0,h0,r[1]+r[3]),Vector3(x1,h1,r[1]+r[3]),timber)
			return
		slab(r,h*0.5,h,timber if wood else stone)
		if fine:
			for z in range(ceili(r[1]),floori(r[1]+r[3])):
				model.box(Vector3(center.x,h+0.03,z),Vector3(r[2]-0.15,0.06,0.13),timber.lightened(0.25) if wood else stone.darkened(0.2))
			for x in [r[0]+0.35,r[0]+r[2]-0.35]:
				for z in range(ceili(r[1])+1,floori(r[1]+r[3]),4):
					model.rod(Vector3(x,-1,z),Vector3(x,h+0.7,z),0.18,timber.darkened(0.15))
		return
	if kind == "cargo":
		for x in range(3):
			for z in range(2):
				model.box(center+Vector3(x-1,0.7,z-0.5),Vector3(0.8,1.3,0.8),timber.lightened(0.22))
		return
	if kind == "monument":
		slab(r,0.5,1,stone)
		model.rod(center+Vector3.UP,center+Vector3.UP*h,0.6,stone.lightened(0.2))
		model.box(center+Vector3.UP*h,Vector3(2,0.8,2),stone)
		return
	if kind == "wall":
		slab(r,h*0.5,h,stone.darkened(0.12))
		for i in range(0,ceili(maxf(r[2],r[3])),3):
			var at := Vector3(r[0]+(i if r[2]>r[3] else r[2]*0.5),h+0.4,r[1]+(i if r[3]>r[2] else r[3]*0.5))
			model.box(at,Vector3(1.4,0.8,1.4),stone)
		return
	var masonry := not kind in ["shed", "shipshed", "workshop", "market"]
	var color := stone if masonry else timber.lightened(0.20)
	if kind == "shipshed":
		for x in [r[0]+0.4,r[0]+r[2]-0.4]:
			for z in range(ceili(r[1])+1,floori(r[1]+r[3]),4):
				model.rod(Vector3(x,0,z),Vector3(x,h,z),0.25,timber)
		if illustrative:
			_boat(center+Vector3(0,1.3,0),r[3]*0.8,false)
	else:
		slab(r,h*0.5,h,color)
	if kind in ["tower", "beacon"]:
		slab([r[0]-0.25,r[1]-0.25,r[2]+0.5,r[3]+0.5],h,0.5,stone.lightened(0.1))
		for x in [r[0],r[0]+r[2]-1]:
			for z in [r[1],r[1]+r[3]-1]:
				model.box(Vector3(x+0.5,h+0.7,z+0.5),Vector3(1.1,1.3,1.1),stone)
		if kind == "beacon":
			model.ellipsoid(center+Vector3.UP*(h+0.4),Vector3(1.2,0.4,1.2),Color("dc9849"))
	else:
		var ridge := h+minf(2.2,r[2]*0.20)
		for side in [-1,1]:
			var outer: float = center.x+side*(r[2]*0.5+0.35)
			var a := Vector3(outer,h,r[1]-0.3)
			var b := Vector3(center.x,ridge,r[1]-0.3)
			var c := Vector3(center.x,ridge,r[1]+r[3]+0.3)
			var d := Vector3(outer,h,r[1]+r[3]+0.3)
			model.triangle(a,b,c,roof if side<0 else roof.lightened(0.13))
			model.triangle(a,c,d,roof if side<0 else roof.lightened(0.13))
		if fine:
			for z in range(ceili(r[1]),floori(r[1]+r[3])):
				model.rod(Vector3(r[0]-0.3,h+0.04,z),Vector3(center.x,ridge+0.04,z),0.045,roof.lightened(0.24))
				model.rod(Vector3(center.x,ridge+0.04,z),Vector3(r[0]+r[2]+0.3,h+0.04,z),0.045,roof.lightened(0.24))
	if fine and kind != "shipshed":
		# Door faces the open lane/quay; upper slots and stone courses reinforce scale.
		model.box(Vector3(center.x,1.3,r[1]+r[3]+0.03),Vector3(1.8,2.6,0.08),Color("433c31"))
		for x in range(ceili(r[0])+2,floori(r[0]+r[2])-1,3):
			model.box(Vector3(x,maxf(2.8,h-1.1),r[1]+r[3]+0.06),Vector3(0.65,0.75,0.08),Color("5d5548"))
		for y in range(1,floori(h)):
			model.box(Vector3(center.x,y,r[1]+r[3]+0.01),Vector3(r[2],0.035,0.04),color.darkened(0.2))

func _crane(at: Vector3) -> void:
	for side in [-1,1]:
		model.rod(at+Vector3(side*1.4,0,0),at+Vector3(0,7,0),0.18,timber)
	model.rod(at+Vector3(0,6,0),at+Vector3(0,7,5),0.2,timber)
	model.rod(at+Vector3(0,7,5),at+Vector3(0,1.2,5),0.06,linen)
	model.box(at+Vector3(0,0.8,5),Vector3(1.8,1.5,1.8),timber.lightened(0.3))

func _boat(at: Vector3, length: float, sail: bool) -> void:
	model.ellipsoid(at,Vector3(length*0.20,0.85,length*0.5),timber.darkened(0.22))
	model.box(at+Vector3.UP*0.5,Vector3(length*0.32,0.25,length*0.7),timber.lightened(0.22))
	if sail:
		model.rod(at+Vector3.UP*0.5,at+Vector3.UP*7,0.12,timber)
		model.box(at+Vector3(0,4.7,0),Vector3(length*0.55,3.8,0.08),linen)
		model.rod(at+Vector3.UP*7,at+Vector3(0,1,length*0.4),0.025,timber)
		model.rod(at+Vector3.UP*7,at+Vector3(0,1,-length*0.4),0.025,timber)
	elif fine:
		for z in range(-3,4,2):
			model.box(at+Vector3(0,0.72,z),Vector3(length*0.3,0.12,0.24),linen.darkened(0.4))
