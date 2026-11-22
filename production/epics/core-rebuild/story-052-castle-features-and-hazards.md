# Story 052: Castle: track features and hazards

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: Track Collision AC-16; ADR-0002 (movers); `architecture.md` Performance Budgets (hazards and movers 0.1 ms)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025: Castle Circuit rebuilt). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0002: Collision Backend and Surface Attributes (Proposed); ADR-0004: Course Data Format (Proposed)
**ADR Decision Summary**:
- ADR-0002: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).
- ADR-0004: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0002 2026-11-22; ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`. The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Hazards re-authored.** Each frozen Castle Circuit hazard re-authored on the mover model passes the Track Collision §4.5 checks with its shipped numbers where they apply (barrels 9.070 <= 10, cart 9.496 <= 14, drawbridge and portcullis never blocked together) (Track Collision AC-16).
- [ ] **Features.** Boost pads and trick ramps come from surface kinds and pay through `DriveState` on track; area triggers from `CourseData.areas` fire once per entry.
- [ ] **Synced time.** Hazards are evaluated with `mover_pose(t)` on synced race time, and presentation draws the same pose at the same `t` (Track Collision AC-15).
- [ ] **Budget.** Hazards and movers (effects) <= 0.1 ms p95 per tick, 12 karts (`architecture.md` Performance Budgets).

---

## Implementation Notes

- The hazard's collision cost is counted in the collision row, not here (`architecture.md`).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 062: Dungeon hazards.
- Story 059: hazard visuals and audio.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/gameplay/hazards/hazard_manager.gd`, `src/gameplay/features/track_features.gd` (new)
- `art_src/tracks/castle_circuit/castle_circuit.blend` (movers)
- `tests/integration/hazards/castle_hazards_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/hazards/castle_hazards_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-052/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-050-castle-race-clock-registry-tick.md`
- Unlocks: `production/epics/core-rebuild/story-055-castle-bot-race-and-budget.md`
