class_name CollisionBootCheck
extends RefCounted
## The collision boot and load checks of the core rebuild (ADR-0002 "Boot and load checks",
## ADR-0001 section 5; core-rebuild story 006). Static functions only. The composition root calls
## assert_boot_settings() once at boot, and checked_query() once per track load and asserts on its
## problem: both checks are blocking (a wrong setting or an unknown id must fail loudly, never reach
## Driving). checked_query() is the ONLY place under src/ that builds a CollisionQuery
## (tools/core_greps.sh enforces it), so no unchecked query exists; tests and tools may build one
## directly.
## Main thread only (the load check casts through CollisionQuery; the settings are read at boot).
## [codeblock]
## # Boot:
## CollisionBootCheck.assert_boot_settings()
## # Track load (composition root, importer):
## var surfaces: SurfaceSet = SurfaceSet.load_checked(SurfaceSet.CORE_PATH)
## var walls: WallAttrSet = WallAttrSet.load_checked(WallAttrSet.CORE_PATH)
## var checked: CollisionBootCheck.CheckedQuery = CollisionBootCheck.checked_query(data, surfaces, walls,
##         limits.probe_max_drop_m)
## assert(checked.problem.is_empty(), checked.problem)
## var query: CollisionQuery = checked.query  # null when the check failed
## [/codeblock]


## The result of checked_query(): either a checked [member query] and an empty [member problem], or
## a null query (already disposed) and the reason. Plain data; main thread only, like the query.
## [codeblock]
## var checked: CollisionBootCheck.CheckedQuery = CollisionBootCheck.checked_query(data, surfaces, walls, drop)
## if checked.query == null:
##     push_error(checked.problem)
## [/codeblock]
class CheckedQuery:
	extends RefCounted
	## The query, built and load-checked; null when the check failed. The owner calls dispose() on
	## it at track unload.
	var query: CollisionQuery = null
	## "" on success, otherwise the load_error() sentence.
	var problem: String = ""

## Physics engine setting (ADR-0002). Read through ProjectSettings: the server class name does not
## reveal the engine.
const ENGINE_SETTING: String = "physics/3d/physics_engine"
## Physics-on-a-separate-thread setting (ADR-0002: queries run on the main thread).
const SEPARATE_THREAD_SETTING: String = "physics/3d/run_on_separate_thread"
## Jolt face-index setting ground surface ids need (ADR-0002): with it off, Jolt reports no face index.
const FACE_INDEX_SETTING: String = "physics/jolt_physics_3d/queries/enable_ray_cast_face_index"
## Tick rate setting (ADR-0001 section 5). Read from Engine, the runtime value.
const TICKS_SETTING: String = "physics/common/physics_ticks_per_second"
## Catch-up cap setting (ADR-0001 section 5). Read from Engine, the runtime value.
const MAX_STEPS_SETTING: String = "physics/common/max_physics_steps_per_frame"
## Engine physics interpolation setting (ADR-0001 section 5: off, the game interpolates itself).
const INTERPOLATION_SETTING: String = "physics/common/physics_interpolation"
## Physics jitter fix setting (ADR-0001 section 5, Verification Required 2).
const JITTER_FIX_SETTING: String = "physics/common/physics_jitter_fix"

## The pinned value of each setting (ADR-0002 Backend and ownership; ADR-0001 section 5). Pinned by
## the ADRs, not tuning: changing one is an ADR change.
const PINNED_SETTINGS: Dictionary[String, Variant] = {
	ENGINE_SETTING: "Jolt Physics",
	FACE_INDEX_SETTING: true,
	SEPARATE_THREAD_SETTING: false,
	TICKS_SETTING: 60,
	MAX_STEPS_SETTING: 8,
	INTERPOLATION_SETTING: false,
	JITTER_FIX_SETTING: 0.0,
}
## The ADR that pins each key of PINNED_SETTINGS, for the failure message.
const PINNED_BY: Dictionary[String, String] = {
	ENGINE_SETTING: "ADR-0002",
	FACE_INDEX_SETTING: "ADR-0002",
	SEPARATE_THREAD_SETTING: "ADR-0002",
	TICKS_SETTING: "ADR-0001 section 5",
	MAX_STEPS_SETTING: "ADR-0001 section 5",
	INTERPOLATION_SETTING: "ADR-0001 section 5",
	JITTER_FIX_SETTING: "ADR-0001 section 5",
}


## The current value of every PINNED_SETTINGS key: the tick rate and catch-up cap from Engine (the
## runtime values ADR-0001 section 5 asserts), the rest from ProjectSettings. Allocates: boot only.
## [codeblock]
## var now: Dictionary[String, Variant] = CollisionBootCheck.current_settings()
## print(now[CollisionBootCheck.TICKS_SETTING])  # 60
## [/codeblock]
static func current_settings() -> Dictionary[String, Variant]:
	var now: Dictionary[String, Variant] = {}
	now[ENGINE_SETTING] = ProjectSettings.get_setting(ENGINE_SETTING, "")
	now[FACE_INDEX_SETTING] = ProjectSettings.get_setting(FACE_INDEX_SETTING, false)
	now[SEPARATE_THREAD_SETTING] = ProjectSettings.get_setting(SEPARATE_THREAD_SETTING, true)
	now[TICKS_SETTING] = Engine.physics_ticks_per_second
	now[MAX_STEPS_SETTING] = Engine.max_physics_steps_per_frame
	now[INTERPOLATION_SETTING] = ProjectSettings.get_setting(INTERPOLATION_SETTING, true)
	now[JITTER_FIX_SETTING] = ProjectSettings.get_setting(JITTER_FIX_SETTING, -1.0)
	return now


## Checks [param settings] (a current_settings() snapshot, or a test's) against PINNED_SETTINGS.
## Returns "" when every pinned key holds its value, otherwise one sentence naming the first key that
## is missing or differs, its value, the pinned value and the ADR. int and float compare as numbers;
## any other type mismatch is a difference. Pure: safe from any thread.
## [codeblock]
## var problem: String = CollisionBootCheck.settings_error(CollisionBootCheck.current_settings())
## [/codeblock]
static func settings_error(settings: Dictionary[String, Variant]) -> String:
	for key: String in PINNED_SETTINGS:
		var expected: Variant = PINNED_SETTINGS[key]
		if not settings.has(key):
			return "boot: %s is not set (pinned to %s, %s)" % [key, var_to_str(expected), PINNED_BY[key]]
		var actual: Variant = settings[key]
		if not CollisionBootCheck._same_value(actual, expected):
			return "boot: %s is %s, pinned to %s (%s)" % [key, var_to_str(actual), var_to_str(expected), PINNED_BY[key]]
	return ""


## The boot assert the composition root calls once (ADR-0002, ADR-0001 section 5): checks
## current_settings(). On a difference it push_errors and asserts (debug builds stop there); it
## returns the problem ("" when sound) so a release build can still refuse to start.
## [codeblock]
## if not CollisionBootCheck.assert_boot_settings().is_empty():
##     get_tree().quit(1)  # release build: refuse to run with the wrong physics settings
## [/codeblock]
static func assert_boot_settings() -> String:
	var problem: String = settings_error(current_settings())
	if not problem.is_empty():
		push_error("CollisionBootCheck: %s" % problem)
	assert(problem.is_empty(), "CollisionBootCheck: %s" % problem)
	return problem


## The track-load check (ADR-0002 "Boot and load checks"; story 006). Returns "" when [param data]
## is sound for [param query] (built from it), otherwise one sentence; the composition root asserts.
## Order: (1) [param query] or [param data] null; (2) the probe cast query.probe_error() runs on
## EVERY load, an empty query included (story 003 LP review); (3) data.layout_error(), reported
## with the probe's result, because a rejected layout built an empty query; (4)
## data.id_error([param surfaces], [param walls]), blocking; (5) the probe's result.
## [param probe_max_drop] is the probe cast length (m, > 0): ADR-0005's TrackImportLimits
## .probe_max_drop_m once that exists. Game code calls checked_query() instead, which runs this and
## disposes a failing query; call this directly only with a query you built yourself (tests,
## tools). Allocates: load time only. Main thread only.
## [codeblock]
## var query: CollisionQuery = CollisionQuery.create(data.pack_native())  # tools/ and tests/ only
## var problem: String = CollisionBootCheck.load_error(query, data, surfaces, walls, limits.probe_max_drop_m)
## if not problem.is_empty():
##     query.dispose()  # never keep, or drop without dispose(), a query that failed its check
##     push_error(problem)
## [/codeblock]
static func load_error(query: CollisionQuery, data: TrackCollisionData, surfaces: SurfaceSet,
		walls: WallAttrSet, probe_max_drop: float) -> String:
	if query == null:
		return "load check: no CollisionQuery"
	if data == null:
		return "load check: no TrackCollisionData"
	var probe: String = query.probe_error(data.probe_point, data.probe_surface_id, probe_max_drop)
	var layout: String = data.layout_error()
	if not layout.is_empty():
		return "load check: TrackCollisionData layout: %s; %s" % [layout, probe if not probe.is_empty() else "load probe passed"]
	var ids: String = data.id_error(surfaces, walls)
	if not ids.is_empty():
		return "load check: %s" % ids
	if not probe.is_empty():
		return "load check: %s" % probe
	return ""


## Builds the CollisionQuery of [param data] (CollisionQuery.validate_packed, then create) and runs load_error() on it (ADR-0002 "Boot and load
## checks"; story 006 LP review). On success returns a CheckedQuery holding the query and an empty
## problem; on failure disposes the query (bodies, shapes, space) and returns a CheckedQuery with a
## null query and the reason. It never push_errors or asserts itself: the caller (composition root,
## importer) asserts on the problem. The only builder of a CollisionQuery under src/
## (tools/core_greps.sh). Arguments as for load_error(). Allocates: load time only. Main thread only.
## [codeblock]
## var checked: CollisionBootCheck.CheckedQuery = CollisionBootCheck.checked_query(data, surfaces, walls,
##         limits.probe_max_drop_m)
## assert(checked.problem.is_empty(), checked.problem)
## _query = checked.query
## # ... at track unload:
## _query.dispose()
## [/codeblock]
static func checked_query(data: TrackCollisionData, surfaces: SurfaceSet, walls: WallAttrSet,
		probe_max_drop: float) -> CheckedQuery:
	var result: CheckedQuery = CheckedQuery.new()
	if data == null:
		result.problem = "load check: no TrackCollisionData"
		return result
	var layout: String = data.layout_error()
	if not layout.is_empty():
		# A rejected layout builds no query (the native create refuses it), so no probe ran.
		result.problem = "load check: TrackCollisionData layout: %s; no query built (layout rejected)" % layout
		return result
	var packed: Dictionary = data.pack_native()
	var packed_problem: String = CollisionQuery.validate_packed(packed)
	if not packed_problem.is_empty():
		result.problem = "load check: native packed data: %s" % packed_problem
		return result
	var query: CollisionQuery = CollisionQuery.create(packed)
	if query == null:
		result.problem = "load check: CollisionQuery.create failed (see the engine error)"
		return result
	var problem: String = load_error(query, data, surfaces, walls, probe_max_drop)
	if not problem.is_empty():
		query.dispose()
		result.problem = problem
		return result
	result.query = query
	return result


## True when [param actual] equals [param expected]: numbers (int or float) by value, anything else
## only with the same type.
static func _same_value(actual: Variant, expected: Variant) -> bool:
	var numeric: Array[int] = [TYPE_INT, TYPE_FLOAT]
	if typeof(actual) in numeric and typeof(expected) in numeric:
		return float(actual) == float(expected)
	if typeof(actual) != typeof(expected):
		return false
	return actual == expected
