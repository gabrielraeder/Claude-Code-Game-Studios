# Story 041: Fresh-clone import (NV-15) and a Blender test track end to end

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none for the pipeline itself (ADR-0005 is the spec); `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria) for the import refusals
**Requirement**: ADR-0005 Migration Plan steps 1 and 4 (fresh-clone first import in CI, one test track authored end to end); ADR-0005 Validation Criteria (story 024 evidence); NV-15
**Roadmap step**: `architecture.md` Phase A Sequencing step 5 (roadmap item 024: Blender track pipeline end to end). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0005: Blender Track Pipeline (Accepted)
**ADR Decision Summary**: Editor-time import: a headless Blender exporter (`tools/blender/export_track.py`) writes one `.glb` with `kk_*` custom properties; a Godot `EditorScenePostImport` script (`import_script/path`, also run headless with `--import`) validates it (I1-I16) and bakes a binary `TrackPackage` (`.res`); any failed check refuses the file and names the reason. Runtime `GLTFDocument` is kept only as a future front end for user tracks.

**ADR Version**: ADR-0005 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Open NVs closed in the pipeline stories: NV-1 (keep `art_src/.gdignore` as the real guard), NV-10, NV-15 (fresh-clone first import), NV-16 (verified; re-run). Every script the baker touches is `@tool` and loaded by `preload` path. Blender 5.3 on the platform layer.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **NV-15.** On a clean clone (no `.godot/`, no `*.track.res`), one headless `--import` registers the `@tool` scripts, runs the post-import script and bakes and saves the package with no second pass, in CI; if it fails, the named fallback is taken (two-pass import in `tools/track_build.sh`, then Git LFS for the package) and recorded (ADR-0005 NV-15).
- [ ] **Test track.** One test track authored in Blender goes through `tools/track_build.sh` with no FAIL and is driven in the story-027 drive scene; a screenshot of it in game is retained (ADR-0005 Validation Criteria).
- [ ] **Loop time and NV table.** The authoring-loop time is measured against ADR-0005's target, and the NV table is closed with outputs retained in `production/qa/evidence/core-rebuild-story-041/` (ADR-0005 Validation Criteria).

---

## Implementation Notes

- If NV-15 passes without `@tool`, the marks may be dropped (ADR-0005 NV-7); record the decision.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 042: Castle bootstrap from the legacy JSON.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tools/ci/fresh_clone_import.sh` (new), the CI workflow
- `art_src/tracks/test_track/test_track.blend`, `assets/tracks/core/test_track/test_track.glb` (new)
- `tests/integration/pipeline/fresh_clone_import_test.gd` (new)
- `production/qa/evidence/core-rebuild-story-041/` (NV outputs, screenshot)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/pipeline/fresh_clone_import_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-041/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-027-checkpoint-a1-feel-signoff.md`, `production/epics/core-rebuild/story-040-track-loader-and-build-script.md`
- Unlocks: `production/epics/core-rebuild/story-042-castle-blend-bootstrap.md`
