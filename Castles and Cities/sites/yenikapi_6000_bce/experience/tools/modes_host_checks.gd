extends SceneTree
## Worker pacing, cancellation and save/resume exercise the production battle rules.
const Host=preload("res://src/defense_host.gd")
const Adapter=preload("res://src/defense_adapter.gd")
const Saves=preload("res://src/campaign_save.gd")
const Living=preload("res://tools/living_driver.gd")
class SlowDefense extends RefCounted:
	var original
	var tuning: Dictionary
	func _init(r):original=r;tuning=r.defense.tuning
	func control(b,a,_r) -> String:return original.defense.control(b,a,original)
	func prepare_delegated(b,_r) -> void:original.defense.prepare_delegated(b,original)
	func step(b,_r) -> void:
		# A deliberately slow wrapper verifies cancellation even on slower machines.
		OS.delay_msec(15);original.defense.step(b,original)
var checks: int=0
var failures: int=0
var measurements: Dictionary={}
var app
var r
func _initialize() -> void:call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",note)
func apply(b: Dictionary,action: Dictionary) -> void:check(r.defense.control(b,action,r).is_empty(),"accepted "+str(action))
func resolve(b: Dictionary) -> void:
	for i in range(int(r.defense.tuning.limit_ticks)+1):
		if b.phase=="ended":break
		r.defense.step(b,r)
	check(b.phase=="ended","bounded ordinary fixed-step resolution")
func wait_quick(host) -> void:
	var started: int=Time.get_ticks_msec()
	while host.status().quick and Time.get_ticks_msec()-started<15000:await create_timer(.002).timeout
	check(not host.status().quick,"quick worker terminates within 15-second test bound")
func run() -> void:
	app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame;r=app.campaign.rules
	var source: Dictionary=Living.at_season(r,12,true)
	source=r.command(source,{"kind":"warfare_begin"}).state
	app.campaign.state=source;app.show_campaign(source,r)
	var nav: Dictionary=Adapter.capture(app.world,r.defense)
	var begun: Dictionary=r.command(source,{"kind":"defense_begin","nav":nav})
	check(begun.has("state"),"ordinary prepared residents mobilize")
	if not begun.has("state"):quit(1);return
	var state: Dictionary=begun.state
	var initial: Dictionary=state.defense.battle.duplicate(true)
	var normal: Dictionary=initial.duplicate(true)
	apply(normal,{"kind":"defense_mode","mode":"delegated"});r.defense.prepare_delegated(normal,r);apply(normal,{"kind":"defense_start"});resolve(normal)
	var host=Host.new();host.attach(r,initial)
	check(host.begin_quick().is_empty(),"quick starts delegated encounter through command boundary")
	host.run();await wait_quick(host);host.stop()
	var accelerated: Dictionary=host.snapshot()
	measurements.typical_ms=host.status().elapsed_ms;measurements.typical_ticks=accelerated.tick
	check(accelerated==normal,"batching equals ordinary ticks including AI decisions and serialized command stream")
	check(int(measurements.typical_ms)<2000,"typical quick resolution meets practical two-second target")
	check(initial==state.defense.battle,"worker never changes caller's detached initial state")
	# The standard paced host must also go through Director + defense.step.
	var paced=Host.new();paced.attach(r,initial);paced.invoke({"kind":"defense_mode","mode":"delegated"});paced.invoke({"kind":"defense_start"});paced.run()
	while int(paced.status().tick)<2:await create_timer(.003).timeout
	paced.pause();paced.stop();var paced_b: Dictionary=paced.snapshot()
	var expected: Dictionary=initial.duplicate(true)
	apply(expected,{"kind":"defense_mode","mode":"delegated"});apply(expected,{"kind":"defense_start"})
	for i in range(int(paced_b.tick)):r.defense.step(expected,r)
	apply(expected,{"kind":"defense_pause"})
	check(paced_b==expected,"normal worker includes the same delegated orders and exact fixed ticks")
	var slow=Host.new();slow.attach({"defense":SlowDefense.new(r)},initial);slow.begin_quick();slow.run()
	while int(slow.status().tick)<2:await create_timer(.002).timeout
	var cancel_at: int=Time.get_ticks_msec();slow.cancel_quick();measurements.cancel_ms=Time.get_ticks_msec()-cancel_at
	var paused: Dictionary=slow.snapshot();slow.stop()
	check(paused.phase=="fighting" and paused.paused and paused.tick>0,"cancel keeps a partially simulated coherent active battle")
	check(not slow.status().quick and paused.tactics.encounter.mode=="delegated","cancel changes runtime batching and pause, preserving delegated mode")
	check(paused.commands.back().action=={"kind":"defense_pause"},"cancellation pause is an accepted serialized command")
	check(int(measurements.cancel_ms)<250,"bounded mutex batches keep cancellation responsive")
	state.defense.battle=paused.duplicate(true)
	var save_path: String="/tmp/village-modes-host-checks.json"
	check(Saves.write(save_path,state,r),"cancelled quick state validates and saves")
	var loaded: Dictionary=Saves.read(save_path,r)
	check(loaded==state,"cancelled quick state roundtrips exactly")
	if not loaded.is_empty():
		var resumed=Host.new();resumed.attach(r,loaded.defense.battle);check(resumed.begin_quick().is_empty(),"saved paused delegated state resumes quick simulation");resumed.run();await wait_quick(resumed);resumed.stop()
		var reference: Dictionary=paused.duplicate(true)
		apply(reference,{"kind":"defense_mode","mode":"delegated"});apply(reference,{"kind":"defense_pause"});resolve(reference)
		check(resumed.snapshot()==reference,"saved resumed batches exactly match ordinary simulation for the same commands")
		state.defense.battle=resumed.snapshot()
		check(Saves.write(save_path,state,r),"ended quick state saves before acceptance")
		var accepted: Dictionary=r.command(state,{"kind":"defense_commit"})
		check(accepted.has("state") and accepted.state.defense.battle.is_empty(),"quick outcome reconciles through the ordinary acceptance boundary")
		if accepted.has("state"):check(not r.command(accepted.state,{"kind":"defense_commit"}).has("state"),"second acceptance cannot duplicate consequences")
	# Legacy battles still use the same fixed-step host without mode metadata.
	var legacy_source: Dictionary=Living.at_season(r,12,true)
	var legacy: Dictionary=r.command(legacy_source,{"kind":"defense_begin","nav":nav}).state.defense.battle
	var old=Host.new();old.attach(r,legacy);check(old.begin_quick()=="bad_order","legacy battle does not silently adopt mode extensions");old.pause();old.stop()
	# The lightweight view is also safe for isolated practice.
	var panel=app.defense_panel;panel.open();panel.mobilize(true);panel.render_quick()
	check(panel.find_child("DefenseSave",true,false).disabled,"quick practice exposes no continuing-village save action")
	check(not app.world.visible and not panel.view.visible,"quick progress suppresses expensive geometry")
	panel.cancel_quick();check(app.world.visible and panel.view.visible,"cancellation restores presentation without touching rules")
	panel.close()
	print("MODES HOST: ",checks," checks, ",failures," failures; measurements ",JSON.stringify(measurements))
	FileAccess.open("/tmp/village-modes-host-report.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements},"  "))
	quit(1 if failures else 0)
