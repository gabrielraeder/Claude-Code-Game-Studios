# Story 005: Analytic moving colliders

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0002 is Proposed (owner acceptance pending)
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: Track Collision AC-12 to AC-15; ADR-0002 Validation Criteria (rotating mover point velocity, mover blocks or clears at t); ADR-0002 v5.1 `MoverDef.solid`
**Roadmap step**: `architecture.md` Phase A Sequencing step 2-3 (spike follow-through; roadmap item 022 implements `CollisionQuery`, ADR-0002 Migration Plan). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0002: Collision Backend and Surface Attributes (Proposed)
**ADR Decision Summary**: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).

**ADR Version**: ADR-0002 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Pose curve.** A box mover keyed 0 -> 10 m along +X over 2 s: `mover_pose(id, 1.0)` origin x = 5.0 +/- 1e-4, and `mover_pose(id, period + 1.0)` equals `mover_pose(id, 1.0)`; a mover blocks or clears at time t as its curve says (Track Collision AC-12; ADR-0002 Validation Criteria).
- [ ] **Point velocity.** A mover rotating 90° about +Y in 1 s: `mover_point_velocity` at 2 m from the axis has magnitude π/2 × 2 = 3.1416 +/- 0.001 m/s, and a sweep hit on it reports that velocity at the contact (Track Collision AC-13).
- [ ] **Mover overlap.** A mover that moves into a stationary kart's sphere sets `started_inside`; with a static wall and a mover both overlapping, the deeper one wins; a mover with `solid = false` never blocks (Track Collision AC-14; ADR-0002 v5/v5.1).
- [ ] **One evaluator.** Simulation and presentation calls at the same `t` return bit-identical poses; grep finds no pose interpolation of `key_pos` outside `src/core/collision/` (Track Collision AC-15).

---

## Implementation Notes

- Movers are evaluated analytically from keyframed pose curves; no physics body is stepped (ADR-0002 Summary).
- Time comes from the caller (synced race time per ADR-0001 §5); never read a clock inside the query.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 021: carrying a kart on a platform.
- Story 052: re-authoring the Castle hazards on movers.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/core/collision/mover_def.gd` (new), `src/core/collision/collision_query.gd` (mover_pose, mover_point_velocity)
- `tests/unit/collision/collision_movers_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/collision/collision_movers_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-004-collision-query-walls.md`
- Unlocks: `production/epics/core-rebuild/story-006-collision-load-checks-and-mirror.md`, `production/epics/core-rebuild/story-021-kart-moving-platforms.md`
