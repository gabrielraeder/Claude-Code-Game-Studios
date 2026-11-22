# Story 050: Castle: race clock, kart registry and tick order

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0003 and ADR-0004 are Proposed (owner acceptance pending)
> **Layer**: Core
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/kart-physics.md` (§8 Acceptance Criteria); `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0001 Validation Criteria (determinism, 0.5 s hitch); ADR-0003 v4 tick order; ADR-0004 Migration Plan step 3
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025: Castle Circuit rebuilt). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0001: Simulation Conventions and Code Layout (Accepted); ADR-0003: Kart Physics Model (Proposed); ADR-0004: Course Data Format (Proposed)
**ADR Decision Summary**:
- ADR-0001: Godot Y-up, -Z forward, metres; the synced race time is authoritative and the 60 Hz tick follows it with a defined catch-up policy; a fixed step order and one seeded random stream per consumer; our own interpolation with a teleport flag; mirror mode is a proper reflection at track load; the frozen 2.5D game lives in `src/legacy/`, shared data classes in `src/data/`, new code in new folders.
- ADR-0003: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.
- ADR-0004: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0001 2026-11-21; ADR-0003 2026-11-22; ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Tick settings are pinned (`physics_ticks_per_second=60`, `max_physics_steps_per_frame=8`, `physics_interpolation=false`). Since 4.4 every script has a `.uid` sidecar. 4.8: strings can no longer be comments; a script can no longer inherit its own inner classes. Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Tick order.** A new composition root (not yet `run/main_scene`) runs a 12-kart race on the Castle Circuit package built by story 042 in the ADR-0003 v4 order: inbox events -> snapshot -> `drive()` -> `step()` -> snapshot -> `progress` -> remote sample -> contact -> end-of-tick snapshot -> send.
- [ ] **Clock.** `RaceClock` makes the synced race time authoritative and the 60 Hz tick follows it with the ADR-0001 §5 catch-up policy; with an artificial 0.5 s hitch the race clock and hazards stay on synced time and the own kart resyncs with the teleport flag (ADR-0001 Validation Criteria).
- [ ] **Registry and determinism.** `KartRegistry` owns the 12 slots, `slots_simulated_here()` and one seeded random stream per consumer; a headless run twice with the same inputs and seed produces identical traces (ADR-0001 Validation Criteria).
- [ ] **Start.** Karts spawn on the 12 `CourseData` grid poses and the start sequence and start boost run through `DriveState` (Driving & Drift AC-16 on track).

---

## Implementation Notes

- Nothing here references `src/legacy/`.
- Follow `.claude/rules/godot-refcount.md` for any new `connect(`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 051: laps and respawn.
- Story 056: network.
- Story 063: making this the main scene.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/race_main.tscn`, `src/race_main.gd` (new composition root)
- `src/core/race/race_clock.gd`, `src/core/race/kart_registry.gd` (new)
- `tests/integration/race/race_tick_order_test.gd`, `tests/unit/race/race_clock_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/race/race_tick_order_test.gd`, `tests/unit/race/race_clock_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-050/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-024-kart-determinism-and-budget.md`, `production/epics/core-rebuild/story-032-course-laps-respawn-grid.md`, `production/epics/core-rebuild/story-042-castle-blend-bootstrap.md`
- Unlocks: `production/epics/core-rebuild/story-051-castle-laps-ranking-respawn.md`, `production/epics/core-rebuild/story-052-castle-features-and-hazards.md`
