#include "collision/query_cursor.h"

#include "collision/collision_constants.h"
#include "register_types.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <vector>

using namespace godot;

namespace {
/// Every live cursor (they hold engine Resources). Touched only in the constructor, the destructor and the
/// release-all path (load time, main thread), never per tick.
std::vector<QueryCursor *> &cursor_owners() {
	static std::vector<QueryCursor *> list;
	return list;
}
} // namespace

void QueryCursor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_built"), &QueryCursor::is_built);
	ClassDB::bind_method(D_METHOD("get_ray_params"), &QueryCursor::get_ray_params);
	ClassDB::bind_method(D_METHOD("get_ray_result"), &QueryCursor::get_ray_result);
	ClassDB::bind_method(D_METHOD("get_sphere"), &QueryCursor::get_sphere);
	ClassDB::bind_method(D_METHOD("get_shape_params"), &QueryCursor::get_shape_params);
	ClassDB::bind_method(D_METHOD("get_cast_result"), &QueryCursor::get_cast_result);
	ClassDB::bind_method(D_METHOD("get_rest_result"), &QueryCursor::get_rest_result);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "ray_params", PROPERTY_HINT_RESOURCE_TYPE, "PhysicsRayQueryParameters3D", PROPERTY_USAGE_NONE), "", "get_ray_params");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "ray_result", PROPERTY_HINT_RESOURCE_TYPE, "PhysicsIntersectRayResult3D", PROPERTY_USAGE_NONE), "", "get_ray_result");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "sphere", PROPERTY_HINT_RESOURCE_TYPE, "SphereShape3D", PROPERTY_USAGE_NONE), "", "get_sphere");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "shape_params", PROPERTY_HINT_RESOURCE_TYPE, "PhysicsShapeQueryParameters3D", PROPERTY_USAGE_NONE), "", "get_shape_params");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "cast_result", PROPERTY_HINT_RESOURCE_TYPE, "PhysicsCastMotionResult3D", PROPERTY_USAGE_NONE), "", "get_cast_result");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "rest_result", PROPERTY_HINT_RESOURCE_TYPE, "PhysicsGetRestInfoResult3D", PROPERTY_USAGE_NONE), "", "get_rest_result");
}

QueryCursor::QueryCursor() {
	if (!dogworks::g_servers_alive) {
		return;
	}
	ray_params.instantiate();
	ray_result.instantiate();
	sphere.instantiate();
	shape_params.instantiate();
	cast_result.instantiate();
	rest_result.instantiate();
	ray_params->set_collision_mask((uint32_t)dogworks::GROUND_LAYER);
	ray_params->set_hit_back_faces(false);
	ray_params->set_hit_from_inside(false);
	ray_params->set_collide_with_areas(false);
	ray_params->set_collide_with_bodies(true);
	shape_params->set_shape(sphere);
	shape_params->set_collision_mask((uint32_t)dogworks::WALL_LAYER);
	shape_params->set_margin(0.0f);
	shape_params->set_collide_with_areas(false);
	shape_params->set_collide_with_bodies(true);
	built = true;
	cursor_owners().push_back(this);
}

QueryCursor::~QueryCursor() {
	std::vector<QueryCursor *> &list = cursor_owners();
	list.erase(std::remove(list.begin(), list.end(), this), list.end());
}

void QueryCursor::release_all_engine_objects() {
	// Copy first: nothing edits the registry here, but a Ref release can run a destructor. Load time only.
	const std::vector<QueryCursor *> snapshot = cursor_owners();
	for (QueryCursor *cursor : snapshot) {
		cursor->ray_params.unref();
		cursor->ray_result.unref();
		cursor->sphere.unref();
		cursor->shape_params.unref();
		cursor->cast_result.unref();
		cursor->rest_result.unref();
		cursor->built = false;
	}
	cursor_owners().clear();
}

Ref<PhysicsRayQueryParameters3D> QueryCursor::get_ray_params() const {
	ERR_FAIL_COND_V(!built, Ref<PhysicsRayQueryParameters3D>());
	return ray_params;
}

Ref<PhysicsIntersectRayResult3D> QueryCursor::get_ray_result() const {
	ERR_FAIL_COND_V(!built, Ref<PhysicsIntersectRayResult3D>());
	return ray_result;
}

Ref<SphereShape3D> QueryCursor::get_sphere() const {
	ERR_FAIL_COND_V(!built, Ref<SphereShape3D>());
	return sphere;
}

Ref<PhysicsShapeQueryParameters3D> QueryCursor::get_shape_params() const {
	ERR_FAIL_COND_V(!built, Ref<PhysicsShapeQueryParameters3D>());
	return shape_params;
}

Ref<PhysicsCastMotionResult3D> QueryCursor::get_cast_result() const {
	ERR_FAIL_COND_V(!built, Ref<PhysicsCastMotionResult3D>());
	return cast_result;
}

Ref<PhysicsGetRestInfoResult3D> QueryCursor::get_rest_result() const {
	ERR_FAIL_COND_V(!built, Ref<PhysicsGetRestInfoResult3D>());
	return rest_result;
}
