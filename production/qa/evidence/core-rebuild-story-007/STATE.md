# Story 007 progress notes (resume point)

- 2026-11-22: read story, collision_query.gd, ADR-0002 query section, Castle movers
  (assets/tracks/castle_circuit/castle_circuit.tres, read-only: drawbridge gate deck 5 m x 18 m,
  raised 78 deg, period 20; portcullis 4.5 m x 2.6 m, lift 2.8 m, period 20; 3 barrels r 0.55
  len 1.1, 9 m/s over 68 m, period 10, non-solid (solid_body default false)).
- No PhysicsServer3D / RenderingServer RID-count API exists in 4.8-beta3 (ClassDB probe):
  readable = OBJECT_* monitors, MEMORY_STATIC, PhysicsServer3D.get_process_info x3.
- Plan: tools/bench_track_fixture.gd (mesh), tools/bench_collision.gd (SceneTree bench),
  tools/bench_collision.sh (3 runs per layout, aggregate). Then baseline, then optimise
  collision_query.gd (pose cache, overlap pass first, Newton-from-left sweep), re-run.
- Tools written + parse ok: tools/bench_track_fixture.gd (48006 ground + 4800 wall tris),
  tools/bench_collision.gd, tools/bench_collision.sh. Runs under runs/ (label "baseline").
- BASELINE (3 runs each, median of run medians / median of run p95s, us per tick):
  castle all 308 / 381; sections p95 curve 329 climb 326 crossover 331 movers 398 ramp 314
  worst  all 391 / 1445; sections p95 curve 420 climb 412 crossover 418 movers 1489 ramp 396
  static all 195 / 214; sections p95 curve 216 climb 214 crossover 221 movers 206 ramp 203
  OBJECT_COUNT unchanged in every run. Finding: movers far away still cost ~0.1-0.2 ms (per-query
  cull loop over every mover, incl. non-solid, with Resource property reads + 2 calls each).
- NEXT: optimise collision_query.gd: solid-slot list + inline cull 1, pose/inverse cache per t,
  lazy omega, overlap pass before sweeps, Newton-from-left sweep (replaces golden + most bisection).
- OPT1 applied to src/core/collision/collision_query.gd: solid-slot list, pose+inverse cache per t
  (_pc_*), lazy omega (_ang_of), overlap pass before sweeps (_rs_* scratch), Newton-from-left sweep
  (_sweep_local new signature: + slope0; _find_contact and INV_PHI removed). Pre-change copy:
  scratchpad collision_query.before.gd. New tests: tests/unit/collision/
  collision_mover_sweep_equivalence_test.gd (8 tests; old routine kept there as reference).
  tests/unit/collision: all pass (39+60+8+25+25+registries). Mutation check (fraction = lo*0.999)
  made the equivalence suite FAIL (exit 100); restored.
- Running opt1 bench (label opt1) next.
- OPT1 results (us, median-of-medians / median-of-p95): castle all 262/303 (curve p95 297,
  climb 282, crossover 288, movers 317, ramp 272); worst all 324/869 (curve 359, climb 352,
  crossover 349, movers 900, ramp 333); static all 198/224. OBJECT_COUNT unchanged all runs.
- OPT2 applied: cull 1 (path sphere) inlined in both mover loops (_in_reach -> _in_reach_at for the
  time-dependent part), mover passes skipped when no solid movers, ray/shape collision_mask and
  hit_back_faces set once in QueryCursor._init (no longer per call). Bench: --stages mode added
  (per-stage + raw _into reference). Running: collision tests -> stages-{castle,worst,static}.txt
  -> opt2 x3 per layout (background). Coordinator hard stop: if castle <= 300 p95 and worst not,
  stop optimising and report.
- OPT2 results: castle 238/283 (p95 curve 259 climb 258 crossover 266 movers 294 ramp 243) -> within
  budget; worst 265/864 (movers 893, curve 313); static 172/193. HARD STOP per coordinator: castle
  within 300, worst not -> no further optimisation; worst-case number goes to the owner.
- FINAL checks done: import 0; parse-check-final.txt all ok; gdunit4-final.log 187/187 pass
  (179 + 8 new), exit 0; core-greps-final.txt 2 PASS; rid-leak-check.log (--verbose) no leak report.
  Report written: collision-bench.md. Story status/TD-012 register NOT edited (left to /story-done).

## Review-fixes pass (2026-11-22, after the coordinator's 16-item message; owner scope change: GDScript CollisionQuery = reference oracle for a C++ port)
- DONE 1 fail closed at cap: NEWTON_CAPPED -> blocking hit at safe lo + push_error once per query
  object (_cap_error_reported); test seam _newton_cap. Tests: 1 km cylinder graze hits; cap=1 case.
- DONE 2 touch rule: touch only when end in contact AND bracket hi within TOL of end
  (_refine_contact); docs updated (MOVER_SWEEP_TOLERANCE, sweep_walls step 5). Tests (a)(b)(c) in
  collision_mover_edge_cases_test.gd. Note: (c) built as "end clear by 0.5 TOL after a real
  contact" (a sub-TOL graze cannot be built in float32).
- DONE 3 split: _test_movers_for_sweep -> _collect_mover_overlaps + _sweep_reach_list;
  _sweep_local -> _newton_first_contact + _refine_contact. A/B vs inline variant pending (castle).
- DONE 4 comments (inline culls, _pc_*/_rs_* sizing/clearing, _pc_t key equality).
- PARTLY 5 (now DROPPED by owner): two semantics-identical trims already in (no motion reset at
  sweep_walls entry, invariant documented in QueryCursor; cast_ground reads out.point instead of
  result.position). Masks moved to QueryCursor in opt2. No further trimming; asserts kept.
- DONE 6 unsafe-point fallback: cause = Jolt (4.8-beta3) puts the cast's unsafe point inside its
  cast tolerance while a rest check there finds nothing (bench: curve tick 167 kart 10 sweep 0;
  1 of 127 unsafe checks in a 1500-tick probe); retry 1e-5 m fails, 1e-4 m finds it; reduced
  22-triangle mesh does NOT reproduce. Fix: one retry UNSAFE_RETRY_LENGTH = 0.001 m further along
  the motion. Test collision_unsafe_point_retry_test.gd (bench mesh); watched fail (mutant
  no-unsafe-retry, exit 100).
- DONE 7, 8, 9, 10 (all four parts), 12: collision_mover_edge_cases_test.gd (12 tests).
- DONE 11: equivalence suite rewritten (derived tolerances, safety assertion, 50% compared share,
  hits per time step, feature hits per shape, counts printed). Mutants (mutation-*.log):
  return-hi FAILS(killed), slope-gt-zero FAILS(killed), no-unsafe-retry FAILS(killed),
  no-step-min-floor SURVIVES (performance-only: Newton still converges in < cap),
  touch-2tol SURVIVES (inside the TOL..2TOL bracket fuzz; not decidable by a deterministic test).
- DONE 13 (ticks >= 1), 14 (consts grouped, class Hook moved last), 15 (stage renamed
  query_mover_pose_cache_hits + STAGE_NOTE line).
- NOT STARTED 16 report edits; final import/parse/gdunit/greps; opt3 bench.
- collision suite with all fixes: 197 tests pass (exit 0).
- RUNNING NEXT: scratchpad s007/opt3.sh = tests on inline variant -> castle x3 inline (opt3inline)
  -> restore split -> opt3 x3 castle/worst/static -> stages-opt3-*.
- opt3 (split) bench: castle 242/291, movers p95 303 (!); worst 269/898; static 172/191.
  opt3inline castle: 237/282, movers p95 296. Split costs +7 us p95 (+2.4%) > 2% -> item 3:
  kept INLINE with "# perf waiver (story 007)" comments; collision_query.gd = scratch cq_inline.gd
  (docs fixed). Fallback warning: 0 of the opt3 logs vs 9 baseline logs.
- NEXT: final opt3final bench (inline code) x3 per layout, then import/parse/gdunit/greps, report.
- FINAL (review pass): opt3final (inline code) castle 237/281 (movers p95 292), worst 262/868
  (movers 898), static 171/190; OBJECT_COUNT unchanged in all runs; 0 fallback warnings.
  import 0; parse-check-final.txt all ok; gdunit4-final.log 200/200 pass, exit 0;
  core-greps-final.txt 2 PASS. collision-bench.md rewritten (item 16 done). Story file and
  TD-012 row not edited. Pass complete.
