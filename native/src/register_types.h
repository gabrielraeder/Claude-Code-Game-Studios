#pragma once
/// Module registration for dogworks_core (ADR-0007 section 4 "Registration").
/// The entry symbol named in addons/dogworks_core/dogworks_core.gdextension is `dogworks_core_init`.

#include <godot_cpp/godot.hpp>

namespace dogworks {

/// True from `initialize_module(SCENE)` until `uninitialize_module(SCENE)`.
/// godot-cpp caches singleton pointers, so `get_singleton() != nullptr` does not prove a server
/// still exists. Every destructor that frees server RIDs checks this flag and skips when it is clear
/// (ADR-0007 section 4, "Servers-alive flag").
extern bool g_servers_alive;

} // namespace dogworks
