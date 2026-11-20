# Story 005: Tougher bots

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: In Progress
> **Layer**: Core
> **Type**: Logic
> **Estimate**: M
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: 2026-11-20

## Context

**GDD**: `design/game-brief.md`
**Requirement**: Brief MVP feature 5

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From the brief's Goal & fail state and Features item 5, plus the playtest findings:*

- [ ] Bots follow better racing lines (cutting apexes, using the full road width) and drift through corners where it pays off.
- [ ] Bots use items: the 3 original items at sensible moments, plus Falcon and Shield. Items work for bots on every PC.
- [ ] Bots take at least one shortcut per track where it is safe, and sometimes miss it.
- [ ] Rubber-banding is tuned: the field stays close, but a skilled human can win clearly. All values live in data.
- [ ] In a race with 11 bots on autopilot-free play, a human player is not trivially in first by lap 2, and bots do not get stuck on walls.
- [ ] The host runs all bots and syncs them like remote karts.
- [ ] The user plays against the bots and judges them tougher than prototype 1's.

*Added from the user's play of story 002 (2026-11-19):*

- [ ] Bots have several AI personalities, not one way around the track: each bot mixes different racing lines (inside, outside, wide), different shortcut and drift choices, and different item decisions, so a field of bots drives as a varied mix. Personalities live in data and are assigned per bot.
- [ ] Bots steer around karts ahead instead of driving into them (story 002 tests showed the autopilot-style bots running nose-to-tail on one line and pinning a stopped kart).

---

## Implementation Notes

- Reference only: `prototypes/kart-concept/` bots (rubber-banding, brief-drift rule: drifting whole corners made bots about 2.4× slower, so only drift where it helps).
- Playtest carry-over: bots were too easy.
- Keep the bot AI separate from the kart controller so a bot is just another input source.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Difficulty menu (personalities themselves are in scope, see the criteria added 2026-11-19).
- Story 006: bot racer models.

---

## Files

- `src/ai/bot_driver.gd` (rewritten: racing lines, drift choice, shortcut plans, traffic avoidance, stuck recovery, rubber band, item decisions, safe rail-less decks)
- `src/ai/bot_personality.gd` (new: one personality's knobs)
- `src/ai/bot_set.gd` (new: personalities, bot names, shared bot tuning)
- `src/ai/bot_context.gd` (new: injected race accessors for bots)
- `src/ai/bot_debug.gd` (new, debug only: bot labels, screenshots)
- `assets/data/ai/bot_set.tres` (new: 8 personalities, 16 bot names, all bot tuning)
- `src/items/item_manager.gd` (bots pick up and use items: per-bot slot, shared use path)
- `src/main.gd` (bot wiring, bot names, race seed to bots, --race-seed)
- `tools/bot_race_test.sh`, `tools/bot_sink_batch.sh`, `tools/bot_log_summary.py` (test rigs)
- `production/qa/evidence/story-005-tougher-bots-evidence.md` (race batches, sinks, stuck test, fps)

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/ai/` — must exist and pass
**Status**: [ ] Not yet created — Test: waived at qa.level minimal

---

## Dependencies

- Depends on: `story-003-tracks-and-shortcuts.md`, `story-004-items.md`
- Unlocks: `story-007-race-flow-hud-sound.md`
