# ADR-0004: Course Data Format

## Status
Proposed

## Date
2026-11-22

## Last Verified
2026-11-22

## Decision Makers
Claude (ai-programmer, autonomous mode, owner-authorized) drafted it from `architecture.md`, ADR-0001, ADR-0002 and a read of the frozen code. The frozen code was read as reference only.
- **godot-specialist validation:** NOT ASSESSED. Not yet run.
- **technical-director (TD-ADR):** NOT ASSESSED. Not yet run. `review_mode` is `full`, so both reviews are required before acceptance.
- **GDD sync:** NOT ASSESSED. No system GDD exists, and this ADR cites `design/gdd/systems-index.md` rows only.

Acceptance needs the owner's confirmation.

## Summary
The rebuilt core has no spline, so it needs its own data to answer "where is the line, the next checkpoint, the respawn" (architecture Principle 4). This data must stay separate from collision.

This ADR fixes:
- **The `CourseData` schema.** A binary `.res` that ADR-0005 bakes from Blender empties. It holds checkpoint gates (oriented quads with group ids and next links, plus key groups for laps), routes with baked per-sample tables and span tables, item-box poses, respawn poses and 12 grid poses.
- **Per-kart `CourseProgress`.** It is computed by a sector cursor in O(1) amortised time, and it handles junctions, shortcuts, wrong-way driving and off-course flight.
- **The boundaries.** Bots read only routes and tables, and never `CollisionQuery`. Mirror swaps every left/right field here.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.8-beta3 |
| **Domain** | Core |
| **Layer** | Core (systems-index row 3 and the architecture layer map put Course Data in Core) |
| **Knowledge Risk** | HIGH (4.8 is post-cutoff and pre-release). The APIs this ADR uses are pre-cutoff: `Resource`, packed arrays, typed `Array`, `Transform3D`, `ResourceSaver` / `ResourceLoader` |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `breaking-changes.md` (4.7: a packed-array element write no longer calls the property setter), `current-best-practices.md` and `deprecated-apis.md` (`duplicate_deep()`, 4.5). No engine probe was run for this ADR |
| **Post-Cutoff APIs Used** | None. `mirrored()` builds new arrays explicitly and does not rely on `duplicate()` or `duplicate_deep()` semantics |
| **Verification Required** | (1) On 4.8-beta3, a binary `.res` round-trip of a `Resource` with typed `Array[Transform3D]`, `Array[CourseRoute]` sub-resources and packed arrays must reload byte-equal and typed. UNVERIFIED. (2) Loading the same `.res` twice returns the cached instance, and `mirrored()` leaves it untouched (the same hazard ADR-0002 guards against). (3) The cost of `CourseProgress` and `RouteCursor` in a release export (see Performance Implications). All estimates there are UNVERIFIED |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Accepted). From it: axes, units, float32 vector precision and the ±2 km bound (§1), pose empties with +Y along travel (§2), step order and no global RNG (§6), mirror (§7). ADR-0002 (Proposed). From it: collision carries no left/right labels, so all left/right data lives here; `TrackCollisionData` and the `SurfaceSet` surface ids are what the bake and `track_check` validate against |
| **Enables** | ADR-0005 (Blender track pipeline, drafted in parallel). It bakes this schema from empties and custom properties. ADR-0006 (network snapshot). It carries `lap` and `distance` from `CourseProgress` in place of today's `LAP` and `TRACK_S` |
| **Blocks** | Story 023 (Course Data + mesh `track_check`). Story 025's lap-and-respawn, items and bots stories |
| **Ordering Note** | ADR-0005 must bake exactly these fields. If it needs a different field, this ADR is amended first. ADR-0002 must be Accepted before story 023 implements the bake-time validation against collision |

## Context

### Problem Statement
The frozen game answers every "where" question from one spline (`TrackModel`): distance `s`, lateral offset, half width, branches as `s` ranges, and surface zones mapped onto `s`. The rebuilt core has triangles (ADR-0002) and no spline. Several systems need that data from somewhere:

- **Bots** (`src/legacy/ai/bot_driver.gd` with `debug/autopilot_driver.gd`) use about 74 `track.*` references. The table in Decision §6 lists them all:
  - half width (`half_width_at`, `road_half_width`);
  - distance to a branch (`distance_to_path`);
  - branch extents (`branches[].s_in/s_out`, `branch_length`, `branch_along`, `branch_distance_for_s`, `branch_point_at`, `data.branches[].id/type/open_edge_reach`);
  - surfaces (`on_ground_zone`, `slick_on_main_between`, `zone_s_range`, `zone_lat_range`, `zone_routes`, `zone_boost_cut`, `zone_route_via`);
  - wall openings (`data.wall_openings` → `_zone_open_sides`);
  - rail-less edges (`data.open_edges`);
  - ramps (`ramp_lip_s`, `ramp_paths`);
  - speed-gated hazards (`hazard_gates`, `hazard_bounds`);
  - timed gates and travelers (`data.movers`, through `BotContext` callables);
  - the line itself (`point_at`, `tangent_at`, `length`).
- **Items** (`items/item_manager.gd`) need each box's position, height and normal (`item_box_position/height/normal`). The homing falcon follows the main `s` with a lateral offset.
- **Laps** (`test_track/lap_counter.gd`) are counted when `s` wraps, with interior checkpoints as `s` values. The wire (`net/kart_wire.gd`) sends `LAP` and `TRACK_S`. The ranking (`main.gd _rank_key`) is `(lap − 1) × length + track_s`.
- **Progress smoothing:** progress is smoothed at junctions by `limit_progress(prev, target, moved)`. That function caps the change of `s` at `progress_rate_cap (1.95) × moved + 0.03`.

### Constraints
- Simulation data is a `Resource` or a `RefCounted`, never a node (Principle 1).
- Course Data owns its runtime format. Blender writes glTF only, and ADR-0005's editor-time import builds the `.res` (Principle 3).
- Bots read routes and baked tables only, never `CollisionQuery` (architecture, CPU Racers row).
- New code must not reference `src/legacy/` (ADR-0001 §9). The frozen behaviour is ported as rules, not as code.
- Tuning values live in `.tres` (`.claude/rules/tuning-values.md`).
- There are 12 racers, and the host simulates up to 11 bots inside the ≤ 3 ms per-tick simulation budget.
- The goal is Mario Kart parity. The data is shaped like Mario Kart's KMP (checkpoints, enemy and item routes, respawn points, start positions), adapted to 3D gates.

### Requirements
- Lap counting that refuses illegal cuts, allows authored shortcuts and branches, and handles reversing over the line exactly as the frozen `LapCounter` does.
- A continuous progress value for ranking, the wire, the kart-pair broadphase and HUD positions. It must stay smooth at junctions.
- Route tables rich enough to replace every bot reference listed above.
- Item boxes, respawn poses and a 12-slot grid.
- `mirrored()` (ADR-0001 §7).
- Progress for 12 karts in well under 0.1 ms per tick.
- Same-machine determinism.

## Decision

### 1. Shape of the data
`CourseData` is one `Resource` saved as binary **`.res`** inside the `TrackPackage` (ADR-0005). It holds five parts:

1. **Gates:** checkpoints as oriented quads.
2. **Routes:** `CourseRoute` sub-resources with baked tables.
3. **Item boxes.**
4. **Respawn poses.**
5. **Grid poses.**

Large per-element data is stored as **packed arrays (structure of arrays)**, not as one sub-resource per gate or per sample, because per-tick reads of packed arrays are cheaper in GDScript. Code lives in `src/core/course/`, with one `class_name` per file.

### 2. `CourseData` schema

**Top level**

| Field | Type | Meaning |
|---|---|---|
| `format_version` | `int` | Matches `CourseData.FORMAT_VERSION`. The loader refuses any other value |
| `lap_length` | `float` | Length of the main route (m). Progress `s` lies in [0, `lap_length`) |
| `gate_xform` | `Array[Transform3D]` | Gate centre and frame: basis.x = right, basis.y = up, −basis.z = travel (the gate's forward normal) |
| `gate_half` | `PackedVector2Array` | Half width (along x) and half height (along y) per gate |
| `gate_group` | `PackedInt32Array` | Group id per gate. Group 0 is the lap line |
| `gate_s` | `PackedFloat32Array` | Lap-reference distance of the gate (§3) |
| `gate_next_start`, `gate_next` | `PackedInt32Array` ×2 | Next links in CSR form: the links of gate g are `gate_next[gate_next_start[g] .. gate_next_start[g+1])`, in authored order |
| `gate_prev_start`, `gate_prev` | `PackedInt32Array` ×2 | Previous links, derived at bake, in the same form |
| `gate_respawn` | `PackedInt32Array` | Respawn index per gate (§9) |
| `key_groups` | `PackedInt32Array` | Key group ids in lap order, excluding group 0 |
| `routes` | `Array[CourseRoute]` | Exactly one route has kind `main` |
| `box_pose` | `Array[Transform3D]` | Item box: origin on the ground, Y = ground normal, −Z = travel |
| `box_route`, `box_along` | `PackedInt32Array`, `PackedFloat32Array` | The route and the distance along it of each box (for item and bot logic) |
| `respawn_pose` | `Array[Transform3D]` | Origin on the ground, Y = up, −Z = travel |
| `respawn_sector_gate`, `respawn_sector_link` | `PackedInt32Array` ×2 | The sector that holds each respawn pose, so relocation is O(1) |
| `respawn_fallback` | `PackedInt32Array` | A respawn on the main route at or behind this one (itself for main-route respawns) |
| `grid_pose` | `Array[Transform3D]` | Exactly 12. Slot 0 is pole position |
| `grid_sector_gate`, `grid_sector_link` | `PackedInt32Array` ×2 | The sector that holds each grid pose |

**`CourseRoute`** (a sub-resource, `src/core/course/course_route.gd`)

| Field | Type | Meaning |
|---|---|---|
| `id` | `StringName` | Stable id from Blender (also used in logs) |
| `kind` | `StringName` | `&"main"` (the lap reference), `&"branch"` (an alternative road: shortcut, lane split, deck), `&"cpu"` (an authored enemy line), `&"item"` (a projectile line), `&"cut"` (an off-road boost-cut line) |
| `branch_type` | `StringName` | Authored, for example `&"shortcut"`, `&"lane_split"`, `&"deck"`. Bots weight their plans by it (`BotSet.branch_factor`, as today) |
| `closed` | `bool` | True for loops. `main` is always closed and starts at the line |
| `length`, `spacing` | `float` | Route length. Sample spacing in metres (an ADR-0005 import setting, default 1.0 m). Sample i lies at along = i × `spacing`, and the last sample is at `length` |
| `fork_route`, `fork_along`, `merge_route`, `merge_along` | `int`, `float` | Where an open route leaves and rejoins its parent route (−1 for closed routes) |
| `min_speed`, `min_boost` | `float` | Entry requirements from custom properties: a speed-gated jump, a boost-cut. 0 means none |
| `pos`, `tangent`, `up` | `PackedVector3Array` | Per sample. right = `tangent.cross(up)`, and lateral is positive to the right |
| `half_left`, `half_right` | `PackedFloat32Array` | Per sample: the lateral distance from the line to the end of the road surface on each side |
| `clear_left`, `clear_right` | `PackedFloat32Array` | Per sample: the lateral distance to the first wall or drop within the bake's scan range, or the scan range itself when the side is clear |
| `edge_flags` | `PackedInt32Array` | Per sample: what lies past each road edge. Bits 0-3 are the left side and bits 4-7 the right: `WALL`, `OFFROAD`, `DROP` (a rail-less edge), `ROUTE` (the edge is open to another route) |
| `s_main` | `PackedFloat32Array` | Per sample: the lap-reference distance. It equals along on `main`, and on a branch it is interpolated from fork to merge by the along fraction (as the frozen `branch_distance_for_s` does). It is non-decreasing on every route |
| `lane_count`, `lane_offset` | `int`, `PackedFloat32Array` | Optional lanes: `lane_count × n` lateral offsets, ordered **left to right** |
| `span_next` | `PackedInt32Array` | Per sample: the first span whose `span_to` ≥ that sample's along |
| `span_from`, `span_to`, `span_lat_lo`, `span_lat_hi`, `span_value` | `PackedFloat32Array` | Spans sorted by `span_from`: along range, lateral range (signed, + right) and a kind-specific value |
| `span_kind`, `span_ref`, `span_side` | `PackedInt32Array` | Kind (below). `span_ref` is a surface id, hazard id, mover id, feature id or route index. `span_side` is −1 left, +1 right, 0 none |

**Span kinds:**
- `SURFACE`: a non-road surface on the road, such as a slick or sand patch. `ref` is the surface id.
- `HAZARD`: a static hazard area. `value` is the minimum crossing speed, 0 for an ordinary hazard.
- `MOVER`: a moving collider that meets the route, such as a drawbridge gate, a cart or barrels. `ref` is the ADR-0002 mover id.
- `RAMP`: the lip is at `span_to`, and `value` is the lip height.
- `PAD`: a boost pad.
- `OPEN_EDGE`: a rail-less edge. `side` says which.
- `WALL_OPENING`: a gap in the wall onto off-road. `side` says which.
- `JUNCTION`: a fork or merge mouth. `ref` is the other route.

**How the tables are filled.** The bake fills these tables by sampling the authored route against `TrackCollisionData` at import: lateral ground casts and wall sweeps, and mover pose curves swept against the route corridor. The algorithm is ADR-0005's. This ADR fixes what each field means.

**Tuning.** The progress tuning values live in **`CourseTuning`** (a `Resource` script in `src/core/course/`, instance `assets/data/core/course_tuning.tres`):

| Field | Default | Meaning |
|---|---|---|
| `progress_rate_cap` | 1.95 | Ported from the frozen game |
| `progress_slack` | 0.03 m | Ported from the frozen game. It was a `const` there and becomes data here |
| `wrong_way_distance` | — | Backward distance that sets the wrong-way flag |
| `wrong_way_clear` | — | Forward distance that clears it |
| `lost_distance` | — | Outside distance beyond which the kart is off course |
| `locate_window_m` | — | Search window of `RouteCursor` |

The defaults marked "—" are not chosen here. Story 023 sets them, starting from playtest values.

### 3. Checkpoint model
- **Gate.** A gate is a quad in the plane through `gate_xform.origin` with normal `fwd = −basis.z`. Its extents are ±`half.x` along right and ±`half.y` along up. Gates are authored as Blender empties: +Y along travel (ADR-0001 §2), with the scale giving the extents (ADR-0005).
- **Sector.** The sector (a, k) is the volume between gate a and its k-th next gate b.
  - **Bake rule:** every corner of b lies in front of a's plane, and every corner of a lies behind b's plane. This keeps the fraction in the next bullet monotone even for gates that are not parallel.
- **Fraction inside a sector:**
  - d_a = (p − o_a)·fwd_a, which is ≥ 0 past a.
  - d_b = (p − o_b)·fwd_b, which is ≤ 0 before b.
  - t = d_a / (d_a − d_b).
  - t in [0, 1] is inside, t > 1 is past b, t < 0 is behind a.
- **Outside distance.** The frame is interpolated at t: origin, normalised right and up, and half extents.
  - lateral = (p − o_t)·right_t;
  - outside = max(0, |lateral| − hw_t) + max(0, |vertical| − hh_t) + the distance of t beyond [0, 1] in metres.
  - The vertical term separates stacked decks, such as a bridge over a road.
- **Groups.**
  - A group is one stage of the lap. Gates on alternative paths at the same stage share a group id.
  - Group ids are non-decreasing along every next link, except at the wrap into group 0.
  - **Key groups** (`key_groups`, plus group 0) must be crossed by **every** legal path around the lap exactly once. The bake checks this on the link graph.
  - Non-key gates exist only to resolve progress, so a branch may have more or fewer of them than the main road over the same stretch.
- **`gate_s`.** On main it is the along of the gate. On a branch it is `s_main` at the gate. Gate 0 has `s` = 0.
- **Coverage.** Gates must cover every legal path, including airborne ones such as cannon arcs and jumps: tall gates, or a `branch` route with gates in the air. `track_check` samples the authored arcs.

### 4. Progress computation (`CourseProgress`, per kart, RefCounted)

**State**
- the cursor (`gate`, `link`);
- `s` (the raw in-lap value from the sector, in [0, `lap_length`));
- `distance` (smoothed race distance, continuous across laps);
- `lap`, `key_next`, `invalid_wraps`, `rejected_crossings`;
- `back_run` and `wrong_way`;
- `off_course`;
- `safe_gate`.

**Per-tick outputs**
- `line_crossed`: +1, −1 or 0;
- `crossing_rejected`: bool.

Lap & Position reads these after the call. There are no signals on the per-tick path, which also avoids RefCounted signal cycles (`.claude/rules/godot-refcount.md`).

**`CourseData.progress(p, position, moved, safe, tuning)`.** It runs once per kart per tick after `KartBody.step`, in `RacerRegistry` slot order. `moved` is the distance actually travelled this tick, and `safe` means the kart is grounded on a road surface outside any hazard (the caller decides).

1. **Fraction.** Compute t and outside for the cursor's sector.
2. **Advance or retreat** (bounded by `MAX_SECTOR_STEPS`, a named `const` of 8, which is a safety bound and not tuning):
   - While t > 1, cross gate b forward: take b's next links and pick the sector with the **smallest outside**. Ties go to the lowest link index.
   - While t < 0, cross gate a backward: take a's previous links the same way.
   - Each crossing applies the lap rule (§5).
3. **Off course.** If the best outside distance is > `lost_distance`, set `off_course`, hold `s` and `distance`, and credit nothing.
   - On later ticks, search the sectors up to 2 links around the cursor.
   - If that fails, run a full search over all sectors. A full search credits no gate it skipped, so an illegal jump earns nothing.
4. **Raw progress.** s = lerp(s_a, s_b, t), where s_b counts as `lap_length` when b is in group 0.
5. **Smoothed race distance.**
   - raw = (lap − 1) × `lap_length` + s.
   - distance = prev + clamp(raw − prev, −allow, +allow), where allow = `progress_rate_cap` × moved + `progress_slack`. This is the frozen `limit_progress` rule.
   - It is applied to a quantity that is already continuous across a valid line crossing, so no wrap handling is needed.
   - Smoothing is **skipped (snap)** on a lap-rule event that is not a valid forward crossing (rejected crossing, backward line crossing) and on `relocate`.
6. **Wrong way.**
   - Δ = distance − prev.
   - Δ < 0 adds −Δ to `back_run`.
   - Forward travel subtracts from `back_run`, and passing `wrong_way_clear` resets it.
   - `wrong_way = back_run ≥ wrong_way_distance`.
   - It is computed from distance only, so a kart sliding backwards counts and a kart turned around but standing still does not.
7. **Safe gate.** If `safe`, `safe_gate` is set to the cursor's gate.

**Relocation.** `relocate(p, sector_gate, sector_link, position)` is used on respawn and teleport. It sets the cursor with no search, credits no crossings, keeps the key state (the frozen `LapCounter.resync` rule: a kart placed past a key it never crossed must still cross it) and snaps `distance`. `relocate_search(p, position)` does a full search for cases without a baked sector.

**Cost.** In the common tick, a kart stays in one sector and pays two plane distances and one frame lerp. Crossing a gate adds one candidate evaluation per link, so the update is O(1) amortised.

### 5. Laps and ranking
**The lap rule** ports `LapCounter` (stories 001 and 003), driven by gate crossings instead of an `s` wrap:
- **Forward across a key group** that equals `key_groups[key_next]`: `key_next += 1`.
- **Forward across group 0:**
  - if `key_next == key_groups.size()`, then `lap += 1` and `line_crossed = +1`;
  - otherwise `rejected_crossings += 1`, `invalid_wraps += 1` and `crossing_rejected = true`.
  - Either way, `key_next = 0`.
- **Backward across group 0:**
  - if `invalid_wraps > 0`, then `invalid_wraps −= 1`;
  - otherwise `lap −= 1` and `line_crossed = −1`.
  - Then `key_next = key_groups.size()`.
- **Backward across** `key_groups[key_next − 1]`: `key_next −= 1`.

**Lap & Position** (Feature) owns everything built on these counts: `max_lap` ("a lap counts only the first time it is reached"), lap times, finish and events.

**Ranking** (Lap & Position):
- Finished karts come first, ordered by finish time.
- The rest are ordered by `distance`, descending.
- Ties are broken by `RacerRegistry` slot on every PC.
- Remote karts are ranked from the wire's `lap` and `distance` (ADR-0006 decides the encoding; float32 `distance` resolves about 2 mm at 16 km). Receivers never recompute a remote kart's progress.

**Kart-pair broadphase.** Kart Physics' broadphase on route distance uses `distance`.

### 6. Routes and baked tables

**Locating a kart on a route.** `RouteCursor` (per kart, per route) locates a world point by a windowed search of ± `locate_window_m` around its last sample. That is O(1) amortised, with a full O(n) search when the hint is invalid. The result is along, signed lateral (+ right), vertical offset, outside and the sample index.

**Sampling.** `route_sample(r, along, out)` lerps the tables between samples. Lerped vectors are renormalised.

**Spans ahead.** `spans_ahead(r, along, look, kind_mask, out_idx)` starts at `span_next[i]` and walks forward while `span_from` ≤ along + look, wrapping on closed routes. It is O(k) in the number of spans returned.

**Mapping a lap distance to a route.** `along_for_s(r, s)` binary-searches `s_main`. It maps a `CourseProgress.s` onto a route.

**What the tables replace.** The bot references listed in Context map onto the tables like this:

| Frozen reference | New source |
|---|---|
| `half_width_at`, `sim.road_half_width`, the `wall_margin` "usable" width | `half_left/right`, `clear_left/right` at the bot's along and at along + look |
| `length`, `wrapf(..., length)` | `CourseRoute.length`, `closed` |
| `point_at`, `tangent_at`, `normal_at`, `branch_point_at` | `route_sample` (pos, tangent, right) |
| `branches[].s_in/s_out`, `branch_count`, `branch_index`, `branch_length`, `data.branches[].id/type` | `routes` with kind `branch`, `fork_*`/`merge_*`, `length`, `id`, `branch_type` |
| `branch_along`, `distance_to_path`, `track.query` | `RouteCursor` locate (along, lateral, outside) |
| `branch_distance_for_s` | `along_for_s` |
| `data.branches[].open_edge_reach`, `data.open_edges` | `edge_flags` `DROP` and `OPEN_EDGE` spans |
| `data.wall_openings` (`_zone_open_sides`) | `WALL_OPENING` spans with side |
| `zone_s_range`, `zone_lat_range`, `zone_types[].on_road`, `slick_on_main_between` | `SURFACE` spans (along and lateral range, surface id), read with `spans_ahead` |
| `zone_routes`, `zone_boost_cut`, `zone_route_via`, `zone_ids` | routes with kind `cut` (via points are in the samples) and `min_boost` |
| `on_ground_zone` (now) | the bot's own `KartSnapshot.surface_id` |
| `on_ground_zone` (ahead, `_line_crosses_zone`) | `edge_flags` `OFFROAD` beyond `half_left/right` |
| `ramp_lip_s`, `ramp_paths` | `RAMP` spans per route |
| `hazard_gates`, `hazard_bounds` | `HAZARD` spans with `value` = minimum crossing speed |
| `data.movers` (gate kind, path, path_from/to; travelers) | `MOVER` spans (mover id, along range). Timing comes from Track Hazards' pure functions of time, not from Course Data |
| `respawn_pose`, `respawn_back_off` | §9 |

**Lanes.** Lanes are optional baked offsets. When a route has none, bots keep computing lateral choices inside `clear − margin`, as the frozen barrel and slick lanes do.

### 7. Bots read routes only
- CPU Racers read `CourseData` routes, samples, spans and `CourseProgress`, their own `KartSnapshot`, other karts' snapshots through `RacerRegistry`, and Track Hazards' timing functions.
- They **never** call `CollisionQuery`. Anything a bot needs about the geometry ahead is baked into the tables.
- If a bot need is found that the tables cannot answer, the schema is extended here. A ray is not added to the bot.

### 8. Items
- **`item_box_pose(i)`** returns `box_pose[i]`. The hover height above the ground point is a tuning value of Items (`ItemSet`), as the frozen `theme.item_box_size` is today.
- **Homing projectiles** follow a route of kind `item` (falling back to `main`) by along and lateral offset. A target's position comes from its `CourseProgress.s` through `along_for_s`.
- **Projectile collision** still uses `CollisionQuery` (Items is allowed to).

### 9. Respawn selection rule
- **Which respawn.** `respawn_pose(p, fallback)` returns `respawn_pose[gate_respawn[p.safe_gate]]`. With `fallback = true` it returns that respawn's `respawn_fallback` entry instead.
- **Who sets `fallback`.** Fall & Respawn sets it when the previous respawn failed (a sink within the respawn immunity) or when the sink was in a speed-gated hazard. This is the frozen `_repeat_sink` / `_gate_sink` rule.
- **After the respawn.** The kart is relocated to that respawn's baked sector.
- **Bake invariants:**
  - A respawn's `s` is ≤ the `gate_s` of every gate that uses it, so a respawn never gains progress.
  - A respawn never lies across the line from its gates, so a respawn never changes `lap`.
  - Every respawn is on road ground, outside hazards and movers' swept volumes (checked against collision by `track_check`).

### 10. Start grid
- **Twelve poses**, `grid_pose[0..11]`, are baked. They are either explicit empties or generated by ADR-0005 from one start empty and a pattern.
- **Who assigns slots.** Race Session maps racers to slots: registry order, or the previous result in a Grand Prix.
- **Initial progress.** Each kart starts relocated to its baked sector with `lap = 0`, `key_next = key_groups.size()` and `distance = s − lap_length` (negative, behind the line). The first forward line crossing gives lap 1, as today.
- **Bake checks:** every pose is behind gate 0, on road ground, and spaced at least 2 × the largest kart radius plus a margin from the others.

### 11. Mirror
`CourseData.mirrored()` returns a **new** object built once at load. It never mutates the loaded resource (ResourceLoader caching).

It applies ADR-0001 §7:
- **Positions:** x → −x for every gate origin, sample position, box, respawn and grid pose.
- **Directions:** the x component of every tangent and up is negated.
- **Poses:** every basis B becomes M·B·M with M = diag(−1, 1, 1).
- **Left/right fields swap:** `half_left` ↔ `half_right`, `clear_left` ↔ `clear_right`, and the left and right nibbles of `edge_flags`.
- **Spans:** lateral ranges become [−hi, −lo], and `span_side` is negated.
- **Lanes:** order is reversed and offsets are negated.
- **Unchanged:** gate, group, link, route and span order; `s`, `along` and length values; extents.

Because the mirrored gate basis stays a proper rotation (M·B·M), the right axis remains right of the mirrored travel direction, and all lateral values computed at run time are correct with no flag. This is the "left/right data lives in Course Data" half of ADR-0002's mirror paragraph.

### 12. Determinism
- `progress`, `relocate`, `RouteCursor` locate, `route_sample` and `spans_ahead` are pure functions of their inputs and the loaded data. They draw no randomness and read no time.
- Every choice is made by index with fixed tie-breaks: lowest link index, then lowest sector index in a full search.
- There is no Dictionary iteration on the per-tick path.
- Progress is updated in `RacerRegistry` slot order after the step (ADR-0001 §6).
- Same inputs give the same progress on one machine. Cross-machine bit-exactness is not required, because each owner computes its own kart's progress and the wire carries the result.

### 13. Load checks and validation
- **At load** (cheap): `format_version`; array lengths consistent; exactly one `main` route; gate 0 in group 0; 12 grid poses; every link index in range. A failure refuses the track and says why.
- **At bake and in the mesh `track_check`** (authoring time, against `TrackCollisionData`):
  - the gate sector rule;
  - the key-group coverage of every path;
  - non-decreasing groups and `s_main`;
  - gates covering airborne paths;
  - respawn and grid invariants;
  - every box, respawn and grid pose matching a ground cast within tolerance (position and normal);
  - routes inside the road;
  - `span_next` consistent.

### Architecture Diagram

```
Blender empties + curves ──glTF──▶ ADR-0005 import (samples against TrackCollisionData) ──▶ CourseData.res
                                                                                   │ mirrored()? new object, swap L/R
                                                                                   ▼
             CourseData (Resource, read-only at run time)
  gates: xform, half, group, s, next/prev (CSR), respawn ── key_groups
  routes[CourseRoute]: samples (pos, tangent, up, half L/R, clear L/R, edge flags, s_main, lanes, span_next)
                       spans (SURFACE, HAZARD, MOVER, RAMP, PAD, OPEN_EDGE, WALL_OPENING, JUNCTION)
  boxes · respawns (+ sector, fallback) · grid[12] (+ sector)
        │                         │                               │                    │
 progress(p, pos, moved, safe)  route_sample / spans_ahead /     item_box_pose      respawn_pose / grid_pose
        ▼                         RouteCursor.locate                 ▼                    ▼
 CourseProgress (per kart)        ▼                               Items              Fall & Respawn, Race Session
  cursor, s, distance, lap,    CPU Racers (never CollisionQuery)
  key_next, wrong_way, safe_gate
        ▼
 Lap & Position (max_lap, times, finish, ranking) ──▶ HUD · wire (lap, distance via ADR-0006) · broadphase
```

### Key Interfaces

Each `class_name` lives in its own file under `src/core/course/`. These names refine the architecture sketch, which has `Progress`, `Route`, `route(kind, lane)` and `progress(p, position, moved)`:
- `CourseProgress` and `CourseRoute` are prefixed, because global class names collide easily.
- Lanes are read with `lane_offset` rather than chosen in `route()`.
- `progress` gains `safe` and `tuning`.

```gdscript
class_name CourseData extends Resource
const FORMAT_VERSION: int = 1                      ## schema version; the loader refuses others
func mirrored() -> CourseData                      # new object; never mutates self
func validate_load() -> PackedStringArray          # empty = ok; each line says why it failed
# Progress
func progress(p: CourseProgress, position: Vector3, moved: float, safe: bool, tuning: CourseTuning) -> void
func relocate(p: CourseProgress, sector_gate: int, sector_link: int, position: Vector3) -> void
func relocate_search(p: CourseProgress, position: Vector3) -> void
func init_grid_progress(p: CourseProgress, slot: int) -> void
# Checkpoints (tools, tests, HUD; not for per-tick hot loops)
func gate_count() -> int
func checkpoint_into(index: int, out: CourseGate) -> void
# Routes
func main_route() -> CourseRoute
func route_count() -> int
func route_at(i: int) -> CourseRoute
func route_sample(r: CourseRoute, along: float, out: RouteSample) -> void
func lane_offset(r: CourseRoute, along: float, lane: int) -> float
func spans_ahead(r: CourseRoute, along: float, look: float, kind_mask: int, out_idx: PackedInt32Array) -> int
func along_for_s(r: CourseRoute, s: float) -> float
# Poses
func item_box_count() -> int
func item_box_pose(i: int) -> Transform3D
func respawn_pose(p: CourseProgress, fallback: bool) -> Transform3D
func respawn_sector(p: CourseProgress, fallback: bool) -> Vector2i   # (gate, link) for relocate
func grid_pose(slot: int) -> Transform3D

class_name CourseProgress extends RefCounted   # gate, link, s, distance, lap, key_next, invalid_wraps,
                                               # rejected_crossings, back_run, wrong_way, off_course,
                                               # safe_gate; per tick: line_crossed, crossing_rejected
class_name RouteCursor extends RefCounted      # sample hint; func locate(r, position, out: RouteLocation) -> void
class_name RouteLocation extends RefCounted    # along, lateral, vertical, outside, sample
class_name RouteSample extends RefCounted      # position, tangent, up, right, half_left, half_right,
                                               # clear_left, clear_right, edge_flags, s_main
class_name CourseRoute extends Resource        # §2 table
class_name CourseGate extends RefCounted       # xform, half, group, s, next links (tools and tests)
class_name CourseTuning extends Resource       # §2 tuning fields, each @export with a ## comment
```

### Implementation Guidelines
- Course Data **must** stay separate from collision. It **must never** hold triangles, and `CollisionQuery` **must never** be called at run time by Course Data or CPU Racers.
- CPU Racers **must** read only `CourseData`, `CourseProgress`, snapshots, `RacerRegistry` and Track Hazards' timing functions. A missing bot input **must** be added to the baked tables, not answered by a ray.
- Per-tick code **must** use the caller-owned `RouteSample`, `RouteLocation` and `RouteCursor` objects and **must never** allocate per call. `checkpoint_into` and `CourseGate` are for tools, tests and the HUD.
- `progress` **must** run once per kart per tick after the step, in `RacerRegistry` slot order. Teleports **must** use `relocate`, never a `progress` call with a large `moved`.
- Lap counting **must** come from gate crossings and the key-group rule, never from a wrap of `s` or `distance`.
- Ranking **must** use `distance`, with ties broken by registry slot.
- A full search **must never** credit a gate crossing.
- `mirrored()` **must** return a new object, **must** swap every left/right field and lane order, and **must never** mutate the loaded resource. Code **must never** store a left/right fact outside these swapped fields.
- `CourseData` **must not** use property setters on its packed arrays. A 4.7+ element write would not call them anyway.
- Tuning values **must** live in `CourseTuning` (`assets/data/core/course_tuning.tres`). Only named `const` safety bounds (`MAX_SECTOR_STEPS`, epsilons) may stay in code.
- New code **must not** reference `src/legacy/`. The frozen `LapCounter`, `TrackModel.limit_progress` and `KartSim._respawn` rules are ported from this ADR's text and the golden traces.

## Alternatives Considered

### Alternative 1: Spline-style progress (nearest point on the main route)
- **Description**: Keep the frozen model. Project the kart onto the main route's polyline (branches mapped to main `s`), and count laps when `s` wraps.
- **Pros**: The closest port of the frozen code, with one value for everything.
- **Cons**: On a 3D mesh the nearest point is ambiguous where roads stack or cross (bridges, loops, anti-gravity walls). Illegal cuts across an infield register as progress. Laps depend on a wrap heuristic (`ds < −L/2`).
- **Rejection Reason**: It breaks on stacked and looping geometry, which Mario Kart parity requires. Gates with groups are the proven KMP model. The spline is kept only as the route tables' `s_main`.

### Alternative 2: Bots look ahead with `CollisionQuery`
- **Description**: Bots cast rays to find walls, off-road and drops ahead instead of reading tables.
- **Pros**: No bake step for bot data, and always in sync with the geometry.
- **Cons**: There are 11 bots with several look-ahead probes each, inside the collision budget (ADR-0002: ≤ 0.3 ms). Rays see geometry, not meaning (a slick patch, a planned shortcut, a timed gate). Results depend on the probe pattern.
- **Rejection Reason**: The architecture forbids it, and the frozen bots' needs are semantic. Baking costs nothing at run time.

### Alternative 3: Engine navigation (`NavigationServer3D`, navmesh, agents)
- **Description**: Bake a navmesh from the road and drive bots with navigation paths.
- **Pros**: An engine feature with dynamic obstacles.
- **Cons**: A kart is not a navigation agent: it has momentum, a racing line, drift and lanes. Navigation would ignore surfaces, spans and the lap model, and would add a server to the headless tests.
- **Rejection Reason**: It does not fit racing lines. Routes with tables do, and they are what Mario Kart's enemy routes are.

### Alternative 4: One sub-resource per gate and per sample, or text `.tres`
- **Description**: `Array[Checkpoint]` and `Array[RoutePoint]` objects, saved as readable text.
- **Pros**: Readable, and easy to inspect in the editor.
- **Cons**: Thousands of objects per track, slower per-tick property reads, and a large text file.
- **Rejection Reason**: Packed arrays in binary `.res` match ADR-0002's choice. `CourseGate` and a debug dump give readability to tools.

### Alternative 5: Distance-field progress (a baked 3D grid of progress values)
- **Description**: Bake progress into a voxel or cell grid and read it at the kart's position.
- **Pros**: O(1) without a cursor.
- **Cons**: Memory grows with volume. Stacked roads need cells by height. Junctions blur, and laps still need gates.
- **Rejection Reason**: Gates and a cursor are O(1) amortised already, exact at gates and small.

## Consequences

### Positive
- One model answers laps, ranking, respawns, the wire's progress and bot look-ahead, and it works on stacked and looping roads.
- Illegal cuts earn nothing (key groups, plus the rule that a full search credits no gate), while authored shortcuts and branches count.
- Bots get richer data than the spline gave them (clear widths, edge kinds, spans by kind) at no run-time collision cost.
- Mirror is one pass at load. All lateral values at run time come out right with no flag.
- It is deterministic and headless-testable with no physics server.

### Negative
- Authoring cost: gates, routes, respawns and the grid must be placed in Blender. ADR-0005 can generate defaults (gates every N m along a route, respawns per gate), but key groups and airborne coverage need care.
- The bake is heavy: lateral scans against collision for every sample of every route.
- `CourseProgress.s` and `distance` are new semantics. The rebuilt kart's progress will not equal the frozen `track_s` exactly, so the trace comparison needs a tolerance.
- The tables are a snapshot of the geometry. Any mesh change needs a re-bake, which ADR-0005's import does automatically.

## Risks
- **Unverified engine behaviour:** the binary `.res` round-trip of typed `Array[Transform3D]` and `Array[CourseRoute]` on 4.8-beta3. Mitigation: story 023's first test saves and reloads a fixture and compares field by field.
- **Gate authoring errors** (a missing key gate on a legal path, sectors that violate the corner rule, gaps under jumps). Mitigation: the bake and `track_check` reject them with the gate ids. A debug view (`src/debug/`) draws gates, sectors and the cursor per kart.
- **Junction cursor flicker** where two sectors overlap (parallel lanes of a split). Mitigation: smallest outside first, then link order, both deterministic. The distance smoothing hides small jumps. Hysteresis is added only if tests show flicker; it would be a `CourseTuning` field.
- **Off-course hold during long flights** (cannons, big jumps) freezes `distance` for seconds, so the ranking lags. Mitigation: gates must cover authored airborne paths, which `track_check` samples.
- **Performance estimates are unmeasured** (see below). Mitigation: story 023's benchmark against the targets.
- **The respawn fallback can be missing** on a track with no main-route respawn behind a branch respawn. Mitigation: a bake invariant (`respawn_fallback` always points to a main-route respawn).
- **Wire precision** of `distance` as float32. About 2 mm at 16 km is enough, but ADR-0006 confirms the encoding.
- **Open questions** (for the owner, ADR-0005 or story 023):
  1. Do generator-made tracks (Castle Circuit, Dungeon Depths) get their gates and routes by an export to Blender empties (ADR-0005), or by a converter tool? A converter reading the frozen `TrackData` would need an ADR-0001 §9 exception.
  2. Are per-track `CourseTuning` overrides needed, or is one shared instance enough?
  3. Should the `cpu` routes carry authored per-point hints (no-drift, brake zone, like KMP's enemy-point settings), or do bots keep deriving them?
  4. Point-to-point (sprint) courses are out of scope (`main` is always closed). Confirm for Alpha modes.
  5. The defaults of `wrong_way_distance`, `wrong_way_clear`, `lost_distance` and `locate_window_m` are to be set in story 023.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| systems-index.md row 3: Course Data (checkpoints, routes, respawns) | Checkpoints, routes and respawns separate from collision | §1-§4, §9. Gates, routes and respawns in `CourseData`, with no triangles |
| systems-index.md row 11: Lap & Position Tracking | Laps with checkpoint integrity, reverse-over-line handling, position ranking | §5: the key-group lap rule ports `LapCounter`. Ranking by `distance` with slot tie-break |
| systems-index.md row 12: Fall & Respawn | Respawn to the last safe road, with a main-road fallback | §9: `safe_gate`, `gate_respawn` and `respawn_fallback` |
| systems-index.md row 15: Items & Item Boxes | Box poses on the road, item lines | §8: `box_pose`, `item` routes, `along_for_s` |
| systems-index.md row 16: CPU Racers | Routes and tables only, never `CollisionQuery`. Shortcuts, lanes, slicks, hazards, gates | §6-§7: the route tables, spans and the frozen-reference mapping |
| systems-index.md row 13: Track Features | Ramps, pads and cannons known to bots and progress | `RAMP` and `PAD` spans. Gates cover airborne paths |
| systems-index.md row 7: Blender Track Pipeline | A baked schema for the import to target | §2 is the schema ADR-0005 bakes |
| systems-index.md row 31: Grand Prix & Speed Classes (mirror) | Mirror mode | §11 `mirrored()` |
| systems-index.md row 27: Anti-Gravity & Wall-Riding | Progress on walls and loops | Gates are 3D planes with up extents, and nothing assumes world up |
| architecture.md Performance Budgets | 12 karts inside ≤ 3 ms per tick; kart-pair broadphase on route distance | Progress ≪ 0.1 ms per tick (below). `distance` feeds the broadphase |

No system GDD exists yet. This table cites the systems-index rows and the architecture.

## Performance Implications
- **CPU (targets, to be registered once measured):**
  - `progress` for 12 karts: **≤ 0.05 ms p95 per tick**, release export, owner's PC. Estimate: about 2-4 µs per kart for two plane distances, one frame lerp and rarely one crossing. UNVERIFIED.
  - Course Data reads for 11 bots (locate, three samples, spans ahead): **≤ 0.1 ms p95 per tick**, counted in CPU Racers' share. UNVERIFIED.
  - A full relocation search over about 300 sectors: ≤ 0.2 ms, once per teleport. UNVERIFIED.
- **Memory:** about 64 bytes per route sample (3 × Vector3, 6 floats, flags, `span_next`), so about 128 KB per 2 km route at 1 m spacing. About 1-2 MB per track with 10 routes, which is negligible against 2 GB. Estimate, UNVERIFIED.
- **Load time:** reading the `.res` takes a few ms (estimate). `mirrored()` is one linear pass over all arrays, also a few ms (estimate).
- **Network:** progress on the wire is `lap` plus `distance` (about 5 bytes) in place of today's `LAP` and `TRACK_S` floats. ADR-0006 owns the encoding.

## Migration Plan
Nothing is migrated in place. The frozen game keeps its spline, `LapCounter` and bots in `src/legacy/`.

1. **Story 023:**
   - implement `CourseData`, `CourseRoute`, `CourseProgress`, `RouteCursor`, `RouteSample`, `RouteLocation`, `CourseGate` and `CourseTuning` in `src/core/course/`, test-first (`tests/unit/course/`);
   - add the mesh `track_check` validations (§13);
   - use a hand-built fixture course plus one course baked from a generator track.
2. **Story 024 (ADR-0005)** bakes the schema from Blender empties and curves.
3. **Story 025:**
   - Lap & Position and Fall & Respawn move onto `CourseProgress` and the respawn rule;
   - Items moves onto box poses and item routes;
   - CPU Racers are rebuilt on routes and spans, replacing every frozen reference in the §6 table;
   - ADR-0006 puts `lap` and `distance` on the wire.

## Validation Criteria
- **Unit tests** (gdUnit4, `tests/unit/course/`, fixture courses built in code, no file I/O):
  - **Sectors:** the fraction is monotone along a sector, and `s` is continuous at a fork and at a merge.
  - **Lap rule:** every `LapCounter` case is ported:
    - forward laps;
    - reversing over the line and back (no extra lap);
    - an illegal cut that misses a key group (refused, `rejected_crossings` +1, recoverable);
    - a legal shortcut that crosses the shared key groups (counted);
    - invalid wraps undone by reversing.
  - **Smoothing:** `distance` never changes by more than `progress_rate_cap × moved + progress_slack` except on a snap event, and it is continuous across a valid line crossing.
  - **Wrong way:** set after `wrong_way_distance` of backward travel, and cleared after `wrong_way_clear`.
  - **Off course:** progress is held and no gate is credited during a full search.
  - **`relocate`:** keeps the key state.
  - **Respawn:** the pose is never ahead of `safe_gate`, the fallback is on main, and `lap` is unchanged.
  - **Grid:** the 12 grid karts start at lap 0, and the first crossing gives lap 1.
  - **Mirror:** `mirrored()` swaps `half_left`/`half_right`, `clear_*`, edge nibbles, span sides and lane order, and leaves the source untouched. A mirrored drive of a recorded path gives the same `s` sequence.
  - **Determinism:** two runs give identical progress traces.
- **Benchmark (story 023):** 12 karts' `progress` and 11 bots' reads inside a running tree, release export, against the targets above.
- **Equivalence:** on a course baked from a generator track, the new `CourseProgress.s` follows the golden traces' `track_s` (`production/qa/evidence/core-rebuild-story-001/golden/`, CSV columns `x`, `z`, `height`, `track_s`, `lap`) within a tolerance that story 023 sets. Lap counts must match exactly.
- **Grep:** no `CollisionQuery` reference under `src/ai/`, and no `src/legacy/` reference under `src/core/course/`.

## Related
- ADR-0001 (conventions: §1, §2, §6, §7, §9). Depends on it.
- ADR-0002 (collision; its mirror paragraph says left/right data lives here; `TrackCollisionData` is the validation target). Depends on it.
- ADR-0005 (Blender track pipeline; bakes this schema). Drafted in parallel, enabled by this ADR.
- ADR-0006 (network snapshot; `lap` and `distance` on the wire). Enabled by this ADR.
- `docs/architecture/architecture.md`: Module Ownership (Course Data), Data Flow 1 and 6, API Boundaries › CourseData (refined here, see Key Interfaces), Performance Budgets.
- `design/gdd/systems-index.md` rows 3, 7, 11, 12, 13, 15, 16, 27, 31.
- Frozen references (read-only, never imported): `src/legacy/test_track/lap_counter.gd`, `track_model.gd` (`limit_progress`, `respawn_pose`, item box helpers), `src/legacy/vehicle/kart_sim.gd` (`_respawn`), `src/legacy/ai/bot_driver.gd`, `src/legacy/debug/autopilot_driver.gd`, `src/legacy/items/item_manager.gd`, `src/legacy/net/kart_wire.gd`, `src/legacy/main.gd` (`_rank_key`, grid formula).
