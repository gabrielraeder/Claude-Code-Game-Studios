#pragma once
/// DogworksCore: the toolchain anchor class of the dogworks_core extension (ADR-0007 section 4).
/// It carries only static, constant-time facts: the tick rate, the build hashes and the build
/// target. It owns no state.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

/// Static facts of the native build. Built with `.new()` (no arguments) when an instance is needed.
class DogworksCore : public RefCounted {
	GDCLASS(DogworksCore, RefCounted)

public:
	/// Simulation ticks per second. `SIM_DT` is derived from it and never bound (class constants are integer-only).
	static constexpr int SIM_HZ = 60;
	/// Seconds per simulation tick. Native-side constant; GDScript keeps its own `SIM_DT` const.
	static constexpr double SIM_DT = 1.0 / SIM_HZ;

	/// GDScript: `DogworksCore.sim_hz() -> int`. Returns SIM_HZ (60).
	static int64_t sim_hz();
	/// GDScript: `DogworksCore.build_hash() -> String`. The full hash (FH) stored in this DLL's marker.
	static String build_hash();
	/// GDScript: `DogworksCore.source_hash() -> String`. The source hash (SH) stored in this DLL's marker.
	static String source_hash();
	/// GDScript: `DogworksCore.build_target() -> String`. "debug", "release" or "bench".
	static String build_target();
	/// GDScript: `DogworksCore.hot_reload_text() -> String`. A literal an editor session reads before and
	/// after a rebuild to see that a hot reload took effect (story 066, Verification Required 3).
	static String hot_reload_text();

protected:
	/// Binds the static methods.
	static void _bind_methods();

private:
	/// Returns part `p_index` of the marker split on ':' (1 target, 2 SH, 3 FH). Load-time only: it allocates.
	static String marker_part(int p_index);
};

} // namespace godot
