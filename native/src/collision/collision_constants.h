#pragma once
/// Constants shared by the native collision classes (ADR-0002 layout, ADR-0007 section 4).
/// Part of the ADR-0002 collision layout or numerical tolerances; none is tuning.

#include <cstdint>

namespace dogworks {

/// Collision layer bit of the ground body (layer 1).
constexpr int64_t GROUND_LAYER = 1;
/// Collision layer bit of the wall body (layer 2, bit value 2).
constexpr int64_t WALL_LAYER = 2;
/// surface_id reported when a static ground hit has no usable face index.
constexpr int64_t SURFACE_NONE = -1;
/// wall_attr reported when a static wall contact has no usable shape index.
constexpr int64_t WALL_ATTR_NONE = -1;
/// Schema version of `TrackCollisionData.pack_native()` and `MoverDef.pack_native()`. GDScript asserts the same number.
constexpr int64_t PACKED_SCHEMA_VERSION = 1;
/// Length (m) at which the analytic mover sweep stops refining the first contact.
constexpr double MOVER_SWEEP_TOLERANCE = 0.0001;
/// Iteration cap of each refinement loop of the analytic mover sweep.
constexpr int64_t MOVER_SWEEP_MAX_ITERATIONS = 64;
/// Sentinel of the sweep's bracket end while no probe is in contact yet (the cap case).
constexpr double NEWTON_CAPPED = -2.0;
/// Extra length (m) along the motion of the second static rest check at the cast's unsafe point.
constexpr double UNSAFE_RETRY_LENGTH = 0.001;
/// Margin (m) added to the mover cull radii so float32 rounding never culls a real contact.
constexpr double MOVER_CULL_MARGIN = 0.01;
/// Below this, a ray direction component counts as parallel to a slab / axis.
constexpr double PARALLEL_EPSILON = 0.000001;
/// Below this vector-part length, a key-to-key rotation uses the small-angle angular velocity.
constexpr double SMALL_ROTATION_EPSILON = 0.000001;
/// Time (s) of the load-time probe cast.
constexpr double PROBE_T = 0.0;
/// Largest |q|^2 - 1 a key rotation may have to count as a unit quaternion.
constexpr double UNIT_QUAT_TOLERANCE = 0.00001;
/// Fewest keys a mover may have.
constexpr int64_t MIN_KEYS = 2;
/// Largest mover id: ids are stored as int32 (INT32_MAX).
constexpr int64_t MAX_MOVER_ID = 2147483647;
/// Largest surface id / wall-attribute id (u8).
constexpr int64_t MAX_ID = 255;

} // namespace dogworks
