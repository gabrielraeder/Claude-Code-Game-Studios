#include "race/race_sim.h"

#include "core/dogworks_core.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>

using namespace godot;
namespace rl = dogworks::race;

namespace {
/// Every built RaceSim, for `live_count()` and the hot-reload release. Touched only in create(), dispose(), the
/// destructor and release_all() (load time, main thread), never per tick.
std::vector<RaceSim *> &owners() {
	static std::vector<RaceSim *> list;
	return list;
}

/// Microseconds on a monotonic clock. Allocation-free; the stage timers use it.
double now_usec() {
	return std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

/// True when every one of `p_count` floats is finite.
bool all_finite(const float *p_values, int64_t p_count) {
	for (int64_t i = 0; i < p_count; i++) {
		if (!std::isfinite(p_values[i])) {
			return false;
		}
	}
	return true;
}

/// Reads a basis from three consecutive column vectors.
Basis basis_from(const float *p_columns) {
	return Basis(Vector3(p_columns[0], p_columns[1], p_columns[2]), Vector3(p_columns[3], p_columns[4], p_columns[5]), Vector3(p_columns[6], p_columns[7], p_columns[8]));
}

/// Checks one setup key: present and of the Variant type `p_type`. Appends nothing and returns "" when fine.
String check_key(const Dictionary &p_dict, const String &p_key, Variant::Type p_type) {
	if (!p_dict.has(p_key)) {
		return String("setup.") + p_key + ": missing key";
	}
	const Variant value = p_dict.get(p_key, Variant());
	if (value.get_type() != p_type) {
		return String("setup.") + p_key + ": wrong type (expected " + Variant::get_type_name(p_type) + ", got " + Variant::get_type_name(value.get_type()) + ")";
	}
	return String();
}
} // namespace

// Stage-order guard: refused in debug and release builds (ADR-0007 section 3), state untouched.
#define RS_GUARD_BUILT(m_name) ERR_FAIL_COND_MSG(!built, "RaceSim." m_name ": the object is not built (use RaceSim.create)")
#define RS_GUARD_PHASE(m_name, m_phase) ERR_FAIL_COND_MSG(phase != (m_phase), "RaceSim." m_name ": stage called out of order")

void RaceSim::_bind_methods() {
#define RS_CONST(m_name) ClassDB::bind_integer_constant(get_class_static(), StringName(), #m_name, rl::m_name)
	RS_CONST(SETUP_SCHEMA_VERSION);
	RS_CONST(MAX_SLOTS);
	RS_CONST(MAX_SEEDS);
	RS_CONST(MAX_EVENT_CAPACITY);
	RS_CONST(STAGE_BEGIN_TICK);
	RS_CONST(STAGE_APPLY_EVENTS);
	RS_CONST(STAGE_STEP_DRIVE);
	RS_CONST(STAGE_STEP_BODIES);
	RS_CONST(STAGE_SET_REMOTE);
	RS_CONST(STAGE_STEP_CONTACT);
	RS_CONST(STAGE_PROGRESS_ITEMS_HAZARDS);
	RS_CONST(STAGE_END_TICK);
	RS_CONST(STAGE_COUNT);
	RS_CONST(ROLE_LOCAL);
	RS_CONST(ROLE_BOT);
	RS_CONST(ROLE_REMOTE);
	RS_CONST(DRIVER_STRIDE);
	RS_CONST(DRIVER_STEER);
	RS_CONST(DRIVER_THROTTLE);
	RS_CONST(DRIVER_BRAKE);
	RS_CONST(DRIVER_DRIFT);
	RS_CONST(DRIVER_HOP);
	RS_CONST(DRIVER_ITEM_USE);
	RS_CONST(SNAP_STRIDE);
	RS_CONST(SNAP_POS);
	RS_CONST(SNAP_BASIS);
	RS_CONST(SNAP_VEL);
	RS_CONST(SNAP_SPEED);
	RS_CONST(SNAP_FLAGS);
	RS_CONST(SNAP_KNOCK);
	RS_CONST(SNAP_STATE);
	RS_CONST(SNAP_TICK);
	RS_CONST(SNAP_FLAG_TELEPORTED);
	RS_CONST(SNAP_FLAG_BUMPED);
	RS_CONST(SNAP_FLAG_HELD);
	RS_CONST(SNAP_FLAG_CONTACT_ELIGIBLE);
	RS_CONST(REMOTE_STRIDE);
	RS_CONST(PLACE_STRIDE);
	RS_CONST(PROG_STRIDE);
	RS_CONST(PROG_DISTANCE);
	RS_CONST(PROG_LAP);
	RS_CONST(PROG_RANK);
	RS_CONST(PROG_FLAGS);
	RS_CONST(PROG_FLAG_MOVED);
	RS_CONST(PROG_FLAG_SAFE);
	RS_CONST(PROG_FLAG_FINISHED);
	RS_CONST(EVENT_HEADER_STRIDE);
	RS_CONST(EVENT_SLOT);
	RS_CONST(EVENT_KIND);
	RS_CONST(EVENT_PAYLOAD_OFFSET);
	RS_CONST(EVENT_KIND_KNOCK);
	RS_CONST(EVENT_KIND_PICKUP);
	RS_CONST(EVENT_KIND_ITEM_HIT);
	RS_CONST(EVENT_PAYLOAD_KNOCK);
	RS_CONST(EVENT_PAYLOAD_PICKUP);
	RS_CONST(EVENT_PAYLOAD_ITEM_HIT);
	RS_CONST(EVENT_PAYLOAD_MAX);
#undef RS_CONST

	ClassDB::bind_static_method(get_class_static(), D_METHOD("validate_packed", "setup"), &RaceSim::validate_packed);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("create", "setup"), &RaceSim::create);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("live_count"), &RaceSim::live_count);
	ClassDB::bind_method(D_METHOD("is_built"), &RaceSim::is_built);
	ClassDB::bind_method(D_METHOD("dispose"), &RaceSim::dispose);

	ClassDB::bind_method(D_METHOD("begin_tick", "tick"), &RaceSim::begin_tick);
	ClassDB::bind_method(D_METHOD("apply_events", "headers", "payload"), &RaceSim::apply_events);
	ClassDB::bind_method(D_METHOD("step_drive", "driver_input_packed"), &RaceSim::step_drive);
	ClassDB::bind_method(D_METHOD("step_bodies"), &RaceSim::step_bodies);
	ClassDB::bind_method(D_METHOD("set_remote", "remote_snaps_packed", "contact_eligible_mask"), &RaceSim::set_remote);
	ClassDB::bind_method(D_METHOD("step_contact"), &RaceSim::step_contact);
	ClassDB::bind_method(D_METHOD("step_progress_items_hazards"), &RaceSim::step_progress_items_hazards);
	ClassDB::bind_method(D_METHOD("end_tick"), &RaceSim::end_tick);
	ClassDB::bind_method(D_METHOD("place", "slot", "pose_packed"), &RaceSim::place);
	ClassDB::bind_method(D_METHOD("hold", "slot_mask"), &RaceSim::hold);

	ClassDB::bind_method(D_METHOD("snapshots"), &RaceSim::snapshots);
	ClassDB::bind_method(D_METHOD("progress"), &RaceSim::progress);
	ClassDB::bind_method(D_METHOD("stage_usec"), &RaceSim::stage_usec);
	ClassDB::bind_method(D_METHOD("event_headers"), &RaceSim::event_headers);
	ClassDB::bind_method(D_METHOD("event_payload"), &RaceSim::event_payload);
	ClassDB::bind_method(D_METHOD("event_count"), &RaceSim::event_count);
	ClassDB::bind_method(D_METHOD("events_overflowed"), &RaceSim::events_overflowed);
	ClassDB::bind_method(D_METHOD("snapshot_position", "slot"), &RaceSim::snapshot_position);
	ClassDB::bind_method(D_METHOD("snapshot_basis", "slot"), &RaceSim::snapshot_basis);
	ClassDB::bind_method(D_METHOD("snapshot_velocity", "slot"), &RaceSim::snapshot_velocity);
	ClassDB::bind_method(D_METHOD("snapshot_speed", "slot"), &RaceSim::snapshot_speed);
	ClassDB::bind_method(D_METHOD("snapshot_flags", "slot"), &RaceSim::snapshot_flags);
	ClassDB::bind_method(D_METHOD("progress_distance", "slot"), &RaceSim::progress_distance);
	ClassDB::bind_method(D_METHOD("progress_lap", "slot"), &RaceSim::progress_lap);
	ClassDB::bind_method(D_METHOD("progress_rank", "slot"), &RaceSim::progress_rank);

	ClassDB::bind_method(D_METHOD("slot_count"), &RaceSim::slot_count);
	ClassDB::bind_method(D_METHOD("slot_roles"), &RaceSim::slot_roles);
	ClassDB::bind_method(D_METHOD("local_slot_count"), &RaceSim::local_slot_count);
	ClassDB::bind_method(D_METHOD("event_capacity"), &RaceSim::event_capacity);
	ClassDB::bind_method(D_METHOD("consumer_count"), &RaceSim::consumer_count);
	ClassDB::bind_method(D_METHOD("consumer_seed", "consumer"), &RaceSim::consumer_seed);
	ClassDB::bind_method(D_METHOD("tick"), &RaceSim::tick);
	ClassDB::bind_method(D_METHOD("tick_time"), &RaceSim::tick_time);

	ClassDB::bind_method(D_METHOD("debug_emit_event", "slot", "kind", "payload"), &RaceSim::debug_emit_event);
	ClassDB::bind_method(D_METHOD("debug_write_progress", "slot", "field", "value"), &RaceSim::debug_write_progress);
	ClassDB::bind_method(D_METHOD("debug_drive_rows", "slot"), &RaceSim::debug_drive_rows);
	ClassDB::bind_method(D_METHOD("debug_start_rows", "slot"), &RaceSim::debug_start_rows);
	ClassDB::bind_method(D_METHOD("debug_integrated", "slot"), &RaceSim::debug_integrated);
	ClassDB::bind_method(D_METHOD("debug_bot_decisions", "slot"), &RaceSim::debug_bot_decisions);
}

String RaceSim::validate_packed(const Dictionary &p_packed) {
	const Array keys = p_packed.keys();
	for (int64_t i = 0; i < keys.size(); i++) {
		const Variant key = keys[i];
		const String name = key.get_type() == Variant::STRING || key.get_type() == Variant::STRING_NAME ? String(key) : String();
		if (name != "schema_version" && name != "slot_count" && name != "slot_roles" && name != "seeds" && name != "event_capacity") {
			return String("setup: unknown key ") + String(key);
		}
	}
	String problem = check_key(p_packed, "schema_version", Variant::INT);
	if (!problem.is_empty()) {
		return problem;
	}
	if ((int64_t)p_packed.get("schema_version", Variant()) != rl::SETUP_SCHEMA_VERSION) {
		return String("setup.schema_version: unsupported version ") + String::num_int64((int64_t)p_packed.get("schema_version", Variant())) + " (this build reads " + String::num_int64(rl::SETUP_SCHEMA_VERSION) + ")";
	}
	problem = check_key(p_packed, "slot_count", Variant::INT);
	if (!problem.is_empty()) {
		return problem;
	}
	const int64_t slot_count = (int64_t)p_packed.get("slot_count", Variant());
	if (slot_count < 1 || slot_count > rl::MAX_SLOTS) {
		return String("setup.slot_count: must be in 1..") + String::num_int64(rl::MAX_SLOTS) + ", got " + String::num_int64(slot_count);
	}
	problem = check_key(p_packed, "slot_roles", Variant::PACKED_INT32_ARRAY);
	if (!problem.is_empty()) {
		return problem;
	}
	const PackedInt32Array roles = p_packed.get("slot_roles", Variant());
	if (roles.size() != slot_count) {
		return String("setup.slot_roles: needs one role per slot (") + String::num_int64(slot_count) + "), got " + String::num_int64(roles.size());
	}
	for (int64_t i = 0; i < roles.size(); i++) {
		if (roles[i] < rl::ROLE_LOCAL || roles[i] > rl::ROLE_REMOTE) {
			return String("setup.slot_roles[") + String::num_int64(i) + "]: must be 0 (local), 1 (bot) or 2 (remote), got " + String::num_int64(roles[i]);
		}
	}
	problem = check_key(p_packed, "seeds", Variant::PACKED_INT64_ARRAY);
	if (!problem.is_empty()) {
		return problem;
	}
	const PackedInt64Array seeds = p_packed.get("seeds", Variant());
	if (seeds.size() < 1 || seeds.size() > rl::MAX_SEEDS) {
		return String("setup.seeds: needs 1..") + String::num_int64(rl::MAX_SEEDS) + " seeds, got " + String::num_int64(seeds.size());
	}
	problem = check_key(p_packed, "event_capacity", Variant::INT);
	if (!problem.is_empty()) {
		return problem;
	}
	const int64_t capacity = (int64_t)p_packed.get("event_capacity", Variant());
	if (capacity < 1 || capacity > rl::MAX_EVENT_CAPACITY) {
		return String("setup.event_capacity: must be in 1..") + String::num_int64(rl::MAX_EVENT_CAPACITY) + ", got " + String::num_int64(capacity);
	}
	return String();
}

Ref<RaceSim> RaceSim::create(const Dictionary &p_packed) {
	const String problem = validate_packed(p_packed);
	if (!problem.is_empty()) {
		ERR_FAIL_V_MSG(Ref<RaceSim>(), problem);
	}
	Ref<RaceSim> sim;
	sim.instantiate();
	sim->slot_count_ = (int64_t)p_packed.get("slot_count", Variant());
	sim->capacity = (int64_t)p_packed.get("event_capacity", Variant());
	const PackedInt32Array roles = p_packed.get("slot_roles", Variant());
	const PackedInt64Array seeds = p_packed.get("seeds", Variant());
	sim->roles.assign(roles.ptr(), roles.ptr() + roles.size());
	sim->slots.assign((size_t)sim->slot_count_, SlotState());
	for (int32_t role : sim->roles) {
		sim->local_count += role == rl::ROLE_LOCAL ? 1 : 0;
		sim->remote_count += role == rl::ROLE_REMOTE ? 1 : 0;
	}
	for (int64_t i = 0; i < seeds.size(); i++) {
		sim->seeds.push_back(seeds[i]);
		Ref<RandomNumberGenerator> rng;
		rng.instantiate();
		rng->set_seed((uint64_t)seeds[i]);
		sim->rngs.push_back(rng);
	}
	// Every buffer is sized and zero-filled here (ADR-0007 section 4: no allocation after build).
	for (int b = 0; b < 2; b++) {
		sim->snap_buf[b].resize(sim->slot_count_ * rl::SNAP_STRIDE);
		sim->snap_buf[b].fill(0.0f);
		sim->prog_buf[b].resize(sim->slot_count_ * rl::PROG_STRIDE);
		sim->prog_buf[b].fill(0.0f);
		sim->usec_buf[b].resize(rl::STAGE_COUNT);
		sim->usec_buf[b].fill(0.0);
		sim->head_buf[b].resize(sim->capacity * rl::EVENT_HEADER_STRIDE);
		sim->head_buf[b].fill(0);
		sim->payload_buf[b].resize(sim->capacity * rl::EVENT_PAYLOAD_MAX);
		sim->payload_buf[b].fill(0.0f);
		sim->write_snapshots(sim->snap_buf[b].ptrw(), -1);
	}
	owners().push_back(sim.ptr());
	sim->registered = true;
	sim->built = true;
	return sim;
}

int64_t RaceSim::live_count() {
	return (int64_t)owners().size();
}

void RaceSim::release_all() {
	const std::vector<RaceSim *> snapshot = owners();
	for (RaceSim *sim : snapshot) {
		sim->release_buffers();
		sim->built = false;
	}
}

void RaceSim::release_buffers() {
	if (registered) {
		std::vector<RaceSim *> &list = owners();
		list.erase(std::remove(list.begin(), list.end(), this), list.end());
		registered = false;
	}
	for (int b = 0; b < 2; b++) {
		snap_buf[b].clear();
		prog_buf[b].clear();
		usec_buf[b].clear();
		head_buf[b].clear();
		payload_buf[b].clear();
	}
	slots.clear();
	roles.clear();
	rngs.clear();
	seeds.clear();
}

bool RaceSim::is_built() const {
	return built;
}

void RaceSim::dispose() {
	if (!built) {
		return;
	}
	release_buffers();
	built = false;
}

RaceSim::~RaceSim() {
	release_buffers();
}

void RaceSim::write_snapshots(float *p_out, int64_t p_tick) const {
	for (int64_t s = 0; s < slot_count_; s++) {
		const SlotState &st = slots[(size_t)s];
		float *row = p_out + s * rl::SNAP_STRIDE;
		row[rl::SNAP_POS + 0] = st.position.x;
		row[rl::SNAP_POS + 1] = st.position.y;
		row[rl::SNAP_POS + 2] = st.position.z;
		for (int c = 0; c < 3; c++) {
			const Vector3 col = st.basis.get_column(c);
			row[rl::SNAP_BASIS + c * 3 + 0] = col.x;
			row[rl::SNAP_BASIS + c * 3 + 1] = col.y;
			row[rl::SNAP_BASIS + c * 3 + 2] = col.z;
		}
		row[rl::SNAP_VEL + 0] = st.velocity.x;
		row[rl::SNAP_VEL + 1] = st.velocity.y;
		row[rl::SNAP_VEL + 2] = st.velocity.z;
		row[rl::SNAP_SPEED] = st.speed;
		int flags = 0;
		flags |= st.teleported_pending ? rl::SNAP_FLAG_TELEPORTED : 0;
		flags |= st.held ? rl::SNAP_FLAG_HELD : 0;
		flags |= st.contact_eligible ? rl::SNAP_FLAG_CONTACT_ELIGIBLE : 0;
		row[rl::SNAP_FLAGS] = (float)flags;
		row[rl::SNAP_KNOCK] = 0.0f;
		row[rl::SNAP_STATE] = 0.0f;
		row[rl::SNAP_TICK] = (float)p_tick;
	}
}

// ---------------------------------------------------------------------------------------------------------------
// The per-tick code. tools/core_greps.sh scans the region below: no allocation, no String/Variant/Dictionary
// construction, no *_create( call and no random source (ADR-0007 section 4).
// PER_TICK_BEGIN
void RaceSim::begin_tick(int64_t p_tick) {
	RS_GUARD_BUILT("begin_tick");
	RS_GUARD_PHASE("begin_tick", 0);
	ERR_FAIL_COND_MSG(p_tick < 0, "RaceSim.begin_tick: the tick number must not be negative");
	const double start = now_usec();
	for (int i = 0; i < rl::STAGE_COUNT; i++) {
		usec_scratch[i] = 0.0;
	}
	current_tick = p_tick;
	current_t = (double)p_tick * DogworksCore::SIM_DT;
	hold_active = hold_pending;
	contact_mask = 0;
	for (int64_t s = 0; s < slot_count_; s++) {
		slots[(size_t)s].held = ((hold_active >> s) & 1) != 0;
		slots[(size_t)s].contact_eligible = false;
	}
	// Progress state carries over from the last published tick; the stages that own it rewrite their part.
	const int work = published ^ 1;
	std::memcpy(prog_buf[work].ptrw(), prog_buf[published].ptr(), (size_t)(slot_count_ * rl::PROG_STRIDE) * sizeof(float));
	phase = 1;
	record_stage(rl::STAGE_BEGIN_TICK, start);
}

void RaceSim::apply_events(const PackedInt32Array &p_headers, const PackedFloat32Array &p_payload) {
	RS_GUARD_BUILT("apply_events");
	RS_GUARD_PHASE("apply_events", 1);
	const int64_t header_count = p_headers.size();
	ERR_FAIL_COND_MSG(header_count % rl::EVENT_HEADER_STRIDE != 0, "RaceSim.apply_events: the headers are not whole rows of slot, kind, payload offset");
	const int64_t rows = header_count / rl::EVENT_HEADER_STRIDE;
	const int64_t payload_count = p_payload.size();
	const int32_t *h = rows > 0 ? p_headers.ptr() : nullptr;
	const float *pl = payload_count > 0 ? p_payload.ptr() : nullptr;
	const double start = now_usec();
	// First pass: validate every row, so a refused call has changed nothing.
	for (int64_t r = 0; r < rows; r++) {
		const int32_t *row = h + r * rl::EVENT_HEADER_STRIDE;
		const int count = rl::payload_floats(row[rl::EVENT_KIND]);
		ERR_FAIL_COND_MSG(row[rl::EVENT_SLOT] < 0 || row[rl::EVENT_SLOT] >= slot_count_, "RaceSim.apply_events: an event row names a slot out of range");
		ERR_FAIL_COND_MSG(count < 0, "RaceSim.apply_events: an event row has an unknown kind");
		ERR_FAIL_COND_MSG(row[rl::EVENT_PAYLOAD_OFFSET] < 0 || (int64_t)row[rl::EVENT_PAYLOAD_OFFSET] + count > payload_count, "RaceSim.apply_events: an event row reads past the payload");
	}
	for (int64_t r = 0; r < rows; r++) {
		const int32_t *row = h + r * rl::EVENT_HEADER_STRIDE;
		hook_apply_event(row[rl::EVENT_SLOT], row[rl::EVENT_KIND], pl + row[rl::EVENT_PAYLOAD_OFFSET]);
	}
	phase = 2;
	record_stage(rl::STAGE_APPLY_EVENTS, start);
}

void RaceSim::step_drive(const PackedFloat32Array &p_driver_input_packed) {
	RS_GUARD_BUILT("step_drive");
	RS_GUARD_PHASE("step_drive", 2);
	const int64_t value_count = p_driver_input_packed.size();
	ERR_FAIL_COND_MSG(value_count % rl::DRIVER_STRIDE != 0, "RaceSim.step_drive: wrong row width (a driver row is DRIVER_STRIDE floats)");
	ERR_FAIL_COND_MSG(value_count / rl::DRIVER_STRIDE != local_count, "RaceSim.step_drive: wrong row count (one row per local slot)");
	const double start = now_usec();
	const float *rows = value_count > 0 ? p_driver_input_packed.ptr() : nullptr;
	int64_t next_row = 0;
	for (int64_t s = 0; s < slot_count_; s++) {
		const int32_t role = roles[(size_t)s];
		if (role == rl::ROLE_LOCAL) {
			const float *row = rows + next_row * rl::DRIVER_STRIDE;
			next_row++;
			if (slots[(size_t)s].held) {
				hook_start_logic(s, row);
			} else {
				hook_drive(s, row);
			}
		} else if (role == rl::ROLE_BOT) {
			hook_bot_decision(s);
		}
	}
	phase = 3;
	record_stage(rl::STAGE_STEP_DRIVE, start);
}

void RaceSim::step_bodies() {
	RS_GUARD_BUILT("step_bodies");
	RS_GUARD_PHASE("step_bodies", 3);
	const double start = now_usec();
	for (int64_t s = 0; s < slot_count_; s++) {
		if (roles[(size_t)s] == rl::ROLE_REMOTE || slots[(size_t)s].held) {
			continue;
		}
		hook_integrate_body(s);
		hook_progress_update(s);
	}
	phase = 4;
	record_stage(rl::STAGE_STEP_BODIES, start);
}

void RaceSim::set_remote(const PackedFloat32Array &p_remote_snaps_packed, int64_t p_contact_eligible_mask) {
	RS_GUARD_BUILT("set_remote");
	RS_GUARD_PHASE("set_remote", 4);
	const int64_t value_count = p_remote_snaps_packed.size();
	ERR_FAIL_COND_MSG(value_count % rl::REMOTE_STRIDE != 0, "RaceSim.set_remote: wrong row width (a remote row is REMOTE_STRIDE floats)");
	ERR_FAIL_COND_MSG(value_count / rl::REMOTE_STRIDE != remote_count, "RaceSim.set_remote: wrong row count (one row per remote slot)");
	ERR_FAIL_COND_MSG(p_contact_eligible_mask < 0 || (p_contact_eligible_mask >> slot_count_) != 0, "RaceSim.set_remote: the contact mask names a slot out of range");
	for (int64_t s = 0; s < slot_count_; s++) {
		ERR_FAIL_COND_MSG(((p_contact_eligible_mask >> s) & 1) != 0 && roles[(size_t)s] != rl::ROLE_REMOTE, "RaceSim.set_remote: the contact mask names a slot that is not remote");
	}
	const float *rows = value_count > 0 ? p_remote_snaps_packed.ptr() : nullptr;
	ERR_FAIL_COND_MSG(value_count > 0 && !all_finite(rows, value_count), "RaceSim.set_remote: a remote pose holds a non-finite value");
	const double start = now_usec();
	int64_t next_row = 0;
	for (int64_t s = 0; s < slot_count_; s++) {
		if (roles[(size_t)s] != rl::ROLE_REMOTE) {
			continue;
		}
		// Copy into the native struct: nothing keeps a reference to the caller's array.
		const float *row = rows + next_row * rl::REMOTE_STRIDE;
		next_row++;
		SlotState &st = slots[(size_t)s];
		st.position = Vector3(row[rl::SNAP_POS], row[rl::SNAP_POS + 1], row[rl::SNAP_POS + 2]);
		st.basis = basis_from(row + rl::SNAP_BASIS);
		st.velocity = Vector3(row[rl::SNAP_VEL], row[rl::SNAP_VEL + 1], row[rl::SNAP_VEL + 2]);
		st.speed = row[rl::SNAP_SPEED];
		st.contact_eligible = ((p_contact_eligible_mask >> s) & 1) != 0;
	}
	contact_mask = p_contact_eligible_mask;
	phase = 5;
	record_stage(rl::STAGE_SET_REMOTE, start);
}

void RaceSim::step_contact() {
	RS_GUARD_BUILT("step_contact");
	RS_GUARD_PHASE("step_contact", 5);
	const double start = now_usec();
	hook_contact();
	phase = 6;
	record_stage(rl::STAGE_STEP_CONTACT, start);
}

void RaceSim::step_progress_items_hazards() {
	RS_GUARD_BUILT("step_progress_items_hazards");
	RS_GUARD_PHASE("step_progress_items_hazards", 6);
	const double start = now_usec();
	hook_progress_items_hazards();
	phase = 7;
	record_stage(rl::STAGE_PROGRESS_ITEMS_HAZARDS, start);
}

void RaceSim::end_tick() {
	RS_GUARD_BUILT("end_tick");
	RS_GUARD_PHASE("end_tick", 7);
	const double start = now_usec();
	const int work = published ^ 1;
	write_snapshots(snap_buf[work].ptrw(), current_tick);
	for (int64_t s = 0; s < slot_count_; s++) {
		slots[(size_t)s].teleported_pending = false;
	}
	record_stage(rl::STAGE_END_TICK, start);
	double *usec = usec_buf[work].ptrw();
	for (int i = 0; i < rl::STAGE_COUNT; i++) {
		usec[i] = usec_scratch[i];
	}
	// Swap: the buffers just written become the published ones; the overflow flag follows the same swap.
	overflow_published = overflow_now;
	overflow_now = false;
	published = work;
	// Clear the working event buffer (the one published two ticks ago): zero only the rows it used.
	const int next_work = published ^ 1;
	if (event_rows[next_work] > 0) {
		std::memset(head_buf[next_work].ptrw(), 0, (size_t)(event_rows[next_work] * rl::EVENT_HEADER_STRIDE) * sizeof(int32_t));
		std::memset(payload_buf[next_work].ptrw(), 0, (size_t)payload_used[next_work] * sizeof(float));
	}
	event_rows[next_work] = 0;
	payload_used[next_work] = 0;
	phase = 0;
}

bool RaceSim::emit_event(int64_t p_slot, int64_t p_kind, const float *p_payload, int p_count) {
	const int work = published ^ 1;
	if (event_rows[work] >= capacity) {
		overflow_now = true;
		return false;
	}
	int32_t *head = head_buf[work].ptrw() + event_rows[work] * rl::EVENT_HEADER_STRIDE;
	head[rl::EVENT_SLOT] = (int32_t)p_slot;
	head[rl::EVENT_KIND] = (int32_t)p_kind;
	head[rl::EVENT_PAYLOAD_OFFSET] = (int32_t)payload_used[work];
	float *payload = payload_buf[work].ptrw() + payload_used[work];
	for (int i = 0; i < p_count; i++) {
		payload[i] = p_payload[i];
	}
	payload_used[work] += p_count;
	event_rows[work] += 1;
	return true;
}

void RaceSim::record_stage(int p_stage, double p_start_usec) {
	usec_scratch[p_stage] = now_usec() - p_start_usec;
}

/// Hook, stage 2: applies one received event (max-merge knock, speed loss, item hits). Filled by stories 022 and 031.
void RaceSim::hook_apply_event(int64_t, int64_t, const float *) {}
/// Hook, stage 3: `drive()` for a local slot. Filled by stories 009, 011 and 016-020.
void RaceSim::hook_drive(int64_t p_slot, const float *) {
	slots[(size_t)p_slot].drive_rows += 1;
}
/// Hook, stage 3: DriveState start logic for a held slot (start boost, Driving & Drift 3.1.9). Filled by story 011.
void RaceSim::hook_start_logic(int64_t p_slot, const float *) {
	slots[(size_t)p_slot].start_rows += 1;
}
/// Hook, stage 3: native bot decisions and bot item use. Filled by story 054.
void RaceSim::hook_bot_decision(int64_t p_slot) {
	slots[(size_t)p_slot].bot_decisions += 1;
}
/// Hook, stage 4: body integration (wall slide, ground cast, suspension, basis, timers). Filled by stories 010, 013-015 and 021.
void RaceSim::hook_integrate_body(int64_t p_slot) {
	slots[(size_t)p_slot].integrated += 1;
}
/// Hook, stage 4: CourseProgress update for the slot just stepped. Filled by the progress stories (051-053).
void RaceSim::hook_progress_update(int64_t) {}
/// Hook, stage 6: kart-vs-kart contact. Filled by stories 022 and 023.
void RaceSim::hook_contact() {}
/// Hook, stage 7: ranking, laps, respawn, items in flight, hazards. Filled by stories 031-032 and 051-053.
void RaceSim::hook_progress_items_hazards() {}
// PER_TICK_END
// ---------------------------------------------------------------------------------------------------------------

void RaceSim::place(int64_t p_slot, const PackedFloat32Array &p_pose_packed) {
	RS_GUARD_BUILT("place");
	ERR_FAIL_COND_MSG(phase != 0, "RaceSim.place: allowed only between end_tick and the next begin_tick");
	ERR_FAIL_INDEX_MSG(p_slot, slot_count_, "RaceSim.place: slot out of range");
	ERR_FAIL_COND_MSG(roles[(size_t)p_slot] == rl::ROLE_REMOTE, "RaceSim.place: a remote slot has no body");
	ERR_FAIL_COND_MSG(p_pose_packed.size() != rl::PLACE_STRIDE, "RaceSim.place: the pose is PLACE_STRIDE floats (position, basis columns)");
	const float *pose = p_pose_packed.ptr();
	ERR_FAIL_COND_MSG(!all_finite(pose, rl::PLACE_STRIDE), "RaceSim.place: the pose holds a non-finite value");
	SlotState &st = slots[(size_t)p_slot];
	st.position = Vector3(pose[0], pose[1], pose[2]);
	st.basis = basis_from(pose + 3);
	st.velocity = Vector3();
	st.speed = 0.0f;
	st.teleported_pending = true;
}

void RaceSim::hold(int64_t p_slot_mask) {
	RS_GUARD_BUILT("hold");
	ERR_FAIL_COND_MSG(phase != 0, "RaceSim.hold: allowed only between end_tick and the next begin_tick");
	ERR_FAIL_COND_MSG(p_slot_mask < 0 || (p_slot_mask >> slot_count_) != 0, "RaceSim.hold: the mask names a slot out of range");
	for (int64_t s = 0; s < slot_count_; s++) {
		ERR_FAIL_COND_MSG(((p_slot_mask >> s) & 1) != 0 && roles[(size_t)s] == rl::ROLE_REMOTE, "RaceSim.hold: a remote slot has no body to hold");
	}
	hold_pending = p_slot_mask;
}

PackedFloat32Array RaceSim::snapshots() const {
	ERR_FAIL_COND_V_MSG(!built, PackedFloat32Array(), "RaceSim.snapshots: the object is not built");
	return snap_buf[published];
}

PackedFloat32Array RaceSim::progress() const {
	ERR_FAIL_COND_V_MSG(!built, PackedFloat32Array(), "RaceSim.progress: the object is not built");
	return prog_buf[published];
}

PackedFloat64Array RaceSim::stage_usec() const {
	ERR_FAIL_COND_V_MSG(!built, PackedFloat64Array(), "RaceSim.stage_usec: the object is not built");
	return usec_buf[published];
}

PackedInt32Array RaceSim::event_headers() const {
	ERR_FAIL_COND_V_MSG(!built, PackedInt32Array(), "RaceSim.event_headers: the object is not built");
	return head_buf[published];
}

PackedFloat32Array RaceSim::event_payload() const {
	ERR_FAIL_COND_V_MSG(!built, PackedFloat32Array(), "RaceSim.event_payload: the object is not built");
	return payload_buf[published];
}

int64_t RaceSim::event_count() const {
	ERR_FAIL_COND_V_MSG(!built, 0, "RaceSim.event_count: the object is not built");
	return event_rows[published];
}

bool RaceSim::events_overflowed() const {
	ERR_FAIL_COND_V_MSG(!built, false, "RaceSim.events_overflowed: the object is not built");
	return overflow_now || overflow_published;
}

Vector3 RaceSim::snapshot_position(int64_t p_slot) const {
	ERR_FAIL_COND_V_MSG(!built, Vector3(), "RaceSim.snapshot_position: the object is not built");
	ERR_FAIL_INDEX_V_MSG(p_slot, slot_count_, Vector3(), "RaceSim.snapshot_position: slot out of range");
	const float *row = snap_buf[published].ptr() + p_slot * rl::SNAP_STRIDE;
	return Vector3(row[rl::SNAP_POS], row[rl::SNAP_POS + 1], row[rl::SNAP_POS + 2]);
}

Basis RaceSim::snapshot_basis(int64_t p_slot) const {
	ERR_FAIL_COND_V_MSG(!built, Basis(), "RaceSim.snapshot_basis: the object is not built");
	ERR_FAIL_INDEX_V_MSG(p_slot, slot_count_, Basis(), "RaceSim.snapshot_basis: slot out of range");
	return basis_from(snap_buf[published].ptr() + p_slot * rl::SNAP_STRIDE + rl::SNAP_BASIS);
}

Vector3 RaceSim::snapshot_velocity(int64_t p_slot) const {
	ERR_FAIL_COND_V_MSG(!built, Vector3(), "RaceSim.snapshot_velocity: the object is not built");
	ERR_FAIL_INDEX_V_MSG(p_slot, slot_count_, Vector3(), "RaceSim.snapshot_velocity: slot out of range");
	const float *row = snap_buf[published].ptr() + p_slot * rl::SNAP_STRIDE;
	return Vector3(row[rl::SNAP_VEL], row[rl::SNAP_VEL + 1], row[rl::SNAP_VEL + 2]);
}

double RaceSim::snapshot_speed(int64_t p_slot) const {
	ERR_FAIL_COND_V_MSG(!built, 0.0, "RaceSim.snapshot_speed: the object is not built");
	ERR_FAIL_INDEX_V_MSG(p_slot, slot_count_, 0.0, "RaceSim.snapshot_speed: slot out of range");
	return snap_buf[published].ptr()[p_slot * rl::SNAP_STRIDE + rl::SNAP_SPEED];
}

int64_t RaceSim::snapshot_flags(int64_t p_slot) const {
	ERR_FAIL_COND_V_MSG(!built, 0, "RaceSim.snapshot_flags: the object is not built");
	ERR_FAIL_INDEX_V_MSG(p_slot, slot_count_, 0, "RaceSim.snapshot_flags: slot out of range");
	return (int64_t)snap_buf[published].ptr()[p_slot * rl::SNAP_STRIDE + rl::SNAP_FLAGS];
}

double RaceSim::progress_distance(int64_t p_slot) const {
	ERR_FAIL_COND_V_MSG(!built, 0.0, "RaceSim.progress_distance: the object is not built");
	ERR_FAIL_INDEX_V_MSG(p_slot, slot_count_, 0.0, "RaceSim.progress_distance: slot out of range");
	return prog_buf[published].ptr()[p_slot * rl::PROG_STRIDE + rl::PROG_DISTANCE];
}

int64_t RaceSim::progress_lap(int64_t p_slot) const {
	ERR_FAIL_COND_V_MSG(!built, 0, "RaceSim.progress_lap: the object is not built");
	ERR_FAIL_INDEX_V_MSG(p_slot, slot_count_, 0, "RaceSim.progress_lap: slot out of range");
	return (int64_t)prog_buf[published].ptr()[p_slot * rl::PROG_STRIDE + rl::PROG_LAP];
}

int64_t RaceSim::progress_rank(int64_t p_slot) const {
	ERR_FAIL_COND_V_MSG(!built, 0, "RaceSim.progress_rank: the object is not built");
	ERR_FAIL_INDEX_V_MSG(p_slot, slot_count_, 0, "RaceSim.progress_rank: slot out of range");
	return (int64_t)prog_buf[published].ptr()[p_slot * rl::PROG_STRIDE + rl::PROG_RANK];
}

int64_t RaceSim::slot_count() const {
	ERR_FAIL_COND_V_MSG(!built, 0, "RaceSim.slot_count: the object is not built");
	return slot_count_;
}

PackedInt32Array RaceSim::slot_roles() const {
	ERR_FAIL_COND_V_MSG(!built, PackedInt32Array(), "RaceSim.slot_roles: the object is not built");
	PackedInt32Array out;
	out.resize((int64_t)roles.size());
	for (size_t i = 0; i < roles.size(); i++) {
		out[(int64_t)i] = roles[i];
	}
	return out;
}

int64_t RaceSim::local_slot_count() const {
	ERR_FAIL_COND_V_MSG(!built, 0, "RaceSim.local_slot_count: the object is not built");
	return local_count;
}

int64_t RaceSim::event_capacity() const {
	ERR_FAIL_COND_V_MSG(!built, 0, "RaceSim.event_capacity: the object is not built");
	return capacity;
}

int64_t RaceSim::consumer_count() const {
	ERR_FAIL_COND_V_MSG(!built, 0, "RaceSim.consumer_count: the object is not built");
	return (int64_t)rngs.size();
}

int64_t RaceSim::consumer_seed(int64_t p_consumer) const {
	ERR_FAIL_COND_V_MSG(!built, 0, "RaceSim.consumer_seed: the object is not built");
	ERR_FAIL_INDEX_V_MSG(p_consumer, (int64_t)seeds.size(), 0, "RaceSim.consumer_seed: consumer out of range");
	return seeds[(size_t)p_consumer];
}

int64_t RaceSim::tick() const {
	ERR_FAIL_COND_V_MSG(!built, 0, "RaceSim.tick: the object is not built");
	return current_tick;
}

double RaceSim::tick_time() const {
	ERR_FAIL_COND_V_MSG(!built, 0.0, "RaceSim.tick_time: the object is not built");
	return current_t;
}

bool RaceSim::debug_emit_event(int64_t p_slot, int64_t p_kind, const PackedFloat32Array &p_payload) {
	ERR_FAIL_COND_V_MSG(!built, false, "RaceSim.debug_emit_event: the object is not built");
	ERR_FAIL_COND_V_MSG(phase == 0, false, "RaceSim.debug_emit_event: allowed only inside a tick");
	ERR_FAIL_INDEX_V_MSG(p_slot, slot_count_, false, "RaceSim.debug_emit_event: slot out of range");
	const int count = rl::payload_floats(p_kind);
	ERR_FAIL_COND_V_MSG(count < 0, false, "RaceSim.debug_emit_event: unknown kind");
	ERR_FAIL_COND_V_MSG(p_payload.size() != count, false, "RaceSim.debug_emit_event: the payload size does not fit the kind");
	return emit_event(p_slot, p_kind, p_payload.ptr(), count);
}

void RaceSim::debug_write_progress(int64_t p_slot, int64_t p_field, double p_value) {
	ERR_FAIL_COND_MSG(!built, "RaceSim.debug_write_progress: the object is not built");
	ERR_FAIL_COND_MSG(phase == 0, "RaceSim.debug_write_progress: allowed only inside a tick");
	ERR_FAIL_INDEX_MSG(p_slot, slot_count_, "RaceSim.debug_write_progress: slot out of range");
	ERR_FAIL_INDEX_MSG(p_field, rl::PROG_STRIDE, "RaceSim.debug_write_progress: field out of range");
	prog_buf[published ^ 1].ptrw()[p_slot * rl::PROG_STRIDE + p_field] = (float)p_value;
}

int64_t RaceSim::debug_drive_rows(int64_t p_slot) const {
	ERR_FAIL_COND_V_MSG(!built, 0, "RaceSim.debug_drive_rows: the object is not built");
	ERR_FAIL_INDEX_V_MSG(p_slot, slot_count_, 0, "RaceSim.debug_drive_rows: slot out of range");
	return slots[(size_t)p_slot].drive_rows;
}

int64_t RaceSim::debug_start_rows(int64_t p_slot) const {
	ERR_FAIL_COND_V_MSG(!built, 0, "RaceSim.debug_start_rows: the object is not built");
	ERR_FAIL_INDEX_V_MSG(p_slot, slot_count_, 0, "RaceSim.debug_start_rows: slot out of range");
	return slots[(size_t)p_slot].start_rows;
}

int64_t RaceSim::debug_integrated(int64_t p_slot) const {
	ERR_FAIL_COND_V_MSG(!built, 0, "RaceSim.debug_integrated: the object is not built");
	ERR_FAIL_INDEX_V_MSG(p_slot, slot_count_, 0, "RaceSim.debug_integrated: slot out of range");
	return slots[(size_t)p_slot].integrated;
}

int64_t RaceSim::debug_bot_decisions(int64_t p_slot) const {
	ERR_FAIL_COND_V_MSG(!built, 0, "RaceSim.debug_bot_decisions: the object is not built");
	ERR_FAIL_INDEX_V_MSG(p_slot, slot_count_, 0, "RaceSim.debug_bot_decisions: slot out of range");
	return slots[(size_t)p_slot].bot_decisions;
}
