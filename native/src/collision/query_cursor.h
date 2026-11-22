#pragma once
/// QueryCursor: the reused engine query objects of one caller for `CollisionQuery` (ADR-0002 "Reuse rules").

#include <godot_cpp/classes/physics_cast_motion_result3d.hpp>
#include <godot_cpp/classes/physics_get_rest_info_result3d.hpp>
#include <godot_cpp/classes/physics_intersect_ray_result3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/physics_shape_query_parameters3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/sphere_shape3d.hpp>

namespace godot {

/// One per kart, projectile or tool, built once with `QueryCursor.new()` and passed to every query, so
/// per-tick collision code allocates nothing. The collision masks and flags are fixed here once; the
/// query only writes from/to, transform and motion. Not thread-safe: one cursor belongs to one caller.
///
/// The constructor creates engine Resource objects (parameters, results, one `SphereShape3D`). NAMED
/// EXCEPTION to "constructors create no RID" (native-code.md, ADR-0007 section 4): engine Resources held
/// by `Ref<>` own their RIDs (the sphere's server shape is freed by that Resource, not by this class), and
/// their holder is registered for release at SCENE uninit: `release_all_engine_objects()` unrefs them and
/// clears `built` before the servers-alive flag drops. When the servers are not alive the constructor
/// builds nothing and `is_built()` is false, and every query refuses it.
/// The exposed read-only properties hand out the live objects: tests and tools must not change their
/// collision masks or flags (the query writes from/to, transform, motion and the sphere radius itself).
class QueryCursor : public RefCounted {
	GDCLASS(QueryCursor, RefCounted)

public:
	/// Ray parameters, reused. Mask GROUND_LAYER, no back faces.
	Ref<PhysicsRayQueryParameters3D> ray_params;
	/// Ray result, reused; valid only right after a cast that returned true.
	Ref<PhysicsIntersectRayResult3D> ray_result;
	/// The sweep sphere, reused; the query writes its radius only when it changes.
	Ref<SphereShape3D> sphere;
	/// Shape-query parameters for `sweep_walls`; mask WALL_LAYER; `motion` is zero between calls.
	Ref<PhysicsShapeQueryParameters3D> shape_params;
	/// Cast result, reused.
	Ref<PhysicsCastMotionResult3D> cast_result;
	/// Rest-info result, reused; valid only right after a rest check that returned true.
	Ref<PhysicsGetRestInfoResult3D> rest_result;

	/// GDScript read-only properties `ray_params`, `ray_result`, `sphere`, `shape_params`, `cast_result`,
	/// `rest_result`: the reused engine objects, for tests and tools that run a raw engine query on the same objects.
	Ref<PhysicsRayQueryParameters3D> get_ray_params() const;
	/// GDScript read-only property `ray_result`.
	Ref<PhysicsIntersectRayResult3D> get_ray_result() const;
	/// GDScript read-only property `sphere`.
	Ref<SphereShape3D> get_sphere() const;
	/// GDScript read-only property `shape_params`.
	Ref<PhysicsShapeQueryParameters3D> get_shape_params() const;
	/// GDScript read-only property `cast_result`.
	Ref<PhysicsCastMotionResult3D> get_cast_result() const;
	/// GDScript read-only property `rest_result`.
	Ref<PhysicsGetRestInfoResult3D> get_rest_result() const;

	/// GDScript: `is_built() -> bool`. True when the constructor built the engine objects.
	bool is_built() const { return built; }

	/// Builds the engine objects (when the servers are alive) and registers the cursor.
	QueryCursor();
	~QueryCursor();

	/// Unrefs the engine Resources of every live cursor and clears their `built` flag (hot reload and exit).
	/// Called from `uninitialize_module(SCENE)` before the servers-alive flag is cleared. Not bound.
	static void release_all_engine_objects();

protected:
	/// Binds `is_built`.
	static void _bind_methods();

private:
	bool built = false;
};

} // namespace godot
