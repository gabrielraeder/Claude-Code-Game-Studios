# Epic: Core Rebuild (Phase A)

> **Source**: `docs/architecture/architecture.md` (Rebuild Strategy, Phase A Sequencing), `design/gdd/systems-index.md`
> **Layer**: Foundation / Core
> **Engine**: Godot 4.8-beta3 (GDScript)
> **Governing ADRs**: ADR-0001 (Accepted); ADR-0002 v5.1, ADR-0003 v4, ADR-0004 v3, ADR-0005 v3, ADR-0006 v2.1 (Proposed, awaiting owner acceptance)
> **Numbering**: epic story numbers are not the roadmap item numbers (022 kart physics, 023 course data, 024 Blender pipeline, 025 Castle); each story has a Roadmap step line

## Goal

Rebuild the game's core on the Mario Kart architecture: kart physics against collision meshes with per-triangle surface attributes, separate course data, and a Blender track pipeline. The 2.5D game stays frozen as the playable build and the reference. Done when checkpoint A3 is signed: Castle Circuit and Dungeon Depths run on the new core, online with bots, at today's quality or better.

## Scope

Phase A Sequencing in `docs/architecture/architecture.md`: freeze and oracle → collision and Blender round-trip spike → 022 kart physics and driving (A1) → 023 course data → 024 Blender track pipeline → 025 Castle rebuilt (A2) → Dungeon rebuilt, composition root switch (A3).

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | Freeze the 2.5D game and capture the regression oracle | Integration | In Review | ADR-0001 |
| 002 | Core surface and wall-attribute registries | Logic | Blocked | ADR-0002 |
| 003 | TrackCollisionData and CollisionQuery ground casts | Logic | Blocked | ADR-0002 |
| 004 | CollisionQuery wall sweeps | Logic | Blocked | ADR-0002 |
| 005 | Analytic moving colliders | Logic | Blocked | ADR-0002 |
| 006 | Collision load checks, mirror and boundary greps | Logic | Blocked | ADR-0002, ADR-0001 |
| 007 | Collision benchmark (<= 0.3 ms p95, 12 karts) | Integration | Blocked | ADR-0002 |
| 008 | Legacy track extractor and generator-baked test mesh | Integration | Blocked | ADR-0004, ADR-0002, ADR-0005 |
| 009 | Core vehicle data fork, KartIntent and KartSnapshot | Logic | Blocked | ADR-0003 |
| 010 | KartBody ground, ride spring and up | Logic | Blocked | ADR-0003, ADR-0002 |
| 011 | DriveState speed, cap and floor surfaces | Logic | Blocked | ADR-0003 |
| 012 | First-slice budget: KartBody + drive() vs 0.3 ms | Integration | Blocked | ADR-0003 |
| 013 | KartBody wall slide loop and push-out | Logic | Blocked | ADR-0003, ADR-0002 |
| 014 | KartBody wall response: impact, scrape, rebound, turnback | Logic | Blocked | ADR-0003, ADR-0002 |
| 015 | KartBody air: takeoff, landing and hop | Logic | Blocked | ADR-0003, ADR-0002 |
| 016 | DriveState drift start, charge, tiers and release | Logic | Blocked | ADR-0003 |
| 017 | DriveState drift end conditions, air drift and boost merge | Logic | Blocked | ADR-0003 |
| 018 | DriveState hits, slowdown profiles and start boost | Logic | Blocked | ADR-0003 |
| 019 | DriveState trick boost and pads | Logic | Blocked | ADR-0003 |
| 020 | DriveState surface transitions, rubble, determinism and boundary | Logic | Blocked | ADR-0003 |
| 021 | KartBody moving platforms | Logic | Blocked | ADR-0003, ADR-0002 |
| 022 | Kart contact solver: local pairs and broadphase | Logic | Blocked | ADR-0003 |
| 023 | Kart contact solver: remote karts, events, merge and freeze | Logic | Blocked | ADR-0003 |
| 024 | Kart determinism, boundary greps and contact budget | Integration | Blocked | ADR-0003 |
| 025 | Parity harness: trace pilot and frozen-kart noise floor | Integration | Blocked | ADR-0003, ADR-0001 |
| 026 | Parity run: rebuilt kart against the golden traces | Integration | Blocked | ADR-0003, ADR-0004 |
| 027 | Checkpoint A1: owner drift and feel sign-off | Visual/Feel | Blocked | ADR-0003, ADR-0002 |
| 028 | CourseData schema, tuning, build settings and mirror | Logic | Blocked | ADR-0004 |
| 029 | CourseBuilder: gates, key groups and defaults | Logic | Blocked | ADR-0004 |
| 030 | CourseBuilder: routes, spans, respawn and grid checks | Logic | Blocked | ADR-0004 |
| 031 | CourseProgress sector cursor, smoothing, wrong way and off course | Logic | Blocked | ADR-0004 |
| 032 | CourseProgress lap rule, respawn and grid | Logic | Blocked | ADR-0004 |
| 033 | Race ranking, progress determinism and benchmark | Integration | Blocked | ADR-0004 |
| 034 | Generator-course equivalence oracle | Integration | Blocked | ADR-0004 |
| 035 | Mesh track_check | Integration | Blocked | ADR-0004, ADR-0005, ADR-0003 |
| 036 | Track pipeline pins, limits and schema | Integration | Blocked | ADR-0005 |
| 037 | Blender exporter and fixture .glb files | Integration | Blocked | ADR-0005, ADR-0001 |
| 038 | Post-import checks I1-I8 | Logic | Blocked | ADR-0005 |
| 039 | Post-import checks I9-I16 and TrackPackage bake | Logic | Blocked | ADR-0005, ADR-0002, ADR-0004 |
| 040 | TrackLoader and tools/track_build.sh | Integration | Blocked | ADR-0005, ADR-0001 |
| 041 | Fresh-clone import (NV-15) and a Blender test track end to end | Integration | Blocked | ADR-0005 |
| 042 | Castle Circuit .blend bootstrap (legacy consumer 2) | Integration | Blocked | ADR-0005, ADR-0004 |
| 043 | SnapshotCodec VERSION 10 | Logic | Blocked | ADR-0006 |
| 044 | NetEventCodec and RaceConfig | Logic | Blocked | ADR-0006 |
| 045 | ClockSync (min-RTT filter and slew) | Logic | Blocked | ADR-0006, ADR-0001 |
| 046 | RemoteKartView and RemoteKartSet | Logic | Blocked | ADR-0006, ADR-0003 |
| 047 | NetMetrics (TD-010) and NetConfig fork | Logic | Blocked | ADR-0006 |
| 048 | NetLink, events channel and host aggregation | Integration | Blocked | ADR-0006 |
| 049 | Version coexistence and track-package mismatch | Integration | Blocked | ADR-0006 |
| 050 | Castle: race clock, kart registry and tick order | Integration | Blocked | ADR-0001, ADR-0003, ADR-0004 |
| 051 | Castle: laps, ranking and respawn | Integration | Blocked | ADR-0004, ADR-0001 |
| 052 | Castle: track features and hazards | Integration | Blocked | ADR-0002, ADR-0004 |
| 053 | Castle: items | Integration | Blocked | ADR-0004, ADR-0006 |
| 054 | Castle: CPU racers on routes and spans | Integration | Blocked | ADR-0004 |
| 055 | Castle: bot race bar and tick budget | Integration | Blocked | ADR-0004 |
| 056 | Castle: network switch to VERSION 10 | Integration | Blocked | ADR-0006 |
| 057 | Castle: HUD, minimap and race flow port | UI | Blocked | ADR-0004 |
| 058 | Castle: chase camera port | Visual/Feel | Blocked | ADR-0001, ADR-0002 |
| 059 | Castle: kart visuals and race audio port | Visual/Feel | Blocked | ADR-0001, ADR-0003 |
| 060 | Checkpoint A2: Castle Circuit online with bots | Integration | Blocked | ADR-0006, ADR-0003, ADR-0004 |
| 061 | Dungeon Depths .blend bootstrap and import | Integration | Blocked | ADR-0005, ADR-0004 |
| 062 | Dungeon Depths gameplay on the new core | Integration | Blocked | ADR-0004, ADR-0002, ADR-0006 |
| 063 | Composition root switch to the new core | Integration | Blocked | ADR-0001, ADR-0006 |
| 064 | Checkpoint A3: both tracks on the new core | Integration | Blocked | ADR-0003, ADR-0004, ADR-0006 |
| 065 | Retire the frozen 2.5D modules (owner-approved deletion) | Integration | Blocked | ADR-0001, ADR-0004 |
