# Story 008: Legacy track extractor and generator-baked test mesh

> **Epic**: Core Rebuild (Phase A)
> **Status**: In Progress
> **Layer**: Foundation
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: 2026-11-22

## Context

**GDD**: `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0004 §15 (one extractor, consumer 1: the `tools/` test builder); `architecture.md` Test Harness (spline-vs-mesh equivalence over ~100k samples); ADR-0003 Migration Plan step 5 (the parity harness needs the generator bake path)
**Roadmap step**: `architecture.md` Phase A Sequencing step 2-3 (the generator-baked test mesh the kart is driven on). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Accepted); ADR-0002: Collision Backend and Surface Attributes (Accepted); ADR-0005: Blender Track Pipeline (Accepted)
**ADR Decision Summary**:
- ADR-0004: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.
- ADR-0002: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).
- ADR-0005: Editor-time import: a headless Blender exporter (`tools/blender/export_track.py`) writes one `.glb` with `kk_*` custom properties; a Godot `EditorScenePostImport` script (`import_script/path`, also run headless with `--import`) validates it (I1-I16) and bakes a binary `TrackPackage` (`.res`); any failed check refuses the file and names the reason. Runtime `GLTFDocument` is kept only as a future front end for user tracks.
- ADR-0004 §15: one extractor, `tools/legacy_track_export.gd`, runs the frozen `TrackModel` headless and writes neutral JSON outside `assets/`; consumer 1 is a `tools/` test builder producing `TrackCollisionData` plus `CourseAuthoring`; consumer 2 is `tools/blender/legacy_to_blend.py`. Proposed amendment text: tools may run or read the frozen game; nothing under `src/` may load them; their output carries no `src/legacy` reference; they are retired at A3.

**ADR Version**: ADR-0004 2026-11-22; ADR-0002 2026-11-22; ADR-0005 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7). Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Extractor.** `tools/legacy_track_export.gd` runs the frozen `TrackModel` headless for Castle Circuit and Dungeon Depths and writes neutral JSON outside `assets/`; the JSON contains no `src/legacy` reference (grep) (ADR-0004 §15).
- [ ] **Consumer 1, collision half.** `tools/legacy_test_bake.gd` builds `TrackCollisionData` (ground with surface ids, walls per wall attribute, movers) for both tracks from the JSON; a `CollisionQuery` builds from each and passes the story-006 load checks.
- [ ] **Spline-vs-mesh equivalence.** Over about 100k samples on Castle Circuit, height, surface id and wall offset from the mesh are compared with the frozen spline; the tolerances are set and recorded by this story, and the report is retained (`architecture.md` Test Harness).
- [ ] **Boundary.** `tools/core_greps.sh` gains a rule: nothing under `src/` (outside `src/legacy/`) loads the extractor, its output or `src/legacy/`; both tools are listed for retirement at A3 (story 065).

---

## Implementation Notes

- The ADR-0001 §9 amendment (tools may run or read the frozen game) was approved by the owner on 2026-11-22.
- Output location: a gitignored folder outside `assets/` (for example `build/legacy_tracks/`), never imported by Godot.
- The `CourseAuthoring` half of consumer 1 is story 034 (it needs `CourseBuilder`).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 034: the `CourseAuthoring` half and the course equivalence oracle.
- Story 042 / 061: consumer 2, `legacy_to_blend.py`.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tools/legacy_track_export.gd`, `tools/legacy_test_bake.gd`, `tools/spline_mesh_equivalence.gd` (new)
- `tools/core_greps.sh` (new rule)
- `tests/integration/collision/generator_bake_test.gd` (new)
- `production/qa/evidence/core-rebuild-story-008/` (equivalence report)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/collision/generator_bake_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-008/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-006-collision-load-checks-and-mirror.md`; owner approval of the ADR-0001 §9 amendment (ADR-0004 §15)
- Unlocks: `production/epics/core-rebuild/story-026-parity-run-rebuilt-kart.md`, `production/epics/core-rebuild/story-034-generator-course-equivalence.md`
