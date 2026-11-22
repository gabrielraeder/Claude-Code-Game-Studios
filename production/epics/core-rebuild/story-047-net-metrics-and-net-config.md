# Story 047: NetMetrics (TD-010) and NetConfig fork

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none (Network Session & Sync has no GDD yet; ADR-0006 is the spec)
**Requirement**: ADR-0006 Validation Criteria 6; ADR-0006 Migration Plan step 3 (`NetConfig` fields, `assets/data/core/net_config.tres`)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025, network sub-story; ADR-0006 Migration Plan step 2). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0006: Network Snapshot for 3D (Proposed)
**ADR Decision Summary**: Protocol VERSION 10: a quantised 41-byte per-kart record batched by the host; reliable gameplay events on their own channel with an ownership check per event kind; a race config carrying track identity, mirror flag and seed, refused on a mismatch; an NTP-style clock with a min-RTT filter and slew that sets the target tick; a `RemoteKartView` that interpolates, caps extrapolation by time, snaps on a teleport epoch that survives packet loss and reports events once per consumer. `NetMetrics` leaves teleports out of the prediction error (closes TD-010).

**ADR Version**: ADR-0006 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: ENet through Godot's multiplayer peer; probes V1, V2, V3 and V5 done (`prototypes/collision-spike/out/`), V4 still to run (Validation 8). Check ENet channel and packet APIs against `docs/engine-reference/godot/` before use.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Teleports excluded.** A respawn sequence produces no prediction-error sample and one `teleports` count (ADR-0006 Validation 6; closes TD-010).
- [ ] **Anomaly.** An unflagged 30 m jump produces one rate-limited `unflagged_jump` anomaly (ADR-0006 Validation 6).
- [ ] **View delay.** `view_delay` equals the maximum over peers (ADR-0006 Validation 6).
- [ ] **NetConfig.** The new fields, including `contact_extrapolation_max`, are added additively with defaults and `##` comments, and `assets/data/core/net_config.tres` is forked from `assets/data/net/net_config.tres` with the new values; the frozen game is unchanged (ADR-0006 Migration Plan step 3).

---

## Implementation Notes

- Additive change to shared `src/data/net_config.gd` per ADR-0001 §9.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 056: the A2 online measurement.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/networking/net_metrics.gd` (new)
- `src/data/net_config.gd` (additive)
- `assets/data/core/net_config.tres` (new)
- `tests/unit/networking/net_metrics_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/networking/net_metrics_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-046-remote-kart-view.md`
- Unlocks: `production/epics/core-rebuild/story-048-net-link-and-host-aggregation.md`
