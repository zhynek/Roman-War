extends SceneTree
## A detached presentation fixture exercises earned skills above the old /5 cap.
## Synthetic experience is never saved, advanced or accepted into village state.
const Living=preload("res://tools/living_driver.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,note: String) -> void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",note)
func texts(node: Node) -> Array:
 var rows: Array=[]
 if node is Label:rows.append(node.text)
 for child in node.get_children():rows.append_array(texts(child))
 return rows
func run() -> void:
 var app=load("res://main.tscn").instantiate();root.add_child(app);await process_frame
 var r=app.campaign.rules
 var source: Dictionary=Living.at_season(r,12,true)
 source=r.command(source,{"kind":"warfare_begin"}).state
 var fixture: Dictionary=source.duplicate(true)
 var ids: Array=r.defense.quote(fixture,r).ids
 check(not ids.is_empty(),"real watch assignments are available")
 for id in ids:fixture.warfare.aftermath.people[id]={"battles":30,"experience":30,"last_turn":fixture.turn,"injury":"none"}
 app.campaign.state=fixture;app.show_campaign(fixture,r);app.defense_panel.open()
 var expected: String="%d–%d/%d"%[r.defense.tactical_tuning.max_skill,r.defense.tactical_tuning.max_skill,r.defense.tactical_tuning.max_skill]
 var found: bool=false
 for value in texts(app.defense_panel):
  if expected in value:found=true
 check(found,"all experienced watch display the actual minimum and maximum "+expected)
 check(app.campaign.state==fixture,"readiness rendering leaves the detached state unchanged")
 check(source.warfare.aftermath.people.is_empty(),"synthetic experience never reaches source village")
 app.defense_panel.close()
 print("READINESS PRESENTATION: ",checks," checks, ",failures," failures")
 quit(1 if failures else 0)
