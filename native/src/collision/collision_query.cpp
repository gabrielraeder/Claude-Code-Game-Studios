#include "collision/collision_query.h"

#include "register_types.h"

#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector4_array.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <algorithm>
#include <cmath>
#include <limits>

using namespace godot;

namespace {

constexpr double INF_D = std::numeric_limits<double>::infinity();
/// Server RIDs owned by all built queries, for the test-only live_rid_count().
int64_t g_live_rids = 0;

/// Every query that owns server RIDs. Touched only in create(), dispose(), the destructor and the
/// release-all path (load time, main thread), never per tick.
std::vector<CollisionQuery *> &owners() {
	static std::vector<CollisionQuery *> list;
	return list;
}

double clampd(double p_x, double p_lo, double p_hi) {
	return p_x < p_lo ? p_lo : (p_x > p_hi ? p_hi : p_x);
}

/// Number of the first `p_n` entries of `p_ids` equal to `p_id`.
int votes_of(const int32_t *p_ids, int64_t p_n, int32_t p_id) {
	int votes = 0;
	for (int64_t j = 0; j < p_n; j++) {
		if (p_ids[j] == p_id) {
			votes++;
		}
	}
	return votes;
}

String num(double p_value) {
	return String(Variant(p_value));
}

String inum(int64_t p_value) {
	return String::num_int64(p_value);
}

/// Checks that `p_d` holds `p_key` with Variant type `p_type`. Returns "" or the message naming the key.
String check_key(const Dictionary &p_d, String p_where, const char *p_key, Variant::Type p_type) {
	const String key = String(p_key);
	if (!p_d.has(key)) {
		return p_where + " key '" + key + "' is missing";
	}
	const Variant v = p_d[key];
	if (v.get_type() != p_type) {
		return p_where + " key '" + key + "' has type " + Variant::get_type_name(v.get_type()) + ", expected " + Variant::get_type_name(p_type);
	}
	return String();
}

/// The checks of MoverDef.layout_error() on the packed mover `p_m` (keys and types already checked).
String mover_layout_error(const Dictionary &p_m, String p_where) {
	const int64_t id = p_m["id"];
	if (id < 1) {
		return p_where + " key 'id' is " + inum(id) + " (mover ids are >= 1)";
	}
	if (id > dogworks::MAX_MOVER_ID) {
		return p_where + " key 'id' is " + inum(id) + " (mover ids are <= " + inum(dogworks::MAX_MOVER_ID) + ", INT32_MAX)";
	}
	const double period = p_m["period"];
	if (!(period > 0.0) || !std::isfinite(period)) {
		return p_where + " key 'period' is " + num(period) + " (must be > 0 and finite)";
	}
	const int64_t surface_id = p_m["surface_id"];
	if (surface_id < 0 || surface_id > dogworks::MAX_ID) {
		return p_where + " key 'surface_id' is " + inum(surface_id) + ", outside 0..255";
	}
	const int64_t wall_attr_id = p_m["wall_attr_id"];
	if (wall_attr_id < 0 || wall_attr_id > dogworks::MAX_ID) {
		return p_where + " key 'wall_attr_id' is " + inum(wall_attr_id) + ", outside 0..255";
	}
	const int64_t shape = p_m["shape"];
	const Vector3 half_extents = p_m["half_extents"];
	const double radius = p_m["radius"];
	const double half_height = p_m["half_height"];
	if (shape == 0) {
		if (!(half_extents.x > 0.0f && half_extents.y > 0.0f && half_extents.z > 0.0f)) {
			return p_where + " key 'half_extents' must all be > 0 for a BOX";
		}
	} else if (shape == 1) {
		if (!(radius > 0.0 && half_height >= 0.0)) {
			return p_where + " keys 'radius' / 'half_height': a CAPSULE needs radius > 0 and half_height >= 0";
		}
	} else if (shape == 2) {
		if (!(radius > 0.0 && half_height > 0.0)) {
			return p_where + " keys 'radius' / 'half_height': a CYLINDER needs radius > 0 and half_height > 0";
		}
	} else {
		return p_where + " key 'shape' is " + inum(shape) + ", not BOX, CAPSULE or CYLINDER";
	}
	const PackedFloat32Array key_t = p_m["key_t"];
	const PackedVector3Array key_pos = p_m["key_pos"];
	const PackedVector4Array key_rot = p_m["key_rot"];
	const int64_t n = key_t.size();
	if (key_pos.size() != n || key_rot.size() != n) {
		return p_where + " key arrays differ in length (key_t " + inum(n) + ", key_pos " + inum(key_pos.size()) + ", key_rot " + inum(key_rot.size()) + ")";
	}
	if (n < dogworks::MIN_KEYS) {
		return p_where + " key 'key_t' has " + inum(n) + " keys (at least 2)";
	}
	const float *kt = key_t.ptr();
	if (!(kt[0] >= 0.0f)) {
		return p_where + " key 'key_t'[0] is " + num(kt[0]) + " (key times lie in [0, period))";
	}
	for (int64_t i = 1; i < n; i++) {
		if (!(kt[i] > kt[i - 1])) {
			return p_where + " key 'key_t'[" + inum(i) + "] is not after key_t[" + inum(i - 1) + "] (key times strictly ascend)";
		}
	}
	if (!((double)kt[n - 1] < period)) {
		return p_where + " key 'key_t'[" + inum(n - 1) + "] is not before period";
	}
	const Vector3 *kp = key_pos.ptr();
	const Vector4 *kr = key_rot.ptr();
	for (int64_t i = 0; i < n; i++) {
		if (!kp[i].is_finite()) {
			return p_where + " key 'key_pos'[" + inum(i) + "] is not finite";
		}
		const float ls = kr[i].length_squared();
		if (!(std::fabs((double)ls - 1.0) < dogworks::UNIT_QUAT_TOLERANCE)) {
			return p_where + " key 'key_rot'[" + inum(i) + "] is not a unit quaternion";
		}
	}
	return String();
}

} // namespace

void CollisionQuery::_bind_methods() {
	ClassDB::bind_static_method(get_class_static(), D_METHOD("validate_packed", "packed"), &CollisionQuery::validate_packed);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("create", "packed"), &CollisionQuery::create);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("majority_surface", "ids", "points", "count", "centre_of_mass", "up", "previous_id"), &CollisionQuery::majority_surface);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("mover_sweep_tolerance"), &CollisionQuery::mover_sweep_tolerance);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("probe_t"), &CollisionQuery::probe_t);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("unsafe_retry_length"), &CollisionQuery::unsafe_retry_length);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("ray_sphere", "oc", "d", "r"), &CollisionQuery::ray_sphere_entry);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("angular_velocity", "q0", "q1", "span"), &CollisionQuery::world_angular_velocity);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("live_rid_count"), &CollisionQuery::live_rid_count);
	ClassDB::bind_method(D_METHOD("cast_ground", "cursor", "origin", "dir", "max_dist", "t", "hit"), &CollisionQuery::cast_ground);
	ClassDB::bind_method(D_METHOD("sweep_walls", "cursor", "from", "to", "radius", "t", "hit"), &CollisionQuery::sweep_walls);
	ClassDB::bind_method(D_METHOD("mover_pose", "id", "t"), &CollisionQuery::mover_pose);
	ClassDB::bind_method(D_METHOD("mover_point_velocity", "id", "t", "p"), &CollisionQuery::mover_point_velocity);
	ClassDB::bind_method(D_METHOD("probe_error", "probe_point", "probe_surface_id", "max_drop"), &CollisionQuery::probe_error);
	ClassDB::bind_method(D_METHOD("has_geometry"), &CollisionQuery::has_geometry);
	ClassDB::bind_method(D_METHOD("owned_rids"), &CollisionQuery::owned_rids);
	ClassDB::bind_method(D_METHOD("space_rid"), &CollisionQuery::space_rid);
	ClassDB::bind_method(D_METHOD("ground_body_rid"), &CollisionQuery::ground_body_rid);
	ClassDB::bind_method(D_METHOD("wall_body_rid"), &CollisionQuery::wall_body_rid);
	ClassDB::bind_method(D_METHOD("dispose"), &CollisionQuery::dispose);
	ClassDB::bind_method(D_METHOD("is_built"), &CollisionQuery::is_built);
	ClassDB::bind_method(D_METHOD("is_disposed"), &CollisionQuery::is_disposed);
	ClassDB::bind_method(D_METHOD("set_newton_cap", "cap"), &CollisionQuery::set_newton_cap);
	ClassDB::bind_method(D_METHOD("blocked_fallback_count"), &CollisionQuery::blocked_fallback_count);
	ClassDB::bind_method(D_METHOD("set_force_rest_miss_for_test", "on"), &CollisionQuery::set_force_rest_miss_for_test);
	ClassDB::bind_method(D_METHOD("local_point", "mover_id", "t", "world_point"), &CollisionQuery::local_point_for_test);
	ClassDB::bind_method(D_METHOD("cap_error_reported"), &CollisionQuery::cap_error_reported);
	ClassDB::bind_method(D_METHOD("closest_local", "mover_id", "local_point"), &CollisionQuery::closest_local);
	ClassDB::bind_method(D_METHOD("closest_point"), &CollisionQuery::closest_point);
	ClassDB::bind_method(D_METHOD("closest_normal"), &CollisionQuery::closest_normal);
	ClassDB::bind_integer_constant(get_class_static(), "", "GROUND_LAYER", dogworks::GROUND_LAYER);
	ClassDB::bind_integer_constant(get_class_static(), "", "WALL_LAYER", dogworks::WALL_LAYER);
	ClassDB::bind_integer_constant(get_class_static(), "", "SURFACE_NONE", dogworks::SURFACE_NONE);
	ClassDB::bind_integer_constant(get_class_static(), "", "WALL_ATTR_NONE", dogworks::WALL_ATTR_NONE);
	ClassDB::bind_integer_constant(get_class_static(), "", "PACKED_SCHEMA_VERSION", dogworks::PACKED_SCHEMA_VERSION);
	ClassDB::bind_integer_constant(get_class_static(), "", "MIN_KEYS", dogworks::MIN_KEYS);
	ClassDB::bind_integer_constant(get_class_static(), "", "MAX_ID", dogworks::MAX_ID);
	ClassDB::bind_integer_constant(get_class_static(), "", "MAX_MOVER_ID", dogworks::MAX_MOVER_ID);
	ClassDB::bind_integer_constant(get_class_static(), "", "MOVER_SWEEP_MAX_ITERATIONS", dogworks::MOVER_SWEEP_MAX_ITERATIONS);
}

double CollisionQuery::mover_sweep_tolerance() {
	return dogworks::MOVER_SWEEP_TOLERANCE;
}

double CollisionQuery::probe_t() {
	return dogworks::PROBE_T;
}

double CollisionQuery::unsafe_retry_length() {
	return dogworks::UNSAFE_RETRY_LENGTH;
}

// ---------------------------------------------------------------------------------------------
// Load time: validation, construction, teardown.
// ---------------------------------------------------------------------------------------------

String CollisionQuery::validate_packed(const Dictionary &p_packed) {
	String where = "packed";
	String problem = check_key(p_packed, where, "schema_version", Variant::INT);
	if (!problem.is_empty()) {
		return problem;
	}
	const int64_t version = p_packed["schema_version"];
	if (version != dogworks::PACKED_SCHEMA_VERSION) {
		return String("packed key 'schema_version' is ") + inum(version) + ", expected " + inum(dogworks::PACKED_SCHEMA_VERSION);
	}
	const struct {
		const char *key;
		Variant::Type type;
	} top_keys[] = {
		{ "ground_faces", Variant::PACKED_VECTOR3_ARRAY },
		{ "surface_of_face", Variant::PACKED_INT32_ARRAY },
		{ "wall_faces", Variant::ARRAY },
		{ "wall_attr_ids", Variant::PACKED_INT32_ARRAY },
		{ "movers", Variant::ARRAY },
	};
	for (const auto &k : top_keys) {
		problem = check_key(p_packed, where, k.key, k.type);
		if (!problem.is_empty()) {
			return problem;
		}
	}
	const PackedVector3Array ground = p_packed["ground_faces"];
	const PackedInt32Array surface = p_packed["surface_of_face"];
	const Array walls = p_packed["wall_faces"];
	const PackedInt32Array wall_ids = p_packed["wall_attr_ids"];
	const Array movers_in = p_packed["movers"];
	if (ground.size() % 3 != 0) {
		return String("packed key 'ground_faces' has ") + inum(ground.size()) + " vertices, not a multiple of 3";
	}
	if (surface.size() != ground.size() / 3) {
		return String("packed key 'surface_of_face' has ") + inum(surface.size()) + " entries for " + inum(ground.size() / 3) + " ground triangles";
	}
	if (walls.size() != wall_ids.size()) {
		return String("packed key 'wall_faces' has ") + inum(walls.size()) + " entries but 'wall_attr_ids' has " + inum(wall_ids.size());
	}
	for (int64_t k = 0; k < walls.size(); k++) {
		const Variant w = walls[k];
		if (w.get_type() != Variant::PACKED_VECTOR3_ARRAY) {
			return String("packed key 'wall_faces'[") + inum(k) + "] has type " + Variant::get_type_name(w.get_type()) + ", expected PackedVector3Array";
		}
		const PackedVector3Array faces = w;
		if (faces.size() == 0) {
			return String("packed key 'wall_faces'[") + inum(k) + "] is empty (wall shapes are dense)";
		}
		if (faces.size() % 3 != 0) {
			return String("packed key 'wall_faces'[") + inum(k) + "] has " + inum(faces.size()) + " vertices, not a multiple of 3";
		}
	}
	std::vector<int64_t> seen_ids;
	for (int64_t k = 0; k < movers_in.size(); k++) {
		String mover_where = String("packed key 'movers'[") + inum(k) + "]";
		const Variant mv = movers_in[k];
		if (mv.get_type() != Variant::DICTIONARY) {
			return mover_where + " has type " + Variant::get_type_name(mv.get_type()) + ", expected Dictionary";
		}
		const Dictionary m = mv;
		problem = check_key(m, mover_where, "schema_version", Variant::INT);
		if (!problem.is_empty()) {
			return problem;
		}
		if ((int64_t)m["schema_version"] != dogworks::PACKED_SCHEMA_VERSION) {
			return mover_where + " key 'schema_version' is " + inum((int64_t)m["schema_version"]) + ", expected " + inum(dogworks::PACKED_SCHEMA_VERSION);
		}
		const struct {
			const char *key;
			Variant::Type type;
		} mover_keys[] = {
			{ "id", Variant::INT },
			{ "period", Variant::FLOAT },
			{ "solid", Variant::BOOL },
			{ "surface_id", Variant::INT },
			{ "wall_attr_id", Variant::INT },
			{ "shape", Variant::INT },
			{ "half_extents", Variant::VECTOR3 },
			{ "radius", Variant::FLOAT },
			{ "half_height", Variant::FLOAT },
			{ "key_t", Variant::PACKED_FLOAT32_ARRAY },
			{ "key_pos", Variant::PACKED_VECTOR3_ARRAY },
			{ "key_rot", Variant::PACKED_VECTOR4_ARRAY },
		};
		for (const auto &mk : mover_keys) {
			problem = check_key(m, mover_where, mk.key, mk.type);
			if (!problem.is_empty()) {
				return problem;
			}
		}
		problem = mover_layout_error(m, mover_where);
		if (!problem.is_empty()) {
			return problem;
		}
		const int64_t id = m["id"];
		for (size_t i = 0; i < seen_ids.size(); i++) {
			if (seen_ids[i] == id) {
				return mover_where + " key 'id' is " + inum(id) + ", already used by movers[" + inum((int64_t)i) + "] (mover ids are unique)";
			}
		}
		seen_ids.push_back(id);
	}
	return String();
}

Ref<CollisionQuery> CollisionQuery::create(const Dictionary &p_packed) {
	const String problem = validate_packed(p_packed);
	if (!problem.is_empty()) {
		ERR_FAIL_V_MSG(Ref<CollisionQuery>(), String("CollisionQuery.create: ") + problem + "; the query has no geometry");
	}
	PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
	ERR_FAIL_NULL_V_MSG(ps, Ref<CollisionQuery>(), "PhysicsServer3D is missing");
	ERR_FAIL_COND_V_MSG(!dogworks::g_servers_alive, Ref<CollisionQuery>(), "the physics servers are not alive");
	Ref<CollisionQuery> query;
	query.instantiate();
	if (!query->build_from(p_packed, ps)) {
		ERR_FAIL_V_MSG(Ref<CollisionQuery>(), "CollisionQuery.create: the physics server gave no direct space state");
	}
	owners().push_back(query.ptr());
	query->registered = true;
	query->built = true;
	return query;
}

bool CollisionQuery::build_from(const Dictionary &p_packed, PhysicsServer3D *p_ps) {
	space = p_ps->space_create();
	state = p_ps->space_get_direct_state(space);
	if (state == nullptr) {
		p_ps->free_rid(space);
		space = RID();
		return false;
	}
	const PackedInt32Array surface = p_packed["surface_of_face"];
	const PackedInt32Array wall_ids = p_packed["wall_attr_ids"];
	if (surface.size() > 0) {
		surface_of_face.assign(surface.ptr(), surface.ptr() + surface.size());
	}
	if (wall_ids.size() > 0) {
		wall_attr_ids.assign(wall_ids.ptr(), wall_ids.ptr() + wall_ids.size());
	}
	const PackedVector3Array ground = p_packed["ground_faces"];
	const Array walls = p_packed["wall_faces"];
	const auto make_shape = [&](const PackedVector3Array &p_faces) {
		const RID shape = p_ps->concave_polygon_shape_create();
		Dictionary data;
		data["faces"] = p_faces;
		data["backface_collision"] = false;
		p_ps->shape_set_data(shape, data);
		shapes.push_back(shape);
		return shape;
	};
	const auto make_body = [&](int64_t p_layer) {
		const RID body = p_ps->body_create();
		p_ps->body_set_mode(body, PhysicsServer3D::BODY_MODE_STATIC);
		p_ps->body_set_collision_layer(body, (uint32_t)p_layer);
		p_ps->body_set_collision_mask(body, 0);
		p_ps->body_set_space(body, space);
		bodies.push_back(body);
		return body;
	};
	if (ground.size() > 0) {
		const RID shape = make_shape(ground);
		ground_body = make_body(dogworks::GROUND_LAYER);
		p_ps->body_add_shape(ground_body, shape);
	}
	if (walls.size() > 0) {
		wall_body = make_body(dogworks::WALL_LAYER);
		for (int64_t k = 0; k < walls.size(); k++) {
			const PackedVector3Array faces = walls[k];
			p_ps->body_add_shape(wall_body, make_shape(faces));
		}
	}
	const Array movers_in = p_packed["movers"];
	movers.reserve((size_t)movers_in.size());
	for (int64_t k = 0; k < movers_in.size(); k++) {
		const Dictionary m = movers_in[k];
		Mover mover;
		mover.id = (int32_t)(int64_t)m["id"];
		mover.period = m["period"];
		mover.solid = m["solid"];
		mover.surface_id = (int32_t)(int64_t)m["surface_id"];
		mover.wall_attr_id = (int32_t)(int64_t)m["wall_attr_id"];
		mover.shape = (int32_t)(int64_t)m["shape"];
		mover.half_extents = m["half_extents"];
		mover.radius = m["radius"];
		mover.half_height = m["half_height"];
		const PackedFloat32Array key_t = m["key_t"];
		const PackedVector3Array key_pos = m["key_pos"];
		const PackedVector4Array key_rot = m["key_rot"];
		if (key_t.size() > 0) {
			mover.key_t.assign(key_t.ptr(), key_t.ptr() + key_t.size());
		}
		if (key_pos.size() > 0) {
			mover.key_pos.assign(key_pos.ptr(), key_pos.ptr() + key_pos.size());
		}
		for (int64_t i = 0; i < key_rot.size(); i++) {
			const Vector4 r = key_rot[i];
			mover.key_rot.push_back(Quaternion(r.x, r.y, r.z, r.w));
		}
		add_mover(mover);
	}
	rs.resize(movers.size());
	owned_rid_count = (int64_t)bodies.size() + (int64_t)shapes.size() + 1;
	g_live_rids += owned_rid_count;
	return true;
}

void CollisionQuery::add_mover(Mover &p_mover) {
	double bound = 0.0;
	if (p_mover.shape == SHAPE_BOX) {
		bound = p_mover.half_extents.length();
	} else if (p_mover.shape == SHAPE_CAPSULE) {
		bound = p_mover.radius + p_mover.half_height;
	} else {
		bound = std::sqrt(p_mover.radius * p_mover.radius + p_mover.half_height * p_mover.half_height);
	}
	Vector3 lo = p_mover.key_pos[0];
	Vector3 hi = p_mover.key_pos[0];
	for (const Vector3 &p : p_mover.key_pos) {
		lo = Vector3((float)std::min((double)lo.x, (double)p.x), (float)std::min((double)lo.y, (double)p.y), (float)std::min((double)lo.z, (double)p.z));
		hi = Vector3((float)std::max((double)hi.x, (double)p.x), (float)std::max((double)hi.y, (double)p.y), (float)std::max((double)hi.z, (double)p.z));
	}
	const Vector3 centre = (lo + hi) * 0.5f;
	double path_radius = 0.0;
	for (const Vector3 &p : p_mover.key_pos) {
		path_radius = std::max(path_radius, (double)centre.distance_to(p));
	}
	p_mover.shape_bound = bound;
	p_mover.path_centre = centre;
	p_mover.path_reach = path_radius + bound + dogworks::MOVER_CULL_MARGIN;
	const int32_t slot = (int32_t)movers.size();
	if (p_mover.solid) {
		solid_slots.push_back(slot);
	}
	slot_by_id.push_back(std::make_pair(p_mover.id, slot));
	std::sort(slot_by_id.begin(), slot_by_id.end());
	PoseCache cache;
	cache.t = std::numeric_limits<double>::quiet_NaN();
	pose_cache.push_back(cache);
	movers.push_back(p_mover);
}

int CollisionQuery::slot_of(int64_t p_id) const {
	const auto it = std::lower_bound(slot_by_id.begin(), slot_by_id.end(), std::make_pair((int32_t)p_id, (int32_t)-1));
	if (it == slot_by_id.end() || it->first != (int32_t)p_id || (int64_t)it->first != p_id) {
		return -1;
	}
	return it->second;
}

void CollisionQuery::free_server_objects(const std::vector<RID> &p_bodies, const std::vector<RID> &p_shapes, RID p_space) {
	if (!dogworks::g_servers_alive) {
		return;
	}
	PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
	if (ps == nullptr) {
		return;
	}
	for (const RID &body : p_bodies) {
		ps->free_rid(body);
	}
	for (const RID &shape : p_shapes) {
		ps->free_rid(shape);
	}
	if (p_space.is_valid()) {
		ps->free_rid(p_space);
	}
}

void CollisionQuery::release_server_objects() {
	if (built) {
		disposed = true;
	}
	free_server_objects(bodies, shapes, space);
	g_live_rids -= owned_rid_count;
	owned_rid_count = 0;
	bodies.clear();
	shapes.clear();
	space = RID();
	ground_body = RID();
	wall_body = RID();
	state = nullptr;
	surface_of_face.clear();
	wall_attr_ids.clear();
	movers.clear();
	slot_by_id.clear();
	solid_slots.clear();
	pose_cache.clear();
	rs.clear();
	rs_count = 0;
	built = false;
	if (registered) {
		std::vector<CollisionQuery *> &list = owners();
		list.erase(std::remove(list.begin(), list.end(), this), list.end());
		registered = false;
	}
}

void CollisionQuery::release_all_server_objects() {
	// Copy first: release_server_objects() edits the registry while we walk it. Load time only.
	const std::vector<CollisionQuery *> snapshot = owners();
	for (CollisionQuery *query : snapshot) {
		query->release_server_objects();
	}
}

void CollisionQuery::dispose() {
	if (!built) {
		return;
	}
	release_server_objects();
}

CollisionQuery::~CollisionQuery() {
	release_server_objects();
}

int64_t CollisionQuery::live_rid_count() {
	return g_live_rids;
}

int64_t CollisionQuery::blocked_fallback_count() const {
	ERR_FAIL_COND_V(!built, 0);
	return blocked_fallbacks;
}

void CollisionQuery::set_force_rest_miss_for_test(bool p_on) {
	ERR_FAIL_COND(!built);
	force_rest_miss = p_on;
}

Vector3 CollisionQuery::local_point_for_test(int64_t p_mover_id, double p_t, const Vector3 &p_world_point) {
	ERR_FAIL_COND_V(!built, Vector3());
	const int k = slot_of(p_mover_id);
	ERR_FAIL_COND_V_MSG(k < 0, Vector3(), "CollisionQuery.local_point: no mover with that id");
	eval_slot(k, p_t);
	return pose_cache[k].inv.xform(p_world_point);
}

bool CollisionQuery::is_built() const {
	return built;
}

bool CollisionQuery::is_disposed() const {
	return disposed;
}

bool CollisionQuery::has_geometry() const {
	ERR_FAIL_COND_V(!built, false);
	return ground_body.is_valid() || wall_body.is_valid() || !movers.empty();
}

TypedArray<RID> CollisionQuery::owned_rids() const {
	TypedArray<RID> rids;
	ERR_FAIL_COND_V(!built, rids);
	for (const RID &r : bodies) {
		rids.push_back(r);
	}
	for (const RID &r : shapes) {
		rids.push_back(r);
	}
	if (space.is_valid()) {
		rids.push_back(space);
	}
	return rids;
}

RID CollisionQuery::space_rid() const {
	ERR_FAIL_COND_V(!built, RID());
	return space;
}

RID CollisionQuery::ground_body_rid() const {
	ERR_FAIL_COND_V(!built, RID());
	return ground_body;
}

RID CollisionQuery::wall_body_rid() const {
	ERR_FAIL_COND_V(!built, RID());
	return wall_body;
}

void CollisionQuery::set_newton_cap(int64_t p_cap) {
	ERR_FAIL_COND(!built);
	ERR_FAIL_COND_MSG(p_cap < 1, "set_newton_cap: the cap must be >= 1");
	newton_cap = p_cap;
}

bool CollisionQuery::cap_error_reported() const {
	ERR_FAIL_COND_V(!built, false);
	return cap_error_done;
}

double CollisionQuery::closest_local(int64_t p_mover_id, const Vector3 &p_local_point) {
	ERR_FAIL_COND_V(!built, 0.0);
	const int k = slot_of(p_mover_id);
	ERR_FAIL_COND_V_MSG(k < 0, 0.0, "CollisionQuery.closest_local: no mover with that id");
	return closest_local_mover(movers[k], p_local_point);
}

Vector3 CollisionQuery::closest_point() const {
	ERR_FAIL_COND_V(!built, Vector3());
	return cl_point;
}

Vector3 CollisionQuery::closest_normal() const {
	ERR_FAIL_COND_V(!built, Vector3());
	return cl_normal;
}

String CollisionQuery::probe_error(const Vector3 &p_probe_point, int64_t p_probe_surface_id, double p_max_drop) {
	ERR_FAIL_COND_V(!built, String("load probe: the query is not built"));
	if (!(p_max_drop > 0.0)) {
		return String("load probe: max_drop is ") + num(p_max_drop) + " (must be > 0)";
	}
	Ref<GroundHit> hit;
	hit.instantiate();
	Ref<QueryCursor> cursor;
	cursor.instantiate();
	if (!cast_ground(cursor, p_probe_point, Vector3(0, -1, 0), p_max_drop, dogworks::PROBE_T, hit)) {
		if (!has_geometry()) {
			return String("load probe at ") + String(p_probe_point) + " missed: the query has no geometry (its data was null or rejected; see the CollisionQuery error)";
		}
		return String("load probe at ") + String(p_probe_point) + " found no ground within " + num(p_max_drop) + " m below (ground missing there, or facing away: a mirror without the winding flip; has_geometry() counts non-solid movers, which the probe never hits)";
	}
	if (hit->collider_id != 0) {
		return String("load probe at ") + String(p_probe_point) + " hit mover " + inum(hit->collider_id) + " at t = " + num(dogworks::PROBE_T) + " (no solid mover may stand over the probe point at t = 0)";
	}
	if (hit->surface_id == dogworks::SURFACE_NONE) {
		const String setting = "physics/jolt_physics_3d/queries/enable_ray_cast_face_index";
		return String("load probe at ") + String(p_probe_point) + " hit ground with no face index (SURFACE_NONE): " + setting + " is " + String(ProjectSettings::get_singleton()->get_setting(setting, false)) + " (must be true)";
	}
	if (hit->surface_id != p_probe_surface_id) {
		return String("load probe at ") + String(p_probe_point) + " found surface id " + inum(hit->surface_id) + ", not probe_surface_id " + inum(p_probe_surface_id);
	}
	if (!(hit->normal.y > 0.0f)) {
		return String("load probe at ") + String(p_probe_point) + " hit a normal " + String(hit->normal) + " that is not up (normal.y must be > 0)";
	}
	return String();
}

void CollisionQuery::report_cap_error(int64_t p_mover_id, double p_last_safe) {
	ERR_PRINT(String("CollisionQuery: the mover sweep reached its iteration cap against mover ") + inum(p_mover_id) + "; reporting a blocking hit at the last safe fraction " + num(p_last_safe) + " (reported once per query)");
}

// ---------------------------------------------------------------------------------------------
// Per-tick code. Everything between PER_TICK_BEGIN and PER_TICK_END is scanned by tools/core_greps.sh:
// no allocation, no server RID creation, no engine query in its Dictionary form.
// ---------------------------------------------------------------------------------------------

// PER_TICK_BEGIN
int64_t CollisionQuery::majority_surface(const PackedInt32Array &p_ids, const PackedVector3Array &p_points, int64_t p_count,
		const Vector3 &p_centre_of_mass, const Vector3 &p_up, int64_t p_previous_id) {
	const int64_t n = std::min(p_count, std::min((int64_t)p_ids.size(), (int64_t)p_points.size()));
	if (n <= 0) {
		return p_previous_id;
	}
	const int32_t *ids = p_ids.ptr();
	const Vector3 *points = p_points.ptr();
	int best_votes = 0;
	for (int64_t i = 0; i < n; i++) {
		const int votes = votes_of(ids, n, ids[i]);
		if (votes > best_votes) {
			best_votes = votes;
		}
	}
	int64_t best_id = p_previous_id;
	double best_dist_sq = INF_D;
	for (int64_t i = 0; i < n; i++) {
		if (votes_of(ids, n, ids[i]) != best_votes) {
			continue;
		}
		const Vector3 offset = points[i] - p_centre_of_mass;
		const Vector3 planar = offset - p_up * offset.dot(p_up);
		const double dist_sq = planar.length_squared();
		if (dist_sq < best_dist_sq) {
			best_dist_sq = dist_sq;
			best_id = ids[i];
		}
	}
	return best_id;
}

bool CollisionQuery::cast_ground(const Ref<QueryCursor> &p_cursor, const Vector3 &p_origin, const Vector3 &p_dir, double p_max_dist, double p_t, const Ref<GroundHit> &p_out) {
	ERR_FAIL_COND_V(!built, false);
	ERR_FAIL_COND_V(p_cursor.is_null() || !p_cursor->is_built(), false);
	ERR_FAIL_COND_V(p_out.is_null(), false);
	// The same input behaves the same in every build: these guards are not debug-only.
	ERR_FAIL_COND_V_MSG(!p_dir.is_normalized(), false, "CollisionQuery.cast_ground: dir must be unit length");
	QueryCursor &cursor = *p_cursor.ptr();
	GroundHit &out = *p_out.ptr();
	PhysicsRayQueryParameters3D *params = cursor.ray_params.ptr();
	params->set_from(p_origin);
	params->set_to(p_origin + p_dir * (float)p_max_dist);
	// collision_mask and hit_back_faces are fixed once by QueryCursor.
	const bool static_hit = state->intersect_ray_into(cursor.ray_params, cursor.ray_result);
	double best_dist = p_max_dist;
	if (static_hit) {
		write_ground_contact(cursor.ray_result, out);
		best_dist = (out.point - p_origin).dot(p_dir);
	}
	if (solid_slots.empty() || !test_ground_movers(p_origin, p_dir, p_max_dist, best_dist, static_hit, p_t)) {
		return static_hit;
	}
	const Mover &mover = movers[gm_slot];
	out.point = p_origin + p_dir * (float)gm_dist;
	out.normal = gm_normal;
	out.surface_id = mover.surface_id;
	out.collider_id = mover.id;
	out.collider_velocity = gm_velocity;
	return true;
}

bool CollisionQuery::sweep_walls(const Ref<QueryCursor> &p_cursor, const Vector3 &p_from, const Vector3 &p_to, double p_radius, double p_t, const Ref<WallHit> &p_out) {
	ERR_FAIL_COND_V(!built, false);
	ERR_FAIL_COND_V(p_cursor.is_null() || !p_cursor->is_built(), false);
	ERR_FAIL_COND_V(p_out.is_null(), false);
	ERR_FAIL_COND_V_MSG(!(p_radius > 0.0), false, "CollisionQuery.sweep_walls: radius must be > 0");
	QueryCursor &cursor = *p_cursor.ptr();
	WallHit &out = *p_out.ptr();
	PhysicsShapeQueryParameters3D *params = cursor.shape_params.ptr();
	// Compared with the engine's own value, so a cursor object a test or tool changed never leaves a stale radius.
	if ((float)p_radius != cursor.sphere->get_radius()) {
		cursor.sphere->set_radius((float)p_radius);
	}
	// collision_mask is fixed once by QueryCursor, and motion is zero between calls (only sweep_static
	// sets it, and resets it right after its cast).
	params->set_transform(Transform3D(Basis(), p_from));
	PhysicsGetRestInfoResult3D &rest = *cursor.rest_result.ptr();
	const Vector3 motion = p_to - p_from;
	// Step 1, static: the unconditional rest check at from.
	const bool static_inside = state->get_rest_info_into(cursor.shape_params, cursor.rest_result);
	// Step 1, movers: the deepest overlap at from; the same pass runs the mover sweep (step 5).
	if (solid_slots.empty()) {
		ov_slot = -1;
		sm_slot = -1;
	} else {
		test_movers_for_sweep(p_from, motion, p_radius, p_t, !static_inside && motion != Vector3());
	}
	if (static_inside || ov_slot >= 0) {
		if (ov_slot >= 0 && (!static_inside || ov_depth > p_radius - (double)(p_from - rest.get_point()).dot(rest.get_normal()))) {
			write_mover_wall_contact(ov_slot, ov_point, ov_normal, ov_velocity, 0.0, true, out);
		} else {
			write_wall_contact(rest, 0.0, true, out);
		}
		return true;
	}
	if (motion == Vector3()) {
		return false;
	}
	const bool static_hit = sweep_static(cursor, p_from, p_to, motion, p_radius, out);
	// Step 5: merge the mover sweep, smaller fraction first (static wins a tie).
	if (sm_slot >= 0 && (!static_hit || sm_fraction < out.fraction)) {
		write_mover_wall_contact(sm_slot, sm_point, sm_normal, sm_velocity, sm_fraction, false, out);
		return true;
	}
	return static_hit;
}

Transform3D CollisionQuery::mover_pose(int64_t p_id, double p_t) {
	ERR_FAIL_COND_V(!built, Transform3D());
	const int k = slot_of(p_id);
	ERR_FAIL_COND_V_MSG(k < 0, Transform3D(), "CollisionQuery.mover_pose: no mover with that id");
	eval_slot(k, p_t);
	return pose_cache[k].pose;
}

Vector3 CollisionQuery::mover_point_velocity(int64_t p_id, double p_t, const Vector3 &p_p) {
	ERR_FAIL_COND_V(!built, Vector3());
	const int k = slot_of(p_id);
	ERR_FAIL_COND_V_MSG(k < 0, Vector3(), "CollisionQuery.mover_point_velocity: no mover with that id");
	eval_slot(k, p_t);
	return pose_cache[k].lin + ang_of(k).cross(p_p - pose_cache[k].pose.origin);
}

void CollisionQuery::write_ground_contact(const Ref<PhysicsIntersectRayResult3D> &p_result, GroundHit &p_out) const {
	const int64_t face = p_result->get_collider_face_index();
	p_out.point = p_result->get_position();
	p_out.normal = p_result->get_normal();
	if (face >= 0 && face < (int64_t)surface_of_face.size()) {
		p_out.surface_id = surface_of_face[(size_t)face];
	} else {
		p_out.surface_id = dogworks::SURFACE_NONE;
	}
	p_out.collider_id = 0;
	p_out.collider_velocity = Vector3();
}

bool CollisionQuery::sweep_static(QueryCursor &p_cursor, const Vector3 &p_from, const Vector3 &p_to, const Vector3 &p_motion, double p_radius, WallHit &p_out) {
	PhysicsShapeQueryParameters3D *params = p_cursor.shape_params.ptr();
	// Step 2: the cast.
	params->set_motion(p_motion);
	const bool cast_hit = state->cast_motion_into(p_cursor.shape_params, p_cursor.cast_result);
	params->set_motion(Vector3());
	if (cast_hit && (double)p_cursor.cast_result->get_unsafe_fraction() < 1.0) {
		// Step 3: the first contact is inside the motion.
		write_blocked_hit(p_cursor, p_from, p_motion, p_radius, p_out);
		return true;
	}
	// Step 4: clear cast, or the first contact is at the very end: a contact at `to` is a touch.
	params->set_transform(Transform3D(Basis(), p_to));
	if (state->get_rest_info_into(p_cursor.shape_params, p_cursor.rest_result)) {
		write_wall_contact(*p_cursor.rest_result.ptr(), 1.0, false, p_out);
		return true;
	}
	return false;
}

void CollisionQuery::write_blocked_hit(QueryCursor &p_cursor, const Vector3 &p_from, const Vector3 &p_motion, double p_radius, WallHit &p_out) {
	PhysicsShapeQueryParameters3D *params = p_cursor.shape_params.ptr();
	const double safe = p_cursor.cast_result->get_safe_fraction();
	const double unsafe = p_cursor.cast_result->get_unsafe_fraction();
	const Vector3 unsafe_centre = p_from + p_motion * (float)unsafe;
	params->set_transform(Transform3D(Basis(), unsafe_centre));
	if (!force_rest_miss && state->get_rest_info_into(p_cursor.shape_params, p_cursor.rest_result)) {
		write_wall_contact(*p_cursor.rest_result.ptr(), safe, false, p_out);
		return;
	}
	// Jolt can place the unsafe point inside its cast tolerance but short of a rest contact: check again
	// UNSAFE_RETRY_LENGTH further along the motion.
	const double retry = std::min(1.0, unsafe + dogworks::UNSAFE_RETRY_LENGTH / (double)p_motion.length());
	params->set_transform(Transform3D(Basis(), p_from + p_motion * (float)retry));
	if (!force_rest_miss && state->get_rest_info_into(p_cursor.shape_params, p_cursor.rest_result)) {
		write_wall_contact(*p_cursor.rest_result.ptr(), safe, false, p_out);
		return;
	}
	blocked_fallbacks++;
	// Still nothing: keep the hit so the sphere is blocked rather than let through.
	const Vector3 dir = p_motion.normalized();
	p_out.point = unsafe_centre + dir * (float)p_radius;
	p_out.normal = -dir;
	p_out.wall_attr = dogworks::WALL_ATTR_NONE;
	p_out.fraction = safe;
	p_out.started_inside = false;
	p_out.collider_id = 0;
	p_out.collider_velocity = Vector3();
}

void CollisionQuery::write_wall_contact(const PhysicsGetRestInfoResult3D &p_rest, double p_fraction, bool p_started_inside, WallHit &p_out) const {
	const int64_t shape = p_rest.get_collider_shape();
	p_out.point = p_rest.get_point();
	p_out.normal = p_rest.get_normal();
	if (shape >= 0 && shape < (int64_t)wall_attr_ids.size()) {
		p_out.wall_attr = wall_attr_ids[(size_t)shape];
	} else {
		p_out.wall_attr = dogworks::WALL_ATTR_NONE;
	}
	p_out.fraction = p_fraction;
	p_out.started_inside = p_started_inside;
	p_out.collider_id = 0;
	p_out.collider_velocity = Vector3();
}

void CollisionQuery::write_mover_wall_contact(int p_slot, const Vector3 &p_point, const Vector3 &p_normal, const Vector3 &p_velocity, double p_fraction, bool p_started_inside, WallHit &p_out) const {
	const Mover &mover = movers[p_slot];
	p_out.point = p_point;
	p_out.normal = p_normal;
	p_out.wall_attr = mover.wall_attr_id;
	p_out.fraction = p_fraction;
	p_out.started_inside = p_started_inside;
	p_out.collider_id = mover.id;
	p_out.collider_velocity = p_velocity;
}

void CollisionQuery::find_segment(const Mover &p_mover, double p_t) {
	const int n = (int)p_mover.key_t.size();
	double u = Math::fposmod(p_t, p_mover.period);
	// The search runs in float32 (the keys' precision), as the packed-array bsearch of the oracle did.
	const float uf = (float)u;
	int i = (int)(std::upper_bound(p_mover.key_t.begin(), p_mover.key_t.end(), uf) - p_mover.key_t.begin()) - 1;
	double t0 = 0.0;
	double t1 = 0.0;
	if (i >= 0 && i < n - 1) {
		seg_j = i + 1;
		t0 = p_mover.key_t[i];
		t1 = p_mover.key_t[i + 1];
	} else {
		// The loop segment: last key -> first key, reached again at key_t[0] + period.
		if (i < 0 && u < (double)p_mover.key_t[0]) {
			u += p_mover.period;
		}
		i = n - 1;
		seg_j = 0;
		t0 = p_mover.key_t[i];
		t1 = (double)p_mover.key_t[0] + p_mover.period;
	}
	seg_i = i;
	seg_span = t1 - t0;
	seg_alpha = clampd((u - t0) / seg_span, 0.0, 1.0);
}

void CollisionQuery::eval_slot(int p_k, double p_t) {
	PoseCache &pc = pose_cache[p_k];
	if (pc.t == p_t) {
		return;
	}
	const Mover &mover = movers[p_k];
	find_segment(mover, p_t);
	const Vector3 p0 = mover.key_pos[seg_i];
	const Vector3 p1 = mover.key_pos[seg_j];
	const Quaternion q0 = mover.key_rot[seg_i];
	Quaternion q1 = mover.key_rot[seg_j];
	if (q0.dot(q1) < 0.0f) {
		// The shortest path, as slerp takes it; also keeps the angle of ang_of in [0, pi].
		q1 = Quaternion(-q1.x, -q1.y, -q1.z, -q1.w);
	}
	const Transform3D pose(Basis(q0.slerp(q1, (float)seg_alpha)), p0.lerp(p1, (float)seg_alpha));
	pc.pose = pose;
	pc.inv = pose.inverse();
	pc.lin = (p1 - p0) / (float)seg_span;
	pc.ang_ok = false;
	pc.seg_i = seg_i;
	pc.seg_j = seg_j;
	pc.span = seg_span;
	pc.t = p_t;
}

Vector3 CollisionQuery::ang_of(int p_k) {
	PoseCache &pc = pose_cache[p_k];
	if (pc.ang_ok) {
		return pc.ang;
	}
	const Mover &mover = movers[p_k];
	const Quaternion q0 = mover.key_rot[pc.seg_i];
	Quaternion q1 = mover.key_rot[pc.seg_j];
	if (q0.dot(q1) < 0.0f) {
		q1 = Quaternion(-q1.x, -q1.y, -q1.z, -q1.w);
	}
	pc.ang = world_angular_velocity(q0, q1, pc.span);
	pc.ang_ok = true;
	return pc.ang;
}

Vector3 CollisionQuery::world_angular_velocity(const Quaternion &p_q0, const Quaternion &p_q1, double p_span) {
	const Quaternion dq = p_q1 * p_q0.inverse();
	const Vector3 v(dq.x, dq.y, dq.z);
	const double s = v.length();
	if (s > dogworks::SMALL_ROTATION_EPSILON) {
		return v * (float)(2.0 * std::atan2(s, (double)dq.w) / (s * p_span));
	}
	return v * (float)(2.0 / p_span);
}

bool CollisionQuery::in_reach_at(int p_k, const Vector3 &p_a, const Vector3 &p_d, double p_radius, double p_t) {
	eval_slot(p_k, p_t);
	const double shape_reach = movers[p_k].shape_bound + dogworks::MOVER_CULL_MARGIN + p_radius;
	const Vector3 ap = pose_cache[p_k].pose.origin - p_a;
	const double dd = p_d.length_squared();
	double s = 0.0;
	if (dd > 0.0) {
		s = clampd((double)ap.dot(p_d) / dd, 0.0, 1.0);
	}
	return (double)(ap - p_d * (float)s).length_squared() <= shape_reach * shape_reach;
}

bool CollisionQuery::test_ground_movers(const Vector3 &p_origin, const Vector3 &p_dir, double p_max_dist, double p_best_dist, bool p_static_hit, double p_t) {
	gm_slot = -1;
	gm_dist = p_best_dist;
	const Vector3 ray = p_dir * (float)p_max_dist;
	const double dd = ray.length_squared();
	for (size_t n = 0; n < solid_slots.size(); n++) {
		const int k = solid_slots[n];
		// The time-free path-sphere cull.
		const double reach = movers[k].path_reach + 0.0;
		const Vector3 ap = movers[k].path_centre - p_origin;
		double s = 0.0;
		if (dd > 0.0) {
			s = clampd((double)ap.dot(ray) / dd, 0.0, 1.0);
		}
		if ((double)(ap - ray * (float)s).length_squared() > reach * reach || !in_reach_at(k, p_origin, ray, 0.0, p_t)) {
			continue;
		}
		const Transform3D &inv = pose_cache[k].inv;
		if (!ray_local(movers[k], inv.xform(p_origin), inv.basis.xform(p_dir), gm_dist)) {
			continue;
		}
		if (ray_dist < gm_dist || (!p_static_hit && gm_slot < 0)) {
			gm_slot = k;
			gm_dist = ray_dist;
			gm_normal = pose_cache[k].pose.basis.xform(ray_normal);
		}
	}
	if (gm_slot < 0) {
		return false;
	}
	gm_velocity = pose_cache[gm_slot].lin + ang_of(gm_slot).cross(p_origin + p_dir * (float)gm_dist - pose_cache[gm_slot].pose.origin);
	return true;
}

void CollisionQuery::test_movers_for_sweep(const Vector3 &p_from, const Vector3 &p_motion, double p_radius, double p_t, bool p_do_sweep) {
	ov_slot = -1;
	ov_depth = -INF_D;
	rs_count = 0;
	const double dd = p_motion.length_squared();
	for (size_t n = 0; n < solid_slots.size(); n++) {
		const int k = solid_slots[n];
		// The time-free path-sphere cull.
		const double reach = movers[k].path_reach + p_radius;
		const Vector3 ap = movers[k].path_centre - p_from;
		double s = 0.0;
		if (dd > 0.0) {
			s = clampd((double)ap.dot(p_motion) / dd, 0.0, 1.0);
		}
		if ((double)(ap - p_motion * (float)s).length_squared() > reach * reach || !in_reach_at(k, p_from, p_motion, p_radius, p_t)) {
			continue;
		}
		const Transform3D &inv = pose_cache[k].inv;
		const Vector3 local_from = inv.xform(p_from);
		const double gap = closest_local_mover(movers[k], local_from) - p_radius;
		if (gap <= 0.0) {
			if (-gap > ov_depth) {
				ov_slot = k;
				ov_depth = -gap;
				ov_point = cl_point;
				ov_normal = cl_normal;
			}
			continue;
		}
		if (p_do_sweep && ov_slot < 0) {
			const Vector3 local_motion = inv.basis.xform(p_motion);
			SweepCandidate &c = rs[rs_count];
			c.slot = k;
			c.from = local_from;
			c.motion = local_motion;
			c.gap = gap;
			c.slope = cl_normal.dot(local_motion);
			rs_count++;
		}
	}
	sm_slot = -1;
	sm_fraction = INF_D;
	if (ov_slot >= 0) {
		const Transform3D &pose0 = pose_cache[ov_slot].pose;
		ov_point = pose0.xform(ov_point);
		ov_normal = pose0.basis.xform(ov_normal);
		ov_velocity = pose_cache[ov_slot].lin + ang_of(ov_slot).cross(ov_point - pose0.origin);
		return;
	}
	if (rs_count == 0) {
		return;
	}
	const double length = p_motion.length();
	for (int n = 0; n < rs_count; n++) {
		const SweepCandidate &c = rs[n];
		if (!sweep_local(movers[c.slot], c.from, c.motion, length, p_radius, c.gap, c.slope)) {
			continue;
		}
		if (sw_fraction < sm_fraction) {
			sm_slot = c.slot;
			sm_fraction = sw_fraction;
			sm_point = sw_point;
			sm_normal = sw_normal;
		}
	}
	if (sm_slot >= 0) {
		const Transform3D &pose = pose_cache[sm_slot].pose;
		sm_point = pose.xform(sm_point);
		sm_normal = pose.basis.xform(sm_normal);
		sm_velocity = pose_cache[sm_slot].lin + ang_of(sm_slot).cross(sm_point - pose.origin);
	}
}

double CollisionQuery::closest_local_mover(const Mover &p_mover, const Vector3 &p_p) {
	switch (p_mover.shape) {
		case SHAPE_BOX:
			return closest_box(p_mover.half_extents, p_p);
		case SHAPE_CAPSULE:
			return closest_capsule(p_mover.radius, p_mover.half_height, p_p);
		default:
			return closest_cylinder(p_mover.radius, p_mover.half_height, p_p);
	}
}

double CollisionQuery::closest_box(const Vector3 &p_h, const Vector3 &p_p) {
	const Vector3 q = p_p.clamp(-p_h, p_h);
	if (q != p_p) {
		const Vector3 out_v = p_p - q;
		const double d = out_v.length();
		cl_point = q;
		cl_normal = out_v / (float)d;
		return d;
	}
	// Inside or on the surface: the nearest face (ties go x, then y, then z).
	const Vector3 face = p_h - p_p.abs();
	int axis = 0;
	if (face.y < face[axis]) {
		axis = 1;
	}
	if (face.z < face[axis]) {
		axis = 2;
	}
	const double sign_a = p_p[axis] >= 0.0f ? 1.0 : -1.0;
	cl_point = p_p;
	cl_point[axis] = (float)(sign_a * (double)p_h[axis]);
	cl_normal = Vector3();
	cl_normal[axis] = (float)sign_a;
	return -(double)face[axis];
}

double CollisionQuery::closest_capsule(double p_r, double p_hh, const Vector3 &p_p) {
	const Vector3 axis_point(0.0f, (float)clampd(p_p.y, -p_hh, p_hh), 0.0f);
	const Vector3 v = p_p - axis_point;
	const double d = v.length();
	if (d > 0.0) {
		cl_normal = v / (float)d;
	} else {
		cl_normal = Vector3(1, 0, 0); // on the segment itself: any direction is nearest
	}
	cl_point = axis_point + cl_normal * (float)p_r;
	return d - p_r;
}

double CollisionQuery::closest_cylinder(double p_r, double p_hh, const Vector3 &p_p) {
	const double px = p_p.x;
	const double pz = p_p.z;
	const double rho = std::sqrt(px * px + pz * pz);
	const double y_out = std::fabs((double)p_p.y) - p_hh;
	if (rho > p_r || y_out > 0.0) {
		Vector3 q(p_p.x, (float)clampd(p_p.y, -p_hh, p_hh), p_p.z);
		if (rho > p_r) {
			q.x = (float)((double)q.x * (p_r / rho));
			q.z = (float)((double)q.z * (p_r / rho));
		}
		const Vector3 out_v = p_p - q;
		const double d = out_v.length();
		cl_point = q;
		cl_normal = out_v / (float)d;
		return d;
	}
	const double side = p_r - rho;
	const double cap = -y_out;
	if (cap <= side) {
		const double sign_y = p_p.y >= 0.0f ? 1.0 : -1.0;
		cl_point = Vector3(p_p.x, (float)(sign_y * p_hh), p_p.z);
		cl_normal = Vector3(0.0f, (float)sign_y, 0.0f);
		return -cap;
	}
	Vector3 radial(1, 0, 0);
	if (rho > 0.0) {
		radial = Vector3((float)(px / rho), 0.0f, (float)(pz / rho));
	}
	cl_point = Vector3((float)((double)radial.x * p_r), p_p.y, (float)((double)radial.z * p_r));
	cl_normal = radial;
	return -side;
}

bool CollisionQuery::ray_local(const Mover &p_mover, const Vector3 &p_o, const Vector3 &p_d, double p_max_dist) {
	switch (p_mover.shape) {
		case SHAPE_BOX:
			return ray_box(p_mover.half_extents, p_o, p_d, p_max_dist);
		case SHAPE_CAPSULE:
			return ray_capsule(p_mover.radius, p_mover.half_height, p_o, p_d, p_max_dist);
		default:
			return ray_cylinder(p_mover.radius, p_mover.half_height, p_o, p_d, p_max_dist);
	}
}

bool CollisionQuery::ray_box(const Vector3 &p_h, const Vector3 &p_o, const Vector3 &p_d, double p_max_dist) {
	double t_in = -INF_D;
	double t_out = INF_D;
	Vector3 n_in;
	for (int axis = 0; axis < 3; axis++) {
		const double oa = p_o[axis];
		const double da = p_d[axis];
		const double ha = p_h[axis];
		if (std::fabs(da) < dogworks::PARALLEL_EPSILON) {
			if (std::fabs(oa) > ha) {
				return false;
			}
			continue;
		}
		const double s_low = (-ha - oa) / da;
		const double s_high = (ha - oa) / da;
		// Entering through the -ha face when moving +axis, through +ha when moving -axis.
		const double s0 = std::min(s_low, s_high);
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
	if (t_in < 0.0 || t_in > p_max_dist) {
		return false;
	}
	ray_dist = t_in;
	ray_normal = n_in;
	return true;
}

double CollisionQuery::ray_sphere_entry(const Vector3 &p_oc, const Vector3 &p_d, double p_r) {
	const double b = p_oc.dot(p_d);
	const double c = (double)p_oc.length_squared() - p_r * p_r;
	const double disc = b * b - c;
	if (disc < 0.0 || (c > 0.0 && b > 0.0)) {
		return INF_D;
	}
	const double s = -b - std::sqrt(disc);
	return s >= 0.0 ? s : INF_D;
}

bool CollisionQuery::ray_capsule(double p_r, double p_hh, const Vector3 &p_o, const Vector3 &p_d, double p_max_dist) {
	const Vector3 o_axis(0.0f, (float)clampd(p_o.y, -p_hh, p_hh), 0.0f);
	if ((double)(p_o - o_axis).length_squared() < p_r * p_r) {
		return false;
	}
	double best = INF_D;
	Vector3 best_n(0, 1, 0);
	const double dx = p_d.x;
	const double dy = p_d.y;
	const double dz = p_d.z;
	const double ox = p_o.x;
	const double oz = p_o.z;
	const double a = dx * dx + dz * dz;
	const double c = ox * ox + oz * oz - p_r * p_r;
	if (a > dogworks::PARALLEL_EPSILON && c >= 0.0) {
		const double b = ox * dx + oz * dz;
		const double disc = b * b - a * c;
		if (disc >= 0.0) {
			const double s = (-b - std::sqrt(disc)) / a;
			if (s >= 0.0 && std::fabs((double)p_o.y + dy * s) <= p_hh) {
				best = s;
				best_n = Vector3((float)(ox + dx * s), 0.0f, (float)(oz + dz * s)) / (float)p_r;
			}
		}
	}
	for (int end = 0; end < 2; end++) {
		const Vector3 centre(0.0f, (float)(end == 1 ? p_hh : -p_hh), 0.0f);
		const double s2 = ray_sphere_entry(p_o - centre, p_d, p_r);
		if (s2 < best) {
			best = s2;
			best_n = (p_o - centre + p_d * (float)s2) / (float)p_r;
		}
	}
	if (best > p_max_dist) {
		return false;
	}
	ray_dist = best;
	ray_normal = best_n;
	return true;
}

bool CollisionQuery::ray_cylinder(double p_r, double p_hh, const Vector3 &p_o, const Vector3 &p_d, double p_max_dist) {
	double t_in = -INF_D;
	double t_out = INF_D;
	bool entry_is_cap = true;
	const double dx = p_d.x;
	const double dy = p_d.y;
	const double dz = p_d.z;
	const double ox = p_o.x;
	const double oy = p_o.y;
	const double oz = p_o.z;
	if (std::fabs(dy) < dogworks::PARALLEL_EPSILON) {
		if (std::fabs(oy) > p_hh) {
			return false;
		}
	} else {
		const double s_low = (-p_hh - oy) / dy;
		const double s_high = (p_hh - oy) / dy;
		t_in = std::min(s_low, s_high);
		t_out = std::max(s_low, s_high);
	}
	const double a = dx * dx + dz * dz;
	const double c = ox * ox + oz * oz - p_r * p_r;
	if (a < dogworks::PARALLEL_EPSILON) {
		if (c > 0.0) {
			return false;
		}
	} else {
		const double b = ox * dx + oz * dz;
		const double disc = b * b - a * c;
		if (disc < 0.0) {
			return false;
		}
		const double root = std::sqrt(disc);
		if ((-b - root) / a > t_in) {
			t_in = (-b - root) / a;
			entry_is_cap = false;
		}
		t_out = std::min(t_out, (-b + root) / a);
	}
	if (t_in > t_out || t_in < 0.0 || t_in > p_max_dist) {
		return false;
	}
	ray_dist = t_in;
	if (entry_is_cap) {
		ray_normal = Vector3(0.0f, dy < 0.0 ? 1.0f : -1.0f, 0.0f);
	} else {
		ray_normal = Vector3((float)(ox + dx * t_in), 0.0f, (float)(oz + dz * t_in)) / (float)p_r;
	}
	return true;
}

bool CollisionQuery::sweep_local(const Mover &p_mover, const Vector3 &p_local_from, const Vector3 &p_local_motion, double p_length, double p_radius, double p_gap0, double p_slope0) {
	double hi = dogworks::NEWTON_CAPPED;
	const double step_min = dogworks::MOVER_SWEEP_TOLERANCE / p_length;
	double lo = 0.0;
	double f = p_gap0;
	double slope = p_slope0;
	for (int64_t iteration = 0; iteration < newton_cap; iteration++) {
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
		const double fs = closest_local_mover(p_mover, p_local_from + p_local_motion * (float)s) - p_radius;
		if (fs <= 0.0) {
			hi = s;
			break;
		}
		if (s >= 1.0) {
			return false;
		}
		lo = s;
		f = fs;
		slope = cl_normal.dot(p_local_motion);
	}
	if (hi == dogworks::NEWTON_CAPPED) {
		if (!cap_error_done) {
			// Named exception to "no String in per-tick code" (tools/core_greps.sh allow-list: report_cap_error):
			// reached once per query, only when the Newton cap fails closed (never seen); it builds one message.
			cap_error_done = true;
			report_cap_error(p_mover.id, lo);
		}
		sw_fraction = lo;
		closest_local_mover(p_mover, p_local_from + p_local_motion * (float)lo);
		sw_point = cl_point;
		sw_normal = cl_normal;
		return true;
	}
	int64_t iterations = 0;
	while ((hi - lo) * p_length > dogworks::MOVER_SWEEP_TOLERANCE && iterations < dogworks::MOVER_SWEEP_MAX_ITERATIONS) {
		const double mid = (lo + hi) * 0.5;
		if (closest_local_mover(p_mover, p_local_from + p_local_motion * (float)mid) - p_radius <= 0.0) {
			hi = mid;
		} else {
			lo = mid;
		}
		iterations++;
	}
	if ((1.0 - hi) * p_length < dogworks::MOVER_SWEEP_TOLERANCE && closest_local_mover(p_mover, p_local_from + p_local_motion) - p_radius <= 0.0) {
		sw_fraction = 1.0;
	} else {
		sw_fraction = lo;
		closest_local_mover(p_mover, p_local_from + p_local_motion * (float)lo);
	}
	sw_point = cl_point;
	sw_normal = cl_normal;
	return true;
}
// PER_TICK_END
