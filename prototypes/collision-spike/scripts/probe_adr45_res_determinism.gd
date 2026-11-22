## PROTOTYPE - NOT FOR PRODUCTION. ADR-0004/0005: is a freshly built package byte-identical across processes?
## Run twice: -s res://scripts/probe_adr45_res_determinism.gd -- run=1   (then run=2), then -- compare
extends SceneTree

const OUT_TXT: String = "res://out/probe_adr45_res_determinism.txt"

func _initialize() -> void:
	var run: String = ""
	var compare: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("run="):
			run = a.substr(4)
		if a == "compare":
			compare = true
	if compare:
		var lines: PackedStringArray = []
		for variant: String in ["random_ids", "fixed_ids"]:
			var b1: PackedByteArray = FileAccess.get_file_as_bytes("res://out/probe_adr45_det_%s_1.res" % variant)
			var b2: PackedByteArray = FileAccess.get_file_as_bytes("res://out/probe_adr45_det_%s_2.res" % variant)
			var ndiff: int = 0
			for i: int in mini(b1.size(), b2.size()):
				if b1[i] != b2[i]:
					ndiff += 1
			var s: String = "%s: run1 size=%d run2 size=%d identical=%s differing_bytes=%d sha1=%s sha2=%s" % [variant, b1.size(), b2.size(), b1 == b2, ndiff,
				FileAccess.get_sha256("res://out/probe_adr45_det_%s_1.res" % variant), FileAccess.get_sha256("res://out/probe_adr45_det_%s_2.res" % variant)]
			lines.append(s)
			print(s)
		var r1: Adr45Course = ResourceLoader.load("res://out/probe_adr45_det_random_ids_1.res", "", ResourceLoader.CACHE_MODE_IGNORE)
		var r2: Adr45Course = ResourceLoader.load("res://out/probe_adr45_det_random_ids_2.res", "", ResourceLoader.CACHE_MODE_IGNORE)
		var arrays_eq: bool = r1.gate_xform == r2.gate_xform and r1.routes[0].pos == r2.routes[0].pos and r1.routes[1].half_left == r2.routes[1].half_left
		var s2: String = "random_ids: loaded arrays equal across runs=%s; sub-resource ids run1=%s,%s run2=%s,%s" % [arrays_eq, r1.routes[0].resource_scene_unique_id, r1.routes[1].resource_scene_unique_id, r2.routes[0].resource_scene_unique_id, r2.routes[1].resource_scene_unique_id]
		lines.append(s2)
		print(s2)
		var f := FileAccess.open(OUT_TXT, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
		quit(0)
		return
	var c: Adr45Course = Adr45Course.make_fixture()
	ResourceSaver.save(c, "res://out/probe_adr45_det_random_ids_%s.res" % run)
	var d: Adr45Course = Adr45Course.make_fixture()
	for k: int in d.routes.size():
		d.routes[k].resource_scene_unique_id = "route_%d" % k
	d.resource_scene_unique_id = "course"
	ResourceSaver.save(d, "res://out/probe_adr45_det_fixed_ids_%s.res" % run)
	print("saved run ", run)
	quit(0)
