# Story 021: KartBody moving platforms

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/kart-physics.md` (§8 Acceptance Criteria)
**Requirement**: Kart Physics AC-15, AC-16, AC-17; ADR-0003 Validation Criteria (platforms)
**Roadmap step**: `architecture.md` Phase A Sequencing step 3 (roadmap item 022: Kart Physics + Driving & Drift, checkpoint A1). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Accepted); ADR-0002: Collision Backend and Surface Attributes (Accepted)
**ADR Decision Summary**:
- ADR-0003: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.
- ADR-0002: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).

**ADR Version**: ADR-0003 2026-11-22; ADR-0002 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists. Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Leave and land back.** Leaving a moving platform and landing back on it with no input: speed relative to the platform unchanged within 1e-3 (no velocity double-counted) (Kart Physics AC-15).
- [ ] **Carried.** Parked on a platform rotating at 1 rad/s, 5 m from the axis: radius kept within 1 mm over 600 ticks and heading turns with the platform; on a translating platform, zero relative drift (Kart Physics AC-16).
- [ ] **Mover shove.** A mover moving into the kart sets `started_inside`, and the shove lands in `knock` (capped at 16 / 22), not in `velocity` (Kart Physics AC-17).

---

## Implementation Notes

- Platforms carry the kart by pose delta from `mover_pose` (story 005), not by velocity integration (ADR-0003 Summary).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 052: Castle movers re-authored.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/core/kart/kart_body.gd` (platform carry)
- `tests/unit/kart/kart_body_platform_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/kart/kart_body_platform_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-005-collision-movers.md`, `production/epics/core-rebuild/story-015-kart-air-takeoff-landing-hop.md`
- Unlocks: `production/epics/core-rebuild/story-024-kart-determinism-and-budget.md`
