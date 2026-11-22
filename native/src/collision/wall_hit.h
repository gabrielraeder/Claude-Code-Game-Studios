#pragma once
/// WallHit: the result of one `CollisionQuery.sweep_walls` (ADR-0002 "Queries per kart per tick").

#include "collision/collision_constants.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

/// One per kart, built once with `WallHit.new()` and reused every tick. `sweep_walls` writes every
/// field when it returns true and leaves them untouched on a miss. Three kinds of hit, told apart by
/// `fraction` and `started_inside`: started_inside (fraction 0, an overlap at `from`), a touch
/// (fraction 1.0, not started_inside) and a blocking hit (0 <= fraction < 1). Main thread only.
class WallHit : public RefCounted {
	GDCLASS(WallHit, RefCounted)

public:
	/// World position of the contact, on the wall surface.
	Vector3 point;
	/// Contact normal (unit length), from the wall toward the sphere centre.
	Vector3 normal;
	/// Stable wall-attribute id of the wall hit, a mover's wall_attr_id, or WALL_ATTR_NONE (-1).
	int64_t wall_attr = dogworks::WALL_ATTR_NONE;
	/// Fraction (0..1) of the motion the sphere can travel before the contact.
	double fraction = 1.0;
	/// True when the sphere already overlapped a wall at `from` (no cast ran).
	bool started_inside = false;
	/// 0 = static wall; otherwise the mover id (>= 1).
	int64_t collider_id = 0;
	/// Velocity of the collider at the contact point (zero for static walls).
	Vector3 collider_velocity;

	/// GDScript: `clear() -> void`. Resets every field to its default (no wall, full move). Allocation-free.
	void clear();

	/// GDScript property `point`.
	void set_point(const Vector3 &p_value) { point = p_value; }
	/// GDScript property `point`.
	Vector3 get_point() const { return point; }
	/// GDScript property `normal`.
	void set_normal(const Vector3 &p_value) { normal = p_value; }
	/// GDScript property `normal`.
	Vector3 get_normal() const { return normal; }
	/// GDScript property `wall_attr`.
	void set_wall_attr(int64_t p_value) { wall_attr = p_value; }
	/// GDScript property `wall_attr`.
	int64_t get_wall_attr() const { return wall_attr; }
	/// GDScript property `fraction`.
	void set_fraction(double p_value) { fraction = p_value; }
	/// GDScript property `fraction`.
	double get_fraction() const { return fraction; }
	/// GDScript property `started_inside`.
	void set_started_inside(bool p_value) { started_inside = p_value; }
	/// GDScript property `started_inside`.
	bool get_started_inside() const { return started_inside; }
	/// GDScript property `collider_id`.
	void set_collider_id(int64_t p_value) { collider_id = p_value; }
	/// GDScript property `collider_id`.
	int64_t get_collider_id() const { return collider_id; }
	/// GDScript property `collider_velocity`.
	void set_collider_velocity(const Vector3 &p_value) { collider_velocity = p_value; }
	/// GDScript property `collider_velocity`.
	Vector3 get_collider_velocity() const { return collider_velocity; }

protected:
	/// Binds the properties and `clear`.
	static void _bind_methods();
};

} // namespace godot
