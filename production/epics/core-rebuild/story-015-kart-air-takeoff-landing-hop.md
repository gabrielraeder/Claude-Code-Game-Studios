# Story 015: KartBody air: takeoff, landing and hop

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/kart-physics.md` (§8 Acceptance Criteria); `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: Kart Physics AC-11, AC-14; Track Collision AC-5; ADR-0003 Validation Criteria (ramp lip, hop with `hop_speed > 0`)
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

- [ ] **Takeoff threshold and landing.** A 0.46 m drop in one tick gives a took-off event, a 0.44 m drop does not; launched with 5 m/s along up onto level ground, the kart lands after 0.50 s +/- 1 tick with impact 5.0 +/- 0.2 m/s and `airtime` reported, and `speed` after landing = velocity · heading (Kart Physics AC-11).
- [ ] **Ramp lip.** A ramp lip at 26 m/s takes off, and the landing reports airtime and impact (Kart Physics AC-14).
- [ ] **Hop.** With `hop_speed > 0` (test fixture only), a hop is an explicit takeoff on the same tick, the ride clamp is bypassed for that tick, `EV_TOOK_OFF` and `EV_HOP_AIRBORNE` are set and `hop_airborne` at landing (ADR-0003 Validation Criteria).
- [ ] **Surface in the air.** An airborne kart keeps its last surface id; landing on mud switches to mud on that tick (Track Collision AC-5).

---

## Implementation Notes

- Event bits are written into the snapshot and copied into `DriveState` at step 13 (ADR-0003 v4); the trick boost that reads them is story 019.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 019: trick boost payout.
- Story 021: landing back on a moving platform.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/core/kart/kart_body.gd` (air)
- `tests/unit/kart/kart_body_air_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/kart/kart_body_air_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-014-kart-wall-response.md`
- Unlocks: `production/epics/core-rebuild/story-019-drive-trick-and-pads.md`, `production/epics/core-rebuild/story-021-kart-moving-platforms.md`
