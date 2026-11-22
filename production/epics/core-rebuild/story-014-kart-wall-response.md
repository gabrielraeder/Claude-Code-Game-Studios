# Story 014: KartBody wall response: impact, scrape, rebound, turnback

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/kart-physics.md` (§8 Acceptance Criteria); `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: Kart Physics AC-2 to AC-5, AC-9; Track Collision AC-8, AC-9; ADR-0003 Validation Criteria (wall rebound, threshold `>=`, turnback)
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

- [ ] **Impact.** Cart at 20 m/s into a vertical wall at 90°, cooldown clear: `speed` 8.00 +/- 0.01, `wall_slide_time` 0.25 s, `wall_cooldown` 0.5 s, hard wall-hit event; Bike 6.00 +/- 0.01. At exactly `wall_impact_threshold_angle` it counts as an impact (`>=`) (Kart Physics AC-2; ADR-0003).
- [ ] **Scrape and cooldown.** Cart at 20 m/s at 25.0° -> 18.29 +/- 0.01 (impact); at 24.9° -> scrape × (1 - 0.8 × 0.45 × W / 60); a second 90° hit 0.4 s after the first -> scrape only, at 0.5 s -> impact; for 0.25 s after an impact the grip applied is <= 2.2 even when `intent.grip` = 9 (Kart Physics AC-3, AC-4, AC-5).
- [ ] **Wall attributes.** Rough (2.0) vs standard (1.0) wall, Cart at 26.0 m/s, 5° graze, 1 tick: 25.307 and 25.653 m/s +/- 0.001 (Track Collision AC-8).
- [ ] **Rebound and turnback.** 10 m/s into a standard wall with bounce 1.0 gives outgoing normal speed 4.0 (Cart) / 9.0 (Bike) +/- 0.01, bounce 0 removes it only; a kart scraping at 20° turns toward the tangent at no more than `turnback_rate × dt` per tick and is not wall-stuck after 1 s; until owner decisions P1/P2 land, the frozen rebound is asserted behind a flag (Kart Physics AC-9; Track Collision AC-9; ADR-0003).

---

## Implementation Notes

- Scrape drag and bounce come from `WallAttrSet` by `wall_attr` id (story 002).
- Owner decisions P1/P2 (bounce, turnback) may change the asserted numbers; keep them in data.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 013: the slide loop and push-out geometry.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/core/kart/kart_body.gd` (wall response)
- `tests/unit/kart/kart_body_wall_response_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/kart/kart_body_wall_response_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-013-kart-wall-slide-and-pushout.md`
- Unlocks: `production/epics/core-rebuild/story-015-kart-air-takeoff-landing-hop.md`, `production/epics/core-rebuild/story-022-kart-contact-local.md`
