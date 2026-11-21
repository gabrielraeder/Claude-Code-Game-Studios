# Story 007: Race flow, HUD and basic sound

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: In Progress
> **Layer**: Presentation
> **Type**: UI
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-20

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 7

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From the brief's Goal & fail state and Features item 7:*

- [ ] Main menu with Host and Join (IP entry), working with keyboard and controller.
- [ ] Lobby: racers see who has joined, and each picks a racer and vehicle; the host picks the track and bot count, then starts the race.
- [ ] Start: a war-horn countdown (the 3-2-1 countdown and start boost are built in story 001; this adds the horn and the lobby sync), then 3 laps. The goal "finish first after 3 laps" works with 1st–12th placing, and there is no fail state.
- [ ] Results screen after the race shows everyone's place and time. The host can start a rematch with one press, back into the lobby or the same setup.
- [ ] HUD: a stream-readable place display (large "1st/12"), lap and lap time, current item, speed, and a minimap showing every racer in their color.
- [ ] UI uses the logo's parchment-banner style, with readable text at 1280×720 and above.
- [ ] Basic sound: engines, drift sparks, boost, item hits, the war-horn countdown, and one music loop. Sound can be muted.
- [ ] A full start-to-rematch loop works for 2+ PCs, with a retained screenshot of each screen (menu, lobby, HUD in a race, results).
- [ ] **Spectators:** a player who joins while a race is running is not kicked. They connect, watch the race (a camera following the leader, with the place list), and are put in the next round when the host starts it. The host's lobby shows who is waiting. (Story 002 currently kicks late joiners; this replaces that.)
- [ ] **Controls menu (added 2026-11-20 at the user's request):** from the main menu, the player can rebind every game action (drive, brake, steer, drift, use item, pause) for keyboard and controller. Pick an action, press the new key or button, and it takes effect at once. A key already used by another action is swapped or flagged, never silently doubled. "Reset to defaults" restores the built-in keys. The bindings are saved per PC and load at every start. The menu itself works with keyboard and controller.

---

## Implementation Notes

- Text is English only.
- Rebinding: the game reads named actions, never keys. All defaults are set in `src/input/input_actions.gd`, so the controls menu only swaps InputMap events and saves them to a file under `user://`. No driving, item or network code changes. The HUD's control hints should show the current bindings, not fixed text.
- The HUD must stay readable on stream: big numbers, high contrast against a busy track.
- The results screen reads ranking from the networked race state (story 002), never from local guesses.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Full audio (music per screen, dog voices, crowd), more languages, cups and championships, split-screen, Steam matchmaking.

---

## Files

- `src/ui/` (menu, lobby, HUD, results, controls menu)
- `src/input/` (saving and loading custom bindings)
- `src/audio/`, `assets/audio/`
- `production/qa/evidence/story-007-*.png` (one screenshot per screen) and `story-007-ui-evidence.md`

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: UI
**Required evidence**: a retained screenshot of each screen touched, in `production/qa/evidence/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `story-002-online-multiplayer.md`, `story-003-tracks-and-shortcuts.md`, `story-004-items.md`, `story-005-tougher-bots.md`, `story-006-racers-and-vehicles.md`
- Unlocks: None
