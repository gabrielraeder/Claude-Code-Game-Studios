# Story 009: Core vehicle data fork, KartIntent and KartSnapshot

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/kart-physics.md` (§8 Acceptance Criteria); `design/gdd/driving-and-drift.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0003 Migration Plan order step 1; Driving & Drift AC-23
**Roadmap step**: `architecture.md` Phase A Sequencing step 3 (roadmap item 022: Kart Physics + Driving & Drift, checkpoint A1). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Proposed)
**ADR Decision Summary**: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.

**ADR Version**: ADR-0003 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Fork.** `assets/data/core/vehicles/armored_cart.tres` and the war-bike file equal the frozen `assets/data/vehicles/` files field by field for every existing field, and `bot_push_mult` is forked into `assets/data/core/kart_physics.tres`; the frozen files are untouched (ADR-0003 Migration Plan step 1).
- [ ] **Additive fields.** The new `VehicleStats` fields are added with defaults and `##` comments; the frozen game's golden traces still reproduce (ADR-0001 §9 additive rule).
- [ ] **Loader validation.** The loader rejects `drift_tier_times` that are not ascending and `drift_boost_times` with a count other than tiers + 1 (Driving & Drift AC-23).
- [ ] **Types.** `KartIntent` and `KartSnapshot` exist in `src/core/kart/` as preallocated RefCounted types with doc comments on every public field (snapshot: pose, speed, `surface_id`, event bits); no Dictionary fields.

---

## Implementation Notes

- Gameplay values are data-driven: every tuning number lives in the forked `.tres`, never in code.
- `KartSnapshot` is written by the body and read by `DriveState`; only the body mutates body state (ADR-0003 boundary).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 010: `KartBody` itself.
- Story 011: `DriveState`.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/data/vehicle_stats.gd` (additive fields)
- `src/core/kart/kart_intent.gd`, `src/core/kart/kart_snapshot.gd`, `src/core/kart/kart_physics_tuning.gd` (new)
- `assets/data/core/vehicles/armored_cart.tres`, `assets/data/core/vehicles/war_bike.tres`, `assets/data/core/kart_physics.tres` (new)
- `tests/unit/kart/vehicle_data_fork_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/kart/vehicle_data_fork_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-001-freeze-and-oracle.md`
- Unlocks: `production/epics/core-rebuild/story-010-kart-body-ground-and-up.md`, `production/epics/core-rebuild/story-011-drive-state-speed-and-surfaces.md`, `production/epics/core-rebuild/story-043-snapshot-codec-v10.md`
