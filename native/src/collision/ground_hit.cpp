#include "collision/ground_hit.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void GroundHit::_bind_methods() {
	ClassDB::bind_method(D_METHOD("clear"), &GroundHit::clear);
	ClassDB::bind_method(D_METHOD("set_point", "value"), &GroundHit::set_point);
	ClassDB::bind_method(D_METHOD("get_point"), &GroundHit::get_point);
	ClassDB::bind_method(D_METHOD("set_normal", "value"), &GroundHit::set_normal);
	ClassDB::bind_method(D_METHOD("get_normal"), &GroundHit::get_normal);
	ClassDB::bind_method(D_METHOD("set_surface_id", "value"), &GroundHit::set_surface_id);
	ClassDB::bind_method(D_METHOD("get_surface_id"), &GroundHit::get_surface_id);
	ClassDB::bind_method(D_METHOD("set_collider_id", "value"), &GroundHit::set_collider_id);
	ClassDB::bind_method(D_METHOD("get_collider_id"), &GroundHit::get_collider_id);
	ClassDB::bind_method(D_METHOD("set_collider_velocity", "value"), &GroundHit::set_collider_velocity);
	ClassDB::bind_method(D_METHOD("get_collider_velocity"), &GroundHit::get_collider_velocity);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "point"), "set_point", "get_point");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "normal"), "set_normal", "get_normal");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "surface_id"), "set_surface_id", "get_surface_id");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "collider_id"), "set_collider_id", "get_collider_id");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "collider_velocity"), "set_collider_velocity", "get_collider_velocity");
}

void GroundHit::clear() {
	point = Vector3();
	normal = Vector3(0, 1, 0);
	surface_id = dogworks::SURFACE_NONE;
	collider_id = 0;
	collider_velocity = Vector3();
}
