#include "toolchain_probe.h"

#include "register_types.h"

#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <algorithm>

using namespace godot;

namespace {
/// Every probe that owns server RIDs. Touched only in create(), dispose(), the destructor and the
/// release-all path (load time, main thread), never per tick.
std::vector<ToolchainProbe *> &owners() {
	static std::vector<ToolchainProbe *> list;
	return list;
}
/// Server RIDs owned by all probes, for the test-only live_rid_count().
int64_t g_live_rids = 0;
} // namespace

void ToolchainProbe::_bind_methods() {
	ClassDB::bind_static_method(get_class_static(), D_METHOD("validate_packed", "packed"), &ToolchainProbe::validate_packed);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("create", "packed"), &ToolchainProbe::create);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("live_rid_count"), &ToolchainProbe::live_rid_count);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("crash_for_test"), &ToolchainProbe::crash_for_test);
	ClassDB::bind_method(D_METHOD("is_built"), &ToolchainProbe::is_built);
	ClassDB::bind_method(D_METHOD("get_output_length"), &ToolchainProbe::get_output_length);
	ClassDB::bind_method(D_METHOD("echo_int", "value"), &ToolchainProbe::echo_int);
	ClassDB::bind_method(D_METHOD("echo_scalar", "value"), &ToolchainProbe::echo_scalar);
	ClassDB::bind_method(D_METHOD("echo_vector3", "value"), &ToolchainProbe::echo_vector3);
	ClassDB::bind_method(D_METHOD("sum_packed", "values"), &ToolchainProbe::sum_packed);
	ClassDB::bind_method(D_METHOD("step", "tick"), &ToolchainProbe::step);
	ClassDB::bind_method(D_METHOD("output"), &ToolchainProbe::output);
	ClassDB::bind_method(D_METHOD("rid_count"), &ToolchainProbe::rid_count);
	ClassDB::bind_method(D_METHOD("dispose"), &ToolchainProbe::dispose);
}

String ToolchainProbe::validate_packed(const PackedFloat64Array &p_packed) {
	if (p_packed.size() != 2) {
		return String("packed: expected 2 values [output_length, rid_servers], got ") + String::num_int64(p_packed.size());
	}
	const double length = p_packed[0];
	if (!(length >= 1.0 && length <= (double)MAX_COUNT) || length != Math::floor(length)) {
		return String("packed[0] output_length: must be an integer in 1..") + String::num_int64(MAX_COUNT) + ", got " + String::num(length);
	}
	const double servers = p_packed[1];
	if (servers != 0.0 && servers != 1.0) {
		return String("packed[1] rid_servers: must be 0 or 1, got ") + String::num(servers);
	}
	return String();
}

Ref<ToolchainProbe> ToolchainProbe::create(const PackedFloat64Array &p_packed) {
	const String problem = validate_packed(p_packed);
	if (!problem.is_empty()) {
		ERR_FAIL_V_MSG(Ref<ToolchainProbe>(), problem);
	}
	PhysicsServer3D *ps = nullptr;
	if (p_packed[1] == 1.0) {
		ps = PhysicsServer3D::get_singleton();
		ERR_FAIL_NULL_V_MSG(ps, Ref<ToolchainProbe>(), "PhysicsServer3D is missing");
	}
	Ref<ToolchainProbe> probe;
	probe.instantiate();
	probe->output_length = (int64_t)p_packed[0];
	for (int i = 0; i < 2; i++) {
		probe->buffers[i].resize(probe->output_length);
		probe->buffers[i].fill(0.0f);
	}
	if (ps != nullptr) {
		probe->space = ps->space_create();
		ps->space_set_active(probe->space, false);
		probe->shape = ps->sphere_shape_create();
		ps->shape_set_data(probe->shape, 0.5);
		probe->body = ps->body_create();
		ps->body_set_space(probe->body, probe->space);
		ps->body_add_shape(probe->body, probe->shape);
		probe->owned_rids = 3;
		g_live_rids += probe->owned_rids;
		owners().push_back(probe.ptr());
		probe->registered = true;
	}
	probe->built = true;
	return probe;
}

void ToolchainProbe::crash_for_test() {
	OS *os = OS::get_singleton();
	ERR_FAIL_NULL(os);
	ERR_FAIL_COND_MSG(!os->has_feature("debug"), "crash_for_test() runs only when OS.has_feature(\"debug\")");
	volatile int *null_target = nullptr;
	*null_target = 1; // deliberate null write (test-only): the stack of this function is the evidence
}

int64_t ToolchainProbe::live_rid_count() {
	return g_live_rids;
}

bool ToolchainProbe::is_built() const {
	return built;
}

int64_t ToolchainProbe::get_output_length() const {
	ERR_FAIL_COND_V(!built, 0);
	return output_length;
}

int64_t ToolchainProbe::echo_int(int64_t p_value) const {
	ERR_FAIL_COND_V(!built, 0);
	return p_value;
}

double ToolchainProbe::echo_scalar(double p_value) const {
	ERR_FAIL_COND_V(!built, 0.0);
	return p_value;
}

Vector3 ToolchainProbe::echo_vector3(const Vector3 &p_value) const {
	ERR_FAIL_COND_V(!built, Vector3());
	return p_value;
}

double ToolchainProbe::sum_packed(const PackedFloat32Array &p_values) const {
	ERR_FAIL_COND_V(!built, 0.0);
	const int64_t n = p_values.size();
	if (n == 0) {
		return 0.0;
	}
	const float *r = p_values.ptr();
	double sum = 0.0;
	for (int64_t i = 0; i < n; i++) {
		sum += r[i];
	}
	return sum;
}

void ToolchainProbe::step(int64_t p_tick) {
	ERR_FAIL_COND(!built);
	// Writes through ptrw(): if the caller still holds this buffer, the write detaches it once.
	float *w = buffers[p_tick & 1].ptrw();
	for (int64_t i = 0; i < output_length; i++) {
		w[i] = (float)((double)p_tick * 0.5 + (double)i);
	}
	last_tick = p_tick;
}

PackedFloat32Array ToolchainProbe::output() const {
	ERR_FAIL_COND_V(!built, PackedFloat32Array());
	return buffers[last_tick & 1];
}

int64_t ToolchainProbe::rid_count() const {
	ERR_FAIL_COND_V(!built, 0);
	return (int64_t)body.is_valid() + (int64_t)shape.is_valid() + (int64_t)space.is_valid();
}

void ToolchainProbe::free_server_objects(RID p_body, RID p_shape, RID p_space) {
	if (!dogworks::g_servers_alive) {
		return;
	}
	PhysicsServer3D *ps = PhysicsServer3D::get_singleton();
	if (ps == nullptr) {
		return;
	}
	if (p_body.is_valid()) {
		ps->free_rid(p_body);
	}
	if (p_shape.is_valid()) {
		ps->free_rid(p_shape);
	}
	if (p_space.is_valid()) {
		ps->free_rid(p_space);
	}
}

void ToolchainProbe::release_server_objects() {
	free_server_objects(body, shape, space);
	body = RID();
	shape = RID();
	space = RID();
	g_live_rids -= owned_rids;
	owned_rids = 0;
	if (registered) {
		std::vector<ToolchainProbe *> &list = owners();
		list.erase(std::remove(list.begin(), list.end(), this), list.end());
		registered = false;
	}
}

void ToolchainProbe::release_all_server_objects() {
	// Copy first: release_server_objects() edits the registry while we walk it. Load time only.
	const std::vector<ToolchainProbe *> snapshot = owners();
	for (ToolchainProbe *probe : snapshot) {
		probe->release_server_objects();
		probe->built = false;
	}
}

void ToolchainProbe::dispose() {
	if (!built) {
		return;
	}
	release_server_objects();
	built = false;
}

ToolchainProbe::~ToolchainProbe() {
	release_server_objects();
}
