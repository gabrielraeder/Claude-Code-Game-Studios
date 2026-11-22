# Story 039: Post-import checks I9-I16 and TrackPackage bake

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0005, ADR-0002 and ADR-0004 are Proposed (owner acceptance pending)
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none for the pipeline itself (ADR-0005 is the spec); `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria) for the import refusals
**Requirement**: ADR-0005 Validation Criteria (I9-I16, bake determinism); Track Collision AC-19; ADR-0005 checks I9 Wall normals, I10 Required empties, I11 Probe, I12 Triangle budget, I13 Movers, I14 No collision nodes, I15 Course, I16 Climbable
**Roadmap step**: `architecture.md` Phase A Sequencing step 5 (roadmap item 024: Blender track pipeline end to end). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0005: Blender Track Pipeline (Proposed); ADR-0002: Collision Backend and Surface Attributes (Proposed); ADR-0004: Course Data Format (Proposed)
**ADR Decision Summary**:
- ADR-0005: Editor-time import: a headless Blender exporter (`tools/blender/export_track.py`) writes one `.glb` with `kk_*` custom properties; a Godot `EditorScenePostImport` script (`import_script/path`, also run headless with `--import`) validates it (I1-I16) and bakes a binary `TrackPackage` (`.res`); any failed check refuses the file and names the reason. Runtime `GLTFDocument` is kept only as a future front end for user tracks.
- ADR-0002: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).
- ADR-0004: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0005 2026-11-22; ADR-0002 2026-11-22; ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Open NVs closed in the pipeline stories: NV-1 (keep `art_src/.gdignore` as the real guard), NV-10, NV-15 (fresh-clone first import), NV-16 (verified; re-run). Every script the baker touches is `@tool` and loaded by `preload` path. Blender 5.3 on the platform layer. Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Watched failing.** Each of I9-I16 fails on a broken fixture and passes on the fixed one: a flipped wall; a missing grid slot; a probe over grass; over 160,000 triangles; a duplicate mover id; a `CollisionShape3D` node; a `CourseBuilder` FAIL; a 0.6 m ground ledge on a route (ADR-0005 Validation Criteria).
- [ ] **Import refusals.** A vertex at x = 2000.5, an unknown `surf_lava2`, a wall facing away from every route, a 0.6 m ground ledge on a route and 160,001 triangles each refuse the file with the matching I4 / I5 / I9 / I16 / I12 line (Track Collision AC-19).
- [ ] **Deterministic bake.** Baking twice gives identical arrays, and a shuffled node order gives identical arrays (ADR-0005 Validation Criteria).
- [ ] **Package.** The baked `TrackPackage` `.res` holds `TrackCollisionData`, `CourseData`, the visual scene and the theme, plus `source_sha256` and a `bake_key` that hashes LF-normalised text inputs (ADR-0005; commit 0b12cc5).

---

## Implementation Notes

- I9 runs after the `CourseAuthoring` parse; I15 calls `CourseBuilder.build` (ADR-0004 §14).
- I16 enforces ADR-0003's step-up rule (`max_step_up` = `probe_lift`, 0.5 m).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 040: `TrackLoader`.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/pipeline/track_checks.gd` (I9-I16), `src/pipeline/track_package.gd`, `src/pipeline/track_baker.gd` (new)
- `tests/unit/pipeline/import_checks_i9_i16_test.gd`, `tests/unit/pipeline/track_bake_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/pipeline/import_checks_i9_i16_test.gd`, `tests/unit/pipeline/track_bake_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-038-post-import-checks-i1-i8.md`
- Unlocks: `production/epics/core-rebuild/story-040-track-loader-and-build-script.md`
