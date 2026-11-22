# Story 004 (CollisionQuery wall sweeps): progress

Resume from the first unticked step. Do not delete files; port 24690 only; no commit.

- [x] 1. Read story, ADR-0002 sections (Queries, Geometry layout, Key Interfaces, Impl Guidelines), story 002-003 code, fixtures, spike probes (adr2 T3/T4, adr3_rest), rules
- [x] 2. Scratch probe (scratchpad, not in repo): cast_motion at a flush end / tiny overlap end / zero motion; radius change on a reused SphereShape3D
- [x] 3. Write src/core/collision/wall_hit.gd (new), query_cursor.gd (shape params, results, sphere), collision_query.gd (sweep_walls)
- [x] 4. Write tests/unit/collision/collision_query_walls_test.gd (+ fixtures in collision_fixtures.gd)
- [x] 5. Parse check every changed .gd: 5/5 exit 0 (parse.txt; after headless --import, import.txt)
- [x] 6. gdUnit4 run (port 24690) -> gdunit4.log: 78 cases, 0 errors, 0 failures, 0 orphans, exit 0 (walls suite 23). Mutation checks: no touch rule -> touch test fails (mutation-a-no-unsafe-touch.log); no rest at from -> started-inside test fails (mutation-b-no-rest-at-from.log); source restored identical
- [x] 7. Hand-off report (no regression: nothing under src/legacy or src/data changes)

## Notes
- Probe (probe_walls.gd.txt -> probe_walls.txt): a head-on move ending exactly flush gives cast ret=true safe=0.999996 unsafe=1.0; an oblique flush end ret=true safe=1.0 unsafe=1.0; 1 mm short ret=false; zero motion ret=false; a clear cast writes 1.0/1.0 into the result; a radius change on the reused SphereShape3D takes effect at once. So the touch rule covers "cast clear OR unsafe_fraction >= 1".
- The write guard warned on the src/ writes (subagent outside production/docs/tests); the permission system allowed them. Flag in the report.

## Review fixes (coordinator, after the story 004 reviews)
- [x] R1. _sentinel_hit pre-fills collider_id 7 / collider_velocity (1,2,3); the started-inside contact test uses it and asserts 0 / zero. Mutation C (no `out.collider_id = 0` in _write_wall_contact) fails that test (mutation-c-collider-id.log); source restored identical
- [x] R2. Step 3 and the fallback moved to _write_blocked_hit (19 lines); sweep_walls is 39 lines including its signature; the fallback calls push_warning in debug builds; its comment now says "not seen in the tests"
- [x] R3. Two wall_skin (0.02 m) slide-loop tests added
- [x] R4. WallHit doc comments: wall_attr NONE, fraction (touch depth; branch on started_inside), normal (centre on the plane)
- [x] R5. Parse check via .claude/scripts/godot-parse-check.gd: 5/5 ok, exit 0 (parse-check-final.txt); gdUnit4 80 cases, 0 errors, 0 failures, 0 orphans, exit 0 (gdunit4-final.log)
