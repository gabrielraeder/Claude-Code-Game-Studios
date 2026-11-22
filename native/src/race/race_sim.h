#pragma once
/// RaceSim: the native race tick (ADR-0007 section 3; core-rebuild story 068). A skeleton: it owns the eight stage
/// calls and their order assertion, the double-buffered outputs, the event pair, the stage timers, the slot roles and
/// the race-flow calls. The stage bodies are empty hooks; the stories named on each hook fill them.

#include "race/race_layout.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <vector>

namespace godot {

/// The native race simulation. Built with the bound static `RaceSim.create(setup)` (checked first by
/// `RaceSim.validate_packed(setup)`, which runs the same C++ validation); `.new()` gives an unbuilt object whose bound
/// methods all refuse, except `dispose()` (silent no-op) and `is_built()`.
///
/// Caller contract (ADR-0007 section 3), repeated on the bound methods:
///  - One caller, one phase: the composition root physics tick, on the main thread, calling the eight stages in order.
///  - Refresh every array reference you take from the output accessors each tick. A held array is a copy-on-write
///    snapshot of its tick and is never corrupted; keeping one longer costs one copy per held array.
///  - Never write through an array an accessor returned, and never pass one back in as an input.
///  - No bound method writes through a packed argument, and none keeps a reference to one: inputs are read through
///    `ptr()` and copied into native structs.
///
/// Output buffers are pairs (A, B). A tick writes the buffer that the previous `end_tick()` did not publish, so for
/// ticks 0, 1, 2 ... that is A, B, A ... A consumer may hold the published arrays across the next tick.
///
/// Hot reload: when the extension is unloaded every live RaceSim has its `built` flag cleared (`release_all`); call
/// `create()` again afterwards. RaceSim owns no server objects, so there is no RID to free.
class RaceSim : public RefCounted {
	GDCLASS(RaceSim, RefCounted)

public:
	/// GDScript: `RaceSim.validate_packed(setup: Dictionary) -> String`. "" when valid, else one message naming the key.
	/// Keys: `schema_version` (int, 1), `slot_count` (int, 1..32), `slot_roles` (PackedInt32Array of slot_count roles:
	/// 0 local, 1 bot, 2 remote), `seeds` (PackedInt64Array, 1..64 per-consumer seeds) and `event_capacity` (int, 1..4096).
	/// Unknown keys are refused. Load time only (allocates).
	static String validate_packed(const Dictionary &p_packed);
	/// GDScript: `RaceSim.create(setup: Dictionary) -> RaceSim`. Same validation as `validate_packed`; null with an error
	/// on failure. Sizes every buffer. Load time only (allocates).
	static Ref<RaceSim> create(const Dictionary &p_packed);
	/// GDScript: `RaceSim.live_count() -> int`. Test-only: built RaceSim objects alive now.
	static int64_t live_count();
	/// Clears `built` on every live RaceSim (hot reload and exit). Called from `uninitialize_module(SCENE)`. Not bound.
	static void release_all();

	/// GDScript: `is_built() -> bool`. The one bound method (with `dispose`) that does not refuse on `!built`.
	bool is_built() const;
	/// GDScript: `dispose() -> void`. Frees the buffers and clears `built`. Idempotent: a silent no-op when unbuilt.
	void dispose();

	// ---- The eight stages (ADR-0007 section 3). Each is refused (ERR_FAIL, debug and release) when called out of order. ----

	/// GDScript: `begin_tick(tick: int) -> void`. Stage 1. `tick >= 0`; native computes t = tick * SIM_DT. Applies the pending
	/// `hold` mask and resets per-tick scratch. Later stories add their per-tick resets here.
	void begin_tick(int64_t p_tick);
	/// GDScript: `apply_events(headers: PackedInt32Array, payload: PackedFloat32Array) -> void`. Stage 2. Received events
	/// (rows of slot, kind, payload offset; layout in race_layout.h). A malformed row refuses the whole call. The arrays are
	/// read through `ptr()` and not kept; do not write through them or pass an output array back in. Hook filled by
	/// stories 022 and 031 (max-merge knock, item hits).
	void apply_events(const PackedInt32Array &p_headers, const PackedFloat32Array &p_payload);
	/// GDScript: `step_drive(driver_input_packed: PackedFloat32Array) -> void`. Stage 3. Exactly one row of DRIVER_STRIDE
	/// floats per LOCAL slot in slot order; a wrong row count or width refuses the call. Rows of held slots still reach the
	/// start-logic hook. Hooks filled by stories 009, 011, 016-020 (drive) and 054 (bot decisions, item use).
	void step_drive(const PackedFloat32Array &p_driver_input_packed);
	/// GDScript: `step_bodies() -> void`. Stage 4. Integrates every local and bot body that is not held, then updates its
	/// progress. Hook filled by stories 010, 013-015, 021.
	void step_bodies();
	/// GDScript: `set_remote(remote_snaps_packed: PackedFloat32Array, contact_eligible_mask: int) -> void`. Stage 5. One row
	/// of REMOTE_STRIDE floats per REMOTE slot in slot order, copied into native structs (the array is not kept). Bit i of the
	/// mask makes slot i contact-eligible; a bit for a slot that is not remote refuses the call.
	void set_remote(const PackedFloat32Array &p_remote_snaps_packed, int64_t p_contact_eligible_mask);
	/// GDScript: `step_contact() -> void`. Stage 6. Hook filled by stories 022-023.
	void step_contact();
	/// GDScript: `step_progress_items_hazards() -> void`. Stage 7. Hook filled by stories 031-032 and 051-053.
	void step_progress_items_hazards();
	/// GDScript: `end_tick() -> void`. Stage 8. Writes the end-of-tick snapshot, closes the stage timers, swaps the output
	/// buffers and clears the working event buffer.
	void end_tick();

	// ---- Race flow, between ticks only (after end_tick, before the next begin_tick) ----

	/// GDScript: `place(slot: int, pose_packed: PackedFloat32Array) -> void`. Start grid and debug only. `pose_packed` is
	/// PLACE_STRIDE floats (position, basis columns). Local and bot slots only. Marks that slot's next snapshot `teleported`.
	void place(int64_t p_slot, const PackedFloat32Array &p_pose_packed);
	/// GDScript: `hold(slot_mask: int) -> void`. Bit i holds slot i from the next `begin_tick`: it does not integrate, but
	/// its driver row still reaches the start-logic hook. Persists until the next `hold`. Not the FROZEN state. Local and bot slots only.
	void hold(int64_t p_slot_mask);

	// ---- Outputs (double-buffered; see the class doc) ----

	/// GDScript: `snapshots() -> PackedFloat32Array`. SNAP_STRIDE floats per slot of the last completed tick.
	PackedFloat32Array snapshots() const;
	/// GDScript: `progress() -> PackedFloat32Array`. PROG_STRIDE floats per slot of the last completed tick.
	PackedFloat32Array progress() const;
	/// GDScript: `stage_usec() -> PackedFloat64Array`. STAGE_COUNT microsecond timers of the last completed tick.
	PackedFloat64Array stage_usec() const;
	/// GDScript: `event_headers() -> PackedInt32Array`. Full capacity; only the first `event_count()` rows are valid (the rest are zero).
	PackedInt32Array event_headers() const;
	/// GDScript: `event_payload() -> PackedFloat32Array`. Full capacity; rows index into it by their payload offset.
	PackedFloat32Array event_payload() const;
	/// GDScript: `event_count() -> int`. Event rows of the last completed tick.
	int64_t event_count() const;
	/// GDScript: `events_overflowed() -> bool`. True once an event was dropped for lack of capacity; stays set until the next
	/// `end_tick()` has closed a tick that dropped none.
	bool events_overflowed() const;
	/// GDScript: `snapshot_position(slot: int) -> Vector3`. One kart's value from the last completed tick, without reading the whole array.
	Vector3 snapshot_position(int64_t p_slot) const;
	/// GDScript: `snapshot_basis(slot: int) -> Basis`.
	Basis snapshot_basis(int64_t p_slot) const;
	/// GDScript: `snapshot_velocity(slot: int) -> Vector3`.
	Vector3 snapshot_velocity(int64_t p_slot) const;
	/// GDScript: `snapshot_speed(slot: int) -> float`.
	double snapshot_speed(int64_t p_slot) const;
	/// GDScript: `snapshot_flags(slot: int) -> int`. Bitmask of SNAP_FLAG_*.
	int64_t snapshot_flags(int64_t p_slot) const;
	/// GDScript: `progress_distance(slot: int) -> float`.
	double progress_distance(int64_t p_slot) const;
	/// GDScript: `progress_lap(slot: int) -> int`.
	int64_t progress_lap(int64_t p_slot) const;
	/// GDScript: `progress_rank(slot: int) -> int`.
	int64_t progress_rank(int64_t p_slot) const;

	// ---- Setup facts ----

	/// GDScript: `slot_count() -> int`.
	int64_t slot_count() const;
	/// GDScript: `slot_roles() -> PackedInt32Array`. A copy of the roles fixed at `create()`; there is no setter.
	PackedInt32Array slot_roles() const;
	/// GDScript: `local_slot_count() -> int`. Rows `step_drive` expects.
	int64_t local_slot_count() const;
	/// GDScript: `event_capacity() -> int`.
	int64_t event_capacity() const;
	/// GDScript: `consumer_count() -> int`. Number of per-consumer random generators.
	int64_t consumer_count() const;
	/// GDScript: `consumer_seed(consumer: int) -> int`. The seed consumer `consumer` was built with.
	int64_t consumer_seed(int64_t p_consumer) const;
	/// GDScript: `tick() -> int`. The tick passed to the last `begin_tick` (-1 before the first).
	int64_t tick() const;
	/// GDScript: `tick_time() -> float`. t = tick * SIM_DT of the last `begin_tick`.
	double tick_time() const;

	// ---- Test seams (debug accessors; the production tick never calls them) ----

	/// GDScript: `debug_emit_event(slot: int, kind: int, payload: PackedFloat32Array) -> bool`. Inside a tick only: appends one event to
	/// the working event buffer through the same path the stages use. Returns false (event dropped, overflow flag set) at capacity.
	bool debug_emit_event(int64_t p_slot, int64_t p_kind, const PackedFloat32Array &p_payload);
	/// GDScript: `debug_write_progress(slot: int, field: int, value: float) -> void`. Inside a tick only: writes the working progress buffer.
	void debug_write_progress(int64_t p_slot, int64_t p_field, double p_value);
	/// GDScript: `debug_drive_rows(slot: int) -> int`. Driver rows delivered to the drive hook for this slot since create.
	int64_t debug_drive_rows(int64_t p_slot) const;
	/// GDScript: `debug_start_rows(slot: int) -> int`. Driver rows delivered to the start-logic hook (held slots) since create.
	int64_t debug_start_rows(int64_t p_slot) const;
	/// GDScript: `debug_integrated(slot: int) -> int`. Ticks this slot's body was integrated since create.
	int64_t debug_integrated(int64_t p_slot) const;
	/// GDScript: `debug_bot_decisions(slot: int) -> int`. Ticks the bot decision hook ran for this slot since create.
	int64_t debug_bot_decisions(int64_t p_slot) const;

	RaceSim() = default;
	~RaceSim();

protected:
	/// Binds the factory pair, the constants, the stages and the accessors.
	static void _bind_methods();

private:
	/// Per-slot native state. Plain data: no heap, no engine objects.
	struct SlotState {
		Vector3 position;
		Basis basis;
		Vector3 velocity;
		float speed = 0.0f;
		bool teleported_pending = false;
		bool held = false;
		bool contact_eligible = false;
		int64_t drive_rows = 0;
		int64_t start_rows = 0;
		int64_t integrated = 0;
		int64_t bot_decisions = 0;
	};

	/// Writes one snapshot row per slot into `p_out` (SNAP_STRIDE floats each). Tick field = `p_tick`.
	void write_snapshots(float *p_out, int64_t p_tick) const;
	/// Appends one event to the working buffer; false (and the overflow flag) when full. Per tick.
	bool emit_event(int64_t p_slot, int64_t p_kind, const float *p_payload, int p_count);
	/// Records the microseconds since `p_start_usec` of a stage into the scratch timers. Per tick.
	void record_stage(int p_stage, double p_start_usec);
	/// Empty hooks, one per system, named by the stories that fill them. Per tick.
	void hook_apply_event(int64_t p_slot, int64_t p_kind, const float *p_payload);
	void hook_drive(int64_t p_slot, const float *p_row);
	void hook_start_logic(int64_t p_slot, const float *p_row);
	void hook_bot_decision(int64_t p_slot);
	void hook_integrate_body(int64_t p_slot);
	void hook_progress_update(int64_t p_slot);
	void hook_contact();
	void hook_progress_items_hazards();
	/// Removes this object from the registry and drops the buffers.
	void release_buffers();

	bool built = false;
	bool registered = false;
	/// Stages completed in the current tick: 0 between ticks, 1 after begin_tick ... 7 after the 7th stage.
	int phase = 0;
	int64_t slot_count_ = 0;
	int64_t local_count = 0;
	int64_t remote_count = 0;
	int64_t capacity = 0;
	int64_t current_tick = -1;
	double current_t = 0.0;
	int64_t hold_pending = 0;
	int64_t hold_active = 0;
	int64_t contact_mask = 0;
	/// Index of the buffer the last end_tick published; the working buffer is the other.
	int published = 1;

	std::vector<int32_t> roles;
	std::vector<SlotState> slots;
	std::vector<Ref<RandomNumberGenerator>> rngs;
	std::vector<int64_t> seeds;

	PackedFloat32Array snap_buf[2];
	PackedFloat32Array prog_buf[2];
	PackedFloat64Array usec_buf[2];
	PackedInt32Array head_buf[2];
	PackedFloat32Array payload_buf[2];
	int64_t event_rows[2] = { 0, 0 };
	int64_t payload_used[2] = { 0, 0 };
	bool overflow_now = false;
	bool overflow_published = false;
	double usec_scratch[dogworks::race::STAGE_COUNT] = {};
};

} // namespace godot
