# Story 003 (TrackCollisionData + CollisionQuery ground casts): progress

Resume from the first unticked step. Do not delete files; port 24690 only.

- [x] 1. Read story, ADR-0002 sections, spike REPORT + probe_adr2, story-002 registries, rules
- [x] 2. Pin project.godot: physics/3d/physics_engine="Jolt Physics", jolt face-index=true, run_on_separate_thread=false
- [x] 3. Scratch probe (scratchpad, not in repo): freed-RID observables (body_get_space->RID(), shape_get_type->SHAPE_CUSTOM 10, space_get_direct_state->null, each with an engine ERROR line), a miss leaves the ray result stale
- [x] 4. Write src/core/collision/{ground_hit,query_cursor,mover_def,track_collision_data,collision_query}.gd
- [x] 5. Write tests/unit/collision/{collision_fixtures,collision_query_ground_test}.gd
- [x] 6. Parse check every changed .gd: 7/7 ok (after a headless --import registered the new class_names)
- [x] 7. gdUnit4 run (port 24690): 50 cases, 0 errors, 0 failures, 0 orphans, exit 0 (gdunit4.log). Run 2 caught a real bug: PREDELETE fallback called dispose() on a null self; fixed with a static _free_server_objects.
- [x] 8. tools/regression.sh -> production/qa/evidence/core-rebuild-story-003/regression: RESULT PASS (6/6 checks) warnings=0, exit 0
- [x] 9. Hand-off report

## Notes
- Step 4 also added query_cursor.gd and mover_def.gd (needed by the ADR cast_ground signature and Array[MoverDef]).
- Headless --import was run once so Godot registered the new class_names; it updated the tracked .godot/global_script_class_cache.cfg (+40 lines) and wrote the .uid sidecars.

## Follow-up (owner decided C12, 2026-11-22: nearest centre of mass on the up plane; equal distance -> lowest probe index)
- [x] 10. majority_surface(ids, points, count, centre_of_mass, up, previous_id) rewritten (allocation-free, two passes)
- [x] 11. Tests: CoM-discriminating 2-2 and 1-1 (bike front/rear), equidistant -> lowest index, 1000 repeats, up-plane, degenerate-triangle alignment (E-18), cast after dispose; header cross-references GDD AC-1 / AC-4
- [x] 12. Parse check 3/3 ok; gdUnit4 55 cases 0 errors 0 failures 0 orphans exit 0 -> gdunit4-final.log
- [ ] 13. GDD C12 / 4.1 / E-2 text: drafted in the hand-off, NOT applied (design-domain edit; needs the owner's yes)
- No regression re-run: nothing under src/legacy or src/data changed.
