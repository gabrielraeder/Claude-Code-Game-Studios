# Story 012: First-slice budget: KartBody + drive() vs 0.3 ms

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0003 is Proposed (owner acceptance pending)
> **Layer**: Core
> **Type**: Integration
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/kart-physics.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0003 Migration Plan order step 2 (measure body + `drive()` against 0.3 ms in the first slice); Kart Physics AC-28 (first half); `architecture.md` Performance Budgets
**Roadmap step**: `architecture.md` Phase A Sequencing step 3 (roadmap item 022: Kart Physics + Driving & Drift, checkpoint A1). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Proposed)
**ADR Decision Summary**: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.

**ADR Version**: ADR-0003 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Measured.** 12 `KartBody` + `DriveState.drive()` in a running tree on the test mesh (story 007's mesh), scripted inputs, 1 lap: p95 per tick <= 0.3 ms on the owner's PC, debug editor build accepted as an upper bound until 4.8 export templates exist (ADR-0003 Migration Plan; Kart Physics AC-28).
- [ ] **Separated.** Collision time inside the same run is reported as its own stage and stays inside its 0.3 ms (ADR-0002).
- [ ] **Decision on a miss.** The report (`production/qa/evidence/core-rebuild-story-012/first-slice-bench.md`) records median, p95, machine, build and command; if p95 > 0.3 ms it names the three hottest functions (profiler shares) and a technical-director decision is logged before story 013 starts.

---

## Implementation Notes

- This is the early warning on the kart budget: run it before walls, air and contact are added.
- Use `tools/profile_tick.gd`-style stage stamps; profiler numbers are used as shares only (the profiler inflates time).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 024: the full-feature re-measure and the contact budget.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tools/bench_kart.gd` (new)
- `production/qa/evidence/core-rebuild-story-012/` (report)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: the integration run named in the criteria; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-012/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-007-collision-benchmark.md`, `production/epics/core-rebuild/story-010-kart-body-ground-and-up.md`, `production/epics/core-rebuild/story-011-drive-state-speed-and-surfaces.md`
- Unlocks: `production/epics/core-rebuild/story-013-kart-wall-slide-and-pushout.md`
