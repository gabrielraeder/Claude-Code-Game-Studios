# Story 023: Kart contact solver: remote karts, events, merge and freeze

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/kart-physics.md` (§8 Acceptance Criteria)
**Requirement**: Kart Physics AC-22, AC-23, AC-24; ADR-0003 Validation Criteria (frozen mode, teleport drop, `contact_eligible`, remote broadphase key)
**Roadmap step**: `architecture.md` Phase A Sequencing step 3 (roadmap item 022: Kart Physics + Driving & Drift, checkpoint A1). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Accepted)
**ADR Decision Summary**: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.

**ADR Version**: ADR-0003 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Local vs remote.** The local kart takes the full separation and only its knock share; exactly one `KartEvent` is produced; a pair of two remote karts is skipped (Kart Physics AC-22).
- [ ] **Max-merge.** Magnitude 3 locally, then 5 by event from the same slot -> total added knock magnitude 5 (not 8, not 3); after `bump_cooldown` (0.3 s) the pair memory is clear (Kart Physics AC-23).
- [ ] **Bump ordering.** After a local contact and after a received bump event, the next `drive()` reads the reduced `speed`, and the `bumped` bit is in the end-of-tick snapshot (Kart Physics AC-24).
- [ ] **Freeze and eligibility.** A FROZEN body runs no queries, holds zero speed, is excluded from contact and drops received bumps; a received bump earlier than `last_teleport_tick` is dropped; `contact_eligible` = 0 (STALE, EMPTY, extrapolated > 0.1 s) removes the kart from every pair; the remote broadphase key is the `distance` sampled at the drawn pose (ADR-0003 Validation Criteria).

---

## Implementation Notes

- Bump victim timeline per ADR-0003 v4/v2 notes (bump tick on the victim's timeline).
- Remote poses come from a stub view here; story 046 builds the real `RemoteKartView`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 046: `RemoteKartView` and `contact_eligible` source.
- Story 048: sending bump events.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/core/kart/kart_contact_solver.gd` (remote, events)
- `src/core/kart/kart_event.gd` (new)
- `tests/unit/kart/kart_contact_remote_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/kart/kart_contact_remote_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-022-kart-contact-local.md`
- Unlocks: `production/epics/core-rebuild/story-024-kart-determinism-and-budget.md`
