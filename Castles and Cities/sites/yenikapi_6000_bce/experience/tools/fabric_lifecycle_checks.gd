extends SceneTree
const Fabric=preload("res://src/fabric.gd")
const FabricProjection=preload("res://src/core/fabric_projection.gd")
const Land=preload("res://src/core/land_rules.gd")
var checks: int=0
var failures: int=0

class AssetStub extends RefCounted:
	func active(_state: Dictionary) -> bool:return true

class RuleStub extends RefCounted:
	var assets=AssetStub.new()
	var projects: Dictionary={}
	var content: Dictionary={"households":[]}
	var balance: Dictionary={"people_per_dwelling":6}
	var residents: Array=[]
	func people(_state: Dictionary) -> Array:return residents
	func has_project(state: Dictionary,id: String) -> bool:
		for item in state.completed:
			if item.id==id:return true
		return false
	func whole(value: Variant,low: int,high: int) -> bool:
		return (value is int or value is float) and float(value)==floorf(float(value)) and value>=low and value<=high

func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func alteration(id: String,expected: int,lifecycle: bool=true) -> Dictionary:
	var change: Dictionary={"kind":"altered","before":["store"],"after":[{"id":"store","revision":1,"at":[3,7],"furniture":[{"id":"bowl"}]}]}
	if lifecycle:change.expected_revisions={"store":expected}
	return {"id":id,"lifecycle":lifecycle,"changes":[change]}
func proposal(id: String,predecessor: String,work: int,lifecycle: bool=true) -> Dictionary:
	var value: Dictionary={"id":id,"site":"workroom","asset":"workroom","requires_access":false,"food":0,"work":work,"cooperation":0,"choice_group":"","retain":true}
	if lifecycle:value.lifecycle=true;value.predecessor=predecessor
	return value
func run() -> void:
	var base: Dictionary={"snapshot_id":"base","objects":[{"id":"store","revision":1,"at":[3,7],"furniture":[{"id":"bowl"}]}]}
	var projects: Dictionary={"first":alteration("first",1,false),"second":alteration("second",2),"third":alteration("third",3)}
	var original: String=JSON.stringify([base,projects])
	var first: Array=[{"id":"first"}]
	var second: Array=first+[{"id":"second"}]
	var legacy: Dictionary=Fabric.resolve(base,{"id":"scenario","kind":"hypothetical","base_snapshot_id":"base","changes":projects.first.changes})
	var replay: Dictionary=FabricProjection.resolve(base,first,projects,"scenario")
	check(JSON.stringify(replay.objects)==JSON.stringify(legacy.objects),"legacy objects remain byte-identical")
	var result: Dictionary=FabricProjection.resolve(base,second,projects,"scenario")
	check(not result.has("error") and result.objects[0].revision==3,"same object evolves from revision one through three")
	check(result.objects[0].at==base.objects[0].at and result.objects[0].furniture==base.objects[0].furniture,"location and furnishings remain")
	check(result.objects[0].change.project_id=="second" and result.objects[0].change.predecessors==["store@2"],"latest object names project and predecessor revision")
	check(result.lineage.size()==2 and result.lineage[1].after==["store@3"],"ordered immutable lineage records project revisions")
	check(FabricProjection.resolve(base,second+[{"id":"third"}],projects,"scenario").objects[0].revision==4,"later explicit successor continues chain")
	check(FabricProjection.resolve(base,[{"id":"second"},{"id":"first"}],projects,"scenario").get("error")=="stale_predecessor_revision","ledger order determines predecessor readiness")
	var invalid: Dictionary=projects.duplicate(true)
	invalid.second.changes[0].expected_revisions.store=1
	check(FabricProjection.resolve(base,second,invalid,"scenario").get("error")=="stale_predecessor_revision","stale authored revision rejected")
	invalid=projects.duplicate(true);invalid.second.changes[0].erase("expected_revisions")
	check(FabricProjection.resolve(base,second,invalid,"scenario").get("error")=="missing_expected_revisions","new changes require explicit expectations")
	invalid=projects.duplicate(true);invalid.second.changes[0].expected_revisions.other=1
	check(FabricProjection.resolve(base,second,invalid,"scenario").get("error")=="invalid_expected_revisions","extra expectation rejected")
	invalid=projects.duplicate(true);invalid.second.changes.append(invalid.second.changes[0].duplicate(true))
	check(FabricProjection.resolve(base,second,invalid,"scenario").get("error")=="duplicate_transaction_mutation","duplicate mutation in one transaction rejected")
	invalid=projects.duplicate(true);invalid.second.lifecycle=false
	check(FabricProjection.resolve(base,second,invalid,"scenario").get("error")=="missing_or_reused_predecessor","legacy changes retain original reuse guard")
	invalid=projects.duplicate(true)
	invalid.second.changes=[{"kind":"added","before":[],"after":[{"id":"new","revision":1}],"expected_revisions":{}},{"kind":"altered","before":["new"],"after":[{"id":"new","revision":1}],"expected_revisions":{"new":1}}]
	check(FabricProjection.resolve(base,second,invalid,"scenario").get("error")=="duplicate_transaction_mutation","addition cannot be mutated twice inside one transaction")
	var inactive: Dictionary=base.duplicate(true);inactive.objects[0].active=false
	check(FabricProjection.resolve(inactive,[{"id":"second"}],{"second":alteration("second",1)},"scenario").get("error")=="stale_predecessor_revision","inactive fabric cannot be silently revived")
	var queued: Dictionary={"completed":first,"queue":[{"id":"second"}]}
	check(not FabricProjection.pending(base,queued,projects,"scenario").has("error"),"valid queued alteration accepted")
	check(FabricProjection.pending(base,queued,projects,"scenario","third").get("error")=="stale_predecessor_revision","queued successor cannot borrow unfinished work")
	invalid=projects.duplicate(true);invalid.rival=alteration("rival",2)
	check(FabricProjection.pending(base,queued,invalid,"scenario","rival").get("error")=="fabric_reserved","distinct projects cannot reserve the same object")
	check(FabricProjection.resolve(base,second+[{"id":"second"}],projects,"scenario").get("error")=="invalid_project_ledger","duplicate completion rejected")
	check(JSON.stringify([base,projects])==original,"all replay and validation queries are pure")
	_land_checks()
	_legacy_checks()
	_boundary_checks()
	print("Fabric lifecycle checks: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _land_checks() -> void:
	var config: Dictionary={"sites":[{"id":"workroom","food":0,"work":2,"cooperation":0}],"proposals":[proposal("first","",6,false),proposal("second","first",9),proposal("third","second",11)],"legacy_projects":[],"tutorial":[]}
	var land=Land.new(config,{"minimum_reserve":1})
	var rules=RuleStub.new()
	for p in config.proposals:rules.projects[p.id]={"changes":[]}
	var state: Dictionary={"turn":3,"food":100,"completed":[{"id":"first","turn":1}],"queue":[],"land":{"version":1,"started":0,"inspected":[],"tutorial":0,"access_enabled":true,"report":{}},"lifecycle":{"version":1}}
	check(land.validate(state,rules),"predecessor land use validates")
	check(land.blocked(state,"second",rules)=="","explicit successor is commissionable")
	check(land.blocked(state,"third",rules)=="land_conflict","successor cannot skip prior land use")
	state.queue=[{"id":"second"}]
	check(land.use_at(state,"workroom",rules)=="first" and land.totals(state,rules).work==6,"retained staging preserves prior working capacity")
	check(land.validate(state,rules),"paid successor reservation validates")
	state.queue.append({"id":"third"})
	check(not land.validate(state,rules),"two reservations cannot claim one site")
	state.queue=[]
	check(land.totals(state,rules).work==6,"cancelled successor leaves previous use intact")
	state.completed.append({"id":"second","turn":2})
	check(land.use_at(state,"workroom",rules)=="second" and land.totals(state,rules).work==9,"latest completed full use replaces old site total without double-counting")
	check(land.validate(state,rules) and land.blocked(state,"third",rules)=="","completed successor supports next explicit transition")
	state.completed.append({"id":"third","turn":3})
	check(land.validate(state,rules) and land.totals(state,rules).work==11,"ordered land chain can continue")
	state.completed=[{"id":"first","turn":1},{"id":"third","turn":2}]
	check(not land.validate(state,rules),"save validation refuses skipped land predecessor")
	state.completed=[{"id":"first","turn":1}];state.lifecycle={}
	check(land.use_at(state,"workroom",rules)=="first" and land.validate(state,rules),"inactive lifecycle preserves legacy land semantics")
	check(land.blocked(state,"second",rules)=="lifecycle_missing","successors require explicit lifecycle adoption")
	state.lifecycle={"version":1};state.queue=[{"id":"second"}]
	land.proposals.second.retain=false
	check(land.use_at(state,"workroom",rules)=="second" and land.totals(state,rules).work==0,"conversion staging closes previous use")
	state.queue=[]
	check(land.totals(state,rules).work==6,"canceling conversion restores previous use")
	rules.residents=[{"household":"family"}];rules.content.households=[{"id":"family","building_id":"home","requires":""}]
	rules.projects.second.changes=[{"kind":"removed","before":["home"],"after":[]}]
	check(land.blocked(state,"second",rules)=="land_accommodation","lifecycle successor cannot remove an occupied home")

func _read(id: String) -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("res://data/"+id+".json"))

func _legacy_checks() -> void:
	var rules=preload("res://src/core/settlement_rules.gd").new(_read("governance"),_read("balance"),_read("neighbors"),_read("households"),_read("assets"),_read("land"),_read("living"),_read("incidents"))
	var states: Array=[preload("res://tools/land_driver.gd").at_season(rules,true,32),preload("res://tools/land_driver.gd").at_season(rules,false,32),preload("res://tools/living_driver.gd").at_season(rules,20),preload("res://tools/incident_driver.gd").at_season(rules,20)]
	var base: Dictionary=_read("settlement")
	for i in range(states.size()):
		var changes: Array=[]
		for item in states[i].completed:changes.append_array(rules.projects[item.id].changes)
		var original: Dictionary=Fabric.resolve(base,{"id":rules.content.scenario_id,"kind":"hypothetical","base_snapshot_id":base.snapshot_id,"changes":changes})
		var ordered: Dictionary=FabricProjection.resolve(base,states[i].completed,rules.projects,rules.content.scenario_id)
		check(not original.has("error") and not ordered.has("error"),"retained public-command scenario replays "+str(i))
		check(JSON.stringify(original.get("objects",[]))==JSON.stringify(ordered.get("objects",[])),"retained actual fabric is byte-identical "+str(i))

func _boundary_checks() -> void:
	var base: Dictionary=_read("settlement")
	var original_base: String=JSON.stringify(base)
	var rules=preload("res://src/core/settlement_rules.gd").new(_read("governance"),_read("balance"),_read("neighbors"),_read("households"),_read("assets"),_read("land"),_read("living"),_read("incidents"),_read("lifecycle"),base)
	var state: Dictionary=preload("res://tools/living_driver.gd").initial(rules)
	state=rules.command(state,{"kind":"commission","id":"shared_store"}).state
	state=rules.advance(state).state
	check(not state.queue.is_empty() and state.queue[0].progress>0,"legacy contract has real paid progress before adoption")
	var before: Dictionary=preload("res://src/campaign_view.gd").snapshot(base,state,rules)
	var adopted: Dictionary=rules.command(state,{"kind":"lifecycle_begin"}).state
	for key in ["queue","completed","wood","food","citizens","living","assets"]:
		check(adopted[key]==state[key],"lifecycle adoption carries legacy contract and "+key)
	check(preload("res://src/campaign_view.gd").snapshot(base,adopted,rules)==before,"adoption itself does not change fabric")
	check(rules.validate_state(adopted),"adopted legacy paid queue remains valid")
	var saved=preload("res://src/campaign_save.gd")
	var path: String="/tmp/yenikapi-fabric-lifecycle-"+str(OS.get_process_id())+".json"
	check(saved.write(path,adopted,rules),"active lifecycle boundary saves atomically")
	var loaded: Dictionary=saved.read(path,rules)
	check(loaded==adopted,"legacy paid work survives lifecycle save readback")
	check(rules.advance(loaded)==rules.advance(adopted),"legacy queue resumes identically after lifecycle adoption")
	var invalid: Dictionary=adopted.duplicate(true)
	for event in invalid.history:
		if event.kind=="lifecycle_adopted":event.params=false
	check(not rules.validate_state(invalid),"malformed adoption event fails without replacing state")
	for malformed in [null,0,true,"active"]:
		invalid=adopted.duplicate(true);invalid.lifecycle=malformed
		check(not rules.validate_state(invalid),"malformed lifecycle type rejected "+str(malformed))
	invalid=adopted.duplicate(true);invalid.lifecycle.recognition=rules.lifecycle.content.recognized_stage
	check(not rules.validate_state(invalid),"unearned legacy town recognition rejected")
	var advanced: Dictionary=rules.advance(adopted).state
	invalid=advanced.duplicate(true);invalid.lifecycle.readiness.last_turn-=1
	check(not rules.validate_state(invalid),"stale readiness clock rejected")
	var town: Dictionary=preload("res://tools/land_driver.gd").at_season(rules,true,32)
	town=rules.command(town,{"kind":"living_begin"}).state
	var town_fabric: Dictionary=preload("res://src/campaign_view.gd").snapshot(base,town,rules)
	var recognized: Dictionary=rules.command(town,{"kind":"lifecycle_begin"}).state
	check(rules.validate_state(recognized) and rules.lifecycle.stage(recognized,rules)==rules.lifecycle.content.recognized_stage,"existing town receives explicit valid recognition")
	check(not rules.has_project(recognized,"lifecycle_assembly") and preload("res://src/campaign_view.gd").snapshot(base,recognized,rules)==town_fabric,"recognition invents no civic building or changed source fabric")
	check(JSON.stringify(base)==original_base,"dated reference remains byte-identical after adoption and replay")
	DirAccess.remove_absolute(path)
