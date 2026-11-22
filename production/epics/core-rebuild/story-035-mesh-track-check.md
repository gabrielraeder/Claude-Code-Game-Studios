# Story 035: Mesh track_check

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0004 Migration Plan step 1 (mesh `track_check` validations, §13); ADR-0003 Ordering Note (track_check enforces the §5 step-up rule); Course Data AC4, AC5; `architecture.md` Performance Budgets (Tools line)
**Roadmap step**: `architecture.md` Phase A Sequencing step 4 (roadmap item 023: Course Data + mesh `track_check`). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Proposed); ADR-0005: Blender Track Pipeline (Proposed); ADR-0003: Kart Physics Model (Proposed)
**ADR Decision Summary**:
- ADR-0004: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.
- ADR-0005: Editor-time import: a headless Blender exporter (`tools/blender/export_track.py`) writes one `.glb` with `kk_*` custom properties; a Godot `EditorScenePostImport` script (`import_script/path`, also run headless with `--import`) validates it (I1-I16) and bakes a binary `TrackPackage` (`.res`); any failed check refuses the file and names the reason. Runtime `GLTFDocument` is kept only as a future front end for user tracks.
- ADR-0003: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.

**ADR Version**: ADR-0004 2026-11-22; ADR-0005 2026-11-22; ADR-0003 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7). Open NVs closed in the pipeline stories: NV-1 (keep `art_src/.gdignore` as the real guard), NV-10, NV-15 (fresh-clone first import), NV-16 (verified; re-run). Every script the baker touches is `@tool` and loaded by `preload` path. Blender 5.3 on the platform layer.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Checks.** `tools/track_check_mesh.gd` runs the ADR-0004 §13 validations and the step-up rule (ground rising more than `max_step_up` = 0.5 m within one sample, or steeper than the slope limit, must be wall) on a baked track by sampling, not by re-running about 120,000 single-kart ticks; it prints PASS / WARN / FAIL / NOT_ASSESSED lines and exits non-zero on FAIL (ADR-0004; ADR-0003 §5; `architecture.md`).
- [ ] **Proposal lines.** WARN lines list fewer than 3 key groups besides group 0, and consecutive main gates more than 25 m apart or turning more than 45° (Course Data AC4, AC5).
- [ ] **Both tracks and a broken copy.** It passes on the generator-baked Castle Circuit and Dungeon Depths, and FAILs on a copy with a removed gate and on one with a 0.6 m ledge on a route; outputs are retained.
- [ ] **Regression.** `tools/regression.sh` gains one mesh `track_check` line per track.

---

## Implementation Notes

- Reuse the `CourseBuilder` check lines; `track_check` adds the drive-free sampled checks.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 039: the same step-up check as import check I16.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tools/track_check_mesh.gd` (new)
- `tools/regression.sh` (mesh track_check lines)
- `tests/integration/course/mesh_track_check_test.gd` (new)
- `production/qa/evidence/core-rebuild-story-035/` (outputs)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/course/mesh_track_check_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-035/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-034-generator-course-equivalence.md`
- Unlocks: `production/epics/core-rebuild/story-042-castle-blend-bootstrap.md`
