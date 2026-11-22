# Systems Index: Dogworks Racing: Kennel Kingdom

> **Status**: Draft v2 (gates run 2026-11-21: TD-SYSTEM-BOUNDARY CONCERNS, PR-SCOPE OPTIMISTIC, CD-SYSTEMS CONCERNS; applied below, three owner decisions open)
> **Created**: 2026-11-21
> **Last Updated**: 2026-11-21
> **Source Concept**: design/gdd/game-concept.md

---

## Overview

Dogworks Racing is an online arcade kart racer for up to 12 friends (Pillar 1),
where drifting, lines and shortcuts decide the race (Pillar 2), built to Mario
Kart-grade quality (Pillar 3) in an original knight-dog medieval kingdom
(Pillar 4). Stories 001-011 built the core loop on a 2.5D spline model. On
2026-11-21 the owner chose Mario Kart's architecture as the base for everything
that follows: **kart physics against collision meshes whose triangles carry
surface attributes (like MK's KCL), separate course data for checkpoints,
routes and respawns (like MK's KMP), and a Blender pipeline for tracks,
characters, karts and props.** So the index has three kinds of systems:

- **The new foundation (Phase A):** Track Collision & Surface Attributes, Course
  Data, Kart Physics, Blender Track Pipeline, Blender Asset Pipeline. Nearly every
  gameplay system reads the track through these, which is why they are designed
  first and carry the highest risk.
- **Built systems that move onto the new base:** driving and drift, items, bots,
  hazards, track features, lap and position, respawn, race flow, HUD, audio,
  online. Their GDDs are written as reverse-documented specs of the shipped
  behaviour, plus what changes on the new base (routes from Course Data instead
  of the spline, surfaces from triangles instead of zone polygons).
- **The approved roadmap (Phase B and later):** anti-gravity and wall-riding,
  turbo reserve, per-dog super specials, Grand Prix with cc classes, mirror and
  200cc, CPU difficulty, team racing, elimination race, kart customization,
  accessibility assists, look-back camera, more items, room codes, and the
  replanned track-feature stories (010, 012-020). Battle and adventure modes come
  last.

**Tier mapping for this project.** *MVP* = the core loop running on the new
foundation (Phase A done: Castle and Dungeon migrated, every built system
working again at today's quality or better). *Vertical Slice* = one cup-quality
track experience with the presentation layer at Mario Kart grade (graphics pass,
dog animation and expressions, living scenery). *Alpha* = every Phase B feature
designed and landed one at a time to the quality bar ("rough" means internal work in progress, never signed off as done; Pillar 3), in two ordered waves: Alpha-1 (Pillars 1 and 2: anti-gravity hook, turbo reserve, CPU difficulty, time trials and ghosts, room codes) then Alpha-2 (modes and meta). *Full Vision* = content-complete cups, polish, then
battle and adventure modes.

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | Input & Bindings | Core | MVP | Implemented | — | — |
| 2 | Track Collision & Surface Attributes | Core | MVP | In Review (owner and TD decisions open) | design/gdd/track-collision-and-surfaces.md | — |
| 3 | Course Data (checkpoints, routes, respawns) | Core | MVP | In Review (owner decisions open) | design/gdd/course-data.md | Track Collision & Surface Attributes |
| 4 | Network Session & Sync | Core | MVP | Implemented (migrate: 3D snapshot, wire version bump) | — | — |
| 5 | Blender Asset Pipeline (dogs, karts, props; owner 2026-11-21: after the migration, story 027 follows 025) | Core | Vertical Slice | Not Started | — | — |
| 6 | Kart Physics (mesh collision; body, contact, kart-vs-kart bumps, variable up vector) | Core | MVP | In Review (owner and TD decisions open) | design/gdd/kart-physics.md | Track Collision & Surface Attributes, Input & Bindings |
| 7 | Blender Track Pipeline | Core | MVP | Not Started | — | Track Collision & Surface Attributes, Course Data |
| 8 | Race Session & Synced Clock (inferred) | Core | MVP | Implemented | — | Network Session & Sync |
| 9 | Driving & Drift (control law, drift, boost, surface grip and caps; turbo-reserve rules decided here) | Gameplay | MVP | In Review (reverse-documented; owner decisions D1-D7) | design/gdd/driving-and-drift.md | Kart Physics |
| 10 | Vehicles & Racers Roster | Gameplay | MVP | Implemented (placeholder models) | — | Driving & Drift |
| 11 | Lap & Position Tracking (inferred) | Gameplay | MVP | Implemented (2.5D, migrate) | — | Course Data, Race Session & Synced Clock |
| 12 | Fall & Respawn (inferred) | Gameplay | MVP | Implemented (2.5D, migrate) | — | Course Data, Kart Physics |
| 13 | Track Features (boost pads via Driving; ramps, jumps, cannons via Physics) | Gameplay | MVP | Implemented (2.5D, migrate) | — | Kart Physics, Track Collision & Surface Attributes, Course Data |
| 14 | Track Hazards | Gameplay | MVP | Implemented (2.5D, migrate) | — | Race Session & Synced Clock, Kart Physics, Track Collision & Surface Attributes (dynamic colliders), Fall & Respawn |
| 15 | Items & Item Boxes | Gameplay | MVP | Implemented (2.5D, migrate) | — | Kart Physics, Track Collision & Surface Attributes, Course Data, Lap & Position Tracking, Network Session & Sync |
| 16 | CPU Racers (bots) | Gameplay | MVP | Implemented (2.5D, migrate) | — | Course Data, Driving & Drift, Items & Item Boxes, Track Hazards |
| 17 | Race Flow & Lobby (rematch in one press, running series tally, post-finish spectating) | Gameplay | MVP | Implemented (rematch tally and spectating not started) | — | Race Session & Synced Clock, Lap & Position Tracking, Vehicles & Racers Roster |
| 18 | Chase Camera (incl. look-back) | Core | MVP | Implemented (look-back not started) | — | Kart Physics |
| 19 | Race HUD & Minimap | UI | MVP | Implemented | — | Lap & Position Tracking, Items & Item Boxes, Course Data |
| 20 | Menus & Lobby UI | UI | MVP | Implemented | — | Race Flow & Lobby, Input & Bindings |
| 21 | Race Audio (MVP: today's set; Vertical Slice scope: track themes, final-lap music shift, dog voices — barks on a hit, howl on a win) | Audio | MVP / Vertical Slice | Implemented | — | Driving & Drift, Items & Item Boxes, Track Hazards, Track Collision & Surface Attributes |
| 22 | Settings & Local Save (inferred) | Persistence | MVP | Implemented (bindings only) | — | Input & Bindings |
| 41 | Spectate & Broadcast Presentation (CD-SYSTEMS): name tags and post-finish spectating at MVP; event callouts, final-lap moment, streamer view at Vertical Slice | UI | MVP / Vertical Slice | Not Started | — | Race Flow & Lobby, Lap & Position Tracking, Items & Item Boxes, Chase Camera |
| 23 | Kart & Dog Presentation (animation, expressions, VFX) | UI | Vertical Slice | Partial (placeholder blocks) | — | Blender Asset Pipeline, Driving & Drift, Items & Item Boxes |
| 24 | Track Art & Scenery (graphics pass, living scenery) | UI | Vertical Slice | Partial (generated) | — | Blender Track Pipeline |
| 25 | Slipstream & Pack Racing | Gameplay | Vertical Slice | Not Started (story 013) | — | Kart Physics, Lap & Position Tracking |
| 26 | Air Tricks | Gameplay | Vertical Slice | Not Started (story 014) | — | Kart Physics, Track Features |
| 27 | Anti-Gravity & Wall-Riding (needs its own Kennel Kingdom fiction, e.g. enchanted rune roads; Pillar 4) | Gameplay | Alpha | Not Started (story 026) | — | Kart Physics, Track Collision & Surface Attributes, Chase Camera |
| 28 | Turbo Reserve (yes/no and rules are decided inside the Driving & Drift GDD now, before the feel sign-off; the code can land later) | Gameplay | Alpha | Not Started | — | Driving & Drift |
| 29 | Per-Dog Super Special (must pass the Pillar 2 counterplay test; original, not a copy of Sonic's) | Gameplay | Alpha | Not Started | — | Vehicles & Racers Roster, Items & Item Boxes |
| 30 | CPU Difficulty | Gameplay | Alpha | Not Started | — | CPU Racers |
| 31 | Grand Prix & Speed Classes (cc, mirror, 200cc) | Progression | Alpha | Not Started | — | Race Flow & Lobby, Kart Physics, Course Data |
| 32 | Team Racing | Gameplay | Alpha | Not Started | — | Race Flow & Lobby, Items & Item Boxes, Lap & Position Tracking |
| 33 | Elimination Race | Gameplay | Alpha | Not Started | — | Race Flow & Lobby, Course Data, Lap & Position Tracking |
| 34 | Kart Customization | Progression | Alpha | Not Started | — | Vehicles & Racers Roster, Blender Asset Pipeline, Settings & Local Save |
| 35 | Accessibility Assists (and light first-race onboarding for casual friends) | Meta | Alpha | Not Started | — | Driving & Drift, Course Data |
| 36 | Room Codes & Relay (owner 2026-11-21: moved up, right after Phase A, before the graphics pass) | Core | Vertical Slice | Not Started (story 021) | — | Network Session & Sync |
| 37 | Track Dynamics (lap evolution, weather, set pieces, traffic; every effect a pure function of the synced clock, Pillar 1) | Gameplay | Alpha | Not Started (stories 015-019) | — | Track Hazards, Track Collision & Surface Attributes (dynamic colliders), Race Session & Synced Clock, Track Art & Scenery |
| 38 | Time Trials & Ghosts | Gameplay | Alpha | Not Started (story 020) | — | Race Flow & Lobby, Kart Physics, Settings & Local Save |
| 39 | Battle Mode | Gameplay | Full Vision | Not Started | — | Items & Item Boxes, Kart Physics, Network Session & Sync |
| 40 | Adventure Mode | Narrative | Full Vision | Not Started | — | Race Flow & Lobby, Grand Prix & Speed Classes |

System 41 was added by CD-SYSTEMS (stream readability and spectating had no owner). "More items" and "more tracks (cups)" are content inside Items & Item
Boxes and the Blender Track Pipeline, not separate systems.

---

## Categories

| Category | Description | Typical Systems |
|----------|-------------|-----------------|
| **Core** | Foundation systems everything depends on | Input, track collision, course data, kart physics, network, pipelines, camera |
| **Gameplay** | The systems that make the game fun | Driving and drift, items, bots, hazards, track features, modes |
| **Progression** | How the player grows over time | Grand Prix and speed classes, kart customization |
| **Persistence** | Save state and continuity | Settings and local save |
| **UI** | Player-facing information and presentation | HUD, menus, kart and dog presentation, track art |
| **Audio** | Sound and music systems | Race audio |
| **Narrative** | Story delivery | Adventure mode |
| **Meta** | Systems outside the core loop | Accessibility assists |

---

## Priority Tiers

| Tier | Definition | Target Milestone | Design Urgency |
|------|------------|------------------|----------------|
| **MVP** | The core loop running on the new foundation: Phase A done, Castle and Dungeon migrated, every built system working again. **Rule: the 2.5D build stays playable and releasable on main until checkpoint A3 is signed by the owner** | Phase A complete | Design FIRST |
| **Vertical Slice** | One cup-quality experience: Mario Kart-grade presentation, animation, scenery, pack racing, tricks | Phase A + presentation | Design SECOND |
| **Alpha** | Every Phase B feature designed and landed one at a time to the quality bar (Alpha-1: Pillars 1 and 2 features; Alpha-2: modes and meta) | Phase B complete | Design THIRD |
| **Full Vision** | 3 cups, 12 tracks (owner 2026-11-21) and polish, then battle and adventure modes | Release among friends | Design as needed |

---

## Dependency Map

### Foundation Layer (no dependencies)

1. Track Collision & Surface Attributes — every system that asks "what is under or around the kart" reads it; it replaces the spline query and zone polygons.
2. Input & Bindings — the player's controls, already built.
3. Network Session & Sync — host/join, owner-authoritative karts, wire format.
4. Blender Asset Pipeline — import contract for rigged dogs, karts and props; no runtime dependency.

### Core Layer (depends on foundation)

1. Course Data — depends on: Track Collision & Surface Attributes (checkpoints and respawns sit on the collision surface).
2. Kart Physics — depends on: Track Collision & Surface Attributes, Input & Bindings.
3. Blender Track Pipeline — depends on: Track Collision & Surface Attributes, Course Data (it exports both from one Blender scene).
4. Race Session & Synced Clock — depends on: Network Session & Sync.
5. Chase Camera — depends on: Kart Physics.

### Feature Layer (depends on core)

1. Driving & Drift — depends on: Kart Physics.
2. Lap & Position Tracking — depends on: Course Data, Race Session & Synced Clock.
3. Fall & Respawn — depends on: Course Data, Kart Physics.
4. Track Features — depends on: Kart Physics, Track Collision & Surface Attributes, Course Data.
5. Track Hazards — depends on: Race Session & Synced Clock, Kart Physics, Fall & Respawn.
6. Vehicles & Racers Roster — depends on: Driving & Drift, Blender Asset Pipeline.
7. Items & Item Boxes — depends on: Kart Physics, Course Data, Lap & Position Tracking, Network Session & Sync.
8. CPU Racers — depends on: Course Data, Driving & Drift, Items & Item Boxes, Track Hazards.
9. Race Flow & Lobby — depends on: Race Session & Synced Clock, Lap & Position Tracking, Vehicles & Racers Roster.
10. Slipstream & Pack Racing, Air Tricks, Anti-Gravity & Wall-Riding, Turbo Reserve, Per-Dog Super Special, CPU Difficulty, Grand Prix & Speed Classes, Team Racing, Elimination Race, Time Trials & Ghosts, Track Dynamics, Room Codes & Relay — each on the rows named in the table.

### Presentation Layer (depends on features)

1. Race HUD & Minimap — depends on: Lap & Position Tracking, Items & Item Boxes, Course Data.
2. Menus & Lobby UI — depends on: Race Flow & Lobby, Input & Bindings.
3. Race Audio — depends on: Driving & Drift, Items & Item Boxes, Track Hazards, Track Collision & Surface Attributes.
4. Kart & Dog Presentation — depends on: Blender Asset Pipeline, Driving & Drift, Items & Item Boxes.
5. Track Art & Scenery — depends on: Blender Track Pipeline.

### Polish Layer (depends on everything)

1. Settings & Local Save — depends on: Input & Bindings (and every system with a saved option).
2. Accessibility Assists — depends on: Driving & Drift, Course Data.
3. Kart Customization — depends on: Vehicles & Racers Roster, Blender Asset Pipeline, Settings & Local Save.
4. Battle Mode, Adventure Mode — last.

**Seams (TD-SYSTEM-BOUNDARY, applied):**

- **Track Collision & Surface Attributes** owns the static mesh query plus *dynamic
  colliders* (moving platforms, hazard bodies, gates, set pieces) whose pose is a
  pure function of race time; the time is passed into the query, so the foundation
  stays clock-free. Track Hazards, Track Features and Track Dynamics use it instead of
  inventing their own collision. It owns surface *data* (the per-triangle id); the
  surface *effect* (grip, caps, slick tail) belongs to Driving & Drift. Mirror mode
  (system 31) needs flipped triangle winding, so the format ADR must allow it.
- **Kart Physics vs Driving & Drift:** Physics owns body state, integration, ground
  contact, the variable up vector and collision response, and reports the contact
  triangle's surface id. Driving & Drift owns the control law (acceleration, steering,
  drift, mini-turbo) and how surfaces change grip and speed cap. Track Features splits
  the same way: boost pads go through Driving, ramps and cannons through Physics.
  Vehicle stats: Driving and Physics own the schema, the Roster supplies the values.
- **Kart-vs-kart contact** (bumps, push-apart, received-bump impulses) belongs to Kart
  Physics, with the Network Session's snapshot contract carrying inbound events (bump
  impulses, item hits) as well as outbound state.
- **Course Data → Track Collision** is an authoring and validation dependency (checked
  by track_check), not a runtime one. Both Blender pipelines are tool-layer producers of
  formats owned by Track Collision and Course Data; a pipeline never owns a runtime format.
- Homing targets (the Falcon) come from a racer registry that treats humans and bots
  alike, through Lap & Position Tracking, not from CPU Racers.

**Bottlenecks:** Track Collision & Surface Attributes (14 dependents, direct or
through Kart Physics), Kart Physics (12), Course Data (10). **Leaf systems**
(nothing depends on them): HUD, Menus, Audio, Presentation, Track Art, every
Alpha mode, Battle, Adventure.

---

## Recommended Design Order

| Order | System | Priority | Layer | Agent(s) | Est. Effort |
|-------|--------|----------|-------|----------|-------------|
| 1 | Track Collision & Surface Attributes | MVP | Foundation | engine-programmer, technical-director, game-designer | L |
| 2 | Kart Physics (mesh collision) | MVP | Core | engine-programmer, game-designer, network-programmer | L |
| 3 | Course Data | MVP | Core | game-designer, level-designer, ai-programmer | M |
| 4 | Blender Track Pipeline | MVP | Core | technical-artist, tools-programmer, level-designer | M |
| 5 | Blender Asset Pipeline (after 025) | Vertical Slice | Foundation | technical-artist, art-director | M |
| 6 | Driving & Drift | MVP | Feature | game-designer (reverse-documented + migration) | M |
| 7 | Network Session & Sync | MVP | Foundation | network-programmer (reverse-documented) | M |
| 8 | Race Session & Synced Clock | MVP | Core | network-programmer (reverse-documented) | S |
| 9 | Lap & Position Tracking | MVP | Feature | game-designer | S |
| 10 | Fall & Respawn | MVP | Feature | game-designer | S |
| 11 | Track Features | MVP | Feature | game-designer, level-designer | M |
| 12 | Track Hazards | MVP | Feature | game-designer, level-designer | M |
| 13 | Items & Item Boxes | MVP | Feature | game-designer, systems-designer | M |
| 14 | CPU Racers | MVP | Feature | ai-programmer, game-designer | M |
| 15 | Vehicles & Racers Roster | MVP | Feature | game-designer, systems-designer | S |
| 16 | Race Flow & Lobby | MVP | Feature | game-designer, ux-designer | S |
| 17 | Chase Camera | MVP | Core | game-designer | S |
| 18 | Race HUD & Minimap | MVP | Presentation | ux-designer | S |
| 19 | Menus & Lobby UI | MVP | Presentation | ux-designer | S |
| 20 | Race Audio | MVP | Presentation | audio-director, sound-designer | S |
| 21 | Settings & Local Save | MVP | Polish | game-designer | S |
| 21b | Input & Bindings (reverse-documented, short) | MVP | Foundation | game-designer | S |
| 21c | Spectate & Broadcast Presentation | MVP/Vertical Slice | Presentation | ux-designer, game-designer | S |
| 22-26 | Kart & Dog Presentation, Track Art & Scenery, Slipstream & Pack Racing, Air Tricks | Vertical Slice | Feature/Presentation | art-director, technical-artist, game-designer | M each |
| 27-38 | Alpha rows in table order, Anti-Gravity first (it changes Kart Physics' up vector) | Alpha | Feature/Polish | game-designer, systems-designer | M each |
| 39-40 | Battle Mode, Adventure Mode | Full Vision | Feature | game-designer, narrative-director | L each |

Orders 1-4 are Phase A (stories 022, 023, 024, then 025 after them; story 027, order 5, follows it). Orders 6-21 are
reverse-documented from the shipped code plus the migration delta; they gate
story 025 (migrate Castle and Dungeon) because each must say how it reads the
new foundation.

---

## Circular Dependencies

- **Kart Physics ↔ Network Session & Sync:** the wire carries kart state, and
  remote karts are drawn from it. Resolved by direction: Kart Physics owns the
  state and knows nothing of the network; Network Sync reads and writes it
  through a snapshot contract (today KartWire). Kart Physics' GDD must define
  that snapshot.
- **Kart-contact ownership** is settled above (Kart Physics), so neither it nor the
  network GDD may assume the other handles bumps.
- **Items ↔ CPU Racers:** bots use items, and the Falcon homes on a racer.
  Resolved: Items defines the item contract; CPU Racers consumes it.

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| Kart Physics (mesh collision) | Technical | Rewrites the kart's core; must keep today's drift feel and run 12 karts at 60 fps. **Determinism requirement, stated precisely:** a fixed tick and same-machine reproducibility (same inputs, same run), for tests, logged-run comparison and host bots; NOT bit-exact across machines (karts are owner-authoritative and remote karts are drawn from snapshots; hazards stay cross-machine exact because they are functions of the synced clock). Ghosts record snapshot streams, never replay inputs | **ADR before 022: the physics model.** Recommended: keep a pure RefCounted kinematic KartSim with an injected CollisionQuery interface (rejected: RigidBody3D on Jolt, which cannot be snapshotted cleanly and fights kart feel; CharacterBody3D, which ties the kart to the scene tree). The same ADR picks the query backend (engine ray/shape casts on a ConcavePolygonShape3D, or our own triangle BVH) and **verifies that ray hits return a triangle index under Jolt** (per-triangle attributes depend on it). A spline-backed adapter of the same interface keeps the 2.5D path running until A3. Prototype on a test mesh first, compare with the 2.5D logged runs (lap times within tolerance, 12 karts at 60 fps) |
| Track Collision & Surface Attributes | Technical | Per-triangle attributes from Blender, fast queries for 12 karts, ramps, walls, anti-gravity later | Decide the format in an ADR; test with a Blender-made test track before migrating |
| Blender Track Pipeline | Technical / Scope | Unproven import path for collision, attributes and course data; a slow loop kills track iteration | One round-trip prototype (Blender → Godot → track_check) before any real track |
| Blender Asset Pipeline | Technical / Scope | Rigged, animated dogs and karts: skeleton, animation import, LOD, budget for 12 | Single-dog prototype with idle, steer, hit and win animations |
| Course Data | Design | Bots, items, laps and respawns all move from the spline to authored routes at once | Migrate one consumer at a time behind track_check; keep the spline path until 025 closes |
| Network wire migration | Technical | KartWire packs 2.5D state; 3D state (position, velocity, up vector or basis, grounded) needs a new snapshot and a protocol version bump; no Phase A story covered it | Belongs to story 022 (snapshot contract) and 025 (switch-over); tracked on the Network Session row |
| Anti-Gravity & Wall-Riding | Technical | Changes gravity and the up vector, which Kart Physics must allow from day one | Kart Physics GDD and ADR include a variable up vector |

---

## Phase A checkpoints

**Superseded 2026-11-21 by the owner's decision to rebuild the core** (not migrate it): the
sequencing, the freeze of the 2.5D build at tag `v0.11-2.5d` and the checkpoints A1-A3 now
live in `docs/architecture/architecture.md` (Rebuild Strategy, Phase A Sequencing). The rows
above marked "Implemented (2.5D, migrate)" read as "rebuilt on the new core; the frozen
2.5D code is the reference, and its tuning and data are ported".

---

## Owner decisions on the gate suggestions (2026-11-21)

1. **Friends play session on the current 2.5D build before story 022 closes:** yes. The 2.5D game stays playable on main until A3.
2. **Blender Asset Pipeline (027):** moved after the migration. Phase A order is now 022, 023, 024, 025; 027 follows 025 (Vertical Slice). Blender *tracks* (024) stay in Phase A.
3. **Room Codes & Relay (021):** moved up to Vertical Slice, right after Phase A and before the graphics pass.
4. Cups and tracks: full vision 3 cups / 12 tracks; MVP 1 cup / 4 tracks (owner, 2026-11-21).

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | 41 |
| Design docs started | 4 |
| Design docs reviewed | 0 |
| Design docs approved | 0 |
| MVP systems designed | 0/22 |
| Vertical Slice systems designed | 0/6 |

---

## Next Steps

- [ ] Director gates: TD-SYSTEM-BOUNDARY, PR-SCOPE, CD-SYSTEMS
- [ ] `/create-architecture`, then ADRs for Track Collision, Kart Physics, Course Data, Blender pipelines
- [ ] Design MVP-tier systems in the order above (`/design-system [system-name]`)
- [ ] `/design-review` on each completed GDD
