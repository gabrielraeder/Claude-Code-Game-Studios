extends SceneTree
## DEBUG TOOL (story 008 part 2). Prints, for a track, the main-loop distance of every control
## point with its height, the ramps' lips, and a crossover probe: the road a height-aware query
## picks at each point where the main loop passes over itself, at both levels.
## Usage: godot --headless --path . -s res://tools/elevation_probe.gd -- <track_id>


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var id: String = args[0] if args.size() > 0 else "test_elevation"
	var data: TrackData = TrackLibrary.load_track(id)
	if data == null:
		printerr("unknown track ", id)
		quit(1)
		return
	var track := TrackModel.new(data)
	print("length=%.1f samples=%d" % [track.length, track.main.points.size()])
	var spc: int = data.samples_per_segment
	for i in data.control_points.size():
		var s: float = track.main.cumulative[i * spc]
		print("cp %d s=%.1f p=%s y=%.2f" % [i, s, str(data.control_points[i]), track.main.y[i * spc]])
	for i in track.ramp_lip_s.size():
		print("ramp %d from=%.1f lip_s=%.1f lip=%.2f" % [i, track.ramp_from[i], track.ramp_lip_s[i], track.ramp_lip[i]])
	# Crossover probe: main samples whose point is inside the corridor of a far part of the loop.
	var m: TrackModel.Path = track.main
	var found: int = 0
	for i in range(0, m.points.size(), 2):
		var p: Vector2 = m.points[i]
		var lo: TrackModel.Hit = m.nearest_filtered(p, -INF, m.y[i] - data.level_separation)
		if lo == null or lo.excess > 0.0:
			continue
		found += 1
		var q_up: TrackModel.Query = track.query(p, -1, m.y[i])
		var q_lo: TrackModel.Query = track.query(p, -1, m.height_at(lo.seg, lo.t))
		var q_none: TrackModel.Query = track.query(p, -1)
		if found % 3 == 1:
			print("cross s=%.1f upper_y=%.2f -> up(s=%.1f h=%.2f) low(s=%.1f h=%.2f) nohint(s=%.1f h=%.2f)" % [
					m.cumulative[i], m.y[i], q_up.s, q_up.height, q_lo.s, q_lo.height, q_none.s, q_none.height])
	print("crossover samples=%d" % found)
	quit(0)
