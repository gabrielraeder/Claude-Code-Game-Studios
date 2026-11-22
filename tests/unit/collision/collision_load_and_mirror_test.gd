extends GdUnitTestSuite
## Core-rebuild story 006: the collision load checks (ids against the core registries, the t = 0
## probe cast, has_geometry), the boot settings asserts, TrackCollisionData.mirrored() /
## MoverDef.mirrored(), and a binary .res round trip. Fixture geometry is built in code
## (collision_fixtures.gd); no randomness, no time-dependent assertion. The two round-trip tests
## write one file each under user:// and remove it again.
##
## Story acceptance criteria (story order) -> GDD / ADR source -> tests:
##   AC 1  Face-index load check       (Track Collision AC-18; ADR-0002 Validation Criteria)
##         test_load_check_with_face_index_setting_off_fails_naming_the_setting,
##         test_load_check_on_sound_fixture_passes
##   AC 2  Mirror                      (Track Collision AC-17; ADR-0001 section 7; ADR-0002 Mirror)
##         test_mirrored_ground_casts_hit_mirrored_points_with_same_surface_ids,
##         test_mirrored_wall_sweeps_hit_mirrored_points_with_same_wall_attr_ids,
##         test_mirrored_mover_poses_are_m_b_m,
##         test_mirrored_flips_winding_so_faces_keep_their_front,
##         test_mirrored_leaves_source_unchanged,
##         test_mirrored_returns_new_objects_and_new_mover_defs,
##         test_mirrored_maps_every_export_field_of_track_collision_data,
##         test_mover_def_mirrored_maps_every_export_field,
##         test_mirrored_data_passes_the_load_check,
##         test_mirrored_of_cached_resource_leaves_the_cache_unmirrored
##   AC 3  Boot asserts                (ADR-0002 Boot and load checks; ADR-0001 section 5)
##         ids: test_id_check_accepts_registered_ids,
##              test_id_check_rejects_unknown_surface_of_face_id,
##              test_id_check_rejects_surface_none,
##              test_id_check_rejects_unknown_wall_attr_id,
##              test_id_check_rejects_repeated_wall_attr_id,
##              test_id_check_rejects_unknown_mover_surface_id,
##              test_id_check_rejects_unknown_mover_wall_attr_id,
##              test_id_check_rejects_unknown_probe_surface_id,
##              test_id_check_without_registries_fails,
##              test_load_check_reports_unknown_id
##         probe: test_load_probe_on_rejected_layout_runs_and_names_no_geometry,
##              test_load_check_on_data_without_geometry_fails_naming_no_geometry,
##              test_load_check_on_null_data_fails,
##              test_load_probe_on_wrong_surface_fails_naming_both_ids,
##              test_load_probe_over_nothing_fails,
##              test_load_probe_over_solid_mover_at_t0_fails,
##              test_load_probe_runs_at_t0_not_while_a_mover_passes_later,
##              test_has_geometry_false_when_rejected_and_after_dispose,
##              test_query_of_only_non_solid_movers_has_geometry_but_fails_the_probe
##         checked query: test_checked_query_of_sound_data_returns_the_query,
##              test_checked_query_of_failing_data_disposes_and_returns_the_reason
##         settings: test_boot_settings_of_this_project_pass,
##              test_boot_settings_each_wrong_pinned_value_fails_naming_it,
##              test_boot_settings_missing_value_fails_naming_it,
##              test_assert_boot_settings_with_interpolation_on_fails_naming_it,
##              test_current_settings_reads_tick_rate_and_max_steps_from_engine
##   AC 4  Grep                        (ADR-0002 Validation Criteria): tools/core_greps.sh, run by
##         the story run (not a gdUnit4 test: it is a shell script wired into tools/regression.sh).
##   Story 003 engine check: test_binary_res_round_trip_keeps_typed_arrays_equal
##
## Mirror-equivalence samples keep away from the degenerate exact-centre cases (a capsule or
## cylinder axis point, a box centre plane), whose fixed RIGHT normal is not mirror-symmetric
## (story 005 LP review).

const Fixtures = preload("res://tests/unit/collision/collision_fixtures.gd")

## Position / normal / velocity / fraction tolerance of a mirrored hit against M x the source hit.
const MIRROR_TOLERANCE: float = 0.001
## Sim times the mirror-equivalence tests run at (s): not key times, so no segment boundary.
const MIRROR_TIMES: Array[float] = [0.0, 0.37, 1.9, 2.75]
## Ground-cast sample grid: origin, step and count per axis (steps chosen off every edge and centre).
const GRID_X0: float = -2.013
const GRID_DX: float = 0.731
const GRID_NX: int = 150
const GRID_Z0: float = -1.117
const GRID_DZ: float = 0.613
const GRID_NZ: int = 11
## Fewest static and mover ground hits per time the grid must produce (so the test is not vacuous).
const MIN_STATIC_HITS: int = 50
const MIN_MOVER_HITS: int = 10
## Sweep cases against the walls (plane x = 0, front +X): offsets from each wall centre (x, y, z).
const WALL_BLOCK_FROM: Vector3 = Vector3(3.1, 2.03, 0.41)
const WALL_BLOCK_TO: Vector3 = Vector3(-0.7, 2.11, 1.23)
const WALL_INSIDE_FROM: Vector3 = Vector3(0.43, 1.97, -0.77)
const WALL_INSIDE_TO: Vector3 = Vector3(2.2, 1.97, -0.77)
const WALL_CLEAR_FROM: Vector3 = Vector3(3.0, 2.0, 0.0)
const WALL_CLEAR_TO: Vector3 = Vector3(5.0, 2.0, 0.3)
## Sweep cases against the movers (world from, to): spinner, capsule, cylinder, plus overlaps
## offset from every mover axis.
const MOVER_SWEEPS: Array[Vector3] = [
	Vector3(16.2, 1.13, 2.37), Vector3(21.9, 0.97, 1.71),
	Vector3(36.4, 1.62, 1.33), Vector3(41.3, 1.41, 2.27),
	Vector3(57.1, 1.31, 2.83), Vector3(62.2, 1.44, 2.12),
	Vector3(21.1, 1.6, 2.9), Vector3(22.3, 1.6, 3.1),
	Vector3(40.37, 1.91, 2.43), Vector3(41.0, 1.91, 2.43),
]
## Fixture ground surface id that is not in the registry (the fixture registry has no 99).
const UNKNOWN_ID: int = 99
## Settings a wrong boot value is built from: a physics engine other than Jolt.
const OTHER_ENGINE: String = "GodotPhysics3D"
## Paths the round-trip tests write (and remove).
const ROUND_TRIP_PATH: String = "user://collision_load_and_mirror_round_trip.res"
const CACHE_PATH: String = "user://collision_load_and_mirror_cache.res"
## Fields of TrackCollisionData mirrored() maps (anything else must be copied unchanged).
const DATA_MIRRORED_FIELDS: Array[StringName] = [&"ground_faces", &"wall_faces", &"movers", &"probe_point"]
const DATA_COPIED_FIELDS: Array[StringName] = [&"surface_of_face", &"wall_attr_ids", &"probe_surface_id"]
## Fields of MoverDef mirrored() maps, and those it copies unchanged.
const MOVER_MIRRORED_FIELDS: Array[StringName] = [&"key_pos", &"key_rot"]
const MOVER_COPIED_FIELDS: Array[StringName] = [
	&"id", &"period", &"solid", &"surface_id", &"wall_attr_id", &"shape", &"half_extents", &"radius",
	&"half_height", &"key_t",
]


# --- hooks --------------------------------------------------------------------------------------

## Undoes whatever a test may have left behind, even after a failed assert: the round-trip files,
## the face-index and interpolation settings, and the Engine tick values.
func after_test() -> void:
	_remove_file(CACHE_PATH)
	_remove_file(ROUND_TRIP_PATH)
	ProjectSettings.set_setting(CollisionBootCheck.INTERPOLATION_SETTING,
			CollisionBootCheck.PINNED_SETTINGS[CollisionBootCheck.INTERPOLATION_SETTING])
	Engine.physics_ticks_per_second = CollisionBootCheck.PINNED_SETTINGS[CollisionBootCheck.TICKS_SETTING]
	Engine.max_physics_steps_per_frame = CollisionBootCheck.PINNED_SETTINGS[CollisionBootCheck.MAX_STEPS_SETTING]
	if ProjectSettings.get_setting(CollisionQuery.FACE_INDEX_SETTING) != true:
		ProjectSettings.set_setting(CollisionQuery.FACE_INDEX_SETTING, true)
		await get_tree().process_frame


## Removes the test-owned file at [param path] when it exists.
func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- helpers ------------------------------------------------------------------------------------

## x -> -x.
func _m(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## M = diag(-1, 1, 1).
func _mirror_basis() -> Basis:
	return Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0))


func _near(a: Vector3, b: Vector3) -> bool:
	return (a - b).length() <= MIRROR_TOLERANCE


## Names of the stored script fields (@export / @export_storage) of [param res].
func _export_fields(res: Object) -> Array[StringName]:
	var names: Array[StringName] = []
	for p: Dictionary in res.get_property_list():
		var usage: int = p["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE:
			names.append(StringName(p["name"]))
	return names


## A deep value snapshot of [param v]: Resources become a Dictionary of their stored script fields,
## arrays are copied element by element, packed arrays duplicated, so later writes to the source
## never reach the snapshot.
func _snap(v: Variant) -> Variant:
	if v is Resource:
		var fields: Dictionary = {}
		for f in _export_fields(v):
			fields[f] = _snap((v as Resource).get(f))
		return fields
	if typeof(v) == TYPE_ARRAY:
		var out: Array = []
		for e: Variant in v:
			out.append(_snap(e))
		return out
	if typeof(v) >= TYPE_PACKED_BYTE_ARRAY and typeof(v) <= TYPE_PACKED_VECTOR4_ARRAY:
		return v.duplicate()
	return v


func _registries() -> Array:
	return [Fixtures.non_contiguous_registry(), Fixtures.wall_registry()]


## load_error of [param data] on a fresh query, the query disposed afterwards.
func _load_error(data: TrackCollisionData) -> String:
	var regs: Array = _registries()
	var query: CollisionQuery = CollisionQuery.new(data)
	var problem: String = CollisionBootCheck.load_error(query, data, regs[0], regs[1], Fixtures.PROBE_MAX_DROP)
	query.dispose()
	return problem


## Compares a source ground hit with its mirrored counterpart; appends a description on mismatch.
func _compare_ground(a: GroundHit, b: GroundHit, where: String, out: Array[String]) -> void:
	if not _near(b.point, _m(a.point)) or not _near(b.normal, _m(a.normal)) or b.surface_id != a.surface_id \
			or b.collider_id != a.collider_id or not _near(b.collider_velocity, _m(a.collider_velocity)):
		out.append("%s: source (p %s n %s s %d c %d v %s) mirror (p %s n %s s %d c %d v %s)" % [where,
				a.point, a.normal, a.surface_id, a.collider_id, a.collider_velocity,
				b.point, b.normal, b.surface_id, b.collider_id, b.collider_velocity])


func _compare_wall(a: WallHit, b: WallHit, where: String, out: Array[String]) -> void:
	if not _near(b.point, _m(a.point)) or not _near(b.normal, _m(a.normal)) or b.wall_attr != a.wall_attr \
			or absf(b.fraction - a.fraction) > MIRROR_TOLERANCE or b.started_inside != a.started_inside \
			or b.collider_id != a.collider_id or not _near(b.collider_velocity, _m(a.collider_velocity)):
		out.append("%s: source (p %s n %s w %d f %s in %s c %d) mirror (p %s n %s w %d f %s in %s c %d)" % [where,
				a.point, a.normal, a.wall_attr, a.fraction, a.started_inside, a.collider_id,
				b.point, b.normal, b.wall_attr, b.fraction, b.started_inside, b.collider_id])


## The sweep cases (from, to pairs, flat) of the mirror fixture: three per wall, then MOVER_SWEEPS.
func _sweep_cases() -> PackedVector3Array:
	var cases: PackedVector3Array = PackedVector3Array()
	for k in Fixtures.WALL_SHAPE_ORDER.size():
		var centre: Vector3 = Vector3(0.0, 0.0, Fixtures.wall_centre_z(k))
		cases.append_array([centre + WALL_BLOCK_FROM, centre + WALL_BLOCK_TO])
		cases.append_array([centre + WALL_INSIDE_FROM, centre + WALL_INSIDE_TO])
		cases.append_array([centre + WALL_CLEAR_FROM, centre + WALL_CLEAR_TO])
	cases.append_array(PackedVector3Array(MOVER_SWEEPS))
	return cases


# --- AC 1: face-index load check ----------------------------------------------------------------

func test_load_check_on_sound_fixture_passes() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	# Act
	var problem: String = _load_error(data)
	# Assert
	assert_str(problem).is_empty()


func test_load_check_with_face_index_setting_off_fails_naming_the_setting() -> void:
	# Arrange: the ADR-0002 procedure: set the setting, await a frame, build a new query.
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	var regs: Array = _registries()
	ProjectSettings.set_setting(CollisionQuery.FACE_INDEX_SETTING, false)
	await get_tree().process_frame
	# Act
	var query: CollisionQuery = CollisionQuery.new(data)
	var probe_hit: GroundHit = GroundHit.new()
	var hit_with_setting_off: bool = query.cast_ground(QueryCursor.new(), data.probe_point, Vector3.DOWN,
			Fixtures.PROBE_MAX_DROP, CollisionQuery.PROBE_T, probe_hit)
	var problem: String = CollisionBootCheck.load_error(query, data, regs[0], regs[1], Fixtures.PROBE_MAX_DROP)
	query.dispose()
	# Restore before asserting, then show the same data passes again.
	ProjectSettings.set_setting(CollisionQuery.FACE_INDEX_SETTING, true)
	await get_tree().process_frame
	var problem_restored: String = _load_error(data)
	# Assert
	assert_bool(hit_with_setting_off).is_true()
	assert_int(probe_hit.surface_id).is_equal(CollisionQuery.SURFACE_NONE)
	assert_str(problem).contains("no face index")
	assert_str(problem).contains(CollisionQuery.FACE_INDEX_SETTING)
	assert_str(problem_restored).is_empty()
	assert_bool(ProjectSettings.get_setting(CollisionQuery.FACE_INDEX_SETTING)).is_true()


# --- AC 2: mirror -------------------------------------------------------------------------------

func test_mirrored_ground_casts_hit_mirrored_points_with_same_surface_ids() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	var source: CollisionQuery = CollisionQuery.new(data)
	var mirror: CollisionQuery = CollisionQuery.new(data.mirrored())
	var cursor_a: QueryCursor = QueryCursor.new()
	var cursor_b: QueryCursor = QueryCursor.new()
	var hit_a: GroundHit = GroundHit.new()
	var hit_b: GroundHit = GroundHit.new()
	var mismatches: Array[String] = []
	var fewest_static: int = GRID_NX * GRID_NZ
	var fewest_mover: int = GRID_NX * GRID_NZ
	var ramp_hits: int = 0
	# Act
	for t in MIRROR_TIMES:
		var n_static: int = 0
		var n_mover: int = 0
		for i in GRID_NX:
			for j in GRID_NZ:
				var p: Vector3 = Vector3(GRID_X0 + i * GRID_DX, Fixtures.CAST_HEIGHT, GRID_Z0 + j * GRID_DZ)
				var a: bool = source.cast_ground(cursor_a, p, Vector3.DOWN, Fixtures.CAST_LENGTH, t, hit_a)
				var b: bool = mirror.cast_ground(cursor_b, _m(p), Vector3.DOWN, Fixtures.CAST_LENGTH, t, hit_b)
				if a != b:
					mismatches.append("t %s at %s: source hit %s, mirror hit %s" % [t, p, a, b])
					continue
				if not a:
					continue
				_compare_ground(hit_a, hit_b, "t %s at %s" % [t, p], mismatches)
				if hit_a.collider_id == 0:
					n_static += 1
					if hit_a.surface_id == Fixtures.RAMP_SURFACE_ID:
						ramp_hits += 1
				else:
					n_mover += 1
		fewest_static = mini(fewest_static, n_static)
		fewest_mover = mini(fewest_mover, n_mover)
	source.dispose()
	mirror.dispose()
	# Assert
	assert_array(mismatches.slice(0, 10)).is_empty()
	assert_int(fewest_static).is_greater_equal(MIN_STATIC_HITS)
	assert_int(fewest_mover).is_greater_equal(MIN_MOVER_HITS)
	assert_int(ramp_hits).is_greater(0)


func test_mirrored_wall_sweeps_hit_mirrored_points_with_same_wall_attr_ids() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	var source: CollisionQuery = CollisionQuery.new(data)
	var mirror: CollisionQuery = CollisionQuery.new(data.mirrored())
	var cursor_a: QueryCursor = QueryCursor.new()
	var cursor_b: QueryCursor = QueryCursor.new()
	var hit_a: WallHit = WallHit.new()
	var hit_b: WallHit = WallHit.new()
	var cases: PackedVector3Array = _sweep_cases()
	var mismatches: Array[String] = []
	var static_blocked: int = 0
	var static_inside: int = 0
	var mover_hits: int = 0
	var misses: int = 0
	# Act
	for t in MIRROR_TIMES:
		for c in range(0, cases.size(), 2):
			var from: Vector3 = cases[c]
			var to: Vector3 = cases[c + 1]
			var a: bool = source.sweep_walls(cursor_a, from, to, Fixtures.SWEEP_RADIUS, t, hit_a)
			var b: bool = mirror.sweep_walls(cursor_b, _m(from), _m(to), Fixtures.SWEEP_RADIUS, t, hit_b)
			if a != b:
				mismatches.append("t %s %s -> %s: source hit %s, mirror hit %s" % [t, from, to, a, b])
				continue
			if not a:
				misses += 1
				continue
			_compare_wall(hit_a, hit_b, "t %s %s -> %s" % [t, from, to], mismatches)
			if hit_a.collider_id != 0:
				mover_hits += 1
			elif hit_a.started_inside:
				static_inside += 1
			else:
				static_blocked += 1
	source.dispose()
	mirror.dispose()
	# Assert
	assert_array(mismatches.slice(0, 10)).is_empty()
	assert_int(static_blocked).is_greater(0)
	assert_int(static_inside).is_greater(0)
	assert_int(mover_hits).is_greater(0)
	assert_int(misses).is_greater(0)


func test_mirrored_mover_poses_are_m_b_m() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	var source: CollisionQuery = CollisionQuery.new(data)
	var mirror: CollisionQuery = CollisionQuery.new(data.mirrored())
	var m: Basis = _mirror_basis()
	var problems: Array[String] = []
	# Act
	for mover in data.movers:
		for t in MIRROR_TIMES:
			var a: Transform3D = source.mover_pose(mover.id, t)
			var b: Transform3D = mirror.mover_pose(mover.id, t)
			var expected: Basis = m * a.basis * m
			var basis_ok: bool = _near(b.basis.x, expected.x) and _near(b.basis.y, expected.y) and _near(b.basis.z, expected.z)
			if not basis_ok or not _near(b.origin, _m(a.origin)) or absf(b.basis.determinant() - 1.0) > MIRROR_TOLERANCE:
				problems.append("mover %d t %s: source %s mirror %s" % [mover.id, t, a, b])
	source.dispose()
	mirror.dispose()
	# Assert
	assert_array(problems).is_empty()


func test_mirrored_flips_winding_so_faces_keep_their_front() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	# Act
	var out: TrackCollisionData = data.mirrored()
	# Assert: (a, b, c) -> (Ma, Mc, Mb), and the Godot front ((c - a) x (b - a)) of each mirrored face
	# is M times the source front (a ground face stays up-facing).
	assert_int(out.ground_faces.size()).is_equal(data.ground_faces.size())
	for tri in data.ground_triangle_count():
		var a: Vector3 = data.ground_faces[tri * 3]
		var b: Vector3 = data.ground_faces[tri * 3 + 1]
		var c: Vector3 = data.ground_faces[tri * 3 + 2]
		assert_vector(out.ground_faces[tri * 3]).is_equal(_m(a))
		assert_vector(out.ground_faces[tri * 3 + 1]).is_equal(_m(c))
		assert_vector(out.ground_faces[tri * 3 + 2]).is_equal(_m(b))
		var front: Vector3 = (c - a).cross(b - a)
		var ma: Vector3 = out.ground_faces[tri * 3]
		var mb: Vector3 = out.ground_faces[tri * 3 + 1]
		var mc: Vector3 = out.ground_faces[tri * 3 + 2]
		assert_vector((mc - ma).cross(mb - ma)).is_equal_approx(_m(front), Vector3.ONE * MIRROR_TOLERANCE)
	for k in data.wall_faces.size():
		var src: PackedVector3Array = data.wall_faces[k]
		var dst: PackedVector3Array = out.wall_faces[k]
		@warning_ignore("integer_division")
		var n_tri: int = src.size() / 3
		for tri in n_tri:
			assert_vector(dst[tri * 3 + 1]).is_equal(_m(src[tri * 3 + 2]))
			assert_vector(dst[tri * 3 + 2]).is_equal(_m(src[tri * 3 + 1]))


func test_mirrored_leaves_source_unchanged() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	var movers_before: Array[MoverDef] = data.movers.duplicate()
	var before: Variant = _snap(data)
	# Act: mirror, then write into every array of the mirror (aliasing would reach the source).
	var out: TrackCollisionData = data.mirrored()
	out.ground_faces[0] = Vector3.ONE
	out.surface_of_face[0] = UNKNOWN_ID
	var wall: PackedVector3Array = out.wall_faces[0]
	wall[0] = Vector3.ONE
	out.wall_faces[0] = wall
	out.wall_attr_ids[0] = UNKNOWN_ID
	out.movers[0].key_pos[0] = Vector3.ONE
	out.movers[0].key_rot[0] = Vector4.ONE
	out.movers[0].key_t[0] = 1.0
	out.movers[0].id = UNKNOWN_ID
	var after: Variant = _snap(data)
	# Assert
	assert_dict(after).is_equal(before)
	for k in movers_before.size():
		assert_object(data.movers[k]).is_same(movers_before[k])


func test_mirrored_returns_new_objects_and_new_mover_defs() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	# Act
	var out: TrackCollisionData = data.mirrored()
	# Assert
	assert_object(out).is_not_same(data)
	assert_int(out.movers.size()).is_equal(data.movers.size())
	for k in data.movers.size():
		assert_object(out.movers[k]).is_not_null()
		assert_object(out.movers[k]).is_not_same(data.movers[k])
	assert_str(out.layout_error()).is_empty()


func test_mirrored_maps_every_export_field_of_track_collision_data() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	var defaults: TrackCollisionData = TrackCollisionData.new()
	# Act
	var out: TrackCollisionData = data.mirrored()
	# Assert: every stored field is known here and set away from its default by the fixture.
	var fields: Array[StringName] = _export_fields(data)
	assert_int(fields.size()).is_greater(0)
	for f in fields:
		assert_bool(_snap(data.get(f)) != _snap(defaults.get(f))) \
				.override_failure_message("the fixture leaves TrackCollisionData.%s at its default" % f).is_true()
		if f in DATA_COPIED_FIELDS:
			assert_that(out.get(f)).override_failure_message("%s not copied" % f).is_equal(data.get(f))
		elif f in DATA_MIRRORED_FIELDS:
			pass  # checked below field by field
		else:
			fail("TrackCollisionData.%s is not mapped by this test: decide how mirrored() maps it (ADR-0001 section 7), then add it here" % f)
	assert_vector(out.probe_point).is_equal(_m(data.probe_point))
	assert_int(out.wall_faces.size()).is_equal(data.wall_faces.size())
	assert_int(out.ground_faces.size()).is_equal(data.ground_faces.size())
	for k in data.movers.size():
		assert_dict(_snap(out.movers[k])).is_equal(_snap(data.movers[k].mirrored()))


func test_mover_def_mirrored_maps_every_export_field() -> void:
	# Arrange
	var source: MoverDef = Fixtures.all_fields_mover()
	var defaults: MoverDef = MoverDef.new()
	# Act
	var out: MoverDef = source.mirrored()
	# Assert: walk every stored field (a new @export field fails here until it is mapped).
	var fields: Array[StringName] = _export_fields(source)
	assert_int(fields.size()).is_equal(MOVER_COPIED_FIELDS.size() + MOVER_MIRRORED_FIELDS.size())
	for f in fields:
		assert_bool(source.get(f) != defaults.get(f)) \
				.override_failure_message("all_fields_mover leaves MoverDef.%s at its default" % f).is_true()
		if f in MOVER_COPIED_FIELDS:
			assert_that(out.get(f)).override_failure_message("MoverDef.%s not copied" % f).is_equal(source.get(f))
		elif f == &"key_pos":
			var expected_pos: PackedVector3Array = PackedVector3Array()
			for p in source.key_pos:
				expected_pos.append(_m(p))
			assert_that(out.key_pos).is_equal(expected_pos)
		elif f == &"key_rot":
			var expected_rot: PackedVector4Array = PackedVector4Array()
			for q in source.key_rot:
				expected_rot.append(Vector4(q.x, -q.y, -q.z, q.w))
			assert_that(out.key_rot).is_equal(expected_rot)
		else:
			fail("MoverDef.%s is not mapped by this test: decide how mirrored() maps it (ADR-0001 section 7), then add it here" % f)
	assert_object(out).is_not_same(source)


func test_mirrored_data_passes_the_load_check() -> void:
	# Arrange: the probe point is mirrored with the track; without the winding flip it would miss.
	var data: TrackCollisionData = Fixtures.mirror_fixture().mirrored()
	# Act
	var problem: String = _load_error(data)
	# Assert
	assert_str(problem).is_empty()
	assert_float(data.probe_point.x).is_less(0.0)


func test_mirrored_of_cached_resource_leaves_the_cache_unmirrored() -> void:
	# Arrange: a cached load, as the track loader gets it.
	_remove_file(CACHE_PATH)
	assert_int(ResourceSaver.save(Fixtures.mirror_fixture(), CACHE_PATH)).is_equal(OK)
	var cached: TrackCollisionData = load(CACHE_PATH) as TrackCollisionData
	var before: Variant = _snap(cached)
	# Act
	var out: TrackCollisionData = cached.mirrored()
	var again: TrackCollisionData = load(CACHE_PATH) as TrackCollisionData
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE_PATH))
	# Assert
	assert_object(again).is_same(cached)
	assert_dict(_snap(again)).is_equal(before)
	assert_object(out).is_not_same(cached)


# --- AC 3: boot asserts: ids ---------------------------------------------------------------------

func test_id_check_accepts_registered_ids() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	var regs: Array = _registries()
	# Act / Assert
	assert_str(data.id_error(regs[0], regs[1])).is_empty()


func test_id_check_rejects_unknown_surface_of_face_id() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	data.surface_of_face[2] = UNKNOWN_ID
	var regs: Array = _registries()
	# Act / Assert
	assert_str(data.id_error(regs[0], regs[1])).is_equal("surface_of_face[2] is 99, not a surface id of the SurfaceSet")


func test_id_check_rejects_surface_none() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	data.surface_of_face[0] = CollisionQuery.SURFACE_NONE
	var regs: Array = _registries()
	# Act / Assert
	assert_str(data.id_error(regs[0], regs[1])).is_equal("surface_of_face[0] is -1, not a surface id of the SurfaceSet")


func test_id_check_rejects_unknown_wall_attr_id() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	data.wall_attr_ids[1] = UNKNOWN_ID
	var regs: Array = _registries()
	# Act / Assert
	assert_str(data.id_error(regs[0], regs[1])).is_equal("wall_attr_ids[1] is 99, not a wall-attribute id of the WallAttrSet")


func test_id_check_rejects_repeated_wall_attr_id() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	data.wall_attr_ids[2] = data.wall_attr_ids[0]
	var regs: Array = _registries()
	# Act / Assert
	assert_str(data.id_error(regs[0], regs[1])).is_equal(
			"wall_attr_ids[2] repeats wall-attribute id %d (one wall shape per attribute)" % data.wall_attr_ids[0])


func test_id_check_rejects_unknown_mover_surface_id() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	data.movers[1].surface_id = UNKNOWN_ID
	var regs: Array = _registries()
	# Act / Assert
	assert_str(data.id_error(regs[0], regs[1])).is_equal("movers[1] (id 2) has surface_id 99, not a surface id of the SurfaceSet")


func test_id_check_rejects_unknown_mover_wall_attr_id() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	data.movers[2].wall_attr_id = UNKNOWN_ID
	var regs: Array = _registries()
	# Act / Assert
	assert_str(data.id_error(regs[0], regs[1])).is_equal("movers[2] (id 3) has wall_attr_id 99, not a wall-attribute id of the WallAttrSet")


func test_id_check_rejects_unknown_probe_surface_id() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	data.probe_surface_id = UNKNOWN_ID
	var regs: Array = _registries()
	# Act / Assert
	assert_str(data.id_error(regs[0], regs[1])).is_equal("probe_surface_id is 99, not a surface id of the SurfaceSet")


func test_id_check_without_registries_fails() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	var regs: Array = _registries()
	# Act / Assert
	assert_str(data.id_error(null, regs[1])).is_equal("no SurfaceSet to check the surface ids against")
	assert_str(data.id_error(regs[0], null)).is_equal("no WallAttrSet to check the wall-attribute ids against")


func test_load_check_reports_unknown_id() -> void:
	# Arrange: the probe still passes (face PROBE_FACE keeps its id); only the id check can fail.
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	data.surface_of_face[0] = UNKNOWN_ID
	# Act
	var problem: String = _load_error(data)
	# Assert
	assert_str(problem).is_equal("load check: surface_of_face[0] is 99, not a surface id of the SurfaceSet")


# --- AC 3: boot asserts: probe -------------------------------------------------------------------

func test_load_probe_on_rejected_layout_runs_and_names_no_geometry() -> void:
	# Arrange: one surface id short: CollisionQuery push_errors and builds nothing.
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	data.surface_of_face.resize(data.surface_of_face.size() - 1)
	var regs: Array = _registries()
	var out: Array[CollisionQuery] = []
	await assert_error(func() -> void: out.append(CollisionQuery.new(data))).is_push_error(
			"CollisionQuery: surface_of_face has 9 entries for 10 ground triangles; the query has no geometry")
	var query: CollisionQuery = out[0]
	# Act
	var probe: String = query.probe_error(data.probe_point, data.probe_surface_id, Fixtures.PROBE_MAX_DROP)
	var problem: String = CollisionBootCheck.load_error(query, data, regs[0], regs[1], Fixtures.PROBE_MAX_DROP)
	query.dispose()
	# Assert
	assert_str(probe).contains("the query has no geometry")
	assert_str(problem).starts_with("load check: TrackCollisionData layout: surface_of_face has 9 entries for 10 ground triangles; ")
	assert_str(problem).ends_with(probe)


func test_load_check_on_data_without_geometry_fails_naming_no_geometry() -> void:
	# Arrange: a valid but empty track (probe id 0 = road is registered).
	var data: TrackCollisionData = TrackCollisionData.new()
	# Act
	var problem: String = _load_error(data)
	# Assert
	assert_str(problem).starts_with("load check: load probe at")
	assert_str(problem).contains("the query has no geometry")


func test_load_check_on_null_data_fails() -> void:
	# Arrange
	var regs: Array = _registries()
	var out: Array[CollisionQuery] = []
	await assert_error(func() -> void: out.append(CollisionQuery.new(null))).is_push_error(
			"CollisionQuery: data is null; the query has no geometry")
	# Act
	var problem: String = CollisionBootCheck.load_error(out[0], null, regs[0], regs[1], Fixtures.PROBE_MAX_DROP)
	out[0].dispose()
	# Assert
	assert_str(problem).is_equal("load check: no TrackCollisionData")


func test_load_probe_on_wrong_surface_fails_naming_both_ids() -> void:
	# Arrange: the probe claims face 0's id while standing over PROBE_FACE.
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	var found: int = data.surface_of_face[Fixtures.PROBE_FACE]
	data.probe_surface_id = data.surface_of_face[0]
	# Act
	var problem: String = _load_error(data)
	# Assert
	assert_str(problem).ends_with("found surface id %d, not probe_surface_id %d" % [found, data.probe_surface_id])


func test_load_probe_over_nothing_fails() -> void:
	# Arrange: the probe between two fixture triangles (no ground below).
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	data.probe_point.x += Fixtures.TRI_SPACING / 2.0
	# Act
	var problem: String = _load_error(data)
	# Assert
	assert_str(problem).contains("found no ground within %s m below" % Fixtures.PROBE_MAX_DROP)


func test_load_probe_over_solid_mover_at_t0_fails() -> void:
	# Arrange: a still box between the probe and the ground.
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	var blocker: MoverDef = Fixtures.still_box(9, data.probe_point + Vector3.DOWN * (Fixtures.PROBE_HEIGHT / 2.0),
			Vector3.ONE * (Fixtures.PROBE_HEIGHT / 8.0))
	blocker.surface_id = Fixtures.MIRROR_MOVER_SURFACE_IDS[0]
	blocker.wall_attr_id = Fixtures.MIRROR_MOVER_WALL_IDS[0]
	data.movers.append(blocker)
	# Act
	var problem: String = _load_error(data)
	# Assert
	assert_str(problem).contains("hit mover 9 at t = 0")


func test_load_probe_runs_at_t0_not_while_a_mover_passes_later() -> void:
	# Arrange: a slide box that is far from the probe at t = 0 and under it at SLIDE_TIME.
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	var under: Vector3 = data.probe_point + Vector3.DOWN * (Fixtures.PROBE_HEIGHT / 2.0)
	var slider: MoverDef = Fixtures.slide_box(9, under - Vector3.RIGHT * Fixtures.SLIDE_DISTANCE,
			Vector3.ONE * (Fixtures.PROBE_HEIGHT / 8.0))
	slider.surface_id = Fixtures.MIRROR_MOVER_SURFACE_IDS[0]
	slider.wall_attr_id = Fixtures.MIRROR_MOVER_WALL_IDS[0]
	data.movers.append(slider)
	var query: CollisionQuery = CollisionQuery.new(data)
	var hit: GroundHit = GroundHit.new()
	# Act
	var later_hit: bool = query.cast_ground(QueryCursor.new(), data.probe_point, Vector3.DOWN,
			Fixtures.PROBE_MAX_DROP, Fixtures.SLIDE_TIME, hit)
	var probe: String = query.probe_error(data.probe_point, data.probe_surface_id, Fixtures.PROBE_MAX_DROP)
	query.dispose()
	# Assert: at SLIDE_TIME the box is under the probe; at t = 0 the probe sees the ground.
	assert_bool(later_hit).is_true()
	assert_int(hit.collider_id).is_equal(9)
	assert_str(probe).is_empty()


func test_has_geometry_false_when_rejected_and_after_dispose() -> void:
	# Arrange
	var sound: CollisionQuery = CollisionQuery.new(Fixtures.mirror_fixture())
	var movers: CollisionQuery = CollisionQuery.new(Fixtures.movers_only([Fixtures.still_box(1, Vector3.ZERO, Vector3.ONE)]))
	var empty: CollisionQuery = CollisionQuery.new(TrackCollisionData.new())
	# Act
	var sound_before: bool = sound.has_geometry()
	sound.dispose()
	# Assert
	assert_bool(sound_before).is_true()
	assert_bool(sound.has_geometry()).is_false()
	assert_bool(movers.has_geometry()).is_true()
	assert_bool(empty.has_geometry()).is_false()
	movers.dispose()
	empty.dispose()


func test_query_of_only_non_solid_movers_has_geometry_but_fails_the_probe() -> void:
	# Arrange: one non-solid box right under the probe point.
	var ghost: MoverDef = Fixtures.still_box(1, Vector3.DOWN * (Fixtures.PROBE_HEIGHT / 2.0),
			Vector3.ONE * (Fixtures.PROBE_HEIGHT / 8.0))
	ghost.solid = false
	var query: CollisionQuery = CollisionQuery.new(Fixtures.movers_only([ghost]))
	# Act
	var geometry: bool = query.has_geometry()
	var probe: String = query.probe_error(Vector3.ZERO, 0, Fixtures.PROBE_MAX_DROP)
	query.dispose()
	# Assert
	assert_bool(geometry).is_true()
	assert_str(probe).contains("found no ground within")
	assert_str(probe).contains("has_geometry() counts non-solid movers")


# --- AC 3: boot asserts: checked query -----------------------------------------------------------

func test_checked_query_of_sound_data_returns_the_query() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	var regs: Array = _registries()
	# Act
	var checked: CollisionBootCheck.CheckedQuery = CollisionBootCheck.checked_query(data, regs[0], regs[1], Fixtures.PROBE_MAX_DROP)
	# Assert
	assert_str(checked.problem).is_empty()
	assert_object(checked.query).is_not_null()
	assert_bool(checked.query.has_geometry()).is_true()
	assert_bool(checked.query.is_disposed()).is_false()
	checked.query.dispose()


func test_checked_query_of_failing_data_disposes_and_returns_the_reason() -> void:
	# Arrange: an unknown surface id (no push_error at construction, so the only possible log entry
	# is the PREDELETE "freed without dispose()" warning of a query that was not disposed).
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	data.surface_of_face[0] = UNKNOWN_ID
	var regs: Array = _registries()
	var out: Array[CollisionBootCheck.CheckedQuery] = []
	# Act / Assert: no warning, so the failing query was disposed before it was dropped.
	await assert_error(func() -> void: out.append(CollisionBootCheck.checked_query(data, regs[0], regs[1],
			Fixtures.PROBE_MAX_DROP))).is_success()
	assert_object(out[0].query).is_null()
	assert_str(out[0].problem).is_equal("load check: surface_of_face[0] is 99, not a surface id of the SurfaceSet")


# --- AC 3: boot asserts: settings ----------------------------------------------------------------

func test_assert_boot_settings_with_interpolation_on_fails_naming_it() -> void:
	# Arrange (after_test restores the setting even if an assert below fails).
	ProjectSettings.set_setting(CollisionBootCheck.INTERPOLATION_SETTING, true)
	var expected: String = "boot: %s is true, pinned to false (ADR-0001 section 5)" % CollisionBootCheck.INTERPOLATION_SETTING
	var out: Array[String] = []
	# Act / Assert: debug builds stop at the assert; release builds strip it and return the problem.
	if OS.is_debug_build():
		await assert_error(func() -> void: out.append(CollisionBootCheck.assert_boot_settings())).is_runtime_error(
				"Assertion failed: CollisionBootCheck: %s" % expected)
	else:
		assert_str(CollisionBootCheck.assert_boot_settings()).is_equal(expected)
	ProjectSettings.set_setting(CollisionBootCheck.INTERPOLATION_SETTING, false)
	assert_str(CollisionBootCheck.settings_error(CollisionBootCheck.current_settings())).is_empty()


func test_current_settings_reads_tick_rate_and_max_steps_from_engine() -> void:
	# Arrange: Engine values that differ from the project settings (60 / 8 in project.godot);
	# after_test restores them even if an assert below fails.
	var ticks: int = CollisionBootCheck.PINNED_SETTINGS[CollisionBootCheck.TICKS_SETTING]
	var steps: int = CollisionBootCheck.PINNED_SETTINGS[CollisionBootCheck.MAX_STEPS_SETTING]
	Engine.physics_ticks_per_second = ticks + 1
	Engine.max_physics_steps_per_frame = steps + 1
	# Act
	var now: Dictionary[String, Variant] = CollisionBootCheck.current_settings()
	Engine.physics_ticks_per_second = ticks
	Engine.max_physics_steps_per_frame = steps
	# Assert
	assert_int(ProjectSettings.get_setting(CollisionBootCheck.TICKS_SETTING)).is_equal(ticks)
	assert_int(ProjectSettings.get_setting(CollisionBootCheck.MAX_STEPS_SETTING)).is_equal(steps)
	assert_int(now[CollisionBootCheck.TICKS_SETTING]).is_equal(ticks + 1)
	assert_int(now[CollisionBootCheck.MAX_STEPS_SETTING]).is_equal(steps + 1)
	assert_str(CollisionBootCheck.settings_error(now)).starts_with("boot: %s is %d" % [CollisionBootCheck.TICKS_SETTING, ticks + 1])


func test_boot_settings_of_this_project_pass() -> void:
	# Arrange
	var now: Dictionary[String, Variant] = CollisionBootCheck.current_settings()
	# Act
	var problem: String = CollisionBootCheck.assert_boot_settings()
	# Assert
	assert_str(problem).is_empty()
	assert_str(CollisionBootCheck.settings_error(now)).is_empty()
	assert_array(now.keys()).contains_exactly_in_any_order(CollisionBootCheck.PINNED_SETTINGS.keys())


func test_boot_settings_each_wrong_pinned_value_fails_naming_it() -> void:
	# Arrange / Act / Assert: one wrong value at a time.
	for key: String in CollisionBootCheck.PINNED_SETTINGS:
		var settings: Dictionary[String, Variant] = CollisionBootCheck.PINNED_SETTINGS.duplicate()
		var pinned: Variant = settings[key]
		var wrong: Variant = null
		match typeof(pinned):
			TYPE_BOOL:
				wrong = not pinned
			TYPE_INT:
				wrong = pinned + 1
			TYPE_FLOAT:
				wrong = pinned + 0.5
			TYPE_STRING:
				wrong = OTHER_ENGINE
		settings[key] = wrong
		var problem: String = CollisionBootCheck.settings_error(settings)
		assert_str(problem).override_failure_message("%s = %s passed: %s" % [key, wrong, problem]) \
				.is_equal("boot: %s is %s, pinned to %s (%s)" % [key, var_to_str(wrong), var_to_str(pinned),
				CollisionBootCheck.PINNED_BY[key]])
	# A pinned int given as an equal float (Engine values) passes; a bool given as an int does not.
	var numeric: Dictionary[String, Variant] = CollisionBootCheck.PINNED_SETTINGS.duplicate()
	numeric[CollisionBootCheck.TICKS_SETTING] = float(numeric[CollisionBootCheck.TICKS_SETTING])
	assert_str(CollisionBootCheck.settings_error(numeric)).is_empty()
	var typed: Dictionary[String, Variant] = CollisionBootCheck.PINNED_SETTINGS.duplicate()
	typed[CollisionBootCheck.SEPARATE_THREAD_SETTING] = 0
	assert_str(CollisionBootCheck.settings_error(typed)).starts_with("boot: %s is 0" % CollisionBootCheck.SEPARATE_THREAD_SETTING)


func test_boot_settings_missing_value_fails_naming_it() -> void:
	# Arrange
	var settings: Dictionary[String, Variant] = CollisionBootCheck.PINNED_SETTINGS.duplicate()
	settings.erase(CollisionQuery.FACE_INDEX_SETTING)
	# Act
	var problem: String = CollisionBootCheck.settings_error(settings)
	# Assert
	assert_str(problem).is_equal("boot: %s is not set (pinned to true, ADR-0002)" % CollisionQuery.FACE_INDEX_SETTING)


# --- story 003 engine check: binary .res round trip ---------------------------------------------

func test_binary_res_round_trip_keeps_typed_arrays_equal() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	# Act
	_remove_file(ROUND_TRIP_PATH)
	var saved: int = ResourceSaver.save(data, ROUND_TRIP_PATH)
	var magic: PackedByteArray = FileAccess.get_file_as_bytes(ROUND_TRIP_PATH).slice(0, 4)
	var loaded: TrackCollisionData = ResourceLoader.load(ROUND_TRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as TrackCollisionData
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROUND_TRIP_PATH))
	# Assert
	assert_int(saved).is_equal(OK)
	assert_that(magic).is_equal("RSRC".to_ascii_buffer())  # binary, not text
	assert_object(loaded).is_not_null()
	assert_bool(loaded.wall_faces.is_typed()).is_true()
	assert_int(loaded.wall_faces.get_typed_builtin()).is_equal(TYPE_PACKED_VECTOR3_ARRAY)
	assert_bool(loaded.movers.is_typed()).is_true()
	assert_object(loaded.movers.get_typed_script()).is_same(MoverDef)
	assert_that(loaded.ground_faces).is_equal(data.ground_faces)
	assert_that(loaded.surface_of_face).is_equal(data.surface_of_face)
	assert_bool(loaded.wall_faces == data.wall_faces).is_true()
	assert_that(loaded.wall_attr_ids).is_equal(data.wall_attr_ids)
	assert_dict(_snap(loaded)).is_equal(_snap(data))
	for k in data.movers.size():
		assert_object(loaded.movers[k]).is_not_same(data.movers[k])
	assert_str(loaded.layout_error()).is_empty()
