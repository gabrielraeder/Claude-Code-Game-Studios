# Story 010: Graphics pass

> **Epic**: Dogworks Racing: Kennel Kingdom
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Visual/Feel
> **Estimate**: L
> **Build step**: core
> **Manifest Version**: N/A (minimal — no control manifest)
> **Last Updated**: —

## Context

**GDD**: `design/game-brief.md` ("Look and references") and the art bible (`/art-bible`, written before this story)
**Requirement**: Brief "Look and references" (added by the user 2026-11-19: graphics improvement after the gameplay stories, with the look locked first by an art bible)

**ADR Governing Implementation**: N/A (minimal — no ADRs)
**ADR Decision Summary**: N/A (minimal — no ADRs)
**ADR Version**: N/A (minimal — no ADRs)

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: none (no ADR engine-compatibility analysis at minimal)

**Control Manifest Rules (this layer)**: N/A (minimal — no control manifest)

---

## Acceptance Criteria

*From the brief's "Look and references" and the art bible:*

- [ ] The shading style the art bible chooses (for example a cel-shaded look with bold outlines in the DogworksTV logo's style) is applied to the tracks, scenery, karts and racers, from shared materials (not per-object colors scattered in code).
- [ ] Surfaces have texture or pattern where the art bible asks (stone, wood planks, cobbles, grass, water), and water and lava read as liquid (movement or shine).
- [ ] Lighting and post-processing follow the art bible per track (Castle Circuit: bright storybook day; Dungeon Depths: dark stone, warm torchlight, lava glow), with every corner readable.
- [ ] Effects: drift sparks per tier, boost flame and trail, wheel dust, water splash on a moat dunk, item-hit burst (once items exist), all readable on stream.
- [ ] Performance: a 12-racer online race keeps a steady frame rate on the user's PC (the budget is in `.claude/docs/technical-preferences.md`: 60 fps); measured, not assumed.
- [ ] A retained screenshot of each track zone and of each effect, before and after, and the user signs off on the look.

---

## Implementation Notes

- Comes after stories 004 (items), 005 (bots) and 006 (racers and vehicles), before or alongside 007 (race flow, HUD, sound), so art is not redone when gameplay changes.
- Shader work goes to the shader specialist (`specialists.shader` in `project.yaml`).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 006: the racer and vehicle models themselves (this story styles them).
- Story 007: menus and HUD art.
- Story 008: elevation geometry.

---

## Files

- `src/` shared materials and shaders, `assets/` textures and effects
- `production/qa/evidence/story-010-graphics-pass/`

---

## QA Test Cases

*N/A — no qa-lead specs at this tier; implement against the Acceptance Criteria above*

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**: retained before/after screenshots in `production/qa/evidence/story-010-graphics-pass/` + sign-off in `production/qa/evidence/story-010-graphics-pass-evidence.md`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: the art bible (`/art-bible`), `story-004-items.md`, `story-005-tougher-bots.md`, `story-006-racers-and-vehicles.md`
- Unlocks: None
