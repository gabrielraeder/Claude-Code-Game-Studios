# core-rebuild story 006 — STATE

- 2026-11-22 pass 1 started: read story, ADR-0002 (TrackCollisionData, Boot and load checks, Mirror,
  Implementation Guidelines, Validation Criteria), ADR-0001 sections 5 and 7, GDD 3.6 / 3.7 / 8,
  q5_mirror.txt, the collision sources and tests, the rules.
- Plan: TrackCollisionData.id_error / mirrored; MoverDef.mirrored; CollisionQuery.has_geometry /
  probe_error (t = 0); new CollisionBootCheck (settings_error, assert_boot_settings, load_error);
  tools/core_greps.sh + regression.sh check `core_greps`; tests in
  tests/unit/collision/collision_load_and_mirror_test.gd; mutants: winding flip, id check, grep.
- pass 1 writes done: query, boot check, track data, mover def, core_greps.sh, regression.sh (6 -> 7 checks), fixtures, test file
- Runs: --import ok; parse-check-final.txt 6/6 ok; gdunit4-new.log 34/34; gdunit4-full.log 174/174,
  0 failures, 0 orphans (port 24690); core-greps.log PASS; regression core_greps check PASS (1/7).
- Mutants (each restored, cmp-verified): mutation-winding.log, mutation-ids.log, mutation-probe.log,
  mutation-settings.log all fail their tests; mutation-grep.log FAILs on the 2 planted code lines.
  The grep mutant first exposed a colon-in-path bug in the comment filter (C:/ root); fixed by
  grepping relative paths from inside the root.
- regression.sh now has 7 checks (core_greps first); RESULT lines read n/7.
- Not committed. Story file not edited.
- 2026-11-22 pass 2 (review: engine check defect, LP CONCERNS, QL GAPS), all applied:
  1. core_greps.sh: grep exit >= 2 -> FAIL with the error (mutation-grep-error.log); header notes
     the trailing-comment false FAIL (fails safe).
  2. collide_shape( and Physics(Ray|Point)QueryParameters3D.create( added; planted in mutation-grep.log.
  3. id_error split into _surface_id_error / _wall_id_error / _mover_id_error, messages unchanged.
  4. CollisionBootCheck.checked_query() + inner class CheckedQuery; grep rule: CollisionQuery.new(
     under src/ only in collision_boot_check.gd; load_error doc example disposes on failure.
  5. Tests: assert_boot_settings failure path (interpolation on), current_settings reads Engine.
  6. after_test removes both .res files and restores face index / interpolation / Engine ticks;
     files removed before each save.
  7. has_geometry() doc and the probe "no ground" message name non-solid movers.
- Final: import-final.log ok; parse-check-final.txt 6/6; gdunit4-new.log 39/39; gdunit4-final.log
  179/179 (full suite, after every restore); regression-core-greps-review: PASS core_greps (1/7).
- Mutants pass 2: mutation-grep.log, mutation-grep-error.log, mutation-checked-query.log,
  mutation-ids.log (re-run after the split) all FAIL as intended; sources cmp-verified restored.
