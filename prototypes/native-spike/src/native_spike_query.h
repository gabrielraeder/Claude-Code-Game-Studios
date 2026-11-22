// PROTOTYPE - NOT FOR PRODUCTION
// ADR-0007 native spike: a RefCounted C++ class that (1) ports the analytic mover tests of
// src/core/collision/collision_query.gd and (2) owns PhysicsServer3D RIDs for the static path.
#pragma once

#include <godot_cpp/classes/physics_cast_motion_result3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_get_rest_info_result3d.hpp>
#include <godot_cpp/classes/physics_intersect_ray_result3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/physics_shape_query_parameters3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <vector>

namespace godot {

class NativeSpikeQuery : public RefCounted {
	GDCLASS(NativeSpikeQuery, RefCounted)

public:
	enum Shape { BOX = 0, CAPSULE = 1, CYLINDER = 2 };

private:
	struct Mover {
		int shape = BOX;
		double radius = 0.0, half_height = 0.0, period = 1.0;
		Vector3 half_extents;
		std::vector<float> key_t;
		std::vector<Vector3> key_pos;
		std::vector<Quaternion> key_rot;
		double shape_bound = 0.0, path_reach = 0.0;
		Vector3 path_centre;
		// pose cache
		double pc_t = NAN;
		Transform3D pose, inv;
	};
	std::vector<Mover> movers;

	// scratch (mirrors the _cl_/_ray_/_sw_ fields of the GDScript)
	Vector3 cl_point, cl_normal = Vector3(0, 1, 0);
	double ray_dist = 0.0;
	Vector3 ray_normal = Vector3(0, 1, 0);
	double sw_fraction = 1.0;
	Vector3 sw_point, sw_normal = Vector3(0, 1, 0);
	int seg_i = 0, seg_j = 0;
	double seg_span = 1.0, seg_alpha = 0.0;
	int gm_slot = -1;
	double gm_dist = 0.0;
	Vector3 gm_normal;
	int ov_slot = -1;
	double ov_depth = 0.0;
	Vector3 ov_point, ov_normal;
	int sm_slot = -1;
	double sm_fraction = 1.0;
	Vector3 sm_point, sm_normal;
	int rs_count = 0;
	std::vector<int> rs_slot;
	std::vector<Vector3> rs_from, rs_motion;
	std::vector<double> rs_gap, rs_slope;
	Vector3 last_normal;
	PackedFloat64Array out64;

	// static path
	RID space, ground_body, wall_body, ground_shape, wall_shape, sphere_shape;
	PhysicsDirectSpaceState3D *state = nullptr;
	Ref<PhysicsRayQueryParameters3D> ray_params;
	Ref<PhysicsIntersectRayResult3D> ray_result;
	Ref<PhysicsShapeQueryParameters3D> shape_params;
	Ref<PhysicsCastMotionResult3D> cast_result;
	Ref<PhysicsGetRestInfoResult3D> rest_result;
	double sphere_radius = -1.0;

	void find_segment(const std::vector<float> &key_t, double period, double t);
	void eval_slot(int k, double t);
	bool in_reach_at(int k, const Vector3 &a, const Vector3 &d, double radius, double t);
	bool test_ground_movers(const Vector3 &origin, const Vector3 &dir, double max_dist, double t);
	void test_movers_for_sweep(const Vector3 &from, const Vector3 &motion, double radius, double t, bool do_sweep);
	double closest_local(const Mover &m, const Vector3 &p);
	double closest_box(const Vector3 &h, const Vector3 &p);
	double closest_capsule(double r, double hh, const Vector3 &p);
	double closest_cylinder(double r, double hh, const Vector3 &p);
	bool ray_local(const Mover &m, const Vector3 &o, const Vector3 &d, double max_dist);
	bool ray_box(const Vector3 &h, const Vector3 &o, const Vector3 &d, double max_dist);
	bool ray_capsule(double r, double hh, const Vector3 &o, const Vector3 &d, double max_dist);
	bool ray_cylinder(double r, double hh, const Vector3 &o, const Vector3 &d, double max_dist);
	bool sweep_local(const Mover &m, const Vector3 &local_from, const Vector3 &local_motion, double length, double radius, double gap0, double slope0);

	double mover_cast_ground_impl(const Vector3 &origin, const Vector3 &dir, double max_dist, double t);
	double mover_sweep_impl(const Vector3 &from, const Vector3 &to, double radius, double t);
	double static_cast_ground_impl(const Vector3 &origin, const Vector3 &dir, double max_dist);
	double static_sweep_impl(const Vector3 &from, const Vector3 &to, double radius);
	void free_server_objects();

protected:
	static void _bind_methods();

public:
	NativeSpikeQuery();
	~NativeSpikeQuery();

	// boundary / typed-argument checks
	int ping() const { return 42; }
	Vector3 add_vec(const Vector3 &a, const Vector3 &b) const { return a + b; }
	Transform3D echo_transform(const Transform3D &t) const { return t; }
	double sum_floats(const PackedFloat32Array &a) const;
	RID echo_rid(const RID &r) const { return r; }

	// movers
	int add_mover(int shape, double radius, double half_height, const Vector3 &half_extents, double period,
			const PackedFloat32Array &key_t, const PackedVector3Array &key_pos, const PackedFloat32Array &key_rot_xyzw);
	Transform3D mover_pose(int slot, double t);
	double mover_cast_ground(const Vector3 &origin, const Vector3 &dir, double max_dist, double t) { return mover_cast_ground_impl(origin, dir, max_dist, t); }
	double mover_sweep(const Vector3 &from, const Vector3 &to, double radius, double t) { return mover_sweep_impl(from, to, radius, t); }
	Vector3 get_last_normal() const { return last_normal; }
	// batch: out = [rays: dist or -1] + [sweeps: fraction, nx, ny, nz]
	PackedFloat64Array movers_tick(double t, const PackedVector3Array &ray_origins, const Vector3 &ray_dir, double ray_len,
			const PackedVector3Array &sweep_from, const PackedVector3Array &sweep_to, double radius);

	// static path (owns RIDs)
	void setup_static(const PackedVector3Array &ground_faces, const PackedVector3Array &wall_faces);
	double static_cast_ground(const Vector3 &origin, const Vector3 &dir, double max_dist) { return static_cast_ground_impl(origin, dir, max_dist); }
	double static_sweep(const Vector3 &from, const Vector3 &to, double radius) { return static_sweep_impl(from, to, radius); }
	PackedFloat64Array static_tick(const PackedVector3Array &ray_origins, const PackedVector3Array &ray_dirs, double ray_len,
			const PackedVector3Array &sweep_from, const PackedVector3Array &sweep_to, double radius);
	TypedArray<RID> owned_rids() const;
	void dispose() { free_server_objects(); }
};

} // namespace godot
