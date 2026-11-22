# Epic: Core Rebuild (Phase A)

> **Source**: `docs/architecture/architecture.md` (Rebuild Strategy, Phase A Sequencing), `design/gdd/systems-index.md`
> **Layer**: Foundation / Core
> **Engine**: Godot 4.8-beta3 (GDScript)
> **Governing ADRs**: ADR-0001 (Accepted); ADR-0002…0006 to be written

## Goal

Rebuild the game's core on the Mario Kart architecture: kart physics against collision meshes with per-triangle surface attributes, separate course data, and a Blender track pipeline. The 2.5D game stays frozen as the playable build and the reference. Done when checkpoint A3 is signed: Castle Circuit and Dungeon Depths run on the new core, online with bots, at today's quality or better.

## Scope

Phase A Sequencing in `docs/architecture/architecture.md`: freeze and oracle → collision and Blender round-trip spike → 022 kart physics and driving (A1) → 023 course data → 024 Blender track pipeline → 025 Castle rebuilt (A2) → Dungeon rebuilt, composition root switch (A3).

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | Freeze the 2.5D game and capture the regression oracle | Integration | In Review | ADR-0001 |
