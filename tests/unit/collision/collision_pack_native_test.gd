extends GdUnitTestSuite
## Core-rebuild story 067: the packed schema of MoverDef.pack_native() and TrackCollisionData.pack_native()
## (ADR-0007 section 2) and the native validation of it. One test pins each Resource's schema (keys, order,
## types, units, version); one negative test per key class shows CollisionQuery.validate_packed() and create()
## refusing a missing or wrong-typed key by name.
##
## Key classes: schema_version (int), int, float, bool, Vector3, PackedFloat32Array, PackedVector3Array,
## PackedVector4Array, PackedInt32Array, Array, Dictionary (a mover entry).

const _GUARD = preload("res://tests/unit/native/native_test_guard.gd")
const Fixtures = preload("res://tests/unit/collision/collision_fixtures.gd")

const MOVER_KEYS: Array[String] = ["schema_version", "id", "period", "solid", "surface_id", "wall_attr_id",
		"shape", "half_extents", "radius", "half_height", "key_t", "key_pos", "key_rot"]
const MOVER_TYPES: Array[int] = [TYPE_INT, TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_INT, TYPE_INT,
		TYPE_INT, TYPE_VECTOR3, TYPE_FLOAT, TYPE_FLOAT, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_VECTOR3_ARRAY,
		TYPE_PACKED_VECTOR4_ARRAY]
const TRACK_KEYS: Array[String] = ["schema_version", "ground_faces", "surface_of_face", "wall_faces",
		"wall_attr_ids", "movers"]
const TRACK_TYPES: Array[int] = [TYPE_INT, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_ARRAY,
		TYPE_PACKED_INT32_ARRAY, TYPE_ARRAY]


func before() -> void:
	assert_str(_GUARD.problem()).is_empty()


## A packed track with every key class populated (ground, walls, three movers).
func _packed() -> Dictionary:
	return Fixtures.mirror_fixture().pack_native()


# --- schema pins ---------------------------------------------------------------------------------

func test_mover_pack_native_pins_keys_order_types_and_units() -> void:
	# Arrange
	var mover: MoverDef = Fixtures.all_fields_mover()
	# Act
	var packed: Dictionary = mover.pack_native()
	# Assert: keys in order, each of its type, values in the Resource's units (seconds, metres).
	assert_array(packed.keys()).is_equal(MOVER_KEYS)
	for i in MOVER_KEYS.size():
		assert_int(typeof(packed[MOVER_KEYS[i]])).override_failure_message("key %s" % MOVER_KEYS[i]).is_equal(MOVER_TYPES[i])
	assert_int(packed["schema_version"]).is_equal(MoverDef.NATIVE_SCHEMA_VERSION)
	assert_int(packed["id"]).is_equal(mover.id)
	assert_float(packed["period"]).is_equal(mover.period)
	assert_bool(packed["solid"]).is_equal(mover.solid)
	assert_int(packed["surface_id"]).is_equal(mover.surface_id)
	assert_int(packed["wall_attr_id"]).is_equal(mover.wall_attr_id)
	assert_int(packed["shape"]).is_equal(int(mover.shape))
	assert_vector(packed["half_extents"]).is_equal(mover.half_extents)
	assert_float(packed["radius"]).is_equal(mover.radius)
	assert_float(packed["half_height"]).is_equal(mover.half_height)
	assert_array(packed["key_t"]).is_equal(mover.key_t)
	assert_array(packed["key_pos"]).is_equal(mover.key_pos)
	assert_array(packed["key_rot"]).is_equal(mover.key_rot)


func test_mover_shape_values_match_the_native_enum() -> void:
	# Arrange / Act / Assert: native reads shape as BOX 0, CAPSULE 1, CYLINDER 2.
	assert_int(int(MoverDef.Shape.BOX)).is_equal(0)
	assert_int(int(MoverDef.Shape.CAPSULE)).is_equal(1)
	assert_int(int(MoverDef.Shape.CYLINDER)).is_equal(2)


func test_track_pack_native_pins_keys_order_types_and_layout() -> void:
	# Arrange
	var data: TrackCollisionData = Fixtures.mirror_fixture()
	# Act
	var packed: Dictionary = data.pack_native()
	# Assert
	assert_array(packed.keys()).is_equal(TRACK_KEYS)
	for i in TRACK_KEYS.size():
		assert_int(typeof(packed[TRACK_KEYS[i]])).override_failure_message("key %s" % TRACK_KEYS[i]).is_equal(TRACK_TYPES[i])
	assert_int(packed["schema_version"]).is_equal(TrackCollisionData.NATIVE_SCHEMA_VERSION)
	assert_array(packed["ground_faces"]).is_equal(data.ground_faces)
	assert_array(packed["surface_of_face"]).is_equal(data.surface_of_face)
	assert_int((packed["wall_faces"] as Array).size()).is_equal(data.wall_faces.size())
	assert_array(packed["wall_attr_ids"]).is_equal(data.wall_attr_ids)
	assert_int((packed["movers"] as Array).size()).is_equal(data.movers.size())
	for k in data.movers.size():
		assert_array((packed["movers"][k] as Dictionary).keys()).is_equal(MOVER_KEYS)


func test_schema_versions_of_both_resources_equal_the_native_one() -> void:
	# Arrange / Act / Assert
	assert_int(TrackCollisionData.NATIVE_SCHEMA_VERSION).is_equal(CollisionQuery.PACKED_SCHEMA_VERSION)
	assert_int(MoverDef.NATIVE_SCHEMA_VERSION).is_equal(CollisionQuery.PACKED_SCHEMA_VERSION)


func test_pack_native_of_sound_data_validates_and_creates() -> void:
	# Arrange
	var packed: Dictionary = _packed()
	# Act
	var problem: String = CollisionQuery.validate_packed(packed)
	var query: CollisionQuery = CollisionQuery.create(packed)
	# Assert
	assert_str(problem).is_empty()
	assert_object(query).is_not_null()
	assert_bool(query.has_geometry()).is_true()
	query.dispose()


# --- negative: one per key class -----------------------------------------------------------------------

func test_validate_names_a_missing_top_level_key() -> void:
	for key in TRACK_KEYS:
		# Arrange
		var packed: Dictionary = _packed()
		packed.erase(key)
		# Act / Assert
		assert_str(CollisionQuery.validate_packed(packed)).contains("'%s'" % key).contains("missing")


func test_validate_names_a_wrong_schema_version_value() -> void:
	# Arrange
	var packed: Dictionary = _packed()
	packed["schema_version"] = CollisionQuery.PACKED_SCHEMA_VERSION + 1
	# Act / Assert
	assert_str(CollisionQuery.validate_packed(packed)).contains("'schema_version'")


func test_validate_names_a_wrong_typed_int_key() -> void:
	# Arrange: schema_version as a float (the int key class).
	var packed: Dictionary = _packed()
	packed["schema_version"] = 1.0
	# Act / Assert
	assert_str(CollisionQuery.validate_packed(packed)).contains("'schema_version'").contains("type")


func test_validate_names_a_wrong_typed_packed_array_key() -> void:
	# Arrange: ground_faces as a PackedFloat32Array (the packed-vector class), surface_of_face as an Array.
	var wrong_vectors: Dictionary = _packed()
	wrong_vectors["ground_faces"] = PackedFloat32Array([0.0])
	var wrong_ints: Dictionary = _packed()
	wrong_ints["surface_of_face"] = [1, 2]
	# Act / Assert
	assert_str(CollisionQuery.validate_packed(wrong_vectors)).contains("'ground_faces'")
	assert_str(CollisionQuery.validate_packed(wrong_ints)).contains("'surface_of_face'")


func test_validate_names_a_wrong_typed_array_key() -> void:
	# Arrange: wall_faces as a PackedVector3Array instead of an Array of them.
	var packed: Dictionary = _packed()
	packed["wall_faces"] = PackedVector3Array()
	# Act / Assert
	assert_str(CollisionQuery.validate_packed(packed)).contains("'wall_faces'")


func test_validate_names_a_wrong_typed_wall_entry() -> void:
	# Arrange: a wall entry that is not a PackedVector3Array.
	var packed: Dictionary = _packed()
	(packed["wall_faces"] as Array)[0] = 5
	# Act / Assert
	assert_str(CollisionQuery.validate_packed(packed)).contains("'wall_faces'[0]")


func test_validate_names_a_wrong_typed_mover_entry() -> void:
	# Arrange: the Dictionary key class: a mover entry that is not a Dictionary.
	var packed: Dictionary = _packed()
	(packed["movers"] as Array)[1] = "not a mover"
	# Act / Assert
	assert_str(CollisionQuery.validate_packed(packed)).contains("'movers'[1]").contains("Dictionary")


func test_validate_names_every_missing_mover_key() -> void:
	for key in MOVER_KEYS:
		# Arrange
		var packed: Dictionary = _packed()
		((packed["movers"] as Array)[0] as Dictionary).erase(key)
		# Act / Assert
		assert_str(CollisionQuery.validate_packed(packed)).contains("'movers'[0]").contains("'%s'" % key)


func test_validate_names_every_wrong_typed_mover_key() -> void:
	# One wrong value per key class: int, float, bool, Vector3, PackedFloat32Array, PackedVector3Array,
	# PackedVector4Array. The wrong value is a String, which no key accepts.
	for key in MOVER_KEYS:
		# Arrange
		var packed: Dictionary = _packed()
		((packed["movers"] as Array)[0] as Dictionary)[key] = "wrong"
		# Act / Assert
		assert_str(CollisionQuery.validate_packed(packed)).contains("'movers'[0]").contains("'%s'" % key)


func test_validate_names_an_int_where_a_float_is_required() -> void:
	# Arrange: period as an int (the float key class is strict: no silent int-to-float).
	var packed: Dictionary = _packed()
	((packed["movers"] as Array)[0] as Dictionary)["period"] = 4
	# Act / Assert
	assert_str(CollisionQuery.validate_packed(packed)).contains("'period'")


func test_validate_names_a_mover_layout_problem_by_key() -> void:
	# Arrange: key_t out of order.
	var packed: Dictionary = _packed()
	var mover: Dictionary = (packed["movers"] as Array)[0]
	var key_t: PackedFloat32Array = mover["key_t"]
	key_t = key_t.duplicate()
	key_t[1] = key_t[0]
	mover["key_t"] = key_t
	# Act / Assert
	assert_str(CollisionQuery.validate_packed(packed)).contains("'key_t'")


func test_create_with_a_bad_key_returns_null_and_reports_the_validate_message() -> void:
	# Arrange
	var packed: Dictionary = _packed()
	packed.erase("movers")
	var out: Array[CollisionQuery] = []
	# Act / Assert: the same C++ validation: create() returns null.
	assert_str(CollisionQuery.validate_packed(packed)).contains("'movers'")
	await assert_error(func() -> void: out.append(CollisionQuery.create(packed))).is_push_error("Method/function failed. Returning: Ref<CollisionQuery>()")
	assert_object(out[0]).is_null()


func test_validate_agrees_with_gdscript_layout_error_on_each_rejected_layout() -> void:
	# Arrange: layouts layout_error() rejects; native must reject them too, so create() never builds half a track.
	var short_surface: TrackCollisionData = Fixtures.quadrant_ground([0, 0, 0, 0])
	short_surface.surface_of_face.resize(short_surface.surface_of_face.size() - 1)
	var ragged: TrackCollisionData = Fixtures.quadrant_ground([0, 0, 0, 0])
	ragged.ground_faces.resize(ragged.ground_faces.size() - 1)
	var dup: TrackCollisionData = Fixtures.movers_only([Fixtures.still_box(1, Vector3.ZERO, Vector3.ONE), Fixtures.still_box(1, Vector3.ONE, Vector3.ONE)])
	var bad_shape: MoverDef = Fixtures.still_box(2, Vector3.ZERO, Vector3.ZERO)
	var zero_box: TrackCollisionData = Fixtures.movers_only([bad_shape])
	for data: TrackCollisionData in [short_surface, ragged, dup, zero_box]:
		# Act / Assert
		assert_str(data.layout_error()).is_not_empty()
		assert_str(CollisionQuery.validate_packed(data.pack_native())).is_not_empty()


func test_mover_id_above_int32_max_is_rejected_by_both_validators() -> void:
	# Arrange
	var mover: MoverDef = Fixtures.still_box(MoverDef.MAX_MOVER_ID + 1, Vector3.ZERO, Vector3.ONE)
	var data: TrackCollisionData = Fixtures.movers_only([mover])
	var ok_mover: MoverDef = Fixtures.still_box(MoverDef.MAX_MOVER_ID, Vector3.ZERO, Vector3.ONE)
	# Act / Assert: the limit itself is valid, one above is refused, and the GDScript and native rules agree.
	assert_str(mover.layout_error()).contains("id is %d" % (MoverDef.MAX_MOVER_ID + 1))
	assert_str(CollisionQuery.validate_packed(data.pack_native())).contains("'id'").contains("INT32_MAX")
	assert_str(ok_mover.layout_error()).is_empty()
	assert_str(CollisionQuery.validate_packed(Fixtures.movers_only([ok_mover]).pack_native())).is_empty()


func test_duplicated_constants_equal_the_native_ones() -> void:
	# Arrange / Act / Assert: constants written on both sides (GDScript layout_error, native validation).
	assert_int(MoverDef.MIN_KEYS).is_equal(CollisionQuery.MIN_KEYS)
	assert_int(SurfaceSet.MAX_ID).is_equal(CollisionQuery.MAX_ID)
	assert_int(WallAttrSet.MAX_ID).is_equal(CollisionQuery.MAX_ID)
	assert_int(MoverDef.MAX_MOVER_ID).is_equal(CollisionQuery.MAX_MOVER_ID)
	# UNIT_QUAT_TOLERANCE is a float (no bound constant): a key rotation whose |q|^2 - 1 is just inside it
	# passes both sides, and one just outside fails both.
	var inside: MoverDef = Fixtures.still_box(1, Vector3.ZERO, Vector3.ONE)
	inside.key_rot[0] = Vector4(0.0, 0.0, 0.0, 1.0 + MoverDef.UNIT_QUAT_TOLERANCE * 0.4)
	var outside: MoverDef = Fixtures.still_box(1, Vector3.ZERO, Vector3.ONE)
	outside.key_rot[0] = Vector4(0.0, 0.0, 0.0, 1.0 + MoverDef.UNIT_QUAT_TOLERANCE * 1.6)
	assert_str(inside.layout_error()).is_empty()
	assert_str(CollisionQuery.validate_packed(Fixtures.movers_only([inside]).pack_native())).is_empty()
	assert_str(outside.layout_error()).is_not_empty()
	assert_str(CollisionQuery.validate_packed(Fixtures.movers_only([outside]).pack_native())).is_not_empty()


## One row per mover_layout_error branch: [label, mutator, key the native message must name].
func _layout_rows() -> Array:
	return [
		["id below 1", func(m: MoverDef) -> void: m.id = 0, "'id'"],
		["id above INT32_MAX", func(m: MoverDef) -> void: m.id = MoverDef.MAX_MOVER_ID + 1, "'id'"],
		["period zero", func(m: MoverDef) -> void: m.period = 0.0, "'period'"],
		["period infinite", func(m: MoverDef) -> void: m.period = INF, "'period'"],
		["surface_id above 255", func(m: MoverDef) -> void: m.surface_id = 256, "'surface_id'"],
		["surface_id negative", func(m: MoverDef) -> void: m.surface_id = -1, "'surface_id'"],
		["wall_attr_id above 255", func(m: MoverDef) -> void: m.wall_attr_id = 256, "'wall_attr_id'"],
		["wall_attr_id negative", func(m: MoverDef) -> void: m.wall_attr_id = -1, "'wall_attr_id'"],
		["shape unknown", func(m: MoverDef) -> void: m.shape = 7 as MoverDef.Shape, "'shape'"],
		["BOX extent zero", func(m: MoverDef) -> void: m.half_extents = Vector3(1.0, 0.0, 1.0), "'half_extents'"],
		["key_pos shorter than key_t", func(m: MoverDef) -> void: m.key_pos = PackedVector3Array([Vector3.ZERO]), "key arrays differ"],
		["key_rot longer than key_t", func(m: MoverDef) -> void: m.key_rot = PackedVector4Array([Vector4(0, 0, 0, 1), Vector4(0, 0, 0, 1), Vector4(0, 0, 0, 1)]), "key arrays differ"],
		["one key only", func(m: MoverDef) -> void: m.key_t = PackedFloat32Array([0.0]); m.key_pos = PackedVector3Array([Vector3.ZERO]); m.key_rot = PackedVector4Array([Vector4(0, 0, 0, 1)]), "'key_t'"],
		["key_t[0] negative", func(m: MoverDef) -> void: m.key_t = PackedFloat32Array([-1.0, 1.0]), "'key_t'"],
		["key_t not ascending", func(m: MoverDef) -> void: m.key_t = PackedFloat32Array([1.0, 1.0]), "'key_t'"],
		["last key_t at period", func(m: MoverDef) -> void: m.key_t = PackedFloat32Array([0.0, m.period]), "'key_t'"],
		["key_pos not finite", func(m: MoverDef) -> void: m.key_pos = PackedVector3Array([Vector3.ZERO, Vector3(INF, 0, 0)]), "'key_pos'"],
		["key_rot not unit", func(m: MoverDef) -> void: m.key_rot = PackedVector4Array([Vector4(0, 0, 0, 1), Vector4(0, 0, 0, 2)]), "'key_rot'"],
	]


func test_every_mover_layout_branch_is_rejected_by_both_validators_and_the_native_names_the_key() -> void:
	for row: Array in _layout_rows():
		# Arrange: a sound mover with one field mutated.
		var mover: MoverDef = Fixtures.slide_box(1, Vector3.ZERO, Vector3.ONE)
		assert_str(mover.layout_error()).override_failure_message("the base mover must be sound").is_empty()
		(row[1] as Callable).call(mover)
		var packed: Dictionary = Fixtures.movers_only([mover]).pack_native()
		# Act
		var gd: String = mover.layout_error()
		var native: String = CollisionQuery.validate_packed(packed)
		# Assert
		assert_str(gd).override_failure_message("layout_error empty for: %s" % row[0]).is_not_empty()
		assert_str(native).override_failure_message("validate_packed empty for: %s" % row[0]).is_not_empty()
		assert_str(native).override_failure_message("native message for '%s' does not name %s: %s" % [row[0], row[2], native]).contains(row[2])
