# Story 027: Checkpoint A1: owner drift and feel sign-off

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0003 and ADR-0002 are Proposed (owner acceptance pending)
> **Layer**: Feature
> **Type**: Visual/Feel
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/driving-and-drift.md` (§8 Acceptance Criteria); `design/gdd/kart-physics.md` (§8 Acceptance Criteria); `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: Driving & Drift AC-X1; Kart Physics AC-X1; Track Collision AC-X1; ADR-0003 Validation Criteria (owner A1 sign-off; feel decision on tolerances)
**Roadmap step**: `architecture.md` Phase A Sequencing step 3, checkpoint **A1** (owner signs drift parity). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Proposed); ADR-0002: Collision Backend and Surface Attributes (Proposed)
**ADR Decision Summary**:
- ADR-0003: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.
- ADR-0002: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).

**ADR Version**: ADR-0003 2026-11-22; ADR-0002 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists. Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Drive scene.** A windowed debug drive scene (tool code, not shipping) loads the baked Castle Circuit and Dungeon Depths with a placeholder kart, a simple follow camera, Cart and Bike selectable, and one scripted second kart to bump.
- [ ] **Owner sign-off.** The owner drives both vehicles on baked Castle Circuit and signs off that drift, boost and surfaces (Driving & Drift AC-X1) and wall scrapes and crashes, landings and bumps (Kart Physics AC-X1) feel like the frozen game; any tolerance the owner moves is recorded (ADR-0003 feel decision, D3).
- [ ] **Screenshots retained.** A tier-3 drift, a wall impact and a landing per vehicle, and one screenshot per surface kind on Castle Circuit and Dungeon Depths, in `production/qa/evidence/core-rebuild-story-027/` (Driving AC-X1, Kart Physics AC-X1, Track Collision AC-X1).
- [ ] **Record.** `production/qa/evidence/core-rebuild-story-027-evidence.md` holds the owner's sign-off, date, build and any moved tolerance.

---

## Implementation Notes

- The drive scene is a tool (`tools/drive_test/`); the shipping camera and visuals are stories 058-059.
- Owner decisions P1/P2/D3 may land here; propagate them to the data and the parity gate.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 058: the shipping chase camera.
- Story 059: kart visuals and audio.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tools/drive_test/drive_test.tscn`, `tools/drive_test/drive_test.gd` (new)
- `production/qa/evidence/core-rebuild-story-027/` (screenshots), `production/qa/evidence/core-rebuild-story-027-evidence.md` (sign-off)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: retained screenshots in `production/qa/evidence/core-rebuild-story-027/` + owner sign-off in `production/qa/evidence/core-rebuild-story-027-evidence.md`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-026-parity-run-rebuilt-kart.md`
- Unlocks: `production/epics/core-rebuild/story-041-fresh-clone-import-and-test-track.md`
