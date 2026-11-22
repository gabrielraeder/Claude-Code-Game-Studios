# Story 016: DriveState drift start, charge, tiers and release

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/driving-and-drift.md` (§8 Acceptance Criteria)
**Requirement**: Driving & Drift AC-6 to AC-9
**Roadmap step**: `architecture.md` Phase A Sequencing step 3 (roadmap item 022: Kart Physics + Driving & Drift, checkpoint A1). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Accepted)
**ADR Decision Summary**: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.

**ADR Version**: ADR-0003 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Start gate.** With the drift button held: speed 12.0 or steer 0.30 -> no drift; speed 12.01 and steer 0.31 -> drift starts and emits `drift_started(+1)` (Driving & Drift AC-6).
- [ ] **Tier timing.** Cart, neutral steer: tier 1 at 0.9 s, tier 2 at 1.9 s, tier 3 at 3.0 s; Cart fully in: 0.5625 / 1.1875 / 1.875 s; Bike fully in: 0.368 / 0.789 / 1.263 s; each +/- 1 tick (Driving & Drift AC-7).
- [ ] **Release.** Release at tier 1 / 2 / 3 -> `boost_time` 0.7 / 1.1 / 1.6 s and `drift_ended(t, s)` with those values; at tier 0 -> `drift_ended(0, 0.0)` and `boost_time` unchanged (Driving & Drift AC-8).
- [ ] **Drift yaw.** At steer = -dir, 0, +dir: Cart 0.40 / 1.25 / 2.10, Bike 0.65 / 1.60 / 2.55 rad/s (× `drift_dir`), never the opposite sign (Driving & Drift AC-9).

---

## Implementation Notes

- Port the drift block and steering curve from the frozen `tick()` as reference only; values from the forked vehicle data.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 017: drift end conditions, air drift and boost merge.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/gameplay/driving/drive_state.gd` (drift)
- `tests/unit/driving/drive_drift_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/driving/drive_drift_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-011-drive-state-speed-and-surfaces.md`
- Unlocks: `production/epics/core-rebuild/story-017-drive-drift-end-and-merge.md`
