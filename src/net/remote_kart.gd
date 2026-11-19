class_name RemoteKart
extends KartSim
## A kart simulated on another PC. It is a KartSim whose fields are filled from interpolated
## network snapshots instead of a tick, so KartVisual and ChaseCamera bind to it unchanged.
## Position and heading are interpolated at (now - view delay); when the newest snapshot is
## older than that, the kart is extrapolated along its velocity, capped by NetConfig.

## Lap the owner reported (0 before the first line crossing).
var lap: int = 0
## True once the owner reported the race finished.
var finished: bool = false
## Owner's total race time when finished.
var finish_time: float = 0.0
## Race-clock time of the newest snapshot, -1 before the first.
var newest_time: float = -1.0

var _buffer: Array[Dictionary] = []
var _cfg: NetConfig
var _net_stats: NetStats
var _newest_s: float = 0.0
var _newest_speed: float = 0.0


func _init(vehicle_stats: VehicleStats, config: NetConfig, stats: NetStats) -> void:
	super(vehicle_stats)
	_cfg = config
	_net_stats = stats


## Drops all snapshots and forgets finish state (new race).
func clear_snapshots() -> void:
	_buffer.clear()
	newest_time = -1.0
	lap = 0
	finished = false
	finish_time = 0.0
	_newest_s = track_s
	_newest_speed = 0.0


## Adds a snapshot sent at race-clock [param t], received when our clock read [param now].
## Out-of-order or short arrays are ignored.
func push_snapshot(t: float, d: PackedFloat32Array, now: float) -> void:
	if d.size() < KartWire.FIELD_COUNT:
		return
	if not _buffer.is_empty():
		var last: Dictionary = _buffer.back()
		if t <= float(last.t):
			return
		var ld: PackedFloat32Array = last.d
		var predicted: Vector2 = Vector2(ld[KartWire.X], ld[KartWire.Z]) \
				+ Vector2(ld[KartWire.VX], ld[KartWire.VZ]) * (t - float(last.t))
		_net_stats.record_error(predicted.distance_to(Vector2(d[KartWire.X], d[KartWire.Z])))
	_net_stats.record_snapshot(now - t, _cfg)
	_buffer.append({"t": t, "d": d})
	if _buffer.size() > _cfg.snapshot_buffer_size:
		_buffer.pop_front()
	newest_time = t
	lap = int(d[KartWire.LAP])
	_newest_s = d[KartWire.TRACK_S]
	_newest_speed = d[KartWire.SPEED]
	finished = d[KartWire.FINISHED] > 0.5
	finish_time = d[KartWire.FINISH_TIME]


## Distance covered along the race (laps * length + position on the loop), projected from
## the newest snapshot to race-clock [param now] at its speed (capped extrapolation).
func projected_progress(now: float, track_length: float) -> float:
	var ahead: float = clampf(now - newest_time, 0.0, _cfg.max_extrapolation) if newest_time >= 0.0 else 0.0
	return float(lap - 1) * track_length + _newest_s + maxf(_newest_speed, 0.0) * ahead


## Moves the kart to where it should be drawn at race-clock [param now]. Call once per physics tick.
func update_view(now: float) -> void:
	_prev_position = position
	_prev_yaw = yaw
	if _buffer.is_empty():
		return
	var rt: float = now - _net_stats.view_delay
	var newest: Dictionary = _buffer.back()
	if rt >= float(newest.t):
		_net_stats.record_frame(true)
		var d: PackedFloat32Array = newest.d
		var ahead: float = minf(rt - float(newest.t), _cfg.max_extrapolation)
		velocity = Vector2(d[KartWire.VX], d[KartWire.VZ])
		position = Vector2(d[KartWire.X], d[KartWire.Z]) + velocity * ahead
		yaw = d[KartWire.YAW]
		_apply_fields(d)
		return
	_net_stats.record_frame(false)
	for i in range(_buffer.size() - 1, 0, -1):
		var a: Dictionary = _buffer[i - 1]
		var b: Dictionary = _buffer[i]
		if float(a.t) <= rt and rt <= float(b.t):
			var f: float = (rt - float(a.t)) / maxf(float(b.t) - float(a.t), 0.0001)
			var da: PackedFloat32Array = a.d
			var db: PackedFloat32Array = b.d
			position = Vector2(da[KartWire.X], da[KartWire.Z]).lerp(Vector2(db[KartWire.X], db[KartWire.Z]), f)
			velocity = Vector2(da[KartWire.VX], da[KartWire.VZ]).lerp(Vector2(db[KartWire.VX], db[KartWire.VZ]), f)
			yaw = lerp_angle(da[KartWire.YAW], db[KartWire.YAW], f)
			_apply_fields(da)
			return
	var oldest: PackedFloat32Array = _buffer[0].d
	position = Vector2(oldest[KartWire.X], oldest[KartWire.Z])
	yaw = oldest[KartWire.YAW]
	_apply_fields(oldest)


func _apply_fields(d: PackedFloat32Array) -> void:
	var now_drifting: bool = d[KartWire.DRIFTING] > 0.5
	var dir: int = int(d[KartWire.DRIFT_DIR])
	if now_drifting and not drifting:
		drift_started.emit(dir)
	drifting = now_drifting
	drift_dir = dir
	drift_tier = int(d[KartWire.DRIFT_TIER])
	speed = d[KartWire.SPEED]
	boost_time = d[KartWire.BOOST_TIME]
	spin_time = d[KartWire.SPIN_TIME]
	last_steer = d[KartWire.LAST_STEER]
	accel_long = d[KartWire.ACCEL_LONG]
	accel_lat = d[KartWire.ACCEL_LAT]
	track_s = d[KartWire.TRACK_S]
