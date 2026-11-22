#include "dogworks_core.h"

#include "build_marker.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

using namespace godot;

void DogworksCore::_bind_methods() {
	ClassDB::bind_static_method(get_class_static(), D_METHOD("sim_hz"), &DogworksCore::sim_hz);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("build_hash"), &DogworksCore::build_hash);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("source_hash"), &DogworksCore::source_hash);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("build_target"), &DogworksCore::build_target);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("hot_reload_text"), &DogworksCore::hot_reload_text);
}

int64_t DogworksCore::sim_hz() {
	return SIM_HZ;
}

/// Load-time and tool-time only: it allocates a String and a PackedStringArray on every call, so it
/// must never run in a per-tick path.
String DogworksCore::marker_part(int p_index) {
	// Fields sit at fixed positions in "<tag>:<target>:<SH>:<FH>:END".
	PackedStringArray parts = String::utf8(dogworks_build_marker).split(":");
	ERR_FAIL_COND_V(parts.size() != 5, String());
	return parts[p_index];
}

String DogworksCore::build_hash() {
	return marker_part(3);
}

String DogworksCore::source_hash() {
	return marker_part(2);
}

String DogworksCore::build_target() {
	return marker_part(1);
}

String DogworksCore::hot_reload_text() {
	return "hot-reload text A";
}
