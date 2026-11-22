# Story 048: NetLink, events channel and host aggregation

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none (Network Session & Sync has no GDD yet; ADR-0006 is the spec)
**Requirement**: ADR-0006 Migration Plan step 2 (`NetLink`); Validation Criteria 5 and 8 (first item)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025, network sub-story; ADR-0006 Migration Plan step 2). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0006: Network Snapshot for 3D (Accepted)
**ADR Decision Summary**: Protocol VERSION 10: a quantised 41-byte per-kart record batched by the host; reliable gameplay events on their own channel with an ownership check per event kind; a race config carrying track identity, mirror flag and seed, refused on a mismatch; an NTP-style clock with a min-RTT filter and slew that sets the target tick; a `RemoteKartView` that interpolates, caps extrapolation by time, snaps on a teleport epoch that survives packet loss and reports events once per consumer. `NetMetrics` leaves teleports out of the prediction error (closes TD-010).

**ADR Version**: ADR-0006 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: ENet through Godot's multiplayer peer; probes V1, V2, V3 and V5 done (`prototypes/collision-spike/out/`), V4 still to run (Validation 8). Check ENet channel and packet APIs against `docs/engine-reference/godot/` before use.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **NetLink.** `NetLink` ports host, join, auth and the fake-network queue from the frozen `NetSession` (reference only) and adds channel 2 for reliable events and `server_relay = false` (ADR-0006 Migration Plan step 2).
- [ ] **Aggregation and ownership.** Replacing a held record ORs its events into the new one; a record or BUMP from a peer that does not own the checked field is dropped and logged (ADR-0006 Validation 5).
- [ ] **Handshake.** Two ENet peers on localhost: a v10 handshake with v10 passes, and a constant v9 packet is refused (ADR-0006 Validation 8).

---

## Implementation Notes

- Integration tests use port 24690 and never kill processes they did not start (story 001 convention).
- Follow `.claude/rules/godot-refcount.md` for any new `connect(`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 049: package mismatch and frozen/new coexistence.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/networking/net_link.gd` (new)
- `tests/unit/networking/host_aggregation_test.gd`, `tests/integration/networking/net_link_handshake_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/unit/networking/host_aggregation_test.gd`, `tests/integration/networking/net_link_handshake_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-048/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-044-net-event-codec-and-race-config.md`, `production/epics/core-rebuild/story-045-clock-sync.md`, `production/epics/core-rebuild/story-047-net-metrics-and-net-config.md`
- Unlocks: `production/epics/core-rebuild/story-049-net-coexistence-and-package-mismatch.md`
