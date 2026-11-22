class_name RaceLayout
extends RefCounted
## GDScript mirror of the native RaceSim buffer layouts (core-rebuild story 068, ADR-0007 section 3, recorded in
## ADR-0003 Key Interfaces, amendment "2026-11-22 (story 068)"). The C++ side is native/src/race/race_layout.h.
## Plain literals on purpose: no constant here reads a native symbol (a script that names a native type must load
## after the boot check, ADR-0007 section 4). tests/unit/race/race_layout_test.gd pins every value against literal
## numbers and against the constants bound on RaceSim, so the two sides cannot drift.
##
## Offsets are float (or int, for event headers) indexes inside one row; strides are row widths.

## Setup dictionary schema version (key schema_version).
const SETUP_SCHEMA_VERSION: int = 1
## Most slots, seeds and event rows one race may hold.
const MAX_SLOTS: int = 32
const MAX_SEEDS: int = 64
const MAX_EVENT_CAPACITY: int = 4096

## Stage indexes, in call order; also the index into RaceSim.stage_usec().
const STAGE_BEGIN_TICK: int = 0
const STAGE_APPLY_EVENTS: int = 1
const STAGE_STEP_DRIVE: int = 2
const STAGE_STEP_BODIES: int = 3
const STAGE_SET_REMOTE: int = 4
const STAGE_STEP_CONTACT: int = 5
const STAGE_PROGRESS_ITEMS_HAZARDS: int = 6
const STAGE_END_TICK: int = 7
const STAGE_COUNT: int = 8

## Slot roles (setup key slot_roles).
const ROLE_LOCAL: int = 0
const ROLE_BOT: int = 1
const ROLE_REMOTE: int = 2

## Driver row, one per LOCAL slot in slot order (step_drive).
const DRIVER_STRIDE: int = 6
const DRIVER_STEER: int = 0
const DRIVER_THROTTLE: int = 1
const DRIVER_BRAKE: int = 2
const DRIVER_DRIFT: int = 3
const DRIVER_HOP: int = 4
const DRIVER_ITEM_USE: int = 5

## snapshots(): one row per slot. Basis is three column vectors. Fields no system writes yet are zero.
const SNAP_STRIDE: int = 20
const SNAP_POS: int = 0
const SNAP_BASIS: int = 3
const SNAP_VEL: int = 12
const SNAP_SPEED: int = 15
const SNAP_FLAGS: int = 16
const SNAP_KNOCK: int = 17
const SNAP_STATE: int = 18
const SNAP_TICK: int = 19
const SNAP_FLAG_TELEPORTED: int = 1
const SNAP_FLAG_BUMPED: int = 2
const SNAP_FLAG_HELD: int = 4
const SNAP_FLAG_CONTACT_ELIGIBLE: int = 8

## set_remote row, one per REMOTE slot in slot order: the first 16 fields of a snapshot row.
const REMOTE_STRIDE: int = 16
## place() pose: position (3) then basis columns (9).
const PLACE_STRIDE: int = 12

## progress(): one row per slot.
const PROG_STRIDE: int = 4
const PROG_DISTANCE: int = 0
const PROG_LAP: int = 1
const PROG_RANK: int = 2
const PROG_FLAGS: int = 3
const PROG_FLAG_MOVED: int = 1
const PROG_FLAG_SAFE: int = 2
const PROG_FLAG_FINISHED: int = 4

## Event pair. A header row is slot, kind and the payload offset (a float index into the payload array).
const EVENT_HEADER_STRIDE: int = 3
const EVENT_SLOT: int = 0
const EVENT_KIND: int = 1
const EVENT_PAYLOAD_OFFSET: int = 2
## Kinds and their payload (floats). KNOCK: knock x, y, z, speed loss. PICKUP: item id. ITEM_HIT: item id, source slot.
const EVENT_KIND_KNOCK: int = 1
const EVENT_KIND_PICKUP: int = 2
const EVENT_KIND_ITEM_HIT: int = 3
const EVENT_PAYLOAD_KNOCK: int = 4
const EVENT_PAYLOAD_PICKUP: int = 1
const EVENT_PAYLOAD_ITEM_HIT: int = 2
const EVENT_PAYLOAD_MAX: int = 4


## Payload float count of an event kind, or -1 for an unknown kind.
static func payload_floats(kind: int) -> int:
	match kind:
		EVENT_KIND_KNOCK:
			return EVENT_PAYLOAD_KNOCK
		EVENT_KIND_PICKUP:
			return EVENT_PAYLOAD_PICKUP
		EVENT_KIND_ITEM_HIT:
			return EVENT_PAYLOAD_ITEM_HIT
	return -1
