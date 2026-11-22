#pragma once
/// GroundHit: the result of one `CollisionQuery.cast_ground` (ADR-0002 "Queries per kart per tick").

#include "collision/collision_constants.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

/// One per probe, built once with `GroundHit.new()` and reused every tick. `cast_ground` writes every
/// field when it returns true and leaves them untouched on a miss. Main thread only.
/// Fields are public so the native query writes them without a bound call; GDScript reads and writes
/// them as properties.
class GroundHit : public RefCounted {
	GDCLASS(GroundHit, RefCounted)

public:
	/// World position of the hit.
	Vector3 point;
	/// Surface normal at the hit (unit length, facing the ray).
	Vector3 normal = Vector3(0, 1, 0);
	/// Stable surface id of the triangle hit, or SURFACE_NONE (-1); a mover hit reports the mover's surface_id.
	int64_t surface_id = dogworks::SURFACE_NONE;
	/// 0 = static ground; otherwise the mover id (>= 1).
	int64_t collider_id = 0;
	/// Velocity of the collider at the hit point (zero for static ground).
	Vector3 collider_velocity;

	/// GDScript: `clear() -> void`. Resets every field to its default (a miss-like state). Allocation-free.
	void clear();

	/// GDScript property `point`.
	void set_point(const Vector3 &p_value) { point = p_value; }
	/// GDScript property `point`.
	Vector3 get_point() const { return point; }
	/// GDScript property `normal`.
	void set_normal(const Vector3 &p_value) { normal = p_value; }
	/// GDScript property `normal`.
	Vector3 get_normal() const { return normal; }
	/// GDScript property `surface_id`.
	void set_surface_id(int64_t p_value) { surface_id = p_value; }
	/// GDScript property `surface_id`.
	int64_t get_surface_id() const { return surface_id; }
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
