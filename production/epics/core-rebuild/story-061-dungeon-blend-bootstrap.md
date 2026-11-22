# Story 061: Dungeon Depths .blend bootstrap and import

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0005 and ADR-0004 are Proposed (owner acceptance pending); ADR-0001 §9 amendment (ADR-0004 §15, legacy extractor) pending owner approval — nothing in ADR-0004 §15 may be implemented until it is approved
> **Layer**: Core
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0004 §15 (consumer 2); ADR-0005 Migration Plan (Legacy tracks); Course Data AC1 to AC9
**Roadmap step**: `architecture.md` Phase A Sequencing step 7 (Dungeon Depths rebuilt; composition root switch; old modules retired, owner-approved; checkpoint A3). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0005: Blender Track Pipeline (Proposed); ADR-0004: Course Data Format (Proposed)
**ADR Decision Summary**:
- ADR-0005: Editor-time import: a headless Blender exporter (`tools/blender/export_track.py`) writes one `.glb` with `kk_*` custom properties; a Godot `EditorScenePostImport` script (`import_script/path`, also run headless with `--import`) validates it (I1-I16) and bakes a binary `TrackPackage` (`.res`); any failed check refuses the file and names the reason. Runtime `GLTFDocument` is kept only as a future front end for user tracks.
- ADR-0004: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0005 2026-11-22; ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Open NVs closed in the pipeline stories: NV-1 (keep `art_src/.gdignore` as the real guard), NV-10, NV-15 (fresh-clone first import), NV-16 (verified; re-run). Every script the baker touches is `@tool` and loaded by `preload` path. Blender 5.3 on the platform layer. The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Bootstrap.** `tools/blender/legacy_to_blend.py` builds `art_src/tracks/dungeon_depths/dungeon_depths.blend` from the extractor JSON (ADR-0004 §15).
- [ ] **Import.** `tools/track_build.sh dungeon_depths` imports it with no FAIL and no NOT_ASSESSED line, and the bake's structure, respawn and grid lines PASS (Course Data AC1-AC9).
- [ ] **Matches.** Gate positions, route samples and surface ids match the story-034 generator course within that story's tolerance, and the mesh `track_check` passes (story 035).

---

## Implementation Notes

- Do not start until the owner approves the ADR-0001 §9 amendment (ADR-0004 §15).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 062: Dungeon gameplay on the new core.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `art_src/tracks/dungeon_depths/dungeon_depths.blend`, `assets/tracks/core/dungeon_depths/dungeon_depths.glb` (new)
- `tests/integration/pipeline/dungeon_bootstrap_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/pipeline/dungeon_bootstrap_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-061/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-042-castle-blend-bootstrap.md`, `production/epics/core-rebuild/story-060-checkpoint-a2-castle-online.md`; owner approval of the ADR-0001 §9 amendment (ADR-0004 §15)
- Unlocks: `production/epics/core-rebuild/story-062-dungeon-gameplay-rebuild.md`
