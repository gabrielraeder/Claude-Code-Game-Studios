# Story 067: deviations from the ADRs and intentional behaviour changes

1. **Mover ray-distance parity tolerance (deviation from ADR-0007 section 5, "ray distances within 1e-5 m").**
   Static hits keep 1e-5 m exactly. Mover hits (`collider_id != 0`) use `MOVER_RAY_TOLERANCE` in
   `tests/unit/collision/collision_native_parity_test.gd`, the observed maximum rounded up (numbers in
   `parity-final.txt`: `mover_ray_max` per fixture). Cause: the mover-local frame. A mover ray enters the
   local frame through a float32 `Transform3D` multiply, and the engine's build and godot-cpp's round it differently by an
   ulp of the coordinate (ulp is 7.6e-6 m at 100 m, 3e-5 m at 300 m); a grazing ray amplifies that along its length.
   `test_mover_local_transform_and_pose_are_compared_bit_for_bit_with_the_oracle` compares the mover-local point
   bit for bit and prints `LOCAL_TRANSFORM ...` (mismatch count and worst difference).
2. **"Warns on undisposed drop" is intentionally gone.** The ADR-0002 behaviour (a `CollisionQuery` dropped without
   `dispose()` push_warns, then frees) is replaced by the native destructor, which frees the server objects silently
   through the same static helper as `dispose()` (ADR-0007 section 4). Tests prove it with
   `CollisionQuery.live_rid_count()` returning to its baseline, not with the absence of a warning.
3. **Release builds keep the `dir` normalised and `radius > 0` guards** (`ERR_FAIL_COND_V_MSG`): the GDScript oracle only
   asserted them in debug builds. The same input now behaves the same in every build.
4. **After `dispose()` every bound method refuses** (`ERR_FAIL_COND`), except `dispose`, `is_built`, `is_disposed`
   (the oracle asserted in debug and answered a miss/identity in release).
5. **The "no rest contact at the unsafe point" warning is gone** (per-tick paths never print); `blocked_fallback_count()`
   counts the fallback instead, and the parity and bench runs assert it is 0.
6. **A rejected layout builds no query** (`create` returns null); the oracle built an empty query and push_errored.
7. **Mover ids are limited to INT32_MAX** in both `MoverDef.layout_error()` and native validation.
8. **The fail-closed "blocked, WALL_ATTR_NONE" fallback is reachable by random grazing sweeps (finding).** With the new
   `blocked_fallback_count()` the seeded parity runs show it firing, identically in the GDScript oracle (whose
   `push_warning` "no rest contact at the unsafe point" prints), on the wall fixtures: `ground_with_walls` 8 of 1500
   sweeps, `attr_walls` 5, `inner_corner` 1 (sweeps that graze a wall's edge: Jolt reports a cast hit whose unsafe point and
   the 0.001 m retry find no rest contact). It is 0 on `mirror_fixture`, its mirrored copy, `movers_over_ground`,
   `touch_boundary`, the bench mesh with 4,800 wall triangles (random and wall-directed sweeps) and the captured
   retry sweep, and 0 in every bench run. The counts are pinned per fixture in `collision_native_parity_test.gd` (a seeded
   run is deterministic), so a change shows as a failure. Native and oracle agree on every one of those results.
