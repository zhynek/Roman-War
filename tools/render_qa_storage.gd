extends RefCounted
## Godot 4.4 creates built-in shader cache directories before SceneTree._init.
## Changing user:// for a QA run must retain that directory skeleton: pending
## compiles still use user:// paths. Copy no cache contents or player saves.
static func configure(name: String) -> void:
	var cache_directories: Array[String]=[]
	_directories(ProjectSettings.globalize_path("user://shader_cache"),"",cache_directories)
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name",name)
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	var cache:=OS.get_user_data_dir().path_join("shader_cache")
	DirAccess.make_dir_recursive_absolute(cache)
	for directory in cache_directories:
		DirAccess.make_dir_recursive_absolute(cache.path_join(directory))

static func _directories(base: String,relative: String,result: Array[String]) -> void:
	var directory:=DirAccess.open(base.path_join(relative))
	if directory==null:return
	for child in directory.get_directories():
		var path:=relative.path_join(child)
		result.append(path)
		_directories(base,path,result)
