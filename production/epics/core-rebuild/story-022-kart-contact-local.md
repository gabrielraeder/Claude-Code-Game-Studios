# Story 022: Kart contact solver: local pairs and broadphase

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0003 is Proposed (owner acceptance pending)
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/kart-physics.md` (§8 Acceptance Criteria)
**Requirement**: Kart Physics AC-18 to AC-21, AC-25; ADR-0003 Validation Criteria (pair restitution, both-local pairs, broadphase)
**Roadmap step**: `architecture.md` Phase A Sequencing step 3 (roadmap item 022: Kart Physics + Driving & Drift, checkpoint A1). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Proposed)
**ADR Decision Summary**: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.

**ADR Version**: ADR-0003 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Head-on.** Two local Carts head-on at 20 m/s each: knock magnitude 16.0 each (capped), speed × 0.90 (Kart Physics AC-18).
- [ ] **Mixed pair.** Cart vs Bike side contact closing at 8 m/s, both local: Cart speed × 0.92, Bike × 0.68; Cart takes 0.318 and Bike 0.682 of the separation in `pending_push`; no `position` write during contact; the pair is resolved once, each kart's knock uses its own `bump_restitution`, the vertical gate uses the smaller `bump_max_height_diff` (Kart Physics AC-19; ADR-0003).
- [ ] **Weights and vertical gate.** Human Cart vs bot Cart: the human takes 0.259 of the separation (`bot_push_mult`); bot vs bot 0.5; karts 1.19 m apart along up touch, 1.21 m apart never touch (Kart Physics AC-20, AC-21).
- [ ] **Broadphase.** The window is 4.7 m with a Cart in the race, and it finds the same pairs as brute force over a 12-kart race (zero misses) (Kart Physics AC-25).

---

## Implementation Notes

- `KartContactSolver` re-implements `_resolve_kart_contacts`, `_push_of`, `resolve_kart_contact` and `_take_bump` as ADR-0003 §7 changes them; reference only.
- Broadphase key is course distance; until Course Data exists, tests supply distances from the fixture.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 023: remote karts, events, merge, freeze.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/core/kart/kart_contact_solver.gd` (new)
- `tests/unit/kart/kart_contact_local_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/kart/kart_contact_local_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-014-kart-wall-response.md`
- Unlocks: `production/epics/core-rebuild/story-023-kart-contact-remote-and-events.md`
