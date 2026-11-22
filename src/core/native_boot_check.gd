extends RefCounted
## Boot refusal for the native core (ADR-0007 section 7, "Boot refusal moves out of
## CollisionBootCheck"). This script names NO native type, so it parses and runs when the
## extension is missing; every script that names a native type fails to parse then.
## Call it before any native-typed script is loaded, and load those scripts with load() only
## after it returns "".
##
## Checks, in order:
##  1. ClassDB.class_exists("DogworksCore"): the extension is loaded.
##  2. Through ClassDB.class_call_static (after class_has_method and a type check), sim_hz() * SIM_DT == 1.0
##     and sim_hz() equals physics_ticks_per_second (ADR-0007 section 4, SIM_DT).
##  3. Editor builds only: the source hash recomputed with FileAccess equals DogworksCore.source_hash().

const _SOURCE_HASH = preload("res://addons/dogworks_core/source_hash.gd")

## GDScript side of SIM_DT (ADR-0001 section 5). Native has its own constexpr from SIM_HZ.
const SIM_DT: float = 1.0 / 60.0
## The class whose presence proves the extension loaded.
const ANCHOR_CLASS: StringName = &"DogworksCore"
## Named in every refusal.
const FIX: String = "run tools/build_native.sh"

## Microseconds the source-hash recompute took on the last [method check] (0 when it did not run).
static var last_hash_usec: int = 0


## Returns "" when the native core is loaded and fresh, otherwise one message naming the cause and
## [code]tools/build_native.sh[/code]. [param anchor_class] and [param source_hash_override] exist for
## tests only (a non-empty override replaces the hash the DLL reports).
static func check(anchor_class: StringName = ANCHOR_CLASS, source_hash_override: String = "") -> String:
	last_hash_usec = 0
	if not ClassDB.class_exists(anchor_class):
		return "native extension is not loaded (class %s is missing); %s" % [anchor_class, FIX]
	var hz_value: Variant = _SOURCE_HASH.call_static_checked(anchor_class, &"sim_hz", TYPE_INT)
	if hz_value == null:
		return "native build is incompatible: %s; %s" % [_SOURCE_HASH.last_error, FIX]
	var hz: int = hz_value
	if hz <= 0 or float(hz) * SIM_DT != 1.0:
		return "sim_hz() is %d but SIM_DT is 1/60; the DLL and the GDScript disagree; %s" % [hz, FIX]
	var ticks: int = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"))
	if hz != ticks:
		return "sim_hz() is %d but physics_ticks_per_second is %d" % [hz, ticks]
	if OS.has_feature("editor"):
		var native_sh: String = source_hash_override
		if native_sh.is_empty():
			var sh_value: Variant = _SOURCE_HASH.call_static_checked(anchor_class, &"source_hash", TYPE_STRING)
			if sh_value == null:
				return "native build is incompatible: %s; %s" % [_SOURCE_HASH.last_error, FIX]
			native_sh = sh_value
		var problem: String = _SOURCE_HASH.problem(native_sh)
		last_hash_usec = _SOURCE_HASH.last_compute_usec
		if not problem.is_empty():
			return problem
	return ""
