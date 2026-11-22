#pragma once
/// RaceSim buffer layouts (core-rebuild story 068; ADR-0007 section 3). One definition for the C++ side. The GDScript
/// mirror is `src/core/race_layout.gd` (`RaceLayout`); a test pins both against the same literal numbers and against the
/// constants bound on `RaceSim`. The layouts are recorded in ADR-0003 Key Interfaces (amendment 2026-11-22, story 068).
/// Every value is a count of floats (or ints for the event headers) unless it says otherwise.

#include <cstdint>

namespace dogworks {
namespace race {

/// Setup dictionary schema version carried in `RaceSim.create(setup)` under the key `schema_version`.
constexpr int64_t SETUP_SCHEMA_VERSION = 1;
/// Most slots one race may hold (the contact mask is a 64-bit int; 32 keeps the sign bit clear).
constexpr int64_t MAX_SLOTS = 32;
/// Most per-consumer seeds in the setup data.
constexpr int64_t MAX_SEEDS = 64;
/// Largest event capacity (rows per tick) accepted at setup.
constexpr int64_t MAX_EVENT_CAPACITY = 4096;

/// Stage numbers, in call order (ADR-0007 section 3). Index into `stage_usec()`.
constexpr int STAGE_BEGIN_TICK = 0;
constexpr int STAGE_APPLY_EVENTS = 1;
constexpr int STAGE_STEP_DRIVE = 2;
constexpr int STAGE_STEP_BODIES = 3;
constexpr int STAGE_SET_REMOTE = 4;
constexpr int STAGE_STEP_CONTACT = 5;
constexpr int STAGE_PROGRESS_ITEMS_HAZARDS = 6;
constexpr int STAGE_END_TICK = 7;
/// Number of stage calls per tick (length of `stage_usec()`).
constexpr int STAGE_COUNT = 8;

/// Slot roles (`slot_roles` in the setup data), fixed at `create()`.
constexpr int ROLE_LOCAL = 0;
constexpr int ROLE_BOT = 1;
constexpr int ROLE_REMOTE = 2;

/// Driver row, one per LOCAL slot in slot order (`step_drive`): raw driver input, not KartIntent.
constexpr int DRIVER_STRIDE = 6;
constexpr int DRIVER_STEER = 0;
constexpr int DRIVER_THROTTLE = 1;
constexpr int DRIVER_BRAKE = 2;
constexpr int DRIVER_DRIFT = 3;
constexpr int DRIVER_HOP = 4;
constexpr int DRIVER_ITEM_USE = 5;

/// `snapshots()`: SNAP_STRIDE floats per slot, in slot order. Fields no system writes yet are zero.
/// Basis is three column vectors (x, y, z axes). Flags are a bitmask held in a float (exact below 2^24).
constexpr int SNAP_STRIDE = 20;
constexpr int SNAP_POS = 0;    ///< 3 floats: position
constexpr int SNAP_BASIS = 3;  ///< 9 floats: basis columns x, y, z
constexpr int SNAP_VEL = 12;   ///< 3 floats: velocity (zero until story 010)
constexpr int SNAP_SPEED = 15; ///< forward speed (zero until story 010)
constexpr int SNAP_FLAGS = 16; ///< bitmask of SNAP_FLAG_*
constexpr int SNAP_KNOCK = 17; ///< knock strength (zero until story 022)
constexpr int SNAP_STATE = 18; ///< drive state id (zero until story 011)
constexpr int SNAP_TICK = 19;  ///< tick number of this snapshot (-1 before the first tick)
constexpr int SNAP_FLAG_TELEPORTED = 1;
constexpr int SNAP_FLAG_BUMPED = 2;
constexpr int SNAP_FLAG_HELD = 4;
constexpr int SNAP_FLAG_CONTACT_ELIGIBLE = 8;

/// `set_remote` row, one per REMOTE slot in slot order: the first REMOTE_STRIDE fields of a snapshot row
/// (position, basis, velocity, speed).
constexpr int REMOTE_STRIDE = 16;
/// `place` pose: position (3) then basis columns (9).
constexpr int PLACE_STRIDE = 12;

/// `progress()`: PROG_STRIDE floats per slot, in slot order.
constexpr int PROG_STRIDE = 4;
constexpr int PROG_DISTANCE = 0; ///< distance along the course
constexpr int PROG_LAP = 1;      ///< completed laps
constexpr int PROG_RANK = 2;     ///< 0-based rank
constexpr int PROG_FLAGS = 3;    ///< bitmask of PROG_FLAG_*
constexpr int PROG_FLAG_MOVED = 1;
constexpr int PROG_FLAG_SAFE = 2;
constexpr int PROG_FLAG_FINISHED = 4;

/// Event pair: `event_headers()` rows of EVENT_HEADER_STRIDE ints, and `event_payload()` floats.
/// A header row is slot, kind and the payload offset (a float index into `event_payload()`).
constexpr int EVENT_HEADER_STRIDE = 3;
constexpr int EVENT_SLOT = 0;
constexpr int EVENT_KIND = 1;
constexpr int EVENT_PAYLOAD_OFFSET = 2;
/// Event kinds and their payload (floats):
///  KNOCK    (4): knock x, knock y, knock z, speed loss.
///  PICKUP   (1): item id (from the GDScript odds roll).
///  ITEM_HIT (2): item id, source slot (the hit confirmation).
constexpr int EVENT_KIND_KNOCK = 1;
constexpr int EVENT_KIND_PICKUP = 2;
constexpr int EVENT_KIND_ITEM_HIT = 3;
constexpr int EVENT_PAYLOAD_KNOCK = 4;
constexpr int EVENT_PAYLOAD_PICKUP = 1;
constexpr int EVENT_PAYLOAD_ITEM_HIT = 2;
/// Largest payload of any kind: the payload buffer holds capacity x this many floats.
constexpr int EVENT_PAYLOAD_MAX = 4;

/// Payload float count of an event kind, or -1 for an unknown kind.
constexpr int payload_floats(int64_t p_kind) {
	return p_kind == EVENT_KIND_KNOCK ? EVENT_PAYLOAD_KNOCK : p_kind == EVENT_KIND_PICKUP ? EVENT_PAYLOAD_PICKUP : p_kind == EVENT_KIND_ITEM_HIT ? EVENT_PAYLOAD_ITEM_HIT : -1;
}

// The layout pins on the C++ side: changing a number here fails the build until the amendment and the mirror change.
static_assert(SETUP_SCHEMA_VERSION == 1 && MAX_SLOTS == 32 && STAGE_COUNT == 8, "setup/stage layout");
static_assert(DRIVER_STRIDE == 6 && DRIVER_ITEM_USE == 5, "driver row layout");
static_assert(SNAP_STRIDE == 20 && SNAP_BASIS == 3 && SNAP_VEL == 12 && SNAP_SPEED == 15 && SNAP_FLAGS == 16 && SNAP_TICK == 19, "snapshot layout");
static_assert(REMOTE_STRIDE == SNAP_SPEED + 1 && PLACE_STRIDE == 12, "remote and place layout");
static_assert(PROG_STRIDE == 4 && PROG_FLAGS == 3, "progress layout");
static_assert(EVENT_HEADER_STRIDE == 3 && EVENT_PAYLOAD_MAX == 4 && payload_floats(EVENT_KIND_ITEM_HIT) == 2, "event layout");

} // namespace race
} // namespace dogworks
