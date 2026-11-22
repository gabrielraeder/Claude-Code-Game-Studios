# Story 011: DriveState speed, cap and floor surfaces

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/driving-and-drift.md` (§8 Acceptance Criteria)
**Requirement**: Driving & Drift AC-1 to AC-5; ADR-0003 Migration Plan (`_update_speed` without slope gravity, `_update_surface`)
**Roadmap step**: `architecture.md` Phase A Sequencing step 3 (roadmap item 022: Kart Physics + Driving & Drift, checkpoint A1). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Proposed)
**ADR Decision Summary**: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.

**ADR Version**: ADR-0003 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Acceleration.** Cart, full throttle on road from 0: target speed reaches 26.0 m/s at 1.857 s +/- 1 tick and never exceeds 26.0; Bike reaches 24.96 m/s at 1.371 s +/- 1 tick (Driving & Drift AC-1).
- [ ] **Boost cap and decay.** With `boost_time > 0`, target speed never exceeds 35.1 (Cart) / 33.696 (Bike) m/s and reaches 35.1 from 26.0 in 0.217 s +/- 1 tick with throttle 0; from 35.1 with no boost the Cart returns to 26.0 in 0.506 s +/- 1 tick, monotonically (Driving & Drift AC-2, AC-3).
- [ ] **Floor surfaces.** Cart on grass at full throttle settles at 14.158 +/- 0.01 m/s, on mud at 10.211 +/- 0.01 m/s, with the surface looked up in `SurfaceSet` by `snapshot.surface_id` (Driving & Drift AC-4).
- [ ] **No slope gravity.** On a stub snapshot with a 10° slope, `drive()`'s `target_speed` equals the flat-ground output (Driving & Drift AC-5).

---

## Implementation Notes

- `DriveState.drive()` re-implements the frozen control law in `src/gameplay/driving/`, re-typed against `KartSnapshot` / `KartIntent`; nothing is imported from `src/legacy/` (read `kart_sim.gd` as reference only).
- No numeric tuning literal other than 0/1/-1 in `drive()` (Driving & Drift AC-21).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 016-019: drift, boosts, hits, start, trick, pads.
- Story 020: slick tail, rubble, greps.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/gameplay/driving/drive_state.gd` (new)
- `tests/unit/driving/drive_speed_test.gd`, `tests/unit/driving/driving_fixtures.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/driving/drive_speed_test.gd`, `tests/unit/driving/driving_fixtures.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-009-core-vehicle-data-and-kart-types.md`
- Unlocks: `production/epics/core-rebuild/story-012-first-slice-budget.md`, `production/epics/core-rebuild/story-016-drive-drift-tiers.md`
