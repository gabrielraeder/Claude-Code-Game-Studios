# Story 018: DriveState hits, slowdown profiles and start boost

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/driving-and-drift.md` (§8 Acceptance Criteria)
**Requirement**: Driving & Drift AC-14 to AC-16
**Roadmap step**: `architecture.md` Phase A Sequencing step 3 (roadmap item 022: Kart Physics + Driving & Drift, checkpoint A1). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Accepted)
**ADR Decision Summary**: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.

**ADR Version**: ADR-0003 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Hit.** `hit()` during a tier-3 drift -> no boost paid, `boost_time` 0, no control for 1.1 s (Cart) / 1.25 s (Bike) +/- 1 tick; a second `hit()` during the spin returns false (Driving & Drift AC-14).
- [ ] **Slowdown profile.** Cart, slowdown profile 2 from 26 m/s -> speed never below 7.235 m/s, and the profile ends after 0.6 s (Driving & Drift AC-15).
- [ ] **Start.** Start level 3 -> `boost_time` 2.0 s; stall -> throttle ignored for 1.0 s +/- 1 tick with steer still working; level 4 -> ignored (Driving & Drift AC-16).

---

## Implementation Notes

- Port the start and slowdown functions as reference only; `HitSlowdownProfile` is shared data in `src/data/`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 053: which items call `hit()`.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/gameplay/driving/drive_state.gd` (hit, slowdown, start)
- `tests/unit/driving/drive_hits_start_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/driving/drive_hits_start_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-017-drive-drift-end-and-merge.md`
- Unlocks: `production/epics/core-rebuild/story-019-drive-trick-and-pads.md`
