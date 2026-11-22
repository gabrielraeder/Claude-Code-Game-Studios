#include "collision/wall_hit.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void WallHit::_bind_methods() {
	ClassDB::bind_method(D_METHOD("clear"), &WallHit::clear);
	ClassDB::bind_method(D_METHOD("set_point", "value"), &WallHit::set_point);
	ClassDB::bind_method(D_METHOD("get_point"), &WallHit::get_point);
	ClassDB::bind_method(D_METHOD("set_normal", "value"), &WallHit::set_normal);
	ClassDB::bind_method(D_METHOD("get_normal"), &WallHit::get_normal);
	ClassDB::bind_method(D_METHOD("set_wall_attr", "value"), &WallHit::set_wall_attr);
	ClassDB::bind_method(D_METHOD("get_wall_attr"), &WallHit::get_wall_attr);
	ClassDB::bind_method(D_METHOD("set_fraction", "value"), &WallHit::set_fraction);
	ClassDB::bind_method(D_METHOD("get_fraction"), &WallHit::get_fraction);
	ClassDB::bind_method(D_METHOD("set_started_inside", "value"), &WallHit::set_started_inside);
	ClassDB::bind_method(D_METHOD("get_started_inside"), &WallHit::get_started_inside);
	ClassDB::bind_method(D_METHOD("set_collider_id", "value"), &WallHit::set_collider_id);
	ClassDB::bind_method(D_METHOD("get_collider_id"), &WallHit::get_collider_id);
	ClassDB::bind_method(D_METHOD("set_collider_velocity", "value"), &WallHit::set_collider_velocity);
	ClassDB::bind_method(D_METHOD("get_collider_velocity"), &WallHit::get_collider_velocity);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "point"), "set_point", "get_point");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "normal"), "set_normal", "get_normal");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "wall_attr"), "set_wall_attr", "get_wall_attr");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "fraction"), "set_fraction", "get_fraction");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "started_inside"), "set_started_inside", "get_started_inside");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "collider_id"), "set_collider_id", "get_collider_id");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "collider_velocity"), "set_collider_velocity", "get_collider_velocity");
}

void WallHit::clear() {
	point = Vector3();
	normal = Vector3();
	wall_attr = dogworks::WALL_ATTR_NONE;
	fraction = 1.0;
	started_inside = false;
	collider_id = 0;
	collider_velocity = Vector3();
}
