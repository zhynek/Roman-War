extends RefCounted
## Independent persistence boundary. Never reads the reference bookmark or medieval saves.
static func write(path: String, state: Dictionary, rules) -> bool:
	if not rules.validate_state(state): return false
	var record := {"format":"yenikapi_seasons","version":1,"state":state}
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
	if not record.get("format") is String or not rules.whole(record.get("version"),1,1): return {}
	if record.format!="yenikapi_seasons": return {}
	if not rules.validate_state(record.get("state")): return {}
	return rules.canonical(record.state)
