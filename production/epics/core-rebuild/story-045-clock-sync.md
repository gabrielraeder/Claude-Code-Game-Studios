# Story 045: ClockSync (min-RTT filter and slew)

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none (Network Session & Sync has no GDD yet; ADR-0006 is the spec)
**Requirement**: ADR-0006 Validation Criteria 3; ADR-0001 §5 (synced race time is authoritative)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025, network sub-story; ADR-0006 Migration Plan step 2). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0006: Network Snapshot for 3D (Proposed); ADR-0001: Simulation Conventions and Code Layout (Accepted)
**ADR Decision Summary**:
- ADR-0006: Protocol VERSION 10: a quantised 41-byte per-kart record batched by the host; reliable gameplay events on their own channel with an ownership check per event kind; a race config carrying track identity, mirror flag and seed, refused on a mismatch; an NTP-style clock with a min-RTT filter and slew that sets the target tick; a `RemoteKartView` that interpolates, caps extrapolation by time, snaps on a teleport epoch that survives packet loss and reports events once per consumer. `NetMetrics` leaves teleports out of the prediction error (closes TD-010).
- ADR-0001: Godot Y-up, -Z forward, metres; the synced race time is authoritative and the 60 Hz tick follows it with a defined catch-up policy; a fixed step order and one seeded random stream per consumer; our own interpolation with a teleport flag; mirror mode is a proper reflection at track load; the frozen 2.5D game lives in `src/legacy/`, shared data classes in `src/data/`, new code in new folders.

**ADR Version**: ADR-0006 2026-11-22; ADR-0001 2026-11-21

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: ENet through Godot's multiplayer peer; probes V1, V2, V3 and V5 done (`prototypes/collision-spike/out/`), V4 still to run (Validation 8). Check ENet channel and packet APIs against `docs/engine-reference/godot/` before use. Tick settings are pinned (`physics_ticks_per_second=60`, `max_physics_steps_per_frame=8`, `physics_interpolation=false`). Since 4.4 every script has a `.uid` sidecar. 4.8: strings can no longer be comments; a script can no longer inherit its own inner classes.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Converges.** With injected times at 150 ms RTT +/- 30 ms jitter and 5% loss (seeded), |err| < 5 ms within 8 s (ADR-0006 Validation 3).
- [ ] **First sample.** The first sample sets the offset exactly (ADR-0006 Validation 3).
- [ ] **Monotonic and snap.** Race time is monotonic under slew, and a 0.5 s step snaps (ADR-0006 Validation 3).

---

## Implementation Notes

- Times are injected (no real clock in tests); seeded jitter only (determinism rule).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 050: `RaceClock` and the target tick.
- Story 056: wiring ClockSync into the race.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/networking/clock_sync.gd` (new)
- `tests/unit/networking/clock_sync_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/networking/clock_sync_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-043-snapshot-codec-v10.md`
- Unlocks: `production/epics/core-rebuild/story-048-net-link-and-host-aggregation.md`
