extends RefCounted

func test_runner_uses_an_isolated_directory(t) -> void:
	var directory := OS.get_user_data_dir()
	t.check(directory.contains("Roman War Tests/"), "the test runner isolates every user:// path")
	t.check(not directory.ends_with("app_userdata/Roman War"), "automated saves never address the normal campaign slot")
	t.check(DirAccess.dir_exists_absolute(directory), "the isolated directory exists before UI saves")
