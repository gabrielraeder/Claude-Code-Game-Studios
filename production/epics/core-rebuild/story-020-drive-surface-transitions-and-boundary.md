# Story 020: DriveState surface transitions, rubble, determinism and boundary

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/driving-and-drift.md` (§8 Acceptance Criteria)
**Requirement**: Driving & Drift AC-19 to AC-22 (TD-004)
**Roadmap step**: `architecture.md` Phase A Sequencing step 3 (roadmap item 022: Kart Physics + Driving & Drift, checkpoint A1). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Proposed)
**ADR Decision Summary**: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.

**ADR Version**: ADR-0003 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Slick tail.** Slick -> road: slick grip in force for 0.6 s +/- 1 tick, then road; slick -> grass: grass on the next tick; slick then respawn: no tail; slick -> `boost_pad`: the tail keeps counting (Driving & Drift AC-19).
- [ ] **Rubble.** At 15.6 m/s the added yaw is a sine of amplitude 1.1 rad/s whose phase advances with distance; two runs give bit-identical yaw sequences (Driving & Drift AC-20).
- [ ] **Boundary grep.** `tools/core_greps.sh` finds no `CollisionQuery`, `KartBody` mutation or `src/legacy` reference in `src/gameplay/driving/`, and no numeric tuning literal other than 0/1/-1 in `drive()` (Driving & Drift AC-21).
- [ ] **Determinism.** Two runs of the same input sequence produce bit-identical `KartIntent` streams (Driving & Drift AC-22).

---

## Implementation Notes

- Rubble phase uses distance, not time or a random stream.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 024: whole-body determinism.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/gameplay/driving/drive_state.gd` (surface transitions)
- `tools/core_greps.sh` (driving rules)
- `tests/unit/driving/drive_surfaces_determinism_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/driving/drive_surfaces_determinism_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-019-drive-trick-and-pads.md`
- Unlocks: `production/epics/core-rebuild/story-024-kart-determinism-and-budget.md`
