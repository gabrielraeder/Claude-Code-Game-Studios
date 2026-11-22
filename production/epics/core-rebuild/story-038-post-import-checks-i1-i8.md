# Story 038: Post-import checks I1-I8

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none for the pipeline itself (ADR-0005 is the spec); `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria) for the import refusals
**Requirement**: ADR-0005 Validation Criteria (each of I1-I15 watched failing, NOT_ASSESSED, grep); ADR-0005 checks I1 Origin, I2 Schema, I3 Fields, I4 Bounds, I5 Ids known, I6 Collision transforms, I7 Pose empties, I8 Ground winding
**Roadmap step**: `architecture.md` Phase A Sequencing step 5 (roadmap item 024: Blender track pipeline end to end). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0005: Blender Track Pipeline (Proposed)
**ADR Decision Summary**: Editor-time import: a headless Blender exporter (`tools/blender/export_track.py`) writes one `.glb` with `kk_*` custom properties; a Godot `EditorScenePostImport` script (`import_script/path`, also run headless with `--import`) validates it (I1-I16) and bakes a binary `TrackPackage` (`.res`); any failed check refuses the file and names the reason. Runtime `GLTFDocument` is kept only as a future front end for user tracks.

**ADR Version**: ADR-0005 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Open NVs closed in the pipeline stories: NV-1 (keep `art_src/.gdignore` as the real guard), NV-10, NV-15 (fresh-clone first import), NV-16 (verified; re-run). Every script the baker touches is `@tool` and loaded by `preload` path. Blender 5.3 on the platform layer.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Watched failing.** On scenes built in code (meta `extras`, `ArrayMesh` surfaces), each of I1-I8 fails on a broken fixture and passes on the fixed one: a node without `kk_layer`; a schema mismatch naming the newer side; `kk_index = 1.5`; a 2,001 m vertex; an unknown material; a non-identity Ground transform; a non-orthonormal pose empty; a flipped ground triangle (ADR-0005 Validation Criteria).
- [ ] **NOT_ASSESSED.** A missing input yields NOT_ASSESSED, not PASS (ADR-0005 Validation Criteria).
- [ ] **Refusal.** Any FAIL refuses the file, names the check and reason, prints `TRACK_IMPORT RESULT FAIL` and writes no package (ADR-0005 Summary).
- [ ] **Grep.** No `get_faces()` and no `src/legacy/` reference in `src/pipeline/` (ADR-0005 Validation Criteria).

---

## Implementation Notes

- `track_post_import.gd` is an `EditorScenePostImport`; it loads core scripts by `preload("res://...")` path, never by `class_name` (NV-7).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 039: I9-I16 and the bake.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/pipeline/track_post_import.gd`, `src/pipeline/track_checks.gd` (new)
- `tests/unit/pipeline/import_checks_i1_i8_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/pipeline/import_checks_i1_i8_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-037-blender-exporter-and-fixtures.md`
- Unlocks: `production/epics/core-rebuild/story-039-post-import-checks-i9-i16-and-bake.md`
