# Story 004: CollisionQuery wall sweeps

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: Track Collision AC-6, AC-7, AC-10, AC-11; ADR-0002 Validation Criteria (wall attribute mapping, `started_inside`); ADR-0002 v5 amendment
**Roadmap step**: `architecture.md` Phase A Sequencing step 2-3 (spike follow-through; roadmap item 022 implements `CollisionQuery`, ADR-0002 Migration Plan). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0002: Collision Backend and Surface Attributes (Proposed)
**ADR Decision Summary**: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).

**ADR Version**: ADR-0002 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Wall attribute id.** A wall triangle with material `wall_rough` mapped to a non-contiguous id: `sweep_walls` returns `wall_attr` = that id, via `wall_attr_ids[collider_shape]` (Track Collision AC-6; ADR-0002 Validation Criteria).
- [ ] **One-sided walls.** A sphere swept at a wall from its back face passes through; from its front it hits (Track Collision AC-7).
- [ ] **Touch.** A move ending flush against a wall returns `fraction = 1.0` and `started_inside = false` (Track Collision AC-10).
- [ ] **Started inside.** A sweep starting inside a wall returns `started_inside = true`, `fraction = 0`, runs no cast, and fills point, normal, `wall_attr` and `collider_id` from the overlap (Track Collision AC-11; ADR-0002 v5 amendment).

---

## Implementation Notes

- Walls are one body with one shape per wall attribute, on their own layer; the wall sweep never sees ground triangles.
- ADR-0002 v5 contract: when `started_inside` is set (by the rest check at `from` or an analytic mover overlap), `sweep_walls` returns true at once; when a static wall and a mover both overlap, the deeper one wins (the mover half is tested in story 005).
- Up to 3 sweeps per kart per tick are budgeted inside collision's 0.3 ms (ADR-0002 Performance Implications).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 005: mover overlaps and point velocity.
- Story 013: the kart slide loop and push-out that consume these hits.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/core/collision/collision_query.gd` (sweep_walls), `src/core/collision/wall_hit.gd` (new)
- `tests/unit/collision/collision_query_walls_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/collision/collision_query_walls_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-003-collision-query-ground.md`
- Unlocks: `production/epics/core-rebuild/story-005-collision-movers.md`
