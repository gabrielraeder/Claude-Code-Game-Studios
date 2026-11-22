extends "res://tests/unit/race/race_suite_base.gd"
## Core-rebuild story 068, criteria "Double-buffered outputs", "Event pair and overflow", "Stage timers", "Caller contract"
## and "Heap flat" (ADR-0007 section 3 Outputs are double-buffered; Validation Criteria "Heap flat").

const _GUARD = preload("res://tests/unit/native/native_test_guard.gd")

## local, bot, remote
const ROLES: PackedInt32Array = [0, 1, 2]
## Heap growth allowed over 600 ticks, bytes. Story 067 measured +104 B per 600 ticks in an idle loop.
const HEAP_TOLERANCE: int = 2048

var _sims: Array[RaceSim] = []


func before() -> void:
	assert_str(_GUARD.problem()).is_empty()


func after_test() -> void:
	for sim: RaceSim in _sims:
		sim.dispose()
	_sims.clear()


func _make(capacity: int = 4) -> RaceSim:
	var sim: RaceSim = RaceSim.create(setup_for(ROLES, capacity))
	assert_object(sim).is_not_null()
	_sims.append(sim)
	return sim


func _tick(sim: RaceSim, tick: int, rows: PackedFloat32Array = PackedFloat32Array(), remote: PackedFloat32Array = PackedFloat32Array()) -> void:
	sim.begin_tick(tick)
	sim.apply_events(PackedInt32Array(), PackedFloat32Array())
	sim.step_drive(rows if rows.size() > 0 else driver_rows(1))
	sim.step_bodies()
	sim.set_remote(remote if remote.size() > 0 else remote_rows(1), 0)
	sim.step_contact()
	sim.step_progress_items_hazards()
	sim.end_tick()


## A tick that writes [param value] into the working progress buffer for slot 0, then ends.
func _tick_with_progress(sim: RaceSim, tick: int, value: float) -> void:
	sim.begin_tick(tick)
	sim.debug_write_progress(0, RaceLayout.PROG_DISTANCE, value)
	sim.apply_events(PackedInt32Array(), PackedFloat32Array())
	sim.step_drive(driver_rows(1))
	sim.step_bodies()
	sim.set_remote(remote_rows(1), 0)
	sim.step_contact()
	sim.step_progress_items_hazards()
	sim.end_tick()


func test_held_arrays_of_tick_n_are_intact_across_tick_n_plus_one() -> void:
	var sim: RaceSim = _make()
	_tick(sim, 0)
	var held_snaps: PackedFloat32Array = sim.snapshots()
	var held_copy: PackedFloat32Array = held_snaps.duplicate()
	var held_usec: PackedFloat64Array = sim.stage_usec()
	var held_usec_copy: PackedFloat64Array = held_usec.duplicate()
	_tick(sim, 1)
	_tick(sim, 2)
	assert_array(held_snaps).is_equal(held_copy)
	assert_array(held_usec).is_equal(held_usec_copy)
	assert_int(int(held_snaps[RaceLayout.SNAP_TICK])).is_equal(0)
	assert_int(int(sim.snapshots()[RaceLayout.SNAP_TICK])).is_equal(2)


func test_progress_alternates_between_buffers_and_a_held_copy_is_intact() -> void:
	var sim: RaceSim = _make()
	_tick_with_progress(sim, 0, 10.0)
	var held: PackedFloat32Array = sim.progress()
	assert_float(held[RaceLayout.PROG_DISTANCE]).is_equal(10.0)
	_tick_with_progress(sim, 1, 20.0)
	assert_float(sim.progress()[RaceLayout.PROG_DISTANCE]).is_equal(20.0)
	assert_float(held[RaceLayout.PROG_DISTANCE]).is_equal(10.0)
	# Tick 2 writes the buffer the held array still references: the holder keeps its data (one copy is paid).
	_tick_with_progress(sim, 2, 30.0)
	assert_float(held[RaceLayout.PROG_DISTANCE]).is_equal(10.0)
	assert_float(sim.progress()[RaceLayout.PROG_DISTANCE]).is_equal(30.0)
	assert_float(sim.progress_distance(0)).is_equal(30.0)


func test_consecutive_ticks_publish_different_buffers() -> void:
	var sim: RaceSim = _make()
	_tick(sim, 0)
	var a: PackedFloat32Array = sim.snapshots()
	_tick(sim, 1)
	var b: PackedFloat32Array = sim.snapshots()
	assert_int(int(a[RaceLayout.SNAP_TICK])).is_equal(0)
	assert_int(int(b[RaceLayout.SNAP_TICK])).is_equal(1)


func test_per_slot_accessors_match_the_whole_array() -> void:
	var sim: RaceSim = _make()
	sim.place(0, PackedFloat32Array([4, 5, 6, 0, 1, 0, -1, 0, 0, 0, 0, 1]))
	_tick(sim, 0)
	var snaps: PackedFloat32Array = sim.snapshots()
	var pos: Vector3 = sim.snapshot_position(0)
	assert_vector(pos).is_equal(Vector3(snaps[RaceLayout.SNAP_POS], snaps[RaceLayout.SNAP_POS + 1], snaps[RaceLayout.SNAP_POS + 2]))
	assert_vector(pos).is_equal(Vector3(4, 5, 6))
	var basis: Basis = sim.snapshot_basis(0)
	assert_vector(basis.x).is_equal(Vector3(0, 1, 0))
	assert_vector(basis.y).is_equal(Vector3(-1, 0, 0))
	assert_vector(sim.snapshot_velocity(0)).is_equal(Vector3.ZERO)
	assert_float(sim.snapshot_speed(0)).is_equal(0.0)
	assert_int(sim.progress_lap(0)).is_equal(0)
	assert_int(sim.progress_rank(0)).is_equal(0)


func test_accessors_refuse_a_slot_out_of_range() -> void:
	var sim: RaceSim = _make()
	await refuses(func() -> void: sim.snapshot_position(3), "slot out of range")
	await refuses(func() -> void: sim.snapshot_flags(-1), "slot out of range")
	await refuses(func() -> void: sim.progress_rank(3), "slot out of range")


func _emit(sim: RaceSim, slot: int, kind: int) -> bool:
	var payload: PackedFloat32Array = PackedFloat32Array()
	payload.resize(RaceLayout.payload_floats(kind))
	payload.fill(float(slot) + 0.5)
	return sim.debug_emit_event(slot, kind, payload)


func test_events_fill_a_pair_with_rows_and_payload_offsets() -> void:
	var sim: RaceSim = _make()
	sim.begin_tick(0)
	assert_bool(_emit(sim, 0, RaceLayout.EVENT_KIND_KNOCK)).is_true()
	assert_bool(_emit(sim, 1, RaceLayout.EVENT_KIND_PICKUP)).is_true()
	assert_bool(_emit(sim, 2, RaceLayout.EVENT_KIND_ITEM_HIT)).is_true()
	sim.apply_events(PackedInt32Array(), PackedFloat32Array())
	sim.step_drive(driver_rows(1))
	sim.step_bodies()
	sim.set_remote(remote_rows(1), 0)
	sim.step_contact()
	sim.step_progress_items_hazards()
	sim.end_tick()
	assert_int(sim.event_count()).is_equal(3)
	var heads: PackedInt32Array = sim.event_headers()
	var payload: PackedFloat32Array = sim.event_payload()
	var s: int = RaceLayout.EVENT_HEADER_STRIDE
	assert_array([heads[0], heads[1], heads[2]]).is_equal([0, RaceLayout.EVENT_KIND_KNOCK, 0])
	assert_array([heads[s], heads[s + 1], heads[s + 2]]).is_equal([1, RaceLayout.EVENT_KIND_PICKUP, RaceLayout.EVENT_PAYLOAD_KNOCK])
	assert_array([heads[2 * s], heads[2 * s + 1], heads[2 * s + 2]]).is_equal([2, RaceLayout.EVENT_KIND_ITEM_HIT, RaceLayout.EVENT_PAYLOAD_KNOCK + RaceLayout.EVENT_PAYLOAD_PICKUP])
	assert_float(payload[heads[s + 2]]).is_equal(1.5)
	assert_float(payload[heads[2 * s + 2]]).is_equal(2.5)


func test_events_past_capacity_are_dropped_and_overflow_stays_set_until_a_clean_tick() -> void:
	var sim: RaceSim = _make(2)
	sim.begin_tick(0)
	assert_bool(_emit(sim, 0, RaceLayout.EVENT_KIND_PICKUP)).is_true()
	assert_bool(_emit(sim, 0, RaceLayout.EVENT_KIND_PICKUP)).is_true()
	assert_bool(sim.events_overflowed()).is_false()
	assert_bool(_emit(sim, 0, RaceLayout.EVENT_KIND_PICKUP)).is_false()
	assert_bool(sim.events_overflowed()).is_true()
	assert_bool(_emit(sim, 1, RaceLayout.EVENT_KIND_KNOCK)).is_false()
	sim.apply_events(PackedInt32Array(), PackedFloat32Array())
	sim.step_drive(driver_rows(1))
	sim.step_bodies()
	sim.set_remote(remote_rows(1), 0)
	sim.step_contact()
	sim.step_progress_items_hazards()
	sim.end_tick()
	assert_int(sim.event_count()).is_equal(2)
	assert_bool(sim.events_overflowed()).is_true()
	# Tick 1 drops nothing: the flag stays set until its end_tick, then clears.
	sim.begin_tick(1)
	assert_bool(sim.events_overflowed()).is_true()
	sim.apply_events(PackedInt32Array(), PackedFloat32Array())
	sim.step_drive(driver_rows(1))
	sim.step_bodies()
	sim.set_remote(remote_rows(1), 0)
	sim.step_contact()
	sim.step_progress_items_hazards()
	assert_bool(sim.events_overflowed()).is_true()
	sim.end_tick()
	assert_bool(sim.events_overflowed()).is_false()


func test_end_tick_clears_the_working_event_buffer() -> void:
	var sim: RaceSim = _make()
	sim.begin_tick(0)
	_emit(sim, 1, RaceLayout.EVENT_KIND_KNOCK)
	sim.apply_events(PackedInt32Array(), PackedFloat32Array())
	sim.step_drive(driver_rows(1))
	sim.step_bodies()
	sim.set_remote(remote_rows(1), 0)
	sim.step_contact()
	sim.step_progress_items_hazards()
	sim.end_tick()
	assert_int(sim.event_count()).is_equal(1)
	var held_heads: PackedInt32Array = sim.event_headers()
	_tick(sim, 1)
	assert_int(sim.event_count()).is_equal(0)
	assert_int(held_heads[RaceLayout.EVENT_KIND]).is_equal(RaceLayout.EVENT_KIND_KNOCK)
	_tick(sim, 2)
	assert_int(sim.event_count()).is_equal(0)
	for value: int in sim.event_headers():
		assert_int(value).is_equal(0)


func test_debug_emit_event_refuses_outside_a_tick_and_a_bad_kind_or_payload() -> void:
	var sim: RaceSim = _make()
	await refuses(func() -> void: sim.debug_emit_event(0, RaceLayout.EVENT_KIND_PICKUP, PackedFloat32Array([1.0])), "inside a tick")
	sim.begin_tick(0)
	await refuses(func() -> void: sim.debug_emit_event(0, 77, PackedFloat32Array([1.0])), "unknown kind")
	await refuses(func() -> void: sim.debug_emit_event(0, RaceLayout.EVENT_KIND_KNOCK, PackedFloat32Array([1.0])), "does not fit")
	await refuses(func() -> void: sim.debug_emit_event(7, RaceLayout.EVENT_KIND_PICKUP, PackedFloat32Array([1.0])), "slot out of range")


func test_stage_timers_have_one_element_per_stage_and_close_in_end_tick() -> void:
	var sim: RaceSim = _make()
	assert_int(sim.stage_usec().size()).is_equal(RaceLayout.STAGE_COUNT)
	_tick(sim, 0)
	var usec: PackedFloat64Array = sim.stage_usec()
	assert_int(usec.size()).is_equal(8)
	for i in usec.size():
		assert_float(usec[i]).is_greater_equal(0.0)
		assert_float(usec[i]).is_less(1000000.0)
	var total: float = 0.0
	for value: float in usec:
		total += value
	assert_float(total).is_greater(0.0)


func test_stage_timers_mid_tick_serve_the_last_closed_tick() -> void:
	var sim: RaceSim = _make()
	_tick(sim, 0)
	var closed: PackedFloat64Array = sim.stage_usec().duplicate()
	sim.begin_tick(1)
	# Mid-tick the accessor still serves the last closed tick.
	assert_array(sim.stage_usec()).is_equal(closed)


func _heap_run(sim: RaceSim, first: int, ticks: int) -> void:
	var rows: PackedFloat32Array = driver_rows(1)
	var remote: PackedFloat32Array = remote_rows(1)
	var snaps: PackedFloat32Array
	var progress: PackedFloat32Array
	var usec: PackedFloat64Array
	var heads: PackedInt32Array
	for t in range(first, first + ticks):
		sim.begin_tick(t)
		sim.apply_events(PackedInt32Array(), PackedFloat32Array())
		sim.step_drive(rows)
		sim.step_bodies()
		sim.set_remote(remote, 0)
		sim.step_contact()
		sim.step_progress_items_hazards()
		sim.end_tick()
		# A consumer that refreshes every reference every tick.
		snaps = sim.snapshots()
		progress = sim.progress()
		usec = sim.stage_usec()
		heads = sim.event_headers()


func test_heap_is_flat_over_600_ticks_with_refreshing_consumer() -> void:
	var sim: RaceSim = _make()
	_heap_run(sim, 0, 20)
	var before: int = OS.get_static_memory_usage()
	_heap_run(sim, 20, 600)
	var growth: int = OS.get_static_memory_usage() - before
	print("HEAP refreshing consumer: static memory growth over 600 ticks = %d bytes" % growth)
	assert_int(growth).is_less_equal(HEAP_TOLERANCE)


func test_heap_costs_one_copy_when_a_consumer_holds_one_array_for_the_whole_run() -> void:
	var sim: RaceSim = _make()
	_heap_run(sim, 0, 20)
	var held: PackedFloat32Array = sim.snapshots()
	var held_tick: int = int(held[RaceLayout.SNAP_TICK])
	var before_first: int = OS.get_static_memory_usage()
	_heap_run(sim, 20, 4)
	var first_cost: int = OS.get_static_memory_usage() - before_first
	var before_second: int = OS.get_static_memory_usage()
	_heap_run(sim, 24, 600)
	var growth: int = OS.get_static_memory_usage() - before_second
	print("HEAP holding consumer: first 4 ticks cost %d bytes (one copy of %d), next 600 ticks grew %d bytes" % [first_cost, held.size() * 4, growth])
	assert_int(growth).is_less_equal(HEAP_TOLERANCE)
	assert_int(int(held[RaceLayout.SNAP_TICK])).is_equal(held_tick)
	assert_int(first_cost).is_less_equal(held.size() * 4 + HEAP_TOLERANCE)
