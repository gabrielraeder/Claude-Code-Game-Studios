// PROTOTYPE - NOT FOR PRODUCTION
// Port of the analytic mover routines of src/core/collision/collision_query.gd (read-only source).
// Numeric convention, to mirror GDScript exactly: scalars are double, Vector3 components are float.
// Every `float`-typed GDScript local is a double here; every Vector3 op stays float32.
#include "native_spike_query.h"

#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <algorithm>
#include <cmath>

using namespace godot;

namespace {
const double PARALLEL_EPSILON = 0.000001;
const double MOVER_CULL_MARGIN = 0.01;
const double MOVER_SWEEP_TOLERANCE = 0.0001;
const int MOVER_SWEEP_MAX_ITERATIONS = 64;
const double NEWTON_CAPPED = -2.0;
const int GROUND_LAYER = 1;
const int WALL_LAYER = 2;
inline double D(float v) { return (double)v; }
inline float F(double v) { return (float)v; }
const double INF_D = INFINITY;

double segment_point_distance_sq(const Vector3 &a, const Vector3 &d, const Vector3 &p) {
	Vector3 ap = p - a;
	double dd = D(d.length_squared());
	double s = 0.0;
	if (dd > 0.0) {
		s = Math::clamp(D(ap.dot(d)) / dd, 0.0, 1.0);
	}
	return D((ap - d * F(s)).length_squared());
}

double ray_sphere(const Vector3 &oc, const Vector3 &d, double r) {
	double b = D(oc.dot(d));
	double c = D(oc.length_squared()) - r * r;
	double disc = b * b - c;
	if (disc < 0.0 || (c > 0.0 && b > 0.0)) {
		return INF_D;
	}
	double s = -b - std::sqrt(disc);
	return s >= 0.0 ? s : INF_D;
}
} // namespace

void NativeSpikeQuery::_bind_methods() {
	ClassDB::bind_method(D_METHOD("ping"), &NativeSpikeQuery::ping);
	ClassDB::bind_method(D_METHOD("add_vec", "a", "b"), &NativeSpikeQuery::add_vec);
	ClassDB::bind_method(D_METHOD("echo_transform", "t"), &NativeSpikeQuery::echo_transform);
	ClassDB::bind_method(D_METHOD("sum_floats", "a"), &NativeSpikeQuery::sum_floats);
	ClassDB::bind_method(D_METHOD("echo_rid", "r"), &NativeSpikeQuery::echo_rid);
	ClassDB::bind_method(D_METHOD("add_mover", "shape", "radius", "half_height", "half_extents", "period", "key_t", "key_pos", "key_rot_xyzw"), &NativeSpikeQuery::add_mover);
	ClassDB::bind_method(D_METHOD("mover_pose", "slot", "t"), &NativeSpikeQuery::mover_pose);
	ClassDB::bind_method(D_METHOD("mover_cast_ground", "origin", "dir", "max_dist", "t"), &NativeSpikeQuery::mover_cast_ground);
	ClassDB::bind_method(D_METHOD("mover_sweep", "from", "to", "radius", "t"), &NativeSpikeQuery::mover_sweep);
	ClassDB::bind_method(D_METHOD("get_last_normal"), &NativeSpikeQuery::get_last_normal);
	ClassDB::bind_method(D_METHOD("movers_tick", "t", "ray_origins", "ray_dir", "ray_len", "sweep_from", "sweep_to", "radius"), &NativeSpikeQuery::movers_tick);
	ClassDB::bind_method(D_METHOD("setup_static", "ground_faces", "wall_faces"), &NativeSpikeQuery::setup_static);
	ClassDB::bind_method(D_METHOD("static_cast_ground", "origin", "dir", "max_dist"), &NativeSpikeQuery::static_cast_ground);
	ClassDB::bind_method(D_METHOD("static_sweep", "from", "to", "radius"), &NativeSpikeQuery::static_sweep);
	ClassDB::bind_method(D_METHOD("static_tick", "ray_origins", "ray_dirs", "ray_len", "sweep_from", "sweep_to", "radius"), &NativeSpikeQuery::static_tick);
	ClassDB::bind_method(D_METHOD("owned_rids"), &NativeSpikeQuery::owned_rids);
	ClassDB::bind_method(D_METHOD("dispose"), &NativeSpikeQuery::dispose);
}

NativeSpikeQuery::NativeSpikeQuery() {}

NativeSpikeQuery::~NativeSpikeQuery() {
	free_server_objects();
}

void NativeSpikeQuery::free_server_objects() {
	PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
	if (ps == nullptr) {
		return;
	}
	// ADR-0002 order: bodies, then shapes, then the space.
	state = nullptr;
	RID *bodies[] = { &ground_body, &wall_body };
	for (RID *b : bodies) {
		if (b->is_valid()) {
			ps->free_rid(*b);
			*b = RID();
		}
	}
	RID *shapes[] = { &ground_shape, &wall_shape, &sphere_shape };
	for (RID *s : shapes) {
		if (s->is_valid()) {
			ps->free_rid(*s);
			*s = RID();
		}
	}
	if (space.is_valid()) {
		ps->free_rid(space);
		space = RID();
	}
}

TypedArray<RID> NativeSpikeQuery::owned_rids() const {
	TypedArray<RID> a;
	const RID all[] = { ground_body, wall_body, ground_shape, wall_shape, sphere_shape, space };
	for (const RID &r : all) {
		if (r.is_valid()) {
			a.push_back(r);
		}
	}
	return a;
}

double NativeSpikeQuery::sum_floats(const PackedFloat32Array &a) const {
	double s = 0.0;
	for (int64_t i = 0; i < a.size(); i++) {
		s += a[i];
	}
	return s;
}

// ---------------------------------------------------------------- movers

int NativeSpikeQuery::add_mover(int shape, double radius, double half_height, const Vector3 &half_extents, double period,
		const PackedFloat32Array &key_t, const PackedVector3Array &key_pos, const PackedFloat32Array &key_rot_xyzw) {
	Mover m;
	m.shape = shape;
	m.radius = radius;
	m.half_height = half_height;
	m.half_extents = half_extents;
	m.period = period;
	int n = (int)key_t.size();
	for (int i = 0; i < n; i++) {
		m.key_t.push_back(key_t[i]);
		m.key_pos.push_back(key_pos[i]);
		m.key_rot.push_back(Quaternion(key_rot_xyzw[i * 4], key_rot_xyzw[i * 4 + 1], key_rot_xyzw[i * 4 + 2], key_rot_xyzw[i * 4 + 3]));
	}
	double bound = 0.0;
	if (shape == BOX) {
		bound = D(half_extents.length());
	} else if (shape == CAPSULE) {
		bound = radius + half_height;
	} else {
		bound = std::sqrt(radius * radius + half_height * half_height);
	}
	Vector3 lo = m.key_pos[0], hi = m.key_pos[0];
	for (const Vector3 &p : m.key_pos) {
		lo = Vector3(std::min(lo.x, p.x), std::min(lo.y, p.y), std::min(lo.z, p.z));
		hi = Vector3(std::max(hi.x, p.x), std::max(hi.y, p.y), std::max(hi.z, p.z));
	}
	Vector3 centre = (lo + hi) * 0.5f;
	double path_radius = 0.0;
	for (const Vector3 &p : m.key_pos) {
		path_radius = std::max(path_radius, D(centre.distance_to(p)));
	}
	m.shape_bound = bound;
	m.path_centre = centre;
	m.path_reach = path_radius + bound + MOVER_CULL_MARGIN;
	movers.push_back(m);
	rs_slot.resize(movers.size());
	rs_from.resize(movers.size());
	rs_motion.resize(movers.size());
	rs_gap.resize(movers.size());
	rs_slope.resize(movers.size());
	return (int)movers.size() - 1;
}

void NativeSpikeQuery::find_segment(const std::vector<float> &key_t, double period, double t) {
	int n = (int)key_t.size();
	double u = Math::fposmod(t, period);
	// bsearch(u, false) compares in float32 (upper bound)
	int i = (int)(std::upper_bound(key_t.begin(), key_t.end(), (float)u) - key_t.begin()) - 1;
	double t0, t1;
	if (i >= 0 && i < n - 1) {
		seg_j = i + 1;
		t0 = key_t[i];
		t1 = key_t[i + 1];
	} else {
		if (i < 0 && u < key_t[0]) {
			u += period;
		}
		i = n - 1;
		seg_j = 0;
		t0 = key_t[i];
		t1 = D(key_t[0]) + period;
	}
	seg_i = i;
	seg_span = t1 - t0;
	seg_alpha = Math::clamp((u - t0) / seg_span, 0.0, 1.0);
}

void NativeSpikeQuery::eval_slot(int k, double t) {
	Mover &m = movers[k];
	if (m.pc_t == t) {
		return;
	}
	find_segment(m.key_t, m.period, t);
	Vector3 p0 = m.key_pos[seg_i];
	Vector3 p1 = m.key_pos[seg_j];
	Quaternion q0 = m.key_rot[seg_i];
	Quaternion q1 = m.key_rot[seg_j];
	if (q0.dot(q1) < 0.0f) {
		q1 = Quaternion(-q1.x, -q1.y, -q1.z, -q1.w);
	}
	m.pose = Transform3D(Basis(q0.slerp(q1, F(seg_alpha))), p0.lerp(p1, F(seg_alpha)));
	m.inv = m.pose.inverse();
	m.pc_t = t;
}

Transform3D NativeSpikeQuery::mover_pose(int slot, double t) {
	if (slot < 0 || slot >= (int)movers.size()) {
		return Transform3D();
	}
	eval_slot(slot, t);
	return movers[slot].pose;
}

bool NativeSpikeQuery::in_reach_at(int k, const Vector3 &a, const Vector3 &d, double radius, double t) {
	eval_slot(k, t);
	double shape_reach = movers[k].shape_bound + MOVER_CULL_MARGIN + radius;
	return segment_point_distance_sq(a, d, movers[k].pose.origin) <= shape_reach * shape_reach;
}

double NativeSpikeQuery::closest_local(const Mover &m, const Vector3 &p) {
	if (m.shape == BOX) {
		return closest_box(m.half_extents, p);
	}
	if (m.shape == CAPSULE) {
		return closest_capsule(m.radius, m.half_height, p);
	}
	return closest_cylinder(m.radius, m.half_height, p);
}

double NativeSpikeQuery::closest_box(const Vector3 &h, const Vector3 &p) {
	Vector3 q = p.clamp(-h, h);
	if (q != p) {
		Vector3 out_v = p - q;
		double d = D(out_v.length());
		cl_point = q;
		cl_normal = out_v / F(d);
		return d;
	}
	Vector3 face = h - p.abs();
	int axis = 0;
	if (face.y < face[axis]) {
		axis = 1;
	}
	if (face.z < face[axis]) {
		axis = 2;
	}
	double sign_a = p[axis] >= 0.0f ? 1.0 : -1.0;
	cl_point = p;
	cl_point[axis] = F(sign_a * D(h[axis]));
	cl_normal = Vector3();
	cl_normal[axis] = F(sign_a);
	return -D(face[axis]);
}

double NativeSpikeQuery::closest_capsule(double r, double hh, const Vector3 &p) {
	Vector3 axis_point = Vector3(0.0f, F(Math::clamp(D(p.y), -hh, hh)), 0.0f);
	Vector3 v = p - axis_point;
	double d = D(v.length());
	if (d > 0.0) {
		cl_normal = v / F(d);
	} else {
		cl_normal = Vector3(1, 0, 0);
	}
	cl_point = axis_point + cl_normal * F(r);
	return d - r;
}

double NativeSpikeQuery::closest_cylinder(double r, double hh, const Vector3 &p) {
	double px = p.x, py = p.y, pz = p.z;
	double rho = std::sqrt(px * px + pz * pz);
	double y_out = std::fabs(py) - hh;
	if (rho > r || y_out > 0.0) {
		Vector3 q = Vector3(p.x, F(Math::clamp(py, -hh, hh)), p.z);
		if (rho > r) {
			q.x = F(D(q.x) * (r / rho));
			q.z = F(D(q.z) * (r / rho));
		}
		Vector3 out_v = p - q;
		double d = D(out_v.length());
		cl_point = q;
		cl_normal = out_v / F(d);
		return d;
	}
	double side = r - rho;
	double cap = -y_out;
	if (cap <= side) {
		double sign_y = py >= 0.0 ? 1.0 : -1.0;
		cl_point = Vector3(p.x, F(sign_y * hh), p.z);
		cl_normal = Vector3(0.0f, F(sign_y), 0.0f);
		return -cap;
	}
	Vector3 radial = Vector3(1, 0, 0);
	if (rho > 0.0) {
		radial = Vector3(F(px / rho), 0.0f, F(pz / rho));
	}
	cl_point = Vector3(F(D(radial.x) * r), p.y, F(D(radial.z) * r));
	cl_normal = radial;
	return -side;
}

bool NativeSpikeQuery::ray_local(const Mover &m, const Vector3 &o, const Vector3 &d, double max_dist) {
	if (m.shape == BOX) {
		return ray_box(m.half_extents, o, d, max_dist);
	}
	if (m.shape == CAPSULE) {
		return ray_capsule(m.radius, m.half_height, o, d, max_dist);
	}
	return ray_cylinder(m.radius, m.half_height, o, d, max_dist);
}

bool NativeSpikeQuery::ray_box(const Vector3 &h, const Vector3 &o, const Vector3 &d, double max_dist) {
	double t_in = -INF_D;
	double t_out = INF_D;
	Vector3 n_in;
	for (int axis = 0; axis < 3; axis++) {
		double oa = o[axis];
		double da = d[axis];
		double ha = h[axis];
		if (std::fabs(da) < PARALLEL_EPSILON) {
			if (std::fabs(oa) > ha) {
				return false;
			}
			continue;
		}
		double s_low = (-ha - oa) / da;
		double s_high = (ha - oa) / da;
		double s0 = std::min(s_low, s_high);
		if (s0 > t_in) {
			t_in = s0;
			n_in = Vector3();
			n_in[axis] = da > 0.0 ? -1.0f : 1.0f;
		}
		t_out = std::min(t_out, std::max(s_low, s_high));
		if (t_in > t_out) {
			return false;
		}
	}
	if (t_in < 0.0 || t_in > max_dist) {
		return false;
	}
	ray_dist = t_in;
	ray_normal = n_in;
	return true;
}

bool NativeSpikeQuery::ray_capsule(double r, double hh, const Vector3 &o, const Vector3 &d, double max_dist) {
	Vector3 o_axis = Vector3(0.0f, F(Math::clamp(D(o.y), -hh, hh)), 0.0f);
	if (D((o - o_axis).length_squared()) < r * r) {
		return false;
	}
	double best = INF_D;
	Vector3 best_n = Vector3(0, 1, 0);
	double dx = d.x, dy = d.y, dz = d.z, ox = o.x, oy = o.y, oz = o.z;
	double a = dx * dx + dz * dz;
	double c = ox * ox + oz * oz - r * r;
	if (a > PARALLEL_EPSILON && c >= 0.0) {
		double b = ox * dx + oz * dz;
		double disc = b * b - a * c;
		if (disc >= 0.0) {
			double s = (-b - std::sqrt(disc)) / a;
			if (s >= 0.0 && std::fabs(oy + dy * s) <= hh) {
				best = s;
				best_n = Vector3(F(ox + dx * s), 0.0f, F(oz + dz * s)) / F(r);
			}
		}
	}
	for (int end = 0; end < 2; end++) {
		Vector3 centre = Vector3(0.0f, F(end == 1 ? hh : -hh), 0.0f);
		double s2 = ray_sphere(o - centre, d, r);
		if (s2 < best) {
			best = s2;
			best_n = (o - centre + d * F(s2)) / F(r);
		}
	}
	if (best > max_dist) {
		return false;
	}
	ray_dist = best;
	ray_normal = best_n;
	return true;
}

bool NativeSpikeQuery::ray_cylinder(double r, double hh, const Vector3 &o, const Vector3 &d, double max_dist) {
	double t_in = -INF_D;
	double t_out = INF_D;
	bool entry_is_cap = true;
	double dx = d.x, dy = d.y, dz = d.z, ox = o.x, oy = o.y, oz = o.z;
	if (std::fabs(dy) < PARALLEL_EPSILON) {
		if (std::fabs(oy) > hh) {
			return false;
		}
	} else {
		double s_low = (-hh - oy) / dy;
		double s_high = (hh - oy) / dy;
		t_in = std::min(s_low, s_high);
		t_out = std::max(s_low, s_high);
	}
	double a = dx * dx + dz * dz;
	double c = ox * ox + oz * oz - r * r;
	if (a < PARALLEL_EPSILON) {
		if (c > 0.0) {
			return false;
		}
	} else {
		double b = ox * dx + oz * dz;
		double disc = b * b - a * c;
		if (disc < 0.0) {
			return false;
		}
		double root = std::sqrt(disc);
		if ((-b - root) / a > t_in) {
			t_in = (-b - root) / a;
			entry_is_cap = false;
		}
		t_out = std::min(t_out, (-b + root) / a);
	}
	if (t_in > t_out || t_in < 0.0 || t_in > max_dist) {
		return false;
	}
	ray_dist = t_in;
	if (entry_is_cap) {
		ray_normal = Vector3(0.0f, dy < 0.0 ? 1.0f : -1.0f, 0.0f);
	} else {
		ray_normal = Vector3(F(ox + dx * t_in), 0.0f, F(oz + dz * t_in)) / F(r);
	}
	return true;
}

bool NativeSpikeQuery::test_ground_movers(const Vector3 &origin, const Vector3 &dir, double max_dist, double t) {
	gm_slot = -1;
	gm_dist = max_dist;
	Vector3 ray = dir * F(max_dist);
	double dd = D(ray.length_squared());
	for (int k = 0; k < (int)movers.size(); k++) {
		Mover &m = movers[k];
		double reach = m.path_reach + 0.0;
		Vector3 ap = m.path_centre - origin;
		double s = 0.0;
		if (dd > 0.0) {
			s = Math::clamp(D(ap.dot(ray)) / dd, 0.0, 1.0);
		}
		if (D((ap - ray * F(s)).length_squared()) > reach * reach || !in_reach_at(k, origin, ray, 0.0, t)) {
			continue;
		}
		if (!ray_local(m, m.inv.xform(origin), m.inv.basis.xform(dir), gm_dist)) {
			continue;
		}
		if (ray_dist < gm_dist || gm_slot < 0) { // static_hit is false in this spike
			gm_slot = k;
			gm_dist = ray_dist;
			gm_normal = m.pose.basis.xform(ray_normal);
		}
	}
	return gm_slot >= 0;
}

void NativeSpikeQuery::test_movers_for_sweep(const Vector3 &from, const Vector3 &motion, double radius, double t, bool do_sweep) {
	ov_slot = -1;
	ov_depth = -INF_D;
	rs_count = 0;
	double dd = D(motion.length_squared());
	for (int k = 0; k < (int)movers.size(); k++) {
		Mover &m = movers[k];
		double reach = m.path_reach + radius;
		Vector3 ap = m.path_centre - from;
		double s = 0.0;
		if (dd > 0.0) {
			s = Math::clamp(D(ap.dot(motion)) / dd, 0.0, 1.0);
		}
		if (D((ap - motion * F(s)).length_squared()) > reach * reach || !in_reach_at(k, from, motion, radius, t)) {
			continue;
		}
		Vector3 local_from = m.inv.xform(from);
		double gap = closest_local(m, local_from) - radius;
		if (gap <= 0.0) {
			if (-gap > ov_depth) {
				ov_slot = k;
				ov_depth = -gap;
				ov_point = cl_point;
				ov_normal = cl_normal;
			}
			continue;
		}
		if (do_sweep && ov_slot < 0) {
			Vector3 local_motion = m.inv.basis.xform(motion);
			rs_slot[rs_count] = k;
			rs_from[rs_count] = local_from;
			rs_motion[rs_count] = local_motion;
			rs_gap[rs_count] = gap;
			rs_slope[rs_count] = D(cl_normal.dot(local_motion));
			rs_count++;
		}
	}
	sm_slot = -1;
	sm_fraction = INF_D;
	if (ov_slot >= 0) {
		const Transform3D &pose0 = movers[ov_slot].pose;
		ov_point = pose0.xform(ov_point);
		ov_normal = pose0.basis.xform(ov_normal);
		return;
	}
	if (rs_count == 0) {
		return;
	}
	double length = D(motion.length());
	for (int n = 0; n < rs_count; n++) {
		int k = rs_slot[n];
		if (!sweep_local(movers[k], rs_from[n], rs_motion[n], length, radius, rs_gap[n], rs_slope[n])) {
			continue;
		}
		if (sw_fraction < sm_fraction) {
			sm_slot = k;
			sm_fraction = sw_fraction;
			sm_point = sw_point;
			sm_normal = sw_normal;
		}
	}
	if (sm_slot >= 0) {
		const Transform3D &pose = movers[sm_slot].pose;
		sm_point = pose.xform(sm_point);
		sm_normal = pose.basis.xform(sm_normal);
	}
}

bool NativeSpikeQuery::sweep_local(const Mover &m, const Vector3 &local_from, const Vector3 &local_motion, double length,
		double radius, double gap0, double slope0) {
	double hi = NEWTON_CAPPED;
	double step_min = MOVER_SWEEP_TOLERANCE / length;
	double lo = 0.0;
	double f = gap0;
	double slope = slope0;
	for (int iteration = 0; iteration < MOVER_SWEEP_MAX_ITERATIONS; iteration++) {
		if (slope >= 0.0) {
			return false;
		}
		double s = lo - f / slope;
		if (s > 1.0) {
			if (s - 1.0 > step_min) {
				return false;
			}
			s = 1.0;
		}
		if (s - lo < step_min) {
			s = std::min(lo + step_min, 1.0);
		}
		double fs = closest_local(m, local_from + local_motion * F(s)) - radius;
		if (fs <= 0.0) {
			hi = s;
			break;
		}
		if (s >= 1.0) {
			return false;
		}
		lo = s;
		f = fs;
		slope = D(cl_normal.dot(local_motion));
	}
	if (hi == NEWTON_CAPPED) {
		sw_fraction = lo;
		closest_local(m, local_from + local_motion * F(lo));
		sw_point = cl_point;
		sw_normal = cl_normal;
		return true;
	}
	int iterations = 0;
	while ((hi - lo) * length > MOVER_SWEEP_TOLERANCE && iterations < MOVER_SWEEP_MAX_ITERATIONS) {
		double mid = (lo + hi) * 0.5;
		if (closest_local(m, local_from + local_motion * F(mid)) - radius <= 0.0) {
			hi = mid;
		} else {
			lo = mid;
		}
		iterations++;
	}
	if ((1.0 - hi) * length < MOVER_SWEEP_TOLERANCE && closest_local(m, local_from + local_motion) - radius <= 0.0) {
		sw_fraction = 1.0;
	} else {
		sw_fraction = lo;
		closest_local(m, local_from + local_motion * F(lo));
	}
	sw_point = cl_point;
	sw_normal = cl_normal;
	return true;
}

double NativeSpikeQuery::mover_cast_ground_impl(const Vector3 &origin, const Vector3 &dir, double max_dist, double t) {
	if (movers.empty() || !test_ground_movers(origin, dir, max_dist, t)) {
		return -1.0;
	}
	last_normal = gm_normal;
	return gm_dist;
}

// Returns -1 on a miss, else the fraction (0 = started inside); last_normal = world normal.
double NativeSpikeQuery::mover_sweep_impl(const Vector3 &from, const Vector3 &to, double radius, double t) {
	Vector3 motion = to - from;
	if (movers.empty()) {
		return -1.0;
	}
	test_movers_for_sweep(from, motion, radius, t, motion != Vector3());
	if (ov_slot >= 0) {
		last_normal = ov_normal;
		return 0.0;
	}
	if (sm_slot >= 0) {
		last_normal = sm_normal;
		return sm_fraction;
	}
	return -1.0;
}

PackedFloat64Array NativeSpikeQuery::movers_tick(double t, const PackedVector3Array &ray_origins, const Vector3 &ray_dir, double ray_len,
		const PackedVector3Array &sweep_from, const PackedVector3Array &sweep_to, double radius) {
	int nr = (int)ray_origins.size();
	int ns = (int)sweep_from.size();
	if (out64.size() != nr + ns * 4) {
		out64.resize(nr + ns * 4);
	}
	double *out = out64.ptrw();
	for (int i = 0; i < nr; i++) {
		out[i] = mover_cast_ground_impl(ray_origins[i], ray_dir, ray_len, t);
	}
	for (int i = 0; i < ns; i++) {
		double fr = mover_sweep_impl(sweep_from[i], sweep_to[i], radius, t);
		double *o = out + nr + i * 4;
		o[0] = fr;
		if (fr >= 0.0) {
			o[1] = last_normal.x;
			o[2] = last_normal.y;
			o[3] = last_normal.z;
		} else {
			o[1] = o[2] = o[3] = 0.0;
		}
	}
	return out64;
}

// ---------------------------------------------------------------- static path

void NativeSpikeQuery::setup_static(const PackedVector3Array &ground_faces, const PackedVector3Array &wall_faces) {
	free_server_objects();
	PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
	space = ps->space_create();
	ps->space_set_active(space, true);
	auto make_body = [&](const PackedVector3Array &faces, int layer, RID &shape_out, RID &body_out) {
		shape_out = ps->concave_polygon_shape_create();
		Dictionary d;
		d["faces"] = faces;
		d["backface_collision"] = false;
		ps->shape_set_data(shape_out, d);
		body_out = ps->body_create();
		ps->body_set_mode(body_out, PhysicsServer3D::BODY_MODE_STATIC);
		ps->body_set_collision_layer(body_out, layer);
		ps->body_set_collision_mask(body_out, 0);
		ps->body_add_shape(body_out, shape_out);
		ps->body_set_space(body_out, space);
	};
	make_body(ground_faces, GROUND_LAYER, ground_shape, ground_body);
	make_body(wall_faces, WALL_LAYER, wall_shape, wall_body);
	sphere_shape = ps->sphere_shape_create();
	state = ps->space_get_direct_state(space);
	ray_params.instantiate();
	ray_result.instantiate();
	shape_params.instantiate();
	cast_result.instantiate();
	rest_result.instantiate();
	ray_params->set_collision_mask(GROUND_LAYER);
	ray_params->set_hit_back_faces(false);
	shape_params->set_collision_mask(WALL_LAYER);
	shape_params->set_shape_rid(sphere_shape);
	sphere_radius = -1.0;
}

double NativeSpikeQuery::static_cast_ground_impl(const Vector3 &origin, const Vector3 &dir, double max_dist) {
	ray_params->set_from(origin);
	ray_params->set_to(origin + dir * F(max_dist));
	if (!state->intersect_ray_into(ray_params, ray_result)) {
		return -1.0;
	}
	last_normal = ray_result->get_normal();
	return D((ray_result->get_position() - origin).dot(dir));
}

// The ADR-0002 sweep: rest check at from; cast; rest check at the unsafe point or at to.
double NativeSpikeQuery::static_sweep_impl(const Vector3 &from, const Vector3 &to, double radius) {
	if (sphere_radius != radius) {
		PhysicsServer3D::get_singleton()->shape_set_data(sphere_shape, radius);
		sphere_radius = radius;
	}
	Vector3 motion = to - from;
	shape_params->set_transform(Transform3D(Basis(), from));
	if (state->get_rest_info_into(shape_params, rest_result)) {
		last_normal = rest_result->get_normal();
		return 0.0;
	}
	if (motion == Vector3()) {
		return -1.0;
	}
	shape_params->set_motion(motion);
	bool cast_hit = state->cast_motion_into(shape_params, cast_result);
	shape_params->set_motion(Vector3());
	if (cast_hit && cast_result->get_unsafe_fraction() < 1.0f) {
		double safe = cast_result->get_safe_fraction();
		shape_params->set_transform(Transform3D(Basis(), from + motion * cast_result->get_unsafe_fraction()));
		if (state->get_rest_info_into(shape_params, rest_result)) {
			last_normal = rest_result->get_normal();
		}
		return safe;
	}
	shape_params->set_transform(Transform3D(Basis(), to));
	if (state->get_rest_info_into(shape_params, rest_result)) {
		last_normal = rest_result->get_normal();
		return 1.0;
	}
	return -1.0;
}

PackedFloat64Array NativeSpikeQuery::static_tick(const PackedVector3Array &ray_origins, const PackedVector3Array &ray_dirs, double ray_len,
		const PackedVector3Array &sweep_from, const PackedVector3Array &sweep_to, double radius) {
	int nr = (int)ray_origins.size();
	int ns = (int)sweep_from.size();
	int per_kart = ray_dirs.size() > 0 ? nr / (int)ray_dirs.size() : 1;
	if (out64.size() != nr + ns) {
		out64.resize(nr + ns);
	}
	double *out = out64.ptrw();
	for (int i = 0; i < nr; i++) {
		out[i] = static_cast_ground_impl(ray_origins[i], ray_dirs[i / per_kart], ray_len);
	}
	for (int i = 0; i < ns; i++) {
		out[nr + i] = static_sweep_impl(sweep_from[i], sweep_to[i], radius);
	}
	return out64;
}
