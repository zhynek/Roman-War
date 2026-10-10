extends RefCounted
## Presentation adapter for the saved handover. No orders, automatic progress,
## provider calls or reads of worker-owned campaign state.
var _owner: WeakRef
var owner:
	get:return _owner.get_ref()

func _init(context_owner) -> void:
	_owner=weakref(context_owner)

func words() -> Dictionary:
	return owner.session.game.data.succession_council_content.ui

func _text(id: String, params: Dictionary={}) -> String:
	return String(words().get(id,id)).format(params)

func status() -> Dictionary:
	var block: String=owner.council_context.blocked()
	if block!="":return {"blocked":block,"available":false,"eligible":false,"briefing":{}}
	return owner.session.game.succession_council_status()

func selected_briefing() -> Dictionary:
	if owner.session.council_agenda!="succession":return {}
	var reading: Dictionary=status()
	if reading.get("blocked","")!="" or not reading.get("available",false):return {}
	if reading.get("key","")!=owner.session.succession_key:return {}
	return reading.briefing.duplicate(true)

func select(key: String) -> bool:
	var reading: Dictionary=status()
	if reading.get("blocked","")!="" or not reading.get("available",false):return false
	if reading.get("key","")!=key:return false
	for panel in owner.session.advisor_panels.values():panel.voice.stop()
	owner.session.living_council.reset()
	owner.session.council_agenda="succession"
	owner.session.succession_key=key
	return true

func respond(key: String, action: String) -> bool:
	if owner.council_context.blocked()!="":return false
	return owner.session.game.succession_council_respond(key,action)

func date(calendar: Dictionary) -> String:
	var content: Dictionary=owner.session.game.data.advisor_memory_content.ui
	var year: int=int(calendar.get("year",0))
	var year_text: String=String(content.year_bc if year<0 else content.year_ad).format({"year":absi(year)})
	return String(content.date).format({"season":content.get(String(calendar.get("season","")),""),"year":year_text})

func page() -> Dictionary:
	var reading: Dictionary=status()
	var result: Dictionary=reading.duplicate(true)
	result.selected=owner.session.council_agenda=="succession" and reading.get("key","")!="" and reading.get("key","")==owner.session.succession_key
	result.title=_text("title")
	result.sections=[]
	result.notice=""
	if not reading.get("available",false) or reading.get("blocked","")!="":return result
	var briefing: Dictionary=reading.briefing
	var calendar: Dictionary=briefing.resolved_season
	result.title=_text("ruler_title",{"name":briefing.ruler.name})
	var year: int=int(calendar.year)
	result.notice=_text("captured",{"season":_text(String(calendar.season)),"year":_text("year_bc" if year<0 else "year_ad",{"year":absi(year)}),
		"turn":int(calendar.turn),"captured_turn":int(briefing.captured_turn)})
	if int(briefing.captured_turn)!=int(owner.session.game.state.turn):result.notice+="\n"+_text("replay_note")
	if int(result.get("postponed_until",0))<=int(owner.session.game.state.turn):result.postponed_until=0
	var predecessors: Array=[_text("ruler_line",{"ruler":briefing.ruler.name,"previous":briefing.predecessor.get("name",_text("unknown_ruler"))})]
	result.sections.append({"title":_text("rulers"),"lines":predecessors})
	result.sections.append({"title":_text("treasury"),"lines":[_text("treasury_line",{"amount":int(briefing.treasury)})]})
	var wars: Array=[]
	for war in briefing.get("wars",[]):wars.append(_text("war_line",{"name":war.name,"source_ref":war.source_ref}))
	if wars.is_empty() and int(briefing.omitted.wars)==0:wars.append(_text("no_wars"))
	_omission(wars,briefing,"wars")
	result.sections.append({"title":_text("wars"),"lines":wars})
	var policies: Array=[]
	for tax in briefing.get("taxes",[]):policies.append(_text("tax_line",{"level":_text(String(tax.level)),"count":int(tax.count)}))
	result.sections.append({"title":_text("taxes"),"lines":policies})
	policies=[]
	for edict in briefing.get("edicts",[]):policies.append(_text("edict_line",{"city":edict.city,"name":edict.name,"turns":int(edict.turns_held)}))
	if briefing.get("edicts",[]).is_empty() and int(briefing.omitted.edicts)==0:policies.append(_text("no_edicts"))
	_omission(policies,briefing,"edicts")
	result.sections.append({"title":_text("edicts"),"lines":policies})
	var patron: Dictionary=briefing.get("patron",{})
	var patron_lines: Array=[]
	if patron.is_empty():patron_lines.append(_text("no_patron"))
	else:
		patron_lines.append(_text("patron_line",{"name":patron.name,"progress":int(patron.progress),"target":int(patron.target)}))
		if patron.get("completed",false):patron_lines.append(_text("patron_complete"))
	patron_lines.append(_text("patron_note"))
	result.sections.append({"title":_text("patron"),"lines":patron_lines})
	var records: Array=[]
	for item in briefing.get("history",[]):
		records.append(_text("history_line",{"date":item.date,"source_ref":item.source_ref,"summary":item.summary}))
	if records.is_empty():records.append(_text("no_history"))
	_omission(records,briefing,"history")
	records.append(_text("history_note"))
	result.sections.append({"title":_text("history"),"lines":records})
	return result

func _omission(lines: Array, briefing: Dictionary, group: String) -> void:
	var count: int=int(briefing.get("omitted",{}).get(group,0))
	if count>0:lines.append(_text("omitted",{"count":count,"kind":_text(group)}))
