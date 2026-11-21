extends SceneTree
## DEBUG TOOL (story 008 part 3). Drives real KartSims headless on a track with stacked roads and
## logs what each kart meets, to show that track objects act only on their own level:
##   [box]  item boxes a kart reaches with the game's rule (planar radius + ItemSet.box_height_tolerance)
##          and, for comparison, the ones the old planar-only rule would have given it
##   [pad]  boost pads that fire (KartSim.pad_boosted), with the kart's height and track_s
##   [sink] hazard sinks / falls (KartSim.sank), with the kind and height
## Runs: the lower road through the crossover, the bridge over it (and over water), the bank and
## the plateau, and a kart steered off the ledge's open edge into the water beside it.
## Usage: godot --headless --path . -s res://tools/level_probe.gd [-- --track=test_elevation]
## Observations only: always exits 0.

const DT: float = 1.0 / 60.0
## Seconds each scripted drive lasts.
const DRIVE_TIME: float = 9.0
## Meters ahead along the road the steering aims at.
const AIM_AHEAD: float = 10.0

var _track: TrackModel
var _items: ItemSet
var _stats: VehicleStats


func _initialize() -> void:
	var id: String = "test_elevation"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			id = a.substr("--track=".length())
	_track = TrackModel.new(TrackLibrary.load_track(id))
	_items = load("res://assets/data/items/item_set.tres")
	_stats = load("res://assets/data/vehicles/armored_cart.tres")
	print("track=%s boxes=%d pads=%d hazards=%d" % [id, _track.data.item_box_spots.size(), _track.pad_centers.size(), _track.hazard_polygons.size()])
	for i in _track.data.item_box_spots.size():
		var p: Vector2 = _track.item_box_position(i)
		print("box %d s=%.1f lat=%.1f pos=(%.1f, %.1f) h=%.2f" % [i, _track.data.item_box_spots[i].x, _track.data.item_box_spots[i].y, p.x, p.y, _track.item_box_height(i)])
	for i in _track.pad_centers.size():
		print("pad %d pos=(%.1f, %.1f) h=%.2f" % [i, _track.pad_centers[i].x, _track.pad_centers[i].y, _track.pad_heights[i]])
	for i in _track.hazard_polygons.size():
		print("hazard %d kind=%s surface=%.2f" % [i, _track.hazard_kinds[i], _track.hazard_heights[i]])
	_drive("lower_road_crossing", 1180.0, 0.0, 0.0, 0.0)
	_drive("lower_road_lat3", 1180.0, -3.0, 0.0, 0.0)
	_drive("bridge_over_lower_and_water", 1385.0, 0.0, 0.0, 0.0)
	_drive("bridge_lat_m3", 1385.0, -3.0, 0.0, 0.0)
	_drive("hill_climb_pad", 60.0, 0.0, 0.0, 0.0)
	_drive("bank", 360.0, 3.5, 0.0, 0.0)
	_drive("plateau_and_ramp", 455.0, 0.0, 0.0, 0.0)
	_drive("off_ledge_into_water", 465.0, 0.0, 1.0, 2.0)
	quit(0)


# Drives a kart from main-loop distance [param s0] at sideways offset [param lat] for DRIVE_TIME,
# aiming along the road at that offset; after [param veer_after] s it aims [param veer] (+1 normal
# side) off the road, to go over an open edge.
func _drive(label: String, s0: float, lat: float, veer: float, veer_after: float) -> void:
	var sim := KartSim.new(_stats)
	sim.reset_to(_track, s0, lat)
	var input := KartInput.new()
	input.throttle = 1.0
	var events: PackedStringArray = PackedStringArray()
	var level_boxes: Dictionary = {}
	var planar_boxes: Dictionary = {}
	sim.pad_boosted.connect(func() -> void:
		events.append("[pad] t=%.2f s=%.1f h=%.2f" % [_t, sim.track_s, sim.height]))
	sim.sank.connect(func() -> void:
		events.append("[sink] t=%.2f kind=%s s=%.1f h=%.2f pos=(%.1f, %.1f)" % [_t, sim.hazard_kind, sim.track_s, sim.height, sim.position.x, sim.position.y]))
	sim.respawned.connect(func() -> void:
		events.append("[respawn] t=%.2f s=%.1f h=%.2f" % [_t, sim.track_s, sim.height]))
	var r2: float = _items.box_pickup_radius * _items.box_pickup_radius
	var pad_near: PackedFloat32Array = PackedFloat32Array()
	pad_near.resize(_track.pad_centers.size())
	pad_near.fill(INF)
	var min_h: float = INF
	var max_h: float = -INF
	_t = 0.0
	while _t < DRIVE_TIME:
		var aim_s: float = sim.track_s + AIM_AHEAD
		var off: float = lat + (veer * 40.0 if _t >= veer_after and veer != 0.0 else 0.0)
		var aim: Vector2 = _track.point_at(aim_s) + _track.normal_at(aim_s) * off
		var d: Vector2 = aim - sim.position
		var want: float = atan2(-d.x, -d.y)
		input.steer = clampf(wrapf(want - sim.yaw, -PI, PI) * 2.0, -1.0, 1.0)
		sim.tick(DT, input, _track)
		_t += DT
		if not sim.is_sinking():
			min_h = minf(min_h, sim.height)
			max_h = maxf(max_h, sim.height)
		for i in _track.pad_centers.size():
			pad_near[i] = minf(pad_near[i], _track.pad_centers[i].distance_to(sim.position))
		for i in _track.data.item_box_spots.size():
			var bp: Vector2 = _track.item_box_position(i)
			if bp.distance_squared_to(sim.position) > r2:
				continue
			if not planar_boxes.has(i):
				planar_boxes[i] = "%d(s=%.0f h=%.1f)" % [i, sim.track_s, sim.height]
			if absf(sim.height - _track.item_box_height(i)) <= _items.box_height_tolerance and not level_boxes.has(i):
				level_boxes[i] = "%d(s=%.0f h=%.1f)" % [i, sim.track_s, sim.height]
	print("== %s: from s=%.1f lat=%.1f -> s=%.1f, height %.2f..%.2f, falls=%d respawns=%d" % [label, s0, lat, sim.track_s, min_h, max_h, sim.fall_count, sim.respawn_count])
	print("   [box] taken (level rule): %s" % (", ".join(PackedStringArray(level_boxes.values())) if not level_boxes.is_empty() else "none"))
	print("   [box] planar-only rule would take: %s" % (", ".join(PackedStringArray(planar_boxes.values())) if not planar_boxes.is_empty() else "none"))
	var near: PackedStringArray = PackedStringArray()
	for i in pad_near.size():
		if pad_near[i] < 6.0:
			near.append("pad %d %.2f m" % [i, pad_near[i]])
	print("   closest pad centres: %s" % (", ".join(near) if not near.is_empty() else "none within 6 m"))
	for e in events:
		print("   " + e)
	if events.is_empty():
		print("   no pad, no sink")


var _t: float = 0.0
