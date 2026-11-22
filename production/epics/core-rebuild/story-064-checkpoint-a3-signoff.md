# Story 064: Checkpoint A3: both tracks on the new core

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/driving-and-drift.md` (§8 Acceptance Criteria); `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: EPIC.md Goal (done when A3 is signed); Course Data AC18, AC19 (Dungeon); Driving & Drift AC-P2 on pipeline packages
**Roadmap step**: `architecture.md` Phase A Sequencing step 7, checkpoint **A3**. Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0003: Kart Physics Model (Proposed); ADR-0004: Course Data Format (Proposed); ADR-0006: Network Snapshot for 3D (Proposed)
**ADR Decision Summary**:
- ADR-0003: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.
- ADR-0004: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.
- ADR-0006: Protocol VERSION 10: a quantised 41-byte per-kart record batched by the host; reliable gameplay events on their own channel with an ownership check per event kind; a race config carrying track identity, mirror flag and seed, refused on a mismatch; an NTP-style clock with a min-RTT filter and slew that sets the target tick; a `RemoteKartView` that interpolates, caps extrapolation by time, snaps on a teleport epoch that survives packet loss and reports events once per consumer. `NetMetrics` leaves teleports out of the prediction error (closes TD-010).

**ADR Version**: ADR-0003 2026-11-22; ADR-0004 2026-11-22; ADR-0006 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists. The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7).

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Parity on shipped packages.** The story-026 parity gate re-run on the pipeline-built Castle Circuit and Dungeon Depths packages passes (Driving & Drift AC-P2).
- [ ] **Budget.** The whole simulation tick is <= 2.0 ms p95 on both tracks, 12 karts, owner's PC (`architecture.md` Performance Budgets).
- [ ] **Playtest and sign-off.** Dungeon shortcut savings and hazard warnings meet Course Data AC18, AC19; the owner signs off that both tracks run on the new core, online with bots, at today's quality or better, in `production/qa/evidence/core-rebuild-story-064-evidence.md` (EPIC.md Goal).

---

## Implementation Notes

- Export templates for 4.8 may exist by now; if so, re-measure on a release export.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 065: legacy retirement.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `production/qa/evidence/core-rebuild-story-064/` (parity, profiles), `production/qa/evidence/core-rebuild-story-064-evidence.md` (sign-off)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: the integration run named in the criteria; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-064/`; playtest and sign-off record `production/qa/evidence/core-rebuild-story-064-evidence.md`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-063-composition-root-switch.md`
- Unlocks: `production/epics/core-rebuild/story-065-legacy-retirement.md`
