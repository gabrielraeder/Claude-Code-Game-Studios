# Story 056: Castle: network switch to VERSION 10

> **Epic**: Core Rebuild (Phase A)
> **Status**: Blocked — BLOCKED: ADR-0006 is Proposed (owner acceptance pending)
> **Layer**: Foundation
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none (Network Session & Sync has no GDD yet; ADR-0006 is the spec); `design/gdd/kart-physics.md` (§8 Acceptance Criteria)
**Requirement**: ADR-0006 Migration Plan step 4 (composition root) and Validation Criteria 9 (online run at A2)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025: Castle Circuit rebuilt). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0006: Network Snapshot for 3D (Proposed)
**ADR Decision Summary**: Protocol VERSION 10: a quantised 41-byte per-kart record batched by the host; reliable gameplay events on their own channel with an ownership check per event kind; a race config carrying track identity, mirror flag and seed, refused on a mismatch; an NTP-style clock with a min-RTT filter and slew that sets the target tick; a `RemoteKartView` that interpolates, caps extrapolation by time, snaps on a teleport epoch that survives packet loss and reports events once per consumer. `NetMetrics` leaves teleports out of the prediction error (closes TD-010).

**ADR Version**: ADR-0006 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: ENet through Godot's multiplayer peer; probes V1, V2, V3 and V5 done (`prototypes/collision-spike/out/`), V4 still to run (Validation 8). Check ENet channel and packet APIs against `docs/engine-reference/godot/` before use.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Wiring.** The composition root wires `ClockSync` -> `RaceClock` -> target tick, sends snapshots on send ticks, calls `RemoteKartSet.sample_into` (SIM cursor, `contact_eligible`) in ADR-0003 v4's tick order and clears the views on `race_go` (ADR-0006 Migration Plan step 4).
- [ ] **Online run.** 4 PCs or the net_stress harness, fake lag 75 ms each way (150 ms RTT), 30 ms jitter, 5% loss: |clock err| < 5 ms at every client after 10 s; view delay 0.26 s +/- 0.04 at clients and <= 0.20 s at the host; extrapolated frames < 5% at clients and < 2% at the host; client download 14.8 KB/s +/- 15% and host upload 44.5 KB/s +/- 15% with 3 clients (`NetMetrics`, IPv4) (ADR-0006 Validation 9).
- [ ] **Teleport and degraded.** A moat respawn draws as a snap, not a streak, with no remote bump on the respawned kart (capture retained); at 250 ms RTT the race completes, client extrapolated frames are < 25% and no kart becomes STALE (ADR-0006 Validation 9).
- [ ] **Shell tests.** New-core equivalents of `net_stress_test.sh` and `bump_test.sh` pass.

---

## Implementation Notes

- Port 24690; never kill processes the test did not start.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 060: owner A2 sign-off.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/race_main.gd` (network wiring)
- `tests/integration/networking/castle_online_test.gd` (new)
- `tools/net_stress_core.sh`, `tools/bump_test_core.sh` (new)
- `production/qa/evidence/core-rebuild-story-056/` (metrics, capture)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/networking/castle_online_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-056/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-049-net-coexistence-and-package-mismatch.md`, `production/epics/core-rebuild/story-055-castle-bot-race-and-budget.md`
- Unlocks: `production/epics/core-rebuild/story-057-castle-hud-minimap-race-flow.md`, `production/epics/core-rebuild/story-058-castle-chase-camera.md`, `production/epics/core-rebuild/story-059-castle-kart-visuals-and-audio.md`
