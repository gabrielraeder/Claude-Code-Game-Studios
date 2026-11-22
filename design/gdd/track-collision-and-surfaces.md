# Track Collision & Surface Attributes — Design Document

---
**Status**: Reverse-Documented (Draft, pending owner review)
**Source**: `assets/data/surfaces/surface_set.tres`; `src/data/surface_type.gd`; `src/legacy/track/track_mover.gd`; `src/legacy/track/track_branch.gd` (`wall_drag_mult`); `src/legacy/test_track/track_data.gd` (`wall_openings`, `open_edges`); `src/legacy/vehicle/kart_sim.gd` (`_wall_contact`, `_push_off_body`, `_mover_stop`); `src/data/vehicle_stats.gd` (wall and knock-back fields); `assets/data/vehicles/armored_cart.tres`, `war_bike.tres`; `assets/tracks/castle_circuit/castle_circuit.tres`, `assets/tracks/dungeon_depths/dungeon_depths.tres` (movers, surface zones, branches); `design/art/art-bible.md` §4 and §6
**Rebuild contract**: `docs/architecture/adr-0002-collision-backend-and-surface-attributes.md` (v5, Proposed) — the source of truth for backend, layout, ids, movers, queries, touch, mirror and load checks; `docs/architecture/adr-0005-blender-track-pipeline.md` §2 and §5 (import checks I1-I16); `docs/architecture/adr-0003-kart-physics-model.md` §5-§6 (wall response, step-up contract); `docs/architecture/adr-0004-course-data-format.md` (areas and spans, dependency only)
**Date**: 2026-11-22
**Verified By**: pending owner review
**Implementation Status**: Frozen 2.5D game: surfaces are spline zones, walls are spline offsets, movers are `TrackMover` schedules. New core: not started (story 022 builds `CollisionQuery`; story 024 the Blender pipeline)
**Systems index**: row 2 (Track Collision & Surface Attributes)
---

> **Provenance — reverse-documented.**
> Reverse-documented from `src/legacy` and the frozen data at commit HEAD (`59614ff`) on 2026-11-22.
> Every number in this document is copied from the code, a data file or an ADR, and the source is named
> next to it. Derived numbers show their arithmetic. Where the *reason* for a rule or value had to be
> inferred, it is marked **INTENT UNKNOWN**. Values no source states are marked **NOT SOURCED**.
> Nothing marked "proposal" is adopted; those items are listed in **Open decisions for the owner**.
>
> **What this document is for.** The frozen game describes its tracks as a spline with zones; the
> rebuilt core describes them as triangles with an attribute on each (ADR-0002). This document states,
> as design, what the player meets on and beside the road — the surface catalogue, the wall classes, the
> moving colliders — and the authoring rules that keep a Blender track playable. **How a surface
> changes driving (caps, grip, drag, tail) is owned by `design/gdd/driving-and-drift.md` §3.1.7 and
> §4**; this document lists the values and points there, it does not restate the control law.

---

## Summary

Track Collision & Surface Attributes is the foundation every "what is under or around the kart" question
goes through. It holds the track as one-sided triangles in two layers — **ground** (what a kart drives
on, each triangle tagged with a stable surface id) and **walls** (what stops a kart, each group tagged
with a stable wall-attribute id) — plus **movers**, primitive shapes on looping keyframed pose curves.
It answers two queries per kart per tick (ground cast, wall sweep) and one evaluator for movers, and it
owns the two registries (`SurfaceSet`, `WallAttrSet`) whose ids every other system uses. For the player
it is the difference between road, grass, mud and ice, between a wall that grinds and one that
glances, and the drawbridge, barrels, portcullis, lava and ore cart that move on a clock everyone shares.

---

## 1. Overview

A track on the new core is baked from Blender into a `TrackCollisionData` resource (ADR-0005). Its
ground is every drivable or off-road triangle — road, grass, ramps, decks — and each triangle carries a
surface id taken from its Blender material `surf_<name>`. The surface under a kart is the majority of
its wheel probes' surfaces (ADR-0003 §5); Driving & Drift looks up the matching `SurfaceType` and
applies its handling. Walls are separate, one-sided triangles that face the route; each carries a
wall-attribute id from its material `wall_<name>`, which scales how a contact scrapes or bounces. Moving
hazards and platforms are not physics bodies: each is a box, capsule or cylinder whose pose is a pure
function of race time, so every PC, the simulation, the hazard effects and the visuals all see the same
pose. The surface catalogue the player meets is the frozen one — grass, sand, mud, rubble, shallows,
slick — plus three kinds the new core adds as collision attributes: `road` (id 0), `boost_pad` and
`trick_ramp`. Every track is checked at import (ADR-0005 I1-I16) and at load (probe cast) so a bad
export never reaches a race.

---

## 2. Player Fantasy

*The road tells you what it is before you touch it: green speckle means grass will drag you down,
glossy blue-grey means the cart will skate, a cyan chevron strip means go. A wall you graze at speed
costs you a little; one you hit head-on costs you a lot; and the drawbridge rises on the same beat for
every racer in the lobby.*

- **Primary MDA aesthetic: Challenge** (game-concept rank 2, "racing lines"). Surfaces and walls are the
  terrain of the racing line: off-road is a cost, a shortcut across mud is a gamble, a slick patch is a
  test of control. Movers are timing puzzles (Castle Circuit's drawbridge and portcullis are deliberately
  never closed together, `out_of_phase_with`).
- **Readability (art bible §4, §6):** each surface has one flat ground colour and one low-contrast
  pattern; brown speckle reads as off-road (`surface_type.gd` doc comment); only gameplay objects (item
  boxes, pads, hazards) sit on the road; the track edge keeps a 20% value step from the scenery. A
  player on a compressed stream must be able to name the surface ahead from colour and pattern.
- **Fairness (Pillar 1, online with friends first):** every surface lookup and every mover pose is a
  deterministic function of geometry and synced time (`t = n × SIM_DT`, ADR-0001). A barrel that hits
  you on your screen hit you on everyone's.
- **Pillar 3, Mario Kart-grade quality:** surfaces and pads as per-triangle collision attributes is the
  MK KCL model (ADR-0002); the frozen catalogue is the floor the rebuild must match before it changes.
- **Anti-fantasy (what must never happen):** driving through a wall from behind or from inside it,
  climbing a cliff that looks like a wall, a hazard that strikes with no warning, a surface whose look
  lies about its effect.

---

## 3. Detailed Design

### 3.1 Layers and what the player meets

| Layer | Holds | Player-facing rule | Source |
|---|---|---|---|
| **Ground** (layer 1) | Road, off-road, ramps, decks: one concave shape | Drivable; each triangle has a surface; the kart rides on it | ADR-0002 Geometry layout |
| **Walls** (layer 2) | One-sided wall triangles facing the route, grouped by wall attribute | Stops the kart; how it costs speed depends on angle (Kart Physics) and attribute (§3.3) | ADR-0002; ADR-0003 §5 |
| **Movers** | Box / capsule / cylinder on a looping pose curve; id ≥ 1 | Hit by ground casts (you can ride a deck) and wall sweeps (you can be blocked or pushed) | ADR-0002 Moving colliders |
| **Areas** (not this system) | Oriented boxes: `hazard_static`, `hazard_speed_gated`, `cannon_trigger`, `fall_boundary` | Water, lava, cannons, fall-out | ADR-0004 (dependency only) |

- **Ground rays do not see wall tops, and the wall sweep does not see ground.** Anything that must stop
  a kart is on the wall layer; anything a kart must drive on is ground (ADR-0002 Consequences, Negative).
- **Walls are one-sided.** A wall blocks only from its front, which must face the route (ADR-0005 I9).
  From behind it does not exist.
- **Floor effects are not carried by the hit.** `GroundHit` carries the surface id only; Driving & Drift
  looks the effect up in `SurfaceSet` (ADR-0002 `TrackCollisionData`).

### 3.2 The surface catalogue

#### 3.2.1 Ids and registry (ADR-0002 v5)

- Surface ids are **stable, project-wide, owned by Track Collision**. `SurfaceType` gains
  `@export var id: int = -1` (additive; the frozen game ignores it).
- The core `SurfaceSet` instance lives in `assets/data/core/`. Ids are unique, ≥ 0 and append-only; a
  removed id is never reused; **id 0 = `road`**. The array index is never the id.
- The core instance adds three kinds to the frozen six: **`road`**, **`boost_pad`**, **`trick_ramp`**.
  Pads and ramps are collision attributes (MK KCL style); Course Data derives its `PAD` and `RAMP` spans
  from them (ADR-0004).
- Blender material `surf_<name>` maps to the id registered for `<name>`; an unknown name fails the
  import (ADR-0005 I5). New surfaces are added to the registry first, never invented in Blender.
- **Id assignment — PROPOSAL (Open decision C1):** 0 `road`, 1 `grass`, 2 `sand`, 3 `mud`, 4 `rubble`,
  5 `shallows`, 6 `slick`, 7 `boost_pad`, 8 `trick_ramp`. Only id 0 is fixed by the ADR.

#### 3.2.2 Handling values (frozen, `assets/data/surfaces/surface_set.tres`)

How each field acts on the kart: `driving-and-drift.md` §3.1.2 (cap, drag, decel), §3.1.4 (grip),
§3.1.5 (drift ban), §3.1.7 (tail), §4.1, §4.2, §4.11 (rubble wobble). Cart cap column = Cart
`max_speed` 26.0 m/s (`driving-and-drift.md` AC-1) × `max_speed_frac`.

| Kind | `max_speed_frac` | Cart cap (m/s) | `drag` (1/s) | `grip_mult` | `steer_mult` | `drift_allowed` | `surface_decel` (m/s²) | `boost_ignores` | `tail_time` (s) | `bump_yaw` (rad/s) / `bump_height` (m) |
|---|---|---|---|---|---|---|---|---|---|---|
| grass | 0.55 | 14.3 | 0.6 | 0.80 | 0.90 | false | 14 | true | 0 | 0 / 0 |
| sand | 0.50 | 13.0 | 0.8 | 0.70 | 0.85 | false | 16 | true | 0 | 0 / 0 |
| mud | 0.40 | 10.4 | 1.1 | 0.45 | 0.75 | false | 20 | true | 0 | 0 / 0 |
| rubble | 0.60 | 15.6 | 0.7 | 0.75 | 0.90 | false | 18 | true | 0 | 1.1 / 0.06 (0.8 cycles/m) |
| shallows | 0.75 | 19.5 | 0.3 | 0.85 | 0.90 | **true** | 12 | true | 0 | 0 / 0 |
| slick | 1.00 | 26.0 (no cap) | 0 | **0.35** | 1.00 | **true** | 14 | true | **0.6** | 0 / 0 |
| road (new) | — | — | — | — | — | — | — | — | — | — |
| boost_pad (new) | — | — | — | — | — | — | — | — | — | — |
| trick_ramp (new) | — | — | — | — | — | — | — | — | — | — |

- **Settled speeds** (drag included, full throttle): Cart grass 14.158 m/s, mud 10.211 m/s
  (`driving-and-drift.md` AC-4). Derivation is Driving's (§4.2).
- **The three new kinds behave as the frozen "no surface" branch** — neutral handling, and a slick tail
  keeps counting down over them — because in the frozen game pads and ramps were not surface zones
  (`driving-and-drift.md` §3.1.7 parity rule, E-15, D7). Their `SurfaceType` entries therefore hold the
  field defaults (`max_speed_frac` 1.0, `drag` 0.0, `grip_mult` 1.0, `steer_mult` 1.0,
  `drift_allowed` true, `tail_time` 0.0; `surface_type.gd`). **Caution:** Driving must recognise these
  three by kind, not by `tail_time = 0`, or the §3.1.7 rule "a surface with `tail_time = 0` clears the
  tail at once" would wrongly cut a slick tail on road (Open decision C2).
- **Boost pad strength** (frozen per track: Castle Circuit 1.10 s, Dungeon Depths 0.80 s,
  `TrackData.boost_pad_time`) has no home on the new core yet: `driving-and-drift.md` D5, repeated here as
  Open decision C3 because a per-`SurfaceType` value would erase the per-track difference.
- **Where the frozen catalogue is used:** Castle Circuit — `tourney_turf` grass, `kennel_yard` mud,
  `moat_shallows` shallows, `ale_spill` slick; Dungeon Depths — `cave_rubble_in` and `cave_rubble_out`
  rubble, `cinder_cut` sand, `cistern_slime` slick; `test_surfaces` track — every kind (track `.tres`
  files).
- **Design reading (INTENT UNKNOWN, inferred from the numbers):** the four off-road kinds form a ladder
  of punishment (rubble 0.60 → grass 0.55 → sand 0.50 → mud 0.40 cap) and all forbid drifting, so a
  drift cut across them is impossible; shallows is "mild off-road you can still drift on"; slick is the
  only on-road kind and the only one that costs control instead of speed. Every kind sets
  `boost_ignores = true`, so a boost always carries a kart across — the shortcut gamble.

#### 3.2.3 Visual and audio language (frozen `surface_set.tres`; art bible §4, §6)

Hex values are converted from the `.tres` colours (channel × 255, rounded).

| Kind | Ground | Pattern | Pattern cell / mark (m) | Puff effect | Puff (amount, life s, size m, speed m/s, gravity m/s², spread °, min speed m/s) | Sound |
|---|---|---|---|---|---|---|
| grass | `#6FA05A` (= art bible Meadow Green) | brown speckle `#735C39` | 1.3 / 0.20 | dust | 9, 0.7, 0.28, 2.2, 2.5, 28, 4 | none |
| sand | `#C9AE76` | speckle `#A88F58` | 0.8 / 0.12 | dust | 12, 0.8, 0.30, 2.6, 2.0, 32, 4 | none |
| mud | `#6B4A32` | speckle `#4A3222` | 0.9 / 0.20 | mud | 10, 0.6, 0.30, 2.8, 5.0, 40, 4 | none |
| rubble | `#857D70` | speckle `#5C554B` | 0.7 / 0.14 | gravel | 9, 0.5, 0.20, 3.2, 6.0, 45, 4 | none |
| shallows | `#5FA5C0` | stripe `#EAF4F8` (= art bible moat foam rim) | 2.4 / 0.18 | splash | 14, 0.6, 0.30, 3.5, 9.0, 38, 3 | `surface_splash` on entry, repeated every 0.45 s while moving |
| slick | `#3E4A63`, overlay alpha 0.55, gloss 0.9 | none | — | none | 0 | none |
| boost_pad | cyan `#22E6E0` with white `#FFFFFF` chevrons, emissive (art bible §4) | animated chevrons (colourblind backup) | NOT SOURCED | NOT SOURCED | — | NOT SOURCED |
| trick_ramp | **NOT SOURCED** (no art bible entry) | — | — | — | — | — |

- Per-kart puffs are capped at `SurfaceSet.puff_max_amount` 14.
- **Rules carried to the new core** (art bible §6): one low-contrast tiling pattern per surface, never
  photographic texture; brown speckle = off-road; when a surface looks busy at the chase camera, remove
  its pattern before changing its colour; pads must stay distinguishable from moat water under
  tritanopia (chevrons + glow vs foam rim + wave lines), and the moat is never on the racing line.
- **Frozen-only presentation fields.** `on_road`, `overlay_alpha`, `ground_lift` 0.02, `overlay_lift`
  0.03, `pattern_lift` 0.012, `pattern_max_marks` 2500 and the zone fence (`fence_height` 0.5,
  `fence_thickness` 0.25, colours `#9E7347` / `#F5EBD1`, 3 stripe segments) exist because the frozen
  game draws zones procedurally over a spline road. On the new core the look is Blender art in the
  `Visual` collection; these fields do not drive collision. Whether the procedural look is kept for
  blockout tracks (`kk_render_collision = true`) is Open decision C4.

### 3.3 Wall behaviour classes

The wall response itself — angle of incidence, impact vs scrape, cooldown, slide, turn-back — is Kart
Physics' (ADR-0003 §5 step 3, using the frozen `VehicleStats` wall fields). A wall attribute only
**scales** it. ADR-0002 v5 names the `WallAttr` fields "scrape drag, bounce and opening"; their exact
names and defaults are not yet written. Proposed fields below are marked.

| Class | Player meets | Frozen source | New-core mapping |
|---|---|---|---|
| **Scrape — standard** | Stone walls and fences of every main road. A graze bleeds speed; a hit at ≥ 25° costs up to 60% (Cart) / 70% (Bike) of speed and a 0.25 s slide | `wall_drag_mult` 1.0 on the main road (`track_model.gd`); `VehicleStats` wall fields | `WallAttr` **`scrape_drag_mult` = 1.0** (proposed name), e.g. material `wall_stone` |
| **Scrape — rough** | Narrow rough-stone passages that grind a sliding kart twice as hard | `wall_drag_mult = 2` on Castle Circuit `secret_passage` and Dungeon Depths `mine_rail` (`track_branch.gd`: "rough stone that grinds a kart sliding along it > 1") | `WallAttr` **`scrape_drag_mult` = 2.0**, e.g. `wall_rough` |
| **Bounce** | How hard the kart is knocked off. Frozen: per vehicle only — Cart 1.4, Bike 1.9 ("harder wall bounce", `war_bike_notes.md`); no wall in the frozen game bounces differently | `VehicleStats.bump_knockback` (1 = dead stop, 2 = perfect bounce) | `WallAttr` **`bounce_mult` = 1.0** (proposed) multiplying `bump_knockback` (§4.3). A bumper-style wall (> 1.0) is new design: Open decision C5 |
| **Opening** | A stretch of road edge with no wall, where a kart can drive off onto off-road (frozen: onto a surface zone) or, at a rail-less edge, over a drop into water or a fall | `TrackData.wall_openings` ("stretches of the main road with no wall on one side, where a kart can drive onto a zone"), `open_edges` | **No wall triangles there.** Course Data derives `WALL_OPENING` and `OPEN_EDGE` spans (ADR-0004 §5). What ADR-0002's `WallAttr` "opening" field means is **INTENT UNKNOWN**: Open decision C6 |

- **Frozen wall heights** (presentation, no gameplay effect in 2.5D): branch `wall_height` 1.3 m
  (Castle Circuit), zone fences 0.5 m. On the new core a wall's height is real geometry: it must be at
  least tall enough that the kart's sweep sphere (Cart radius 1.0 m, Bike 0.85 m, centred one radius
  above the contact, ADR-0003 §5) cannot pass over it. Proposed authoring floor: wall top ≥ 2 × radius
  = 2.0 m above the drivable ground in front of it (INTENT — derived, not sourced; Open decision C7).

### 3.4 Moving colliders (movers)

#### 3.4.1 The new mover model (ADR-0002 v5, ADR-0005 §2)

- A mover is a primitive — `BOX` (half extents), `CAPSULE` or `CYLINDER` (radius, `half_height` of the
  segment, axis along Godot local +Y) — with a looping keyframed pose curve: `key_t`, `key_pos`,
  `key_rot` (quaternion), `period`. Position is piecewise linear, rotation is slerp (§4.4).
- Mover ids are ≥ 1; 0 always means static geometry.
- `CollisionQuery` is the **only** evaluator: `mover_pose(id, t)` and `mover_point_velocity(id, t, p)`.
  Simulation (at `t = n × SIM_DT`), Track Hazards and presentation (at the continuous synced time) call
  the same functions. Nobody keeps a second evaluator.
- Ground casts test movers analytically (the nearest of static and mover hits wins), so a kart can ride
  a mover; the hit carries the **point velocity** at the contact, so a kart on a moving deck gets that
  deck's velocity there (ADR-0003 carry and takeoff).
- Wall sweeps test movers analytically too; a mover that moved into a kart sets `started_inside`.
- **What a mover does to a kart (spin, stop, sink, push-off) is not authored with it.** Track Hazards
  maps `kk_mover_id` to a `HazardEffect` in its own data (ADR-0005 §2 Movers). Timing (warning,
  active window) is therefore whatever the Blender action encodes, plus Track Hazards' schedule data.
- Authored in Blender as a `Course` empty, `kk_type = mover`, animated with ordinary keyframes; the
  exporter samples `matrix_world` at every frame and fails on a loop-closure mismatch, on scale ≠ 1 at
  any frame, or on no animation (ADR-0005 §2).

#### 3.4.2 The frozen hazards mapped to the new model

All values from the track `.tres` files and `track_mover.gd` defaults. Shapes and sizes in the "new
model" column are the proposed authoring; the frozen game has no collision shape for most of these (it
tests distances along the spline).

| Hazard (track) | Frozen behaviour | Frozen numbers | New model (proposal) |
|---|---|---|---|
| **Drawbridge deck** (Castle Circuit, branch `drawbridge`) | `gate`: the deck over the moat rises on chains and lowers; while it is up (progress ≥ `block_progress`) a kart reaching it **sinks** into the water and is put back on the main road | `path_from` 65.10 → `path_to` 83.10 (18.0 m deck, hinge at `path_to`), `deck_half_width` 2.5, `raised_angle_deg` 78, `period` 20, `active_start` 12, `active_time` 8, `transition_time` 1.2, `warning_lead` 1.5, `block_progress` 0.25, `hit_effect` sink (water) | `BOX` 5.0 m wide × 18.0 m long × thickness NOT SOURCED, rotating about the hinge edge from 0° to 78° and back. Ground-layer role: drivable when down. Raised behaviour: Open decision C8 |
| **Portcullis** (Castle Circuit, branch `secret_passage`) | `gate`: an iron grille drops in a stone frame across the passage; a kart hitting it is **stopped like a wall** and rolls back at 15% of its speed | `path_from` 19.07 → `path_to` 19.67 (0.6 m thick), `deck_half_width` 2.25, `grille_height` 2.6, `lift_height` 2.8, `period` 20, `active_start` 3.5, `active_time` 5.5, `transition_time` 0.8, `warning_lead` 1.5, `stop_rebound` 0.15, `out_of_phase_with` drawbridge_deck | `BOX` half extents (2.25, 1.3, 0.3), translating along +Y between the road (down) and 2.8 m bottom clearance (up). Acts through the wall sweep as a mover. `stop_rebound` moves to Track Hazards' `HazardEffect` |
| **Barrels ×3** (Castle Circuit, main road) | `barrel`, motion `run`: each waits at `path_from` during the warning (rising out of its cellar, solid only for the last 0.75 s), rolls to `path_to`, then is hidden until the next warning; a hit is a **spin** (profile 1, medium); not solid | `path_from` 446.37 → `path_to` 514.50 (68.13 m), `speed` 9.0, `period` 10, phases 0 / 3.333 / 6.667, lanes +2.6 / −2.6 / 0, `warning_lead` 1.5, `solid_lead` 0.75, `hit_radius` 1.4, `hit_height` 1.5, `body_radius` 0.55, `body_length` 1.1, `appear_distance` 2.0, `min_free_gap` 3.0 | `CYLINDER` radius 0.55, `half_height` 0.55, axis across the road, translating along the route. The hidden phase must be a pose (Open decision C9); the visual roll must not be in the collision keys (§5 E-12, Open decision C10) |
| **Lava bursts ×3** (Dungeon Depths, main road) | `burst`: a vent in the road edge glows during the warning, then a lava column erupts; a kart inside the **footprint** while active is **spun** (profile 1) with a scorch puff | Shore A/B: octagon footprint ≈ 7.39 m across, `vent_radius` 3.4; Bridge: ≈ 5.54 m across, `vent_radius` 2.55; all `column_radius` 1.6, `column_height` 6.0, `period` 7.5, `active_start` 3.0, `active_time` 1.6, `transition_time` 0.35, phases 0 / 2.5 / 5.0, `warning_lead` 1.5, footprint height band 4.0 m (`y_max − y_min`) | `CYLINDER` column, radius NOT DECIDED (column 1.6 m vs footprint ≈ 3.7 m half width), rising out of the vent and sinking back. Must not block or push the kart (frozen: not solid). Open decision C11 (hit volume and solidity) |
| **Ore cart** (Dungeon Depths, branch `mine_rail`) | `cart`, motion `shuttle`: always present and **solid**; goes back and forth, easing in and out, standing at each end for the rest of a half period; a kart touching it is pushed out and loses its into-cart speed like a wall; a closing speed ≥ 4 m/s also **spins** it (profile 2, heavy) | `path_from` 32.13 → `path_to` 49.87 (17.74 m), average `speed` 5.0, `period` 14, `warning_lead` 1.2, `lane_offset` 1.75, `hit_radius` 1.7, `body_radius` 0.65, `cart_width` 1.3, `cart_height` 0.9, `cart_length` 1.9, `spin_min_speed` 4.0, `solid_body` true | `BOX` half extents (0.65, 0.45, 0.95), translating along the rail with the eased shuttle sampled per frame. Solid through the wall sweep; the spin above 4 m/s closing speed is Track Hazards' effect, using `collider_velocity` |

- **Water and lava themselves** (`moat`, `moat_edge`, `moat_bridge`, `lava_shore`, `lava_bridge_l/r`,
  `lava_gap` with `min_cross_speed` 24.0) are static areas, not movers: ADR-0004 `hazard_static` /
  `hazard_speed_gated`, owned by Track Hazards.
- **Warning language** (frozen, kept as a Track Hazards / presentation requirement): an ember ring in
  `color_warn` `#FFBF26` pulsing at `warn_blink_hz` (4.0 default, 3.0 on the bursts) lies where the
  hazard strikes for `warning_lead` before it does; gate lanterns show green / amber / red
  (`track_mover.gd`). This is the art bible's "a hazard never strikes with no warning" made concrete.

### 3.5 Queries and touch semantics (what the player feels)

Full contract: ADR-0002 "Queries per kart per tick". Player-facing consequences:

- **Surface under the kart** = majority surface of the wheel probes (4 for the Cart, 2-3 for the Bike,
  ADR-0003 §5); kept while airborne; starts at 0 (road). Ties are not yet specified (Open decision C12).
- **Walls are swept, not just tested**, so a fast kart cannot pass through a thin wall in one tick. A
  kart that starts a tick inside a wall (7.5% of sampled sweeps in the spike) is reported at once with
  `fraction = 0` and pushed out by Kart Physics; if a static wall and a mover both overlap, the deeper
  one wins.
- **Touch:** a clear move that ends resting against a wall reports `fraction = 1.0`. The kart completes
  its move, does not slide, and the wall response runs as a scrape (ADR-0003 §5 step 4). Driving flush
  along a wall therefore scrapes continuously; it never "sticks".
- **Floor/wall corners** never confuse the two: walls are on their own layer because a combined query
  returns only the floor at a corner (ADR-0002 Verified 10).

### 3.6 Mirror mode

- `TrackCollisionData.mirrored()` builds a **new** object once at load: every vertex x → −x, winding
  flipped, surface and wall-attribute ids kept in face order, mover keys mirrored (M·B·M), probe point
  mirrored. It never mutates the source resource (ADR-0002 Mirror).
- **Collision has no left/right labels.** A surface stays the same surface; walls move with the geometry.
  Left/right data (lanes, `WALL_OPENING` side) lives in Course Data and swaps there (ADR-0004).

### 3.7 Checks that protect the player

| When | Check | What it prevents | Source |
|---|---|---|---|
| Boot | Jolt engine, face-index setting on, physics not on a separate thread | Every surface wrong; non-deterministic queries | ADR-0002 |
| Load | `cast_ground` at `probe_point` returns `probe_surface_id` with `normal.y > 0` | Disabled setting, missing winding flip | ADR-0002 |
| Load | Every id in `surface_of_face` and `wall_attr_ids` exists; ids unique | Unknown surface at runtime | ADR-0002 |
| Import | I4: every vertex and empty within ±2000 m on each axis; collision extent ≥ `min_extent_m` | Float precision loss; cm-unit exports | ADR-0005 I4, ADR-0001 §1 |
| Import | I5: every `surf_` / `wall_` name registered | Invented surfaces | ADR-0005 I5 |
| Import | I6: Ground and Walls transforms are identity (1e-5) | Shifted collision | ADR-0005 I6 |
| Import | I7, I13: mover bases orthonormal, scale 1; mover shape known, size > 0, ≥ 2 keys, times strictly increasing, period > 0, t = 0 key equals node transform | Broken mover curves | ADR-0005 I7, I13 |
| Import | I8: every ground triangle has normal.y > 0 (WARN: degenerate triangles) | Ground invisible to rays | ADR-0005 I8 |
| Import | I9: every wall triangle's front half-space holds a route sample (WARN: nearest sample behind it; \|normal.y\| > `wall_flat_normal_y`) | Walls facing away (passable) | ADR-0005 I9 |
| Import | I11: probe cast on the just-baked data | Same as the load probe, earlier | ADR-0005 I11 |
| Import | I12: ground + wall triangles ≤ 160,000 (WARN > 120,000) | Collision over budget | ADR-0005 I12 |
| Import | I14: no collision nodes | A second collision path | ADR-0005 I14 |
| Import | I16: along every drivable route, a rise > `max_step_up` 0.5 m within one sample, or ground steeper than the slope limit, is on the wall layer | Climbing a cliff; tunnelling a step | ADR-0005 I16, ADR-0003 §5 |

### 3.8 Authoring rules (for track designers and the Blender pipeline)

1. **Ground vs Walls.** Drivable and off-road surfaces, ramps and deck tops are `Ground`; anything that
   must stop a kart is `Walls`. A steep or tall face left on `Ground` fails I16; a drivable top left on
   `Walls` is invisible to the wheels (ADR-0002, ADR-0005 I16).
2. **Max step-up 0.5 m.** A rise taller than 0.5 m between two route samples (spacing 1.0 m,
   `CourseBuildSettings.sample_spacing_m`) must be a wall (`max_step_up` = ADR-0003 `probe_lift`).
3. **Walls are one-sided and face the route** (front toward the road). Never rely on a wall's back.
   `backface_collision` stays false.
4. **Ground winding faces up** (normal.y > 0) everywhere until ADR-0009 (anti-gravity) adds an exemption.
5. **Within ±2 km** of the origin on every axis (ADR-0001 §1). Never rescaled or rotated at import.
6. **One surface per ground triangle, no overlaps.** A frozen "on-road" slick overlay becomes its own
   road-height ground triangles with `surf_slick`, cut into the road, never a second coplanar layer (two
   coplanar triangles make the ray's choice arbitrary; §5 E-9).
7. **Pads and trick ramps are materials** (`surf_boost_pad`, `surf_trick_ramp`), not areas or objects
   (ADR-0005 §2 `area` row).
8. **Collision may be simpler than the visual**, within the visible-gap bound track_check sets
   (ADR-0005 §2, §7).
9. **Movers:** root-level `Course` empties, no scale ever, looping action, visual parented to them; the
   gameplay effect is Track Hazards data, never Blender.
10. **Passages and gaps** a kart must use are at least 2 × kart radius wide plus margin; a traveling
    hazard leaves at least `min_free_gap` 3.0 m of road free (frozen `track_mover.gd` tool rule). The
    passage minimum is **INTENT UNKNOWN** beyond the frozen 3.0 m traveler gap (Open decision C7).
11. **Triangle budget:** ≤ 120,000 collision triangles to stay clear of the warning; 160,000 fails.

---

## 4. Formulas

`SIM_DT = 1/60 s` (ADR-0001; `driving-and-drift.md` §3). Surface formulas for driving (cap, speed update,
grip, wobble) are `driving-and-drift.md` §4.1, §4.2, §4.5, §4.11 and are not repeated.

### 4.1 Surface of a ground hit and of a kart

```
surface_id(hit)  = surface_of_face[face_index]          (static ground)
                 = mover surface (see C13)               (mover hit)
surface_id(kart) = majority( surface_id(hit_k) for k in probes that hit )   while grounded
                 = previous surface_id(kart)                                 while airborne
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `face_index` | int | 0 … triangle count − 1 | Triangle index in `set_faces()` order (ADR-0002 Verified 1) |
| `surface_of_face` | PackedInt32Array | ids ≥ 0 | Baked stable id per ground triangle |
| probes | set | 2-4 rays | Wheel probe points (`ground_probe_points`, ADR-0003 §5) |
| `surface_id(kart)` | int | registered ids | Passed to Driving as `snapshot.surface_id` |

**Output range:** always a registered id (load check). Starts at 0. **Tie:** unspecified (C12).
**Example:** Cart probes hit road, road, grass, grass → 2-2 tie, unresolved today; road, grass, grass,
grass → grass (id 1 under C1).

### 4.2 Wall scrape drag with a wall attribute

```
speed' = speed × (1 − wall_friction_drag × m_angle × scrape_drag_mult × SIM_DT)
m_angle = 1                                                  if angle < scrape_min or angle > scrape_max
        = lerp(scrape_friction_mult, 1, clamp(fade, 0, 1))   otherwise
fade    = 0                                                  if angle ≤ impact_threshold
        = inverse_lerp(impact_threshold, scrape_max, angle)  otherwise
```
(frozen `kart_sim.gd _wall_contact`; ADR-0003 §5 step 3 keeps it and scales it by the attribute)

| Symbol | Type | Range | Description |
|---|---|---|---|
| `speed` | float | 0 – 35.1 m/s (Cart boosted cap) | Speed before the scrape |
| `wall_friction_drag` | float | 0.8 (both vehicles) | Share of speed lost per second while touching |
| `angle` | float | 0° – 90° | Angle between velocity and wall tangent |
| `scrape_min` / `scrape_max` | float | 10° / 40° | Scrape band |
| `impact_threshold` | float | 25° | At or above: impact if cooldown allows (not this formula) |
| `scrape_friction_mult` | float | 0.45 | Drag multiplier inside the band |
| `scrape_drag_mult` | float | ≥ 0; parity 1.0 / 2.0 | Wall attribute (frozen `wall_drag_mult`) |
| `speed'` | float | [0.9733 × speed, speed] at parity | Speed after one tick of scrape |

**Output range:** at parity the per-tick factor is between 1 − 0.8 × 1 × 2.0 / 60 = 0.97333 (rough wall,
outside the band) and 1 − 0.8 × 0.45 × 1.0 / 60 = 0.99400 (standard wall, in the band). **The factor goes
negative** when `wall_friction_drag × m_angle × scrape_drag_mult × SIM_DT > 1`, i.e. `scrape_drag_mult` >
1 / (0.8 × 1 × 1/60) = 75. Bound it: a loader assert `scrape_drag_mult < 75` (structural) or clamp the
factor at 0 (proposal).
**Example:** Cart at 26.0 m/s, 5° graze (below the band, `m_angle` 1): standard wall
26.0 × (1 − 0.8 / 60) = 26.0 × 0.98667 = 25.653 m/s; rough wall 26.0 × (1 − 1.6 / 60) = 25.307 m/s. Held
for 1 s (60 ticks): 26.0 × 0.98667⁶⁰ ≈ 11.6 m/s vs 26.0 × 0.97333⁶⁰ ≈ 5.1 m/s (before Driving's
re-acceleration on the next `drive()`).

### 4.3 Wall bounce with a wall attribute (PROPOSAL)

```
into   = max(velocity · (−n_out), 0)
velocity' = velocity + n_out × into × bump_knockback × bounce_mult
```
(frozen: `velocity -= outward × into_wall × bump_knockback`, `kart_sim.gd` line 732; `bounce_mult` is
the proposed `WallAttr` field)

| Symbol | Type | Range | Description |
|---|---|---|---|
| `n_out` | Vector3 | unit, up-plane | Wall normal toward the route (ADR-0003: projected onto the up plane) |
| `into` | float | ≥ 0 m/s | Velocity component into the wall |
| `bump_knockback` | float | Cart 1.4, Bike 1.9 | Per vehicle: 1 = dead stop, 2 = perfect bounce |
| `bounce_mult` | float | parity 1.0 | Wall attribute |
| `k = bump_knockback × bounce_mult` | float | 1.0 – 2.0 meaningful | Effective restitution + 1 |

**Output range:** outgoing normal speed = `into × (k − 1)`. k < 1 leaves the kart still moving into the
wall (the slide loop then removes it, so the wall feels sticky); k > 2 adds energy (a kart leaves faster
than it hit). Safe `bounce_mult`: Cart [1/1.4, 2/1.4] = [0.714, 1.429]; Bike [1/1.9, 2/1.9] = [0.526,
1.053]. A shared bumper wall at 1.429 would push the Bike to k = 2.715 — over 2 — so a per-wall
bounce must be clamped on k, not on the multiplier (proposal: `k = clamp(bump_knockback × bounce_mult,
1, 2)`).
**Example:** 10 m/s into a standard wall: Cart leaves at 10 × (1.4 − 1) = 4.0 m/s, Bike at
10 × 0.9 = 9.0 m/s outward.

### 4.4 Mover pose and point velocity (ADR-0002)

```
u   = fposmod(t, period)
i   : key_t[i] ≤ u < key_t[i+1]
α   = (u − key_t[i]) / (key_t[i+1] − key_t[i])
pos = lerp(key_pos[i], key_pos[i+1], α)
rot = slerp(key_rot[i], key_rot[i+1], α)
v_lin = (key_pos[i+1] − key_pos[i]) / (key_t[i+1] − key_t[i])
ω     = axis(Δq) × angle(Δq) / (key_t[i+1] − key_t[i]),   Δq = key_rot[i+1] · key_rot[i]⁻¹
v(p)  = v_lin + ω × (p − pos)
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `t` | float | ≥ 0 s | Race time passed in (`n × SIM_DT` in simulation) |
| `period` | float | > 0 s | Loop length (I13) |
| `key_t` | float[] | strictly increasing, ≥ 2 keys | Sample times (every Blender frame) |
| `α` | float | [0, 1) | Segment fraction |
| `v(p)` | Vector3 | unbounded by formula | Point velocity at contact `p` |

**Output range:** pose is always defined (looped). Point velocity grows with distance from the rotation
origin; it is bounded only by authoring. **Example (drawbridge, proposal shape):** 78° in 1.2 s
averages ω = 78 / 1.2 = 65 °/s = 1.134 rad/s; at the deck tip 18.0 m from the hinge,
|v| = 1.134 × 18.0 = 20.4 m/s — close to the Cart's 26.0 m/s top speed, so a kart on a rising deck tip
would be launched hard (feeds Open decision C8).

### 4.5 Mover schedule rules (frozen `track_mover.gd validate()` and track_check)

```
travel   = (path_to − path_from) / speed
run:      travel + warning_lead ≤ period
shuttle:  2 × travel + 2 × warning_lead ≤ period
gate:     active_time + transition_time ≤ period
traveler: solid_lead ≤ warning_lead
shortcut gate: open share ≥ min_open_fraction (0.4); blocked share ≥ min_blocked_fraction (0.2)
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `travel` | float | > 0 s | One run of a traveler |
| `warning_lead` | float | 1.2 – 1.5 s shipped | Warning before a strike |
| `period` | float | 7.5 – 20 s shipped | Cycle |

**Worked checks (shipped data):** barrels 68.13 / 9.0 = 7.570 s; 7.570 + 1.5 = 9.070 ≤ 10 ✓. Ore cart
17.74 / 5.0 = 3.548 s; 2 × 3.548 + 2 × 1.2 = 9.496 ≤ 14 ✓. Drawbridge 8.0 + 1.2 = 9.2 ≤ 20 ✓. Portcullis
5.5 + 0.8 = 6.3 ≤ 20 ✓; its active window 3.5-9.8 s (incl. lowering) never overlaps the drawbridge's
12-20 s (warning from 10.5 s) ✓ `out_of_phase_with`. Bursts 1.6 + 0.35 = 1.95 ≤ 7.5 ✓.
On the new core the timing lives in the Blender action and Track Hazards data; where these checks run
is Open decision C14.

### 4.6 Climbable (I16)

```
FAIL if  (h[j+1] − h[j]) > max_step_up   or   slope(j) > slope_limit,   for ground along any drivable route
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `h[j]` | float | m | Ground height at route sample j (spacing 1.0 m) |
| `max_step_up` | float | 0.5 m | = ADR-0003 `probe_lift` |
| `slope_limit` | float | **NOT SOURCED** | Ground slope limit (Open decision C15) |

**Example:** a 0.4 m kerb over one sample passes; a 0.6 m ledge fails unless its face is on `Walls`.
Over 1.0 m spacing, 0.5 m rise = 26.6° — the step rule alone already forbids anything steeper than
atan(0.5 / 1.0) = 26.57° sustained over a sample, so `slope_limit` matters only if it is set below that.

---

## 5. Edge Cases

| ID | Situation | What happens |
|---|---|---|
| E-1 | Kart airborne | `surface_id` keeps the last grounded value (ADR-0003). Landing re-samples it. |
| E-2 | Probes split 2-2 (Cart) or 1-1 (Bike, 2 probes) between surfaces | **Unspecified today.** Proposal: the surface of the probe nearest the centre of mass, ties to the lower probe index — the same rule ADR-0003 uses for the support (C12). |
| E-3 | Ground ray hits both static ground and a mover deck | Nearest hit wins (ADR-0002). |
| E-4 | Surface id not in `SurfaceSet` at runtime | Unreachable after the load check; Driving's fallback is `driving-and-drift.md` E-16 (treat as road, debug counter, proposal). |
| E-5 | Unknown `surf_` / `wall_` name in Blender | Import FAIL (I5); the track is refused. |
| E-6 | Kart drives onto a wall top | Ground rays do not see wall tops; the wall-top guard (ADR-0003 §6, `|n_h| < 0.3`) skips the push-out; the kart falls to whatever ground is below or into Fall & Respawn. Authoring rule 1 says drivable tops are ground. |
| E-7 | Kart approaches a wall from its back face | The wall does not exist from behind: the kart passes through. I9 refuses walls that face away from every route; a wall reachable from behind by a shortcut route is an authoring error I9 only WARNs about (nearest sample behind). |
| E-8 | Kart starts a tick inside a wall or mover | `sweep_walls` returns at once, `fraction = 0`; Kart Physics pushes out; if static and mover both overlap, the deeper wins (ADR-0002 v5). |
| E-9 | Two coplanar ground triangles with different surfaces | The ray returns either one; surface flickers. Prevented by authoring rule 6; **no import check exists** (follow-up). |
| E-10 | Kart pinned between a moving mover and a static wall (portcullis closing on a kart, cart pushing against a wall) | Deeper overlap wins each sweep; ADR-0003's slide cap (3 sweeps) leaves the kart at the last safe point. Frozen portcullis: "a kart already under the grille goes on to the side its centre is on". Parity of that rule on the new core is **not guaranteed** (C8 also covers the portcullis). |
| E-11 | Kart on the drawbridge deck as it rises | New core: the deck is ground; the kart gets the deck's point velocity (up to ≈ 20.4 m/s at the tip, §4.4) and may be launched. Frozen: the kart sinks once progress ≥ 0.25. Decision C8. |
| E-12 | Barrel collision keys include its visual roll | Point velocity on the cylinder surface would add ω × r = (9.0 / 0.55) × 0.55 = 9.0 m/s, so the top moves at 18 m/s and the bottom at 0: a kart touching the barrel gets a spurious push. Rule: the collision empty translates only; the rolling mesh is a child visual (C10). |
| E-13 | Barrel hidden between runs | MoverDef has no visibility flag: a "hidden" barrel is still a solid shape somewhere. Proposal: park it below the ground (in its cellar) for the hidden part of the period (C9). |
| E-14 | Kart inside a lava burst footprint while it is idle | No effect (frozen: dangerous only while active). The new collider must not block or push either (C11). |
| E-15 | Kart touches the parked ore cart slowly | Pushed out, into-cart speed removed, no spin below 4.0 m/s closing speed (frozen `spin_min_speed`). |
| E-16 | Mirror race | Mirrored data built once at load; surfaces and wall attributes keep their ids; the source `.res` is untouched, so the next non-mirrored race is correct (ADR-0002). |
| E-17 | Vertex beyond 2000 m on any axis | Import FAIL (I4). Never rescaled. |
| E-18 | Degenerate triangles | Import WARN (I8); Jolt drops them and `face_index` stays aligned (Verified 1). |
| E-19 | Ground step 0.5 m exactly | Passes I16 (strict `>`); the kart's probes start `probe_lift` 0.5 m above the contact, so they still see it. |
| E-20 | Late-joining or reconnecting PC | Movers are a pure function of `t`; it sees the same pose with no message. |
| E-21 | Kart slides along a wall at exactly `fraction = 1.0` | Touch: full move, no slide, scrape response (ADR-0003 step 4). |
| E-22 | Slick tail onto a boost pad or trick ramp | Tail keeps counting (`driving-and-drift.md` E-15, D7). Requires Driving to treat the three new kinds by kind (C2). |
| E-23 | Collision triangles between 120,000 and 160,000 | Import WARN (I12); above 160,000 FAIL. |
| E-24 | `scrape_drag_mult` ≥ 75 | Speed factor negative (§4.2). Must be refused by a loader assert or clamped (C5). |

---

## 6. Dependencies

Each system below must name this document in its own GDD when that GDD is written; this table is the
bidirectional record until then. `driving-and-drift.md` §6 already lists this system.

| System | Direction | Contract |
|---|---|---|
| **Kart Physics** (row 6, ADR-0003) | consumed by | `cast_ground` (surface id, normal, collider id, point velocity), `sweep_walls` (wall attr, fraction, `started_inside`), `WallAttrSet` scaling of the wall response. Owns overlap resolution, slide loop, step-up = `probe_lift` 0.5 m. |
| **Driving & Drift** (row 9) | consumed by | `SurfaceSet` by stable id; id 0 = road; new kinds treated as "no surface" (§3.2.2, C2). Pad duration: D5 / C3. |
| **Course Data** (row 3, ADR-0004) | consumed by | Derives `SURFACE`, `PAD`, `RAMP`, `WALL_OPENING`, `OPEN_EDGE` spans and half widths from collision; validates routes inside the road (I15). Owns areas and left/right data. |
| **Blender Track Pipeline** (row 7, ADR-0005) | consumed by | Bakes `TrackCollisionData`; maps `surf_` / `wall_` names to ids; runs I1-I16. |
| **Track Hazards** (row 14) | consumed by | `mover_pose` / `mover_point_velocity`; maps mover id → effect (spin, stop, sink, push-off) and schedule data. Owns water and lava areas. |
| **Track Features** (row 13) | consumed by | `boost_pad` and `trick_ramp` surface kinds; ramps as ground geometry. |
| **Items** (row 15) | consumed by | Projectiles cast against ground and walls; slick-like item spills are Items' own, not ground surfaces (INTENT UNKNOWN for Cauldron Spill). |
| **Fall & Respawn** (row 12) | consumed by | Falls when no ground is found or a `fall_boundary` area is entered; wall-top case E-6. |
| **CPU Racers** (row 16) | indirect | Read Course Data tables only, never `CollisionQuery` (ADR-0004 Constraints). |
| **Grand Prix (mirror)** | consumed by | `mirrored()`. |
| **Presentation / Audio** | consumed by | Surface look, puffs, sounds (`SurfaceType` Look / Puffs / Sound groups); mover visuals parented to mover empties, posed by `mover_pose`. |
| **Simulation conventions** (ADR-0001) | depends on | Axes, units, ±2 km bound, mirror §7, `t = n × SIM_DT`. |
| **Physics engine** (Jolt 5.6.0, Godot 4.8-beta3) | depends on | `PhysicsServer3D`, `_into` queries, face-index setting (ADR-0002 Engine Compatibility). |

---

## 7. Tuning Knobs

`SurfaceType` safe ranges come from its `@export_range` hints; others are structural bounds the rules
need, and anything tighter is a playtest call. Category: **F** feel, **C** curve, **G** gate, **A**
authoring limit.

| Knob | Cat. | Affects | Default / shipped | Safe range | Why |
|---|---|---|---|---|---|
| `SurfaceType.max_speed_frac` | C | surface cap | §3.2.2 | 0.05-1.0 (export range) | effect law: Driving §4.1 |
| `SurfaceType.grip_mult` | F | slide | §3.2.2 | 0.05-2.0 | |
| `SurfaceType.steer_mult` | F | steering | §3.2.2 | 0.1-2.0 | |
| `SurfaceType.drag`, `surface_decel`, `tail_time`, `bump_*` | F/C | see Driving §7 | §3.2.2 | ≥ 0; `surface_decel` > 0 | |
| `SurfaceType.pattern_cell`, `pattern_size` | F | readability | §3.2.3 | `pattern_size` < `pattern_cell` | marks must not merge into a solid fill |
| `SurfaceType.puff_*`, `SurfaceSet.puff_max_amount` | F | feedback | §3.2.3, cap 14 | amount ≤ cap | cosmetic; per-kart particle budget |
| `SurfaceType.repeat_interval` | F | splash sound | 0.45 s (shallows) | ≥ 0; 0 = once on entry | |
| `WallAttr.scrape_drag_mult` (proposed) | F | wall grind | 1.0 standard, 2.0 rough | [0, 75) | ≥ 75 makes §4.2 negative |
| `WallAttr.bounce_mult` (proposed) | F | knock-off strength | 1.0 | effective k in [1, 2] (§4.3) | k > 2 adds energy |
| `max_step_up` (`probe_lift`) | A | what is climbable | 0.5 m | > 0, < wheel-to-body height (NOT SOURCED) | owned by ADR-0003; I16 reads it |
| ground `slope_limit` | A | what is climbable | NOT SOURCED | ≤ 26.57° to matter (§4.6) | C15 |
| `collision_tris_warn` / `_fail` | A | collision budget | 120,000 / 160,000 | fail ≤ 154k-ish measured flat | ADR-0002 measured to 154k |
| `sample_spacing_m` | A | I9 and I16 resolution | 1.0 m | > 0 | owned by Course Data |
| `min_extent_m`, `probe_max_drop_m`, `wall_route_max_dist_m`, `wall_route_max_dy_m`, `wall_flat_normal_y`, `degenerate_area_m2` | A | import checks | NOT SOURCED (in `TrackImportLimits`) | — | ADR-0005 §5 |
| Mover timing (`period`, `warning_lead`, active window, speed) | G | hazard fairness | §3.4.2 | §4.5 rules | encoded in the Blender action + Track Hazards data |
| `min_free_gap` | A | traveler never blocks the road | 3.0 m | ≥ 2 × largest kart radius (2.0 m) | frozen tool rule |
| `min_open_fraction` / `min_blocked_fraction` | G | shortcut gate gamble | 0.4 / 0.2 | sum ≤ 1 | frozen tool rule |
| collision CPU budget | — | frame time | ≤ 0.3 ms p95 / tick, 12 karts | measured 0.06 ms median | ADR-0002 registered budget |

All knobs live in data (`assets/data/core/` on the new core), never as literals in `src/`
(`.claude/rules/tuning-values.md`).

---

## 8. Acceptance Criteria

Functional criteria are gdUnit4 tests in `tests/unit/collision/` against `CollisionQuery` on fixture
meshes, unless stated. Many restate ADR-0002 Validation Criteria as player-facing outcomes.

**Surfaces and ids**
- AC-1: A fixture ground with one triangle per registered kind: `cast_ground` straight down on each
  returns that kind's registered id (not its array index), for a registry with non-contiguous ids.
- AC-2: The core `SurfaceSet` has `road` at id 0, every id unique and ≥ 0, and contains `boost_pad` and
  `trick_ramp`. Loader rejects a duplicate id.
- AC-3: The six frozen kinds in the core `SurfaceSet` carry exactly the handling values of §3.2.2
  (field-by-field compare against `assets/data/surfaces/surface_set.tres`).
- AC-4: Probe majority: 4 probes on road, grass, grass, grass → grass id. 2-2 and 1-1 ties resolve by
  the rule C12 chooses, identically over 1000 repeats.
- AC-5: Airborne kart keeps its last surface id; landing on mud switches to mud on that tick.

**Walls**
- AC-6: A wall triangle with material `wall_rough` mapped to a non-contiguous id: `sweep_walls` returns
  `wall_attr` = that id.
- AC-7: A sphere swept at a wall from its back face passes through; from its front it hits.
- AC-8: Rough wall (2.0) vs standard (1.0), Cart at 26.0 m/s, 5° graze, 1 tick: speeds 25.307 and
  25.653 m/s ± 0.001 (§4.2).
- AC-9: Bounce at parity: 10 m/s into a standard wall → outgoing normal speed 4.0 (Cart) / 9.0 (Bike)
  m/s ± 0.01 (§4.3).
- AC-10: A move ending flush against a wall returns `fraction = 1.0`, `started_inside = false`.
- AC-11: A sweep starting inside a wall returns `started_inside = true`, `fraction = 0`, and runs no cast.

**Movers**
- AC-12: A box mover keyed 0 → 10 m along +X over 2 s: `mover_pose(id, 1.0)` origin x = 5.0 ± 1e-4;
  `mover_pose(id, period + 1.0)` equals `mover_pose(id, 1.0)`.
- AC-13: A mover rotating 90° about +Y in 1 s: `mover_point_velocity` at 2 m from the axis has magnitude
  π/2 × 2 = 3.1416 ± 0.001 m/s.
- AC-14: A mover that moves into a stationary kart's sphere sets `started_inside`.
- AC-15: Simulation and presentation calls at the same `t` return bit-identical poses; no second
  evaluator exists (grep: no pose interpolation of `key_pos` outside `src/core/collision/`).
- AC-16: Each frozen hazard re-authored on the new model passes §4.5 checks with its shipped numbers
  (barrels 9.070 ≤ 10, cart 9.496 ≤ 14, drawbridge and portcullis never blocked together).

**Mirror and checks**
- AC-17: A mirrored fixture returns mirrored hit points (x → −x), the same surface and wall-attr ids,
  and `mirrored()` leaves the source resource unchanged (compare before/after).
- AC-18: Load check fails with the face-index setting off (ADR-0002 procedure).
- AC-19: Importing each of: a vertex at x = 2000.5; an unknown `surf_lava2`; a wall facing away from
  every route; a 0.6 m ground ledge on a route; 160,001 triangles — each refuses the file with the
  matching I4 / I5 / I9 / I16 / I12 line.
- AC-20: Budget (story 022 benchmark): 12 karts, release export, owner's PC, collision ≤ 0.3 ms p95.

**Experiential (owner and playtest)**
- AC-X1 (owner sign-off, with Driving AC-X1): on the baked Castle Circuit and Dungeon Depths, the owner
  drives onto every surface kind and into the standard and rough walls, and signs off that they feel
  like the frozen game. Retained screenshot per surface kind in `production/qa/evidence/`.
- AC-X2 (playtest): shown a still of each surface from the chase camera, playtesters name its kind
  (or "off-road / slick / pad / road") without being told; the owner sets the pass bar. Repeated in a
  colour-vision simulator for the pad vs moat pair.
- AC-X3 (playtest): every mover hazard is seen warning before it strikes; no playtester reports a hit
  "out of nowhere" over a session on each track.

---

## Open decisions for the owner

| ID | Decision | Options | Recommendation |
|---|---|---|---|
| **C1** | **Surface id numbering** | A. 0 road, 1 grass, 2 sand, 3 mud, 4 rubble, 5 shallows, 6 slick, 7 boost_pad, 8 trick_ramp; B. another order (only id 0 is fixed) | A — frozen order, append-only from here. Needs technical-director confirmation (registry owner). |
| **C2** | **How Driving recognises road / pad / ramp** | by kind (explicit "neutral" list); by a new `SurfaceType` flag (e.g. `neutral = true`); by values (fails: `tail_time = 0` would cut a slick tail) | A flag on `SurfaceType`, so a future neutral kind needs no code change. Coordinate with `driving-and-drift.md` D7. |
| **C3** | **Per-track pad strength** (= `driving-and-drift.md` **D5**) | per track (Course/Track data); one value on the `boost_pad` `SurfaceType` (loses 1.10 vs 0.80); several pad kinds (`boost_pad_strong`, …) | Per track, for parity; several pad kinds is the MK-style alternative if the owner wants pads to differ inside one track. |
| C4 | Keep the procedural zone look for blockout tracks | yes (reuse `SurfaceType` Look fields when `kk_render_collision = true`); no (blockouts render flat collision) | Yes — cheap readability for greybox playtests. INTENT UNKNOWN. |
| **C5** | **Wall bounce per wall** | A. per vehicle only (frozen; `bounce_mult` absent); B. `bounce_mult` with k clamped to [1, 2]; C. bumper walls as a distinct class | B at 1.0 everywhere through parity; add bumpers only as new design after A1. |
| **C6** | **What `WallAttr` "opening" means** (ADR-0002 names the field) | A. drop it: an opening is the absence of wall geometry, Course Data derives `WALL_OPENING`; B. a non-solid marker wall that Course Data reads (conflicts with "everything on the wall layer stops a kart") | A; amend ADR-0002's field list. Needs technical-director call. |
| C7 | Minimum wall height and passage width | wall top ≥ 2 × kart radius (2.0 m) and passages ≥ `min_free_gap` 3.0 m (proposed); other values | Proposed values, enforced by track_check later. INTENT UNKNOWN. |
| **C8** | **Drawbridge raised / portcullis closing behaviour on mesh physics** | A. parity: Track Hazards applies sink at progress ≥ 0.25 and the frozen "side of centre" rule for the portcullis; B. physical: the rising deck is a ramp that can launch a kart (≈ 20 m/s at the tip) | A through parity; B is a candidate MK-style feature after A1. |
| C9 | Barrel hidden phase | park the collider below ground in its cellar; add an active flag to `MoverDef` (ADR change) | Park below ground (no ADR change). |
| C10 | Barrel roll in collision keys | collision empty translates only, roll is a child visual (rule); allow roll | Translate only. |
| **C11** | **Lava burst hit volume and solidity** | A. frozen footprint (≈ 7.39 m / 5.54 m octagon) as a non-solid trigger; B. the column (1.6 m radius); and: solid vs trigger needs a flag `MoverDef` lacks | A for parity, with a "trigger" (non-solid) mover kind added to ADR-0002, or the burst authored as an ADR-0004 area switched by Track Hazards' schedule. Technical-director call. |
| C12 | Surface tie-break between probes (2-2 Cart, 1-1 Bike) | nearest centre of mass, ties to lower index (= support rule); keep previous surface; lowest id | Nearest centre of mass (one rule for support and surface). |
| C13 | Surface of a mover's top (a deck you drive on) | always road (id 0); a per-mover surface id in `MoverDef` | Road through parity (frozen decks were road). `MoverDef` has no surface field today. |
| C14 | Where mover schedule checks (§4.5) run on the new core | track_check over the baked keys + Track Hazards data; Track Hazards loader | track_check, so the import refuses an unfair hazard. |
| C15 | Ground slope limit for I16 | a value (≤ 26.57° to matter, §4.6); rely on the step rule alone | Set it with Kart Physics; NOT SOURCED. |

---

## Open Questions and Follow-Up Work

### Flagged Follow-Up Work
- Add an import check for overlapping coplanar ground triangles with different surfaces (E-9).
- Add a loader assert `scrape_drag_mult < 75` (or a clamp) and the k-clamp of §4.3 when `WallAttr` is
  written (E-24).
- Art direction for `trick_ramp` and the boost pad's puff and sound is NOT SOURCED: art-director /
  audio-director to add entries to the art bible §4 and `AudioSet`.
- When Kart Physics, Course Data, Blender Track Pipeline, Track Hazards, Track Features, Items and Fall
  & Respawn GDDs are written, each must reference this document (Dependencies are bidirectional).
- Update `design/gdd/systems-index.md` row 2 to point at this document.

## Version History

| Date | Change | By |
|---|---|---|
| 2026-11-22 | First draft, reverse-documented from `src/legacy` and frozen data at `59614ff`, against ADR-0002 v5 | systems-designer (orchestrated run) |
