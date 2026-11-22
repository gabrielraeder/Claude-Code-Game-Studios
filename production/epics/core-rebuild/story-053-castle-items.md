# Story 053: Castle: items

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/course-data.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0004 Migration Plan step 3 (Items on box poses and item routes); ADR-0006 follow-up (event kinds 5 and up); `architecture.md` Performance Budgets (items 0.15 ms)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025: Castle Circuit rebuilt). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0004: Course Data Format (Accepted); ADR-0006: Network Snapshot for 3D (Accepted)
**ADR Decision Summary**:
- ADR-0004: A binary `CourseData` `.res` (checkpoint gates with group ids and next links plus key groups for laps, routes with baked per-sample and span tables, item-box, respawn and 12 grid poses, oriented `areas`) is built by a `@tool` `CourseBuilder` in `src/core/course/` from a neutral `CourseAuthoring` plus a `CollisionQuery`; per-kart `CourseProgress` runs a sector cursor in O(1) amortised time and handles junctions, shortcuts, wrong-way driving and off-course flight; bots read only routes and tables, never `CollisionQuery`; mirror swaps every left/right field.
- ADR-0006: Protocol VERSION 10: a quantised 41-byte per-kart record batched by the host; reliable gameplay events on their own channel with an ownership check per event kind; a race config carrying track identity, mirror flag and seed, refused on a mismatch; an NTP-style clock with a min-RTT filter and slew that sets the target tick; a `RemoteKartView` that interpolates, caps extrapolation by time, snaps on a teleport epoch that survives packet loss and reports events once per consumer. `NetMetrics` leaves teleports out of the prediction error (closes TD-010).

**ADR Version**: ADR-0004 2026-11-22; ADR-0006 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The `.res` round trip and cache identity are VERIFIED by probe (`prototypes/collision-spike/out/probe_adr45_*`). Scripts the baker touches are `@tool` and loaded by `preload("res://...")` path, not `class_name` (ADR-0005 NV-7). ENet through Godot's multiplayer peer; probes V1, V2, V3 and V5 done (`prototypes/collision-spike/out/`), V4 still to run (Validation 8). Check ENet channel and packet APIs against `docs/engine-reference/godot/` before use.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Boxes and routes.** Items run in `src/gameplay/items/` on `CourseData` item-box poses and item routes, with no `src/legacy` reference (ADR-0004 Migration Plan step 3).
- [ ] **Events.** Item event kinds 5 and up are defined with their `owner_slot` rule and round-trip in `NetEventCodec` (ADR-0006 follow-up).
- [ ] **Behaviour kept.** A new-core equivalent of `item_net_test.sh` passes on Castle Circuit, and an item hit calls `DriveState.hit()` (Driving & Drift AC-14).
- [ ] **Budget.** Items <= 0.15 ms p95 per tick, 12 karts (`architecture.md` Performance Budgets).

---

## Implementation Notes

- Read the frozen `item_manager.gd` as reference only; `ItemDef` / `ItemSet` are shared data in `src/data/`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 057: item HUD.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/gameplay/items/item_manager.gd` (new)
- `src/networking/net_event_codec.gd` (item kinds)
- `tests/integration/items/castle_items_test.gd`, `tests/unit/items/item_events_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/items/castle_items_test.gd`, `tests/unit/items/item_events_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-053/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-044-net-event-codec-and-race-config.md`, `production/epics/core-rebuild/story-051-castle-laps-ranking-respawn.md`
- Unlocks: `production/epics/core-rebuild/story-055-castle-bot-race-and-budget.md`
