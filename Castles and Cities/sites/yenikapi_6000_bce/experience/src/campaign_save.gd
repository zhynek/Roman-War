extends RefCounted
## Independent persistence boundary. Never reads the reference bookmark or medieval saves.
static func write(path: String, state: Dictionary, rules) -> bool:
	if not rules.validate_state(state): return false
	var record := {"format":"yenikapi_seasons","version":5 if rules.land.active(state) else 4 if rules.assets.active(state) else (3 if rules.households.active(state) else (2 if rules.neighbors.active(state) else 1)),"state":state}
	var temporary: String = path+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(record,"  "))
	file.flush()
	var error: int = file.get_error()
	file.close()
	if error != OK: return false
	if read(temporary,rules).is_empty(): return false
	return DirAccess.rename_absolute(temporary,path)==OK

static func read(path: String, rules) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>4194304: return {}
	var record: Variant = JSON.parse_string(file.get_as_text())
	if not record is Dictionary: return {}
	if not record.get("format") is String or not rules.whole(record.get("version"),1,5): return {}
	if record.format!="yenikapi_seasons": return {}
	if not record.get("state") is Dictionary: return {}
	rules.ensure_state_keys(record.state)
	if not rules.validate_state(record.state): return {}
	var expected: int = 5 if rules.land.active(record.state) else 4 if rules.assets.active(record.state) else (3 if rules.households.active(record.state) else (2 if rules.neighbors.active(record.state) else 1))
	if record.version != expected: return {}
	return rules.canonical(record.state)
