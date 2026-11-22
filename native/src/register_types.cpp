#include "register_types.h"

#include "collision/collision_query.h"
#include "collision/ground_hit.h"
#include "collision/query_cursor.h"
#include "collision/wall_hit.h"
#include "core/dogworks_core.h"
#include "core/toolchain_probe.h"
#include "race/race_sim.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

namespace dogworks {
bool g_servers_alive = false;
} // namespace dogworks

/// Registers every class at the SCENE level (not RUNTIME: editor-time @tool code must reach them).
/// `DogworksCore` goes first (ADR-0007 section 4); bases and result types precede the classes using them.
static void initialize_dogworks_core(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(DogworksCore);
	GDREGISTER_CLASS(ToolchainProbe);
	// Result and base types before the class whose API uses them (ADR-0007 section 4).
	GDREGISTER_CLASS(GroundHit);
	GDREGISTER_CLASS(WallHit);
	GDREGISTER_CLASS(QueryCursor);
	GDREGISTER_CLASS(CollisionQuery);
	GDREGISTER_CLASS(RaceSim);
	dogworks::g_servers_alive = true;
}

/// Frees the server objects of every live RID owner (hot reload and exit), then clears the
/// servers-alive flag so destructors that run later skip their RID frees. The servers are still
/// alive at the SCENE level: godot-cpp calls the terminator before `ClassDB::deinitialize`
/// (native/godot-cpp/src/godot.cpp, `deinitialize_level`).
static void uninitialize_dogworks_core(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	ToolchainProbe::release_all_server_objects();
	CollisionQuery::release_all_server_objects();
	QueryCursor::release_all_engine_objects();
	RaceSim::release_all();
	dogworks::g_servers_alive = false;
}

extern "C" {
GDExtensionBool GDE_EXPORT dogworks_core_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_dogworks_core);
	init_obj.register_terminator(uninitialize_dogworks_core);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
