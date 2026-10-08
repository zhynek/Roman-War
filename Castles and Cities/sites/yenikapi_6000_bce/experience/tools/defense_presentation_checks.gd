extends SceneTree
## View-only acceptance: synthetic detached snapshots never enter village rules.
## Optional -- render out_dir=/tmp/... captures procedural articulation outside Git.
const View = preload("res://src/defense_view.gd")
class FlatGround:
	extends Node3D
	func floor_height(_x: float, _z: float) -> float:return 0.0
var checks: int = 0
var failures: int = 0
var out_dir: String = "/tmp/village-defense-presentation"
var render: bool = false
var view
var battle: Dictionary
var copy: Dictionary
var tuning: Dictionary
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "render":render = true
		if arg.begins_with("out_dir="):out_dir = arg.trim_prefix("out_dir=")
	call_deferred("run")
func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:failures += 1;printerr("FAIL ",note)
func group(id: String, side: String, at: Array, count: int) -> Dictionary:
	return {"id":id,"side":side,"initial":count,"kits":count,"hp":count*int(tuning.hp_per_person),"morale":80,"position":at,"goal":at.duplicate(),"path":[],"order":"hold","facing":[0,1000],"routed":false,"exited":false,"revealed":side=="watch","moving":false,"engaged":false,"attack_seq":0,"hit_seq":0,"tactical":{"width":2,"effective_width":2,"fatigue":28,"blocked":""}}
func signature(node: Node) -> Array:
	var result: Array = []
	if node is Node3D:result.append(node.transform)
	if node is MeshInstance3D:
		result.append(node.mesh.get_class());result.append(node.mesh.get_aabb())
		result.append(node.material_override.albedo_color)
	for child in node.get_children():result.append(signature(child))
	return result
func run() -> void:
	copy = JSON.parse_string(FileAccess.get_file_as_string("res://data/governance.json")).defense.ui
	tuning = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json")).defense
	var world := FlatGround.new();root.add_child(world)
	view = View.new();view.world = world;root.add_child(view)
	battle = {"paused":false,"speed":1,"nav":{"places":{"stores":[-1000,-1000]}},"groups":[group("watch_1","watch",[-160,0],2),group("raider_1","raider",[160,0],3)]}
	var original: Dictionary = battle.duplicate(true)
	view.update(battle,["watch_1"],copy,tuning,.016)
	check(not view.actors.has("raider_1") and not view.anchors.has("raider_1"),"unseen enemy has no model or selectable anchor")
	for i in range(120):view.update(battle,["watch_1"],copy,tuning,.016)
	check(battle == original,"rendering and cosmetic time leave every snapshot value unchanged")
	var own: Dictionary = battle.groups[0]
	check(view.anchors.watch_1 == view.actors.watch_1.node.position+Vector3.UP,"picking uses exactly the rendered root")
	own.order = "advance";own.goal = [-160,400];own.path = [[-160,100],[-100,200],[-160,400]]
	view.update(battle,["watch_1"],copy,tuning,.016)
	var route_id: int = view.actors.watch_1.route.get_instance_id()
	var mesh_id: int = view.actors.watch_1.route.mesh.get_instance_id()
	var nodes: int = view.get_child_count()
	for i in range(60):view.update(battle,["watch_1"],copy,tuning,.016)
	check(view.get_child_count() == nodes and view.actors.watch_1.route.get_instance_id() == route_id and view.actors.watch_1.route.mesh.get_instance_id() == mesh_id,"ordinary frames retain goal nodes and mesh resources")
	check(view.actors.watch_1.route.mesh.get_surface_count() == 1,"retained route never accumulates stale surfaces")
	own.tactical.effective_width = 1;view.update(battle,["watch_1"],copy,tuning,.016)
	check(view.actors.watch_1.figures[0].offset.x == 0 and view.actors.watch_1.figures[1].offset.x == 0,"squeezed formation shows a centered column")
	own.tactical.effective_width = 2;view.update(battle,["watch_1"],copy,tuning,.016)
	check(view.actors.watch_1.figures[0].offset.x == -view.actors.watch_1.figures[1].offset.x,"wide formation is centered on its pick anchor")
	own.moving = true;view.update(battle,["watch_1"],copy,tuning,.016);battle.paused = true
	var frozen: Array = signature(view.actors.watch_1.node)
	for i in range(30):view.update(battle,["watch_1"],copy,tuning,.033)
	check(signature(view.actors.watch_1.node) == frozen,"pause freezes articulation and visual events")
	battle.groups[1].revealed = true;view.update(battle,["watch_1"],copy,tuning,0)
	var generic: Array = signature(view.actors.raider_1.node)
	var other = View.new();other.world = world;root.add_child(other)
	var altered: Dictionary = battle.duplicate(true);altered.groups[1].kits = 99;altered.groups[1].readiness = 99;altered.groups[1].members = ["private_hidden_roster"]
	other.update(altered,["watch_1"],copy,tuning,0)
	check(signature(other.actors.raider_1.node) == generic,"visible enemy geometry ignores private kit, readiness and roster")
	other.free()
	var enemy_actor: Dictionary = view.actors.raider_1
	battle.groups[1].revealed = false
	view.update(battle,["watch_1"],copy,tuning,0)
	check(not enemy_actor.node.visible and not enemy_actor.goal.visible and not enemy_actor.route.visible and not view.anchors.has("raider_1"),"lost sight hides retained enemy model and all markers")
	battle.groups[1].attack_seq += 3;battle.groups[1].hit_seq += 2
	battle.groups[1].revealed = true
	view.update(battle,["watch_1"],copy,tuning,0)
	check(enemy_actor.node.visible and view.anchors.has("raider_1") and not enemy_actor.impact.visible and enemy_actor.attack_until<view.elapsed,"re-observation restores exact anchor without replaying hidden attacks")
	own.tactical.face = [1000,0];own.tactical.face_locked = true
	var paused_order: Dictionary = battle.duplicate(true)
	view.update(battle,["watch_1"],copy,tuning,0)
	check(view.actors.watch_1.node.basis.z.is_equal_approx(Vector3(0,0,1)) and view.actors.watch_1.facing.global_basis.z.is_equal_approx(Vector3(1,0,0)),"paused facing intent changes marker without turning authoritative body")
	check(view.actors.watch_1.goal.basis.z.is_equal_approx(Vector3(1,0,0)) and battle == paused_order,"destination facing follows paused intent without changing snapshot")
	own.tactical.face = [-1000,0]
	view.update(battle,["watch_1"],copy,tuning,0)
	check(view.actors.watch_1.goal.basis.z.is_equal_approx(Vector3(-1,0,0)),"retained destination refreshes when only intended facing changes")
	own.tactical.face_locked = false
	view.update(battle,["watch_1"],copy,tuning,0)
	check(view.actors.watch_1.facing.global_basis.z.is_equal_approx(Vector3(0,0,1)),"released facing intent returns marker to actual facing")
	var legacy: Dictionary = battle.duplicate(true)
	for f in legacy.groups:f.erase("tactical")
	view.update(legacy,["watch_1"],copy,tuning,0)
	check(view.actors.watch_1.width == 2,"legacy snapshots render without a tactical extension")
	battle.groups[0].exited = true;view.update(battle,["watch_1"],copy,tuning,0)
	check(not view.actors.watch_1.node.visible and not view.anchors.has("watch_1") and not view.actors.watch_1.goal.visible,"exited formation has no stale marker or pick anchor")
	battle.groups[0].exited = false
	if render:await render_probe()
	print("DEFENSE PRESENTATION: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func shot(name_: String) -> void:
	for i in range(8):await process_frame;RenderingServer.force_draw(true)
	check(root.get_texture().get_image().save_png(out_dir.path_join(name_+".png"))==OK,"rendered "+name_)
func render_probe() -> void:
	root.size = Vector2i(1280,800);root.always_on_top = true;root.grab_focus()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var stage := Node3D.new();root.add_child(stage)
	var camera := Camera3D.new();stage.add_child(camera);camera.position = Vector3(6,4.5,8);camera.look_at(Vector3(0,.9,0));camera.current = true
	var light := DirectionalLight3D.new();light.rotation_degrees = Vector3(-45,-30,0);light.light_energy = 1.15;light.shadow_enabled = true;stage.add_child(light)
	var env := WorldEnvironment.new();env.environment = Environment.new();env.environment.background_mode = Environment.BG_COLOR;env.environment.background_color = Color("abb5ab");env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color = Color("d1d3be");env.environment.ambient_light_energy = .7;stage.add_child(env)
	view.box(stage,Vector3(0,-.08,0),view.material("777d61"),Vector3(30,.1,30))
	var own: Dictionary = battle.groups[0];var enemy: Dictionary = battle.groups[1]
	own.order = "defend";own.goal = own.position.duplicate();own.path = [];own.moving = false;own.engaged = false
	enemy.revealed = true;enemy.facing = [0,-1000]
	battle.paused = true;view.update(battle,["watch_1"],copy,tuning,0);await shot("01-wide-equipment-guard")
	own.tactical.face = [1000,0];own.tactical.face_locked = true
	view.update(battle,["watch_1"],copy,tuning,0);await shot("01a-paused-facing-intent")
	own.tactical.face_locked = false
	own.moving = true;own.order = "advance";own.goal = [-160,350];own.path = [[-160,200],[-160,350]]
	own.tactical.effective_width = 1;own.tactical.blocked = "formation_narrow";battle.paused = false
	for i in range(13):view.update(battle,["watch_1"],copy,tuning,.016)
	battle.paused = true;await shot("02-column-moving-order")
	own.engaged = true;own.attack_seq += 1;own.moving = false;own.tactical.effective_width = 2;own.tactical.blocked = ""
	enemy.position = [-160,155];enemy.engaged = true;enemy.hit_seq += 1
	battle.paused = false
	for i in range(16):view.update(battle,["watch_1"],copy,tuning,.016)
	battle.paused = true;await shot("03-attack-and-reaction")
	own.moving = true;own.routed = true;own.morale = 12;own.tactical.fatigue = 82;own.hp = int(tuning.hp_per_person)
	own.facing = [0,-1000];battle.paused = false
	for i in range(20):view.update(battle,["watch_1"],copy,tuning,.016)
	battle.paused = true;await shot("04-incapacitation-and-withdrawal")
