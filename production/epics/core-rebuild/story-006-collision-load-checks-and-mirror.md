# Story 006: Collision load checks, mirror and boundary greps

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0002 is Proposed (owner acceptance pending)
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: Track Collision AC-17, AC-18; ADR-0002 Validation Criteria (mirror, face-index load check, Dictionary grep); ADR-0001 §7 (mirror is a reflection at track load)
**Roadmap step**: `architecture.md` Phase A Sequencing step 2-3 (spike follow-through; roadmap item 022 implements `CollisionQuery`, ADR-0002 Migration Plan). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0002: Collision Backend and Surface Attributes (Proposed); ADR-0001: Simulation Conventions and Code Layout (Accepted)
**ADR Decision Summary**:
- ADR-0002: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).
- ADR-0001: Godot Y-up, -Z forward, metres; the synced race time is authoritative and the 60 Hz tick follows it with a defined catch-up policy; a fixed step order and one seeded random stream per consumer; our own interpolation with a teleport flag; mirror mode is a proper reflection at track load; the frozen 2.5D game lives in `src/legacy/`, shared data classes in `src/data/`, new code in new folders.

**ADR Version**: ADR-0002 2026-11-22; ADR-0001 2026-11-21

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`. Tick settings are pinned (`physics_ticks_per_second=60`, `max_physics_steps_per_frame=8`, `physics_interpolation=false`). Since 4.4 every script has a `.uid` sidecar. 4.8: strings can no longer be comments; a script can no longer inherit its own inner classes.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Face-index load check.** Building a query fails with a named reason when the face-index setting is off; the test sets the setting, awaits a frame, builds a new query, then restores the setting (Track Collision AC-18; ADR-0002 Validation Criteria).
- [ ] **Mirror.** A mirrored fixture returns mirrored hit points (x -> -x) with the same surface and wall-attr ids, and `mirrored()` leaves the source resource unchanged (compared before and after) (Track Collision AC-17; ADR-0001 §7).
- [ ] **Boot asserts.** Loading refuses, with a named reason, a `TrackCollisionData` whose surface or wall-attr id is not in the core registries, and a project whose physics engine or tick settings differ from ADR-0001 §5 / ADR-0002.
- [ ] **Grep.** `tools/core_greps.sh` (new, prints one PASS/FAIL line per rule, exits non-zero on a failure) finds no Dictionary query forms in per-tick code under `src/core/` and `src/gameplay/` (ADR-0002 Validation Criteria), and is wired into `tools/regression.sh`.

---

## Implementation Notes

- Mirror is applied once at track load, never per query (ADR-0001 §7).
- Later stories append their boundary greps to `tools/core_greps.sh`; it emits observations per rule, not a verdict on the story (CLAUDE.md helper-script rule).
- Follow `.claude/rules/godot-refcount.md` for any new `connect(`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 040: mirror applied by `TrackLoader` at package load.
- Story 028: Course Data's mirror.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/core/collision/collision_query.gd` (load check), `src/core/collision/track_collision_data.gd` (`mirrored()`), `src/core/collision/collision_boot_check.gd` (new)
- `tools/core_greps.sh` (new), `tools/regression.sh` (add the grep line)
- `tests/unit/collision/collision_load_and_mirror_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/collision/collision_load_and_mirror_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-005-collision-movers.md`
- Unlocks: `production/epics/core-rebuild/story-007-collision-benchmark.md`, `production/epics/core-rebuild/story-008-legacy-extractor-and-test-mesh.md`, `production/epics/core-rebuild/story-028-course-data-schema-and-mirror.md`
