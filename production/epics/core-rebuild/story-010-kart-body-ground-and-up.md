# Story 010: KartBody ground, ride spring and up

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/kart-physics.md` (§8 Acceptance Criteria)
**Requirement**: Kart Physics AC-1, AC-10, AC-12, AC-13; ADR-0003 Validation Criteria (antiparallel up guard, 30° bank)
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

- [ ] **Integration and slope.** On flat ground, `speed` after the step equals `intent.target_speed` exactly; on a 10° uphill it equals `target_speed - 0.00434` m/s +/- 1e-5 per tick, Cart and Bike (Kart Physics AC-1).
- [ ] **Ride spring.** A 0.2 m step down at rest: `ride_offset` is within 0.004 m of 0 by 0.25 s, never below 0 and never above 0.3 (Kart Physics AC-10).
- [ ] **Up guard.** A target exactly opposite to up produces no NaN and an orthonormal basis (Kart Physics AC-12).
- [ ] **Bank.** On a 30° bank, the first tick moves up 6.25° +/- 0.05° toward the normal; after settling `basis.y` equals the smoothed normal within 1e-4, and `basis` is orthonormal within 1e-5 after 36,000 ticks (Kart Physics AC-13).

---

## Implementation Notes

> **Note from story 003 review (LP):** treat `GroundHit.surface_id == CollisionQuery.SURFACE_NONE` (-1) as a miss or assert on it; never read a `GroundHit` after `cast_ground` returned false (it is left untouched). Pass unit `dir` vectors. Do not call `owned_rids()` per tick.

- Step order per ADR-0003: slide loop (story 013), then 2 to 4 ground rays, one damped ride spring, up from the smoothed normal; this story implements the ground half with a stub wall phase.
- Per-body gravity vector; no `Vector3.DOWN`, `randf`, `randi` or `delta` in `src/core/kart/` (ADR-0003 grep).
- Rebuild the `Basis` from up and heading each tick; the probe showed it stays orthonormal without `orthonormalized()`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 013-014: walls.
- Story 015: air.
- Story 021: platforms.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/core/kart/kart_body.gd` (new)
- `tests/unit/kart/kart_body_ground_test.gd`, `tests/unit/kart/kart_fixtures.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/kart/kart_body_ground_test.gd`, `tests/unit/kart/kart_fixtures.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-003-collision-query-ground.md`, `production/epics/core-rebuild/story-009-core-vehicle-data-and-kart-types.md`
- Unlocks: `production/epics/core-rebuild/story-012-first-slice-budget.md`
