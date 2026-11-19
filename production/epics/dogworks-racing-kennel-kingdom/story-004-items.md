# Story 004: Five medieval items

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: —

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 3

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From the brief's Goal & fail state and Features item 3:*

- [ ] Item boxes on the track give an item; whoever takes a box announces it so every PC hides it and respawns it.
- [ ] War Horn: a self-boost. Catapult Stone: a wall-bouncing projectile. Cauldron Spill: a slick dropped behind that spins out whoever drives over it.
- [ ] Falcon: homes in on the racer ahead of the user, and can miss or be dodged.
- [ ] Shield of the Realm: blocks one incoming hit, then breaks.
- [ ] A hit spins the victim out for about 1 s. **Only the victim's PC decides a hit**, and tells the others reliably, so nobody spins from something that looked like a miss.
- [ ] Item odds depend on race position and are tuned for 12 racers, with leaders getting weaker items and the back of the pack getting stronger ones. The odds table lives in a data file.
- [ ] Item firing, hits and the shield work for karts on other PCs, checked in a 3-PC race (items fired and hit in both directions with no errors).
- [ ] Item use works with keyboard (E) and controller (LB).

---

## Implementation Notes

- Reference only: `prototypes/kart-net-spike/` (item spawn, `rpc_item_gone`, `rpc_box_taken`, victim-decided hits).
- The firer spawns the item and announces it; every PC simulates it. Items and hits are always reliable.
- The first 3 (Horn, Stone, Spill) are proven in the prototype; build them first, then Falcon and Shield.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 005: bots' item-use decisions.
- Story 007: item HUD icon art and item sounds beyond placeholders.

---

## Files

- `src/items/` (item definitions, odds table, item box)
- `assets/data/items/` (odds and tuning data)
- `production/qa/evidence/story-004-items-evidence.md` (the 3-PC race log)

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/items/` OR a documented playtest (the 3-PC race log)
**Status**: [ ] Not yet created — Test: waived at qa.level minimal

---

## Dependencies

- Depends on: `story-002-online-multiplayer.md`, `story-003-tracks-and-shortcuts.md`
- Unlocks: `story-005-tougher-bots.md`, `story-007-race-flow-hud-sound.md`
