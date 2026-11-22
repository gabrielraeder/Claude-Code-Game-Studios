# Story 042: Castle Circuit .blend bootstrap (legacy consumer 2)

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria); `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0004 §15 (consumer 2); ADR-0005 Migration Plan (Legacy tracks); Course Data AC1
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025: Castle Circuit rebuilt). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0005: Blender Track Pipeline (Accepted); ADR-0004: Course Data Format (Accepted)
**ADR Decision Summary**:
- ADR-0005: Editor-time import: a headless Blender exporter (`tools/blender/export_track.py`) writes one `.glb` with `kk_*` custom properties; a Godot `EditorScenePostImport` script (`import_script/path`, also run headless with `--import`) validates it (I1-I16) and bakes a binary `TrackPackage` (`.res`); any failed check refuses the file and names the reason. Runtime `GLTFDocument` is kept only as a future front end for user tracks.
- ADR-0004: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0005 2026-11-22; ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Open NVs closed in the pipeline stories: NV-1 (keep `art_src/.gdignore` as the real guard), NV-10, NV-15 (fresh-clone first import), NV-16 (verified; re-run). Every script the baker touches is `@tool` and loaded by `preload` path. Blender 5.3 on the platform layer. The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Bootstrap.** `tools/blender/legacy_to_blend.py` builds `art_src/tracks/castle_circuit/castle_circuit.blend` from the extractor JSON: ground with surface materials, walls with `wall_<name>` materials, movers, checkpoint, respawn, grid and item-box empties, and routes as curves (ADR-0004 §15).
- [ ] **Through the pipeline.** `tools/track_build.sh castle_circuit` imports it with no FAIL and no NOT_ASSESSED line, and the package loads (Course Data AC1).
- [ ] **Matches the generator course.** Gate positions, route samples and surface ids match the story-034 generator course within that story's tolerance, and the mesh `track_check` passes (story 035).
- [ ] **Boundary.** The `.blend` and package carry no `src/legacy` reference; the script is listed for retirement at A3 (story 065).

---

## Implementation Notes

- Do not start until the owner approves the ADR-0001 §9 amendment (ADR-0004 §15).
- From here on Castle Circuit ships only through the Blender pipeline (ADR-0005).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 061: Dungeon Depths bootstrap.
- Story 052: re-authoring hazards beyond what the JSON carries.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tools/blender/legacy_to_blend.py` (new)
- `art_src/tracks/castle_circuit/castle_circuit.blend`, `assets/tracks/core/castle_circuit/castle_circuit.glb` (new)
- `tests/integration/pipeline/castle_bootstrap_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/pipeline/castle_bootstrap_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-042/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-035-mesh-track-check.md`, `production/epics/core-rebuild/story-041-fresh-clone-import-and-test-track.md`; owner approval of the ADR-0001 §9 amendment (ADR-0004 §15)
- Unlocks: `production/epics/core-rebuild/story-050-castle-race-clock-registry-tick.md`, `production/epics/core-rebuild/story-061-dungeon-blend-bootstrap.md`
