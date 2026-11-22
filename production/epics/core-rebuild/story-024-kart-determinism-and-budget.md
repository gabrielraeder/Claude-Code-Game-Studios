# Story 024: Kart determinism, boundary greps and contact budget

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0003 is Proposed (owner acceptance pending)
> **Layer**: Core
> **Type**: Integration
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/kart-physics.md` (§8 Acceptance Criteria)
**Requirement**: Kart Physics AC-26, AC-27, AC-28; ADR-0003 Validation Criteria (determinism, grep, benchmark)
**Roadmap step**: `architecture.md` Phase A Sequencing step 3 (roadmap item 022: Kart Physics + Driving & Drift, checkpoint A1). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Proposed)
**ADR Decision Summary**: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.

**ADR Version**: ADR-0003 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Determinism.** Two runs with the same inputs (offline, host-bot, and recorded remote events replayed at their ticks) give bit-identical `KartSnapshot` streams on one machine (Kart Physics AC-26).
- [ ] **Grep.** `tools/core_greps.sh` finds no `src/legacy`, `src/gameplay`, `src/networking`, `Vector3.DOWN`, `randf`, `randi` or `delta` in `src/core/kart/`, no `Dictionary(` or `Geometry3D.get_closest_points_between_segments` in per-tick paths, and no numeric tuning literal other than 0/1/-1 and the named consts of Kart Physics §3.2 (Kart Physics AC-27).
- [ ] **Budget.** 12 karts in a running tree on the owner's PC with every feature on: body + `drive()` <= 0.3 ms p95 and contact <= 0.2 ms p95, debug build accepted as an upper bound until 4.8 export templates exist; report retained (Kart Physics AC-28; `architecture.md` Performance Budgets).

---

## Implementation Notes

- Re-use `tools/bench_kart.gd` from story 012 with contact on.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 026: parity against the frozen kart.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tools/bench_kart.gd` (contact stage)
- `tools/core_greps.sh` (kart rules)
- `tests/integration/kart/kart_determinism_test.gd` (new)
- `production/qa/evidence/core-rebuild-story-024/` (bench report)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/kart/kart_determinism_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-024/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-020-drive-surface-transitions-and-boundary.md`, `production/epics/core-rebuild/story-021-kart-moving-platforms.md`, `production/epics/core-rebuild/story-023-kart-contact-remote-and-events.md`
- Unlocks: `production/epics/core-rebuild/story-026-parity-run-rebuilt-kart.md`, `production/epics/core-rebuild/story-050-castle-race-clock-registry-tick.md`
