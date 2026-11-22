# Story 026: Parity run: rebuilt kart against the golden traces

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/driving-and-drift.md` (§8 Acceptance Criteria); `design/gdd/kart-physics.md` (§8 Acceptance Criteria)
**Requirement**: Driving & Drift AC-P2; Kart Physics AC-P1; ADR-0003 Validation Criteria (gate, solo traces; advisory bot traces)
**Roadmap step**: `architecture.md` Phase A Sequencing step 3 (roadmap item 022: Kart Physics + Driving & Drift, checkpoint A1). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Accepted); ADR-0004: Course Data Format (Accepted)
**ADR Decision Summary**:
- ADR-0003: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.
- ADR-0004: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0003 2026-11-22; ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists. The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Timing gate.** On the generator-baked Castle Circuit and Dungeon Depths meshes (story 008), the pilot of story 025 driving the new `KartBody` + `DriveState` on the 4 solo traces gives lap time within +/-2% of golden (Castle Circuit Cart 42.27 s -> 41.42-43.11 s), per-checkpoint sector splits within +/-3%, top speed within +/-1% (Driving & Drift AC-P2).
- [ ] **Counts gate.** Drift boosts within +/-1 per tier per lap; takeoff, landing and lap counts exact; no interval with speed < 2 m/s for more than 1 s after the start on any solo trace (Driving & Drift AC-P2; Kart Physics AC-P1).
- [ ] **Diagnostics.** The report counts `depenetrated` guard events per track (ADR-0003 Risks) and reports the bot traces' finish spread as advisory, not gating (ADR-0003 Validation Criteria).

---

## Implementation Notes

- Tolerances are Open decision D3 (driving-and-drift.md); the owner may move them at A1 (story 027).
- Checkpoint positions for sector splits come from the extractor JSON (story 008).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 027: owner feel sign-off.
- Story 054-055: rebuilt bots.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tools/parity/new_kart_adapter.gd` (new), `tools/parity/run_parity.sh` (new-kart mode)
- `tests/integration/parity/parity_gate_test.gd` (new)
- `production/qa/evidence/core-rebuild-story-026/` (parity report)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/parity/parity_gate_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-026/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-008-legacy-extractor-and-test-mesh.md`, `production/epics/core-rebuild/story-024-kart-determinism-and-budget.md`, `production/epics/core-rebuild/story-025-parity-harness-noise-floor.md`
- Unlocks: `production/epics/core-rebuild/story-027-checkpoint-a1-feel-signoff.md`, `production/epics/core-rebuild/story-034-generator-course-equivalence.md`
