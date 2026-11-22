# Story 062: Dungeon Depths gameplay on the new core

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria); `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: Course Data AC10 to AC17 (Dungeon); Track Collision AC-16 (Dungeon hazards); ADR-0006 Validation 9 bars on Dungeon
**Roadmap step**: `architecture.md` Phase A Sequencing step 7 (Dungeon Depths rebuilt; composition root switch; old modules retired, owner-approved; checkpoint A3). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Proposed); ADR-0002: Collision Backend and Surface Attributes (Proposed); ADR-0006: Network Snapshot for 3D (Proposed)
**ADR Decision Summary**:
- ADR-0004: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.
- ADR-0002: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).
- ADR-0006: Protocol VERSION 10: a quantised 41-byte per-kart record batched by the host; reliable gameplay events on their own channel with an ownership check per event kind; a race config carrying track identity, mirror flag and seed, refused on a mismatch; an NTP-style clock with a min-RTT filter and slew that sets the target tick; a `RemoteKartView` that interpolates, caps extrapolation by time, snaps on a teleport epoch that survives packet loss and reports events once per consumer. `NetMetrics` leaves teleports out of the prediction error (closes TD-010).

**ADR Version**: ADR-0004 2026-11-22; ADR-0002 2026-11-22; ADR-0006 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7). Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Hazards.** Each frozen Dungeon Depths hazard re-authored on the mover model passes the Track Collision §4.5 checks with its shipped numbers, inside the 0.1 ms hazards budget (Track Collision AC-16).
- [ ] **Laps and respawn.** Course Data AC10-AC16 pass on Dungeon Depths and its mirror (story 051's tests, run on this package).
- [ ] **Bots.** 11 bots, 5 races: 11/11 finish, 0 stuck, 0 shortcut mis-entries (Course Data AC17).
- [ ] **Online.** The story-056 online run passes on Dungeon Depths with the ADR-0006 Validation 9 bars.

---

## Implementation Notes

- Reuse the Castle tests parameterised by track; no track-specific code paths.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 063: main scene switch.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `art_src/tracks/dungeon_depths/dungeon_depths.blend` (movers)
- `tests/integration/race/dungeon_race_test.gd` (new)
- `production/qa/evidence/core-rebuild-story-062/` (races, online metrics)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/race/dungeon_race_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-062/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-061-dungeon-blend-bootstrap.md`
- Unlocks: `production/epics/core-rebuild/story-063-composition-root-switch.md`
