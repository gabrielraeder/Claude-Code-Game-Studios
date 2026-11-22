# Story 065: Retire the frozen 2.5D modules (owner-approved deletion)

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: owner deletion approval pending (ADRs accepted and ADR-0001 §9 amendment approved 2026-11-22)
> **Layer**: Foundation
> **Type**: Integration
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none (`architecture.md` Rebuild Strategy: retire, don't delete until approved)
**Requirement**: `architecture.md` Phase A Sequencing step 7 (old 2.5D modules retired, owner-approved); ADR-0004 §15 (legacy tools retired at A3)
**Roadmap step**: `architecture.md` Phase A Sequencing step 7 (Dungeon Depths rebuilt; composition root switch; old modules retired, owner-approved; checkpoint A3). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0001: Simulation Conventions and Code Layout (Accepted); ADR-0004: Course Data Format (Accepted)
**ADR Decision Summary**:
- ADR-0001: Godot Y-up, -Z forward, metres; the synced race time is authoritative and the 60 Hz tick follows it with a defined catch-up policy; a fixed step order and one seeded random stream per consumer; our own interpolation with a teleport flag; mirror mode is a proper reflection at track load; the frozen 2.5D game lives in `src/legacy/`, shared data classes in `src/data/`, new code in new folders.
- ADR-0004: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0001 2026-11-21; ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Tick settings are pinned (`physics_ticks_per_second=60`, `max_physics_steps_per_frame=8`, `physics_interpolation=false`). Since 4.4 every script has a `.uid` sidecar. 4.8: strings can no longer be comments; a script can no longer inherit its own inner classes. The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Approval first.** The owner's deletion approval (date, scope) is recorded in `production/qa/evidence/core-rebuild-story-065-evidence.md` before any file is deleted.
- [ ] **Removed.** `src/legacy/`, `tools/legacy_track_export.gd`, `tools/legacy_test_bake.gd`, `tools/blender/legacy_to_blend.py`, the frozen-kart parity adapter and the frozen-oracle lines of `tools/regression.sh` are deleted; `src/data/` classes used only by the frozen game are listed for an owner decision, not deleted here (ADR-0004 §15).
- [ ] **Clean load.** The project loads with no uid warnings and no missing-resource errors, `tools/regression.sh` (new core) passes, and the golden traces and evidence stay in `production/qa/evidence/`; the `v0.11-2.5d` tag still reaches the frozen game.

---

## Implementation Notes

- Never delete before the owner's approval is on record; a skipped question is not an answer.

### Retire at A3

Tools that run or read the frozen game under the ADR-0001 section 9 amendment (2026-11-22); delete them, their output folder and their `tools/core_greps.sh` rule together with `src/legacy/`:

- `tools/legacy_track_export.gd` (story 008): the extractor; output `build/legacy_tracks/` (gitignored).
- `tools/legacy_test_bake.gd` (story 008): JSON to `TrackCollisionData` test builder.
- `tools/spline_mesh_equivalence.gd` (story 008): the spline-vs-mesh equivalence run.
- `tools/legacy_bake_tri_dump.gd` (story 008): triangle dump of the baked test mesh around a point (debug).
- `tests/integration/collision/generator_bake_test.gd` (story 008): the bake's fixture test (it preloads the bake).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Phase B work (roadmap 021 room codes, 027 Blender asset pipeline).

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/legacy/**` (deleted)
- `tools/legacy_track_export.gd`, `tools/legacy_test_bake.gd`, `tools/blender/legacy_to_blend.py`, `tools/parity/frozen_kart_adapter.gd` (deleted)
- `tools/regression.sh`
- `production/qa/evidence/core-rebuild-story-065-evidence.md`

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: the integration run named in the criteria; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-065/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-064-checkpoint-a3-signoff.md`
- Unlocks: None
