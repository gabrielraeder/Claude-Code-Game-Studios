# Story 025: Parity harness: trace pilot and frozen-kart noise floor

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0003 is Proposed (owner acceptance pending)
> **Layer**: Core
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/driving-and-drift.md` (§8 Acceptance Criteria); `design/gdd/kart-physics.md` (§8 Acceptance Criteria)
**Requirement**: Driving & Drift AC-P1; ADR-0003 Validation Criteria (parity setup, noise floor first)
**Roadmap step**: `architecture.md` Phase A Sequencing step 3 (roadmap item 022: Kart Physics + Driving & Drift, checkpoint A1). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Proposed); ADR-0001: Simulation Conventions and Code Layout (Accepted)
**ADR Decision Summary**:
- ADR-0003: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.
- ADR-0001: Godot Y-up, -Z forward, metres; the synced race time is authoritative and the 60 Hz tick follows it with a defined catch-up policy; a fixed step order and one seeded random stream per consumer; our own interpolation with a teleport flag; mirror mode is a proper reflection at track load; the frozen 2.5D game lives in `src/legacy/`, shared data classes in `src/data/`, new code in new folders.

**ADR Version**: ADR-0003 2026-11-22; ADR-0001 2026-11-21

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists. Tick settings are pinned (`physics_ticks_per_second=60`, `max_physics_steps_per_frame=8`, `physics_interpolation=false`). Since 4.4 every script has a `.uid` sidecar. 4.8: strings can no longer be comments; a script can no longer inherit its own inner classes.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Pilot.** A trace-following pilot steers along each golden trace's `x, z, height` path and replays the golden `drifting` / `drift_dir` and throttle timing by distance travelled along the golden trace's own path, neither by time nor by `CourseProgress.s` (ADR-0003 Validation Criteria).
- [ ] **Noise floor.** The pilot runs the frozen kart (`src/legacy/`, through the regression tools ADR-0001 allows) on the 4 solo traces (Cart and Bike, Castle Circuit and Dungeon Depths), and the self-error of every gated metric is reported: lap time, per-checkpoint sector splits, top speed, drift boosts per tier per lap, takeoff/landing/lap counts, wall-stuck intervals (Driving & Drift AC-P1).
- [ ] **Tolerances above the floor.** Every tolerance of Driving & Drift AC-P2 sits above the measured self-error; where one does not, the harness is fixed before any rebuild run counts, and the report says which (ADR-0003 noise-floor rule).
- [ ] **Repeatable.** Two frozen-kart harness runs give identical metric reports (`production/qa/evidence/core-rebuild-story-025/`).

---

## Implementation Notes

- The pilot talks to the kart through a small adapter so the same pilot drives the frozen `KartSim` here and the new `KartBody` in story 026; the frozen adapter lives under `tools/`, never `src/`.
- Golden traces: `production/qa/evidence/core-rebuild-story-001/golden/`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 026: running the rebuilt kart through the gate.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tools/parity/trace_pilot.gd`, `tools/parity/frozen_kart_adapter.gd`, `tools/parity/parity_report.py`, `tools/parity/run_parity.sh` (new)
- `tests/integration/parity/parity_harness_test.gd` (new)
- `production/qa/evidence/core-rebuild-story-025/` (noise-floor report)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/parity/parity_harness_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-025/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-001-freeze-and-oracle.md`
- Unlocks: `production/epics/core-rebuild/story-026-parity-run-rebuilt-kart.md`
