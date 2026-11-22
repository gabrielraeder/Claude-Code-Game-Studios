# Story 051: Castle: laps, ranking and respawn

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0004 is Proposed (owner acceptance pending)
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: Course Data AC10 to AC16 on Castle Circuit; ADR-0004 Migration Plan step 3 (Lap & Position and Fall & Respawn on `CourseProgress`)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025: Castle Circuit rebuilt). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Proposed); ADR-0001: Simulation Conventions and Code Layout (Accepted)
**ADR Decision Summary**:
- ADR-0004: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.
- ADR-0001: Godot Y-up, -Z forward, metres; the synced race time is authoritative and the 60 Hz tick follows it with a defined catch-up policy; a fixed step order and one seeded random stream per consumer; our own interpolation with a teleport flag; mirror mode is a proper reflection at track load; the frozen 2.5D game lives in `src/legacy/`, shared data classes in `src/data/`, new code in new folders.

**ADR Version**: ADR-0004 2026-11-22; ADR-0001 2026-11-21

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7). Tick settings are pinned (`physics_ticks_per_second=60`, `max_physics_steps_per_frame=8`, `physics_interpolation=false`). Since 4.4 every script has a `.uid` sidecar. 4.8: strings can no longer be comments; a script can no longer inherit its own inner classes.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Laps.** An autopilot on Castle Circuit for 3 laps gets `lap` 1, 2, 3, 4, `rejected_crossings = 0` and non-decreasing `distance`; each shortcut driven by a scripted line counts the lap with continuous `distance`; a scripted infield cut earns no lap (`crossing_rejected = true`) (Course Data AC10, AC11, AC12).
- [ ] **Respawn.** Driving off each open edge respawns at the respawn of the last safe gate with `lap` unchanged and `distance` not greater than before; a failed speed-gated jump, where the track has one, respawns on main; the respawn sets the teleport flag (Course Data AC14, AC15; ADR-0001 §8).
- [ ] **Mirror.** The mirrored Castle Circuit passes AC10-AC12 on the mirrored line, and the cached `CourseData` is byte-for-byte unchanged afterwards (Course Data AC16).
- [ ] **Ranking in race.** `RaceRanking` (story 033) orders the 12 karts every tick, and the race-logic stage stays inside 0.15 ms p95 (`architecture.md`).

---

## Implementation Notes

- Lap & Position and Fall & Respawn are Feature-layer modules reading `CourseProgress`; neither reads the spline.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 057: HUD display of laps and ranking.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/gameplay/race/lap_and_position.gd`, `src/gameplay/respawn/fall_and_respawn.gd` (new)
- `tests/integration/race/castle_laps_respawn_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/race/castle_laps_respawn_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-051/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-050-castle-race-clock-registry-tick.md`
- Unlocks: `production/epics/core-rebuild/story-053-castle-items.md`, `production/epics/core-rebuild/story-054-castle-bots-on-routes.md`
