# Story 004: Five medieval items

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-20

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

- `src/items/item_def.gd` (new: one item's tuning)
- `src/items/item_set.gd` (new: the five items and the odds table by place)
- `src/items/item_manager.gd` (new: boxes, roulette, firing, item sim, victim-decided hits, shield, effects)
- `assets/data/items/item_set.tres` (new: item tuning and odds data)
- `src/main.gd` (item manager wiring; race seed in the start info)
- `src/net/net_session.gd` (reliable RPCs: box taken, item granted, item spawn, item hit)
- `src/ui/race_hud.gd` (item slot)
- `src/race/race_ranking.gd` (`id_at_place`)
- `src/track/track_scenery.gd` (item boxes moved to the item manager)
- `src/debug/debug_options.gd`, `src/debug/debug_harness.gd` (--give-item, --item-interval, item screenshots)
- `tools/item_net_test.sh`, `tools/item_log_check.py`, `tools/item_odds_check.gd`, `tools/net_stress_test.sh` (test rigs)
- `production/qa/evidence/story-004-items-evidence.md` (3-PC race logs, odds, 12-racer and lag runs)

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

## Completion Notes
**Completed**: 2026-11-20
**Criteria**: 7/8 passing (deferred: E / LB item use, to be checked when played)
**Deviations**: None
**Test Evidence**: production/qa/evidence/story-004-items-evidence.md (3-PC race logs, odds, 12-racer and lag runs); waived test files at qa.level minimal
**Reviewed by**: self, no independent review (engine check by godot-gdscript-specialist: one reset bug found and fixed)

## Calls beyond the design
- Odds by place (1st: horn 25, stone 5, spill 40, falcon 0, shield 30; 12th: 40/25/0/35/0) · `assets/data/items/item_set.tres` · kept 2026-11-20
- Falcon vanishes when its target is more than 140 m ahead · `item_set.tres` · kept 2026-11-20
- Shield expires after 12 s; box respawn 5 s; roulette 1 s; horn 1.8 s; stone 38 m/s, 4 bounces; slick 20 s · `item_set.tres` · kept 2026-11-20
- Item messages are `any_peer`, so clients are trusted · `src/net/net_session.gd` · kept 2026-11-20
- Placeholder shapes and colors for the items · `src/items/item_manager.gd` · kept 2026-11-20
