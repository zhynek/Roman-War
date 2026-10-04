extends RefCounted
## Original Byzantine architectural analogies. All ordinary sites and elevations
## are interpretive. Selection is stable per plot and never touches simulation RNG.
const Geometry = preload("res://src/geometry.gd")
var config: Dictionary
var materials: Dictionary
var types: Dictionary = {}
var _cache: Dictionary = {}

func _init(p_config: Dictionary, p_materials: Dictionary = {}) -> void:
	config = p_config
	materials = p_materials
	for record: Dictionary in config["types"]:
		types[str(record["id"])] = record

func select(item: Dictionary) -> String:
	var profile: Array = config["district_profiles"][str(item["style"])]
	var total := 0.0
	for row: Dictionary in profile:
		total += float(row["weight"])
	# Plot ids differ by small hash increments along a street. A linear modulo
	# transform preserves that correlation and creates long strips of one type.
	# Each local seeded stream is independent; no campaign or shared RNG is used.
	var rng:=RandomNumberGenerator.new()
	rng.seed=int(item["seed"]) ^ 187391
	var draw:float=rng.randf()*total
	for row: Dictionary in profile:
		draw -= float(row["weight"])
		if draw < 0.0:
			return str(row["type_id"])
	return str(profile[-1]["type_id"])

func floors_for(item: Dictionary, type_id: String) -> int:
	return clampi(roundi((float(item["size"].y)-1.1)/3.1),1,int(types[type_id]["max_floors"]))

func height_for(type_id: String, floors: int) -> float:
	var plan: String = types[type_id]["plan"]
	if plan == "cross_domed": return 8.5
	if plan == "basilica": return 7.0
	if plan == "water": return 4.0
	if plan == "market": return 4.2
	return float(floors)*float(config["dimensions"]["floor_height_m"])+1.6

func mesh(type_id: String, detail: bool, floors: int = 2) -> ArrayMesh:
	floors = clampi(floors,1,int(types[type_id]["max_floors"]))
	var cache_key := "%s:%s:%d" % [type_id,detail,floors]
	if _cache.has(cache_key): return _cache[cache_key]
	var type: Dictionary = types[type_id]
	var g = Geometry.new(materials)
	var h: float = float(floors)*float(config["dimensions"]["floor_height_m"])
	var wall: String = type["wall_material"]
	var plan: String = type["plan"]
	match plan:
		"hall":
			_block(g,Vector2(-0.6,-0.7),Vector2(6.7,9.4),h,wall,"gable",detail,floors)
			_block(g,Vector2(3.35,1.9),Vector2(2.6,4.0),minf(h,3.0),"stone","hip",detail,1)
			if detail: _entry(g,Vector3(-1.6,0,4.04),1.15)
		"hipped":
			_block(g,Vector2(0,-0.65),Vector2(8.7,9.5),h,wall,"hip",detail,floors)
			_porch(g,Vector3(-1.2,0,4.65),Vector2(4.0,2.0),2.7,"roof",detail)
			if detail: _entry(g,Vector3(-1.2,0,4.15),1.25)
		"l_court", "weaver":
			_court(g)
			_block(g,Vector2(0,-3.6),Vector2(9.1,3.6),h,wall,"hip",detail,floors)
			_block(g,Vector2(-3.0,1.55),Vector2(3.1,6.7),maxf(3.0,h-1.25),wall,"gable",detail,maxi(1,floors-1))
			_boundary(g,Vector2(1.25,5.48),Vector2(6.55,0.22),1.0)
			if plan == "weaver": _porch(g,Vector3(1.9,0,2.25),Vector2(4.3,4.05),2.9,"linen",detail)
			if detail:
				_entry(g,Vector3(1.5,0,-1.74),1.2)
				if floors>=2:
					# External stair reaches the upper doorway of the rear wing.
					var landing:float=float(config["dimensions"]["floor_height_m"])
					_stair(g,Vector3(0.2,0.18,1.36),landing-0.18)
					g.box(Vector3(0.2,landing-0.10,-1.36),Vector3(1.3,0.2,0.8),"stone")
					_entry(g,Vector3(0.2,landing,-1.70),1.0)
				if plan == "weaver": _weaving(g,Vector3(1.75,0,1.2))
				else: _well(g,Vector3(2.1,0,2.55),0.56,false)
		"u_court":
			_court(g)
			_block(g,Vector2(0,-3.85),Vector2(9.1,3.1),h,wall,"hip",detail,floors)
			for side in [-1.0,1.0]:
				_block(g,Vector2(side*3.2,1.55),Vector2(2.7,7.05),maxf(3.0,h-(0.7 if side<0 else 1.6)),wall,"gable",detail,maxi(1,floors-1))
			if detail:
				_well(g,Vector3(0,0,1.6),0.57,false)
				_entry(g,Vector3(0,0,-2.24),1.25)
				_gallery(g,Vector3(-1.62,0,1.5),6.1,2.8)
		"paired":
			_block(g,Vector2(-2.35,-0.55),Vector2(4.1,9.5),h,wall,"gable",detail,floors)
			_block(g,Vector2(2.3,0.6),Vector2(4.0,8.0),maxf(2.9,h-1.1),"plaster","hip",detail,maxi(1,floors-1))
			if detail:
				_entry(g,Vector3(-2.35,0,4.25),1.1)
				_entry(g,Vector3(2.3,0,4.65),1.1)
		"garden":
			_court(g)
			_block(g,Vector2(-0.7,-2.35),Vector2(7.4,6.1),h,wall,"hip",detail,floors)
			_porch(g,Vector3(-0.7,0,1.9),Vector2(7.4,2.3),2.7,"roof",detail)
			if detail:
				_entry(g,Vector3(-1.1,0,0.75),1.2)
				for x in [-2.8,-0.2,2.4]:
					g.box(Vector3(x,0.27,4.4),Vector3(1.8,0.42,1.15),"earth")
					g.box(Vector3(x,0.52,4.4),Vector3(1.5,0.1,0.8),"green")
		"shop":
			_block(g,Vector2(0,-1.45),Vector2(9.0,7.8),h,wall,"hip",detail,floors)
			for x in [-2.3,2.3]:
				_porch(g,Vector3(x,0,3.95),Vector2(4.2,2.55),2.55,"linen",detail)
				if detail:
					g.box(Vector3(x,1.25,2.51),Vector3(2.2,2.5,0.10),"dark")
					g.box(Vector3(x,0.95,4.2),Vector3(3.5,0.2,1.0),"wood")
					for j in range(3): _vessel(g,Vector3(x+(j-1)*0.8,1.05,4.2),0.22,0.4,"roof")
		"storehouse":
			_block(g,Vector2(-0.7,-0.85),Vector2(7.5,9.0),h,wall,"gable",detail,floors)
			_porch(g,Vector3(-0.7,0,4.5),Vector2(6.5,2.05),2.65,"roof",detail)
			if detail:
				_entry(g,Vector3(-0.7,0,3.71),2.25)
				for j in range(4): _vessel(g,Vector3(3.65,0,3.8-j*1.1),0.45,1.15,"roof")
		"potter", "smith", "baker":
			_court(g)
			if plan == "smith":
				_block(g,Vector2(-1.75,-1.35),Vector2(5.5,7.95),h,wall,"hip",detail,floors)
				_porch(g,Vector3(2.85,0,0.5),Vector2(3.15,5.6),2.8,"roof",detail)
			else:
				_block(g,Vector2(-0.4,-3.0),Vector2(8.4,4.65),h,wall,"gable",detail,floors)
				_porch(g,Vector3(-2.55,0,2.0),Vector2(3.85,3.75) if plan=="baker" else Vector2(3.6,5.2),2.8,"roof",detail)
			if plan == "baker": _oven(g,Vector3(-2.55,0,1.2))
			if detail:
				_entry(g,Vector3(-0.8,0,2.68 if plan=="smith" else -0.62),1.25)
				match plan:
					"potter":
						for j in range(3):
							for k in range(3): _vessel(g,Vector3(0.25+j*1.2,0,0.8+k*1.6),0.29+float((j+k)%2)*0.12,0.8+float(j%2)*0.3,"roof")
						g.box(Vector3(-2.65,0.75,2.2),Vector3(2.5,0.15,1.3),"wood")
						g.cylinder(Vector3(-2.65,0.55,2.2),0.45,0.35,"wood")
					"smith": _forge(g,Vector3(2.85,0,-0.5))
		"basilica", "cross_domed": _church(g,plan,detail)
		"water":
			_court(g)
			_well(g,Vector3(-1.6,0,-1.0),1.05,true)
			_porch(g,Vector3(-1.6,0,-1.0),Vector2(4.5,4.5),3.0,"roof",detail)
			_trough(g,Vector3(1.35,0,3.0),Vector2(5.1,1.55))
			if detail:
				for z in [-3.5,-0.6]: g.box(Vector3(3.35,0.45,z),Vector3(1.0,0.9,2.0),"stone")
		"market":
			_court(g)
			for x in [-2.8,2.8]:
				for z in [-2.6,2.6]:
					_porch(g,Vector3(x,0,z),Vector2(3.55,4.3),2.8,"roof" if x<0 else "linen",detail)
					if detail:
						g.box(Vector3(x,0.95,z),Vector3(2.6,0.16,2.0),"wood")
						for j in range(2): _vessel(g,Vector3(x+(j-0.5)*0.8,1.06,z),0.28,0.5,"roof")
	var result: ArrayMesh = g.finish()
	_cache[cache_key] = result
	return result

func _block(g, at: Vector2, size: Vector2, h: float, wall: String, roof: String, detail: bool, floors: int) -> void:
	var base: float = float(config["dimensions"]["foundation_depth_m"])
	g.box(Vector3(at.x,-base*0.5,at.y),Vector3(size.x,base,size.y),"stone")
	g.box(Vector3(at.x,h*0.5,at.y),Vector3(size.x,h,size.y),wall)
	g.box(Vector3(at.x,0.2,at.y),Vector3(size.x+0.12,0.4,size.y+0.12),"stone")
	var roof_at := Vector3(at.x,h,at.y)
	if roof == "hip": _hip(g,roof_at,size+Vector2.ONE*0.28,minf(1.6,size.x*0.22))
	else: g.roof(roof_at,size.x+0.28,size.y+0.28,minf(1.6,size.x*0.25),"roof")
	if not detail: return
	g.box(Vector3(at.x,h-0.12,at.y),Vector3(size.x+0.14,0.17,size.y+0.14),"wood")
	for floor_index in range(floors):
		var y: float = minf(h-0.8,1.8+floor_index*3.05)
		if y < 0.9: continue
		for side in [-1.0,1.0]:
			var count: int = maxi(1,floori(size.x/2.8))
			for i in range(count):
				var x: float = at.x+(float(i)-float(count-1)*0.5)*2.45
				_window(g,Vector3(x,y,at.y+side*(size.y*0.5+0.045)),Vector2(0.8,1.12),0.0,side>0 and (i+floor_index)%2==0)
			var side_count: int = maxi(1,floori(size.y/3.1))
			for i in range(side_count):
				var z: float = at.y+(float(i)-float(side_count-1)*0.5)*2.7
				_window(g,Vector3(at.x+side*(size.x*0.5+0.045),y,z),Vector2(0.7,0.95),PI*0.5,false)
		if floor_index > 0:
			g.box(Vector3(at.x,minf(h-0.4,floor_index*3.05+0.3),at.y),Vector3(size.x+0.1,0.11,size.y+0.1),"brick")

func _hip(g, at: Vector3, size: Vector2, rise: float) -> void:
	var a := at+Vector3(-size.x*0.5,0,-size.y*0.5)
	var b := at+Vector3(size.x*0.5,0,-size.y*0.5)
	var c := at+Vector3(size.x*0.5,0,size.y*0.5)
	var d := at+Vector3(-size.x*0.5,0,size.y*0.5)
	var ridge: float = maxf(0.2,size.y*0.5-size.x*0.36)
	var e := at+Vector3(0,rise,-ridge)
	var f := at+Vector3(0,rise,ridge)
	g._oriented_quad(a,d,f,e,Vector3(-1,1,0),"roof")
	g._oriented_quad(b,e,f,c,Vector3(1,1,0),"roof")
	_up(g,a,e,b,"roof")
	_up(g,c,f,d,"roof")
	g.rod(e,f,0.105,"roof",-1.0,6)

func _up(g,a:Vector3,b:Vector3,c:Vector3,mat:String) -> void:
	if (c-a).cross(b-a).y<0: g.triangle(c,b,a,mat)
	else: g.triangle(a,b,c,mat)

func _window(g, at: Vector3, size: Vector2, yaw: float, shutter: bool) -> void:
	var basis := Basis(Vector3.UP,yaw)
	g.box(at,Vector3(size.x,size.y,0.075),"dark",Vector3(0,yaw,0))
	g.box(at+basis*Vector3(0,-size.y*0.5-0.06,0),Vector3(size.x+0.22,0.12,0.2),"stone",Vector3(0,yaw,0))
	g.box(at,Vector3(0.07,size.y,0.12),"wood",Vector3(0,yaw,0))
	if shutter: g.box(at+basis*Vector3(size.x*0.5+0.25,0,0.1),Vector3(0.38,size.y,0.095),"wood",Vector3(0,yaw+0.18,0))

func _entry(g, at: Vector3, width: float) -> void:
	g.box(at+Vector3(0,1.16,0),Vector3(width,2.32,0.13),"wood")
	for side in [-1.0,1.0]: g.box(at+Vector3(side*(width*0.5+0.1),1.22,0.03),Vector3(0.16,2.44,0.20),"stone")
	g.box(at+Vector3(0,2.5,0.02),Vector3(width+0.42,0.17,0.25),"stone")
	g.box(at+Vector3(0,0.08,0.28),Vector3(width+0.5,0.16,0.65),"stone")
	g.box(at+Vector3(width*0.28,1.12,0.09),Vector3(0.09,0.13,0.04),"dark")

func _court(g) -> void:
	# A deliberately level earth terrace supports the court's furniture on relief.
	var depth: float = float(config["dimensions"]["foundation_depth_m"])
	g.box(Vector3(0,(-depth+0.18)*0.5,0),Vector3(9.5,depth+0.18,11.5),"earth")

func _boundary(g, at:Vector2,size:Vector2,h:float) -> void:
	g.box(Vector3(at.x,h*0.5,at.y),Vector3(size.x,h,size.y),"stone")

func _porch(g,at:Vector3,size:Vector2,h:float,cover:String,detail:bool) -> void:
	var foundation:float=config["dimensions"]["foundation_depth_m"]
	for sx in [-1.0,1.0]:
		for sz in [-1.0,1.0]:
			var foot:=at+Vector3(sx*(size.x*0.5-0.17),0,sz*(size.y*0.5-0.17))
			# Whole plots sit at their highest terrain sample. Deep individual
			# stone supports reach downhill ground without filling the open porch.
			g.box(foot-Vector3.UP*foundation*0.5,Vector3(0.36,foundation,0.36),"stone")
			g.box(foot+Vector3.UP*h*0.5,Vector3(0.16,h,0.16),"wood")
	if cover == "roof": _hip(g,at+Vector3.UP*h,size,0.75)
	else: g.box(at+Vector3.UP*h,size_to_3d(size,0.08),cover,Vector3(0.055,0,0))
	if detail:
		for x in [-size.x*0.5+0.18,size.x*0.5-0.18]:
			g.box(at+Vector3(x,h-0.14,0),Vector3(0.18,0.22,size.y),"wood")
		for i in range(4): g.box(at+Vector3((i-1.5)*size.x/4.0,h-0.075,0),Vector3(0.09,0.1,size.y),"wood")

func size_to_3d(size:Vector2,h:float) -> Vector3:
	return Vector3(size.x,h,size.y)

func _gallery(g,at:Vector3,length:float,h:float) -> void:
	g.box(at+Vector3(0,h,0),Vector3(1.0,0.16,length),"wood")
	for j in range(5):
		g.box(at+Vector3(0.36,h*0.5,(j-2)*length/4.4),Vector3(0.12,h,0.12),"wood")
	g.box(at+Vector3(0.36,h-0.65,0),Vector3(0.12,0.13,length),"wood")

func _stair(g,at:Vector3,height:float) -> void:
	for j in range(10):
		var h:float=(j+1)*height/10.0
		g.box(at+Vector3(0,h*0.5,-j*0.26),Vector3(0.9,h,0.27),"stone")

func _vessel(g,at:Vector3,r:float,h:float,mat:String) -> void:
	# Hollow visible mouth, faceted belly and neck; original low-poly pottery type.
	var profile: Array[Vector2] = [Vector2(r*0.42,0),Vector2(r*0.9,h*0.22),Vector2(r,h*0.55),Vector2(r*0.64,h*0.85),Vector2(r*0.45,h),Vector2(r*0.31,h)]
	for j in range(profile.size()-1):
		for i in range(10):
			var a:float=TAU*i/10.0
			var b:float=TAU*(i+1)/10.0
			var p:Vector2=profile[j]
			var q:Vector2=profile[j+1]
			g._oriented_quad(at+Vector3(cos(a)*p.x,p.y,sin(a)*p.x),at+Vector3(cos(b)*p.x,p.y,sin(b)*p.x),at+Vector3(cos(b)*q.x,q.y,sin(b)*q.x),at+Vector3(cos(a)*q.x,q.y,sin(a)*q.x),Vector3(cos(a),0.2,sin(a)),mat)
	g.cylinder(at+Vector3.UP*h*0.91,r*0.30,0.02,"dark")

func _well(g,at:Vector3,r:float,beam:bool) -> void:
	for j in range(12):
		var angle:float=TAU*j/12.0
		g.box(at+Vector3(cos(angle)*r,0.42,sin(angle)*r),Vector3(r*0.52,0.84,0.24),"stone",Vector3(0,PI*0.5-angle,0))
	g.cylinder(at+Vector3.UP*0.09,r*0.82,0.06,"dark")
	if beam:
		for side in [-1.0,1.0]: g.box(at+Vector3(side*r*1.2,1.1,0),Vector3(0.18,2.2,0.18),"wood")
		g.rod(at+Vector3(-r*1.3,2.12,0),at+Vector3(r*1.3,2.12,0),0.12,"wood")
		g.rod(at+Vector3(0,0.8,0),at+Vector3(0,2.12,0),0.025,"linen",-1,6)

func _weaving(g,at:Vector3) -> void:
	for side in [-1.0,1.0]: g.box(at+Vector3(side*1.05,1.3,0),Vector3(0.15,2.6,0.2),"wood")
	for y in [0.45,2.42]: g.box(at+Vector3(0,y,0),Vector3(2.4,0.18,0.18),"wood")
	g.box(at+Vector3(0,1.43,0),Vector3(1.8,1.7,0.045),"linen")
	g.box(at+Vector3(0,0.5,1.4),Vector3(2.5,0.25,0.6),"wood")
	for j in range(4): _vessel(g,at+Vector3(-0.7+j*0.5,0,2.5),0.19,0.35,"roof")

func _forge(g,at:Vector3) -> void:
	g.box(at+Vector3(0,0.55,0),Vector3(1.65,1.1,1.6),"brick")
	g.box(at+Vector3(0,1.14,0),Vector3(1.12,0.1,1.08),"dark")
	for side in [-1.0,1.0]: g.box(at+Vector3(side*0.7,1.62,-0.35),Vector3(0.18,1.0,0.35),"brick")
	g.roof(at+Vector3(0,2.12,-0.35),1.8,1.6,0.48,"roof")
	g.box(at+Vector3(0,0.4,2.0),Vector3(0.55,0.8,0.8),"wood")
	g.box(at+Vector3(0,0.93,2.0),Vector3(0.65,0.26,1.0),"lead")

func _oven(g,at:Vector3) -> void:
	g.box(at+Vector3(0,0.5,0),Vector3(2.5,1.0,2.4),"stone")
	_cap(g,at+Vector3.UP*1.0,1.15,0.9,"brick")
	g.box(at+Vector3(0,1.2,1.05),Vector3(0.65,0.5,0.09),"dark")
	g.box(at+Vector3(0,0.9,1.5),Vector3(0.9,0.15,1.0),"stone")
	g.box(at+Vector3(0,0.7,3.0),Vector3(2.0,0.15,1.0),"wood")

func _trough(g,at:Vector3,size:Vector2) -> void:
	g.box(at+Vector3.UP*0.12,Vector3(size.x,0.24,size.y),"stone")
	for side in [-1.0,1.0]:
		g.box(at+Vector3(side*(size.x*0.5-0.12),0.5,0),Vector3(0.24,0.75,size.y),"stone")
		g.box(at+Vector3(0,0.5,side*(size.y*0.5-0.12)),Vector3(size.x-0.48,0.75,0.24),"stone")
	g.box(at+Vector3.UP*0.48,Vector3(size.x-0.5,0.03,size.y-0.5),"glass")

func _cap(g,at:Vector3,r:float,h:float,mat:String) -> void:
	for ring in range(5):
		var aa:float=PI*0.5*ring/5.0
		var ab:float=PI*0.5*(ring+1)/5.0
		for j in range(16):
			var a:float=TAU*j/16.0
			var b:float=TAU*(j+1)/16.0
			g._oriented_quad(at+Vector3(cos(a)*cos(aa)*r,sin(aa)*h,sin(a)*cos(aa)*r),at+Vector3(cos(b)*cos(aa)*r,sin(aa)*h,sin(b)*cos(aa)*r),at+Vector3(cos(b)*cos(ab)*r,sin(ab)*h,sin(b)*cos(ab)*r),at+Vector3(cos(a)*cos(ab)*r,sin(ab)*h,sin(a)*cos(ab)*r),Vector3(cos(a),1,sin(a)),mat)

func _church(g,plan:String,detail:bool) -> void:
	_court(g)
	if plan == "basilica":
		_block(g,Vector2(0,0.15),Vector2(3.9,9.5),5.45,"brick","gable",false,1)
		for side in [-1.0,1.0]: _block(g,Vector2(side*3.0,0.35),Vector2(1.95,8.8),3.3,"stone","hip",false,1)
		_porch(g,Vector3(0,0,4.8),Vector2(8.0,1.6),2.8,"roof",detail)
		g.cylinder(Vector3(0,2.2,-4.5),1.22,4.4,"brick")
		_cap(g,Vector3(0,4.4,-4.5),1.26,0.75,"roof")
	else:
		_block(g,Vector2(0,0),Vector2(4.6,4.6),5.7,"brick","hip",false,1)
		for x in [-3.25,3.25]: _block(g,Vector2(x,0),Vector2(1.85,4.0),4.15,"brick","gable",false,1)
		for z in [-3.2,3.2]: _block(g,Vector2(0,z),Vector2(4.0,1.85),4.5,"brick","hip",false,1)
		for x in [-3.2,3.2]:
			for z in [-3.2,3.2]: _block(g,Vector2(x,z),Vector2(1.85,1.85),3.0,"stone","hip",false,1)
		g.cylinder(Vector3(0,6.17,0),1.72,1.82,"brick")
		_cap(g,Vector3(0,7.08,0),1.88,1.23,"roof")
		for x in [-2.45,0.0,2.45]:
			g.cylinder(Vector3(x,1.72,-4.38),0.78,3.44,"brick")
			_cap(g,Vector3(x,3.44,-4.38),0.84,0.65,"roof")
	if not detail: return
	_entry(g,Vector3(0,0,4.95 if plan=="basilica" else 4.2),1.0)
	for side in [-1.0,1.0]:
		for j in range(3):
			var z:float=(j-1)*2.65
			var facade:float=3.975 if plan=="basilica" else (4.175 if j==1 else 4.125)
			_window(g,Vector3(side*(facade+0.045),1.85,z),Vector2(0.58,1.1),PI*0.5,false)
			g.arch(Vector3(side*(facade+0.045),0.45,z),1.35,2.15,0.12,0.12,"brick",PI*0.5)
	if plan=="cross_domed":
		for j in range(8):
			var angle:float=TAU*j/8.0
			g.box(Vector3(cos(angle)*1.73,6.27,sin(angle)*1.73),Vector3(0.35,0.73,0.07),"dark",Vector3(0,PI*0.5-angle,0))
	else:
		for side in [-1.0,1.0]:
			for j in range(4): _window(g,Vector3(side*1.99,4.7,(j-1.5)*2.0),Vector2(0.5,0.6),PI*0.5,false)
