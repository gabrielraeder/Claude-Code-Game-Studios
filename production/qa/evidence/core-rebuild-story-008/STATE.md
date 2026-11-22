# Story 008 working state

- [x] Step 1: read story, ADR-0004 s15, ADR-0002 schema/mirror, core collision scripts, registries (2026-11-22)
- [x] Step 2: read frozen TrackModel (Path arrays, query/_to_query, zones, pads, ramps, walls, openings) and HazardManager (pose_at, progress_at, distance_at). Castle/Dungeon load via TrackLibrary.load_track(id) -> TrackModel.new(data).
- [x] Step 3: `tools/legacy_track_export.gd` written and run (headless, exit 0):
  - output `build/legacy_tracks/{castle_circuit,dungeon_depths}.json` + `.gdignore` (build/ is already gitignored)
  - castle: 4 paths (main 1145.3 m, 916 samples), 1 ramp, 4 pads, 4 zones, 3 hazards, 5 movers (2 gates, 3 barrels)
  - dungeon: 5 paths (main 1095.6 m), 1 ramp, 3 pads, 4 zones, 4 hazards, 4 movers (3 bursts, 1 cart)
  - `grep -c src/legacy` on both JSON files: 0 (the extractor also refuses to write output containing src/legacy, res://, .gd, .tres)
- [x] Step 4: `tools/legacy_test_bake.gd` written and run: both tracks bake, checked_query passes (normal and mirrored). Evidence `bake_run.txt`, `extract_run.txt`. 
- [x] Step 5: `tools/spline_mesh_equivalence.gd` run on Castle (100000 height/surface + 11328 wall samples). Report `equivalence_report.md`, log `equivalence_run.txt` (exit 1). Held out of tolerance: height 146/98120 (max 0.221 m, p99.9 0.056), surface 1/97033 (a deck-edge miss), wall 146/9234 (max 0.515 m, p99 0.070). NOT all within tolerance: see report worst rows.
- [x] Step 6: core_greps rule added; real tree PASS (`core_greps_real.txt`), planted scratch copy FAIL on the preload and the class name, string literal ignored (`core_greps_planted.txt`). Scratch tree deleted.
- [x] Step 7: story 065 "Retire at A3" subsection added under Implementation Notes.
- [x] Step 8: `tests/integration/collision/generator_bake_test.gd` (8 tests) run with gdUnit4 after `build_native.sh --check` CHECK PASS: 8/8 passed (`gdunit_generator_bake_test.txt`).
- Fixture test written; extractor JSON v1 now also carries road_keep_band and branch_switch_margin.

## Bake design (decided, step 4)
- Decks per path: cells from the frozen samples (miter normals, lerp between), subdivided to ~1 m along / ~1 m across, heights from the frozen formula y + clamp(lat) * tan(bank).
- Surface per deck triangle: exact 2D clip (Geometry2D.intersect/clip_polygons) against pads (7) then zones in data order (zone kind -> core id); rest road (0).
- Ramps: separate wedge (trick_ramp 8) on top of the deck, lifted RAMP_LIFT.
- Off-road zones: their own triangles (frozen vertex heights). Floor: one quad at ground_y (road id, neutral).
- Walls: per path side at wall_at, skipped in wall openings and where inside another road's corridor at the same level; fence edges of zones as walls. Branch wall_drag_mult 2.0 -> rough (1), else standard (0).
- Movers: drawbridge deck = solid BOX rotating about the hinge (static deck removed there); portcullis = solid BOX grille; barrels, bursts = non-solid cylinders; cart = solid BOX. Keys = frozen pose at every tick.

## Round 2 (coordinator: fix the bake to meet the unchanged tolerances)
- [x] Bake: deck heights and edge fits from each cell's own segment (keeps the frozen inside-of-turn step at the mitre line); EDGE_SKIRT 0.03 m under walled edges; overlapping decks cut on the frozen ownership line (bisection, `_cut_tri`, `_owner_of`).
- [x] Equivalence: walled-edge band removed (held again); wall truth = frozen barrier along the ray (`_frozen_barrier`); BASELINE before/after table; worst list 10.
- [ ] First round-2 bake run is slow (seam bisection used whole-path searches; machine shared with story 067's build). Patched to a windowed owner search (`_owner_of` with only/hint) while it runs. Cannot kill it (classifier denied). Wait, then re-run bake, equivalence, gdUnit.
- The slow round-2 run (pids 12972 / 13452, old whole-path seam search) was ended by the owner: NOT a result. Its partial log showed Castle baking (574 seam cuts) and then the load check failing to compile because story 067 had swapped `CollisionQuery` to native mid-run, so checked_query could not run either way.
- HOLD: no Godot process until the coordinator sends "008 go" (story 067 has the machine).
- To do on "008 go": parse-check the 3 tools + test; run bake (`bake_run.txt`), equivalence (`equivalence_report.md`, `equivalence_run.txt`), gdUnit for `generator_bake_test.gd` only (after `build_native.sh --check`).
- Review during HOLD (no Godot):
  - `_cut_tri`: when no owner is found at a flagged vertex (float edge case) the whole edge is kept, so no hole can open. Fixed.
  - Ownership is complementary between two decks (`_frozen_prefers` with main as the hint-free current road), and a point is given away only to a road whose deck holds it, so no double deck and no gap at the seam.
  - Story 067's native port: the GroundHit / WallHit properties (point, normal, surface_id, wall_attr, started_inside, collider_id) and the CollisionQuery methods the tools use (cast_ground, sweep_walls) are all bound in native/src/collision. The tools build only through checked_query and use no-argument `.new()` for hits and cursors.
  - `generator_bake_test.gd` now preloads `tests/unit/native/native_test_guard.gd` and asserts `problem()` is empty in `before()`, so a stale DLL is refused.

## Round 2 run ("008 go")
- [x] Parse check: all 4 files ok.
- [x] Export exit 0; JSON has 0 `src/legacy`, 0 `res://` (`extract_run.txt`).
- [x] Bake exit 0; checked_query (native CollisionQuery) PASS, normal and mirrored, on both tracks (`bake_run.txt`).
- [x] Equivalence exit 1 (`equivalence_report.md`, `equivalence_run.txt`). Held rows: height 146 -> 44 out (max 0.221 -> 0.181), surface 1 -> 3, wall 146 -> 99 out (max 0.515 -> 0.353).
- [x] Shared vertex against native: at the exact vertex the cast goes through the deck to the floor (y -0.05, id 0); 1-2 cm off it hits pad 7 / slick 6 (`shared_vertex_native.txt`). So it is a pinhole along a cross-section row, not a face_index mix-up.
- [ ] Next, not done yet:
  - share each boundary row's XZ between the two segments either side of it;
  - set WALL_PROBE_RADIUS to 0.01;
  - drawbridge seam hole at path 1 along 12.4-13.0;
  - secret-passage fold walls;
  - main 1073-1076 on the inside of the turn.
- gdUnit not run (waiting for "008 gdunit").

## Round 3 (coordinator items 1-5)
- [x] Boundary rows are computed once per sample and shared, and lerp endpoints are exact, so continuous boundary vertices are bit-identical.
  - Frozen steps (height difference > 1e-4 m) keep both heights. The step vertex reaches 2 mm into the neighbouring cell, so the two cells overlap rather than meeting on a zero-width line.
- [x] Watertightness check over each deck's base cell grid: 0 unexpected open edges on both tracks.
  - Castle open edges: 4984 outer, 58 at path ends or gate decks, 13230 frozen steps. Dungeon: 5360 / 68 / 10752.
  - Step-vertex cast check (bake runner): no fall-through; Castle 5867 casts, Dungeon 4830.
- [x] Walls follow the frozen barrier (`_barrier`, a root search with the query window), and chords that cut back into the road are clipped (`_clip_fraction`): 25 on Castle, 11 on Dungeon. The fold drop is removed.
- [x] Equivalence probe radius set to 0.01 m; the reason is written in the report.
- [x] Fixture tests added: `test_cast_exactly_on_a_shared_deck_vertex_hits_the_deck` and `test_deck_grid_is_watertight`. Not run; waiting for "008 gdunit".
- Equivalence (exit 1), held rows: height 44 out (max 0.181), surface 3, wall 32 out (max 0.138, p99 0.020).
- Open, not fixed yet:
  - drawbridge seam hole at path 1 along 12.4-13.0. The frozen game gives the point to the drawbridge, but the mesh falls to the floor;
  - deck misses at main along 519.9 (village-lane seam) and secret passage along 39.7-40.0;
  - main 1073-1076, inside of the turn: height +0.07 to +0.125, not yet diagnosed;
  - wall residue: 32 held samples out, max 0.138.

## Round 4 ("008 go")
- [x] Seam fix: cells that touch another road's ownership are split up to 5 levels (`_seam_tri`, `SEAM_DEPTH` 5, 3 cm leaves) before each leaf is cut or dropped. Wall pieces that run into a junction are clipped, not dropped (`_junction_fraction`): 33 on Castle, 32 on Dungeon.
- [x] Seam check on the cut mesh (`seam_cast_problem`, run by the bake): FAIL, Castle 8279 of 42363 probes, Dungeon 17572 of 93251 (`bake_run.txt`).
  - Not yet sorted into real gaps and probe-definition artefacts.
  - Dungeon has 1 step-vertex fall-through at (-1.47, 241.29).
- [x] Equivalence (exit 1). Held rows: height 24 out, 0 misses (max 0.125); surface 0; wall 29 out, 1 miss (max 0.117). Each worst entry carries a case-by-case verdict (frozen jump within 0.01 m) in `equivalence_report.md`.
- [x] `tools/legacy_bake_tri_dump.gd` added (debug helper; listed for retirement with the bake).
- [x] gdUnit, 10 test cases, all pass. The suite still FAILS: `before()` guard reports a stale native DLL (`gdunit_generator_bake_test.txt`).
  - `build_native.sh --check` printed CHECK PASS just before the run, then CHECK FAIL (3) right after (`build_native_check.txt`).
  - The native sources changed under the DLL; a rebuild is needed (not mine to run).

## Round 5 (started 18:58; report due 20:30)
- [x] Seam probes now target the deck the frozen game assigns at the exact xz (`_seam_probe`, the same `_frozen_prefers` rule). The other deck's height is accepted when it also holds the point. The owner search inside `_seam_tri` is windowed (`_owned_at`).
- [x] Adaptive deck cells (`_refine_tri`): split while the frozen height is more than 5 mm off the cell plane, up to 3 levels (12.5 cm).
- [x] Adaptive wall pieces (`_wall_refine`): split while the barrier is more than 5 mm off the chord, up to 4 levels. Junction and fold clips are applied per leaf (`_wall_piece`).
- [ ] Running: bake, equivalence. gdUnit waits for story 067's DLL rebuild.
- First round-5 bake (19:01, 238 s): seam check still FAIL. Castle 8006 of 41609, Dungeon 17524 of 93109. Cells refined: Castle 15454, Dungeon 7739. Wall pieces refined: Castle 1186, Dungeon 417.
- Diagnosis with `tools/legacy_bake_tri_dump.gd` at (28.216, 108.531): only drawbridge triangles are nearby, and only the floor contains the point. The frozen game gives the point to main, but main's cell there was dropped: all its corner, midpoint and centroid samples said "drawbridge", stepping over a thin wedge of main ownership.
  - Fix: `_seam_margin`. The ownership quantities change by at most 2 m per m, so a cell is split while the smallest of them at its centroid is under 2x the cell radius.
- RULE SLIP: two short Godot runs (the tri dump and one parse check) started while the other agent's 2 Godot processes were up. Each was a single headless script of a few seconds, and nothing was killed. Every later run waits for the process count to reach 0.
- Second round-5 bake (19:08-19:17, 534 s), with `_seam_margin`: seam check still FAIL, but the miss rate fell. Castle 9845 of 791789 probes (1.2%, was 19%); Dungeon 18285 of 2807477 (0.65%, was 19%).
  - The same clusters remain: Castle around (28.2, 108.5-108.95), where the frozen game says main at 0.0 and no deck triangle covers the point; Dungeon around (12.35-12.38, 176.3-177.1) and (20.9-21.0, 176.9-177.9).
  - Dungeon step fall-through: now 2, at (-1.51, 240.77) and (-1.47, 241.29).
  - The bake now takes about 9 min (millions of probes).
- Running: equivalence (background, waits for the Godot process count to reach 0).
- Equivalence after the round-5 bake (19:18-19:22, exit 1), held rows: height 2 out (max 0.125; the case proof calls it a frozen discontinuity), surface 0, wall 20 out with 0 misses (max 0.254 at main 763.25, a bake error).
  - The main 725 miss is gone.
  - The drawbridge 86.63 height sample (-0.073) lands on the floor: a deck hole.
- 19:22: HOLD again (story 067 benchmark). I stopped my own queued tri-dump loop (a bash loop, not Godot) before it started Godot. No Godot until "008 go".
- Prepared, not run: scratchpad `s008_diag.gd`. It prints a 5 cm ownership map around a gap point: the frozen road there and which decks the bake keeps.

## Round 6 ("008 go", 19:46; report due 20:40)
- [x] `s008_diag.gd` at the Castle gap (28.216, 108.531): ownership is consistent. Every point on the 5 cm map belongs to exactly one road, and the bake rule agrees with the frozen game.
  - The triangle dump shows main's refined leaves stopping right at the main/drawbridge boundary, with nothing covering the probe but the floor.
  - Diagnosis: the gaps are along cell edges, not ownership errors.
    - Refined cells and seam leaves meet unrefined neighbours at T-junctions. The mid vertex sits on the frozen surface while the neighbour edge is straight, so there is a vertical crack of zero XZ width.
    - The two decks' cut lines at a seam are not shared.
    - The seam and step probes sit exactly on such edges and vertices, so they slip through.
- [x] Fix:
  - `_fix_t_junctions`: inserts every vertex lying on another triangle's edge (1e-4 m in XZ, 7 mm in height) and re-fans that triangle around its centroid, keeping its facing.
  - `SEAM_OVERLAP` 2 mm: the kept side of a seam cut runs 2 mm past the cut line.
  - `RAMP_LIFT` raised 0.005 -> 0.01 so the repair never stitches a ramp foot into the deck.
- [ ] Running (background): bake, then equivalence. Then gdUnit.
- Round-6 bake (19:52-20:02): T-junction repair ran (Castle 31,984 triangles, Dungeon 62,487). Ground triangles: Castle 391,334, Dungeon 883,840.
  - Seam check still FAIL: Castle 9803 of 791789, Dungeon 18080 of 2807477. The same points as before, so the T-junction theory is NOT confirmed.
  - Step check got worse: Castle 9 fall-throughs, Dungeon 3.
  - Grid check: 0 unexpected open edges on both tracks.
- Round-6 equivalence (20:02-20:06, exit 1), held rows: height 2 out (max 0.125), surface 0, wall 20 out, 0 misses (max 0.254 at main 763.25).
- build_native --check: CHECK PASS. gdUnit `generator_bake_test.gd`: 10/10 PASS, exit 0 (20:07).
- Running: tri dump at the exact Castle probe point (r = 4 mm).
- Tri dump at the exact failing Castle probe (28.21585, 108.5312): main deck tri 26638 (y 0.0, sides about 1 cm, facing up) contains the point in XZ, yet the native cast from y 10 hits the floor.
  - The point lies on that triangle's edge (cross product about 0), and nothing on the deck's level lies across the edge.
  - A cast at the triangle's centroid (28.21461, 108.53503) hits it at y -0.000002.
  - So this probe sits exactly on the outer edge of main's kept region at the seam, and the neighbouring area across that edge is uncovered at deck level. Whether that area is a real sliver gap or just the edge of the cut is NOT resolved.
- Report delivered 20:15. Remaining gaps are listed in the report.

## Handoff (2026-11-22, end of round 6)

The code is left as it is at the end of round 6, with no reverts. No Godot is running. Nothing is committed.

### 1. Results to date

Held rows of `equivalence_report.md`. Tolerances never changed: height and wall offset 0.05 m, surface id exact outside a 0.25 m band.

| Held row | Round 1 (first report) | Round 5 (19:18-19:22) | Round 6 (20:02-20:06) |
|---|---|---|---|
| height: out / misses / max / p99 / p99.9 | 146 / 1 / 0.221 / - / - (98,120 samples) | 2 / 0 / 0.1252 / 0.0045 / 0.0067 (98,648) | 2 / 0 / 0.1252 / 0.0044 / 0.0103 (98,648) |
| surface: mismatches | 1 (97,033) | 0 (97,561) | 0 (97,561) |
| wall: out / misses / max / p99 / p99.9 | 146 / 10 / 0.515 / - / - (9,234) | 20 / 0 / 0.2544 / 0.0061 / 0.0644 (9,233) | 20 / 0 / 0.2544 / 0.0061 / 0.0644 (9,233) |

Bake self-checks (`bake_run.txt`):

| Check | Round 5 | Round 6 |
|---|---|---|
| seam probes missing, Castle | 9,845 of 791,789 | 9,803 of 791,789 |
| seam probes missing, Dungeon | 18,285 of 2,807,477 | 18,080 of 2,807,477 |
| step-vertex fall-throughs, Castle / Dungeon | 0 / 2 | 9 / 3 |
| base-grid unexpected open edges | 0 / 0 | 0 / 0 |
| ground triangles, Castle / Dungeon | not recorded (more than 101k / 103k) | 391,334 / 883,840 |
| bake time (both tracks, plus mirrored load checks) | 534 s | about 650 s |

Other results:
- `checked_query` and the story-006 load checks pass on both tracks, normal and mirrored, with the native `CollisionQuery` from story 067.
- gdUnit `tests/integration/collision/generator_bake_test.gd`: **10/10 PASS, exit 0** (20:07, after `build_native.sh --check` printed CHECK PASS; `gdunit_generator_bake_test.txt`).
- The extractor exports with exit 0, and both JSON files contain 0 `src/legacy` and 0 `res://`.
- `tools/core_greps.sh`: the story-008 rule passes on the real tree and fails on the planted scratch copy (round 1).
- The story 065 "Retire at A3" note lists the four tools and the test.

### 2. Every failing point (round 6)
- **Seam clusters** (the probe's holding deck, then "no hit" at that deck's level):
  - Castle, main/drawbridge seam: x 28.19-28.22, z 108.53-108.95, main at 0.0.
    - (28.21585, 108.5312) lies exactly on an edge of main triangle 26638, and nothing at deck level lies across that edge.
    - A cast at that triangle's centroid hits it (y -0.000002).
  - Dungeon: (12.35-12.38, 176.26-177.09) at about 1.12, and (20.91-20.99, 176.97-177.85) at 1.08-1.12.
  - The rest of the 9,803 / 18,080 misses: only the first 10 of each are listed (`EDGES_LISTED`).
- **Step fall-throughs:**
  - Castle: (130.83, 197.80) step 2.404-2.411; (137.35, 191.30) 3.346-3.352; (138.59, 186.74) 3.773-3.778; (138.56, 183.18) 4.093-4.098; (135.36, 175.61) 4.838-4.844; (129.82, 171.26) 5.480-5.486; (119.65, 171.45) 6.232-6.238; (-55.90, 246.35) 4.685-4.690; (-62.54, 15.64) 2.268-2.273.
  - Dungeon: (27.09, 4.04) 6.398-6.404; (29.14, 4.01) 6.414-6.421; (36.86, 124.36) 3.520-3.526.
  - Round 5's Dungeon points (-1.51, 240.77) and (-1.47, 241.29) are no longer reported.
- **Drawbridge along 86.63, lateral 1.08** (86.74, 143.48): height -0.073 m, the cast lands on the floor. A real deck hole; the frozen surface is smooth there (jump 0.023 within 1 cm).
- **Main 763.25, side +1:** wall -0.254 m (frozen barrier 10.032, wall_at 9.780). The frozen barrier is smooth there (jump 0.004), so this is a bake error.
- **Other held failures:** 18 wall samples and 1 height sample. Each has its verdict in the report; most walls are on the drawbridge taper at along 17.75-23.5 and main 311.5 / 724.0, several of them frozen discontinuities. The remaining held height failure (+0.125 at main 1074.83) is a frozen discontinuity.

### 3. What each round tried, and what it did to the numbers

| Round | Change | Effect |
|---|---|---|
| 1 | First bake: per-path decks with mitre cross-sections; 1 m cells; global-nearest heights; pads and zones clipped exactly; ramp wedge; floor; walls at wall_at; fold and junction drops | height 146 out, wall 146 out (first report) |
| 2 | Own-segment heights (keeps the frozen inside-of-turn step); 3 cm skirt under walled edges; ownership cut on the frozen switch line (`_cut_tri`) | height 146 -> 44, wall 146 -> 99; seam holes appeared |
| 3 | Shared boundary rows plus exact-endpoint lerp; frozen-step vertices nudged 2 mm (`STEP_OVERLAP`); base-grid watertightness and step-cast checks; walls on the frozen barrier (`_barrier`) with clipped fold chords; probe radius 0.01 m | wall 99 -> 32; height stayed 44; step casts 0 fall-through on Castle |
| 4 | Seam cells split up to 5 levels (`_seam_tri`); junction walls clipped, not dropped; seam-cast check; case-by-case verdicts | height 44 -> 24, 0 misses; surface 0; wall 32 -> 29; seam check FAIL (8279 / 17572); bake about 5 min |
| 5 | Probes test the deck the frozen game assigns; windowed owner search; adaptive deck cells (`_refine_tri`) and wall pieces (`_wall_refine`); margin-based seam split (`_seam_margin`) | height 24 -> 2, wall 29 -> 20 (0 misses, main 725 fixed); seam miss rate 19% -> 1.2% / 0.65%; bake 9 min; triangle count jumped |
| 6 | T-junction repair (`_fix_t_junctions`), `SEAM_OVERLAP` 2 mm, `RAMP_LIFT` 0.005 -> 0.01 | **did not help; made step checks worse**: seam misses about the same (9,803 / 18,080), step fall-throughs 0/2 -> 9/3, triangles 391k / 884k |

### 4. Root-cause hypothesis and design alternatives

**Hypothesis.** Each road builds its deck on its own, and two overlapping decks are then cut on a computed ownership line. The decks have unrelated triangulations, so their cut chords, T-junctions and nudged step vertices never share vertices. Along the seam a ray can land on the open edge of one deck with the other deck already cut away. Every fix so far refined the cut (deeper splits, probes, overlap, T-junction repair) instead of removing it. That multiplied the triangles and made new open edges (the step fall-throughs in round 6). The frozen ownership rule itself is consistent: the 5 cm map in `s008_diag.gd` shows each point owned by exactly one road, matching the bake.

**Alternatives:**
- **A. One merged deck per level, built from a 2D union of the road footprints, with heights from the owning road.**
  - Each road's deck outline (offset of the centre line at reach, plus skirt) is unioned per level (`Geometry2D.merge_polygons`).
  - Triangulate the union once (constrained triangulation, or a grid clipped to the union), then set each vertex height from the road the frozen game gives it to.
  - Ownership steps (drawbridge 0.13 over main 0.0) become one shared cut polyline inserted into the single mesh, with duplicated vertices on both sides and the same XZ, so it is watertight by construction.
  - Triangles: about the round-3 base count, Castle about 101k and Dungeon about 103k including floor, zones and ramps, minus the doubled overlap. With adaptive refinement capped near tight turns, about 100-120k per track: near ADR-0005's 120k WARN, under the 160k FAIL.
  - Risk: a constrained triangulation in GDScript (Geometry2D offers none with holes); a clipped grid avoids it.
- **B. Extend one deck under the other, with no cut at all.**
  - Keep main whole. Trim each branch only to its own outline, overlapping main by a margin.
  - Triangles: about the base count, about 100k.
  - Fails the height tolerance wherever the lower deck owns the point. At the drawbridge (0.13 over main 0.0, a frozen step) the upper deck wins the ray, so the error is up to 0.13 m in the overlap. Acceptable only if the owner rule is changed to "upper deck wins", which is a design change for the owner, not a bake fix.
- **C. Sample the frozen support directly.**
  - The extractor exports `TrackModel.query(p).support` and road ownership on a per-level grid over the deck footprints (0.5 m, adaptive near steps).
  - The bake triangulates that grid as one mesh per level, splitting quads on frozen steps.
  - Triangles: Castle deck area about 12,000 m2 at 0.5 m is about 96k, about 50-70k with coarser cells where flat.
  - JSON grows by several MB per track.
  - Watertight by construction, and it carries the frozen discontinuities as data.

### 5. Bake time and triangle count against ADR-0005
- ADR-0005 import limits are 120k triangles WARN and 160k FAIL. Round 6 is 391,334 (Castle) and 883,840 (Dungeon): 2.4x and 5.5x the FAIL limit.
- Most of the growth is seam splits (round 5: 305k Castle and 1.1M Dungeon split operations) and T-junction fans (round 6).
- Bake time: 4 s (round 1) -> about 5 min (round 4) -> 9 min (round 5) -> about 11 min (round 6). This is GDScript nearest-segment searches inside the seam subdivision and probe generation (2.8M probes on Dungeon).
- The equivalence run itself takes about 3-4 min.
- Any redesign should hold the base count of about 100k and remove the seam probes as a bake-time cost.

### 6. Files and constants per round, and what to revert
- **Files** (all under story 008):
  - `tools/legacy_track_export.gd`; `tools/legacy_test_bake.gd`; `tools/spline_mesh_equivalence.gd`; `tools/legacy_bake_tri_dump.gd` (round 4);
  - `tests/integration/collision/generator_bake_test.gd`;
  - the `tools/core_greps.sh` rule; the story 065 note.
  - Scratch, not in the repo: `s008_diag.gd` in the session scratchpad.
- **Round 1:** ALONG_STEP 1.0, LAT_STEP 1.0, RAMP_STEP 0.5, RAMP_LIFT 0.005, WALL_HEIGHT 2.0, WALL_BELOW 0.5, WALL_STEP 1.0 (0.25 from round 1b), JUNCTION_EPS 0.05, OPEN_EPS 0.01, FLOOR_MARGIN 20, NEAREST_WINDOW 6, PROBE_LIFT 2.0, PROBE_MAX_DROP 4.0, MIN_GRILLE_HALF 0.1, AREA_EPS 1e-4, CLIP_AREA_REL 0.01, MIN_MITRE_COS 0.5; exporter KEY_DT 1/60, STATIC_PERIOD 1.0. **Keep.**
- **Round 2:** EDGE_SKIRT 0.03, CUT_ITERATIONS 10, `_cut_tri`, `_owner_of`, `_frozen_prefers`; the exporter's road_keep_band and branch_switch_margin. **Keep `_frozen_prefers` and the exports; replace the cut with the redesign.**
- **Round 3:**
  - STEP_EPS 1e-4, STEP_OVERLAP 0.002, ROOT_MARCH 0.1, ROOT_BISECT 24, ROOT_SPAN 2.0, STEP_CAST_START 0.5, STEP_CAST_EPS 0.001, EDGES_LISTED 10;
  - `_barrier`, `_boundary_row`, `_check_edges`, `step_cast_problem`, `_clip_fraction`; exporter `query_window`;
  - equivalence WALL_PROBE_RADIUS 0.01, `_frozen_barrier`, WALL_MARCH 0.25, WALL_BISECT 16.
  - **Keep.** Re-check STEP_OVERLAP under the redesign.
- **Round 4:**
  - SEAM_DEPTH 5, SEAM_PROBE_IN 0.005, SEAM_CAST_TOL 0.02, `_seam_tri`, `seam_cast_problem`, `_junction_fraction`;
  - equivalence CASE_PROBE 0.01 and the case verdicts.
  - **Revert the seam subdivision** (`_seam_tri` and SEAM_DEPTH). Keep the case verdicts, the junction wall clip, and a seam-check idea redesigned for the new deck.
- **Round 5:**
  - REFINE_TOL 0.005, REFINE_DEPTH 3, WALL_REFINE_TOL 0.005, WALL_REFINE_DEPTH 4;
  - `_refine_tri`, `_wall_refine`, `_wall_piece`, `_seam_probe`, `_owned_at`, `_seam_margin`.
  - **Keep** `_wall_refine` / `_wall_piece`, and `_refine_tri` with a triangle budget. **Revert** `_seam_margin`, `_owned_at`, `_seam_probe` together with the seam subdivision.
- **Round 6:** TJ_EPS 1e-4, TJ_HEIGHT_TOL 0.007, TJ_CELL 0.5, TJ_MAX_EDGE 2.0, SEAM_OVERLAP 0.002, `_fix_t_junctions`, RAMP_LIFT 0.01. **Revert all of it** (RAMP_LIFT back to 0.005): it did not help and made the step checks worse.
- **Open items carried:**
  - The shared-vertex surface id is a logged open item; the coordinator will write the rule into the collision GDD.
  - Dungeon's `mine_rail` `floor_drag_mult` 1.25 is baked as plain road (story 026).
