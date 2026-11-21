extends SceneTree
## DEBUG TOOL (story 011 part 1). Drives the autopilot on a track with no window and no real time,
## and prints "[surface]" lines like the game's autopilot harness: for every change of surface and
## every PRINT_EVERY seconds on one, the kind, the cap in force, the speed, boost time and drift.
## Usage: godot --headless --path . -s res://tools/surface_probe.gd -- [--track=test_surfaces]
##        [--seconds=40] [--lane=S0:S1:LAT] [--cut=S0:S1] [--boost=S:SECONDS] [--drift-at=S0:S1]
##        [--vehicle=armored_cart] [--start=S]
## --drift-at holds the drift button with full steer (right) between S0 and S1 (to see a surface end it).
## --start puts the kart at main-loop distance S at 0.8 of its top speed (skips the first straight).

const TICK: float = 1.0 / 60.0
const PRINT_EVERY: float = 0.25
## Share of top speed the kart starts with when --start is given (probe setup, not game tuning).
const START_SPEED_FRAC: float = 0.8


func _initialize() -> void:
	var track_id: String = "test_surfaces"
	var seconds: float = 40.0
	var lane := Vector3(0.0, -1.0, 0.0)
	var cut := Vector2(0.0, -1.0)
	var boost := Vector2(-1.0, 0.0)
	var drift_at := Vector2(0.0, -1.0)
	var vehicle: String = "armored_cart"
	var start: float = NAN
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			track_id = a.substr(8)
		elif a.begins_with("--seconds="):
			seconds = a.substr(10).to_float()
		elif a.begins_with("--lane="):
			var p: PackedStringArray = a.substr(7).split(":")
			lane = Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
		elif a.begins_with("--cut="):
			var p2: PackedStringArray = a.substr(6).split(":")
			cut = Vector2(p2[0].to_float(), p2[1].to_float())
		elif a.begins_with("--boost="):
			var p3: PackedStringArray = a.substr(8).split(":")
			boost = Vector2(p3[0].to_float(), p3[1].to_float())
		elif a.begins_with("--drift-at="):
			var p4: PackedStringArray = a.substr(11).split(":")
			drift_at = Vector2(p4[0].to_float(), p4[1].to_float())
		elif a.begins_with("--vehicle="):
			vehicle = a.substr(10)
		elif a.begins_with("--start="):
			start = a.substr(8).to_float()
	var data: TrackData = TrackLibrary.load_track(track_id)
	var stats: VehicleStats = load("res://assets/data/vehicles/%s.tres" % vehicle) as VehicleStats
	if data == null or stats == null:
		printerr("bad track or vehicle")
		quit(1)
		return
	var track := TrackModel.new(data)
	var sim := KartSim.new(stats)
	sim.reset_to(track, start if not is_nan(start) else -data.start_distance_behind_line, 0.0)
	if not is_nan(start):
		sim.speed = stats.max_speed * START_SPEED_FRAC
		sim.velocity = sim.forward() * sim.speed
	var ap := AutopilotDriver.new()
	ap.lane_window = lane
	ap.cut_window = cut
	ap.boost_at = boost
	var input := KartInput.new()
	var t: float = 0.0
	var last: StringName = &"-"
	var since: float = 0.0
	var max_speed_seen: float = 0.0
	var go_time: float = stats.start_countdown_time if is_nan(start) else 0.0
	while t < seconds:
		ap.time_to_go = maxf(go_time - t, 0.0)
		input.clear()
		if t < go_time and is_nan(start):
			input.throttle = 0.0
		else:
			ap.drive(input, sim, track, TICK)
		if drift_at.y >= drift_at.x and sim.track_s >= drift_at.x and sim.track_s <= drift_at.y:
			input.drift = true
			input.steer = 1.0
		sim.tick(TICK, input, track)
		t += TICK
		since += TICK
		max_speed_seen = maxf(max_speed_seen, sim.speed)
		var kind: StringName = sim.surface_effect.kind if sim.surface_effect != null else &"none"
		if kind != last or (kind != &"none" and since >= PRINT_EVERY):
			last = kind
			since = 0.0
			print("[surface] t=%.2f kind=%s zone=%s cap=%s speed=%.1f boost=%.2f drift=%d s=%.1f lat=%.1f grip_mult=%.2f sunk=%d" % [
					t, kind, "on" if sim.surface != null else "tail",
					("%.1f" % sim.surface_cap) if sim.surface_cap < INF else "none", sim.speed, sim.boost_time,
					1 if sim.drifting else 0, sim.track_s, sim.lateral,
					sim.surface_effect.grip_mult if sim.surface_effect != null else 1.0, sim.respawn_count])
	print("[probe] done t=%.1f s=%.1f max_speed=%.1f respawns=%d surface_drift_ends=%d" % [t, sim.track_s, max_speed_seen,
			sim.respawn_count, sim.surface_drift_ends])
	quit(0)
