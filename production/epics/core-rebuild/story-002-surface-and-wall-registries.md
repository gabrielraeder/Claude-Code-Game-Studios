# Story 002: Core surface and wall-attribute registries

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: Track Collision AC-2, AC-3, AC-6 (registry half); ADR-0002 Decision (surface and wall-attribute ids, v5.1 core surface ids, `SurfaceType.neutral`, no wall `opening` field)
**Roadmap step**: `architecture.md` Phase A Sequencing step 2-3 (spike follow-through; roadmap item 022 implements `CollisionQuery`, ADR-0002 Migration Plan). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0002: Collision Backend and Surface Attributes (Proposed)
**ADR Decision Summary**: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).

**ADR Version**: ADR-0002 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Core SurfaceSet.** `assets/data/core/surface_set.tres` has `road` at id 0, every id unique and >= 0, and contains `boost_pad` and `trick_ramp`; the loader rejects a set with a duplicate id (Track Collision AC-2).
- [ ] **Frozen kinds unchanged.** The six frozen kinds in the core `SurfaceSet` carry exactly the handling values of Track Collision GDD §3.2.2, checked field by field against `assets/data/surfaces/surface_set.tres` (Track Collision AC-3).
- [ ] **Wall attributes.** `WallAttr` / `WallAttrSet` (new core classes in `src/core/collision/`, not `src/data/`) give stable, unique, append-only ids with scrape drag and bounce fields and no `opening` field; `wall_<name>` maps by name and an unknown name is reported as not found; the loader rejects a duplicate id; the core instance `assets/data/core/wall_attr_set.tres` holds `standard` (scrape drag 1.0) and `rough` (2.0) (ADR-0002 Decision; Track Collision AC-8 values).
- [ ] **Additive shared-data change.** `SurfaceType.neutral` is added with a default, and `src/data/surface_set.gd`, `surface_type.gd` and the wall-attribute set are marked `@tool` (ADR-0005 NV-7, additive per ADR-0001 §9); `tools/regression.sh` still passes and the golden traces reproduce.

---

## Implementation Notes

- Id policy for both registries: unique, >= 0, append-only, a removed id is never reused (ADR-0002 Decision). Floor effects (drag, grip, caps) stay in `SurfaceSet` and are read by Driving by id; `GroundHit` carries no floor drag.
- An opening is the absence of wall geometry; Course Data derives `WALL_OPENING` / `OPEN_EDGE` from its own lateral sweeps (ADR-0004).
- Changes to `src/data/` are additive only; the frozen game must not change behaviour (re-run `tools/regression.sh`).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 003: `TrackCollisionData`, `CollisionQuery` and ground casts.
- Story 004: wall sweeps returning `wall_attr`.
- Story 014: using scrape drag and bounce in the wall response.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/data/surface_set.gd`, `src/data/surface_type.gd` (additive)
- `src/core/collision/wall_attr.gd`, `src/core/collision/wall_attr_set.gd` (new)
- `assets/data/core/surface_set.tres`, `assets/data/core/wall_attr_set.tres` (new)
- `tests/unit/collision/surface_and_wall_registries_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/collision/surface_and_wall_registries_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-001-freeze-and-oracle.md`
- Unlocks: `production/epics/core-rebuild/story-003-collision-query-ground.md`
