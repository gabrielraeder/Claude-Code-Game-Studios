# Story 003: TrackCollisionData and CollisionQuery ground casts

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: Track Collision AC-1, AC-4; ADR-0002 Validation Criteria (ground surface ids, `dispose()`)
**Roadmap step**: `architecture.md` Phase A Sequencing step 2-3 (spike follow-through; roadmap item 022 implements `CollisionQuery`, ADR-0002 Migration Plan). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0002: Collision Backend and Surface Attributes (Proposed)
**ADR Decision Summary**: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).

**ADR Version**: ADR-0002 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Jolt pinned and query built.** `project.godot` pins Jolt as the 3D physics engine; a `@tool` `TrackCollisionData` resource (ground triangles with a per-triangle surface-id table, wall triangles per wall attribute, `wall_attr_ids`, mover defs) builds a `CollisionQuery` that owns a private space with server-created shapes and bodies (ADR-0002 Summary).
- [ ] **Ground surface ids.** On a fixture ground with one triangle per registered kind, `cast_ground` straight down on each returns that kind's registered id, not its array index, for a registry with non-contiguous ids (Track Collision AC-1; ADR-0002 Validation Criteria).
- [ ] **Probe majority.** 4 probes on road, grass, grass, grass give the grass id; 2-2 and 1-1 ties resolve by the rule Track Collision C12 chooses, identically over 1000 repeats (Track Collision AC-4).
- [ ] **Dispose.** `dispose()` frees every RID in the fixed order (orphan check finds none) and is safe to call twice (ADR-0002 Validation Criteria).

---

## Implementation Notes

- Use only `PhysicsServer3D` with the 4.8 non-allocating `_into` query methods; result objects (`GroundHit`) are preallocated by the caller.
- Ground is one concave shape; the surface id is looked up from `face_index` in the baked table (about 4 bytes per triangle).
- Fixture meshes are built in code (no file I/O in unit tests).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 004: wall sweeps.
- Story 005: movers.
- Story 006: the face-index load check, boot asserts and mirror.
- Story 007: the benchmark.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `project.godot` (pin Jolt)
- `src/core/collision/track_collision_data.gd`, `src/core/collision/collision_query.gd`, `src/core/collision/ground_hit.gd` (new)
- `tests/unit/collision/collision_query_ground_test.gd`, `tests/unit/collision/collision_fixtures.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/collision/collision_query_ground_test.gd`, `tests/unit/collision/collision_fixtures.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-002-surface-and-wall-registries.md`
- Unlocks: `production/epics/core-rebuild/story-004-collision-query-walls.md`, `production/epics/core-rebuild/story-010-kart-body-ground-and-up.md`
