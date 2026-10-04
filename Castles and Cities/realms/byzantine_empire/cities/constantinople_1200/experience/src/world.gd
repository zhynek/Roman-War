extends Node3D
## Standalone original procedural city. Everything here is presentation; there
## is no campaign object, force, construction tick, or simulation RNG.
const Layout = preload("res://src/layout.gd")
const Geometry = preload("res://src/geometry.gd")
const Landmarks = preload("res://src/landmarks.gd")
const Architecture = preload("res://src/architecture.gd")

var data: Dictionary = {}
var visuals: Dictionary = {}
var materials: Dictionary = {}
var stats: Dictionary = {}
var landmark_nodes: Dictionary = {}
var urban := Node3D.new()
var additions := Node3D.new()
var _prototypes: Dictionary = {}
var architecture
var _architecture_placements: Array = []
var _layout: Dictionary = {}
var _obstacles: Dictionary = {}
var _stage := "reference_1200"
var _cutaway_caps: Array[Node3D] = []
var _lane_segments := 0
var _reservoir_cutouts: Array = []
var _terrain_points:=PackedVector3Array()
var _terrain_origin:=Vector2.ZERO
var _terrain_stride:=0
var _terrain_rows:=0

func configure(city: Dictionary) -> void:
	data = city
	visuals = JSON.parse_string(FileAccess.get_file_as_string("res://data/visuals.json"))
	stats = {"building_count":0,"landmark_count":0,"tree_count":0,"wall_towers":0,"road_segments":0}
	_materials()
	_terrain()
	_context_land()
	_fields()
	_roads()
	_reservoir_paths()
	_walls()
	_landmarks()
	_harbors()
	_street_life()
	urban.name = "InhabitedWards"
	add_child(urban)
	additions.name = "CreativeVariant"
	add_child(additions)
	set_stage(_stage)

func _materials() -> void:
	for key in visuals["palette"]:
		var m := ShaderMaterial.new()
		m.shader = preload("res://src/masonry.gdshader")
		m.set_shader_parameter("tint",Color.html(visuals["palette"][key]))
		var family := 7
		if key == "stone": family=0
		elif key == "brick": family=1
		elif key == "roof": family=2
		elif key == "wood": family=3
		elif key in ["gold","lead"]: family=4
		elif key == "road": family=5
		elif key == "ground": family=6
		m.set_shader_parameter("family",family)
		if key=="lead":
			m.set_shader_parameter("metal_amount",0.35)
			m.set_shader_parameter("surface_roughness",0.79)
		materials[key]=m
	var sea := ShaderMaterial.new()
	sea.shader=preload("res://src/water.gdshader")
	materials["water"]=sea
	for key in ["earth","cultivation"]:
		var m:=ShaderMaterial.new()
		m.shader=preload("res://src/masonry.gdshader")
		m.set_shader_parameter("tint",Color("827051") if key=="earth" else Color("666644"))
		m.set_shader_parameter("family",6)
		materials[key]=m

func _terrain() -> void:
	_reservoir_cutouts=_make_reservoir_cutouts()
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2.ONE*float(visuals["ocean_extent_m"])
	sea.mesh=plane
	sea.material_override=materials["water"]
	sea.position=Vector3(3000,0,-2200)
	sea.name="MarmaraBosphorusGoldenHorn"
	add_child(sea)
	var boundary: Array=data["site"]["boundary_m"]
	var lo:=Vector2(INF,INF)
	var hi:=Vector2(-INF,-INF)
	for p in boundary:
		lo=lo.min(Vector2(float(p[0]),float(p[1])))
		hi=hi.max(Vector2(float(p[0]),float(p[1])))
	var step: float=visuals["terrain_grid_m"]
	lo-=Vector2.ONE*step*3.0
	lo.x-=6000.0 # Continue the Thracian countryside beyond the authoring study.
	hi+=Vector2.ONE*step*3.0
	var nx:=int(ceil((hi.x-lo.x)/step))
	var nz:=int(ceil((hi.y-lo.y)/step))
	_terrain_origin=lo
	_terrain_stride=nx+1
	_terrain_rows=nz+1
	var points:=PackedVector3Array()
	for j in range(nz+1):
		for i in range(nx+1):
			var x:=lo.x+i*step
			var north:=lo.y+j*step
			points.append(Vector3(x,Layout.height_at(data,x,north),-north))
	_terrain_points=points
	var s:=SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(nz):
		for i in range(nx):
			var a:=points[j*(nx+1)+i]
			var b:=points[j*(nx+1)+i+1]
			var c:=points[(j+1)*(nx+1)+i]
			var d:=points[(j+1)*(nx+1)+i+1]
			for triangle in [[a,c,b],[b,c,d]]:
				var clipped:=_clip_reservoirs(triangle[0],triangle[1],triangle[2])
				for v in clipped:
					s.set_color(Color.WHITE)
					s.add_vertex(v)
	s.generate_normals()
	s.index()
	var terrain:=MeshInstance3D.new()
	terrain.name="HistoricPeninsulaInterpretiveRelief"
	terrain.mesh=s.commit()
	terrain.material_override=materials["ground"]
	add_child(terrain)

func _surface_height(east:float,north:float) -> float:
	# Match the actual terrain triangles, so thin roads and plot surfaces do
	# not disappear beneath the interpolated ground between height samples.
	var grid:Vector2=(Vector2(east,north)-_terrain_origin)/float(visuals["terrain_grid_m"])
	var i:=floori(grid.x)
	var j:=floori(grid.y)
	if i<0 or j<0 or i>=_terrain_stride-1 or j>=_terrain_rows-1:return Layout.height_at(data,east,north)
	var u:=grid.x-i
	var v:=grid.y-j
	var a:float=_terrain_points[j*_terrain_stride+i].y
	var b:float=_terrain_points[j*_terrain_stride+i+1].y
	var c:float=_terrain_points[(j+1)*_terrain_stride+i].y
	var d:float=_terrain_points[(j+1)*_terrain_stride+i+1].y
	if u+v<=1.0:return a*(1.0-u-v)+b*u+c*v
	return d*(u+v-1.0)+b*(1.0-v)+c*(1.0-u)

func _ground_triangle(builder:RefCounted,a:Vector3,b:Vector3,c:Vector3,clearance:float,material:String,clip_basins:bool=false) -> void:
	# Sampling only the corners lets a road/apron cut THROUGH a terrain ridge.
	# Split at the actual grid triangles first, then lift every piece by the
	# same clearance. Each output triangle is parallel to its ground triangle.
	var polygon:=PackedVector2Array([Vector2(a.x,-a.z),Vector2(b.x,-b.z),Vector2(c.x,-c.z)])
	var bounds:=Rect2(polygon[0],Vector2.ZERO).expand(polygon[1]).expand(polygon[2])
	var step:float=visuals["terrain_grid_m"]
	var first:=Vector2i(floori((bounds.position.x-_terrain_origin.x)/step),floori((bounds.position.y-_terrain_origin.y)/step))
	var last:=Vector2i(floori((bounds.end.x-_terrain_origin.x)/step),floori((bounds.end.y-_terrain_origin.y)/step))
	for j in range(maxi(0,first.y),mini(_terrain_rows-2,last.y)+1):
		for i in range(maxi(0,first.x),mini(_terrain_stride-2,last.x)+1):
			var corner:=_terrain_origin+Vector2(i,j)*step
			for half in [PackedVector2Array([corner,corner+Vector2(step,0),corner+Vector2(0,step)]),PackedVector2Array([corner+Vector2(step,0),corner+Vector2(step,step),corner+Vector2(0,step)])]:
				for piece in Geometry2D.intersect_polygons(polygon,half):
					for k in range(1,piece.size()-1):
						var triangle:Array[Vector3]=[]
						for index in [0,k,k+1]:
							var p:Vector2=piece[index]
							triangle.append(Vector3(p.x,_surface_height(p.x,p.y)+clearance,-p.y))
						var vertices:Array[Vector3]=_clip_reservoirs(triangle[0],triangle[1],triangle[2]) if clip_basins else triangle
						for v in range(0,vertices.size(),3):_up_triangle(builder,vertices[v],vertices[v+1],vertices[v+2],material)

func _make_reservoir_cutouts() -> Array:
	var holes:Array=[]
	for item in data["landmarks"]:
		if float(item["dimensions"].get("underground",0))<0.5 and float(item["dimensions"].get("open_top",0))<0.5: continue
		var center:=Layout.world(data,item["position_m"])
		var basis:=Basis(Vector3.UP,deg_to_rad(float(item.get("rotation_deg",0))))
		var half:=Vector2(float(item["dimensions"]["width_m"]),float(item["dimensions"]["depth_m"]))*0.5
		var poly:=PackedVector2Array()
		for q in [Vector3(-half.x,0,-half.y),Vector3(half.x,0,-half.y),Vector3(half.x,0,half.y),Vector3(-half.x,0,half.y)]:
			var p:Vector3=center+basis*q
			poly.append(Vector2(p.x,p.z))
		var bounds:=Rect2(poly[0],Vector2.ZERO)
		for p in poly:bounds=bounds.expand(p)
		holes.append({"polygon":poly,"bounds":bounds})
	return holes

func _clip_reservoirs(a:Vector3,b:Vector3,c:Vector3) -> Array[Vector3]:
	var original:=PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])
	var bounds:=Rect2(original[0],Vector2.ZERO).expand(original[1]).expand(original[2])
	var polygons:Array[PackedVector2Array]=[original]
	var changed:=false
	for hole in _reservoir_cutouts:
		if not bounds.intersects(hole["bounds"]):continue
		changed=true
		var pieces:Array[PackedVector2Array]=[]
		for polygon in polygons:pieces.append_array(Geometry2D.clip_polygons(polygon,hole["polygon"]))
		polygons=pieces
	if not changed:return [a,b,c]
	var normal:Vector3=(b-a).cross(c-a)
	var vertices:Array[Vector3]=[]
	for polygon in polygons:
		var indices:=Geometry2D.triangulate_polygon(polygon)
		for index in range(0,indices.size(),3):
			var triangle:Array[Vector3]=[]
			for j in range(3):
				var q:Vector2=polygon[indices[index+j]]
				var y:=a.y-(normal.x*(q.x-a.x)+normal.z*(q.y-a.z))/normal.y
				triangle.append(Vector3(q.x,y,q.y))
			if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).y>0.0:triangle.reverse()
			vertices.append_array(triangle)
	return vertices

func _reservoir_paths() -> void:
	var rings:Array=[]
	for item in data["landmarks"]:
		if item["kind"]!="cistern":continue
		var center:=Layout.world(data,item["position_m"])
		var basis:=Basis(Vector3.UP,deg_to_rad(float(item.get("rotation_deg",0))))
		var half:=Vector2(float(item["dimensions"]["width_m"]),float(item["dimensions"]["depth_m"]))*0.5+Vector2.ONE*6
		var points:Array=[]
		for q in [Vector3(-half.x,0,-half.y),Vector3(half.x,0,-half.y),Vector3(half.x,0,half.y),Vector3(-half.x,0,half.y),Vector3(-half.x,0,-half.y)]:
			var p:Vector3=center+basis*q
			points.append([p.x,-p.z])
		rings.append({"id":String(item["id"])+"_rim_access","points_m":points,"width_m":6.0})
	if not rings.is_empty():_roads(rings,self)

func _roads(records:Array=[], parent:Node3D=null) -> int:
	var builder=Geometry.new(materials)
	var count_before:int=stats["road_segments"]
	for road in data["roads"] if records.is_empty() else records:
		var pts: Array=road["points_m"]
		var width: float=road["width_m"]
		for i in range(pts.size()-1):
			var a:=Vector2(float(pts[i][0]),float(pts[i][1]))
			var b:=Vector2(float(pts[i+1][0]),float(pts[i+1][1]))
			var direction:=(b-a).normalized()
			var side:=Vector2(-direction.y,direction.x)*width*0.5
			var count:=maxi(1,int(ceil(a.distance_to(b)/float(visuals["road_sample_m"]))))
			for j in range(count):
				var p:=a.lerp(b,float(j)/count)
				var q:=a.lerp(b,float(j+1)/count)
				var va:=Layout.world(data,[p.x+side.x,p.y+side.y])+Vector3.UP*0.22
				var vb:=Layout.world(data,[p.x-side.x,p.y-side.y])+Vector3.UP*0.22
				var vc:=Layout.world(data,[q.x+side.x,q.y+side.y])+Vector3.UP*0.22
				var vd:=Layout.world(data,[q.x-side.x,q.y-side.y])+Vector3.UP*0.22
				va.y=_surface_height(va.x,-va.z)+0.22
				vb.y=_surface_height(vb.x,-vb.z)+0.22
				vc.y=_surface_height(vc.x,-vc.z)+0.22
				vd.y=_surface_height(vd.x,-vd.z)+0.22
				for triangle in [[va,vb,vc],[vb,vd,vc]]:
					_ground_triangle(builder,triangle[0],triangle[1],triangle[2],0.22,"road",true)
				stats["road_segments"]+=1
	_add_mesh(builder.finish(),"StreetsAndProcessionalRoutes",self if parent==null else parent)
	return int(stats["road_segments"])-count_before

func _up_triangle(builder, a:Vector3,b:Vector3,c:Vector3,mat:String) -> void:
	if (b-a).cross(c-a).y>0: builder.triangle(a,c,b,mat)
	else: builder.triangle(a,b,c,mat)

func _walls() -> void:
	for wall in data["walls"]:
		var builder=Geometry.new(materials)
		var points: Array=wall["points_m"]
		var height: float=wall["height_m"]
		var width: float=wall["width_m"]
		var tower_spacing: float=wall["tower_spacing_m"]
		for i in range(points.size()-1):
			var a:=Vector2(float(points[i][0]),float(points[i][1]))
			var b:=Vector2(float(points[i+1][0]),float(points[i+1][1]))
			var length:=a.distance_to(b)
			var yaw:=atan2(b.x-a.x,-(b.y-a.y))
			var count:=maxi(1,int(ceil(length/12.0)))
			for j in range(count):
				var p:=a.lerp(b,(float(j)+0.5)/count)
				var at:=Layout.world(data,[p.x,p.y])
				if _gate_gap(at):continue
				builder.box(at+Vector3.UP*(height*0.5),Vector3(width,height,length/count+0.15),"stone",Vector3(0,yaw,0))
				# Byzantine stone-and-brick banding; individual repair patterns are interpretive.
				for k in range(3):
					builder.box(at+Vector3.UP*(height*(0.25+k*0.23)),Vector3(width+0.04,0.34,length/count+0.16),"brick",Vector3(0,yaw,0))
				for merlon in range(4):
					var offset:=Basis(Vector3.UP,yaw)*Vector3(0,height+0.65,(float(merlon)-1.5)*length/count/4.0)
					builder.box(at+offset,Vector3(width,1.3,length/count/7.0),"stone",Vector3(0,yaw,0))
			var towers:=maxi(1,int(ceil(length/tower_spacing)))
			for j in range(towers):
				var p:=a.lerp(b,float(j)/towers)
				var at:=Layout.world(data,[p.x,p.y])
				if _gate_gap(at):continue
				var radius:=maxf(3.5,width*1.5)
				builder.box(at+Vector3.UP*(height*0.62),Vector3(radius*2.0,height*1.24,radius*2.0),"stone",Vector3(0,yaw,0))
				for k in range(3):
					builder.box(at+Vector3.UP*(height*(0.24+k*0.3)),Vector3(radius*2.02,0.36,radius*2.02),"brick",Vector3(0,yaw,0))
				for side in [-1.0,1.0]:
					for k in range(4):
						var v:=Basis(Vector3.UP,yaw)*Vector3(side*radius,height*1.24+0.6,(k-1.5)*radius*0.5)
						builder.box(at+v,Vector3(1.1,1.2,radius*0.3),"stone",Vector3(0,yaw,0))
				stats["wall_towers"]+=1
		_add_mesh(builder.finish(),String(wall["id"]),self)

func _gate_gap(at:Vector3) -> bool:
	for item in data["landmarks"]:
		if item["kind"]!="gate":continue
		var p:=Layout.world(data,item["position_m"])
		var local:=Basis(Vector3.UP,-deg_to_rad(float(item.get("rotation_deg",0))))*(at-p)
		if absf(local.x)<float(item["dimensions"]["width_m"])*0.48 and absf(local.z)<float(item["dimensions"]["depth_m"])*0.5+32.0:return true
	return false

func _landmarks() -> void:
	for item in data["landmarks"]:
		var node:Node3D=Landmarks.build(item,materials)
		node.name=item["id"]
		node.position=Layout.world(data,item["position_m"])
		node.rotation.y=deg_to_rad(float(item.get("rotation_deg",0)))
		add_child(node)
		landmark_nodes[item["id"]]=node
		stats["landmark_count"]+=1
		if item["kind"]=="aqueduct":
			# Keep the water channel level while carrying each pier to the
			# uneven saddle beneath it; never leave a foundation floating.
			var foundation=Geometry.new(materials)
			var width:float=item["dimensions"]["width_m"]
			var bays:int=int(item["dimensions"]["arch_count"])
			for i in range(bays+1):
				var local:=Vector3(-width*0.5+i*width/bays,0,0)
				var ground:=node.to_global(local)
				var delta:=Layout.height_at(data,ground.x,-ground.z)-node.position.y
				if delta<0.0:
					foundation.box(local+Vector3.UP*(delta*0.5-0.25),Vector3(width/bays*0.20,-delta+0.5,float(item["dimensions"]["depth_m"])),"stone")
			_add_mesh(foundation.finish(),"GroundedPierFoundations",node)
		if float(item["dimensions"].get("underground",0))>0.5:
			var cap:=MeshInstance3D.new()
			var plane:=PlaneMesh.new()
			plane.size=Vector2(float(item["dimensions"]["width_m"]),float(item["dimensions"]["depth_m"]))
			cap.mesh=plane
			cap.material_override=materials["ground"]
			cap.name="ReservoirGroundCover"
			cap.position=node.position+Vector3.UP*0.06
			cap.rotation.y=node.rotation.y
			add_child(cap)
			_cutaway_caps.append(cap)

func set_stage(id:String) -> void:
	if id==_stage and not _layout.is_empty():return
	if architecture==null:
		architecture=Architecture.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/architecture.json")),materials)
	_stage=id
	for child in urban.get_children():
		urban.remove_child(child)
		child.queue_free()
	_layout=Layout.generate(data,id)
	stats["road_segments"]-=_lane_segments
	_lane_segments=0
	if not _layout.get("lanes",[]).is_empty():_lane_segments=_roads(_layout["lanes"],urban)
	_obstacles.clear()
	_architecture_placements.clear()
	var groups:Dictionary={}
	var type_counts:Dictionary={}
	for item:Dictionary in _layout["buildings"]:
		var p:Vector3=item["position"]
		var type_id:String=architecture.select(item)
		var floors:int=architecture.floors_for(item,type_id)
		var key:="%d_%d_%s_%d" % [floori(p.x/float(visuals["chunk_size_m"])),floori(p.z/float(visuals["chunk_size_m"])),type_id,floors]
		if not groups.has(key):groups[key]=[]
		var scale_by:Vector3=item["size"]/Vector3(10,architecture.height_for(type_id,floors),12)
		if architecture.types[type_id]["kind"] in ["church","town_feature"]:scale_by.y=1.0
		var basis:=Basis(Vector3.UP,float(item["yaw"]))*Basis.from_scale(scale_by)
		# Reference records stay byte-identical: terrain-conforming presentation
		# transforms are derived separately. Foundations reach below the lowest edge.
		var top:=_surface_height(p.x,-p.z)
		var bottom:=top
		for x in [-5.0,0.0,5.0]:
			for z in [-6.0,0.0,6.0]:
				var corner:Vector3=p+basis*Vector3(x,0,z)
				var surface:=_surface_height(corner.x,-corner.z)
				top=maxf(top,surface)
				bottom=minf(bottom,surface)
		p.y=top+0.03
		var placement:Dictionary={"id":item["id"],"type_id":type_id,"floors":floors,"transform":Transform3D(basis,p),"seed":item["seed"],"ground_min":bottom,"ground_max":top}
		groups[key].append(placement)
		_architecture_placements.append(placement)
		type_counts[type_id]=int(type_counts.get(type_id,0))+1
		var obstacle_key:=Vector2i(floori(p.x/80.0),floori(p.z/80.0))
		if not _obstacles.has(obstacle_key):_obstacles[obstacle_key]=[]
		_obstacles[obstacle_key].append(item)
	for key in groups:
		var entries:Array=groups[key]
		var type_id:String=entries[0]["type_id"]
		var common_bounds:=AABB()
		var first_bounds:=true
		for placement:Dictionary in entries:
			var mesh_height:float=architecture.height_for(type_id,int(placement["floors"]))+0.4
			var prototype_bounds:=AABB(Vector3(-5,-6.1,-6),Vector3(10,mesh_height+6.1,12))
			var instance_bounds:AABB=placement["transform"]*prototype_bounds
			common_bounds=instance_bounds if first_bounds else common_bounds.merge(instance_bounds)
			first_bounds=false
		for detail in [false,true]:
			var floors:int=entries[0]["floors"]
			var mesh:ArrayMesh=architecture.mesh(type_id,detail,floors)
			var batch:=MultiMesh.new()
			batch.transform_format=MultiMesh.TRANSFORM_3D
			batch.use_colors=true
			batch.mesh=mesh
			batch.instance_count=entries.size()
			batch.custom_aabb=common_bounds
			for i in range(entries.size()):
				var item:Dictionary=entries[i]
				batch.set_instance_transform(i,item["transform"])
				var tint:=0.84+float(posmod(int(item["seed"]),29))*0.009
				batch.set_instance_color(i,Color(tint,tint*0.985,tint*0.95))
			var instance:=MultiMeshInstance3D.new()
			instance.name=key+("_Detail" if detail else "_Silhouette")
			instance.multimesh=batch
			var detail_distance:float=architecture.config["dimensions"]["near_detail_m"]
			if detail:instance.visibility_range_end=detail_distance
			else:instance.visibility_range_begin=detail_distance
			urban.add_child(instance)
	_plot_surfaces()
	_trees(_layout["trees"])
	stats["building_count"]=_layout["buildings"].size()
	stats["tree_count"]=_layout["trees"].size()
	stats["architecture_types"]=type_counts.size()
	stats["architecture_counts"]=type_counts

func _floors(item:Dictionary) -> int:
	return clampi(roundi((float(item["size"].y)-1.1)/3.1),1,4)

func _house_mesh(variant:int,detail:bool,floors:int=2) -> ArrayMesh:
	if architecture==null:
		architecture=Architecture.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/architecture.json")),materials)
	var home_ids:Array=[]
	for record:Dictionary in architecture.config["types"]:
		if record["kind"]=="home":home_ids.append(record["id"])
	return architecture.mesh(home_ids[posmod(variant,home_ids.size())],detail,floors)

func _plot_surfaces() -> void:
	# Packed-earth aprons connect dwellings visually to their plots. These are
	# inferred everyday surfaces, never cadastral parcels or surveyed paving.
	var g=Geometry.new(materials)
	for item in _layout["buildings"]:
		var center:Vector3=item["position"]
		var half:Vector3=item["size"]*0.5+Vector3(1.1,0,1.1)
		var basis:=Basis(Vector3.UP,float(item["yaw"]))
		var corners:Array[Vector3]=[]
		for q in [Vector3(-half.x,0,-half.z),Vector3(half.x,0,-half.z),Vector3(half.x,0,half.z),Vector3(-half.x,0,half.z)]:
			var p:Vector3=center+basis*q
			p.y=_surface_height(p.x,-p.z)+0.13
			corners.append(p)
		_ground_triangle(g,corners[0],corners[1],corners[2],0.07,"earth")
		_ground_triangle(g,corners[0],corners[2],corners[3],0.07,"earth")
	_add_mesh(g.finish(),"DomesticPackedEarth",urban)

func _fields() -> void:
	var g=Geometry.new(materials)
	for field in data.get("fields",[]):
		var poly:=PackedVector2Array()
		var lo:=Vector2(INF,INF)
		var hi:=Vector2(-INF,-INF)
		for p in field["polygon_m"]:
			var v:=Vector2(float(p[0]),float(p[1]))
			poly.append(v)
			lo=lo.min(v)
			hi=hi.max(v)
		# Small ground-conforming tiles preserve the authored relief.
		for north in range(int(lo.y),int(hi.y),12):
			for east in range(int(lo.x),int(hi.x),12):
				var p:=Vector2(east,north)
				if not Geometry2D.is_point_in_polygon(p+Vector2.ONE*6,poly):continue
				var corners:Array[Vector3]=[]
				for delta in [Vector2.ZERO,Vector2(12,0),Vector2(12,12),Vector2(0,12)]:
					var point:Vector2=p+delta
					corners.append(Vector3(point.x,_surface_height(point.x,point.y)+0.1,-point.y))
				var mat:="earth" if posmod(north,36)<12 else "cultivation"
				_ground_triangle(g,corners[0],corners[1],corners[2],0.1,mat)
				_ground_triangle(g,corners[0],corners[2],corners[3],0.1,mat)
	_add_mesh(g.finish(),"WesternCultivation",self)

func _context_land() -> void:
	for region in data["site"].get("context_land",[]):
		var poly:=PackedVector2Array()
		var lo:=Vector2(INF,INF)
		var hi:=Vector2(-INF,-INF)
		for p in region["polygon_m"]:
			var v:=Vector2(float(p[0]),float(p[1]))
			poly.append(v)
			lo=lo.min(v)
			hi=hi.max(v)
		var s:=SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		for north in range(int(lo.y)-160,int(hi.y)+160,160):
			for east in range(int(lo.x)-160,int(hi.x)+160,160):
				var points:Array[Vector3]=[]
				for q in [Vector2(east,north),Vector2(east+160,north),Vector2(east,north+160),Vector2(east+160,north+160)]:
					var h:=-24.0
					if Geometry2D.is_point_in_polygon(q,poly):
						h=float(region["base_height_m"])
						for hill in region["hills"]:
							var dist:float=q.distance_to(Vector2(float(hill["position_m"][0]),float(hill["position_m"][1])))
							h=maxf(h,float(hill["height_m"])*exp(-pow(dist/float(hill["radius_m"]),2)))
						var shore:=INF
						for i in range(poly.size()):shore=minf(shore,q.distance_to(Geometry2D.get_closest_point_to_segment(q,poly[i],poly[(i+1)%poly.size()])))
						h*=smoothstep(0,float(region["coast_falloff_m"]),shore)
					points.append(Vector3(q.x,h,-q.y))
				for i in [0,2,1,1,2,3]:s.add_vertex(points[i])
		s.generate_normals()
		s.index()
		var mesh:=_add_mesh(s.commit(),String(region["id"]),self)
		mesh.material_override=materials["ground"]

func _trees(points:Array) -> void:
	var g=Geometry.new(materials)
	g.cylinder(Vector3(0,2.8,0),0.26,5.6,"wood",0.16)
	g.cylinder(Vector3(0,4.4,0),1.95,4.8,"green",0.18)
	g.cylinder(Vector3(0,6.5,0),1.2,3.5,"green",0.04)
	g.cylinder(Vector3(0,3.1,0),1.8,2.2,"green",1.0)
	var mesh:ArrayMesh=g.finish()
	var groups:Dictionary={}
	for i in range(points.size()):
		var p:Vector3=points[i]
		var key:=Vector2i(floori(p.x/500.0),floori(p.z/500.0))
		if not groups.has(key):groups[key]=[]
		groups[key].append(p)
	for key in groups:
		var entries:Array=groups[key]
		var batch:=MultiMesh.new()
		batch.transform_format=MultiMesh.TRANSFORM_3D
		batch.use_colors=true
		batch.mesh=mesh
		batch.instance_count=entries.size()
		for i in range(entries.size()):
			var scale_by:=0.7+fmod(absf(entries[i].x*0.27+entries[i].z*0.39),0.7)
			batch.set_instance_transform(i,Transform3D(Basis().scaled(Vector3.ONE*scale_by),entries[i]))
			batch.set_instance_color(i,Color(0.8+scale_by*0.15,0.85+scale_by*0.12,0.78+scale_by*0.11))
		var instance:=MultiMeshInstance3D.new()
		instance.multimesh=batch
		urban.add_child(instance)

func _harbors() -> void:
	var g=Geometry.new(materials)
	var ship:=_ship_mesh()
	for harbor in data.get("harbors",[]):
		var pos:Array=harbor["position_m"]
		var desired:=Vector2(float(pos[0]),float(pos[1]))
		var shore:=desired
		var nearest:=INF
		var boundary:Array=data["site"]["boundary_m"]
		for segment in range(boundary.size()-1):
			var a:=Vector2(float(boundary[segment][0]),float(boundary[segment][1]))
			var b:=Vector2(float(boundary[segment+1][0]),float(boundary[segment+1][1]))
			var candidate:=Geometry2D.get_closest_point_to_segment(desired,a,b)
			if candidate.distance_squared_to(desired)<nearest:
				nearest=candidate.distance_squared_to(desired)
				shore=candidate
		var outward:=(desired-shore).normalized()
		var at:=Vector3(shore.x,0.5,-shore.y)
		var yaw:=atan2(outward.x,-outward.y)
		var rotation:=Basis(Vector3.UP,yaw)
		var count:=int(harbor.get("piers",3))
		g.box(at+rotation*Vector3(-17,0.6,-8),Vector3(count*34+24,2.5,22),"stone",Vector3(0,yaw,0))
		for i in range(count):
			var origin:=at+rotation*Vector3((i-count*0.5)*34,0,0)
			g.box(origin+rotation*Vector3(0,1.4,20),Vector3(5,0.6,44),"wood",Vector3(0,yaw,0))
			for j in range(8):
				for side in [-1.0,1.0]:
					g.cylinder(origin+rotation*Vector3(side*2.2,0.3,j*5.4),0.22,5,"wood")
			for j in range(2):
				var vessel:=MeshInstance3D.new()
				vessel.mesh=ship
				vessel.position=origin+rotation*Vector3(9+float(j)*15,0.2,20+j*23)
				vessel.rotation.y=yaw+0.08*j
				vessel.scale=Vector3.ONE*(0.7+0.18*((i+j)%3))
				add_child(vessel)
	_add_mesh(g.finish(),"GoldenHornLandingStages",self)

func _ship_mesh() -> ArrayMesh:
	var g=Geometry.new(materials)
	# Original lateen-rigged merchant vessel: a visual type, not a named excavated hull.
	var sections:=[Vector3(0,0,-14),Vector3(3.4,1.6,-8),Vector3(4.3,1.9,0),Vector3(3.1,1.7,9),Vector3(0,3.0,14)]
	for i in range(sections.size()-1):
		var a:Vector3=sections[i]
		var b:Vector3=sections[i+1]
		for side in [-1.0,1.0]:
			var va:=Vector3(side*a.x,a.y,a.z)
			var vb:=Vector3(side*b.x,b.y,b.z)
			g._oriented_quad(va,Vector3(0,-0.8,a.z),Vector3(0,-0.8,b.z),vb,Vector3(side,-0.25,0),"wood")
			g._oriented_quad(va,vb,Vector3(0,1.3,b.z),Vector3(0,1.3,a.z),Vector3.UP,"wood")
	g.box(Vector3(0,1.5,0),Vector3(5.7,0.25,18),"wood")
	g.cylinder(Vector3(0,9,1),0.16,16,"wood",0.09)
	g.box(Vector3(0,14.5,1),Vector3(0.18,0.18,20),"wood",Vector3(0.5,0,0))
	var a:=Vector3(0,19,-8)
	var b:=Vector3(0,10,10)
	var c:=Vector3(0,3,6)
	for side in [-0.04,0.04]:
		g.triangle(a+Vector3(side,0,0),b+Vector3(side,0,0),c+Vector3(side,0,0),"linen")
		g.triangle(c+Vector3(side,0,0),b+Vector3(side,0,0),a+Vector3(side,0,0),"linen")
	for i in range(5):g.box(Vector3((i%2)*1.5-0.75,2.1,(i-2)*2.3),Vector3(1.2,1.2,1.5),"wood")
	return g.finish()

func _street_life() -> void:
	var people=Geometry.new(materials)
	people.cylinder(Vector3(0,0.77,0),0.25,1.2,"linen",0.17)
	people.dome(Vector3(0,1.35,0),0.15,0.3,"skin")
	for side in [-1.0,1.0]:
		people.cylinder(Vector3(side*0.12,0.18,0),0.07,0.35,"dark")
		people.cylinder(Vector3(side*0.27,0.94,0),0.065,0.65,"skin")
	var mesh:ArrayMesh=people.finish()
	var groups:Dictionary={}
	for road in data["roads"]:
		var pts:Array=road["points_m"]
		for i in range(pts.size()-1):
			var a:=Vector2(float(pts[i][0]),float(pts[i][1]))
			var b:=Vector2(float(pts[i+1][0]),float(pts[i+1][1]))
			var count:=int(a.distance_to(b)/float(visuals["population_spacing_m"]))
			for j in range(count):
				var p:=a.lerp(b,(float(j)+0.4)/maxi(1,count))
				var at:=Vector3(p.x,_surface_height(p.x,p.y)+0.24,-p.y)
				var k:=Vector2i(floori(at.x/400),floori(at.z/400))
				if not groups.has(k):groups[k]=[]
				groups[k].append(Transform3D(Basis(Vector3.UP,float(j)*1.7),at))
	for key in groups:
		var batch:=MultiMesh.new()
		batch.transform_format=MultiMesh.TRANSFORM_3D
		batch.use_colors=true
		batch.mesh=mesh
		batch.instance_count=groups[key].size()
		for i in range(groups[key].size()):
			batch.set_instance_transform(i,groups[key][i])
			batch.set_instance_color(i,Color(0.5+0.08*(i%5),0.52+0.06*(i%4),0.49+0.07*(i%3)))
		var node:=MultiMeshInstance3D.new()
		node.multimesh=batch
		node.visibility_range_end=420
		add_child(node)

func set_design_objects(objects:Array) -> void:
	for child in additions.get_children():
		additions.remove_child(child)
		child.queue_free()
	for item in objects:
		var node:Node3D
		if architecture.config["creative_defaults"].has(item["kind"]):
			var instance:=MeshInstance3D.new()
			var type_id:String=architecture.config["creative_defaults"][item["kind"]]
			instance.mesh=architecture.mesh(type_id,true,2)
			node=instance
		else:
			var g=Geometry.new(materials)
			var footing:float=architecture.config["dimensions"]["foundation_depth_m"]
			g.cylinder(Vector3(0,-footing*0.5,0),4.2,footing,"stone")
			g.cylinder(Vector3(0,9,0),4.2,18,"stone")
			g.dome(Vector3(0,18,0),4.7,4,"roof")
			node=MeshInstance3D.new()
			node.mesh=g.finish()
		node.name=item["id"]
		node.set_meta("grounded_footings",true)
		node.position=Layout.world(data,item["position_m"])
		node.rotation.y=deg_to_rad(float(item.get("rotation_deg",0)))
		node.scale=Vector3.ONE*float(item.get("scale",1.0))
		var top:=_surface_height(node.position.x,-node.position.z)
		for x in [-5.0,0.0,5.0]:
			for z in [-6.0,0.0,6.0]:
				var corner:Vector3=node.position+node.basis*Vector3(x,0,z)
				top=maxf(top,_surface_height(corner.x,-corner.z))
		node.position.y=top+0.03
		additions.add_child(node)

func ground_can_walk(p:Vector3) -> bool:
	if Layout.height_at(data,p.x,-p.z)<0.3:return false
	var key:=Vector2i(floori(p.x/80.0),floori(p.z/80.0))
	for dx in [-1,0,1]:
		for dz in [-1,0,1]:
			for item in _obstacles.get(key+Vector2i(dx,dz),[]):
				var local:=Basis(Vector3.UP,-float(item["yaw"]))*(p-Vector3(item["position"]))
				var size:Vector3=item["size"]
				if absf(local.x)<size.x*0.5+0.35 and absf(local.z)<size.z*0.5+0.35:return false
	return true

func set_cutaway(enabled:bool) -> void:
	for cap in _cutaway_caps:cap.visible=not enabled

func set_quality(high:bool) -> void:
	for child in urban.get_children():
		if child is MultiMeshInstance3D:
			child.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if high else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _add_mesh(mesh:ArrayMesh,label:String,parent:Node3D) -> MeshInstance3D:
	var instance:=MeshInstance3D.new()
	instance.name=label
	instance.mesh=mesh
	parent.add_child(instance)
	return instance
