extends GdUnitTestSuite
## Core-rebuild story 066: the GDScript source hash and the bash source hash agree over the real list, the
## shared helper refuses a bad list the way tools/build_native.sh does, and the test guard refuses a stale
## hash. (ADR-0007 section 7: one list, one order, bytes.) This suite names no native class, so it is not
## subject to the native-suite guard rule; it still runs the guard in before() so it fails on a stale build.
##
## The parity test starts Git's bash.exe with tools/build_native.sh --hashes through OS.execute. It fails, not skips,
## when bash cannot run.

const _GUARD = preload("res://tests/unit/native/native_test_guard.gd")
const _SOURCE_HASH = preload("res://addons/dogworks_core/source_hash.gd")

## Fixture lists live under user:// and are written by each test.
const FIXTURE_DIR: String = "user://native_hash_fixture"


func before() -> void:
	assert_str(_GUARD.problem()).is_empty()


## Writes a fixture list and returns its path.
func _list(name: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(FIXTURE_DIR)
	var path: String = FIXTURE_DIR + "/" + name
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


## Git's bash.exe. A bare "bash" resolves to WSL's bash in C:/Windows/System32 when Godot starts it, so the
## path is explicit; DOG_BASH overrides it.
func _git_bash() -> String:
	var candidates: Array[String] = [OS.get_environment("DOG_BASH"), "C:/Program Files/Git/usr/bin/bash.exe", "C:/Program Files (x86)/Git/usr/bin/bash.exe"]
	for c: String in candidates:
		if not c.is_empty() and FileAccess.file_exists(c):
			return c
	return ""


func test_gdscript_source_hash_equals_build_native_sh_hashes_over_the_real_list() -> void:
	var bash: String = _git_bash()
	assert_str(bash).override_failure_message("Git bash.exe not found; set DOG_BASH").is_not_empty()
	var output: Array = []
	var script: String = ProjectSettings.globalize_path("res://tools/build_native.sh")
	var code: int = OS.execute(bash, [script, "--hashes"], output, true)
	assert_int(code).override_failure_message("build_native.sh --hashes failed: " + str(output)).is_equal(0)
	var first_line: String = str(output[0]).split("
")[0].strip_edges()
	assert_str(first_line).is_equal("SH " + _SOURCE_HASH.compute())


func test_hashed_paths_are_sorted_and_have_no_dot_names() -> void:
	var paths: PackedStringArray = _SOURCE_HASH.hashed_paths()
	assert_bool(paths.size() > 5).is_true()
	var sorted: Array = Array(paths)
	sorted.sort()
	assert_array(Array(paths)).is_equal(sorted)
	for p: String in paths:
		assert_bool(p.get_file().begins_with(".")).is_false()


func test_unknown_line_kind_is_refused() -> void:
	var path: String = _list("unknown_kind.txt", "bogus native/SConstruct\n")
	assert_int(_SOURCE_HASH.hashed_paths(path).size()).is_equal(0)
	assert_str(_SOURCE_HASH.last_error).contains("unknown line kind")
	assert_str(_SOURCE_HASH.compute(path)).is_empty()


func test_missing_listed_file_is_refused() -> void:
	var path: String = _list("missing_file.txt", "file native/does_not_exist.txt\n")
	assert_int(_SOURCE_HASH.hashed_paths(path).size()).is_equal(0)
	assert_str(_SOURCE_HASH.last_error).contains("listed file is missing")


func test_missing_tree_is_refused() -> void:
	var path: String = _list("missing_tree.txt", "tree native/no_such_dir\n")
	assert_int(_SOURCE_HASH.hashed_paths(path).size()).is_equal(0)
	assert_str(_SOURCE_HASH.last_error).contains("listed tree is missing")


func test_empty_list_is_refused() -> void:
	var path: String = _list("empty.txt", "# nothing listed\n")
	assert_int(_SOURCE_HASH.hashed_paths(path).size()).is_equal(0)
	assert_str(_SOURCE_HASH.last_error).contains("lists nothing")


func test_failed_compute_resets_last_compute_usec() -> void:
	assert_str(_SOURCE_HASH.compute()).is_not_empty()
	assert_bool(_SOURCE_HASH.last_compute_usec > 0).is_true()
	var path: String = _list("bad_after_good.txt", "bogus x\n")
	assert_str(_SOURCE_HASH.compute(path)).is_empty()
	assert_int(_SOURCE_HASH.last_compute_usec).is_equal(0)


func test_guard_refuses_a_stale_hash_and_names_the_build_script() -> void:
	var stale: String = "0".repeat(64)
	var problem: String = _GUARD.problem(stale)
	assert_str(problem).contains("stale native DLL")
	assert_str(problem).contains("tools/build_native.sh")


func test_guard_accepts_the_real_build() -> void:
	assert_str(_GUARD.problem()).is_empty()


func test_call_static_checked_refuses_a_missing_method_and_a_wrong_type() -> void:
	assert_object(_SOURCE_HASH.call_static_checked(&"Node", &"no_such_static", TYPE_INT)).is_null()
	assert_str(_SOURCE_HASH.last_error).contains("has no method")
