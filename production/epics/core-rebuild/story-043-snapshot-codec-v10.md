# Story 043: SnapshotCodec VERSION 10

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0006 is Proposed (owner acceptance pending)
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none (Network Session & Sync has no GDD yet; ADR-0006 is the spec)
**Requirement**: ADR-0006 Validation Criteria 1 (codec unit tests)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025, network sub-story; ADR-0006 Migration Plan step 2). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0006: Network Snapshot for 3D (Proposed)
**ADR Decision Summary**: Protocol VERSION 10: a quantised 41-byte per-kart record batched by the host; reliable gameplay events on their own channel with an ownership check per event kind; a race config carrying track identity, mirror flag and seed, refused on a mismatch; an NTP-style clock with a min-RTT filter and slew that sets the target tick; a `RemoteKartView` that interpolates, caps extrapolation by time, snaps on a teleport epoch that survives packet loss and reports events once per consumer. `NetMetrics` leaves teleports out of the prediction error (closes TD-010).

**ADR Version**: ADR-0006 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: ENet through Godot's multiplayer peer; probes V1, V2, V3 and V5 done (`prototypes/collision-spike/out/`), V4 still to run (Validation 8). Check ENet channel and packet APIs against `docs/engine-reference/godot/` before use.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Sizes and refusal.** The record size is 41 and the header size is 2; a wrong version byte or a short buffer returns -1, and a record with non-finite fields decodes as false (ADR-0006 Validation 1).
- [ ] **Position.** The round-trip error is <= 0.123 mm over a grid that includes +/-2000 m and both range edges, and a clamp sets `position_clamped` (ADR-0006 Validation 1).
- [ ] **Rotation.** 10,000 seeded random quaternions decode within 0.28°, with w >= 0 (ADR-0006 Validation 1).
- [ ] **Scalars.** f16 fields have error <= 0.0156 below 64 and <= 0.031 up to 128, mean signed error ≈ 0 over a seeded sweep (pre-round, no truncation bias), and +/-70000 encodes as +/-65504, not inf; the u16 and snorm8 bounds hold (ADR-0006 Validation 1).

---

## Implementation Notes

- API: `write_header`, `write_record(buf, offset, ...)` returning the next offset, `read_header` returning the count or -1, `read_record(..., out)` into a preallocated object; buffers are preallocated by the caller (ADR-0006 Decision).
- Code in `src/networking/`; VERSION 9 stays in `src/legacy/net/` untouched.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 044: events and `RaceConfig`.
- Story 048: `NetLink`.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/networking/snapshot_codec.gd` (new)
- `tests/unit/networking/snapshot_codec_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/networking/snapshot_codec_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-009-core-vehicle-data-and-kart-types.md`
- Unlocks: `production/epics/core-rebuild/story-044-net-event-codec-and-race-config.md`, `production/epics/core-rebuild/story-045-clock-sync.md`, `production/epics/core-rebuild/story-046-remote-kart-view.md`
