#pragma once
/// ToolchainProbe: a small test-only class that proves the toolchain end to end (story 066):
/// the bound static factory pair `validate_packed` / `create`, the `built` guard on every bound
/// method, server RID ownership and teardown, and double-buffered packed outputs. No production
/// code calls it.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace godot {

/// Test-only native object. `.new()` gives an unbuilt object whose bound methods all refuse;
/// `ToolchainProbe.create(packed)` gives a built one that owns one physics space, shape and body.
///
/// Hot reload: when the extension is unloaded (a rebuilt debug DLL in the editor), every live
/// RID owner has its server objects freed and its `built` flag cleared, before the servers-alive
/// flag drops (`release_all_server_objects`). After a reload the GDScript side must call
/// `create()` again; an old reference is an unbuilt object whose methods refuse.
class ToolchainProbe : public RefCounted {
	GDCLASS(ToolchainProbe, RefCounted)

public:
	/// Upper bound on the output length accepted by `validate_packed`.
	static constexpr int64_t MAX_COUNT = 4096;

	/// GDScript: `ToolchainProbe.validate_packed(packed: PackedFloat64Array) -> String`.
	/// `packed` is `[output_length, rid_servers]`: output_length in 1..4096 and rid_servers 0 or 1
	/// (1 = create server RIDs). Returns "" when valid, otherwise a message naming the key.
	static String validate_packed(const PackedFloat64Array &p_packed);
	/// GDScript: `ToolchainProbe.create(packed: PackedFloat64Array) -> ToolchainProbe`.
	/// Runs the same validation as `validate_packed`; returns null (with an error) on failure.
	static Ref<ToolchainProbe> create(const PackedFloat64Array &p_packed);
	/// GDScript: `ToolchainProbe.live_rid_count() -> int`. Test-only: server RIDs currently owned by
	/// every probe (3 per probe created with rid_servers = 1). A test asserts it returns to its baseline.
	static int64_t live_rid_count();
	/// GDScript: `ToolchainProbe.crash_for_test() -> void`. Test-only: writes through a null pointer so a crash repro
	/// has a native stack with a known function name. Refuses (error, no crash) unless `OS.has_feature("debug")`.
	/// Never called from the regular test suite or from regression (core_greps enforces it for tests/).
	static void crash_for_test();
	/// Frees the server objects of every live probe and clears their `built` flag (hot reload and exit).
	/// Called from `uninitialize_module(SCENE)` before the servers-alive flag is cleared. Not bound.
	static void release_all_server_objects();

	/// GDScript: `is_built() -> bool`. The only bound method that does not guard on `built`.
	bool is_built() const;
	/// GDScript: `get_output_length() -> int`. Length of each output buffer.
	int64_t get_output_length() const;
	/// GDScript: `echo_int(value: int) -> int`. Returns the argument; measures a scalar crossing.
	int64_t echo_int(int64_t p_value) const;
	/// GDScript: `echo_scalar(value: float) -> float`. Returns the argument.
	double echo_scalar(double p_value) const;
	/// GDScript: `echo_vector3(value: Vector3) -> Vector3`. Returns the argument.
	Vector3 echo_vector3(const Vector3 &p_value) const;
	/// GDScript: `sum_packed(values: PackedFloat32Array) -> float`. Sums through `ptr()`; never stores or writes
	/// the array. An empty array returns 0 without calling `ptr()` (ptr() on an empty array is not guaranteed valid).
	double sum_packed(const PackedFloat32Array &p_values) const;
	/// GDScript: `step(tick: int) -> void`. Fills the output buffer `tick & 1` (no allocation).
	void step(int64_t p_tick);
	/// GDScript: `output() -> PackedFloat32Array`. The buffer filled by the last `step`.
	PackedFloat32Array output() const;
	/// GDScript: `rid_count() -> int`. Number of live server RIDs this object owns.
	int64_t rid_count() const;
	/// GDScript: `dispose() -> void`. Frees the server RIDs (body, shape, space) and clears `built`.
	/// Idempotent by design: on an unbuilt or already disposed object it does nothing and prints nothing,
	/// so a test teardown or a composition root can call it without tracking state. This is the one bound
	/// method that does not refuse on `!built` (see .claude/rules/native-code.md).
	void dispose();

	ToolchainProbe() = default;
	~ToolchainProbe();

protected:
	/// Binds the methods.
	static void _bind_methods();

private:
	/// Frees body, then shape, then space; skips when the servers are gone. Static so a destructor can call it.
	static void free_server_objects(RID p_body, RID p_shape, RID p_space);
	/// Frees this object's server objects, zeroes the RIDs and leaves the registry. Used by dispose, the destructor and the release-all path.
	void release_server_objects();

	bool built = false;
	int64_t output_length = 0;
	int64_t last_tick = 0;
	int64_t owned_rids = 0;
	bool registered = false;
	PackedFloat32Array buffers[2];
	RID space;
	RID shape;
	RID body;
};

} // namespace godot
