## PROTOTYPE - NOT FOR PRODUCTION. ADR-0004 Verification Required (1)(2) + ADR-0005 NV-13.
## Saves a CourseData stand-in as binary .res, reloads it uncached, compares field by field,
## checks typing, save determinism, ResourceLoader caching and FileAccess.get_sha256 on res://.
## Run: godot --headless --path prototypes/collision-spike -s res://scripts/probe_adr45_res_roundtrip.gd
extends SceneTree

const OUT_TXT: String = "res://out/probe_adr45_res_roundtrip.txt"
const RES_A: String = "res://out/probe_adr45_course_a.res"
const RES_B: String = "res://out/probe_adr45_course_b.res"
var lines: PackedStringArray = []

func _p(s: String) -> void:
	lines.append(s)
	print(s)

func _check(name: String, ok: bool, detail: String = "") -> void:
	_p("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])

func _initialize() -> void:
	_p("engine " + Engine.get_version_info().string)
	_p("OS.has_feature(editor)=%s (editor binary, -s run)" % OS.has_feature("editor"))
	var c: Adr45Course = Adr45Course.make_fixture()
	var e1: Error = ResourceSaver.save(c, RES_A)
	var e2: Error = ResourceSaver.save(c, RES_B)
	_check("save", e1 == OK and e2 == OK, "errs=%d,%d" % [e1, e2])
	var ba: PackedByteArray = FileAccess.get_file_as_bytes(RES_A)
	var bb: PackedByteArray = FileAccess.get_file_as_bytes(RES_B)
	_check("two saves byte-equal", ba == bb, "size=%d" % ba.size())
	# sha256 (NV-13)
	var sha_res: String = FileAccess.get_sha256(RES_A)
	var sha_abs: String = FileAccess.get_sha256(ProjectSettings.globalize_path(RES_A))
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(ba)
	var sha_ctx: String = hc.finish().hex_encode()
	_check("NV-13 get_sha256(res://) == HashingContext", sha_res == sha_ctx and sha_res.length() == 64, sha_res)
	_check("NV-13 get_sha256(res://) == get_sha256(absolute)", sha_res == sha_abs)
	_check("NV-13 get_sha256(missing) is empty", FileAccess.get_sha256("res://out/nope.bin") == "")
	# reload, ignoring the cache
	var r: Resource = ResourceLoader.load(RES_A, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check("reload class", r is Adr45Course, "script=%s" % (r.get_script().resource_path if r and r.get_script() else "?"))
	var l: Adr45Course = r as Adr45Course
	_check("format_version/lap_length", l.format_version == c.format_version and l.lap_length == c.lap_length, "lap_length=%.6f" % l.lap_length)
	_check("gate_xform typed builtin", l.gate_xform.is_typed() and l.gate_xform.get_typed_builtin() == TYPE_TRANSFORM3D, "typed=%s builtin=%d" % [l.gate_xform.is_typed(), l.gate_xform.get_typed_builtin()])
	var xf_eq: bool = l.gate_xform.size() == c.gate_xform.size()
	for i: int in mini(l.gate_xform.size(), c.gate_xform.size()):
		xf_eq = xf_eq and l.gate_xform[i] == c.gate_xform[i]
	_check("gate_xform exact (==, not approx)", xf_eq, "n=%d first=%s" % [l.gate_xform.size(), l.gate_xform[0] if l.gate_xform.size() > 0 else "-"])
	_check("gate_half/group/s exact", l.gate_half == c.gate_half and l.gate_group == c.gate_group and l.gate_s == c.gate_s)
	_check("routes typed (script)", l.routes.is_typed() and l.routes.get_typed_builtin() == TYPE_OBJECT and l.routes.get_typed_script() == Adr45Route, "class_name=%s script=%s" % [l.routes.get_typed_class_name(), l.routes.get_typed_script()])
	var r_eq: bool = l.routes.size() == 2
	for k: int in mini(l.routes.size(), 2):
		var a: Adr45Route = c.routes[k]
		var b: Adr45Route = l.routes[k]
		r_eq = r_eq and b is Adr45Route and a.id == b.id and typeof(b.id) == TYPE_STRING_NAME and a.kind == b.kind and a.closed == b.closed and a.length == b.length and a.pos == b.pos and a.half_left == b.half_left and a.edge_flags == b.edge_flags
		_p("  route %d id=%s(%s) kind=%s pos.size=%d resource_path='%s'" % [k, b.id, type_string(typeof(b.id)), b.kind, b.pos.size(), b.resource_path])
	_check("routes exact (embedded sub-resources)", r_eq)
	_check("instance methods on loaded data", l.gate_count() == 8 and is_equal_approx(l.route_half_sum(), c.route_half_sum()), "half_sum=%f" % l.route_half_sum())
	_check("stats dictionary", l.stats == c.stats, str(l.stats))
	_p("INFO plain (non-@export) var after reload = %d (fixture set 42; 0 means not stored)" % l.plain_not_exported)
	# re-save of the loaded copy gives the same bytes
	var e3: Error = ResourceSaver.save(l, RES_B)
	_check("re-save of loaded copy byte-equal to first save", e3 == OK and FileAccess.get_file_as_bytes(RES_B) == ba)
	# caching (ADR-0004 V(2))
	var c1: Resource = load(RES_A)
	var c2: Resource = load(RES_A)
	var c3: Resource = ResourceLoader.load(RES_A)
	_check("load() twice returns the same cached instance", c1 == c2 and c2 == c3, "ids=%d,%d,%d" % [c1.get_instance_id(), c2.get_instance_id(), c3.get_instance_id()])
	_check("uncached load is a different instance", r != c1)
	# a mirrored() built from new arrays leaves the cached instance untouched
	var cached: Adr45Course = c1 as Adr45Course
	var before0: Vector3 = cached.routes[0].pos[0]
	var m := Adr45Course.new()
	for t: Transform3D in cached.gate_xform:
		m.gate_xform.append(t)
	m.gate_xform[0].origin.x = -m.gate_xform[0].origin.x
	var shallow: Adr45Course = cached.duplicate(false) as Adr45Course
	var shared_sub: bool = shallow.routes[0] == cached.routes[0]
	var deep: Adr45Course = cached.duplicate(true) as Adr45Course
	var deep_sub_new: bool = deep.routes[0] != cached.routes[0]
	_check("new-array copy leaves cached gate_xform untouched", cached.gate_xform[0].origin.x == c.gate_xform[0].origin.x)
	_p("INFO duplicate(false) shares route sub-resources with the cached instance: %s" % shared_sub)
	_p("INFO duplicate(true) makes new route sub-resources: %s" % deep_sub_new)
	_check("cached route pos untouched", cached.routes[0].pos[0] == before0)
	var f := FileAccess.open(OUT_TXT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)
