# core-rebuild story 005 — STATE

- 2026-11-22 pass 1: MoverDef / TrackCollisionData mover checks; CollisionQuery mover_pose /
  mover_point_velocity; analytic movers in cast_ground and sweep_walls; 47 tests; full suite 127/127.
- 2026-11-22 pass 2 (review: engine check, LP CONCERNS, QL GAPS), all applied:
  1. Wrap bug fixed in _find_segment (`if i < 0 and u < key_t[0]`); test at keys 3.7 / 0.1.
     mutation-wrap.log: old condition -> the new test fails.
  2. MoverDef.surface_id (0 road) / wall_attr_id (0 standard), checked 0..255; written on mover hits.
  3. Splits: _ray_box/_ray_capsule/_ray_cylinder (+ _ray_sphere), _closest_box/_capsule/_cylinder,
     _test_ground_movers, _mover_in_reach, _sweep_static, _find_segment, _angular_velocity,
     _write_ground_contact; MoverDef._shape_error/_key_error; TrackCollisionData._mover_error.
  4. New tests (a)-(e); mutation-t.log and mutation-rot.log: (a) and (b) fail on the mutants.
  5. key_pos finite; UNIT_QUAT_TOLERANCE 1e-5; typed _slot_of; `_n`; scan asserts reads.
  6. dispose() clears the three cull arrays.
  7. Docs: t convention, frozen pose, shared scratch, riding by pose delta.
- Final: --import ok; parse-check-final.txt 8/8 ok; gdunit4-final.log 140 cases, 0 failures.
- Not done here (by instruction): performance (story 007, TD-012). Not committed.
