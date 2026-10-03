class_name CityBattleHost
extends RefCounted
## Runtime scheduling boundary, deliberately outside src/core and the scene tree.
## The worker serializes input commands and fixed simulation ticks under one lock.
## UI frames only poll a detached snapshot. Closing, saving and leaving join/pause
## the worker before the city/campaign is allowed to read the shared Game again.
var _game: Game
var _region: String
var _thread := Thread.new()
var _mutex := Mutex.new()
var _stop := false
var _snapshot: Dictionary = {}

func attach(game: Game, region: String) -> void:
	_game=game
	_region=region
	_snapshot=_game.city_battle_status(_region)

func run() -> void:
	if _thread.is_started():return
	_stop=false
	_thread.start(_work)

func _work() -> void:
	var next := Time.get_ticks_msec()
	while true:
		_mutex.lock()
		if _stop:
			_mutex.unlock()
			break
		var battle: Dictionary = _game.state.get("city_battles",{}).get(_region,{})
		var running: bool = battle.get("phase","")=="fighting" and not battle.get("paused",true)
		var now := Time.get_ticks_msec()
		if running and now>=next:
			var result := _game.city_battle_step(_region)
			if not result.get("ok",false):
				battle["paused"]=true
			_snapshot=_game.city_battle_status(_region)
			# Never burst through a backlog after suspension or a slow frame.
			next=now+maxi(1,int(CityBattleSim.rules(_game.data)["tick_ms"])/int(battle.get("speed",1)))
		elif not running:
			next=now
		_mutex.unlock()
		OS.delay_msec(4)

func snapshot() -> Dictionary:
	_mutex.lock()
	if not _thread.is_started(): _snapshot=_game.city_battle_status(_region)
	var result := _snapshot.duplicate(true)
	_mutex.unlock()
	return result

func invoke(action: String, args: Array = []) -> Dictionary:
	_mutex.lock()
	var result: Dictionary
	match action:
		"begin": result=_game.city_battle_begin(_region,bool(args[0]))
		"drill": result=_game.city_battle_drill(_region)
		"start": result=_game.city_battle_start(_region)
		"control": result=_game.city_battle_control(_region,String(args[0]))
		"order": result=_game.city_battle_command(_region,args[0],String(args[1]),args[2],String(args[3]))
		"node": result=_game.city_battle_order(_region,String(args[0]),String(args[1]))
		"close": result=_game.city_battle_close(_region)
		"save":
			var battle: Dictionary = _game.state.get("city_battles",{}).get(_region,{})
			if battle.has("paused"):battle["paused"]=true
			result={"ok":_game.save_to(String(args[0]))}
		_: result={"ok":false,"reason":"invalid_order"}
	_snapshot=_game.city_battle_status(_region)
	_mutex.unlock()
	return result

func stop() -> void:
	if _game==null:return
	_mutex.lock()
	_stop=true
	var battle: Dictionary = _game.state.get("city_battles",{}).get(_region,{})
	if battle.has("paused"):battle["paused"]=true
	_snapshot=_game.city_battle_status(_region)
	_mutex.unlock()
	if _thread.is_started():_thread.wait_to_finish()
