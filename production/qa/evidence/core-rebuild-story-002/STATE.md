# Story 002 progress (core surface and wall-attribute registries)

Resume from the first unchecked step.

- [x] 1. Read story, ADR-0002 TrackCollisionData section, GDD 3.2 and 3.3, rules
- [x] 2. src/data/surface_type.gd: @tool, `id` (-1), `neutral` (false) - additive
- [x] 3. src/data/surface_set.gd: @tool, CORE_PATH, static load_checked (rejects duplicate / negative id)
- [x] 4. src/core/collision/wall_attr.gd, wall_attr_set.gd (new, @tool)
- [x] 5. assets/data/core/surface_set.tres (9 kinds, ids 0-8), wall_attr_set.tres (standard 0, rough 1)
- [x] 6. tests/unit/collision/surface_and_wall_registries_test.gd + fixtures (duplicate-id .tres)
- [x] 7. godot --import (class cache), parse check
- [x] 8. gdUnit4 run (port 24690)
- [x] 9. tools/regression.sh production/qa/evidence/core-rebuild-story-002/regression (background, timeout 1500)

## Notes
- import: exit 0 (import.txt). Parse check: 5/5 ok, exit 0 (parse-check.txt).
- gdUnit4 (port 24690): 15 test cases, 0 errors, 0 failures, 0 orphans, exit 0 (gdunit4-run.txt;
  12 in surface_and_wall_registries_test.gd + 3 in item_set_roll_test.gd). The two ERROR lines in the
  log are the expected push_error of the loader-rejection tests (push_error is not a gdUnit4 failure).
- Step 9 started in background: outdir production/qa/evidence/core-rebuild-story-002/regression,
  console log regression-console.txt. Resume: read its last line (RESULT ...).
- Run 1 result: RESULT PASS (6/6 checks) warnings=0 (regression/, regression-console.txt).

## Review fixes (round 2)
- [x] 10. SurfaceSet: typed _by_kind, index built in load_checked; MAX_ID 255; NEUTRAL_FIELDS check;
      empty/duplicate kind; null at index; ResourceLoader.exists "not found"
- [x] 11. WallAttrSet: MAX_ID 255; empty/duplicate name; not found; WallAttr export_range + C5 note
- [x] 12. Core set neutral entries: effect none, puff_amount 0
- [x] 13. Fixtures regenerated without load_steps (13 files); test suite rewritten (27 tests,
      exact push_error messages via assert_error().is_push_error)
- [x] 14. import (import-final.txt) exit 0; parse 5/5 ok (parse-check-final.txt);
      gdUnit4 30 cases, 0 errors, 0 failures, 0 orphans (gdunit4-final.txt)
- [x] 15. tools/regression.sh -> regression-final/ (console regression-final-console.txt)
- Run 2 result: RESULT PASS (6/6 checks) warnings=0 (out=/c/writechoice/Claude-Code-Game-Studios/production/qa/evidence/core-rebuild-story-002/regression-final). Story work complete; nothing committed.
