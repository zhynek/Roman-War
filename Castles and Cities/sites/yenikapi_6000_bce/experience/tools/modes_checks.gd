extends SceneTree
## Cross-layer equivalence and continuing-season reconciliation; no rendering clock.
const Driver=preload("res://tools/lifecycle_driver.gd")
const Living=preload("res://tools/living_driver.gd")
const View=preload("res://src/campaign_view.gd")
const Adapter=preload("res://src/defense_adapter.gd")
const Saves=preload("res://src/campaign_save.gd")
var r
var checks: int=0
var failures: int=0
var timings: Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",note)
func cmd(s: Dictionary,a: Dictionary) -> Dictionary:
	var result: Dictionary=r.command(s,a)
	check(result.has("state"),str(a)+": "+str(result.get("error","")))
	return result.get("state",s)
func run() -> void:
	r=Driver.rules()
	var base: Dictionary=Living.at_season(r,12,true)
	base=cmd(base,{"kind":"warfare_begin"})
	base=cmd(base,{"kind":"warfare_muster","value":4})
	var world=preload("res://src/village.gd").new();root.add_child(world)
	world.build(View.snapshot(Driver.read("settlement"),base,r));world.set_meta("project_presentation",true)
	var presentation=View.new();root.add_child(presentation);presentation.refresh(base,r,world)
	var nav: Dictionary=Adapter.capture(world,r.defense)
	var scheduled:=cmd(base,{"kind":"warfare_threats"})
	var seen: Array=[]
	for cycle in range(3):
		for season in range(40):
			if r.warfare.threats.ready(scheduled,r):break
			var advanced: Dictionary=r.advance(scheduled)
			check(advanced.has("state"),"ordinary preparation season")
			if not advanced.has("state"):break
			scheduled=advanced.state
			check(r.validate_state(scheduled),"seasonal threat state validates")
		check(r.warfare.threats.ready(scheduled,r),"bounded warning becomes actionable")
		if not r.warfare.threats.ready(scheduled,r):break
		check(r.advance(scheduled).get("error")=="threat_ready","ready encounter prevents skipping consequence")
		var path: String="/tmp/village-modes-%d.json"%cycle
		check(Saves.write(path,scheduled,r) and Saves.read(path,r)==scheduled,"threat preparation save")
		# Capture the actual fabric after seasons instead of reusing a stale geometry snapshot.
		world.build(View.snapshot(Driver.read("settlement"),scheduled,r));presentation.refresh(scheduled,r,world)
		nav=Adapter.capture(world,r.defense)
		var s:=cmd(scheduled,{"kind":"defense_begin","nav":nav})
		if not r.defense.locked(s):break
		var encounter: String=s.defense.battle.tactics.encounter.id
		seen.append(encounter)
		check(r.validate_state(s),"new deployment validates "+encounter)
		check(Saves.write(path,s,r) and Saves.read(path,r)==s,"scheduled deployment roundtrip")
		s=cmd(s,{"kind":"defense_mode","mode":"delegated"})
		r.defense.prepare_delegated(s.defense.battle,r)
		s=cmd(s,{"kind":"defense_start"})
		var streamed: Dictionary=s.duplicate(true)
		var batched: Dictionary=s.duplicate(true)
		var resumed: Dictionary={}
		var began: int=Time.get_ticks_msec()
		for i in range(5000):
			r.defense.step(streamed.defense.battle,r)
			if i==83:
				check(Saves.write(path,streamed,r),"delegated active save")
				resumed=Saves.read(path,r)
				check(resumed==streamed,"active authority restored including AI schedule")
			elif r.defense.locked(resumed):
				r.defense.step(resumed.defense.battle,r)
				check(resumed==streamed,"resumed fixed tick matches uninterrupted")
			if streamed.defense.battle.phase=="ended":break
		timings.append({"encounter":encounter,"elapsed_ms":Time.get_ticks_msec()-began,"ticks":streamed.defense.battle.tick})
		check(streamed.defense.battle.phase=="ended","delegated bounded termination "+encounter)
		for batch in range(400):
			for i in range(16):r.defense.step(batched.defense.battle,r)
			if batched.defense.battle.phase=="ended":break
		check(batched==streamed,"normal tick and accelerated batch exact equivalence "+encounter)
		check(r.validate_state(streamed),"ended unaccepted state validates "+encounter)
		check(Saves.write(path,streamed,r) and Saves.read(path,r)==streamed,"ended waiting acceptance save")
		# Replaying the identical serialized order stream in direct mode produces
		# identical tactical state. Mode and command history differ intentionally.
		var replay: Dictionary=s.duplicate(true);replay.defense.battle.tactics.encounter.mode="direct"
		var original_count: int=replay.defense.battle.commands.size()
		var commands: Array=streamed.defense.battle.commands.slice(original_count)
		for tick in range(5000):
			for entry in commands:
				if int(entry.tick)==int(replay.defense.battle.tick):check(r.defense.control(replay.defense.battle,entry.action,r).is_empty(),"delegated order valid through player boundary")
			r.defense.step(replay.defense.battle,r)
			if replay.defense.battle.phase=="ended":break
		var expected: Dictionary=streamed.defense.battle.duplicate(true)
		expected.tactics.encounter.mode="direct";expected.tactics.encounter.next_decision=replay.defense.battle.tactics.encounter.next_decision
		check(expected==replay.defense.battle,"identical player stream gives identical outcome "+encounter)
		var before: Dictionary=scheduled.duplicate(true)
		scheduled=cmd(streamed,{"kind":"defense_commit"})
		check(r.validate_state(scheduled),"accepted repeated encounter validates "+encounter)
		check(r.command(scheduled,{"kind":"defense_commit"}).has("error"),"repeated commit refused")
		for key in ["completed","queue","contacts","lifecycle","land","assets"]:check(scheduled[key]==before[key],"outcome preserves unrelated "+key)
		check(not r.warfare.threats.ready(scheduled,r),"post battle recovery interval")
		check(scheduled.defense.reports.size()==cycle+1,"persistent encounter report history")
	check(seen.size()==3 and seen[0]!=seen[1] and seen[1]!=seen[2] and seen[0]!=seen[2],"three different sequential objectives")
	print("MODE TIMINGS ",JSON.stringify(timings))
	print("VILLAGE MODES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
