# Story 002: Online host/join for up to 12 racers

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: In Progress
> **Layer**: Core
> **Type**: Integration
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-19

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 2

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From the brief's Goal & fail state and Features item 2:*

- [ ] One player hosts and others join by IP over ENet (UDP 24680), up to 12 racers in total. Joining over a Tailscale 100.x address works.
- [ ] Owner-authoritative: each PC simulates its own karts and sends state about 30 times a second (unreliable ordered). Remote karts are interpolated with the adaptive view delay (lateness + 2×jitter + one send interval).
- [ ] The race clock syncs to the host's clock through ping/pong.
- [ ] Remote progress is projected to "now" before ranking, and lead changes are debounced, so shown positions do not flicker.
- [ ] The host owns the bots; the host picks how many, and they fill the empty slots up to 12.
- [ ] Fake-network flags (`--lag`, `--jitter`, `--loss`) exist for testing.
- [ ] A headless 12-player stress test (copies on autopilot) completes a race, with the logged extrapolated-frame share and prediction error recorded in `production/qa/evidence/`.
- [ ] A cross-PC test over Tailscale (laptop on a phone hotspot) completes a race, as in prototype 2.
- [ ] Message handling never errors on a peer that has disconnected.

---

## Implementation Notes

- Reference only: `prototypes/kart-net-spike/` (kart.gd `net_state()`, main.gd RPCs, adaptive delay, ranking projection). Rewrite fresh; never import.
- Prototype 2 tested 4 racers at most. Check bandwidth at 12: the host relays every peer's updates to the others.
- Late joiners are not required; the lobby closes when the race starts.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 004: item hits over the network (the victim decides; built with the items).
- Story 007: the lobby screen, results and rematch UI.
- Host migration, anti-cheat and Steam relay.

---

## Files

- `assets/data/net/net_config.tres`
- `src/ai/bot_driver.gd`
- `src/debug/debug_harness.gd`
- `src/main.gd`
- `src/main.tscn`
- `src/net/kart_wire.gd`
- `src/net/net_config.gd`
- `src/net/net_options.gd`
- `src/net/net_session.gd`
- `src/net/net_stats.gd`
- `src/net/remote_kart.gd`
- `src/race/race_ranking.gd`
- `src/race/racer.gd`
- `src/test_track/lap_counter.gd`
- `src/ui/pause_menu.gd`
- `src/ui/race_hud.gd`
- `tools/net_stress_summary.sh`
- `tools/net_stress_test.sh`
- `production/qa/evidence/story-002-online-multiplayer/` (two-human/ shots and logs; stress-12-final-v6/ = final 12-racer run; stress-6-lag80-final-v3/ = final fake-lag run; earlier stress-* dirs are superseded runs kept for the record)

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/net/` OR a documented playtest (the stress-test log)
**Status**: [ ] Not yet created — Test: waived at qa.level minimal

---

## Dependencies

- Depends on: `story-001-driving-and-drift.md`
- Unlocks: `story-004-items.md`, `story-007-race-flow-hud-sound.md`
