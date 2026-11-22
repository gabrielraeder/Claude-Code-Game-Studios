# Story 040: TrackLoader and tools/track_build.sh

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0005 is Proposed (owner acceptance pending)
> **Layer**: Core
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none for the pipeline itself (ADR-0005 is the spec); `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria) for the import refusals
**Requirement**: ADR-0005 Validation Criteria (failing fixture writes no package, stale package refused); ADR-0005 Migration Plan step 3 (`tools/track_build.sh`); ADR-0001 §7 (mirror at load)
**Roadmap step**: `architecture.md` Phase A Sequencing step 5 (roadmap item 024: Blender track pipeline end to end). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0005: Blender Track Pipeline (Proposed); ADR-0001: Simulation Conventions and Code Layout (Accepted)
**ADR Decision Summary**:
- ADR-0005: Editor-time import: a headless Blender exporter (`tools/blender/export_track.py`) writes one `.glb` with `kk_*` custom properties; a Godot `EditorScenePostImport` script (`import_script/path`, also run headless with `--import`) validates it (I1-I16) and bakes a binary `TrackPackage` (`.res`); any failed check refuses the file and names the reason. Runtime `GLTFDocument` is kept only as a future front end for user tracks.
- ADR-0001: Godot Y-up, -Z forward, metres; the synced race time is authoritative and the 60 Hz tick follows it with a defined catch-up policy; a fixed step order and one seeded random stream per consumer; our own interpolation with a teleport flag; mirror mode is a proper reflection at track load; the frozen 2.5D game lives in `src/legacy/`, shared data classes in `src/data/`, new code in new folders.

**ADR Version**: ADR-0005 2026-11-22; ADR-0001 2026-11-21

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Open NVs closed in the pipeline stories: NV-1 (keep `art_src/.gdignore` as the real guard), NV-10, NV-15 (fresh-clone first import), NV-16 (verified; re-run). Every script the baker touches is `@tool` and loaded by `preload` path. Blender 5.3 on the platform layer. Tick settings are pinned (`physics_ticks_per_second=60`, `max_physics_steps_per_frame=8`, `physics_interpolation=false`). Since 4.4 every script has a `.uid` sidecar. 4.8: strings can no longer be comments; a script can no longer inherit its own inner classes.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Loader.** `TrackLoader` loads a `TrackPackage`, builds the `CollisionQuery` and hands out `CourseData`, applying the mirror at load when the race asks for it; the cached package is unchanged afterwards (ADR-0001 §7).
- [ ] **Stale and failed.** A stale package (`.glb` changed) is refused by `TrackLoader` with a named reason; a failing fixture imported headless writes no package and prints `TRACK_IMPORT RESULT FAIL` (ADR-0005 Validation Criteria).
- [ ] **One command.** `tools/track_build.sh <track>` runs the headless Blender export, then `--import`, prints one result line and exits non-zero on failure.

---

## Implementation Notes

- Staleness compares the package's `source_sha256` to the current `.glb`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 041: fresh-clone import in CI.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/pipeline/track_loader.gd` (new)
- `tools/track_build.sh` (new)
- `tests/integration/pipeline/track_loader_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/pipeline/track_loader_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-040/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-039-post-import-checks-i9-i16-and-bake.md`
- Unlocks: `production/epics/core-rebuild/story-041-fresh-clone-import-and-test-track.md`
