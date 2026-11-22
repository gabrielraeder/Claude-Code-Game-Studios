# Story 019: DriveState trick boost and pads

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0003 is Proposed (owner acceptance pending)
> **Layer**: Feature
> **Type**: Logic
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/driving-and-drift.md` (§8 Acceptance Criteria)
**Requirement**: Driving & Drift AC-17, AC-18; ADR-0003 Validation Criteria (trick boost via step 13 copy; frozen `kart_sim.gd:916`, `:931`)
**Roadmap step**: `architecture.md` Phase A Sequencing step 3 (roadmap item 022: Kart Physics + Driving & Drift, checkpoint A1). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Proposed)
**ADR Decision Summary**: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.

**ADR Version**: ADR-0003 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Trick window.** Drift pressed 0.30 s before takeoff with airtime 0.25 s -> 0.7 s boost on landing; pressed 0.32 s before, or airtime 0.24 s -> no boost (Driving & Drift AC-17).
- [ ] **Paid once.** A takeoff within `trick_window` of the hop press, then a landing with airtime >= `trick_min_airtime`, pays `trick_boost_time` exactly once, with the events arriving through the step 13 copy into `DriveState`; a hop-only flight pays nothing (ADR-0003 Validation Criteria).
- [ ] **Pads.** Pad input on 3 consecutive ticks -> `boost_time` refreshed each tick and `pad_boosted` emitted once (Driving & Drift AC-18).

---

## Implementation Notes

- Frozen reference: `kart_sim.gd:916` sets `_trick_pending`, `:931` pays it in `_land`.
- Pads are a surface kind (`boost_pad`), read by id.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 052: pads and ramps placed on Castle.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/gameplay/driving/drive_state.gd` (trick, pads)
- `tests/unit/driving/drive_trick_pads_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/driving/drive_trick_pads_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-015-kart-air-takeoff-landing-hop.md`, `production/epics/core-rebuild/story-018-drive-hits-slowdown-start.md`
- Unlocks: `production/epics/core-rebuild/story-020-drive-surface-transitions-and-boundary.md`
