# Story 049: Version coexistence and track-package mismatch

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0006 is Proposed (owner acceptance pending)
> **Layer**: Foundation
> **Type**: Integration
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none (Network Session & Sync has no GDD yet; ADR-0006 is the spec)
**Requirement**: ADR-0006 Validation Criteria 8 (items 2 and 3, probe V4)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025, network sub-story; ADR-0006 Migration Plan step 2). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0006: Network Snapshot for 3D (Proposed)
**ADR Decision Summary**: Protocol VERSION 10: a quantised 41-byte per-kart record batched by the host; reliable gameplay events on their own channel with an ownership check per event kind; a race config carrying track identity, mirror flag and seed, refused on a mismatch; an NTP-style clock with a min-RTT filter and slew that sets the target tick; a `RemoteKartView` that interpolates, caps extrapolation by time, snaps on a teleport epoch that survives packet loss and reports events once per consumer. `NetMetrics` leaves teleports out of the prediction error (closes TD-010).

**ADR Version**: ADR-0006 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: ENet through Godot's multiplayer peer; probes V1, V2, V3 and V5 done (`prototypes/collision-spike/out/`), V4 still to run (Validation 8). Check ENet channel and packet APIs against `docs/engine-reference/godot/` before use.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Package mismatch.** A race start with a `bake_key` mismatch excludes that client with a message (ADR-0006 Validation 8).
- [ ] **V4 coexistence.** A frozen (VERSION 9) host with a new client, and the reverse, both refuse with a message; the log is retained in `production/qa/evidence/core-rebuild-story-049/` (ADR-0006 Validation 8).

---

## Implementation Notes

- The frozen side is run unchanged from `src/legacy/`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 056: the full online run.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tests/integration/networking/net_coexistence_test.gd` (new)
- `production/qa/evidence/core-rebuild-story-049/` (logs)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/networking/net_coexistence_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-049/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-048-net-link-and-host-aggregation.md`
- Unlocks: `production/epics/core-rebuild/story-056-castle-network-switch.md`
