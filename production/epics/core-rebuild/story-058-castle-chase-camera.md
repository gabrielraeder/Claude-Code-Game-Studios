# Story 058: Castle: chase camera port

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Visual/Feel
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/systems-index.md` row Chase Camera (no system GDD yet)
**Requirement**: `architecture.md` Performance Budgets (chase camera 0.3 ms per frame, no per-frame track scans; frozen cost 2.7 ms)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025: Castle Circuit rebuilt). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0001: Simulation Conventions and Code Layout (Accepted); ADR-0002: Collision Backend and Surface Attributes (Proposed)
**ADR Decision Summary**:
- ADR-0001: Godot Y-up, -Z forward, metres; the synced race time is authoritative and the 60 Hz tick follows it with a defined catch-up policy; a fixed step order and one seeded random stream per consumer; our own interpolation with a teleport flag; mirror mode is a proper reflection at track load; the frozen 2.5D game lives in `src/legacy/`, shared data classes in `src/data/`, new code in new folders.
- ADR-0002: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).

**ADR Version**: ADR-0001 2026-11-21; ADR-0002 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Tick settings are pinned (`physics_ticks_per_second=60`, `max_physics_steps_per_frame=8`, `physics_interpolation=false`). Since 4.4 every script has a `.uid` sidecar. 4.8: strings can no longer be comments; a script can no longer inherit its own inner classes. Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **No scans.** The camera reads Course Data or collision at most once per frame (no route or track scan), and costs <= 0.3 ms p95 per rendered frame (frozen: 2.7 ms) (`architecture.md` Performance Budgets).
- [ ] **Follows the body.** It follows the kart's interpolated pose and up through banks and landings, and snaps on the teleport flag (ADR-0001 §3, §8).
- [ ] **Owner sign-off.** The owner signs off that the camera feels like the frozen game on Castle Circuit; screenshots of a bank, a jump and a respawn are retained.

---

## Implementation Notes

- Presentation reads snapshots; it never writes simulation state.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 059: kart visuals.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/presentation/camera/chase_camera.gd` (new)
- `production/qa/evidence/core-rebuild-story-058/` (screenshots), `production/qa/evidence/core-rebuild-story-058-evidence.md`

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: retained screenshots in `production/qa/evidence/core-rebuild-story-058/` + owner sign-off in `production/qa/evidence/core-rebuild-story-058-evidence.md`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-056-castle-network-switch.md`
- Unlocks: `production/epics/core-rebuild/story-060-checkpoint-a2-castle-online.md`
