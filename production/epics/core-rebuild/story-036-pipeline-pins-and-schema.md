# Story 036: Track pipeline pins, limits and schema

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0005 is Proposed (owner acceptance pending)
> **Layer**: Core
> **Type**: Integration
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none for the pipeline itself (ADR-0005 is the spec); `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria) for the import refusals
**Requirement**: ADR-0005 Migration Plan steps 1-2 (preset, `project.godot` keys, NV-1/NV-10/NV-16, `.gdignore`, gitignore, core registry instances, `TrackImportLimits`)
**Roadmap step**: `architecture.md` Phase A Sequencing step 5 (roadmap item 024: Blender track pipeline end to end). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0005: Blender Track Pipeline (Proposed)
**ADR Decision Summary**: Editor-time import: a headless Blender exporter (`tools/blender/export_track.py`) writes one `.glb` with `kk_*` custom properties; a Godot `EditorScenePostImport` script (`import_script/path`, also run headless with `--import`) validates it (I1-I16) and bakes a binary `TrackPackage` (`.res`); any failed check refuses the file and names the reason. Runtime `GLTFDocument` is kept only as a future front end for user tracks.

**ADR Version**: ADR-0005 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Open NVs closed in the pipeline stories: NV-1 (keep `art_src/.gdignore` as the real guard), NV-10, NV-15 (fresh-clone first import), NV-16 (verified; re-run). Every script the baker touches is `@tool` and loaded by `preload` path. Blender 5.3 on the platform layer.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Pins.** The import preset (`tools/track_import_preset.gd`) and the `project.godot` keys, including `import_script/path` -> `src/pipeline/track_post_import.gd`, are pinned; NV-1, NV-10 and NV-16 are re-run on the real pipeline with outputs retained (ADR-0005 Migration Plan step 1).
- [ ] **Repo guards.** `art_src/.gdignore` exists, `.gitignore` has a `*.track.res` line, and `assets/data/core/track_import_limits.tres` holds the limits (including `collision_tris_fail` 160,000) with `##` comments (ADR-0005 Migration Plan step 2; I12).
- [ ] **Schema.** `src/pipeline/track_schema.json` defines `SCHEMA`, the `kk_*` keys and `curve_expand_spacing_m`, and is read by both the exporter and the post-import script (ADR-0005; ADR-0004 §14).

---

## Implementation Notes

- Where a pipeline threshold and a builder threshold coincide, the pipeline fills the builder's `CourseBuildSettings` field from `TrackImportLimits` (ADR-0004 §14).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 037: the exporter.
- Story 038-039: the checks.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tools/track_import_preset.gd`, `src/pipeline/track_schema.json`, `src/pipeline/track_import_limits.gd` (new)
- `project.godot`, `.gitignore`, `art_src/.gdignore`
- `assets/data/core/track_import_limits.tres` (new)
- `tests/integration/pipeline/pipeline_pins_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/pipeline/pipeline_pins_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-036/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-030-course-builder-routes-spans-invariants.md`
- Unlocks: `production/epics/core-rebuild/story-037-blender-exporter-and-fixtures.md`
