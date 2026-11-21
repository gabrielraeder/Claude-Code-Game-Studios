# Story 021: Room codes and relay fallback

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: —

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 8 (added by the user 2026-11-21: "host without needing an IP to connect")

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From the user's request (2026-11-21) and the brief's Intent ("needs 2–12 players", friends join by IP, Tailscale-friendly):*

- [ ] The host gets a short room code (4-5 characters, no look-alike letters or digits) shown in the lobby, and joining by IP still works.
- [ ] The main menu has "Join with a code", working with keyboard and controller (a character picker, no typing needed), and lists the last codes used.
- [ ] A small rendezvous service (a Cloudflare Worker with a Durable Object) registers and looks up rooms: the host renews its entry every few seconds, the room disappears when the host leaves or stops renewing, and the service stores only the host endpoint, game version and player count.
- [ ] Direct path: the host tries to open its port automatically (UPnP) and the joiner connects straight to the published endpoint. The version check from story 007 still applies.
- [ ] Relay fallback: when the direct connection is not up within a few seconds, both sides connect through the relay and the race plays the same. The lobby shows "Direct" or "Relay".
- [ ] A race with 12 racers holds 60 fps on both paths, and the extra delay of the relay is measured and recorded (round trip on direct vs relay).
- [ ] Clear messages for an unknown code, a full room, a different game version and an unreachable service; the player returns to the menu.
- [ ] Abuse limits: codes are hard to guess, lookups are rate-limited per address, and the service address lives in a data file, not in code.
- [ ] The service's source lives in the repository (`tools/rendezvous/`) with deploy notes and a local test mode that needs no internet; checked from two different networks.

---

## Implementation Notes

- The code only says where the host is; the race traffic still has to reach it. Direct first (lowest latency), relay only when direct fails.
- Reuse the version handshake (`src/net/net_handshake.gd`, KartWire.VERSION) so a mismatched build is refused before any RPC, also over the relay.
- The relay must carry the same unreliable snapshots and reliable RPCs the game uses today; measure the added delay before judging it playable.
- The player's connection details are private: the service keeps only what a join needs and drops it when the room closes.
- The Cloudflare service needs the owner's account; the owner does the deploy or approves it.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Steam, a public room list, accounts and playing with strangers (brief: Out of scope, later).

---

## Files

- `src/net/` (room code, rendezvous client, UPnP, relay transport)
- `src/ui/` (code entry, code display in the lobby, path label)
- `assets/data/net/` (service address, timeouts)
- `tools/rendezvous/` (service source, deploy notes, local test mode)
- `production/qa/evidence/story-021-room-codes-evidence.md`

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/room-codes/` OR a documented playtest (a race over direct and over relay, from two networks)
**Status**: [ ] Not yet created — Test: waived at qa.level minimal

---

## Dependencies

- Depends on: `story-002-online-multiplayer.md`, `story-007-race-flow-hud-sound.md`
- Unlocks: None
