extends Node3D
## Reusable perimeter-block authoring: one topology feeds visible walls, openings,
## walk surfaces and collision. Authored metres, never campaign simulation.
const Geometry = preload("res://src/geometry.gd")
const Layout = preload("res://src/layout.gd")
var config: Dictionary
var city_world: Node3D
var parcels: Dictionary = {}
var solids: Array = []
var floors: Array = []
var stairs: Array = []
var suppressed_ids: Array[String] = []
var bounds: Rect2
var active := true
var _solid_cells: Dictionary = {}
var _origin := Vector2.ZERO
var _materials: Dictionary
var _shell
var _detail
var _d: Dictionary
var _boundary := PackedVector2Array()

func configure(world: Node3D) -> void:
	city_world = world
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/neighborhood.json"))
	_d = config.dimensions
	_origin = Vector2(config.origin_m[0], config.origin_m[1])
	for p in config.boundary_m: _boundary.append(Vector2(p[0], p[1]))
	bounds = Rect2(_boundary[0], Vector2.ZERO)
	for p in _boundary: bounds = bounds.expand(p)
	_materials = world.materials.duplicate()
	for i in range(6):
		var mat: ShaderMaterial = world.materials.plaster.duplicate()
		mat.set_shader_parameter("tint", Color("c5bba2").darkened(i * 0.036))
		mat.set_shader_parameter("family", 8)
		_materials["lime_%d" % i] = mat
	var repair: ShaderMaterial = world.materials.stone.duplicate()
	repair.set_shader_parameter("tint", Color("827967"))
	_materials["repair"] = repair
	var lane:ShaderMaterial=world.materials.road.duplicate()
	lane.set_shader_parameter("tint",Color("998a6e"))
	_materials["lane_surface"]=lane
	var ground_mat:ShaderMaterial=world.materials.earth.duplicate()
	ground_mat.set_shader_parameter("family",9)
	ground_mat.set_shader_parameter("ward_origin",_origin)
	var boundary_uniform:=_boundary.duplicate()
	boundary_uniform.resize(16)
	ground_mat.set_shader_parameter("ward_polygon",boundary_uniform)
	ground_mat.set_shader_parameter("ward_vertex_count",_boundary.size())
	ground_mat.set_shader_parameter("ground_tint",world.materials.ground.get_shader_parameter("tint"))
	_materials["ward_ground"]=ground_mat
	_shell = Geometry.new(_materials)
	_detail = Geometry.new(_materials)
	_ground()
	for block in config.blocks: _block(block)
	_drainage()
	_add_mesh(_shell.finish(), "ConnectedMasonryAndRoofs", false)
	_add_mesh(_detail.finish(), "JoineryRoofStructureAndOccupation", true)
	_index_solids()

func _add_mesh(mesh: ArrayMesh, label: String, close: bool) -> void:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	# Bounded district geometry remains resident: no interior disappears when the
	# camera crosses a batch-origin LOD threshold. The whole-city prototypes keep LOD.
	instance.set_meta("district_detail", close)
	add_child(instance)

func local_point(p: Vector3) -> Vector2:
	return Vector2(p.x, -p.z) - _origin

func point(p: Vector2, height: float = NAN) -> Vector3:
	var q := p + _origin
	return Vector3(q.x, ground(p) if is_nan(height) else height, -q.y)

func ground(p: Vector2) -> float:
	return city_world._surface_height(p.x + _origin.x, p.y + _origin.y) + 0.24

func contains(p: Vector3, margin: float = 0.0) -> bool:
	var q := local_point(p)
	if not bounds.grow(margin).has_point(q): return false
	if Geometry2D.is_point_in_polygon(q, _boundary): return true
	for i in range(_boundary.size()):
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, _boundary[i], _boundary[(i+1)%_boundary.size()])) <= margin: return true
	return false

func masks(item: Dictionary) -> bool:
	# A margin contains the entire legacy roof/apron, including rotated corners.
	return contains(item.position, Vector2(item.size.x, item.size.z).length()*0.5 + 2.0)

func _ground() -> void:
	var ids := Geometry2D.triangulate_polygon(_boundary)
	for i in range(0, ids.size(), 3):
		city_world._ground_triangle(_shell, point(_boundary[ids[i]]), point(_boundary[ids[i+1]]), point(_boundary[ids[i+2]]), 0.24, "ward_ground")
	# Join authored lanes to the retained Pantokrator approach; all widths are interpretations.
	for street in config.streets:
		var pts: Array = street.points_m
		for i in range(pts.size()-1):
			var a := Vector2(pts[i][0], pts[i][1])
			var b := Vector2(pts[i+1][0], pts[i+1][1])
			var side := Vector2(-(b-a).y, (b-a).x).normalized()*float(street.width_m)*0.5
			city_world._ground_triangle(_shell,point(a-side),point(a+side),point(b+side),0.26,"lane_surface")
			city_world._ground_triangle(_shell,point(a-side),point(b+side),point(b-side),0.26,"lane_surface")

func _inset(poly: PackedVector2Array, depth: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(poly.size()):
		var before := (poly[i]-poly[posmod(i-1,poly.size())]).normalized()
		var after := (poly[(i+1)%poly.size()]-poly[i]).normalized()
		var n1 := Vector2(-before.y,before.x)
		var n2 := Vector2(-after.y,after.x)
		var bisector := (n1+n2).normalized()
		result.append(poly[i]+bisector*depth/maxf(0.2,bisector.dot(n1)))
	return result

func _block(block: Dictionary) -> void:
	var poly := Layout._polygon(block.polygon_m)
	var inner := _inset(poly, float(block.depth_m))
	var center := Vector2.ZERO
	for p in inner: center += p / float(inner.size())
	for edge in range(poly.size()):
		var a := poly[edge]
		var b := poly[(edge+1)%poly.size()]
		var ia := inner[edge]
		var ib := inner[(edge+1)%poly.size()]
		var count := maxi(2, roundi(a.distance_to(b)/float(block.frontage_m)))
		var breaks: Array[float] = [0.0]
		for j in range(1,count):
			breaks.append((float(j)+0.12*sin(float(j*7+edge*13)))/count)
		breaks.append(1.0)
		for j in range(count):
			var id := "%s_e%d_p%d" % [block.id, edge, j]
			var q := PackedVector2Array([a.lerp(b,breaks[j]),a.lerp(b,breaks[j+1]),ia.lerp(ib,breaks[j+1]),ia.lerp(ib,breaks[j])])
			var passage := false
			for gap in block.passages:
				if edge==int(gap.edge) and j==int(gap.index): passage=true
			if passage:
				# Full open passage: no invisible footprint or overhead collision box.
				continue
			var seed_value := Layout._stable_hash(id)
			var storeys := 1 if seed_value%5==0 else 2
			var use := "ordinary"
			for stop in config.stops:
				if stop.get("parcel_id", "")==id: use=stop.id
			if use=="bakery": storeys=1
			var floor_y := -INF
			for p in q: floor_y=maxf(floor_y,ground(p)+0.09)
			var front := (q[0]+q[1])*0.5
			var back := (q[2]+q[3])*0.5
			var frontage := (q[1]-q[0]).normalized()
			var inward := Vector2(-frontage.y,frontage.x)
			var record := {"id":id,"polygon":q,"floor_y":floor_y,"front":front,"back":back,"inward":inward,"storeys":storeys,"use":use,"block":block.id}
			parcels[id]=record
			_room(record, seed_value)
	_court(inner, center, block)

func _room(record: Dictionary, seed_value: int) -> void:
	var q: PackedVector2Array = record.polygon
	var y: float = record.floor_y
	var h := float(_d.storey_m)*int(record.storeys)
	var mat := "lime_%d" % (seed_value%6)
	_floor(q,y,"stone")
	for edge in range(4):
		var a:=q[edge]
		var b:=q[(edge+1)%4]
		# Offset into parcel, so adjacent properties meet without doubled wall faces.
		var tangent:Vector2=(b-a).normalized()
		var inside:=Vector2(-tangent.y,tangent.x)*float(_d.wall_m)*0.5
		a+=inside
		b+=inside
		var door:bool=edge in [0,2]
		_wall(a,b,y,h,mat,door,record.storeys,seed_value+edge,record.use=="home" and edge==2)
		# Deep foundations reach terrain without broad rectangular pads.
		var bottom:=minf(ground(a),ground(b))-0.65
		_beam(_shell,point(a,(y+bottom)*0.5),point(b,(y+bottom)*0.5),float(_d.wall_m),y-bottom,"stone",false)
	_roof(q,y+h,float(_d.roof_rise_m)*(0.85+float(seed_value%4)*0.1))
	_threshold(record.front,-Vector2(record.inward),y)
	_threshold(record.back,Vector2(record.inward),y)
	# Interior ceiling ties and first-floor deck have structural depth.
	if int(record.storeys)>1:
		_floor(q,y+float(_d.storey_m),"wood",record.use=="home")
		for t in [0.2,0.5,0.8]:
			_beam(_detail,point(q[0].lerp(q[1],t),y+_d.storey_m-0.14),point(q[3].lerp(q[2],t),y+_d.storey_m-0.14),0.17,0.22,"wood",false)
	if record.use in ["home","bakery","store"]:
		_furnish(record)
		if record.use=="home":
			_gallery(record)
			var upper:float=y+_d.storey_m
			var center:Vector2=(Vector2(record.front)+Vector2(record.back))*0.5
			_box(_detail,point(center+Vector2(2.0,0),upper+0.25),Vector3(1.3,0.5,2),"wood")
			_box(_detail,point(center+Vector2(2.0,0),upper+0.55),Vector3(1.2,0.14,1.9),"linen",0,false)
	elif seed_value%4==0:
		var near_back:Vector2=Vector2(record.back).lerp(record.front,0.24)
		var right:Vector2=(q[1]-q[0]).normalized()
		_jar(point(near_back+right*2.0,y),0.36,0.82)

func _floor(poly: PackedVector2Array, y: float, material: String, walk: bool=true) -> void:
	var indices:=Geometry2D.triangulate_polygon(poly)
	for i in range(0,indices.size(),3):
		var a:=point(poly[indices[i]],y)
		var b:=point(poly[indices[i+1]],y)
		var c:=point(poly[indices[i+2]],y)
		city_world._up_triangle(_shell,a,b,c,material)
		_shell.triangle(a-Vector3.UP*0.12,b-Vector3.UP*0.12,c-Vector3.UP*0.12,material)
	for j in range(poly.size()):
		var a:=point(poly[j],y)
		var b:=point(poly[(j+1)%poly.size()],y)
		_shell._oriented_quad(a,b,b-Vector3.UP*0.12,a-Vector3.UP*0.12,Vector3(b.z-a.z,0,a.x-b.x),material)
	if walk: floors.append({"polygon":poly,"y":y})

func _beam(builder, a: Vector3, b: Vector3, width: float, height: float, material: String, collide: bool=true) -> void:
	var length:=Vector2(a.x-b.x,a.z-b.z).length()
	var yaw:=atan2(-(b.z-a.z),b.x-a.x)
	_box(builder,(a+b)*0.5,Vector3(length,height,width),material,yaw,collide)

func _box(builder, at: Vector3, size: Vector3, material: String, yaw: float=0.0, collide: bool=true) -> void:
	builder.box(at,size,material,Vector3(0,yaw,0))
	if collide:solids.append({"at":at,"half":size*0.5,"yaw":yaw})

func _wall(a: Vector2, b: Vector2, y: float, height: float, mat: String, door: bool, storeys: int, seed_value: int, upper_door: bool=false) -> void:
	var length:=a.distance_to(b)
	var tangent:Vector2=(b-a)/length
	var thick:=float(_d.wall_m)
	# One cut-list per wall; jambs, reveals and the collision solid are identical.
	var openings:Array=[]
	if door:openings.append({"x":length*0.5,"width":float(_d.door_width_m),"sill":0.0,"top":float(_d.door_height_m)})
	if upper_door:openings.append({"x":length*0.5,"width":float(_d.door_width_m),"sill":float(_d.storey_m),"top":float(_d.storey_m)+float(_d.door_height_m)})
	if door and storeys>1:
		for t in [0.23,0.77]:openings.append({"x":length*t,"width":0.86,"sill":float(_d.storey_m)+1.0,"top":float(_d.storey_m)+2.12})
	var cuts:Array[float]=[0.0,length]
	for op in openings:
		cuts.append(op.x-op.width*0.5)
		cuts.append(op.x+op.width*0.5)
	cuts.sort()
	for i in range(cuts.size()-1):
		var lo:=cuts[i]
		var hi:=cuts[i+1]
		if hi-lo<0.001:continue
		var middle:float=(lo+hi)*0.5
		var blocked:Array=[]
		for op in openings:
			if absf(middle-float(op.x))<float(op.width)*0.5+0.001:blocked.append(Vector2(op.sill,op.top))
		blocked.sort_custom(func(x:Vector2,z:Vector2):return x.x<z.x)
		var bottom:=0.0
		for opening in blocked:
			if opening.x>bottom:_beam(_shell,point(a+tangent*lo,y+(bottom+opening.x)*0.5),point(a+tangent*hi,y+(bottom+opening.x)*0.5),thick,opening.x-bottom,mat)
			bottom=opening.y
		if bottom<height:_beam(_shell,point(a+tangent*lo,y+(bottom+height)*0.5),point(a+tangent*hi,y+(bottom+height)*0.5),thick,height-bottom,mat)
	for op in openings:
		var center:Vector2=a+tangent*float(op.x)
		_beam(_detail,point(center-tangent*(op.width*0.5+0.13),y+op.top+0.11),point(center+tangent*(op.width*0.5+0.13),y+op.top+0.11),thick+0.05,0.22,"wood",false)
		if op.sill>0:
			_beam(_detail,point(center-tangent*(op.width*0.5+0.09),y+op.sill-0.07),point(center+tangent*(op.width*0.5+0.09),y+op.sill-0.07),thick+0.16,0.14,"stone",false)
			# Open shutters are recessed and folded against the outside facade.
			var outside:=Vector2(tangent.y,-tangent.x)
			for side in [-1.0,1.0]:
				var c:Vector2=center+tangent*side*(op.width*0.5+0.27)+outside*(thick*0.5+0.05)
				_beam(_detail,point(c-tangent*0.24,y+(op.sill+op.top)*0.5),point(c+tangent*0.24,y+(op.sill+op.top)*0.5),0.075,op.top-op.sill,"wood",false)
	if storeys>1:
		var out_band:=Vector2(tangent.y,-tangent.x)*(thick*0.5-0.015)
		_beam(_detail,point(a+out_band,y+float(_d.storey_m)-0.25),point(b+out_band,y+float(_d.storey_m)-0.25),0.05,0.13,"brick",false)
	if door:
		var leaf_c:Vector2=(a+b)*0.5+tangent*1.3-Vector2(tangent.y,-tangent.x)*(thick*0.5+0.055)
		_beam(_detail,point(leaf_c-tangent*0.44,y+1.1),point(leaf_c+tangent*0.44,y+1.1),0.08,2.15,"wood",false)
		for band in [0.48,1.62]:
			_beam(_detail,point(leaf_c-tangent*0.40,y+band),point(leaf_c+tangent*0.40,y+band),0.11,0.055,"dark",false)
	# Irregular exposed repair stones; embedded solid patches avoid coplanar decals.
	var out:=Vector2(tangent.y,-tangent.x)
	for j in range(3):
		var x:=0.65+float(posmod(seed_value+j*37,100))/100.0*maxf(0.1,length-1.3)
		if door and absf(x-length*0.5)<1.35:continue
		var c:=a+tangent*x+out*(thick*0.5-0.018)
		_beam(_detail,point(c-tangent*0.25,y+0.30+j*0.22),point(c+tangent*0.25,y+0.30+j*0.22),0.055,0.17,"repair",false)

func _roof(q: PackedVector2Array, y: float, rise: float) -> void:
	var outward:Vector2=((q[0]+q[1])-(q[2]+q[3])).normalized()*float(_d.eave_m)
	var a:=point(q[0]+outward,y)
	var b:=point(q[1]+outward,y)
	var c:=point(q[2]-outward,y)
	var d:=point(q[3]-outward,y)
	var e:=point((q[0]+q[3])*0.5,y+rise)
	var f:=point((q[1]+q[2])*0.5,y+rise)
	for face in [[a,b,f,e],[e,f,c,d]]:
		_shell._oriented_quad(face[0],face[1],face[2],face[3],Vector3.UP,"roof")
		_shell._oriented_quad(face[0]-Vector3.UP*0.13,face[1]-Vector3.UP*0.13,face[2]-Vector3.UP*0.13,face[3]-Vector3.UP*0.13,Vector3.DOWN,"wood")
	for ends in [[a,d,e],[b,c,f]]:
		_shell.triangle(ends[0],ends[1],ends[2],"brick")
		_shell.triangle(ends[2],ends[1],ends[0],"brick")
	for edge in [[a,b],[b,c],[c,d],[d,a]]:
		_shell._oriented_quad(edge[0],edge[1],edge[1]-Vector3.UP*0.13,edge[0]-Vector3.UP*0.13,(edge[0]+edge[1])*0.5-(a+b+c+d)*0.25,"wood")
	# Real rafters under the deck, tile roll at the ridge, and eave ends.
	var count:=maxi(2,ceili(a.distance_to(b)/1.1))
	for i in range(count+1):
		var t:=float(i)/count
		_detail.rod(a.lerp(b,t)-Vector3.UP*0.18,e.lerp(f,t)-Vector3.UP*0.18,0.075,"wood",-1,6)
		_detail.rod(d.lerp(c,t)-Vector3.UP*0.18,e.lerp(f,t)-Vector3.UP*0.18,0.075,"wood",-1,6)
	_detail.rod(e+Vector3.UP*0.05,f+Vector3.UP*0.05,0.13,"roof",-1,10)

func _threshold(center: Vector2, outside: Vector2, y: float) -> void:
	var tangent:=Vector2(-outside.y,outside.x)
	var base:=ground(center+outside*1.8)
	var rise:=maxf(0.0,y-base)
	var count:=maxi(1,ceili(rise/0.17))
	for i in range(count):
		var depth:=0.36
		var c:=center+outside*(float(count-i)-0.5)*depth
		var top:=lerpf(base,y,float(i+1)/count)
		var poly:=PackedVector2Array([c-tangent*1.05-outside*depth*0.5,c+tangent*1.05-outside*depth*0.5,c+tangent*1.05+outside*depth*0.5,c-tangent*1.05+outside*depth*0.5])
		var bottom:=minf(base,ground(c))-0.25
		_beam(_shell,point(c-tangent*1.05,(top+bottom)*0.5),point(c+tangent*1.05,(top+bottom)*0.5),depth,top-bottom,"stone",false)
		stairs.append({"polygon":poly,"y":top})

func _jar(at: Vector3, radius: float, height: float) -> void:
	_detail.cylinder(at+Vector3.UP*height*0.27,radius*0.73,height*0.54,"roof",radius)
	_detail.cylinder(at+Vector3.UP*height*0.71,radius,height*0.34,"roof",radius*0.43)
	_detail.cylinder(at+Vector3.UP*height*0.93,radius*0.43,height*0.1,"roof",radius*0.48)
	_detail.cylinder(at+Vector3.UP*height*0.985,radius*0.35,0.018,"dark")

func _furnish(r: Dictionary) -> void:
	var q:PackedVector2Array=r.polygon
	var front:Vector2=r.front
	var inward:Vector2=r.inward
	var right:Vector2=(q[1]-q[0]).normalized()
	var yaw:=atan2(right.y,right.x)
	var y:float=r.floor_y
	var center:Vector2=(front+Vector2(r.back))*0.5
	var side:Vector2=center+right*2.0
	# A modest ceramic oil lamp makes the authored furniture legible. It is an
	# interpretive domestic fitting, not an excavated inventory or electrical light.
	var lamp_at:=point(front+inward*2.0+right*3.0,y+1.25)
	_box(_detail,lamp_at-Vector3.UP*0.10,Vector3(0.38,0.12,0.32),"wood",yaw,false)
	_detail.cylinder(lamp_at,0.13,0.08,"roof",0.16)
	_detail.cylinder(lamp_at+Vector3.UP*0.045,0.10,0.015,"dark")
	_detail.dome(lamp_at+Vector3.UP*0.05,0.025,0.075,"gold")
	var light:=OmniLight3D.new()
	light.position=lamp_at+Vector3.UP*0.15
	light.light_color=Color("ffd4a0")
	light.light_energy=1.1
	light.omni_range=7.5
	light.shadow_enabled=true
	add_child(light)
	if r.use=="home":
		_box(_detail,point(side,y+0.30),Vector3(1.3,0.55,2.1),"wood",yaw)
		_box(_detail,point(side,y+0.62),Vector3(1.22,0.15,2.0),"linen",yaw,false)
		_box(_detail,point(center-right*2.2,y+0.38),Vector3(1.2,0.72,0.65),"wood",yaw)
		_table(center-inward*1.7-right*1.8,y,yaw)
		_jar(point(front+inward*1.2+right*2.0,y),0.25,0.58)
	elif r.use=="bakery":
		var oven:Vector2=center+right*2.2+inward*1.1
		_box(_shell,point(oven,y+0.45),Vector3(2.5,0.9,2.3),"brick",yaw)
		_shell.dome(point(oven,y+0.9),1.2,1.0,"brick")
		# Mouth is a separate shallow opening in the dome's front, under an arch.
		var mouth:=point(oven-inward*1.03,y+1.05)
		_box(_detail,mouth,Vector3(0.75,0.52,0.10),"dark",yaw,false)
		_detail.arch(point(oven-inward*1.10,y+0.79),0.72,0.67,0.15,0.13,"brick",yaw)
		_table(center-right*2.0,y,yaw)
		for i in range(4):
			var c:=center-right*2.0+inward*(float(i)-1.5)*0.29
			_detail.dome(point(c,y+0.96),0.19,0.12,"linen")
		for i in range(3):
			_box(_detail,point(front+inward*1.7+right*(2.3+i*0.5),y+0.35),Vector3(0.4,0.65,0.45),"linen",yaw)
		_detail.rod(point(center-right*1.0+inward,y+0.25),point(center-right*1.0+inward*0.2,y+2.1),0.035,"wood")
	else:
		for side_sign in [-1.0,1.0]:
			var c:Vector2=center+right*side_sign*2.1
			_box(_detail,point(c,y+1.0),Vector3(0.12,2.0,3.0),"wood",yaw)
			for shelf in [0.25,1.0,1.7]:
				_box(_detail,point(c,y+shelf),Vector3(0.7,0.09,3.0),"wood",yaw,false)
				for j in range(3):_jar(point(c+inward*(j-1)*0.85,y+shelf+0.05),0.22,0.46)

func _table(p:Vector2,y:float,yaw:float) -> void:
	var at:=point(p,y)
	_box(_detail,at+Vector3.UP*0.91,Vector3(1.35,0.12,1.9),"wood",yaw)
	for x in [-0.5,0.5]:
		for z in [-0.75,0.75]:
			_box(_detail,at+Basis(Vector3.UP,yaw)*Vector3(x,0.43,z),Vector3(0.1,0.86,0.1),"wood",yaw)

func _gallery(r:Dictionary) -> void:
	# External court stair, based only on regional access typology. No projecting street bay.
	var right:Vector2=(r.polygon[2]-r.polygon[3]).normalized()
	var inward:Vector2=r.inward
	var center:Vector2=Vector2(r.back)+inward*0.9
	var width:float=r.polygon[2].distance_to(r.polygon[3])-1.0
	var upper:float=r.floor_y+_d.storey_m
	var corners:=PackedVector2Array([center-right*width*0.5-inward*0.9,center+right*width*0.5-inward*0.9,center+right*width*0.5+inward*0.8,center-right*width*0.5+inward*0.8])
	_floor(corners,upper,"wood")
	for sign in [-1.0,1.0]:
		var p:Vector2=center+right*sign*(width*0.5-0.1)+inward*0.65
		var bottom:=ground(p)
		_beam(_shell,point(p,(bottom+upper)*0.5),point(p+right*0.13,(bottom+upper)*0.5),0.16,upper-bottom,"wood")
	# A straight 1.25 m wide stair runs away from the court gallery.
	var stair_origin:=center+right*(width*0.5-0.85)
	var count:=ceili((upper-ground(stair_origin+inward*7))/0.16)
	var stair_base:=ground(stair_origin+inward*(0.94+(count-0.5)*0.29))
	for i in range(count):
		var near:=0.94+float(count-1-i)*0.29
		var p:=stair_origin+inward*near
		var base:=ground(p)
		var top:=lerpf(stair_base,upper,float(i+1)/count)
		var poly:=PackedVector2Array([p-right*0.65-inward*0.15,p+right*0.65-inward*0.15,p+right*0.65+inward*0.15,p-right*0.65+inward*0.15])
		_beam(_shell,point(p-right*0.65,(base+top)*0.5),point(p+right*0.65,(base+top)*0.5),0.30,maxf(0.1,top-base),"stone",true)
		stairs.append({"polygon":poly,"y":top})
	# Gallery rail leaves the stair landing at the east end clear.
	var rail_a:=center-right*width*0.5+inward*0.8
	var rail_b:=center+right*(width*0.5-1.6)+inward*0.8
	_beam(_detail,point(rail_a,upper+0.95),point(rail_b,upper+0.95),0.10,0.12,"wood")
	for i in range(9):
		var c:=rail_a.lerp(rail_b,float(i)/8)
		_box(_detail,point(c,upper+0.46),Vector3(0.08,0.9,0.08),"wood")

func _court(poly:PackedVector2Array, center:Vector2, block:Dictionary) -> void:
	# Unequal yard enclosures replace an empty communal rectangle. Each has a gate;
	# partition endpoints derive from the court polygon, never from a separate plan.
	for i in range(poly.size()):
		var a:Vector2=poly[i].lerp(center,0.06)
		var b:Vector2=poly[i].lerp(center,0.65)
		if block.use=="home" and i in [0,1]:continue
		var gap_a:Vector2=a.lerp(b,0.54)
		var gap_b:Vector2=a.lerp(b,0.72)
		for segment in [[a,gap_a],[gap_b,b]]:
			var count:=maxi(1,ceili(segment[0].distance_to(segment[1])/1.0))
			for j in range(count):
				var p:Vector2=segment[0].lerp(segment[1],float(j)/count)
				var q:Vector2=segment[0].lerp(segment[1],float(j+1)/count)
				var y:float=(ground(p)+ground(q))*0.5
				_beam(_shell,point(p,y+0.62),point(q,y+0.62),0.35,1.4,"stone")
		if i%2==0:
			var c:Vector2=poly[i].lerp(center,0.35)
			_shed(c,Vector2(center-c).normalized(),block.use=="work")
	var tree_at:Vector2=center+Vector2(-5,6)
	if block.use!="home":
		var y:=ground(tree_at)
		_detail.rod(point(tree_at,y),point(tree_at+Vector2(0.3,0),y+4.3),0.22,"wood",0.11)
		for i in range(5):
			var offset:=Vector2(cos(i*2.4),sin(i*2.4))*1.3
			_detail.rod(point(tree_at,y+2.8),point(tree_at+offset,y+4.4),0.085,"wood",0.03)
			_detail.dome(point(tree_at+offset,y+3.6),1.7,2.0,"green")
	if block.use=="garden":
		# Irregular small beds, open paths and one tree; species is not asserted.
		for i in range(3):
			var c:=center+Vector2((i-1)*5.0,0)
			var p:=point(c)
			_box(_shell,p+Vector3.UP*0.12,Vector3(3.6,0.18,8.0),"cultivation",0,false)
			for j in range(7):
				_detail.dome(point(c+Vector2(sin(j*5.0),j-3),p.y+0.22),0.35,0.4,"green")
	else:
		var c:=center+Vector2(3,-2)
		# Open well throat, with a solid perimeter rather than a filled cylinder.
		var y:=ground(c)
		for i in range(16):
			var a:=c+Vector2(cos(i*TAU/16),sin(i*TAU/16))*0.85
			var b:=c+Vector2(cos((i+1)*TAU/16),sin((i+1)*TAU/16))*0.85
			_beam(_shell,point(a,y+0.44),point(b,y+0.44),0.25,0.88,"stone")
		_box(_shell,point(c,y+0.02),Vector3(1.2,0.04,1.2),"dark",0,false)
		for sign in [-1.0,1.0]:
			_box(_detail,point(c+Vector2(sign*1.15,0),y+1.3),Vector3(0.16,2.6,0.16),"wood")
		_beam(_detail,point(c+Vector2(-1.3,0),y+2.6),point(c+Vector2(1.3,0),y+2.6),0.18,0.18,"wood",false)
		_detail.rod(point(c,y+2.6),point(c,y+0.35),0.024,"linen",-1,6)
		_jar(point(c+Vector2(1.5,1.1),y),0.28,0.65)

func _drainage() -> void:
	# A shallow stone-lined runoff course follows the same terrain triangles as
	# the street. Flat boxes used here previously submerged their downhill ends.
	for street in config.streets:
		var pts:Array=street.points_m
		for i in range(pts.size()-1):
			var a:=Vector2(pts[i][0],pts[i][1])
			var b:=Vector2(pts[i+1][0],pts[i+1][1])
			var t:Vector2=(b-a).normalized()
			var normal:=Vector2(-t.y,t.x)
			var side:=normal*(float(street.width_m)*0.5-0.25)
			for strip in [[-0.22,-0.12,"repair",0.30],[-0.12,0.12,"dark",0.285],[0.12,0.22,"repair",0.30]]:
				var p:Vector2=a+side+normal*float(strip[0])
				var q:Vector2=a+side+normal*float(strip[1])
				var r:Vector2=b+side+normal*float(strip[1])
				var s:Vector2=b+side+normal*float(strip[0])
				city_world._ground_triangle(_detail,point(p),point(q),point(r),float(strip[3]),strip[2])
				city_world._ground_triangle(_detail,point(p),point(r),point(s),float(strip[3]),strip[2])

func _index_solids() -> void:
	for i in range(solids.size()):
		var solid:Dictionary=solids[i]
		var radius:float=Vector2(solid.half.x,solid.half.z).length()+1.0
		var c:=Vector2(solid.at.x,solid.at.z)
		for x in range(floori((c.x-radius)/12),floori((c.x+radius)/12)+1):
			for z in range(floori((c.y-radius)/12),floori((c.y+radius)/12)+1):
				var key:=Vector2i(x,z)
				if not _solid_cells.has(key):_solid_cells[key]=[]
				_solid_cells[key].append(i)

func walk_height(at:Vector3, previous_y:float) -> float:
	var p:=local_point(at)
	var result:=ground(p)
	for surface in floors+stairs:
		if float(surface.y)>previous_y+float(_d.step_m):continue
		if float(surface.y)>result and Geometry2D.is_point_in_polygon(p,surface.polygon):result=surface.y
	return result

func can_stand(at:Vector3) -> bool:
	var radius:=float(_d.walk_radius_m)
	for index in _solid_cells.get(Vector2i(floori(at.x/12),floori(at.z/12)),[]):
		var solid:Dictionary=solids[index]
		if at.y+1.55<solid.at.y-solid.half.y or at.y+float(_d.step_m)>solid.at.y+solid.half.y:continue
		var p:Vector3=Basis(Vector3.UP,-solid.yaw)*(at-Vector3(solid.at))
		# Rounded capsule footprint vs oriented rectangle, not a coarse parcel box.
		var delta:=Vector2(maxf(absf(p.x)-solid.half.x,0.0),maxf(absf(p.z)-solid.half.z,0.0))
		if delta.length_squared()<radius*radius:return false
	return true

func move_walk(eye:Vector3, delta:Vector3) -> Vector3:
	var feet:=eye-Vector3.UP*float(_d.eye_height_m)
	var steps:=maxi(1,ceili(Vector2(delta.x,delta.z).length()/float(_d.move_sample_m)))
	for i in range(steps):
		var part:=delta/steps
		for direction in [part,Vector3(part.x,0,0),Vector3(0,0,part.z)]:
			if direction.length_squared()<0.000001:continue
			var candidate:Vector3=feet+direction
			candidate.y=walk_height(candidate,feet.y)
			if absf(candidate.y-feet.y)>float(_d.step_m):continue
			if can_stand(candidate) and city_world.ground_can_walk(candidate):
				feet=candidate
				if direction==part:break
	return feet+Vector3.UP*float(_d.eye_height_m)

func stop_pose(index:int) -> Dictionary:
	var stop:Dictionary=config.stops[index]
	if stop.has("parcel_id") and parcels.has(stop.parcel_id):
		var r:Dictionary=parcels[stop.parcel_id]
		var p:Vector2=Vector2(r.front)-Vector2(r.inward)*2.2
		return {"eye":point(p,ground(p)+_d.eye_height_m),"target":point(r.back,r.floor_y+1.5),"stop":stop}
	var p:=Vector2(stop.get("point_m",[0,0])[0],stop.get("point_m",[0,0])[1])
	var look:=Vector2(stop.get("look_m",[0,10])[0],stop.get("look_m",[0,10])[1])
	return {"eye":point(p,ground(p)+_d.eye_height_m),"target":point(look,ground(look)+1.5),"stop":stop}


func _shed(c:Vector2,inward:Vector2,work:bool) -> void:
	var right:=Vector2(inward.y,-inward.x)
	var y:=maxf(ground(c+right*2+inward*2),ground(c-right*2-inward*2))+0.10
	var yaw:=atan2(right.y,right.x)
	# Three masonry sides and an open work shelter face their yard.
	for side in [-1.0,1.0]:
		_beam(_shell,point(c+right*side*1.9-inward*1.7,y+1.25),point(c+right*side*1.9+inward*1.7,y+1.25),0.35,2.5,"stone")
	_beam(_shell,point(c-right*2-inward*1.7,y+1.25),point(c+right*2-inward*1.7,y+1.25),0.35,2.5,"stone")
	var a:=point(c-right*2.1-inward*1.9,y+2.65)
	var b:=point(c+right*2.1-inward*1.9,y+2.65)
	var d:=point(c-right*2.1+inward*1.9,y+2.25)
	var e:=point(c+right*2.1+inward*1.9,y+2.25)
	_shell._oriented_quad(a,b,e,d,Vector3.UP,"roof")
	_shell._oriented_quad(a-Vector3.UP*0.12,b-Vector3.UP*0.12,e-Vector3.UP*0.12,d-Vector3.UP*0.12,Vector3.DOWN,"wood")
	if work:_table(c,y,yaw)
	else:
		for i in range(4):_box(_detail,point(c+right*(i-1.5)*0.6,y+0.5),Vector3(0.5,0.95,0.6),"wood",yaw)
