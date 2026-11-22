# Course Data — Design Document

---
**Status**: Draft (level-designer view, partly reverse-documented; pending owner review)
**Source**: `src/legacy/test_track/lap_counter.gd` (`update`, `_pass_forward`, `_pass_backward`, `reset`, `resync`); `src/legacy/test_track/track_model.gd` (checkpoint placement lines 430-432, `respawn_pose`, `limit_progress`); `src/legacy/test_track/track_data.gd` (respawn, fall and progress fields); `src/legacy/vehicle/kart_sim.gd` (`_respawn`, `_start_sinking`, safe-point update in `tick`, `_fell_off`); `src/legacy/main.gd` (grid placement, lines 1121-1123); `assets/data/net/net_config.tres` (`grid_row_spacing`, `grid_lateral`); `assets/data/ai/bot_set.tres` (`shortcut_chance`, `branch_factor`); `assets/tracks/castle_circuit/castle_circuit.tres`, `assets/tracks/dungeon_depths/dungeon_depths.tres` (branches, hazards, surfaces, respawn values); generators `tools/gen_castle_circuit.py`, `tools/gen_dungeon_depths.py`; evidence `production/qa/evidence/story-008-elevation-evidence.md`, `story-009-moving-hazards-evidence.md`
**Rebuild contract**: `docs/architecture/adr-0004-course-data-format.md` (v3, Proposed) — the source of truth for every rule in §3.1-§3.3; `docs/architecture/adr-0005-blender-track-pipeline.md` (Proposed) — the `kk_*` authoring table, curve expansion, auto-gates
**Date**: 2026-11-22
**Verified By**: pending owner review
**Implementation Status**: The frozen 2.5D game answers these questions from one spline (`TrackModel`). The new-core `CourseData` is Not Started (systems-index row 3; story 023 builds it, story 024 the Blender path, story 025 migrates Castle and Dungeon)
**Systems index**: row 3 (Course Data, Core, MVP); authoring side of row 7 (Blender Track Pipeline)
---

> **Provenance — what is decided, what is reverse-documented, what is proposed.**
> Written on 2026-11-22 at commit HEAD (`59614ff`).
> - **§3.1-§3.3 (the course model and its runtime rules)** restate ADR-0004 v3 and ADR-0005 for a track
>   author. Where this document and the ADRs disagree, the ADRs win and this document is wrong.
> - **§3.4 (the frozen tracks)** is reverse-documented. Every number is copied from the named code or
>   data file. Where the *reason* had to be inferred, it is marked **INTENT UNKNOWN**.
> - **§3.5 (authoring rules for the MVP cup)** is the level designer's **proposal**. Each rule is
>   derived from a frozen value or an ADR rule, and the derivation is shown. None is adopted until the
>   owner decides; each one is listed in **Open decisions for the owner**.
>
> **What this document is for.** ADR-0004 says *what the data is*. This document says *how a track is
> designed and authored* so that laps count fairly, shortcuts are legal and worth the risk, a kart
> that falls off comes back somewhere fair, bots find their way, and items have a line to follow — the
> Mario Kart KMP layer (checkpoints, enemy and item routes, respawn points, start positions) on our 3D
> gates.

---

## Summary

Course Data is the invisible layer of a track: checkpoint gates that count laps and measure progress,
routes that bots and homing items follow, respawn poses, the 12-slot start grid, and oriented areas
(hazards, cannon triggers, fall boundaries). A track author places these as `Course`-collection empties
and curves in Blender (ADR-0005); at import, `CourseBuilder` (ADR-0004 §14) checks them against the
track's collision and bakes one binary `CourseData.res`. At run time each kart has a `CourseProgress`
that turns its position into lap, race distance, wrong-way and a safe gate. This document gives the
author's rules: where gates go, which gates are key, how shortcuts are drawn, where respawns sit, and
how the grid is laid out, with the frozen Castle Circuit and Dungeon Depths as the reference.

---

## 1. Overview

A course is a closed `main` route (the lap reference, starting at the line) plus optional `branch`,
`cut`, `cpu` and `item` routes, and a chain of **gates** across the road. Each gate belongs to a
**group** (one stage of the lap; gates on alternative paths at the same stage share a group). Some
groups are **key groups**: every legal path around the lap must cross each key group exactly once, in
order, before a forward crossing of the line (group 0) counts as a lap. Gates link to their next gates,
so a shortcut is simply a second chain of gates that rejoins the first. Every gate names a **respawn**
(or gets the nearest one behind it); a kart that falls or sinks returns to the respawn of the last gate
it passed safely. Twelve explicit **grid poses** stand behind the line. **Areas** mark hazards, cannon
triggers and fall boundaries. Half widths, wall clearances, rail-less edges, surface runs, pads and
ramps along each route are **never authored**: the builder derives them from collision. Mirror mode is
a transform of the same data, built at load. The author's job is to make the gate graph express the
lap the designer intends: a fair lap, legal shortcuts, no illegal cuts.

---

## 2. Player Fantasy

*A knight dog spots a gap in the castle wall, gambles that the portcullis is up, threads the secret
passage and bursts out into the gardens two places higher — and if the gamble fails, the game puts the
dog back on the road a few seconds behind, never stranded and never robbed of a lap it earned.*

- **Primary MDA aesthetics:** **Challenge** (game-concept: "3-tier drift boosts, racing lines") and
  **Discovery** of shortcuts. The course layer is what makes a shortcut *legal* and a cut *illegal*.
- **Autonomy (SDT):** branches turn a lap into choices. The frozen tracks already offer them: 3
  branches on Castle, 4 on Dungeon (§3.4). Each choice must have a readable cost.
- **Competence (SDT):** a skill shortcut (a speed-gated jump, a boost-cut over sand) pays only when it
  is executed well. The course data encodes the requirement (`min_speed`, `min_boost`), so bots and
  humans face the same test.
- **Pillar 2 — Drift is the skill:** "Drifting, racing lines and shortcuts decide the race."
  Shortcuts are part of the skill ceiling, not a lottery. §3.5.3 states the risk/reward rule.
- **Pillar 1 — Online with friends first:** progress, laps and respawns are deterministic functions of
  position and data, computed by each kart's owner and carried on the wire (`lap`, `distance`), so all
  12 PCs agree on the ranking.
- **Pillar 3 — Mario Kart-grade quality:** no illegal cut ever counts a lap, no respawn ever gains
  progress or changes the lap, no respawn drops a kart into a hazard. These are bake checks, not
  hopes (ADR-0004 §9, §13).
- **Pillar 4 — The Kennel Kingdom:** branch types carry medieval names and fiction (drawbridge, secret
  passage, mine rail, lava gap); the data's `branch_type` is where that identity lives for bots.

The course layer is invisible when it works. What the player *feels* is: "I took the risk, and the game
was fair about it."

---

## 3. Detailed Design

Units are metres and seconds. `SIM_DT = 1/60 s` (ADR-0001; see `driving-and-drift.md` §3). Axes and
poses follow ADR-0001 §1-§2: a pose empty's local +Y points along travel and lands in Godot facing −Z.

### 3.1 Course building blocks (ADR-0004 §1-§3, §8-§10)

#### 3.1.1 Gates (checkpoints)

- **What it is.** An oriented quad across the road. Frame: right = basis.x, up = basis.y, travel =
  −basis.z (ADR-0004 §2).
- **How it is authored.** A `checkpoint` empty, `ARROWS` display, scale 1, origin **on the road**, +Y
  along travel, with `kk_index` (unique, contiguous from 0; 0 = the start line), `kk_group`,
  `kk_width` (> 0 m) and `kk_height` (> 0 m) (ADR-0005 §2 table). At least 3 gates per track
  (ADR-0005 §2).
- **Lift.** The builder raises the quad centre by `height/2`, so the quad stands on the road
  (ADR-0004 §3).
- **Optional fields.** `kk_next` (comma list of `kk_index` values; default index + 1, wrapping from the
  last gate to 0), `kk_key` (bool, must agree across the whole group), `kk_respawn` (a respawn
  `kk_index`; default: the nearest respawn behind the gate).
- **What a gate is for.** Two different jobs:
  1. **Resolving progress** (every gate): progress is interpolated between consecutive gates, so gates
     are needed wherever the road bends enough that a straight interpolation would leave the road.
  2. **Enforcing the lap** (key gates only): §3.1.2.

#### 3.1.2 Groups, key groups and next links

- **Group** = one stage of the lap. Gates on alternative paths at the same stage share a group id.
  Group ids are **non-decreasing along every next link**, except at the wrap into group 0 (ADR-0004 §3).
- **Key group** = a group whose gates are `kk_key = true`. Every legal path around the lap must cross
  each key group **exactly once**; the bake checks this on the link graph and FAILs otherwise. Group 0
  (the line) is always a key. Key groups are **authored, never generated** (ADR-0005 §3, auto-gates).
- **Non-key gates** exist only to resolve progress, so a branch may have more or fewer of them than the
  main road over the same stretch (ADR-0004 §3).
- **Next links** make the graph. A fork is a gate with two or more `kk_next` entries; a merge is a gate
  that two chains both link to. Links are evaluated in authored order; when two candidate sectors tie,
  the lowest link index wins (ADR-0004 §4).
- **Sector** (a, k) = the volume between gate a and its k-th next gate b. **Bake rule:** every corner of
  b lies in front of a's plane, and every corner of a lies behind b's plane (ADR-0004 §3). §4.2 turns
  this into a spacing rule an author can apply.

> **Author's reading.** The frozen game had *only* key checkpoints: 9 interior checkpoints, all required
> in order (§3.4.1). The new model separates the two jobs: many cheap non-key gates for smooth progress,
> a few key groups for lap integrity. A shortcut is legal when its gate chain carries every key group
> it bypasses on main (or bypasses no key group at all).

#### 3.1.3 Routes and kinds

Authored as `route_point` empties (`kk_route_kind`, `kk_route`, `kk_index` contiguous from 0 per
route) or as a Blender curve in `Course` that the exporter expands into points (ADR-0005 §2, §3).

| Kind | Purpose | Needs gates? | Header fields that matter |
|---|---|---|---|
| `main` | The lap reference. Exactly one. Always closed, starts at the line; `main` with `kk_closed` false FAILs (ADR-0004 §2) | Yes, the main chain | `kk_lanes` (optional) |
| `branch` | An alternative road: shortcut, lane split, deck | Only if it bypasses a key group, or to keep progress smooth on it | `kk_branch_type` (`shortcut`, `lane_split`, `deck`, …; bots weight by it), `kk_min_speed`, `kk_min_boost` |
| `cut` | An off-road boost-cut line (sand, grass) | No | `kk_min_boost` |
| `cpu` | An authored enemy (bot) line | No | Per point: `kk_hint_no_drift`, `kk_hint_speed_cap`, `kk_hint_lane_hold` (`left`/`right`), `kk_hint_item_hold` |
| `item` | A projectile line for homing items | No | — |

- **Fork and merge** of an open `branch` or `cut` route are derived: the nearest point on any other
  route to its first and last sample, within `CourseBuildSettings.fork_merge_tolerance_m`. **FAIL if
  none is within tolerance** (ADR-0004 §2). Author rule: start and end every branch **on** the parent
  route's line.
- **Derived, never authored:** half widths, wall clearances, `edge_flags` (`WALL`, `OFFROAD`, `DROP`,
  `ROUTE`), spans (`SURFACE`, `HAZARD`, `MOVER`, `RAMP`, `PAD`, `OPEN_EDGE`, `WALL_OPENING`,
  `JUNCTION`), `s_main` (ADR-0004 §2; ADR-0005 §2 table note).
- **Sampling.** The builder re-samples every route at `CourseBuildSettings.sample_spacing_m` (default
  1.0 m). Curve expansion density (`curve_expand_spacing_m`, in `track_schema.json`) only sets how many
  authored points the exporter generates (ADR-0004 §14).

#### 3.1.4 Respawns

- A `respawn` empty (`kk_index` unique), the pose the kart takes: origin on the ground, +Y along travel
  (ADR-0005 §2). At least 1 per track.
- **Per gate (KMP CKPT style).** Each gate uses its `kk_respawn`, or the nearest respawn **behind** it
  (largest respawn `s` ≤ `gate_s`) (ADR-0004 §9).
- **Fallback.** Each respawn has a baked `respawn_fallback`: a respawn on `main` at or behind it (itself
  for main-route respawns). Fall & Respawn uses the fallback when the previous respawn failed (a sink
  within respawn immunity) or the sink was in a speed-gated hazard (ADR-0004 §9; the frozen
  `_repeat_sink` / `_gate_sink` rule, §3.4.3).
- **Bake invariants** (ADR-0004 §9): a respawn's `s` ≤ the `gate_s` of every gate that uses it (never
  gains progress); a respawn never lies across the line from its gates (never changes `lap`); every
  respawn is on road ground, outside hazards and movers' swept volumes.

#### 3.1.5 Start grid

- **Exactly 12** `grid` empties, `kk_slot` 0 … 11, each once; slot 0 is pole (ADR-0004 §10; ADR-0005 §2).
  A generated pattern is future work, not MVP.
- **Bake checks:** every pose is behind gate 0, on road ground, and spaced at least 2 × the largest kart
  radius plus a margin from the others (ADR-0004 §10).
- **Initial progress:** `lap = 0`, `key_next = key_groups.size()`, `distance = s − lap_length`
  (negative). The first forward line crossing gives lap 1 (ADR-0004 §10), as in the frozen game.
- Race Session maps racers to slots (registry order, or the previous result in a Grand Prix).

#### 3.1.6 Item boxes

- An `item_box` empty (`kk_index` unique), origin on the ground, Y = ground normal (ADR-0004 §2;
  ADR-0005 §2). The hover height, odds and respawn time are Items data, not authored here (ADR-0004 §8).
- Each box is baked with the route and the distance along it (`box_route`, `box_along`) for item and
  bot logic.

#### 3.1.7 Areas

An `area` empty is an oriented box (`kk_size_x/y/z`, full size in m, along the empty's Blender local
axes), with `kk_area` one of (ADR-0005 §2; ADR-0004 §2):

| `kk_area` | Meaning | Param |
|---|---|---|
| `hazard_static` | Water, lava: a sink area | `kk_hazard_id` (Track Hazards binding) |
| `hazard_speed_gated` | A gap that sinks a kart crossing slower than a minimum | `kk_min_speed` |
| `cannon_trigger` | Fires a cannon (reserved; `cannon_target_pose` is empty at MVP) | `kk_cannon_id` |
| `fall_boundary` | Below/outside this, the kart has fallen off | — |

Boost pads and trick ramps are **not** areas: they are `surf_boost_pad` / `surf_trick_ramp` ground
materials, and the builder derives their `PAD` / `RAMP` spans (ADR-0005 §2).

#### 3.1.8 Track flags

- `kk_self_crossing` on the `track` empty (default false): set when the course crosses itself **at the
  same height**, so route distance is not a valid contact broadphase key; Kart Physics then tests all
  kart pairs on that track. Story 022's brute-force cross-check catches a track that needs the flag and
  lacks it (ADR-0004 Decision preamble). A bridge over the road (different height) does **not** need it.
  **INTENT UNKNOWN** whether Castle or Dungeon needs it: the generators print a "loop clearance min"
  (`gen_dungeon_depths.py` line 880) but the value is not committed.

### 3.2 Authoring in Blender (ADR-0005 §2-§3)

- **Collection.** Every course empty sits in the `Course` collection. A collection whose name starts
  with `_` is skipped (scratch).
- **Empties.** `ARROWS` display, scale 1 (|s − 1| ≤ 1e-4), transforms never applied (the pose *is* the
  transform). Any other display type FAILs.
- **Properties.** Every `kk_*` key is checked against `src/pipeline/track_schema.json`. An unknown key
  on a known type FAILs, so a misspelt optional field is never silently ignored. `int` fields must be
  integral (|v − round(v)| ≤ 1e-6).
- **Indices.** `kk_index` values are unique per type. ADR-0005's table says gate indices are
  "contiguous from 0"; ADR-0004 §14 says authored indices are "unique but not necessarily contiguous"
  and are mapped to array positions. **Author rule: keep them contiguous anyway** (satisfies both).
- **Curves.** A Blender curve in `Course` with `kk_route_kind`, `kk_route` and the header properties
  is expanded by the exporter into in-memory `route_point` empties. The `.blend` is never changed.
- **Route header.** Header fields go on the route's first point **or** on a `route_header` empty with
  the same `kk_route`, never both (both FAILs).
- **Auto-gates.** `export_track.py --auto-gates <N>` adds a gate every N metres along `main` in memory.
  An authored gate within the same stretch overrides the generated one. Key groups are never generated.
  **Author rule:** use auto-gates for the non-key progress gates on main; author every key gate, every
  branch gate and every gate at a fork or merge by hand.
- **Validation.** `CourseBuilder`'s check lines run at every import (ADR-0005 check I15); any FAIL or
  NOT ASSESSED refuses the file (ADR-0005 §5). `--check` runs the Blender-side checks without exporting.

### 3.3 Runtime behaviour, as the author must picture it (ADR-0004 §4-§7, §11)

#### 3.3.1 Progress

Each tick, after physics, each kart's `CourseProgress` finds where it is between two gates (fraction
t, §4.1) and how far outside the gate corridor it is (§4.1). Crossing a gate forward moves the cursor
to the next sector with the **smallest outside distance** (that is how a kart is assigned to a branch:
by being inside that branch's corridor). Up to `MAX_SECTOR_STEPS` = 8 crossings per tick (a safety
bound, not tuning). Raw lap distance `s` is lerped between the two gates' `gate_s`; race `distance` is
smoothed by the frozen `limit_progress` rule (§4.3).

**Off course.** If the best outside distance exceeds `lost_distance`, the kart is off course: `s` and
`distance` are held and nothing is credited. Later ticks search 2 links around the cursor; failing
that, a full search (rate-limited by `offcourse_search_interval_ticks`, staggered by registry slot).
A full search credits no gate it skipped, **so an illegal jump earns nothing** (ADR-0004 §4).

> **Author consequence.** Gate width and height are the *legal corridor*. Too narrow, and a kart
> drifting wide on a legal line goes off course and freezes on the HUD. Too wide or too tall, and an
> illegal cut across an infield stays "inside" the corridor. §3.5.1 gives the sizing rule.

#### 3.3.2 Laps (ADR-0004 §5, ported from the frozen `LapCounter`)

| Event | Effect |
|---|---|
| Forward across the key group `key_groups[key_next]` | `key_next += 1` |
| Forward across group 0, all keys crossed | `lap += 1`, `line_crossed = +1` |
| Forward across group 0, a key missing | `rejected_crossings += 1`, `invalid_wraps += 1`, `crossing_rejected = true` |
| Either forward crossing of group 0 | `key_next = 0` |
| Backward across group 0 | if `invalid_wraps > 0`: `invalid_wraps −= 1`; else `lap −= 1`, `line_crossed = −1`. Then `key_next = key_groups.size()` |
| Backward across `key_groups[key_next − 1]` | `key_next −= 1` |

Lap & Position owns `max_lap` ("a lap counts only the first time it is reached"), lap times and finish
(frozen `LapCounter._reached_new_lap`). Lap count per race is **not** Course Data: the frozen value is
`lap_count = 3` on both tracks (`castle_circuit.tres`, `dungeon_depths.tres`); on the new core it lives
in the `TrackDef` catalog or Race Flow (INTENT UNKNOWN which; see Open decisions).

#### 3.3.3 Wrong way

Computed from race `distance` only (ADR-0004 §4 step 6): backward movement accumulates `back_run`;
forward travel reduces it and passing `wrong_way_clear` resets it; `wrong_way = back_run ≥
wrong_way_distance`. A kart sliding backwards counts; one turned around but standing still does not.
The two distances are not chosen yet (story 023 sets them, ADR-0004 §2).

#### 3.3.4 Ranking

Finished karts by finish time; the rest by `distance`, descending; ties by `RacerRegistry` slot
(ADR-0004 §5). The frozen equivalent is `(lap − 1) × length + track_s` (`main.gd _rank_key`, per
ADR-0004 Context). Because `distance` on a branch comes from `s_main` (interpolated fork → merge by the
along fraction), a kart on a shorter shortcut shows progress advancing *faster than its speed* while it
is on the shortcut — the frozen behaviour (`branch_distance_for_s`), smoothed by the rate cap (§4.3).

#### 3.3.5 Respawn at run time

`safe_gate` is updated each tick the kart is `safe` (grounded on a road surface outside any hazard;
the caller decides). On a fall or sink, Fall & Respawn asks for `respawn_pose(p, fallback)` =
`respawn_pose[gate_respawn[safe_gate]]` (or its fallback), and the kart is relocated to that respawn's
baked sector with no crossings credited and the key state kept (ADR-0004 §4 "Relocation", §9).

#### 3.3.6 Bots and items

- Bots read only routes, samples, spans and `CourseProgress`, never `CollisionQuery` (ADR-0004 §7). A
  bot need the tables cannot answer extends the schema; a ray is never added to the bot. Bots derive
  braking, drifting and lane choice from the tables by default; `cpu`-route hints are overrides,
  implemented only if playtests need them (ADR-0004 §6).
- Homing projectiles follow an `item` route (falling back to `main`) by along and lateral offset
  (ADR-0004 §8).

#### 3.3.7 Mirror

`CourseData.mirrored()` builds a new object at load (x → −x, poses M·B·M, left/right fields and lane
order swapped, `LANE_HOLD_LEFT` ↔ `LANE_HOLD_RIGHT`). Gate, route and span order, `s`, along and
lengths are unchanged (ADR-0004 §11). **Author rule:** never encode left or right in an id or a
`branch_type` (`hall_left` in Dungeon becomes the right hall in mirror; the id is only a log label, so
this is cosmetic, but a future hint or callout keyed on the name would be wrong).

### 3.4 Reference: the frozen tracks' course behaviour (reverse-documented)

The frozen game uses one spline per road. Its "course data" is: a main loop of length L, branches as
side roads with `s_in` / `s_out` on main, `checkpoint_count`, item spots, hazard polygons, open edges
and respawn values in `TrackData`.

#### 3.4.1 Checkpoints and laps (frozen)

- **Checkpoints:** `checkpoint_count = 10` on both tracks (`castle_circuit.tres`, `dungeon_depths.tres`;
  the `track_data.gd` default is 8). `TrackModel` places **9 interior checkpoints** at
  `L × k / 10`, k = 1 … 9 (`track_model.gd` lines 430-432), plus the line at s = 0. All are required, in
  order: in the new model's terms, **every checkpoint was a key group** and there were no non-key gates.
- **Branches** map onto the main `s` range, so a kart on a branch sweeps through the checkpoints the
  branch covers (`lap_counter.gd` header comment). A shortcut was therefore always legal by
  construction; an off-road cut across the infield was refused because `s` jumped past a checkpoint
  only if the kart's spline query moved it forward — **INTENT UNKNOWN** how robust that was against a
  cut that stays near one centreline; the new model replaces it with the outside-distance rule.
- **Lap rule:** exactly the table in §3.3.2, driven by an `s` wrap (`ds < −L/2` forward, `ds > L/2`
  backward) instead of a gate crossing (`lap_counter.gd` `update`).
- **Teleport:** `resync(s)` sets the position without counting; the checkpoint state is kept, so a kart
  placed past a checkpoint it never passed still has to pass it (`lap_counter.gd` lines 69-72). Ported
  as `relocate` (ADR-0004 §4).
- **Main length L** is computed by `TrackModel` from the spline and is not stored in the `.tres`. From
  the largest `s` values in the files: L > 1086.5 m on Castle (`castle_theme.tres` `zone_gardens` end
  1086.47) and L > 1013.8 m on Dungeon (`lava_gap.s_out` 1013.807). Checkpoint spacing L / 10 is
  therefore about 109 m or more on both tracks.

#### 3.4.2 Branches and shortcuts (frozen)

Main road half width: Castle 6.5 m, Dungeon 6.0 m (`road_half_width`). Main length covered = `s_out −
s_in` from the `.tres`.

| Track | Branch id (`type`) | Main s range | Main covered | Branch half width | What makes it a choice | Measured saving | Bot `branch_factor` |
|---|---|---|---|---|---|---|---|
| Castle | `drawbridge` (drawbridge) | 155.2 – 316.7 | 161.4 m | 2.50 m, rail-less (`curb_width 0`, `wall_height 0`, `open_edge_reach 6.0`) | Timed deck over the moat: 20 s cycle, raised 43 % of the time, 1.5 s warning; meeting it raised sinks the kart (story 009) | 1.09 s open; about 3.8 s lost when met raised (story 009 evidence) | 0.8 |
| Castle | `village_lane` (lane_split) | 517.5 – 619.6 | 102.1 m | 3.40 m (widening to 5.5 at the mouths) | A parallel lane; the main lane carries the `ale_spill` slick, so the other lane avoids it (`gen_castle_circuit.py` line 951) | Not a shortcut (same height, beside main) | 1.0 |
| Castle | `secret_passage` (secret_passage) | 698.0 – 793.3 | 95.3 m | 2.25 m, `wall_drag_mult 2` | Narrow enclosed passage with a portcullis: 20 s cycle, closed 29.5 %, never closed together with the drawbridge (≥ 2.75 s apart) | 1.17 s (story 008 evidence) | 1.0 |
| Dungeon | `hall_left`, `hall_right` (lane_split) | both 214.5 – 294.4 | 79.9 m | 3.40 m each | Two halls with the same mouths. **INTENT UNKNOWN** whether main continues between them (a three-way split) | Not measured | 1.0 |
| Dungeon | `mine_rail` (mine_rail) | 486.3 – 623.0 | 136.7 m | 3.25 m, `floor_drag_mult 1.25`, `wall_drag_mult 2.0`, `rail_lane 1.75` | A shuttling mine cart over 18 m in its own lane, 3.3 m free beside it; solid, spins and pushes | 1.32 s with the cart (story 009 evidence) | 1.0 |
| Dungeon | `lava_gap` (lava_gap) | 819.3 – 1013.8 | 194.5 m | 3.50 m, raised to 7.0 m | A jump ramp at 42.5 m along (lip 0.6 m, length 6 m) over a lava gap with `min_cross_speed = 24.00` (`Hazard_3`); too slow sinks | Not recorded | 0.7 |

**Off-road boost-cuts** (frozen `TrackSurface` with `boost_cut = true`; new kind `cut`, `min_boost`):

| Track | Surface id (kind) | Route range | Note |
|---|---|---|---|
| Castle | `tourney_turf` (grass) | `route_from 24.45` – `route_to 110.37` | Boost-cut across the tourney field |
| Dungeon | `cinder_cut` (sand) | `route_from 897.23` – `route_to 977.77` | Boost-cut inside the lava-gap stretch. **INTENT UNKNOWN** whether these values are main `s` or along the branch |

Castle's `moat_shallows` (shallows) carries a route range 171.25 – 290.57 but `boost_cut = false`.
**INTENT UNKNOWN** what that route is (likely the ford line, `gen_castle_circuit.py` line 819).

**Bots and shortcuts (frozen).** Each personality has a `shortcut_chance` from 0.35 to 1.0 across 8
personalities (`bot_set.tres`; 1.0 = "Shortcut Hunter"), multiplied by the per-type `branch_factor`
above. Story 009: on Castle, 13 drawbridge entries, 10 skips, 0 mis-entries over 5 races; on Dungeon,
the mine rail is entered about 18 times per race.

**Pattern (derived).** Every frozen skill shortcut saves **1.09 – 1.32 s** when executed, and the one
with a measured failure cost loses about **3.8 s** when it fails (≈ 3.5 × its saving). Each has one
readable gate on success: a timer you can see (drawbridge lanterns and horn, portcullis), a cart you
can see, or a speed you can carry.

#### 3.4.3 Respawn (frozen, `kart_sim.gd`)

- **Safe point.** Updated each tick the kart is grounded, not over a hazard, and inside the road
  (`|lateral| ≤ half_width`): the road it is on (`_safe_path`) and the distance along it
  (`_safe_along`); on main, also `_main_safe_along` (`tick`, lines 763-769).
- **Fall.** Off the road over a drop, the kart has fallen when it is more than `fall_respawn_depth =
  2.5 m` below the road beside it, or has flown off the road for `fall_respawn_time = 1.2 s`
  (`track_data.gd` defaults; not overridden in either track `.tres`). It is put back after
  `fall_respawn_delay = 0.8 s`.
- **Sink.** In a hazard it stops and sinks for `respawn_sink_time = 1.0 s` (both tracks).
- **Where.** `_respawn`: on the **centreline of the road last driven safely**, `respawn_back_off =
  4.0 m` behind the safe point, facing along the road (`track_model.gd respawn_pose`).
- **Branch fallback.** If the sink repeated within the last respawn's immunity (`_repeat_sink`), or was
  a speed-gated hazard or a sink mover (`_gate_sink`, e.g. the raised drawbridge, the lava gap), and the
  safe road was a branch, the kart respawns on **main** at `_main_safe_along` instead ("the branch
  respawn point did not work for this kart: the next respawn uses the main road instead (no loop)",
  `kart_sim.gd` lines 992-994).
- **After.** Speed `respawn_speed_frac = 0.2609` × `max_speed` (30 mph of a 115 mph top speed, owner's
  notes per `gen_castle_circuit.py` lines 26-29), hit immunity `respawn_immunity_time = 3.0 s`, spin
  and surface tail cleared.

> **Parity change on the new core.** The frozen respawn is *continuous* (4 m behind wherever you last
> drove safely). The new one is *discrete* (the authored respawn of your last safe gate). The worst-case
> lost distance is now the gap between a gate and its respawn, which is an authoring choice — §3.5.4
> bounds it.

#### 3.4.4 Grid (frozen, `main.gd` lines 1121-1123)

- Kart k (0 … 11) starts at `L − start_distance_behind_line − floor(k / 2) × grid_row_spacing` along
  main, at lateral `grid_lateral × (+1 for even k, −1 for odd k)`.
- Values: `start_distance_behind_line = 6.0` (both tracks), `grid_row_spacing = 8.0`, `grid_lateral =
  2.5` (`net_config.tres`). So 6 rows of 2, side by side (not staggered), front row 6 m and last row
  46 m behind the line, karts 5 m apart across.
- Castle's line sits `LINE_SHIFT = 9.0 m` into the first straight "for a longer grid run-up"
  (`gen_castle_circuit.py` line 24).

### 3.5 Authoring rules for the MVP cup (proposal)

The owner's scope: **1 cup of 4 tracks at MVP, 3 cups / 12 tracks at full vision** (`game-concept.md`
Scope Tiers: "Cup 1 completed to 4 tracks (MVP content)"). Castle and Dungeon are migrated in Phase A;
that they are cup 1's first two tracks is **INTENT UNKNOWN** (inferred from the scope table). Every
rule below is a proposal (Open decisions 1-8).

#### 3.5.1 Gates — spacing and size

1. **Main progress gates every 20 m** on straights and gentle curves (`--auto-gates 20`), with
   hand-authored gates at every corner apex, every fork, every merge, and both ends of every jump.
   *Derivation:* the frozen 109 m spacing (§3.4.1) worked only because a spline gave continuous `s`;
   with linear interpolation between gates, the chord between two gates in a bend must stay on the road.
   For a bend of radius R and chord c, the chord's mid-point lies `R − sqrt(R² − c²/4)` inside the arc
   (§4.2): a 20 m chord on a 25 m radius corner (a tight medieval street) cuts in 2.1 m, which stays
   inside a 6.0-6.5 m half width. A 40 m chord cuts in 9.0 m and leaves the road.
2. **Turn between consecutive gates ≤ 45°.** Together with rule 1 it keeps the sector rule (§4.2) true
   with margin and keeps the interpolated frame close to the road's heading.
3. **Gate width = road width between walls + 2 m on each side**, and on a rail-less edge, + the reach
   a kart can legally use (frozen `open_edge_reach = 6.0 m`). *Derivation:* the corridor must contain
   every legal drift line, including a slide onto the curb; the outside distance then grows only for an
   illegal line. `lost_distance` is the second tolerance on top (Tuning Knobs).
4. **Gate height = 4 m on the ground; on jumps, tall enough to contain the arc** (ADR-0004 §3
   "Coverage": tall gates, or a `branch` with gates in the air). On a stacked deck (a bridge over a road)
   gate height must be **less than the vertical gap** between the two roads, so the vertical term of the
   outside distance separates them (ADR-0004 §3). *Derivation:* frozen `level_separation = 3.0 m`
   (`track_data.gd`) is the smallest stacking the frozen game tells apart; 4 m covers a kart hop and a
   bank on a single deck. INTENT UNKNOWN: kart height on the new core.

#### 3.5.2 Key gates

1. **3 key groups plus the line per track**, at roughly 1/4, 1/2 and 3/4 of the lap. *Derivation:*
   the frozen 9 required checkpoints (§3.4.1) refuse any cut that skips a ninth of the lap; with
   outside-distance progress refusing off-corridor jumps already (§3.3.1), keys only need to stop a
   kart from turning back across the line or cutting a whole section, so fewer keys suffice. Mario Kart
   KMP courses also use a handful of key checkpoints per lap.
2. **Place each key on a stretch every path shares** (between the merge of one shortcut and the fork of
   the next). A key may sit inside a branched stretch only if **every** alternative path carries a gate
   of that same group with `kk_key = true` (the bake FAILs otherwise, ADR-0004 §3).
3. **Never put a key gate where a shortcut lands mid-stretch on main**, unless the shortcut's own chain
   also carries it.
4. **One key just past the first corner** after the line (inside 1/4 lap). *Derivation:* it stops a
   kart from reversing over the line and back for a lap, together with the `invalid_wraps` rule
   (§3.3.2).

#### 3.5.3 Shortcuts — risk and reward (Pillar 2)

Definitions: *saving* = time gained over the main line when the shortcut is executed well; *failure
cost* = time lost versus the main line when the attempt fails (sink and respawn, stop, spin).

1. **Every shortcut has a readable skill check** — one of: carry a speed (`hazard_speed_gated`,
   `kk_min_speed`), spend a boost (`cut` route, `kk_min_boost`), read a clock-driven hazard (a timed
   gate, Pillar 1 design test: clock-driven, not physics-pushed), or hold a tight line (a narrow road,
   frozen 2.25 m half width). No shortcut is free.
2. **Saving 0.8 – 1.5 s per lap.** *Derivation:* the frozen skill shortcuts save 1.09 – 1.32 s
   (§3.4.2). Above ~1.5 s, a shortcut decides the race on its own and stops being a choice; below
   ~0.8 s, few players will risk it. INTENT UNKNOWN: the bounds are a judgement on the frozen data,
   not playtested.
3. **Failure cost 2 – 4 × the saving.** *Derivation:* drawbridge ≈ 3.5 × (3.8 s / 1.09 s). The
   break-even success rate is cost / (saving + cost) (§4.5): 67 % at 2 ×, 80 % at 4 ×. A shortcut is
   then worth it for a player who executes it more often than that — skill decides.
4. **Counterplay window** (Pillar 2 design test): a timed hazard on a shortcut warns at least 1.5 s
   before it closes (frozen drawbridge and portcullis warnings: 1.5 s, story 009). Two shortcuts on one
   track are never closed together (frozen portcullis rule, ≥ 2.75 s apart).
5. **Per track: 1-2 skill shortcuts, 0-1 lane splits, 0-1 boost-cuts.** *Derivation:* Castle has 2
   skill shortcuts + 1 lane split + 1 boost-cut; Dungeon 2 + 1 split (two halls) + 1 boost-cut.
6. **Data.** A shortcut is a `branch` route with `kk_branch_type = shortcut` (or a themed type the bot
   `branch_factor` table knows); a boost-cut is a `cut` route with `kk_min_boost`. Every branch that
   bypasses a key group carries that key (3.5.2 rule 2). Each skill shortcut gets its own respawn
   **before** its skill check (3.5.4).
7. **Fairness check.** A shortcut ships only when story-009-style bot runs show 0 mis-entries and a
   human playtest confirms the cue is readable (the open drawbridge fairness item: "blind use loses, by
   design. A 13 s down / 7 s up cycle was suggested as fairer", story 009 evidence).

#### 3.5.4 Respawn placement

1. **A respawn every 40 m of route** wherever the edge is a `DROP`, `OPEN_EDGE` or hazard, and every
   100 m elsewhere on main. *Derivation:* the frozen continuous rule loses 4 m + the sink or fall time;
   a discrete respawn loses up to the gap. At 40 m and the frozen respawn speed (0.2609 × max), the
   extra loss is about the 1 s scale of a shortcut saving — a fall must never cost more than a failed
   shortcut does. INTENT UNKNOWN: kart `max_speed` on the new core, so the 1 s figure is not computed.
2. **On a shortcut, put the respawn before the skill check, on safe road, facing the check.**
3. **On a speed-gated branch, gates in the run-up use a respawn on main**, not on the branch:
   a respawn at 0.2609 × max speed cannot reach the gate speed (frozen lava gap `min_cross_speed =
   24.00`) in a short run-up, and the frozen game sends `_gate_sink` karts to main for the same reason.
   Set `kk_respawn` on those gates explicitly.
4. **Never in a mover's swept volume, a hazard area, or on a pad or ramp** (bake check, ADR-0004 §9,
   plus pad/ramp: a respawn onto a pad would boost a kart that just failed). Leave at least
   `respawn_immunity_time` (3.0 s) × respawn speed of clear road ahead before the next hazard.
5. **Never across the line** from the gates that use it (bake check). The last respawn before the line
   is behind gate 0; the first after it is used only by gates after the line.

#### 3.5.5 Grid of 12

1. **12 explicit poses, 2 per row, 6 rows, staggered by half a row** (Mario Kart style), row spacing
   8.0 m, lateral ±2.5 m, front row 6.0 m behind gate 0. *Derivation:* frozen values (§3.4.4); the
   frozen grid is side-by-side, the stagger is a proposal (Open decision 6) so no two karts start
   wheel to wheel.
2. **Straight before the line ≥ 46 m + 12 m.** 46 m is the frozen last-row distance; 12 m is a
   proposed margin so the last row starts on straight road. **First corner ≥ 60 m after the line** so
   12 karts can sort themselves out (INTENT UNKNOWN: frozen Castle's first-corner distance is not in
   the files; `LINE_SHIFT = 9.0 m` shows the intent to lengthen the run-up).
3. **Grid on road ground only**, all behind gate 0 (bake checks, ADR-0004 §10), no item box, pad or
   hazard between the grid and the first key gate.

#### 3.5.6 Routes for bots and items

1. **Author a `cpu` route** for main and for every branch the bots may take; keep it ≥ 1.5 m inside
   `clear_left/right` (frozen `road_keep_band = 1.5`, `track_data.gd`). No hints at first (ADR-0004 §6:
   hints only if playtests need them).
2. **Author an `item` route** only where `main` is a bad projectile line (a shortcut's mouth, a
   hairpin); otherwise homing items fall back to `main`.
3. **Item boxes: a row across the full width**, at least one row on every legal path between two
   consecutive key groups; frozen Castle puts one box on each lane of the lane split (`gen_castle_circuit.py`
   lines 554-556). Whether a skill shortcut carries its own box is Open decision 8.

### 3.6 Integration points

| Consumer | Reads | Notes |
|---|---|---|
| Lap & Position (row 11) | `CourseProgress` `lap`, `distance`, `line_crossed`, `crossing_rejected`, `wrong_way` | Owns `max_lap`, lap times, finish, ranking events |
| Fall & Respawn (row 12) | `respawn_pose`, `safe_gate`, `relocate`, `FALL_BOUNDARY` areas | Decides `safe` and `fallback`; owns sink, fall and immunity timings |
| CPU Racers (row 16) | Routes, samples, spans, `branch_type`, `min_speed`, `min_boost`, hints | Never `CollisionQuery` |
| Items (row 15) | `box_pose`, `box_route`, `box_along`, `item` routes, `along_for_s` | Projectile collision uses `CollisionQuery` |
| Track Hazards (row 14) | `HAZARD` areas and spans, `MOVER` spans | Timing is Track Hazards' pure functions of the synced clock |
| Track Features (row 13) | `PAD` / `RAMP` spans, `CANNON_TRIGGER` areas | Pads and ramps come from surface kinds |
| Kart Physics (ADR-0003) | `distance` (pair broadphase), `self_crossing` | |
| Network (ADR-0006) | `lap` (u8), `distance` (signed) on the wire | Receivers never recompute remote progress |
| Race HUD & Minimap (row 19) | `distance`, `lap`, `wrong_way`, route `pos` for the minimap line | |
| Grand Prix (row 31) | `mirrored()` | |
| Blender Track Pipeline (row 7) | Produces `CourseAuthoring`, runs `CourseBuilder` at import | ADR-0005 |

---

## 4. Formulas

### 4.1 Sector fraction and outside distance (ADR-0004 §3)

```
d_a = (p − o_a) · fwd_a          (≥ 0 past gate a)
d_b = (p − o_b) · fwd_b          (≤ 0 before gate b)
t   = d_a / (d_a − d_b)
outside = max(0, |lateral| − hw_t) + max(0, |vertical| − hh_t) + metres of t beyond [0, 1]
```

| Variable | Meaning | Range |
|---|---|---|
| p | Kart position | world, ±2 km (ADR-0001) |
| o_a, o_b | Lifted gate centres | — |
| fwd_a, fwd_b | Gate travel normals (−basis.z) | unit |
| t | Fraction through the sector | [0, 1] inside; > 1 past b; < 0 behind a |
| hw_t, hh_t | Gate half width and half height lerped at t | > 0 m |
| lateral, vertical | Offsets from the lerped frame at t | m |

**Example.** Gates 20 m apart and parallel, kart 5 m past a: d_a = 5, d_b = −15, t = 5 / 20 = 0.25.
Half widths 8.5 m at both gates (6.5 m road + 2 m, §3.5.1 rule 3), kart 9.5 m right of centre:
outside = 9.5 − 8.5 = 1.0 m.

### 4.2 Gate spacing in a bend (proposal, §3.5.1)

**Sector rule, simple case.** Gate b at distance d straight ahead of a, rotated by θ about up, half
width w_b. b's inner corner lies d − w_b·sin θ in front of a's plane, so the rule needs

```
d > w_b · sin θ      and, symmetrically,      d > w_a · sin θ
```

Example: a hairpin with θ = 45°, w = 8.5 m → d > 6.0 m. With θ = 90° → d > 8.5 m. (The builder checks
the real rule on all corners; this is the author's quick test.)

**Chord sag.** Two gates on an arc of radius R, chord length c between them; the chord's mid-point is
inside the arc by

```
sag = R − sqrt(R² − c² / 4)
```

| R | c = 20 m | c = 40 m |
|---|---|---|
| 25 m | 25 − sqrt(625 − 100) = 25 − 22.9 = 2.1 m | 25 − sqrt(625 − 400) = 25 − 15 = 10.0 m |
| 50 m | 50 − sqrt(2500 − 100) = 50 − 49.0 = 1.0 m | 50 − sqrt(2500 − 400) = 50 − 45.8 = 4.2 m |

Rule: sag ≤ half the road half width (≤ 3.0 m on a 6.0 m half width). 20 m spacing meets it down to a
25 m radius; tighter corners get a gate at the apex.

### 4.3 Smoothed race distance (ADR-0004 §4 step 5; frozen `limit_progress`)

```
raw      = (lap − 1) × lap_length + s
allow    = progress_rate_cap × moved + progress_slack
distance = prev + clamp(raw − prev, −allow, +allow)
```

| Variable | Default | Source |
|---|---|---|
| `progress_rate_cap` | 1.95 | `CourseTuning`, ported from `track_data.gd` |
| `progress_slack` | 0.03 m | `CourseTuning`, ported from the frozen `PROGRESS_SLACK` const |
| moved | m travelled this tick | caller |

Smoothing is skipped (snap) on a rejected or backward line crossing and on relocate.

**Example.** A kart on a shortcut that covers 161.4 m of main (drawbridge) with a branch of, say, 120 m
(INTENT UNKNOWN: the frozen branch length is printed by the generator, not stored): `s_main` advances
161.4 / 120 = 1.35 m per metre driven, under the 1.95 cap, so the HUD shows it smoothly. At 20 m/s,
moved = 20 / 60 = 0.333 m per tick, allow = 1.95 × 0.333 + 0.03 = 0.68 m per tick.

**Author consequence.** A shortcut whose main-covered / branch-length ratio exceeds 1.95 makes
progress lag behind the truth on the shortcut and catch up after the merge (the rate cap is the
limit). Keep the ratio ≤ 1.95, or accept the lag.

### 4.4 Grid positions (frozen, `main.gd` lines 1121-1123)

```
along(k)   = L − start_distance_behind_line − floor(k / 2) × grid_row_spacing
lateral(k) = grid_lateral × (+1 if k even else −1)
```

k = 0 … 11; `start_distance_behind_line = 6.0`, `grid_row_spacing = 8.0`, `grid_lateral = 2.5`.
Example: k = 11 → floor(5.5) = 5 → along = L − 6 − 40 = L − 46 m, lateral = −2.5 m.

**Staggered proposal (§3.5.5):** `along(k) = L − 6 − k × 4` (half a row per slot), same lateral rule.
k = 11 → L − 50 m.

### 4.5 Shortcut break-even (proposal, §3.5.3)

```
EV(p)      = p × saving − (1 − p) × cost
p_breakeven = cost / (saving + cost)
```

| Variable | Meaning | Range (proposal) |
|---|---|---|
| saving | Time gained when executed (s) | 0.8 – 1.5 s |
| cost | Time lost versus main when the attempt fails (s) | 2 – 4 × saving |
| p | The player's success rate | 0 – 1 |

**Example (frozen drawbridge):** saving 1.09 s, cost 3.8 s → p_breakeven = 3.8 / 4.89 = 0.78. A player
who reads the lantern right more than 78 % of the time should take it. (For a *timed* hazard p is not
pure execution skill: a blind attempt succeeds with p = 1 − 0.43 = 0.57 — the deck is raised 43 % of
the cycle — so blind use loses: EV = 0.57 × 1.09 − 0.43 × 3.8 = 0.62 − 1.63 = −1.01 s. "Blind use
loses, by design", story 009.)

### 4.6 Wrong way (ADR-0004 §4 step 6)

```
Δ = distance − prev
if Δ < 0: back_run += −Δ
else:     back_run = max(0, back_run − Δ); passing wrong_way_clear resets back_run to 0
wrong_way = back_run ≥ wrong_way_distance
```

INTENT UNKNOWN: whether "passing `wrong_way_clear`" means cumulative forward travel since the last
backward step; ADR-0004 does not say. `wrong_way_distance` and `wrong_way_clear` defaults are set by
story 023.

---

## 5. Edge Cases

| # | Situation | What happens | Source |
|---|---|---|---|
| E1 | A kart reverses over the line and drives forward again | Backward crossing: `lap −= 1`, `key_next = key_groups.size()`; forward again: `lap += 1`, but `max_lap` does not grow, so no new lap is reached | ADR-0004 §5; `lap_counter.gd` |
| E2 | A kart cuts across an infield, skipping a key group | It goes off course (outside > `lost_distance`), progress is held, and a full search credits no skipped gate; if it reaches the line, the crossing is rejected (`invalid_wraps += 1`) | ADR-0004 §4-§5 |
| E3 | After a rejected crossing, the kart backs over the line | `invalid_wraps −= 1`, lap unchanged (the rejected crossing is undone, not a real lap) | ADR-0004 §5; `lap_counter.gd` lines 121-122 |
| E4 | A kart is respawned past a key it never crossed (bad authoring) | `relocate` keeps the key state, so it must still cross that key; the bake prevents it (respawn `s` ≤ `gate_s`) | ADR-0004 §4, §9 |
| E5 | A shortcut bypasses a key group and its chain lacks that group | Bake FAIL (key coverage of every path); the track is refused at import | ADR-0004 §3, §13 |
| E6 | A branch's first or last point is more than `fork_merge_tolerance_m` from any route | Bake FAIL | ADR-0004 §2 |
| E7 | Two gates of one group disagree on `kk_key` | Bake FAIL | ADR-0004 §3 |
| E8 | A respawn is placed inside a mover's swept volume or a hazard | `track_check` FAIL | ADR-0004 §9 |
| E9 | A kart sinks again within respawn immunity after a branch respawn | Fall & Respawn sets `fallback`; the kart goes to the branch respawn's `respawn_fallback` on main (no respawn loop) | ADR-0004 §9; `kart_sim.gd` lines 992-994 |
| E10 | A kart fails a speed-gated jump (lava gap) | Sinks; `fallback` is set (speed-gated hazard), so it respawns on main | ADR-0004 §9; frozen `_gate_sink` |
| E11 | A kart flies over a jump outside every gate | If the gates do not cover the arc, it goes off course mid-air and is held; authoring rule 3.5.1-4 (tall gates) and the bake's airborne coverage check prevent it | ADR-0004 §3 "Coverage" |
| E12 | Bridge over a road (stacked decks), kart on the lower road | The vertical term of outside keeps it in the lower sector, provided gate height < vertical gap (3.5.1-4) | ADR-0004 §3 |
| E13 | All 12 karts off course at once | Full searches are staggered: at most about 12 / N per tick (N = `offcourse_search_interval_ticks`) | ADR-0004 §4 |
| E14 | Two candidate next sectors are equally close | The lowest link index wins; order `kk_next` with the main road first | ADR-0004 §4, §12 |
| E15 | More than 8 gates crossed in one tick (teleport, cannon) | `MAX_SECTOR_STEPS = 8` stops the walk; use `relocate` for teleports | ADR-0004 §4 |
| E16 | Mirror mode | A new `CourseData` with left/right swapped; ids keep their names (`hall_left` is on the right) | ADR-0004 §11 |
| E17 | A kart slides backwards while facing forward | Counts towards wrong-way (distance-based) | ADR-0004 §4 |
| E18 | Course crosses itself at the same height and `kk_self_crossing` is false | Story 022's brute-force cross-check reports it; the author sets the flag | ADR-0004 Decision preamble |
| E19 | Fewer or more than 12 grid empties, or a duplicate slot | Import FAIL | ADR-0005 §2 |
| E20 | Two shortcuts' timed hazards would close together | Authoring rule 3.5.3-4 (≥ 2.75 s apart, frozen portcullis rule); not a bake check — Track Hazards' `track_check` check (17) covers it today (story 009) | story 009 evidence |

---

## 6. Dependencies

| System | Direction | Interface | Reciprocal mention |
|---|---|---|---|
| Track Collision & Surface Attributes (row 2, ADR-0002) | Course Data depends on it | `CollisionQuery`, surface kinds, mover ids for the bake | ADR-0002 states left/right data lives in Course Data; no GDD yet — the row 2 GDD must list Course Data |
| Blender Track Pipeline (row 7, ADR-0005) | Depends on Course Data | Parses empties into `CourseAuthoring`, calls `CourseBuilder` | ADR-0005 §2 "Course Data seam"; no GDD yet |
| Lap & Position Tracking (row 11) | Depends on Course Data | `CourseProgress` outputs | No GDD yet; must list Course Data |
| Fall & Respawn (row 12) | Depends on Course Data | `respawn_pose`, `safe_gate`, `relocate` | No GDD yet; must list Course Data |
| Track Features (row 13) | Depends on Course Data | `PAD`, `RAMP` spans, cannon areas | No GDD yet |
| Track Hazards (row 14) | Depends on Course Data | `HAZARD` areas, `MOVER` spans | No GDD yet |
| Items & Item Boxes (row 15) | Depends on Course Data | Box poses, `item` routes | No GDD yet |
| CPU Racers (row 16) | Depends on Course Data | Routes and tables only | No GDD yet |
| Race HUD & Minimap (row 19) | Depends on Course Data | `distance`, `lap`, `wrong_way`, route line | No GDD yet |
| Grand Prix & Speed Classes (row 31) | Depends on Course Data | `mirrored()` | No GDD yet |
| Elimination Race (row 33), Accessibility Assists (row 35) | Depend on Course Data | Progress and routes | No GDD yet |
| Kart Physics (ADR-0003) | Depends on Course Data | `distance` broadphase, `self_crossing` | ADR-0003 |
| Network snapshot (ADR-0006) | Depends on Course Data | `lap`, `distance` | ADR-0004 Enables |
| Driving & Drift (row 9) | None directly | Bots' drift choices read Course Data spans via CPU Racers | `driving-and-drift.md` does not need to list it |

---

## 7. Tuning Knobs

| Knob | Where | Default | Safe range (proposal) | Affects |
|---|---|---|---|---|
| `progress_rate_cap` | `CourseTuning` (`assets/data/core/course_tuning.tres`) | 1.95 | 1.5 – 2.5 | How fast displayed progress may move on a shortcut; below a shortcut's ratio, progress lags (§4.3) |
| `progress_slack` | `CourseTuning` | 0.03 m | 0.01 – 0.1 m | Progress movement allowed while standing still |
| `lost_distance` | `CourseTuning` | not chosen (story 023) | 2 – 6 m outside the gate corridor | How far off the corridor before progress freezes; too small = freezes on legal wide lines, too big = cuts stay "on course" |
| `wrong_way_distance` | `CourseTuning` | not chosen | 5 – 20 m | When the wrong-way warning appears |
| `wrong_way_clear` | `CourseTuning` | not chosen | 2 – 10 m | When it clears |
| `offcourse_search_interval_ticks` | `CourseTuning` | not chosen | 4 – 15 ticks | CPU cost vs how fast an off-course kart is re-found |
| `locate_window_m` | `CourseTuning` | not chosen | 10 – 40 m | `RouteCursor` search window |
| `sample_spacing_m` | `CourseBuildSettings` | 1.0 m | 0.5 – 2.0 m | Route table resolution (bots, spans, wall check I9) |
| `fork_merge_tolerance_m` | `CourseBuildSettings` | not stated in ADR-0004 | 0.5 – 2.0 m | How close a branch's ends must be to its parent |
| `curve_expand_spacing_m` | `src/pipeline/track_schema.json` | not stated | ≤ `sample_spacing_m` × 2 | Density of points generated from Blender curves |
| Auto-gate N | `export_track.py --auto-gates <N>` | none (off) | 15 – 25 m (proposal: 20) | Main progress-gate spacing (§3.5.1, §4.2) |
| Gate `kk_width`, `kk_height` | Per gate, authored | — | width: road + 2 m each side; height 4 m on ground (§3.5.1) | Legal corridor |
| `kk_min_speed` (route / area) | Per route or area | 0 (none) | Frozen: 24.00 (lava gap) | Skill check of a jump shortcut |
| `kk_min_boost` | Per route | 0 (none) | — | Skill check of a boost-cut |
| Respawn spacing | Authored | — | 40 m near drops/hazards, 100 m elsewhere (§3.5.4) | Worst-case fall cost |
| Grid row spacing, lateral, front offset | Authored poses (frozen values in `net_config.tres`, `TrackData`) | 8.0 m, ±2.5 m, 6.0 m | row 6 – 10 m, lateral 2 – 3 m | Start spacing; first-corner congestion |
| Shortcut saving / failure cost | Track geometry and hazard timing | Frozen: 1.09 – 1.32 s saving; 3.8 s drawbridge cost | 0.8 – 1.5 s; 2 – 4 × (§3.5.3) | Risk/reward of shortcuts |
| `branch_factor`, `shortcut_chance` | `BotSet` (`assets/data/ai/bot_set.tres`) — owned by CPU Racers | 0.7 – 1.0 per type; 0.35 – 1.0 per personality | — | How often bots take each branch type |

Respawn timings (`respawn_sink_time` 1.0 s, `respawn_speed_frac` 0.2609, `respawn_immunity_time` 3.0 s,
`respawn_back_off` 4.0 m, `fall_respawn_*`) are Fall & Respawn's knobs; they are listed in §3.4.3 for
reference only. `respawn_back_off` has no direct equivalent on the new core (the respawn pose is
authored).

---

## 8. Acceptance Criteria

Each is verifiable by `track_check`, a `tests/unit/course/` test, or a scripted run.

**Bake and authoring (per MVP track)**
- AC1. The track imports with **no FAIL and no NOT ASSESSED** line from `CourseBuilder` (ADR-0005 I15).
- AC2. Exactly one `main` route, closed; gate 0 in group 0; exactly 12 grid poses, slots 0 … 11.
- AC3. Every legal path (every path through the gate graph) crosses every key group exactly once —
  the bake's key-coverage line PASSes, and a deliberately broken copy (one shortcut gate's `kk_key`
  removed) FAILs.
- AC4. The track has at least 3 key groups besides group 0 (proposal §3.5.2; drop if the owner rejects it).
- AC5. No two consecutive main gates are more than 25 m apart, and none turns more than 45° (proposal
  §3.5.1; a `track_check` WARN line or an author script lists violations).
- AC6. Every respawn's `s` ≤ the `gate_s` of every gate that uses it; none lies across the line from its
  gates; none is in a hazard, a mover's swept volume, or on a pad or ramp.
- AC7. On every route with a `DROP` or `OPEN_EDGE` span, the along distance from any gate to its respawn
  is ≤ 40 m (proposal §3.5.4).
- AC8. Every gate in the run-up of a `min_speed` branch uses a respawn on `main`.
- AC9. Every grid pose is behind gate 0 on road ground, ≥ 2 × the largest kart radius + margin from the
  others, and the first corner (first gate turning > 15° from gate 0) is ≥ 60 m after the line.

**Run-time behaviour (scripted autopilot or unit test)**
- AC10. An autopilot driving the main line for 3 laps gets `lap` 1, 2, 3, 4 at the four line crossings,
  `rejected_crossings = 0`, and `distance` never decreases.
- AC11. Each shortcut driven by a scripted line counts the lap (no rejection), and `distance` across the
  shortcut is continuous (no step larger than `allow`, §4.3).
- AC12. A scripted cut that skips a key group (teleport-free path across an infield) earns no lap at the
  line: `crossing_rejected = true`, `lap` unchanged.
- AC13. Reverse over the line and forward again: `lap` goes n → n − 1 → n; `max_lap` unchanged; Lap &
  Position emits no new lap.
- AC14. Drive off each open edge: the kart respawns at the respawn of its last safe gate, `lap`
  unchanged, `distance` not greater than before the fall.
- AC15. Fail the speed-gated jump: the kart respawns on main (fallback).
- AC16. Mirror: `mirrored()` of each track passes AC10-AC12 driven on the mirrored line; the loaded
  (cached) `CourseData` is byte-for-byte unchanged afterwards.
- AC17. 11 bots, 5 races per track: 11/11 finish, 0 stuck, 0 shortcut mis-entries (the story-009 bar).

**Design (playtest)**
- AC18. For each skill shortcut, a timed run measures the saving within 0.8 – 1.5 s and the failure cost
  within 2 – 4 × the saving (proposal §3.5.3).
- AC19. Each timed hazard on a shortcut gives ≥ 1.5 s warning, and no two shortcuts on a track are
  closed at the same time (≥ 2.75 s apart).

---

## Open decisions for the owner

1. **Gate spacing.** Main progress gates every 20 m (auto-gates) with hand gates at apexes, forks,
   merges and jumps; ≤ 45° turn between gates (§3.5.1). Alternatives: 15 m (smoother, more gates) or
   30 m (fewer, needs more hand gates in bends).
2. **Key groups.** 3 per lap plus the line, at about 1/4, 1/2, 3/4 (§3.5.2). Alternative: keep the
   frozen 9 (stricter, harder to author around shortcuts).
3. **Shortcut risk/reward band.** Saving 0.8 – 1.5 s; failure cost 2 – 4 × saving (§3.5.3).
4. **Shortcut count per track.** 1-2 skill shortcuts, 0-1 lane splits, 0-1 boost-cuts (§3.5.3).
5. **Respawn spacing.** 40 m near drops and hazards, 100 m elsewhere (§3.5.4). This accepts the parity
   change from the frozen continuous respawn (4 m back off) to discrete respawns.
6. **Grid.** Keep the frozen side-by-side 2 × 6 (8 m rows, ±2.5 m), or stagger by half a row (Mario
   Kart style, last kart 50 m back) (§3.5.5, §4.4). Also the straight-before-line (≥ 58 m) and
   first-corner (≥ 60 m) minimums.
7. **Drawbridge fairness.** Keep the frozen 20 s cycle raised 43 %, or the suggested 13 s down / 7 s up
   (story 009 evidence) when Castle is migrated.
8. **Item boxes on shortcuts.** Does a skill shortcut carry its own box (extra reward) or none (the time
   saving is the reward)?
9. **Cup 1 line-up.** Confirm cup 1 = Castle Circuit + Dungeon Depths + 2 new tracks (inferred from the
   scope table, INTENT UNKNOWN).
10. **Lap count home.** Lap count is not Course Data; confirm it lives in the `TrackDef` catalog
    (per-track, frozen value 3) rather than Race Flow.
11. **ADR-0001 §9 amendment** (ADR-0004 §15): tools may run the frozen game to export Castle and
    Dungeon course data. Pending; nothing in that path can be built until approved.

## Open Questions and Follow-Up Work

### Flagged Follow-Up Work

- Record the frozen branch lengths and the main length L (the generators print them; they are not
  committed). Needed to check the §4.3 rate-cap ratio for each frozen shortcut.
- Confirm Dungeon's hall split: does main run between `hall_left` and `hall_right` (three-way) or not?
- Confirm whether `cinder_cut`'s `route_from/to` (897.23 – 977.77) are main `s` or branch along, and
  what Castle's `moat_shallows` route range is.
- Kart dimensions and `max_speed` on the new core: needed to finish §3.5.1 rule 4 (gate height) and
  §3.5.4 rule 1 (fall cost in seconds).
- Measure whether Castle or Dungeon needs `kk_self_crossing`.
- ADR-0005 says gate `kk_index` is "contiguous from 0"; ADR-0004 §14 says "not necessarily
  contiguous". One of them should be amended (ADR-0004 governs the meaning).
- GDDs for Lap & Position, Fall & Respawn, CPU Racers, Items, Track Hazards and Track Features must
  list Course Data as a dependency (bidirectional rule).
- `fork_merge_tolerance_m` and `curve_expand_spacing_m` have no stated defaults in the ADRs.

## Version History

| Version | Date | Change |
|---|---|---|
| 0.1 | 2026-11-22 | First draft (level-designer view): ADR-0004 v3 / ADR-0005 restated for authors; Castle and Dungeon course behaviour reverse-documented; MVP-cup authoring rules proposed |
