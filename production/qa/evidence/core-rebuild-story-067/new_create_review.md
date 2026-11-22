# Review of the `.new(` / `.create(` conversions (story 067, item 20)

Method: for every file under `tests/unit/collision` and `tools/bench_collision.gd`, `git diff -U0` against HEAD was
parsed; each removed line containing `CollisionQuery.new(X)` was matched to an added line equal to it with only
`CollisionQuery.new(X)` -> `CollisionQuery.create(X.pack_native())`. Result: **66 converted sites are textually the
same call with the same argument expression X** (13 load_and_mirror, 3 mover_edge_cases, 5 sweep_equivalence,
17 movers, 21 query_ground, 6 query_walls, 1 unsafe_point_retry, 0 bench: the bench goes through `checked_query`);
**4 sites were rewritten by hand** (the null-data and broken-layout tests: now `validate_packed` / `create` returning
null, `collision_query_ground_test.gd` x2, `collision_load_and_mirror_test.gd` x2).

Spot check, one site per test file, read in context (the data object is the one the test built):
- `collision_load_and_mirror_test.gd` `_load_error(data)` builds from its `data` argument.
- `collision_mover_edge_cases_test.gd` and `collision_movers_test.gd` `_movers_query(movers)`: `Fixtures.movers_only(movers)`.
- `collision_mover_sweep_equivalence_test.gd` `_compare`: `Fixtures.movers_only([mover])`.
- `collision_query_ground_test.gd` `_drop_query_without_dispose(data, rids)`: its `data`.
- `collision_query_walls_test.gd` `_attr_query()`: `Fixtures.attr_walls(Fixtures.wall_registry())`.
- `collision_unsafe_point_retry_test.gd`: `fixture.data` of the bench mesh just built.

Counts after the review (tests/unit + tools + src, oracle excluded): `CollisionQuery.create(` call sites are listed by
`grep -rn "CollisionQuery.create(" tests/unit tools src`; no-argument `QueryCursor.new()`, `GroundHit.new()`,
`WallHit.new()` stay (counts in the story report). `CollisionQuery.new()` remains only in the unbuilt-refusal tests.
Packing copies the arrays copy-on-write, so a test that mutated its data after building a query behaves as before.
