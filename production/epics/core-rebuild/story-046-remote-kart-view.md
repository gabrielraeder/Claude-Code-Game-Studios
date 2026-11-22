# Story 046: RemoteKartView and RemoteKartSet

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none (Network Session & Sync has no GDD yet; ADR-0006 is the spec)
**Requirement**: ADR-0006 Validation Criteria 4; ADR-0003 (`contact_eligible`)
**Roadmap step**: `architecture.md` Phase A Sequencing step 6 (roadmap item 025, network sub-story; ADR-0006 Migration Plan step 2). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0006: Network Snapshot for 3D (Accepted); ADR-0003: Kart Physics Model (Accepted)
**ADR Decision Summary**:
- ADR-0006: Protocol VERSION 10: a quantised 41-byte per-kart record batched by the host; reliable gameplay events on their own channel with an ownership check per event kind; a race config carrying track identity, mirror flag and seed, refused on a mismatch; an NTP-style clock with a min-RTT filter and slew that sets the target tick; a `RemoteKartView` that interpolates, caps extrapolation by time, snaps on a teleport epoch that survives packet loss and reports events once per consumer. `NetMetrics` leaves teleports out of the prediction error (closes TD-010).
- ADR-0003: A custom kinematic `KartBody` (RefCounted, Core) is given a `KartIntent` each tick by the Gameplay-layer `DriveState` control law: a wall slide loop capped at 3 sweeps with bounded overlap push-out, then 2 to 4 ground rays, a single damped ride spring, and up from a smoothed normal; kart-vs-kart contact behind a course-distance broadphase with the snapshot written after contact; moving platforms carried by pose delta; lap-time parity measured above the harness's own noise floor. `CharacterBody3D` and `RigidBody3D` are rejected.

**ADR Version**: ADR-0006 2026-11-22; ADR-0003 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: ENet through Godot's multiplayer peer; probes V1, V2, V3 and V5 done (`prototypes/collision-spike/out/`), V4 still to run (Validation 8). Check ENet channel and packet APIs against `docs/engine-reference/godot/` before use. Verified on 4.8-beta3 by probes: rest geometry is exact for faces and edges, but `PhysicsGetRestInfoResult3D` has no depth field (depth is computed, §6); the cast is blind from an overlapped start, so `sweep_walls` returns at once on `started_inside`; a `Basis` rebuilt from up and heading stays orthonormal without `orthonormalized()`; `Geometry3D.get_closest_points_between_segments` allocates (88 B per call), so use the GDScript helper; no per-space step method exists.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Interpolate and cap.** The interpolation midpoint is correct; extrapolation stops at 0.25 s; contact eligibility drops at 0.1 s of extrapolation and when STALE or EMPTY (ADR-0006 Validation 4).
- [ ] **Teleport epoch.** An epoch change holds, then snaps, even when the flagged record was dropped; the first record is a teleport; `clear()` resets the epoch baselines (ADR-0006 Validation 4).
- [ ] **Events once.** A record's events are reported exactly once to SIM and once to PRESENTATION, including when one sample passes three records (ADR-0006 Validation 4).
- [ ] **Ordering.** Duplicate and older ticks are ignored (ADR-0006 Validation 4).

---

## Implementation Notes

- `RemoteKartSet.sample_into(snaps, t)` uses the SIM cursor and fills `contact_eligible` for the contact solver (ADR-0003 v4 tick order; story 023).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 047: `NetMetrics`.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `src/networking/remote_kart_view.gd`, `src/networking/remote_kart_set.gd` (new)
- `tests/unit/networking/remote_kart_view_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/networking/remote_kart_view_test.gd` — must exist and pass, with at least one test per acceptance criterion (`qa.level: full`)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-043-snapshot-codec-v10.md`
- Unlocks: `production/epics/core-rebuild/story-047-net-metrics-and-net-config.md`
