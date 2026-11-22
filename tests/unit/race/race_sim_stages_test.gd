extends "res://tests/unit/race/race_suite_base.gd"
## Core-rebuild story 068, criteria "The eight stages", "Order asserted", "Slot roles" and "Race flow calls"
## (ADR-0007 section 3). One negative test per stage for the order; the same suite is run once on the release-optimised
## DLL (tools/build_native.sh --bench) as the release-build evidence.

const _GUARD = preload("res://tests/unit/native/native_test_guard.gd")

## local, bot, remote, local, remote
const ROLES: PackedInt32Array = [0, 1, 2, 0, 2]

var _sims: Array[RaceSim] = []


func before() -> void:
	assert_str(_GUARD.problem()).is_empty()


func after_test() -> void:
	for sim: RaceSim in _sims:
		sim.dispose()
	_sims.clear()


func _make(roles: PackedInt32Array = ROLES) -> RaceSim:
	var sim: RaceSim = RaceSim.create(setup_for(roles))
	assert_object(sim).is_not_null()
	_sims.append(sim)
	return sim


func _local(sim: RaceSim) -> int:
	return sim.local_slot_count()


func _remote(sim: RaceSim) -> int:
	return sim.slot_count() - sim.local_slot_count() - _bots(sim)


func _bots(sim: RaceSim) -> int:
	var n: int = 0
	for role: int in sim.slot_roles():
		n += 1 if role == RaceLayout.ROLE_BOT else 0
	return n


## Calls stage [param stage] (0..7) with valid arguments.
func _call_stage(sim: RaceSim, stage: int, tick: int = 0) -> void:
	match stage:
		RaceLayout.STAGE_BEGIN_TICK: sim.begin_tick(tick)
		RaceLayout.STAGE_APPLY_EVENTS: sim.apply_events(PackedInt32Array(), PackedFloat32Array())
		RaceLayout.STAGE_STEP_DRIVE: sim.step_drive(driver_rows(_local(sim)))
		RaceLayout.STAGE_STEP_BODIES: sim.step_bodies()
		RaceLayout.STAGE_SET_REMOTE: sim.set_remote(remote_rows(_remote(sim)), 0)
		RaceLayout.STAGE_STEP_CONTACT: sim.step_contact()
		RaceLayout.STAGE_PROGRESS_ITEMS_HAZARDS: sim.step_progress_items_hazards()
		RaceLayout.STAGE_END_TICK: sim.end_tick()


func _run_stages(sim: RaceSim, from: int, to: int, tick: int = 0) -> void:
	for stage in range(from, to + 1):
		_call_stage(sim, stage, tick)


func _tick(sim: RaceSim, tick: int) -> void:
	_run_stages(sim, 0, 7, tick)


func test_full_tick_runs_all_eight_stages_and_records_time() -> void:
	var sim: RaceSim = _make()
	_tick(sim, 3)
	assert_int(sim.tick()).is_equal(3)
	assert_int(int(sim.snapshots()[RaceLayout.SNAP_TICK])).is_equal(3)
	assert_int(sim.stage_usec().size()).is_equal(8)


func test_begin_tick_computes_time_from_the_tick_in_native_code() -> void:
	var sim: RaceSim = _make()
	sim.begin_tick(90)
	assert_float(sim.tick_time()).is_equal(90.0 / 60.0)
	assert_float(sim.tick_time()).is_equal(1.5)


func test_negative_tick_is_refused() -> void:
	var sim: RaceSim = _make()
	await refuses(func() -> void: sim.begin_tick(-1), "must not be negative")
	assert_int(sim.tick()).is_equal(-1)


## Each stage called before its turn (from the between-ticks state; begin_tick twice) is refused, and the tick then
## completes normally: the refused call changed nothing.
func test_stage_out_of_order_is_refused_and_state_is_unchanged(stage: int, test_parameters := [[0], [1], [2], [3], [4], [5], [6], [7]]) -> void:
	var sim: RaceSim = _make()
	if stage == RaceLayout.STAGE_BEGIN_TICK:
		sim.begin_tick(0)
	var before_tick: int = sim.tick()
	await refuses(func() -> void: _call_stage(sim, stage, 1), "out of order")
	assert_int(sim.tick()).is_equal(before_tick)
	assert_int(sim.snapshots().size()).is_equal(sim.slot_count() * RaceLayout.SNAP_STRIDE)
	# The sequence still completes from where it was.
	_run_stages(sim, 1 if stage == RaceLayout.STAGE_BEGIN_TICK else 0, 7)
	assert_int(int(sim.snapshots()[RaceLayout.SNAP_TICK])).is_equal(0)


## Skipping a stage is refused too: the call after the next one, with the tick part way through.
func test_stage_skipped_is_refused(stage: int, test_parameters := [[1], [2], [3], [4], [5], [6], [7]]) -> void:
	var sim: RaceSim = _make()
	_run_stages(sim, 0, stage - 2)
	await refuses(func() -> void: _call_stage(sim, stage), "out of order")
	_run_stages(sim, stage - 1, 7)
	assert_int(int(sim.snapshots()[RaceLayout.SNAP_TICK])).is_equal(0)


func test_stage_cannot_repeat_within_a_tick() -> void:
	var sim: RaceSim = _make()
	_run_stages(sim, 0, 3)
	await refuses(func() -> void: sim.step_bodies(), "out of order")


func test_apply_events_refuses_a_malformed_row_and_changes_nothing() -> void:
	var sim: RaceSim = _make()
	sim.begin_tick(0)
	var ok_headers: PackedInt32Array = [0, RaceLayout.EVENT_KIND_PICKUP, 0]
	await refuses(func() -> void: sim.apply_events(PackedInt32Array([0, 1]), PackedFloat32Array([1.0])), "whole rows")
	await refuses(func() -> void: sim.apply_events(PackedInt32Array([9, RaceLayout.EVENT_KIND_PICKUP, 0]), PackedFloat32Array([1.0])), "slot out of range")
	await refuses(func() -> void: sim.apply_events(PackedInt32Array([0, 99, 0]), PackedFloat32Array([1.0])), "unknown kind")
	await refuses(func() -> void: sim.apply_events(PackedInt32Array([0, RaceLayout.EVENT_KIND_KNOCK, 0]), PackedFloat32Array([1.0])), "past the payload")
	sim.apply_events(ok_headers, PackedFloat32Array([3.0]))
	sim.step_drive(driver_rows(_local(sim)))


func test_step_drive_refuses_a_wrong_row_count_or_width() -> void:
	var sim: RaceSim = _make()
	sim.begin_tick(0)
	sim.apply_events(PackedInt32Array(), PackedFloat32Array())
	await refuses(func() -> void: sim.step_drive(driver_rows(1)), "wrong row count")
	await refuses(func() -> void: sim.step_drive(driver_rows(3)), "wrong row count")
	await refuses(func() -> void: sim.step_drive(PackedFloat32Array()), "wrong row count")
	await refuses(func() -> void: sim.step_drive(PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])), "wrong row width")
	await refuses(func() -> void: sim.step_drive(PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])), "wrong row width")
	sim.step_drive(driver_rows(2))
	assert_int(sim.debug_drive_rows(0)).is_equal(1)
	assert_int(sim.debug_drive_rows(3)).is_equal(1)


func test_bot_slots_take_native_decisions_and_remote_slots_have_no_body() -> void:
	var sim: RaceSim = _make()
	_tick(sim, 0)
	assert_int(sim.debug_bot_decisions(1)).is_equal(1)
	assert_int(sim.debug_integrated(1)).is_equal(1)
	assert_int(sim.debug_drive_rows(1)).is_equal(0)
	for remote_slot: int in [2, 4]:
		assert_int(sim.debug_integrated(remote_slot)).is_equal(0)
		assert_int(sim.debug_drive_rows(remote_slot)).is_equal(0)
	await refuses(func() -> void: sim.place(2, PackedFloat32Array([0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1])), "no body")


func test_set_remote_copies_the_poses_and_keeps_no_reference() -> void:
	var sim: RaceSim = _make()
	sim.begin_tick(0)
	sim.apply_events(PackedInt32Array(), PackedFloat32Array())
	sim.step_drive(driver_rows(2))
	sim.step_bodies()
	var rows: PackedFloat32Array = remote_rows(2)
	rows[RaceLayout.SNAP_POS] = 5.0
	rows[RaceLayout.REMOTE_STRIDE + RaceLayout.SNAP_POS + 2] = -7.0
	sim.set_remote(rows, 0)
	# Overwrite the caller's array after the call: native must hold its own copy.
	rows.fill(99.0)
	sim.step_contact()
	sim.step_progress_items_hazards()
	sim.end_tick()
	assert_vector(sim.snapshot_position(2)).is_equal(Vector3(5, 0, 0))
	assert_vector(sim.snapshot_position(4)).is_equal(Vector3(0, 0, -7))
	assert_bool(sim.snapshot_basis(2).is_equal_approx(Basis.IDENTITY)).is_true()


func test_set_remote_refuses_a_wrong_row_count_width_and_non_finite_pose() -> void:
	var sim: RaceSim = _make()
	_run_stages(sim, 0, 3)
	await refuses(func() -> void: sim.set_remote(remote_rows(1), 0), "wrong row count")
	await refuses(func() -> void: sim.set_remote(PackedFloat32Array([0, 0, 0]), 0), "wrong row width")
	var bad: PackedFloat32Array = remote_rows(2)
	bad[3] = NAN
	await refuses(func() -> void: sim.set_remote(bad, 0), "non-finite")


func test_contact_eligible_mask_is_read_back_through_the_end_of_tick_snapshot() -> void:
	var sim: RaceSim = _make()
	_run_stages(sim, 0, 3)
	sim.set_remote(remote_rows(2), 1 << 4)
	_run_stages(sim, 5, 7)
	assert_int(sim.snapshot_flags(4) & RaceLayout.SNAP_FLAG_CONTACT_ELIGIBLE).is_equal(RaceLayout.SNAP_FLAG_CONTACT_ELIGIBLE)
	assert_int(sim.snapshot_flags(2) & RaceLayout.SNAP_FLAG_CONTACT_ELIGIBLE).is_equal(0)
	assert_int(sim.snapshot_flags(0) & RaceLayout.SNAP_FLAG_CONTACT_ELIGIBLE).is_equal(0)
	# The mask is per tick: the next tick starts with no remote slot eligible.
	_run_stages(sim, 0, 3, 1)
	sim.set_remote(remote_rows(2), 0)
	_run_stages(sim, 5, 7, 1)
	assert_int(sim.snapshot_flags(4) & RaceLayout.SNAP_FLAG_CONTACT_ELIGIBLE).is_equal(0)


func test_contact_mask_naming_a_non_remote_or_unknown_slot_is_refused() -> void:
	var sim: RaceSim = _make()
	_run_stages(sim, 0, 3)
	await refuses(func() -> void: sim.set_remote(remote_rows(2), 1 << 0), "not remote")
	await refuses(func() -> void: sim.set_remote(remote_rows(2), 1 << 9), "out of range")
	await refuses(func() -> void: sim.set_remote(remote_rows(2), -1), "out of range")


func test_place_and_hold_are_refused_inside_a_tick() -> void:
	var sim: RaceSim = _make()
	sim.begin_tick(0)
	var pose: PackedFloat32Array = [1, 2, 3, 1, 0, 0, 0, 1, 0, 0, 0, 1]
	await refuses(func() -> void: sim.place(0, pose), "between end_tick")
	await refuses(func() -> void: sim.hold(1), "between end_tick")
	sim.apply_events(PackedInt32Array(), PackedFloat32Array())
	await refuses(func() -> void: sim.place(0, pose), "between end_tick")
	await refuses(func() -> void: sim.hold(1), "between end_tick")


func test_place_marks_the_snapshot_teleported_for_one_tick() -> void:
	var sim: RaceSim = _make()
	_tick(sim, 0)
	assert_int(sim.snapshot_flags(0) & RaceLayout.SNAP_FLAG_TELEPORTED).is_equal(0)
	var pose: PackedFloat32Array = [1, 2, 3, 1, 0, 0, 0, 1, 0, 0, 0, 1]
	sim.place(0, pose)
	_tick(sim, 1)
	assert_vector(sim.snapshot_position(0)).is_equal(Vector3(1, 2, 3))
	assert_int(sim.snapshot_flags(0) & RaceLayout.SNAP_FLAG_TELEPORTED).is_equal(RaceLayout.SNAP_FLAG_TELEPORTED)
	assert_int(sim.snapshot_flags(1) & RaceLayout.SNAP_FLAG_TELEPORTED).is_equal(0)
	_tick(sim, 2)
	assert_int(sim.snapshot_flags(0) & RaceLayout.SNAP_FLAG_TELEPORTED).is_equal(0)
	assert_vector(sim.snapshot_position(0)).is_equal(Vector3(1, 2, 3))


func test_place_refuses_a_bad_slot_pose_size_or_non_finite_pose() -> void:
	var sim: RaceSim = _make()
	var pose: PackedFloat32Array = [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]
	await refuses(func() -> void: sim.place(9, pose), "slot out of range")
	await refuses(func() -> void: sim.place(0, PackedFloat32Array([1.0])), "PLACE_STRIDE")
	var bad: PackedFloat32Array = pose.duplicate()
	bad[0] = INF
	await refuses(func() -> void: sim.place(0, bad), "non-finite")


func test_hold_is_applied_at_the_next_begin_tick_and_skips_integration() -> void:
	var sim: RaceSim = _make()
	_tick(sim, 0)
	assert_int(sim.debug_integrated(0)).is_equal(1)
	sim.hold(1 << 0)
	# Applied at the next begin_tick, not at the call: the published snapshot is still tick 0's.
	assert_int(sim.snapshot_flags(0) & RaceLayout.SNAP_FLAG_HELD).is_equal(0)
	_tick(sim, 1)
	assert_int(sim.snapshot_flags(0) & RaceLayout.SNAP_FLAG_HELD).is_equal(RaceLayout.SNAP_FLAG_HELD)
	assert_int(sim.debug_integrated(0)).is_equal(1)
	assert_int(sim.debug_integrated(3)).is_equal(3 - 1)
	sim.hold(0)
	_tick(sim, 2)
	assert_int(sim.debug_integrated(0)).is_equal(2)
	assert_int(sim.snapshot_flags(0) & RaceLayout.SNAP_FLAG_HELD).is_equal(0)


func test_held_slot_driver_rows_still_reach_the_start_logic_hook() -> void:
	var sim: RaceSim = _make()
	sim.hold(1 << 0)
	_tick(sim, 0)
	_tick(sim, 1)
	assert_int(sim.debug_start_rows(0)).is_equal(2)
	assert_int(sim.debug_drive_rows(0)).is_equal(0)
	assert_int(sim.debug_start_rows(3)).is_equal(0)
	assert_int(sim.debug_drive_rows(3)).is_equal(2)


func test_hold_refuses_a_remote_or_unknown_slot() -> void:
	var sim: RaceSim = _make()
	await refuses(func() -> void: sim.hold(1 << 2), "no body to hold")
	await refuses(func() -> void: sim.hold(1 << 7), "out of range")
	await refuses(func() -> void: sim.hold(-1), "out of range")
