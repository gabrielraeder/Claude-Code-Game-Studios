#pragma once
/// CollisionQuery: the track's collision queries in C++ (ADR-0002 behaviour, ADR-0007 section 4;
/// core-rebuild story 067, a translation of the story-007 GDScript, now `OracleCollisionQuery`).

#include "collision/collision_constants.h"
#include "collision/ground_hit.h"
#include "collision/query_cursor.h"
#include "collision/wall_hit.h"

#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <vector>

namespace godot {

class PhysicsServer3D;

/// The track's collision queries. Jolt Physics, used only through PhysicsServer3D: `create()` builds a
/// private inactive space, one ground body with ONE concave shape, one wall body with one concave shape
/// per wall attribute. Movers are NOT bodies: each is a primitive on a looped keyframed pose curve that
/// this object evaluates and tests analytically in `cast_ground` and `sweep_walls`.
///
/// Built with the bound static `create(packed)` from `TrackCollisionData.pack_native()` (checked first by
/// `validate_packed(packed)`, which runs the same C++ validation). `.new()` gives an unbuilt object whose
/// every bound method refuses, except `dispose()` (silent no-op) and the `is_*` queries.
///
/// Time convention: every query takes `t`, the caller's tick time n x SIM_DT. A mover is frozen at its
/// pose at `t` for the whole query. Main thread only: the mover code keeps per-object scratch and a pose
/// cache (valid only while every query of one tick passes the identical `t`).
///
/// Lifetime: the composition root calls `dispose()` at track unload: bodies, then shapes, then the space.
/// The destructor does the same through the same static helper, and `uninitialize_module(SCENE)` frees
/// every live query's server objects (hot reload, exit). Needs
/// `physics/jolt_physics_3d/queries/enable_ray_cast_face_index = true` (asserted at boot).
class CollisionQuery : public RefCounted {
	GDCLASS(CollisionQuery, RefCounted)

public:
	/// GDScript: `CollisionQuery.validate_packed(packed: Dictionary) -> String`. Checks every key and Variant
	/// type of the `pack_native()` Dictionary and then the layout (the checks of `TrackCollisionData.layout_error()`
	/// and `MoverDef.layout_error()`). "" when valid, otherwise a message naming the key. Load time only (allocates).
	static String validate_packed(const Dictionary &p_packed);
	/// GDScript: `CollisionQuery.create(packed: Dictionary) -> CollisionQuery`. Runs the same validation as
	/// `validate_packed`; returns null (with an error) on failure or when the physics server is missing.
	/// Creates the server objects. Load time only (allocates).
	static Ref<CollisionQuery> create(const Dictionary &p_packed);
	/// GDScript: `CollisionQuery.majority_surface(ids, points, count, centre_of_mass, up, previous_id) -> int`.
	/// The surface under a kart: the majority of the surface ids its probes hit; a tie goes to the tied kind of the
	/// probe nearest `centre_of_mass` on the plane normal to `up`; no hit returns `previous_id`. Pure, allocation-free.
	static int64_t majority_surface(const PackedInt32Array &p_ids, const PackedVector3Array &p_points, int64_t p_count,
			const Vector3 &p_centre_of_mass, const Vector3 &p_up, int64_t p_previous_id);
	/// GDScript: `CollisionQuery.mover_sweep_tolerance() -> float`. The sweep tolerance constant (a float cannot be a bound constant).
	static double mover_sweep_tolerance();
	/// GDScript: `CollisionQuery.probe_t() -> float`. The time of the load-time probe cast (PROBE_T, 0.0 s).
	static double probe_t();
	/// GDScript: `CollisionQuery.unsafe_retry_length() -> float`. The extra length of the second static rest check.
	static double unsafe_retry_length();
	/// GDScript: `CollisionQuery.live_rid_count() -> int`. Test-only: server RIDs currently owned by every built
	/// query (bodies + shapes + space). A test asserts it returns to its baseline after `dispose()`.
	static int64_t live_rid_count();
	/// Frees the server objects of every live query and clears their `built` flag (hot reload and exit).
	/// Called from `uninitialize_module(SCENE)` before the servers-alive flag is cleared. Not bound.
	static void release_all_server_objects();

	/// GDScript: `cast_ground(cursor, origin, dir, max_dist, t, hit) -> bool`. Casts a ray from `origin` along
	/// `dir` (unit length) for `max_dist` metres against the static ground (layer 1) and the solid movers. The
	/// nearest hit wins; at an exactly equal distance the static ground wins, between movers the first in data
	/// order. Back faces are never hit; a ray starting inside a mover does not hit it. On a hit writes every field
	/// of `hit` and returns true; on a miss returns false and leaves `hit` untouched. Allocation-free.
	bool cast_ground(const Ref<QueryCursor> &p_cursor, const Vector3 &p_origin, const Vector3 &p_dir, double p_max_dist, double p_t, const Ref<GroundHit> &p_out);
	/// GDScript: `sweep_walls(cursor, from, to, radius, t, hit) -> bool`. Sweeps a sphere of `radius` (> 0) from
	/// `from` to `to` against the static walls (layer 2) and the solid movers, in the ADR-0002 order: overlap at
	/// `from` first (started_inside, fraction 0), then the cast, the rest check at the unsafe point (with the
	/// 0.001 m retry), the touch rule at `to`, and the analytic mover sweep. On a hit writes every field of `hit`
	/// and returns true; on a miss returns false and leaves `hit` untouched. Allocation-free.
	bool sweep_walls(const Ref<QueryCursor> &p_cursor, const Vector3 &p_from, const Vector3 &p_to, double p_radius, double p_t, const Ref<WallHit> &p_out);
	/// GDScript: `mover_pose(id, t) -> Transform3D`. Pose of mover `id` at time `t` (position piecewise linear,
	/// rotation shortest-path slerp, looped). An unknown id errors and returns the identity. Allocation-free.
	Transform3D mover_pose(int64_t p_id, double p_t);
	/// GDScript: `mover_point_velocity(id, t, p) -> Vector3`. Velocity at world point `p` of mover `id` at `t`.
	/// An unknown id errors and returns zero. Allocation-free.
	Vector3 mover_point_velocity(int64_t p_id, double p_t, const Vector3 &p_p);
	/// GDScript: `probe_error(probe_point, probe_surface_id, max_drop) -> String`. The load-time probe: a cast
	/// straight down from `probe_point` for `max_drop` metres at t = `probe_t()` must hit the static ground with
	/// surface id `probe_surface_id` and normal.y > 0. "" on success, otherwise one sentence naming the reason.
	/// Refuses (built guard, returns "load probe: the query is not built") on an unbuilt or disposed query.
	/// Load time only (allocates a cursor, a hit and the message).
	String probe_error(const Vector3 &p_probe_point, int64_t p_probe_surface_id, double p_max_drop);
	/// GDScript: `has_geometry() -> bool`. True when the query built a ground body, a wall body or any mover
	/// (non-solid ones included).
	bool has_geometry() const;
	/// GDScript: `owned_rids() -> Array[RID]`. Bodies, then shapes, then the space. Refuses (built guard) after
	/// `dispose()`: read it before disposing. For tests, tools and leak checks; allocates.
	TypedArray<RID> owned_rids() const;
	/// GDScript: `space_rid() -> RID`. The private space, or RID() after `dispose()`.
	RID space_rid() const;
	/// GDScript: `ground_body_rid() -> RID`. The ground body, or RID() when there is none or after `dispose()`.
	RID ground_body_rid() const;
	/// GDScript: `wall_body_rid() -> RID`. The wall body, or RID() when there is none or after `dispose()`.
	RID wall_body_rid() const;
	/// GDScript: `dispose() -> void`. Frees bodies, then shapes, then the space; clears `built`. Idempotent: on an
	/// unbuilt or already disposed object a silent no-op. The one bound method that does not refuse on `!built`.
	void dispose();
	/// GDScript: `is_built() -> bool`. True after `create()` and before `dispose()`. Does not refuse.
	bool is_built() const;
	/// GDScript: `is_disposed() -> bool`. True once `dispose()` freed server objects (or a hot reload did). Does not refuse.
	bool is_disposed() const;

	/// GDScript: `blocked_fallback_count() -> int`. How many times a blocking static hit found no rest contact at
	/// the unsafe point nor at the 0.001 m retry and was reported with WALL_ATTR_NONE (the fail-closed fallback).
	/// A non-allocating counter; it must stay 0 in the parity and bench runs.
	int64_t blocked_fallback_count() const;
	/// GDScript test seam (test-only, not safe mid-tick): `set_force_rest_miss_for_test(on) -> void`. While on,
	/// the rest checks of a blocking static hit are skipped, so the fail-closed fallback runs. Game code never calls it.
	void set_force_rest_miss_for_test(bool p_on);
	/// GDScript test seam (test-only, not safe mid-tick): `local_point(mover_id, t, world_point) -> Vector3`. The
	/// world point in the mover-local frame the query uses at time `t` (its cached inverse pose).
	Vector3 local_point_for_test(int64_t p_mover_id, double p_t, const Vector3 &p_world_point);
	/// GDScript test seam (test-only, not safe mid-tick): `set_newton_cap(cap) -> void`. Lowers the Newton step
	/// cap of the mover sweep (>= 1) so a test can reach the fail-closed path. Game code never calls it.
	void set_newton_cap(int64_t p_cap);
	/// GDScript test seam (test-only): `cap_error_reported() -> bool`. True once this query reported a capped mover sweep.
	bool cap_error_reported() const;
	/// GDScript test seam (test-only, not safe mid-tick: it writes the shared scratch): `closest_local(mover_id, local_point) -> float`. Signed distance from the mover-local
	/// point to the mover's shape (negative inside); also sets the values of `closest_point()` / `closest_normal()`.
	double closest_local(int64_t p_mover_id, const Vector3 &p_local_point);
	/// GDScript test seam: `closest_point() -> Vector3`. The nearest surface point of the last `closest_local`, mover-local.
	Vector3 closest_point() const;
	/// GDScript test seam: `closest_normal() -> Vector3`. The outward unit normal of the last `closest_local`, mover-local.
	Vector3 closest_normal() const;
	/// GDScript (bound as `ray_sphere`; also used by the capsule ray): `ray_sphere(oc, d, r) -> float`. Entry distance of a ray into a sphere at the origin, or INF.
	static double ray_sphere_entry(const Vector3 &p_oc, const Vector3 &p_d, double p_r);
	/// GDScript (bound as `angular_velocity`; also used for mover velocities): `angular_velocity(q0, q1, span) -> Vector3`. World angular velocity of the rotation q0 -> q1.
	static Vector3 world_angular_velocity(const Quaternion &p_q0, const Quaternion &p_q1, double p_span);

	CollisionQuery() = default;
	~CollisionQuery();

protected:
	/// Binds the static functions, methods, constants and test seams.
	static void _bind_methods();

private:
	/// Primitive shape of a mover; the values are MoverDef.Shape.
	enum Shape { SHAPE_BOX = 0, SHAPE_CAPSULE = 1, SHAPE_CYLINDER = 2 };

	/// One mover's immutable data and its precomputed cull spheres (plain copies of the packed input).
	struct Mover {
		int32_t id = 0;
		double period = 1.0;
		bool solid = true;
		int32_t surface_id = 0;
		int32_t wall_attr_id = 0;
		int32_t shape = SHAPE_BOX;
		Vector3 half_extents;
		double radius = 0.0;
		double half_height = 0.0;
		std::vector<float> key_t;
		std::vector<Vector3> key_pos;
		std::vector<Quaternion> key_rot;
		/// Radius of the sphere around the pose origin that holds the shape.
		double shape_bound = 0.0;
		/// Centre of a sphere holding every key position.
		Vector3 path_centre;
		/// That sphere's radius plus shape_bound plus MOVER_CULL_MARGIN: a time-free cull.
		double path_reach = 0.0;
	};
	/// Pose cache of one mover: evaluated at time `t` (NaN = never).
	struct PoseCache {
		double t = 0.0;
		Transform3D pose;
		Transform3D inv;
		Vector3 lin;
		Vector3 ang;
		bool ang_ok = false;
		int32_t seg_i = 0;
		int32_t seg_j = 0;
		double span = 1.0;
	};
	/// One mover in reach and clear at `from` in pass 1 of the sweep, kept for pass 2.
	struct SweepCandidate {
		int32_t slot = 0;
		Vector3 from;
		Vector3 motion;
		double gap = 0.0;
		double slope = 0.0;
	};

	/// Frees `bodies`, then `shapes`, then `space`; skips when the servers are gone. Static so the destructor can call it.
	static void free_server_objects(const std::vector<RID> &p_bodies, const std::vector<RID> &p_shapes, RID p_space);
	/// Frees this object's server objects, empties its data, clears `built` and leaves the registry.
	void release_server_objects();
	/// Builds the server objects and mover tables from validated `p_packed`. Load time only.
	/// Returns false (after freeing what it made) when the engine gave no direct space state.
	bool build_from(const Dictionary &p_packed, PhysicsServer3D *p_ps);
	/// Registers mover `p_mover` and precomputes its cull spheres. Load time only.
	void add_mover(Mover &p_mover);
	/// Index of mover `p_id`, or -1.
	int slot_of(int64_t p_id) const;

	// Per-tick helpers (the PER_TICK regions of collision_query.cpp).
	void write_ground_contact(const Ref<PhysicsIntersectRayResult3D> &p_result, GroundHit &p_out) const;
	bool sweep_static(QueryCursor &p_cursor, const Vector3 &p_from, const Vector3 &p_to, const Vector3 &p_motion, double p_radius, WallHit &p_out);
	void write_blocked_hit(QueryCursor &p_cursor, const Vector3 &p_from, const Vector3 &p_motion, double p_radius, WallHit &p_out);
	void write_wall_contact(const PhysicsGetRestInfoResult3D &p_rest, double p_fraction, bool p_started_inside, WallHit &p_out) const;
	void write_mover_wall_contact(int p_slot, const Vector3 &p_point, const Vector3 &p_normal, const Vector3 &p_velocity, double p_fraction, bool p_started_inside, WallHit &p_out) const;
	void find_segment(const Mover &p_mover, double p_t);
	void eval_slot(int p_k, double p_t);
	Vector3 ang_of(int p_k);
	bool in_reach_at(int p_k, const Vector3 &p_a, const Vector3 &p_d, double p_radius, double p_t);
	bool test_ground_movers(const Vector3 &p_origin, const Vector3 &p_dir, double p_max_dist, double p_best_dist, bool p_static_hit, double p_t);
	void test_movers_for_sweep(const Vector3 &p_from, const Vector3 &p_motion, double p_radius, double p_t, bool p_do_sweep);
	double closest_local_mover(const Mover &p_mover, const Vector3 &p_p);
	double closest_box(const Vector3 &p_h, const Vector3 &p_p);
	double closest_capsule(double p_r, double p_hh, const Vector3 &p_p);
	double closest_cylinder(double p_r, double p_hh, const Vector3 &p_p);
	bool ray_local(const Mover &p_mover, const Vector3 &p_o, const Vector3 &p_d, double p_max_dist);
	bool ray_box(const Vector3 &p_h, const Vector3 &p_o, const Vector3 &p_d, double p_max_dist);
	bool ray_capsule(double p_r, double p_hh, const Vector3 &p_o, const Vector3 &p_d, double p_max_dist);
	bool ray_cylinder(double p_r, double p_hh, const Vector3 &p_o, const Vector3 &p_d, double p_max_dist);
	bool sweep_local(const Mover &p_mover, const Vector3 &p_local_from, const Vector3 &p_local_motion, double p_length, double p_radius, double p_gap0, double p_slope0);
	/// Reports the fail-closed Newton cap once per query. Off the per-tick path: it builds a message.
	void report_cap_error(int64_t p_mover_id, double p_last_safe);

	bool built = false;
	bool disposed = false;
	bool registered = false;
	RID space;
	std::vector<RID> bodies;
	std::vector<RID> shapes;
	RID ground_body;
	RID wall_body;
	PhysicsDirectSpaceState3D *state = nullptr;
	std::vector<int32_t> surface_of_face;
	std::vector<int32_t> wall_attr_ids;
	std::vector<Mover> movers;
	/// (mover id, slot) sorted by id, for the id lookup.
	std::vector<std::pair<int32_t, int32_t>> slot_by_id;
	/// Slots of the solid movers, in data order: the only movers cast_ground and sweep_walls test.
	std::vector<int32_t> solid_slots;
	std::vector<PoseCache> pose_cache;
	/// One entry per mover (sized at create); `rs_count` entries are used per sweep.
	std::vector<SweepCandidate> rs;
	int rs_count = 0;
	int64_t newton_cap = dogworks::MOVER_SWEEP_MAX_ITERATIONS;
	int64_t blocked_fallbacks = 0;
	bool force_rest_miss = false;
	int64_t owned_rid_count = 0;
	bool cap_error_done = false;

	// Per-call scratch (main thread only, never two queries at once).
	int seg_i = 0;
	int seg_j = 0;
	double seg_span = 1.0;
	double seg_alpha = 0.0;
	Vector3 cl_point;
	Vector3 cl_normal = Vector3(0, 1, 0);
	double ray_dist = 0.0;
	Vector3 ray_normal = Vector3(0, 1, 0);
	double sw_fraction = 1.0;
	Vector3 sw_point;
	Vector3 sw_normal = Vector3(0, 1, 0);
	int gm_slot = -1;
	double gm_dist = 0.0;
	Vector3 gm_normal = Vector3(0, 1, 0);
	Vector3 gm_velocity;
	int ov_slot = -1;
	double ov_depth = 0.0;
	Vector3 ov_point;
	Vector3 ov_normal = Vector3(0, 1, 0);
	Vector3 ov_velocity;
	int sm_slot = -1;
	double sm_fraction = 1.0;
	Vector3 sm_point;
	Vector3 sm_normal = Vector3(0, 1, 0);
	Vector3 sm_velocity;
};

} // namespace godot
