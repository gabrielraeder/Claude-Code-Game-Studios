# Story 060: Checkpoint A2: Castle Circuit online with bots

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/kart-physics.md` (§8 Acceptance Criteria); `design/gdd/driving-and-drift.md` (§8 Acceptance Criteria); `design/gdd/course-data.md` (§8 Acceptance Criteria); `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: `architecture.md` checkpoint A2; Kart Physics AC-X2, AC-X3; Driving & Drift AC-X2, AC-X3; Track Collision AC-X2, AC-X3; Course Data AC18, AC19 (Castle)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6, checkpoint **A2** (Castle online with bots). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0006: Network Snapshot for 3D (Accepted); ADR-0003: Kart Physics Model (Accepted); ADR-0004: Course Data Format (Accepted)
**ADR Decision Summary**:
- ADR-0006: Protocol VERSION 10: a quantised 41-byte per-kart record batched by the host; reliable gameplay events on their own channel with an ownership check per event kind; a race config carrying track identity, mirror flag and seed, refused on a mismatch; an NTP-style clock with a min-RTT filter and slew that sets the target tick; a `RemoteKartView` that interpolates, caps extrapolation by time, snaps on a teleport epoch that survives packet loss and reports events once per consumer. `NetMetrics` leaves teleports out of the prediction error (closes TD-010).
- ADR-0003: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.
- ADR-0004: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.

**ADR Version**: ADR-0006 2026-11-22; ADR-0003 2026-11-22; ADR-0004 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: ENet through Godot's multiplayer peer; probes V1, V2, V3 and V5 done (`prototypes/collision-spike/out/`), V4 still to run (Validation 8). Check ENet channel and packet APIs against `docs/engine-reference/godot/` before use. Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Race online.** A 4-PC race on Castle Circuit (host + 3 clients + 8 bots, then host + 11 bots) completes on the new core; `tools/regression.sh`'s new-core lines all PASS.
- [ ] **Budget.** The whole simulation tick is <= 2.0 ms p95 on the owner's PC with every budget row reported (`architecture.md` Performance Budgets).
- [ ] **Playtest record.** Bump counts per PC agree and no tester reports a bump felt twice or one that did nothing (Kart Physics AC-X2); the ramming (E-31) and snaking (E-21) calls, spark-tier naming, surface naming and mover-warning results are recorded (Kart Physics AC-X3; Driving & Drift AC-X2, AC-X3; Track Collision AC-X2, AC-X3); Castle shortcut savings 0.8-1.5 s with failure cost 2-4 × the saving, and timed shortcut hazards warn >= 1.5 s and are never closed together (Course Data AC18, AC19).
- [ ] **Owner sign-off.** The owner signs off A2 in `production/qa/evidence/core-rebuild-story-060-evidence.md`.

---

## Implementation Notes

- Playtest bars marked as owner-set are recorded as the owner sets them; a failed bar becomes a named follow-up, not a silent pass.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 061-064: Dungeon Depths and A3.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `production/qa/evidence/core-rebuild-story-060/` (logs, profiles), `production/qa/evidence/core-rebuild-story-060-evidence.md` (playtest and sign-off)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: the integration run named in the criteria; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-060/`; playtest and sign-off record `production/qa/evidence/core-rebuild-story-060-evidence.md`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-057-castle-hud-minimap-race-flow.md`, `production/epics/core-rebuild/story-058-castle-chase-camera.md`, `production/epics/core-rebuild/story-059-castle-kart-visuals-and-audio.md`
- Unlocks: `production/epics/core-rebuild/story-061-dungeon-blend-bootstrap.md`
