# Story 063: Composition root switch to the new core

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none (`architecture.md` Phase A Sequencing step 7 is the spec)
**Requirement**: `architecture.md` Phase A Sequencing step 7 (the composition root switches); ADR-0001 §9 (code layout)
**Roadmap step**: `architecture.md` Phase A Sequencing step 7 (Dungeon Depths rebuilt; composition root switch; old modules retired, owner-approved; checkpoint A3). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0001: Simulation Conventions and Code Layout (Accepted); ADR-0006: Network Snapshot for 3D (Accepted)
**ADR Decision Summary**:
- ADR-0001: Godot Y-up, -Z forward, metres; the synced race time is authoritative and the 60 Hz tick follows it with a defined catch-up policy; a fixed step order and one seeded random stream per consumer; our own interpolation with a teleport flag; mirror mode is a proper reflection at track load; the frozen 2.5D game lives in `src/legacy/`, shared data classes in `src/data/`, new code in new folders.
- ADR-0006: Protocol VERSION 10: a quantised 41-byte per-kart record batched by the host; reliable gameplay events on their own channel with an ownership check per event kind; a race config carrying track identity, mirror flag and seed, refused on a mismatch; an NTP-style clock with a min-RTT filter and slew that sets the target tick; a `RemoteKartView` that interpolates, caps extrapolation by time, snaps on a teleport epoch that survives packet loss and reports events once per consumer. `NetMetrics` leaves teleports out of the prediction error (closes TD-010).

**ADR Version**: ADR-0001 2026-11-21; ADR-0006 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Tick settings are pinned (`physics_ticks_per_second=60`, `max_physics_steps_per_frame=8`, `physics_interpolation=false`). Since 4.4 every script has a `.uid` sidecar. 4.8: strings can no longer be comments; a script can no longer inherit its own inner classes. ENet through Godot's multiplayer peer; probes V1, V2, V3 and V5 done (`prototypes/collision-spike/out/`), V4 still to run (Validation 8). Check ENet channel and packet APIs against `docs/engine-reference/godot/` before use.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Main scene.** `run/main_scene` points at the new composition root; the menus select Castle Circuit and Dungeon Depths, mirror on or off, offline and online with bots.
- [ ] **No legacy at runtime.** `tools/core_greps.sh` finds no `src/legacy` reference anywhere under `src/` outside `src/legacy/`, and a launch log shows no `src/legacy/` resource loaded.
- [ ] **Regression.** `tools/regression.sh` runs the new-core checks for both tracks (mesh `track_check`, the new shell-test equivalents, determinism traces) and all PASS; the frozen-oracle lines stay until story 065.
- [ ] **Launch.** The game launches windowed from the new main scene and a race starts; a retained screenshot shows it.

---

## Implementation Notes

> **From story 006:** build collision only through `CollisionBootCheck.checked_query(data, surfaces, walls, probe_max_drop)` (it runs the load check and disposes on failure; `core_greps.sh` forbids a bare `CollisionQuery.new(` outside it), and call `CollisionBootCheck.assert_boot_settings()` at boot, refusing to start on a non-empty result (release builds strip the assert).

- Frozen code stays on disk until the owner approves deletion (story 065).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 065: deleting `src/legacy/`.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `project.godot` (`run/main_scene`)
- `src/race_main.tscn`, menu scenes
- `tools/regression.sh` (new-core lines)
- `production/qa/evidence/core-rebuild-story-063/` (log, screenshot)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: the integration run named in the criteria; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-063/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-062-dungeon-gameplay-rebuild.md`
- Unlocks: `production/epics/core-rebuild/story-064-checkpoint-a3-signoff.md`
