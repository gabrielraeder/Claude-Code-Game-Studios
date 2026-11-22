# Story 044: NetEventCodec and RaceConfig

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none (Network Session & Sync has no GDD yet; ADR-0006 is the spec)
**Requirement**: ADR-0006 Validation Criteria 2 and 7
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025, network sub-story; ADR-0006 Migration Plan step 2). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0006: Network Snapshot for 3D (Accepted)
**ADR Decision Summary**: Protocol VERSION 10: a quantised 41-byte per-kart record batched by the host; reliable gameplay events on their own channel with an ownership check per event kind; a race config carrying track identity, mirror flag and seed, refused on a mismatch; an NTP-style clock with a min-RTT filter and slew that sets the target tick; a `RemoteKartView` that interpolates, caps extrapolation by time, snaps on a teleport epoch that survives packet loss and reports events once per consumer. `NetMetrics` leaves teleports out of the prediction error (closes TD-010).

**ADR Version**: ADR-0006 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: ENet through Godot's multiplayer peer; probes V1, V2, V3 and V5 done (`prototypes/collision-spike/out/`), V4 still to run (Validation 8). Check ENet channel and packet APIs against `docs/engine-reference/godot/` before use.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Events.** Every event kind round-trips; `owner_slot` returns `from_slot` for BUMP, `victim` for ITEM_HIT, and `slot` for HAZARD_HIT and FINISH; an unknown kind returns -1 (ADR-0006 Validation 2).
- [ ] **RaceConfig round trip.** Encode then decode is exact, carrying track identity, mirror flag and seed (ADR-0006 Validation 7).
- [ ] **Package check.** `check_package` returns 2 (SOURCE_MISMATCH) on a `source_sha256` mismatch even when `bake_key` also differs, and 3 (BAKE_MISMATCH) on a `bake_key` mismatch alone; 0 OK, 1 TRACK_MISSING (ADR-0006 Validation 7).

---

## Implementation Notes

- Event kinds 5 and up are reserved for the Items story (story 053).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 053: item event kinds.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/networking/net_event_codec.gd`, `src/networking/race_config.gd` (new)
- `tests/unit/networking/net_event_codec_test.gd`, `tests/unit/networking/race_config_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/networking/net_event_codec_test.gd`, `tests/unit/networking/race_config_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-043-snapshot-codec-v10.md`
- Unlocks: `production/epics/core-rebuild/story-048-net-link-and-host-aggregation.md`, `production/epics/core-rebuild/story-053-castle-items.md`
