extends SceneTree
## Exhaustion retains serialized, bounded start/pause/withdraw escape controls.
const Driver=preload("res://tools/lifecycle_driver.gd")
const Living=preload("res://tools/living_driver.gd")
const View=preload("res://src/campaign_view.gd")
const Adapter=preload("res://src/defense_adapter.gd")
const Saves=preload("res://src/campaign_save.gd")
const Host=preload("res://src/defense_host.gd")
var checks: int=0
var failures: int=0
func _initialize():call_deferred("run")
func check(ok: bool,note: String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",note)
func run():
 var r=Driver.rules()
 var base: Dictionary=Living.at_season(r,12,true)
 var world=preload("res://src/village.gd").new();root.add_child(world)
 world.build(View.snapshot(Driver.read("settlement"),base,r))
 var presentation=View.new();root.add_child(presentation);world.set_meta("project_presentation",true);presentation.refresh(base,r,world)
 var s: Dictionary=r.command(base,{"kind":"warfare_begin"}).state
 s=r.command(s,{"kind":"defense_begin","nav":Adapter.capture(world,r.defense)}).state
 var initial: Dictionary=s.defense.battle.duplicate(true)
 var b: Dictionary=s.defense.battle
 for i in range(r.defense.ORDER_BUDGET-b.commands.size()):check(r.defense.control(b,{"kind":"defense_speed"},r)=="","fill ordinary log")
 check(r.defense.control(b,{"kind":"defense_speed"},r)=="command_budget","ordinary budget remains bounded with an explanatory error")
 check(r.defense.control(b,{"kind":"defense_start"},r)=="" and b.phase=="fighting","start survives exhausted deployment budget")
 var host=Host.new();host.attach(r,b);host.pause();b=host.snapshot();host.stop();s.defense.battle=b
 check(b.paused,"save/cancel host pause survives exhaustion")
 var count: int=b.commands.size()
 for i in range(500):check(r.defense.control(b,{"kind":"defense_pause"},r)=="","reserved pause toggle")
 check(b.paused and b.commands.size()==count,"same-tick toggles compact to identical paused state")
 var ids: Array=[]
 for f in b.groups:
  if f.side=="watch":ids.append(f.id)
 var withdrawal: Dictionary={"kind":"defense_order","order":"withdraw","ids":ids,"at":b.exits.watch}
 check(r.defense.control(b,withdrawal,r)=="","withdraw survives exhausted ordinary budget")
 count=b.commands.size()
 for i in range(100):check(r.defense.control(b,withdrawal,r)=="command_budget","repeated withdrawal cannot consume safety reserve")
 check(b.commands.size()==count,"withdrawal repeats leave log unchanged")
 check(r.validate_state(s),"exhausted paused withdrawal state validates")
 var path: String="/tmp/village-command-budget-save.json"
 check(Saves.write(path,s,r) and Saves.read(path,r)==s,"reserved controls save/resume exactly")
 var replay: Dictionary=initial.duplicate(true)
 for c in b.commands.slice(initial.commands.size()):check(r.defense.control(replay,c.action,r)=="","compact stream replays")
 check(replay==b,"compact commands reproduce every authoritative field")
 var bad: Dictionary=s.duplicate(true);bad.defense.battle.commands.append({"tick":b.tick,"action":{"kind":"defense_speed"}})
 check(not r.validate_state(bad),"ordinary command in safety reserve rejected by save validator")
 check(r.defense.control(b,{"kind":"defense_pause"},r)=="","resume withdrawn groups after save")
 for i in range(int(r.defense.tuning.limit_ticks)+1):
  r.defense.step(b,r)
  if b.phase=="ended":break
 check(b.phase=="ended" and r.validate_state(s),"exhausted battle still reaches valid bounded result")
 check(r.command(s,{"kind":"defense_commit"}).has("state"),"exhausted battle reconciles once")
 print("COMMAND BUDGET: ",checks," checks, ",failures," failures")
 quit(1 if failures else 0)
