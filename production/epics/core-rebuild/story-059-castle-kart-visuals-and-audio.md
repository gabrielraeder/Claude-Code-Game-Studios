# Story 059: Castle: kart visuals and race audio port

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Visual/Feel
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/driving-and-drift.md` (§8 Acceptance Criteria); `design/gdd/systems-index.md` rows Kart & Dog Presentation, Race Audio
**Requirement**: `architecture.md` Performance Budgets (kart visuals 0.5 ms; HUD, minimap, audio 0.5 ms per frame); Driving & Drift AC-X2 setup (spark colours)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025: Castle Circuit rebuilt). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0001: Simulation Conventions and Code Layout (Accepted); ADR-0003: Kart Physics Model (Proposed)
**ADR Decision Summary**:
- ADR-0001: Godot Y-up, -Z forward, metres; the synced race time is authoritative and the 60 Hz tick follows it with a defined catch-up policy; a fixed step order and one seeded random stream per consumer; our own interpolation with a teleport flag; mirror mode is a proper reflection at track load; the frozen 2.5D game lives in `src/legacy/`, shared data classes in `src/data/`, new code in new folders.
- ADR-0003: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.

**ADR Version**: ADR-0001 2026-11-21; ADR-0003 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Tick settings are pinned (`physics_ticks_per_second=60`, `max_physics_steps_per_frame=8`, `physics_interpolation=false`). Since 4.4 every script has a `.uid` sidecar. 4.8: strings can no longer be comments; a script can no longer inherit its own inner classes. Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Visuals.** 12 karts draw from interpolated snapshots (own interpolation, teleport flag) at <= 0.5 ms p95 per frame; drift sparks show tier colour blue / orange / purple, and boost, wall hit, landing and bump effects fire from snapshot event bits (`architecture.md`; ADR-0001 §8).
- [ ] **Audio.** `AudioSet` events (engine, drift, boost, wall hit, landing, bump, items, hazards) fire from the same events, once per event (ADR-0006: events once per consumer).
- [ ] **Owner sign-off.** The owner signs off that the karts look and sound like the frozen game; screenshots of a tier-3 drift per vehicle, a boost and a wall hit are retained.

---

## Implementation Notes

- `VehicleVisualStats`, `AudioEventDef`, `AudioSet`, `PennantStyle` are shared data in `src/data/`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 060: A2 sign-off.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/presentation/kart/kart_visual.gd`, `src/presentation/audio/race_audio.gd` (new)
- `production/qa/evidence/core-rebuild-story-059/` (screenshots), `production/qa/evidence/core-rebuild-story-059-evidence.md`

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: retained screenshots in `production/qa/evidence/core-rebuild-story-059/` + owner sign-off in `production/qa/evidence/core-rebuild-story-059-evidence.md`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-056-castle-network-switch.md`
- Unlocks: `production/epics/core-rebuild/story-060-checkpoint-a2-castle-online.md`
