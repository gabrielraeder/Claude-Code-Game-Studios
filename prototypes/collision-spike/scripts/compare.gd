## PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Cross-checks dumped bench results.
## Run: godot --headless --path . -s res://scripts/compare.gd -- ref=face_into_50k other=grid_c2.0_50k
extends SceneTree

const Y_TOL: float = 0.01

func _load(tag: String) -> Dictionary:
	var f := FileAccess.open("res://out/res_%s.bin" % tag, FileAccess.READ)
	var n: int = f.get_32()
	var d := {}
	d.surf = f.get_buffer(n * 4).to_int32_array()
	d.y = f.get_buffer(n * 4).to_float32_array()
	var m: int = f.get_32()
	d.wh = f.get_buffer(m)
	d.wnx = f.get_buffer(m * 4).to_float32_array()
	return d

func _initialize() -> void:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1]
	var r: Dictionary = _load(args.ref)
	var o: Dictionary = _load(args.other)
	var surf_diff: int = 0
	var y_diff: int = 0
	var max_dy: float = 0.0
	for i: int in r.surf.size():
		if r.surf[i] != o.surf[i]:
			surf_diff += 1
		elif r.surf[i] >= 0:
			var dy: float = absf(r.y[i] - o.y[i])
			max_dy = maxf(max_dy, dy)
			if dy > Y_TOL:
				y_diff += 1
	var w_only_ref: int = 0
	var w_only_other: int = 0
	var w_both: int = 0
	var nx_sign_diff: int = 0
	for i: int in r.wh.size():
		if r.wh[i] == 1 and o.wh[i] == 1:
			w_both += 1
			if signf(r.wnx[i]) != signf(o.wnx[i]):
				nx_sign_diff += 1
		elif r.wh[i] == 1:
			w_only_ref += 1
		elif o.wh[i] == 1:
			w_only_other += 1
	print("COMPARE %s vs %s: rays=%d surface mismatches=%d, y mismatches(>%.2f m)=%d, max |dy| on agreeing hits=%.5f m | walls: both=%d only_ref=%d only_other=%d normal.x sign diff=%d" % [args.ref, args.other, r.surf.size(), surf_diff, Y_TOL, y_diff, max_dy, w_both, w_only_ref, w_only_other, nx_sign_diff])
	quit()
