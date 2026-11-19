# Story 002: Online host/join for up to 12 racers

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Complete
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

*Added after the user's first play (2026-11-19):*

- [ ] Karts bump each other online: each PC pushes only the karts it owns out of every kart it sees, using weight-class data from the user's notes (`C:\rea\reverse-engineer\docs\design\01-veiculos-e-fisica.md` section 2.2): push strength light 0.5 / medium 1.0 / heavy 1.5, speed lost in a full bump 0.9 / 0.5 / 0.1. The armored cart is heavy. Bots push humans at ×0.35 (the notes' AI weight). All values in data.
- [ ] Every kart has its slot's color on every PC (the client saw both karts red).
- [ ] A "Back to menu" button leaves an online race or lobby (or abandons a solo race) for the start screen.

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

## Completion Notes
**Completed**: 2026-11-19
**Criteria**: 12/12 passing (no deferred items)
**Deviations**: ADVISORY — late joiners are connected and then kicked (spectating moved to story 007); IPv6 addresses are not supported; debug options and drivers (`--ram`, `--park`, `--port`, `--autopilot`, stress and bump scripts) live in `src/debug/` and `tools/`. The last two are logged as TD-002 and TD-003.
**Test Evidence**: waived at qa.level minimal; stress-run logs, bump-rig runs and screenshots in `production/qa/evidence/story-002-online-multiplayer/`
**Reviewed by**: self, no independent review

## Calls beyond the design
- Menu words: Host, IP field defaulting to 127.0.0.1, Join, "Start race", "Back to menu"; Restart hidden online (`src/ui/pause_menu.gd`) · kept 2026-11-19
- Start grid in 2 columns, 8 m between rows, 2.5 m sideways; default 2 players and 2 bots; bots also get start boosts (`assets/data/net/net_config.tres`) · kept 2026-11-19
- Kart color palette by slot, the same on every PC (`net_config.tres`, `src/main.gd`) · kept 2026-11-19
- Finish wait 3 s (30 s cap); late joiners kicked (`src/main.gd`, `net_config.tres`) · kept 2026-11-19
- Ranking: a kart must lead by 1 m for 0.5 s to pass; finish order by race clock at the line; finished karts keep their place if their player leaves (`src/race/race_ranking.gd`, `src/main.gd`) · kept 2026-11-19
- Bumping: capsule bodies 1.7 m x 2.7 m, knock fades over about 0.3 s, remote karts drawn overlapping are nudged apart on screen, values from the user's notes (`armored_cart.tres`, `src/vehicle/kart_sim.gd`) · kept 2026-11-19
