extends RefCounted
## One worker, serialized commands and detached snapshots. Wall time only paces
## fixed simulation steps; quick mode never changes the authoritative rules.
const QUICK_BATCH_TICKS: int=16
const QUICK_BATCH_MSEC: int=12
var _thread:=Thread.new()
var _mutex:=Mutex.new()
var _stop: bool=false
var _battle: Dictionary={}
var _quick: bool=false
var _quick_started: int=0
var _quick_elapsed: int=0
var rules
func attach(r,b: Dictionary) -> void:rules=r;_battle=b.duplicate(true)
func run() -> void:
	if not _thread.is_started():_stop=false;_thread.start(_work)
func _work() -> void:
	var next: int=Time.get_ticks_msec()
	while true:
		_mutex.lock()
		if _stop:_mutex.unlock();break
		var now: int=Time.get_ticks_msec()
		if _quick:
			var count: int=0
			while _battle.phase=="fighting" and not _battle.paused and count<QUICK_BATCH_TICKS:
				rules.defense.step(_battle,rules);count+=1
				if Time.get_ticks_msec()-now>=QUICK_BATCH_MSEC:break
			if _battle.phase!="fighting" or _battle.paused:_end_quick()
			next=Time.get_ticks_msec()
		elif _battle.phase=="fighting" and not _battle.paused:
			if now>=next:
				rules.defense.step(_battle,rules)
				next=now+int(rules.defense.tuning.tick_ms)/int(_battle.speed)
		else:next=now
		var quick: bool=_quick
		_mutex.unlock()
		# Release the lock between bounded batches for pause, save and cancellation.
		OS.delay_msec(1 if quick else 4)
func _end_quick() -> void:
	if _quick:_quick_elapsed=Time.get_ticks_msec()-_quick_started
	_quick=false
func snapshot() -> Dictionary:
	_mutex.lock();var b: Dictionary=_battle.duplicate(true);_mutex.unlock();return b
func status() -> Dictionary:
	_mutex.lock()
	var info: Dictionary={"quick":_quick,"tick":_battle.tick,"phase":_battle.phase,"elapsed_ms":Time.get_ticks_msec()-_quick_started if _quick else _quick_elapsed,"limit":int(rules.defense.tuning.limit_ticks)}
	_mutex.unlock();return info
func invoke(a: Dictionary) -> String:
	_mutex.lock();_end_quick()
	var error: String=rules.defense.control(_battle,a,rules)
	_mutex.unlock();return error
func prepare_delegated() -> void:
	_mutex.lock();rules.defense.prepare_delegated(_battle,rules);_mutex.unlock()
func begin_quick() -> String:
	_mutex.lock()
	var error: String=rules.defense.control(_battle,{"kind":"defense_mode","mode":"delegated"},rules)
	if error.is_empty():
		if _battle.phase=="deployment":
			rules.defense.prepare_delegated(_battle,rules)
			error=rules.defense.control(_battle,{"kind":"defense_start"},rules)
		elif _battle.paused:error=rules.defense.control(_battle,{"kind":"defense_pause"},rules)
	if error.is_empty():_quick=true;_quick_started=Time.get_ticks_msec();_quick_elapsed=0
	_mutex.unlock();return error
func cancel_quick() -> void:pause()
func pause() -> void:
	_mutex.lock();_end_quick()
	if _battle.phase=="fighting" and not _battle.paused:rules.defense.control(_battle,{"kind":"defense_pause"},rules)
	_mutex.unlock()
func stop() -> void:
	_mutex.lock();_end_quick();_stop=true;_mutex.unlock()
	if _thread.is_started():_thread.wait_to_finish()
