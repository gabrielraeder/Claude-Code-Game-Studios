@tool
extends RefCounted
## The one shared GDScript source-hash check for the native core (ADR-0007 section 7, "The
## editor-panel gap is closed"). It names no native type: a native-typed script cannot parse when
## the extension is missing, and this check must still report that.
##
## Callers: src/core/native_boot_check.gd (boot), addons/dogworks_core/plugin.gd (editor start) and
## tests/unit/native/native_test_guard.gd (before() of every native test suite).
## Not loaded in exports: exports carry no native/ sources, so [method problem] returns "" there.
##
## It must agree with tools/build_native.sh --hashes over the same list (native/hash_files.txt); a test
## (native_hash_parity_test.gd) compares the two. Both fail on an unknown line kind, a missing file,
## and a missing or empty tree, and both leave out files and directories whose name starts with '.'.

## The committed file-list definition; tools/build_native.sh reads the same file.
const LIST_PATH: String = "res://native/hash_files.txt"
## Exists while a bench DLL is swapped into the debug slot (ADR-0007 section 8).
const BENCH_LOCK_PATH: String = "res://addons/dogworks_core/bin/bench.lock"
## Named in every refusal.
const FIX: String = "run tools/build_native.sh"

## Microseconds the last [method compute] took (the UNVERIFIED 100 ms budget is recorded from this).
## 0 when the last compute failed.
static var last_compute_usec: int = 0
## Why the last [method hashed_paths] or [method compute] failed, or "" when it did not.
static var last_error: String = ""


## Hashed paths from the list definition, sorted in byte order (ASCII paths: code-point order is the same).
## Returns an empty array and sets [member last_error] on an unreadable list, an unknown line kind, a
## missing tree or a tree that holds no files. [param list_path] exists for tests.
static func hashed_paths(list_path: String = LIST_PATH) -> PackedStringArray:
	last_error = ""
	var file: FileAccess = FileAccess.open(list_path, FileAccess.READ)
	if file == null:
		last_error = "cannot read %s" % list_path
		return PackedStringArray()
	var paths: Array[String] = []
	var entries: int = 0
	for raw: String in file.get_as_text().split("\n"):
		var line: String = raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts: PackedStringArray = line.split(" ", false)
		if parts.size() != 2:
			last_error = "malformed line in %s: '%s'" % [list_path, line]
			return PackedStringArray()
		var path: String = parts[1].rstrip("/")
		if parts[0] == "file":
			if not FileAccess.file_exists("res://" + path):
				last_error = "listed file is missing: %s" % path
				return PackedStringArray()
			paths.append(path)
		elif parts[0] == "tree":
			var before: int = paths.size()
			if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://" + path)):
				last_error = "listed tree is missing: %s" % path
				return PackedStringArray()
			_walk(path, paths)
			if paths.size() == before:
				last_error = "tree holds no files: %s" % path
				return PackedStringArray()
		else:
			last_error = "unknown line kind '%s' in %s: '%s'" % [parts[0], list_path, line]
			return PackedStringArray()
		entries += 1
	if entries == 0:
		last_error = "%s lists nothing" % list_path
		return PackedStringArray()
	paths.sort()
	var out: PackedStringArray = PackedStringArray()
	for p: String in paths:
		if out.is_empty() or out[out.size() - 1] != p:
			out.append(p)
	return out


## Appends every file below [param dir_path], skipping names that start with '.' (files and directories).
static func _walk(dir_path: String, into: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open("res://" + dir_path)
	if dir == null:
		return
	dir.include_hidden = true
	for f: String in dir.get_files():
		if not f.begins_with("."):
			into.append(dir_path + "/" + f)
	for d: String in dir.get_directories():
		if not d.begins_with("."):
			_walk(dir_path + "/" + d, into)


## SH: sha256 over, per path, bytes(path) 0x00 bytes(lowercase hex sha256 of the file) 0x0A.
## Returns "" (and sets [member last_error]) when the list or a listed file cannot be read.
static func compute(list_path: String = LIST_PATH) -> String:
	last_compute_usec = 0
	var t0: int = Time.get_ticks_usec()
	var paths: PackedStringArray = hashed_paths(list_path)
	if paths.is_empty():
		return ""
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for p: String in paths:
		var file_hash: String = FileAccess.get_sha256("res://" + p)
		if file_hash.is_empty():
			last_error = "cannot hash %s" % p
			return ""
		var bytes: PackedByteArray = p.to_utf8_buffer()
		bytes.append(0)
		bytes.append_array(file_hash.to_utf8_buffer())
		bytes.append(10)
		ctx.update(bytes)
	var result: String = ctx.finish().hex_encode()
	last_compute_usec = Time.get_ticks_usec() - t0
	return result


## Calls static method [param method] of the native class [param anchor], after checking that the class has the
## method, and returns its result only when the result has type [param expected_type]. Returns null (and sets
## [member last_error]) otherwise, so a caller can refuse instead of crashing on a stale or odd DLL.
static func call_static_checked(anchor: StringName, method: StringName, expected_type: int) -> Variant:
	if not ClassDB.class_exists(anchor) or not ClassDB.class_has_method(anchor, method, true):
		last_error = "native class %s has no method %s" % [anchor, method]
		return null
	var value: Variant = ClassDB.class_call_static(anchor, method)
	if typeof(value) != expected_type:
		last_error = "%s.%s() returned type %d, expected %d" % [anchor, method, typeof(value), expected_type]
		return null
	return value


## "" when the loaded native build is fresh, otherwise a message that names tools/build_native.sh.
## [param native_source_hash] is `DogworksCore.source_hash()`, read by the caller through
## [method call_static_checked] so this script stays free of native types. Skipped (returns "") in a
## build without the editor feature, which ships no native/ sources.
static func problem(native_source_hash: String) -> String:
	if not OS.has_feature("editor"):
		return ""
	if FileAccess.file_exists(BENCH_LOCK_PATH):
		return "bench.lock exists: a bench DLL is in the debug slot; %s --restore" % FIX
	var want: String = compute()
	if want.is_empty():
		return "cannot compute the source hash (%s); %s" % [last_error, FIX]
	if want != native_source_hash:
		return "stale native DLL: sources hash %s but the loaded DLL says %s; %s" % [want, native_source_hash, FIX]
	return ""
