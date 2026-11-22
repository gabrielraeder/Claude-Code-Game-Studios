# Story 017: DriveState drift end conditions, air drift and boost merge

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0003 is Proposed (owner acceptance pending)
> **Layer**: Feature
> **Type**: Logic
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/driving-and-drift.md` (§8 Acceptance Criteria)
**Requirement**: Driving & Drift AC-10 to AC-13
**Roadmap step**: `architecture.md` Phase A Sequencing step 3 (roadmap item 022: Kart Physics + Driving & Drift, checkpoint A1). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Proposed)
**ADR Decision Summary**: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.

**ADR Version**: ADR-0003 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Speed end.** Drift at tier 2 with speed set to 8.39 -> drift ends and pays 1.1 s (Driving & Drift AC-10).
- [ ] **Surface end.** Drift onto mud -> drift ends with no boost and `surface_drift_ends` = 1 (Driving & Drift AC-11).
- [ ] **Air drift.** Drift held with `grounded = false` keeps charging and outputs the air yaw rate, not the drift yaw (Driving & Drift AC-12).
- [ ] **Max-merge.** `boost_time` 1.2 then a tier-3 release -> 1.6, not 2.8 (Driving & Drift AC-13).

---

## Implementation Notes

- Port `_end_drift` as reference only.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 018: hits during drift.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/gameplay/driving/drive_state.gd` (drift end)
- `tests/unit/driving/drive_drift_end_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/driving/drive_drift_end_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-016-drive-drift-tiers.md`
- Unlocks: `production/epics/core-rebuild/story-018-drive-hits-slowdown-start.md`
