## PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Prints triangle counts for track presets.
extends SceneTree

const TrackGen := preload("res://scripts/track_gen.gd")
const PRESETS: Array = [[1.0, 10, 4], [0.5, 14, 8], [1.0, 14, 6], [0.6, 14, 6]]

func _initialize() -> void:
	for p: Array in PRESETS:
		var t0: int = Time.get_ticks_usec()
		var tg: TrackGen = TrackGen.new()
		tg.build(p[0], p[1], p[2])
		var dt: float = (Time.get_ticks_usec() - t0) / 1000.0
		var aabb := AABB(tg.ground_faces[0], Vector3.ZERO)
		for v: Vector3 in tg.ground_faces:
			aabb = aabb.expand(v)
		var hist := PackedInt32Array()
		hist.resize(TrackGen.SURF_COUNT)
		for sid: int in tg.ground_surf:
			hist[sid] += 1
		print("preset %s: segs=%d ground=%d wall=%d total=%d build=%.0f ms aabb=%s surf_hist=%s" % [str(p), tg.seg_count, tg.ground_tri_count(), tg.wall_tri_count(), tg.ground_tri_count() + tg.wall_tri_count(), dt, aabb, hist])
	quit()
