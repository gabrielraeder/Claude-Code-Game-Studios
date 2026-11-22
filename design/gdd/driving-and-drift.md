# Driving & Drift — Design Document

---
**Status**: Reverse-Documented (Draft, pending owner review)
**Source**: `src/legacy/vehicle/kart_sim.gd` (`tick`, `_update_speed`, `current_speed_cap`, `_surface_cap_now`, `_update_surface`, `_clear_surface_tail`, `_end_drift`, `hit`, `apply_start`, `apply_hit_slowdown`, `_take_off`, `_land`, pad test in `_constrain_to_track`); `src/data/vehicle_stats.gd`; `src/data/surface_type.gd`; `assets/data/vehicles/armored_cart.tres`; `assets/data/vehicles/war_bike.tres`; `assets/data/surfaces/surface_set.tres`; `assets/tracks/castle_circuit/castle_circuit.tres`, `assets/tracks/dungeon_depths/dungeon_depths.tres` (`boost_pad_time`)
**Rebuild contract**: `docs/architecture/adr-0003-kart-physics-model.md` (v2, Proposed), `docs/architecture/adr-0002-collision-backend-and-surface-attributes.md` (v5, Proposed)
**Date**: 2026-11-22
**Verified By**: pending owner review
**Implementation Status**: Fully implemented in the frozen 2.5D game; to be re-implemented as `DriveState.drive()` on the new core (systems-index row 9: "Implemented (2.5D, migrate)")
**Systems index**: row 9 (Driving & Drift); row 28 (Turbo Reserve) is decided here
---

> **Provenance — reverse-documented.**
> Reverse-documented from `src/legacy` at commit HEAD (`00b5afc`) on 2026-11-22.
> Every number in this document is copied from the code or a data file, and the source file is named
> next to it. Derived numbers (examples) show their arithmetic. Where the *reason* for a rule or value
> had to be inferred from the code, it is marked **INTENT UNKNOWN**. Nothing marked "proposal" is
> adopted; those items are listed in **Open decisions for the owner** at the end.
>
> **What this document is for.** The frozen game's driving feel was tuned by the owner over stories
> 001-011 ("for initial version, the drift feels good enough", `design/game-brief.md`). This document
> states that behaviour as the design the rebuilt core must match (ADR-0003 parity rule), and states
> what changes on the new base.

---

## Summary

Driving & Drift is the control law that turns a racer's input (steer, throttle, brake, drift button)
into how the kart turns, how fast it goes and how much it slides, and it owns the 3-tier drift boost,
every boost source's effect on speed, and how surfaces change grip, steering and the speed cap. It is
the system behind Pillar 2 ("Drift is the skill"). On the new core it is the Gameplay-layer
`DriveState.drive()` function, which reads a `KartSnapshot` and writes a `KartIntent`; the physical
body (`KartBody`, ADR-0003) does the rest.

---

## 1. Overview

Each simulation tick, Driving reads the driver's input and the kart's current state and decides four
things: the yaw rate (how fast the heading turns), the target speed along the heading, the grip (how
quickly the velocity swings onto the heading; low grip is the drift slide), and whether a hop is
requested. Holding the drift button while steering above a minimum speed starts a drift whose
direction locks in; the longer and tighter the drift, the higher the charge tier (1, 2, 3, shown as
blue, orange and purple sparks); releasing pays a boost of that tier's duration. A boost raises the
speed cap by a fixed multiplier and triples acceleration, but never lifts speed above that boosted
cap, and overlapping boosts do not add (the longer one wins). Surfaces (grass, sand, mud, rubble,
shallows, slick, and on the new core road, boost pad and trick ramp) scale grip and steering, cap
speed, add drag, can forbid drifting, and in the slick's case keep their effect for a short tail after
the kart leaves them. Two vehicles ship with different numbers for the same rules: the Armored Cart
and the War Bike.

---

## 2. Player Fantasy

*A knight dog who reads a corner early, throws the cart sideways into it, holds the slide tighter
than feels safe while the sparks climb from blue to orange to purple, and fires out of the exit
faster than anyone who braked.*

- **Primary MDA aesthetics:** **Challenge** (game-concept rank 2: "3-tier drift boosts, racing lines")
  and **Sensation** (rank 3: "Boost and drift feel, speed, sparks").
- **Competence (SDT):** the tier ladder is a visible, readable skill meter. A higher tier is earned by
  holding a drift longer and steering *into* it (which both tightens the line and charges faster, §4.4),
  so the reward and the skill are the same act.
- **Autonomy (SDT):** within one corner the player chooses between a short safe drift (tier 1), a long
  tight one (tier 3) that risks a wall, or no drift at all; surfaces and shortcuts change that choice.
- **Pillar 2 — Drift is the skill:** the drift boost is the main skill-based speed source. The cap
  rule (boosts never exceed `max_speed × boost_speed_mult`) keeps boosts from snowballing into
  unbounded speed, so skill shows as *more time at the boosted cap*, not a higher top speed.
- **Pillar 1 — Online with friends first:** every rule is a deterministic function of input, state
  and data (no random numbers; the rubble wobble follows distance driven), so it simulates identically
  on each PC and reads on stream through spark colours.
- **Pillar 3 — Mario Kart-grade quality:** the frozen feel is the floor. The rebuild must match it
  (ADR-0003 parity rule, §8) before anything in it changes.

---

## 3. Detailed Design

`SIM_DT` is the fixed tick (ADR-0001). ADR-0003 counts "600 ticks (10 s)", so `SIM_DT = 1/60 s`; the
examples below use that value.

### 3.1 Core Mechanics

#### 3.1.1 Control gating (`kart_sim.gd` `tick`, `can_drive`)

1. **Control** is `spin_time <= 0`. Without control, steer, throttle and brake are read as 0.
2. **Stall:** while `stall_time > 0` (a too-early start, §3.1.9), throttle is read as 0; steer and brake
   still work.
3. While the kart is **sinking or falling to a respawn** (`sink_time > 0`), driving does not run:
   speed and velocity are 0 until the respawn. (On the new core this is Fall & Respawn's state; Driving
   produces a zero intent.)

#### 3.1.2 Speed (`_update_speed`, `current_speed_cap`, `_surface_cap_now`)

Speed is a signed scalar along the heading. Applied in this exact order each grounded tick (order
matters for parity):

1. **Slope gravity** (frozen: here; new core: in the body, ADR-0003 §1 — Driving omits it).
2. **Cap** = `min(base_cap, surface_cap)` where `base_cap = max_speed / max(floor_drag_mult, 1)`, or
   `max_speed × boost_speed_mult` while boosting (a boost replaces the floor term entirely).
   `surface_cap = max_speed × max_speed_frac` of the surface in force, or no cap when there is no
   surface, `max_speed_frac >= 1`, or the kart is boosting on a surface with `boost_ignores = true`.
   **INTENT UNKNOWN:** `floor_drag_mult` comes from the frozen `TrackModel.Query` (a per-floor drag
   value of the spline track); no shipped data has been traced to it here. See Open decision D6.
3. **Push:** while boosting, push = `accel × boost_accel_mult` *regardless of throttle*; otherwise
   `accel × throttle`. Push only raises speed toward the cap and never past it.
4. **Brake:** above 0 speed, subtract `brake × brake_input`; at or below 0, reverse at
   `accel × reverse_accel_frac × brake_input`.
5. **Coast:** with no throttle, no brake and no boost, speed moves toward 0 at `coast_drag`.
6. **Overspeed:** above the cap, speed eases down toward it at `overspeed_decel`, or at the surface's
   `surface_decel` when the cap in force is the surface cap. Never a snap.
7. **Surface drag:** `speed *= exp(-drag × dt)` unless boosting on a `boost_ignores` surface.
8. **Reverse limit:** speed is never below `-reverse_max`.
9. **Spin drag:** while spinning, `speed *= exp(-spin_drag × dt)`.
10. **Hit slowdown:** while a slowdown profile runs, speed above the profile floor drops at the
    profile rate, never below the floor (§3.1.8).

In the air, none of the above runs: planar velocity and speed are kept (frozen story 008 rule).

#### 3.1.3 Steering (`tick`)

- **Grounded, not drifting:**
  `yaw_rate = steer × turn_rate × low_speed × damp × sign(speed)`, times the surface's `steer_mult`.
  `low_speed` ramps steering in from 0 to full by `full_steer_speed`; `damp` removes up to
  `high_speed_steer_damp` of it at `max_speed`. Steering is inverted while reversing.
- **Grounded, drifting:** `yaw_rate = drift_dir × (drift_yaw_base + drift_yaw_range × clamp(steer × drift_dir, -1, 1))`.
  The kart always turns into the drift direction; steering into the drift tightens it, steering out
  widens it, and it can never turn the other way. `steer_mult` does **not** apply while drifting
  (code applies it only in the non-drift branch).
- **Bumpy ground:** on a surface with `bump_yaw > 0` and `|speed| > EPSILON` (0.001), a yaw wobble
  `bump_yaw × sin(phase)` is added; the phase advances by `TAU × bump_cycles_per_m × |speed| × dt`, so it
  follows distance driven and uses no random numbers.
- **Air:** the air yaw rate starts at the last grounded yaw rate clamped to `±air_yaw_max`, then moves
  toward `steer × air_yaw_max` at `air_yaw_accel` per second. Drift yaw does not apply in the air.

#### 3.1.4 Grip (`tick`)

- Grip is a rate (1/s). Each grounded tick, velocity is lerped toward `heading × speed` by
  `clamp(grip × dt, 0, 1)`. This lerp is what makes the drift slide.
- `grip = drift_grip` while drifting, otherwise `grip`; times `1 + bank_grip_gain × |sin(bank)|`
  (`bank_grip_gain` is 0.0 on both vehicles, so banks have no grip effect today); times the surface's
  `grip_mult`. During a wall slide the body clamps grip to `wall_slide_grip` (Kart Physics owns that
  clamp on the new core, ADR-0003 §3).
- In the air there is no grip.

#### 3.1.5 Drift (`tick`, `_end_drift`)

**Start** — all of these on the same tick:
- not already drifting, has control, **grounded**;
- drift button **held** (a level, not a press edge — holding the button and then steering past the
  threshold starts a drift; **INTENT UNKNOWN** whether this is deliberate);
- `|steer| > drift_start_steer` (strict);
- `speed > drift_min_speed` (strict);
- the surface in force allows drifting (`drift_allowed`, or no surface).

On start: `drift_dir = +1` if steer > 0 (left) else -1; charge time and tier reset to 0; event
`drift_started(direction)`.

**Charge** — every tick while drifting (grounded *or* airborne):
`drift_time += dt × (1 + drift_charge_steer_bonus × max(steer × drift_dir, 0))`. The tier is the
number of `drift_tier_times` entries that `drift_time` has reached (3 entries, so tiers 0-3).

**End**, checked in this order each tick:
1. The surface in force does not allow drifting → ends, **no boost**; `surface_drift_ends` counter +1.
2. Button released, or `speed < drift_min_speed × drift_end_speed_frac`, or control lost →
   ends and **pays** the current tier (note: dropping below the end speed still pays).
3. A hit (`hit()`, §3.1.8) ends the drift first with **no boost**, so the "control lost" path never pays
   after a hit.

**Pay:** tier 0 pays nothing. Tier `t >= 1` sets `boost_time = max(boost_time, drift_boost_times[t])`.
Event `drift_ended(tier, boost_seconds)`.

A drift held into a jump carries on through the air and keeps charging; a drift can never *start* in
the air.

#### 3.1.6 Boost (all sources)

- One timer, `boost_time`, counts down by `dt` every tick. While it is above 0 the kart is boosting
  (§3.1.2 cap and push).
- **Every source merges by max, never by sum:** `boost_time = max(boost_time, source_seconds)`. A
  boost granted while a longer one is running adds nothing. This is the rule a turbo reserve would
  change (§3.4, Open decision D1).
- **Sources** in the frozen game:

| Source | Seconds | Where |
|---|---|---|
| Drift tier 1 / 2 / 3 | 0.7 / 1.1 / 1.6 (both vehicles) | `VehicleStats.drift_boost_times` |
| Start boost level 1 / 2 / 3 | 1.4 / 1.7 / 2.0 | `VehicleStats.start_boost_times` |
| Trick landing | 0.7 | `VehicleStats.trick_boost_time` |
| Boost pad (refreshed every grounded tick on the pad) | Castle Circuit 1.10, Dungeon Depths 0.80 (field default 1.1) | `TrackData.boost_pad_time` in each track `.tres` |
| War Horn item | owned by Items | not in Driving's data |

- A hit (spin) sets `boost_time = 0`.

#### 3.1.7 Surfaces (`_update_surface`, `_clear_surface_tail`, TD-004)

- Grounded: the surface under the kart is sampled each tick. Airborne: the last surface is kept.
- **Surface in force** (`surface_effect`):
  - on a surface with `tail_time > 0` (slick): the tail timer is set to that surface's `tail_time` every
    tick; the surface is in force;
  - on a surface with `tail_time = 0` (grass, sand, mud, rubble, shallows): the tail is **cleared at
    once** (TD-004 fix) and that surface is in force;
  - on plain road (frozen: no surface zone): the tail counts down; while it is above 0 the tailed
    surface stays in force, then nothing is.
- A respawn clears the tail (TD-004).
- **New-core rule (parity):** road (id 0), `boost_pad` and `trick_ramp` must behave as the frozen
  "no surface" branch — neutral handling and the tail keeps counting down — because in the frozen game
  pads and ramps were not surface zones and did not end a slick's tail. **INTENT UNKNOWN** whether the
  owner wants a pad to cut a slick tail; matching the frozen behaviour is the default.

#### 3.1.8 Hits and slowdowns (`hit`, `apply_hit_slowdown`)

- **Spin hit:** ignored if already spinning. Otherwise `spin_time = VehicleStats.spin_time`, the drift
  ends without boost, `boost_time = 0`. During the spin there is no control and spin drag applies.
  Callers: Track Hazards (movers), Items.
- **Slowdown profile** (index 0 light, 1 medium, 2 heavy; out-of-range index ignored): for
  `duration` seconds, speed above `min_speed_frac × max_speed` falls at `decel_frac × max_speed` m/s²,
  never below that floor. No loss of control.
- Hit immunity (`hit_immunity_time`, 0.6 s both vehicles) is a timer Driving keeps; who checks it is
  the hit source's concern.

#### 3.1.9 Race start (`apply_start`)

- The race-start system decides a level at GO from when accelerate was last pressed (doc comments in
  `vehicle_stats.gd`): within `start_perfect_window` (0.15 s) = level 3, within `start_good_window`
  (0.35 s) = level 2, within `start_ok_window` (0.6 s) = level 1, pressed and held earlier = stall.
- Driving applies it: level 1-3 sets `boost_time = max(boost_time, start_boost_times[level])`; a level
  outside the array is ignored; a stall sets `stall_time = start_stall_time` (1.0 s).

#### 3.1.10 Trick jump (`tick`, `_take_off`, `_land`)

- While grounded, Driving tracks seconds since the drift button was last *pressed* (rising edge).
- At takeoff, a trick is armed if that time `<= trick_window` (0.3 s).
- On landing, an armed trick pays `boost_time = max(boost_time, trick_boost_time)` (0.7 s) if the
  airtime was `>= trick_min_airtime` (0.25 s). Sinking or respawning disarms it.
- On the new core, a flight started by a hop alone (`hop_airborne`) never counts as trick airtime
  (ADR-0003 §3). With `hop_speed = 0` this cannot happen.

#### 3.1.11 Hop

- Frozen: the hop is **visual only** (`VehicleVisualStats.hop_duration` 0.4 s, `hop_height` 0.35 m on
  both vehicles); it never changes physics.
- New core: `KartIntent.hop` exists; the body adds `hop_speed` to the ride spring velocity.
  **`hop_speed` stays 0.0 through parity** (ADR-0003 §3). The trigger that sets `intent.hop` is
  **[inferred — confirm]**: the drift button's rising edge while grounded (the same edge the trick timer
  uses). A physical hop is Open decision D2.

### 3.2 State and Data

**`DriveState`** (one per racer, lives for the race, owned by the racer's controller; reset only by the
start and respawn events — ADR-0003 §3): drifting, `drift_dir`, `drift_time`, `drift_tier`,
`boost_time`, `spin_time`, `stall_time`, slowdown profile and timer, hit-immunity timer, slick tail
surface and timer, air yaw rate, last grounded yaw rate, since-hop timer, trick-pending flag, previous
drift button, start-boost level, `surface_phase`, `surface_drift_ends` counter.

**Data:**
- Per vehicle: `VehicleStats`, forked to `assets/data/core/vehicles/armored_cart.tres` and
  `war_bike.tres` with every value unchanged (ADR-0003 §10). The frozen `assets/data/vehicles/*.tres`
  are never read by new code.
- Surfaces: the core `SurfaceSet` in `assets/data/core/` (ADR-0002 v5): stable ids, unique, `>= 0`,
  append-only, never reused; **id 0 = `road`**; adds the kinds `road`, `boost_pad`, `trick_ramp` to the
  six frozen kinds.
- Pad duration: frozen per track (`TrackData.boost_pad_time`). Where it lives on the new core is Open
  decision D5.

**Vehicle values (both files, `assets/data/vehicles/`):**

| Field | Armored Cart | War Bike | Unit |
|---|---|---|---|
| `max_speed` | 26.0 | 24.96 | m/s |
| `accel` | 14.0 | 18.2 | m/s² |
| `brake` | 32.0 | 34.0 | m/s² |
| `reverse_max` | 8.0 | 8.0 | m/s |
| `coast_drag` | 5.0 | 5.0 | m/s² |
| `reverse_accel_frac` | 0.6 | 0.6 | — |
| `overspeed_decel` | 18.0 | 18.0 | m/s² |
| `turn_rate` | 2.3 | 2.75 | rad/s |
| `full_steer_speed` | 6.0 | 5.0 | m/s |
| `high_speed_steer_damp` | 0.3 | 0.2 | — |
| `grip` | 9.0 | 9.0 | 1/s |
| `drift_grip` | 2.2 | 2.9 | 1/s |
| `drift_min_speed` | 12.0 | 12.0 | m/s |
| `drift_start_steer` | 0.3 | 0.3 | — |
| `drift_end_speed_frac` | 0.7 | 0.7 | — |
| `drift_yaw_base` | 1.25 | 1.6 | rad/s |
| `drift_yaw_range` | 0.85 | 0.95 | rad/s |
| `drift_charge_steer_bonus` | 0.6 | 0.9 | — |
| `drift_tier_times` | 0.9, 1.9, 3.0 | 0.7, 1.5, 2.4 | charge s |
| `drift_boost_times` | 0.0, 0.7, 1.1, 1.6 | 0.0, 0.7, 1.1, 1.6 | s |
| `boost_speed_mult` | 1.35 | 1.35 | — |
| `boost_accel_mult` | 3.0 | 3.0 | — |
| `spin_time` | 1.1 | 1.25 | s |
| `spin_drag` | 2.5 | 2.5 | 1/s |
| `hit_immunity_time` | 0.6 | 0.6 | s |
| `start_stall_time` | 1.0 | 1.0 | s |
| `start_boost_times` | 0.0, 1.4, 1.7, 2.0 | 0.0, 1.4, 1.7, 2.0 | s |
| `slope_gravity` | 1.5 | 1.5 | m/s² (body-owned on the new core) |
| `bank_grip_gain` | 0.0 | 0.0 | — |
| `wall_slide_grip` | 2.2 | 2.2 | 1/s (body-owned clamp) |
| `air_yaw_accel` | 3.0 | 3.6 | rad/s² |
| `air_yaw_max` | 1.5 | 1.7 | rad/s |
| `trick_window` | 0.3 | 0.3 | s |
| `trick_boost_time` | 0.7 | 0.7 | s |
| `trick_min_airtime` | 0.25 | 0.25 | s |

Hit slowdown profiles (`duration` s / `min_speed_frac` / `decel_frac`):

| Profile | Armored Cart | War Bike |
|---|---|---|
| 0 light | 0.3 / 0.5217391304347826 / 0.6521739130434783 | 0.4 / 0.42 / 0.85 |
| 1 medium | 0.3 / 0.3826086956521739 / 0.9565217391304348 | 0.45 / 0.28 / 1.25 |
| 2 heavy | 0.6 / 0.2782608695652174 / 1.3043478260869565 | 0.8 / 0.2 / 1.6 |

**INTENT UNKNOWN:** the cart's fractions are exact ratios over 23 (12/23, 15/23; 8.8/23, 22/23;
6.4/23, 30/23), which suggests they were authored as absolute m/s against a 23 m/s reference and
converted; the bike's are round. Observation only; values are kept as they are.

Note on the bike: its `max_speed` is 26.0 × 0.96 and its `accel` is 14.0 × 1.3, consistent with the
brief's guessed split ("War-bike: faster acceleration and tighter drifts, but knocked harder").

**Surface values (`assets/data/surfaces/surface_set.tres`):**

| Kind | `max_speed_frac` | `drag` 1/s | `grip_mult` | `steer_mult` | `drift_allowed` | `surface_decel` m/s² | `boost_ignores` | `tail_time` s | `bump_yaw` rad/s | `bump_cycles_per_m` |
|---|---|---|---|---|---|---|---|---|---|---|
| grass | 0.55 | 0.6 | 0.8 | 0.9 | false | 14 | true | 0 | 0 | 0.8 |
| sand | 0.5 | 0.8 | 0.7 | 0.85 | false | 16 | true | 0 | 0 | 0.8 |
| mud | 0.4 | 1.1 | 0.45 | 0.75 | false | 20 | true | 0 | 0 | 0.8 |
| rubble | 0.6 | 0.7 | 0.75 | 0.9 | false | 18 | true | 0 | 1.1 | 0.8 |
| shallows | 0.75 | 0.3 | 0.85 | 0.9 | true | 12 | true | 0 | 0 | 0.8 |
| slick | 1.0 (no cap) | 0 | 0.35 | 1.0 | true | 14 | true | 0.6 | 0 | 0.8 |
| road, boost_pad, trick_ramp (new core) | neutral (1.0 / 0 / 1.0 / 1.0 / true / — / — / 0 / 0) | | | | | | | | | |

The neutral row is the parity requirement of §3.1.7, not a frozen data entry (the frozen game had no
such types). Look fields (colours, puffs) belong to presentation and are out of scope here.

### 3.3 Integration Points — the new base (ADR-0003, ADR-0002 v5)

What changes when the frozen `KartSim` is replaced:

1. **Split into a control law and a body.** `DriveState.drive(state, input, snap, stats, surface, dt, out)`
   (`src/gameplay/driving/`) owns every rule in §3.1. `KartBody` (`src/core/kart/`) owns integration,
   collision, ride spring, air, walls, knock and contacts.
2. **The only boundary is `KartIntent`** (Core type), written by `drive()` each tick:
   - `yaw_rate` — ground or air rate (§3.1.3), chosen from `snapshot.grounded`;
   - `target_speed` — the frozen `_update_speed` **minus slope gravity** (§3.1.2 steps 2-10); the body
     adds slope gravity and applies wall and bump losses;
   - `grip` — §3.1.4 without the wall-slide clamp (the body applies it);
   - `hop` — §3.1.11;
   - `steer`, `throttle` — pass-through for audio and visuals.
   Driving never calls `CollisionQuery` and never mutates `KartBody`; it reads `KartSnapshot` only.
3. **Speed read-back.** `drive()` starts from `snapshot.speed`, which already includes last tick's wall
   and local bump losses and this tick's received remote bumps (snapshot refreshed after events,
   ADR-0003 §4 step 1). One integrator, losses read on the next `drive()`, as in the frozen kart.
4. **Surfaces by stable id.** The caller resolves `SurfaceSet.get_type(snapshot.surface_id)` and passes
   the `SurfaceType` in; `surface_id` is the majority surface of the ground hits, kept while airborne,
   starting at 0 (road). Floor effects are looked up only here; `GroundHit` carries no floor drag.
5. **Boost pads are a surface kind** (`boost_pad`), a collision attribute (MK KCL style). The pad test
   runs on the end-of-tick snapshot (ADR-0003 §4 step 13) and reaches `drive()` as an input on the next
   tick. Took-off and landed (airtime, impact, `hop_airborne`) reach it only through the controller's copy into `DriveState` at ADR-0003 v3 step 13 (`snapshot.events` is cleared after step 12).
6. **Hop is visual-only through parity** (`hop_speed = 0.0`).
7. **Snapshot fields copied in from `DriveState`** by the controller: `drift_state`, `boost`, `spin`,
   `sinking` (ADR-0003 Key Interfaces), for presentation, network and ghosts.

### 3.4 Turbo reserve — PROPOSAL, not adopted (systems-index rows 9 and 28)

> **Status: proposal for the owner's decision (Open decision D1). Nothing here is adopted, and the
> parity build ships with the frozen max-merge rule.**

**The question.** The concept doc lists Crash Team Racing Nitro-Fueled's "turbo reserve (boost stored
and spent)" as a reference, "fitted to our 3-tier drift", for a "deeper skill ceiling". Today every
boost merges by max (§3.1.6), so a drift boost released while a pad or start boost is still running is
partly or wholly wasted. A reserve would let skilled players *bank* overlapping boosts.

**Fixed constraint (from the brief, keep in every option):** boosts never exceed the cap
`max_speed × boost_speed_mult`. A reserve may extend *how long* the kart is at the boosted cap, never
raise it.

**Options:**

| | A. No reserve (frozen) | B. Additive stack with a cap — **recommended** | C. Full CTR-style reserve meter |
|---|---|---|---|
| Rule | `boost_time = max(boost_time, s)` | `boost_time = min(boost_time + s, turbo_reserve_max)`; drains 1 s/s as today | Boosts beyond the active one go into a separate reserve; it drains only while throttle is held and grounded; braking, releasing throttle or a hard wall impact empties it |
| Lost on hit/spin | yes (today) | yes (unchanged) | yes |
| New knobs | none | `turbo_reserve_enabled`, `turbo_reserve_max` | those plus drain and loss rules |
| HUD | none | none needed (sparks/flame already show boost) | a reserve meter (UX work) |
| Pillar 2 | skill reward capped by overlap waste | chaining pad → drift, start → drift is rewarded | deepest ceiling |
| Pillar 1 (readable on stream, 12 racers) | clearest | clear: one timer, one cap | an extra meter per racer; harder to read |
| Pillar 3 (hold until right) | already tuned | small, testable change after parity | larger feel change; more tuning risk |
| Network | — | same single `boost` float in the snapshot | one more field (`reserve`) per racer |

**Recommendation: B**, behind `turbo_reserve_enabled = false` until the owner's A1 feel sign-off of the
parity build, then playtested on. Reasoning:
- It answers the reference's intent (stored boost rewards chaining, MDA Challenge, SDT Competence)
  with one rule change in one place (§3.1.6) and no new HUD element (Pillar 1 readability).
- C's throttle-and-brake loss rules add a second skill layer that the 3-tier drift already supplies,
  and a per-racer meter that 12-racer streams would have to read.
- `turbo_reserve_max` has **no source value**. Two derived bounds frame it: it must be greater than the
  longest single boost in data (start level 3, `start_boost_times[3]` = 2.0 s; at or below that, stacking
  does nothing for a perfect start), and a cap is needed at all because without one, alternating drifts
  on a long straight could keep the kart at the boosted cap indefinitely (see §5 E-21). The value is the
  owner's to set at the first playtest.

**Pillar tension to flag:** Pillar 2 (deeper ceiling) pulls toward C; Pillar 1 (reads on stream) and
Pillar 3 (do not ship rough) pull toward A or B. This is an open decision, not resolved here.

---

## 4. Formulas

`dt = SIM_DT = 1/60 s`. "Cart" = Armored Cart, "Bike" = War Bike. All inputs: `steer ∈ [-1, 1]`
(+ = left), `throttle ∈ [0, 1]`, `brake ∈ [0, 1]`.

### 4.1 Speed cap

```
base_cap    = boosting ? max_speed × boost_speed_mult : max_speed / max(floor_drag_mult, 1)
surface_cap = (no surface, or max_speed_frac >= 1, or (boosting and boost_ignores)) ? ∞
              : max_speed × max_speed_frac
cap         = min(base_cap, surface_cap)
```
| Variable | Meaning | Range (data) |
|---|---|---|
| `max_speed` | unboosted top speed | 24.96-26.0 m/s |
| `boost_speed_mult` | boosted cap multiplier | 1.35 |
| `floor_drag_mult` | frozen track floor term (INTENT UNKNOWN) | values `< 1` are ignored |
| `max_speed_frac` | surface share of `max_speed` | 0.4-1.0 (export range 0.05-1.0) |

Examples: Cart boosted cap 26.0 × 1.35 = **35.1 m/s**; Bike 24.96 × 1.35 = **33.696 m/s**.
Cart surface caps: grass 14.3, sand 13.0, mud 10.4, rubble 15.6, shallows 19.5 m/s. Bike: grass
13.728, sand 12.48, mud 9.984, rubble 14.976, shallows 18.72 m/s.

### 4.2 Speed update (grounded; §3.1.2 order)

```
push  = boosting ? accel × boost_accel_mult : accel × throttle
if push > 0 and v < cap:  v = min(v + push·dt, cap)
if brake > 0:             v -= (v > 0 ? brake_rate × brake : accel × reverse_accel_frac × brake) · dt
if throttle = 0 and brake = 0 and not boosting:  v = move_toward(v, 0, coast_drag·dt)
if v > cap:               v = move_toward(v, cap, (cap is the surface cap ? surface_decel : overspeed_decel)·dt)
if drag > 0 and not (boosting and boost_ignores):  v *= exp(-drag·dt)
v = max(v, -reverse_max)
if spinning:              v *= exp(-spin_drag·dt)
if slowdown active and v > floor:  v = max(v - decel_frac·max_speed·dt, floor),  floor = min_speed_frac·max_speed
```

Worked examples (flat ground, no slope):
- **0 → top speed, full throttle:** Cart 26.0 / 14.0 = **1.857 s** (≈ 112 ticks); Bike 24.96 / 18.2 =
  **1.371 s** (≈ 83 ticks).
- **Boost from top speed to boosted cap:** Cart push 14 × 3 = 42 m/s², (35.1 − 26.0) / 42 = **0.217 s**;
  Bike push 54.6 m/s², 8.736 / 54.6 = **0.160 s**.
- **After a boost ends at the boosted cap:** Cart (35.1 − 26.0) / 18 = **0.506 s** back to 26.0; Bike
  8.736 / 18 = **0.485 s**.
- **Brake from top speed to 0:** Cart 26 / 32 = **0.8125 s**; Bike 24.96 / 34 = **0.734 s**.
- **Coast from top speed to 0:** 26 / 5 = **5.2 s** (Cart).
- **Reverse:** Cart reverses at 14 × 0.6 = 8.4 m/s² to −8.0 m/s.
- **Sustained speed on a capped surface with drag** (full throttle, not boosting): once at the cap, each
  tick ends at `cap × exp(-drag·dt)` as long as `accel·dt >= cap·(1 − exp(-drag·dt))`.
  Cart on grass: 14.3 × exp(−0.6/60) = 14.3 × 0.99005 = **14.158 m/s** (push 0.233 m/s per tick ≥ loss
  0.142). Cart on mud: 10.4 × exp(−1.1/60) = **10.211 m/s**.
- **Entering grass at 26 m/s, not boosting:** eases down at `surface_decel` 14 m/s² plus drag;
  (26 − 14.3) / 14 ≈ **0.84 s** upper bound (drag shortens it).

### 4.3 Steering yaw rate (grounded, not drifting)

```
low_speed = clamp(|v| / full_steer_speed, 0, 1)
damp      = 1 − high_speed_steer_damp × clamp(v / max_speed, 0, 1)
yaw_rate  = steer × turn_rate × low_speed × damp × sign(v) × steer_mult
```
Examples, full steer on road: Cart at 26.0 m/s: 2.3 × 1 × 0.7 = **1.61 rad/s** (turn radius
26 / 1.61 ≈ 16.1 m); Cart at 3 m/s: 2.3 × 0.5 × (1 − 0.3 × 3/26) = **1.110 rad/s**; Bike at 24.96 m/s:
2.75 × 0.8 = **2.2 rad/s** (radius ≈ 11.3 m). Cart on mud at 26 m/s: 1.61 × 0.75 = 1.21 rad/s.

### 4.4 Drift yaw and charge

```
yaw_rate    = drift_dir × (drift_yaw_base + drift_yaw_range × clamp(steer × drift_dir, −1, 1))
charge_rate = 1 + drift_charge_steer_bonus × max(steer × drift_dir, 0)
drift_time += dt × charge_rate
tier        = count of i where drift_time >= drift_tier_times[i]
real_time_to_tier(k) = drift_tier_times[k−1] / charge_rate      (constant steer)
```
| | Cart | Bike |
|---|---|---|
| Drift yaw range (steer fully out → neutral → fully in) | 0.40 → 1.25 → 2.10 rad/s | 0.65 → 1.60 → 2.55 rad/s |
| Charge rate, neutral or steering out | 1.0 | 1.0 |
| Charge rate, fully in | 1.6 | 1.9 |
| Real time to tier 1 / 2 / 3, neutral | 0.9 / 1.9 / 3.0 s | 0.7 / 1.5 / 2.4 s |
| Real time to tier 1 / 2 / 3, fully in | 0.5625 / 1.1875 / 1.875 s | 0.368 / 0.789 / 1.263 s |

Boost paid per second of drift at tier 3 held fully in: Cart 1.6 / 1.875 = 0.85; Bike 1.6 / 1.263 = 1.27.

### 4.5 Grip lerp

```
α = clamp(grip_eff × dt, 0, 1);   velocity = lerp(velocity, heading × speed, α)
grip_eff = (drifting ? drift_grip : grip) × (1 + bank_grip_gain × |sin(bank)|) × grip_mult
lateral residual after n ticks (heading held) = (1 − α)^n
```
Examples: road, not drifting: α = 9/60 = **0.15**; after 1 s the residual is 0.85⁶⁰ ≈ 6 × 10⁻⁵ (snaps
on). Cart drifting: α = 2.2/60 = 0.0367, residual after 1 s ≈ **0.106** (the slide). Bike drifting:
α = 2.9/60 = 0.0483. Slick, not drifting: 9 × 0.35 = 3.15 → α = 0.0525. Slick while drifting (Cart):
2.2 × 0.35 = 0.77 → α = 0.0128.

### 4.6 Drift end speed

```
end_speed = drift_min_speed × drift_end_speed_frac = 12.0 × 0.7 = 8.4 m/s   (both vehicles)
```
A drift starts above 12.0 m/s and ends (paying) below 8.4 m/s.

### 4.7 Boost merge (frozen)

```
boost_time = max(boost_time, source_seconds);   boost_time = max(0, boost_time − dt) each tick
```
Example: a tier-3 drift (1.6 s) released with 1.2 s of pad boost left → `boost_time` = 1.6 s (not 2.8).
A tier-1 drift (0.7 s) released on a Castle Circuit pad (refreshed to 1.10 s every tick) is wasted.

### 4.8 Air yaw

```
on takeoff: air_rate = clamp(last_ground_yaw_rate, −air_yaw_max, air_yaw_max)
each tick:  air_rate = move_toward(air_rate, steer × air_yaw_max, air_yaw_accel × dt)
```
From 0 to full: Cart 1.5 / 3.0 = **0.5 s**; Bike 1.7 / 3.6 = **0.472 s**.

### 4.9 Spin

During a spin there is no throttle or brake, so coast drag and spin drag both apply:
`dv/dt = −coast_drag − spin_drag × v` (continuous approximation of §4.2).
`v(t) = (v₀ + coast_drag/spin_drag) e^(−spin_drag·t) − coast_drag/spin_drag`.
Cart from 26 m/s: (26 + 2) e^(−2.5t) − 2 = 0 → t = ln(14)/2.5 ≈ **1.06 s**, just inside the 1.1 s spin.

### 4.10 Hit slowdown

```
floor = min_speed_frac × max_speed;  rate = decel_frac × max_speed;  max loss = min(rate × duration, v − floor)
```
Cart from 26 m/s: light floor 13.565, rate 16.957, loss 5.09 m/s (to 20.91); medium floor 9.948, rate
24.870, loss 7.46 (to 18.54); heavy floor 7.235, rate 33.913, loss 18.77 (stops at the floor).
Bike from 24.96 m/s: light floor 10.483, rate 21.216, loss 8.49 (to 16.47); medium floor 6.989, rate
31.200, loss 31.2 × 0.45 = 14.04 (to 10.92, above the floor); heavy floor 4.992, rate 39.936, stops at
the floor.

### 4.11 Rubble wobble

```
phase += TAU × bump_cycles_per_m × |v| × dt;   yaw_rate += bump_yaw × sin(phase)
heading wobble amplitude = bump_yaw / (TAU × bump_cycles_per_m × |v|)
```
Cart at the rubble cap 15.6 m/s: frequency 0.8 × 15.6 = 12.48 Hz; heading amplitude
1.1 / (2π × 12.48) ≈ **0.014 rad** (0.8°).

---

## 5. Edge Cases

| # | Situation | Outcome |
|---|---|---|
| E-1 | `dt = 0` | `accel_long` is set to 0 (guarded); all timers and lerps are unchanged. `drive()` must keep the guard. |
| E-2 | Speed exactly 12.0 m/s, or steer exactly 0.3, with the drift button held | No drift (both tests are strict `>`). |
| E-3 | Drift button held down a straight, then steering past 0.3 above 12 m/s | A drift starts at that tick (level-triggered). INTENT UNKNOWN. |
| E-4 | Steering the opposite way during a drift | Direction stays locked; yaw drops to `base − range` (Cart 0.40, Bike 0.65 rad/s) in the locked direction; charge rate falls to 1.0. The drift does not flip. |
| E-5 | Releasing the drift below tier 1 | Drift ends, `drift_ended(0, 0.0)`, no boost. |
| E-6 | Speed falls below 8.4 m/s during a drift (wall hit, slowdown) | Drift ends **and pays** its current tier. |
| E-7 | Hit during a drift | Drift ends with no boost, `boost_time` set to 0, spin starts. |
| E-8 | Hit while already spinning | Ignored (`hit()` returns false); the spin timer is not restarted. |
| E-9 | Drifting onto grass, sand, mud or rubble | Drift ends with no boost on the first tick that surface is in force; `surface_drift_ends` +1. |
| E-10 | Drift held into a jump, landing on mud | Drift continues and charges in the air; on the first grounded tick on mud it ends with no boost. |
| E-11 | Drift button pressed while airborne | No drift starts; the press does not arm a trick (the since-hop timer runs only while grounded). |
| E-12 | Leaving a slick onto road | Slick grip (0.35) stays for 0.6 s, then road. |
| E-13 | Leaving a slick onto grass (or any `tail_time = 0` surface) | Tail cleared at once; grass is in force (TD-004). |
| E-14 | Respawn during a slick tail | Tail cleared (TD-004). |
| E-15 | New core: slick onto a boost pad or trick ramp | Treated as road: the tail keeps counting down (parity rule §3.1.7). |
| E-16 | New core: `surface_id` not in `SurfaceSet` | **[proposal — confirm with the technical director]** treat as road (id 0) and count it in a debug counter. ADR-0002's load check should make this unreachable. |
| E-17 | Boost expires while on grass | Cap drops to 14.3 (Cart); speed eases down at `surface_decel` 14 m/s², never snaps; grass drag resumes. |
| E-18 | Boosting on grass | Surface cap and drag are lifted (`boost_ignores = true`); cap is 35.1 (Cart). |
| E-19 | Two boost sources on the same tick | The longer duration wins (max-merge). |
| E-20 | Kart stays on a pad | `boost_time` is refreshed to the pad time every grounded tick; `pad_boosted` fires only on entry. Airborne over a pad: no refresh. |
| E-21 | **Degenerate: snaking** (alternating drifts on a straight to stay boosted) | Possible in the frozen rules: a drift needs only > 12 m/s and > 0.3 steer, and boost runs while the next drift charges. Mitigations today: tier times and the locked minimum drift yaw (0.40 / 0.65 rad/s, so a drift always curves). Not measured. A turbo reserve without a cap would make it worse (§3.4). Playtest check in AC-X3. |
| E-22 | `drift_tier_times` not ascending | Tier is wrong (the loop counts entries reached). Data must be ascending; the new loader should assert it. |
| E-23 | `drift_boost_times` shorter than tiers + 1 | A tier with no entry pays 0 s silently. Data must have `tiers + 1` entries with index 0 = 0.0; the loader should assert it. |
| E-24 | Start level outside `start_boost_times` | Ignored (no boost). |
| E-25 | Slowdown profile index outside the array | Ignored. |
| E-26 | Slowdown while already below its floor | No change. |
| E-27 | Reversing | Steering is inverted (`sign(v)`); `high_speed_steer_damp` does not apply (`v/max_speed` clamped at 0); a drift cannot start. |
| E-28 | Rubble at near-zero speed | No wobble (`|v| <= 0.001`); phase does not advance. |
| E-29 | `floor_drag_mult < 1` | Ignored (`max(…, 1)`); a boost ignores it entirely. |
| E-30 | Start stall | Throttle is 0 for 1.0 s; steering and brake work. |
| E-31 | Hop pressed with `hop_speed = 0` (new core) | No physical change; the trick timer still starts. |
| E-32 | Trick armed but airtime < 0.25 s | No trick boost; the arm is cleared on landing. |

---

## 6. Dependencies

Each dependency below must name this document in its own GDD when that GDD is written (none of
them has a GDD yet except where noted); this list is the bidirectional record until then.

| System | Direction | Contract |
|---|---|---|
| **Kart Physics** (row 6, ADR-0003) | both | Provides `KartSnapshot` (speed after losses, grounded, `surface_id`, events: landed/airtime/impact, `hop_airborne`, bumped). Consumes `KartIntent` (`yaw_rate`, `target_speed`, `grip`, `hop`, `steer`, `throttle`). Owns slope gravity and the wall-slide grip clamp. |
| **Track Collision / `SurfaceSet`** (ADR-0002 v5) | consumes | Stable surface ids, id 0 = road, kinds incl. `boost_pad`, `trick_ramp`. Floor effects are looked up only by Driving. |
| **Input** | consumes | `DriverInput`: steer, throttle, brake, drift button (keyboard: Space; controller: RB, per the brief). |
| **AI Bots** | consumed by | Bots drive through the same `drive()` with their own `DriverInput`; frozen bots read `stats.trick_window` for hop timing. |
| **Race start / countdown** | consumes | Start level 1-3 or stall at GO (§3.1.9). |
| **Items** | consumes | Spin hits (`hit()`), slowdown profiles 0-2, War Horn boost (max-merge). |
| **Track Hazards** (row 14) | consumes | Mover spin hits. |
| **Track Features** (row 13) | consumes | Boost pads (pad test → `drive()` input), ramps (via Kart Physics takeoff/landing). Pad duration location: D5. |
| **Fall & Respawn** (row 12) | consumes | Respawn event resets `DriveState` and clears the slick tail. |
| **Air Tricks** (row 26) | provides | Trick arming and trick boost live here; Air Tricks extends them. |
| **Turbo Reserve** (row 28) | provides | Rules decided here (§3.4, D1); code may land later. |
| **Presentation (kart visual, camera, HUD)** | provides | `drift_state`/tier (spark colour per tier), `boost` (flame, FOV gain), `spin`, visual hop. |
| **Audio** | provides | Drift start/end, tier changes, boost events. |
| **Networking** (ADR-0006) | provides | `drift_state`, `boost`, `spin`, `sinking` in the snapshot; remote karts are interpolated, never driven. |
| **Time Trials & Ghosts** (ADR-0010) | provides | Snapshot streams include the fields above. |

---

## 7. Tuning Knobs

No `@export_range` exists on `VehicleStats`, so numeric safe ranges for vehicle fields are **NOT
SOURCED**; the ranges below are the structural bounds the rules need to stay valid, and anything
tighter is a playtest decision. `SurfaceType` ranges come from its `@export_range` hints. Defaults are
the shipped values in §3.2. Category: **F** feel, **C** curve, **G** gate.

| Knob | Cat. | Affects | Structural safe range | Why |
|---|---|---|---|---|
| `max_speed` | C | top speed, every cap | > `drift_min_speed` (12.0) | at or below `drift_min_speed` no drift can start on road |
| `accel` | F | 0→top time (§4.2) | > 0 | 0 = cannot move |
| `boost_speed_mult` | C | boosted cap | >= 1.0 | < 1 makes boosts slow the kart |
| `boost_accel_mult` | F | how fast a boost bites | >= 1.0 | |
| `overspeed_decel`, `surface_decel` | F | how a boost ends, entering slow ground | > 0 | 0 = speed above the cap never falls |
| `turn_rate`, `full_steer_speed`, `high_speed_steer_damp` | F | turning | `turn_rate` > 0; `full_steer_speed` > 0 (divisor); damp in [0, 1) | damp ≥ 1 = no steering at top speed |
| `grip` | F | line holding | > 0; `grip × SIM_DT` <= 1 means ≤ 60 | above 60 the lerp clamps to 1 (no difference) |
| `drift_grip` | F | slide amount | (0, `grip`) | ≥ `grip` = drift does not slide |
| `drift_min_speed` | G | when drifts are possible | (0, `max_speed`) | |
| `drift_start_steer` | G | drift entry threshold | [0, 1) | ≥ 1 = drift never starts (strict `>`) |
| `drift_end_speed_frac` | G | when a slowing drift ends | (0, 1] | > 1 ends every drift on its first tick |
| `drift_yaw_base`, `drift_yaw_range` | F | drift line | `range` < `base` keeps the drift always curving into its direction (today true: 0.85 < 1.25, 0.95 < 1.6) | `range ≥ base` allows a straight or reversed drift — enables snaking (E-21) |
| `drift_charge_steer_bonus` | C | reward for tight drifts | >= 0 | |
| `drift_tier_times` | C | tier pacing (§4.4) | ascending, > 0, 3 entries (brief: 3 tiers) | E-22 |
| `drift_boost_times` | C | tier reward | tiers + 1 entries, index 0 = 0.0, non-decreasing | E-23; decreasing would punish a higher tier |
| `spin_time`, `spin_drag` | F | hit cost | > 0 | |
| hit slowdown profiles | C | item hit cost | `min_speed_frac` in [0, 1]; `decel_frac` ≥ 0; `duration` ≥ 0 | |
| `start_boost_times`, start windows | G | start reward | windows ascending (perfect < good < ok) | |
| `trick_window`, `trick_min_airtime`, `trick_boost_time` | G | trick reward | ≥ 0 | |
| `air_yaw_accel`, `air_yaw_max` | F | air control | ≥ 0 | |
| `TrackData.boost_pad_time` | G | pad reward per track | ≥ 0 | location on the new core: D5 |
| `SurfaceType.max_speed_frac` | C | surface cap | 0.05-1.0 (export range) | |
| `SurfaceType.grip_mult` | F | surface slide | 0.05-2.0 (export range) | |
| `SurfaceType.steer_mult` | F | surface steering | 0.1-2.0 (export range) | |
| `SurfaceType.drag` | C | surface drag | ≥ 0 | |
| `SurfaceType.tail_time` | F | slick carry-over | ≥ 0 | |
| `SurfaceType.bump_yaw`, `bump_cycles_per_m` | F | rubble wobble | ≥ 0 | |
| `hop_speed` (new) | F | physical hop | **0.0 through parity** | D2 |
| `turbo_reserve_enabled`, `turbo_reserve_max` (proposed) | C | turbo reserve | `enabled = false` through parity; `max` > 2.0 s if adopted | D1, §3.4 |

All knobs live in data (`assets/data/core/…` on the new core), never as literals in `src/`
(`.claude/rules/tuning-values.md`).

---

## 8. Acceptance Criteria

Functional criteria are gdUnit4 unit tests in `tests/unit/driving/` against `DriveState.drive()`
with the forked Cart and Bike data, a stub `KartSnapshot`, and `dt = 1/60`, unless stated. "± 1 tick"
allows float accumulation.

**Speed and cap**
- AC-1: Cart, full throttle on road from 0: target speed reaches 26.0 m/s at 1.857 s ± 1 tick and never
  exceeds 26.0 m/s. Bike: 24.96 m/s at 1.371 s ± 1 tick.
- AC-2: With `boost_time > 0`, target speed never exceeds 35.1 (Cart) / 33.696 (Bike) m/s; from 26.0 it
  reaches 35.1 in 0.217 s ± 1 tick with throttle 0 (boost pushes without throttle).
- AC-3: Starting at 35.1 with no boost, Cart returns to 26.0 in 0.506 s ± 1 tick, monotonically (no snap).
- AC-4: Cart on grass at full throttle settles at 14.158 ± 0.01 m/s; on mud at 10.211 ± 0.01 m/s.
- AC-5: `drive()`'s `target_speed` excludes slope gravity: on a stub snapshot with a 10° slope, output
  equals the flat-ground output.

**Drift**
- AC-6: With the drift button held: speed 12.0 or steer 0.30 → no drift; speed 12.01 and steer 0.31 →
  drift starts, `drift_started(+1)`.
- AC-7: Cart, neutral steer (steer × dir = 0 after start): tier 1 at 0.9 s, tier 2 at 1.9 s, tier 3 at
  3.0 s, each ± 1 tick. Cart fully in: 0.5625 / 1.1875 / 1.875 s ± 1 tick. Bike fully in: 0.368 / 0.789 /
  1.263 s ± 1 tick.
- AC-8: Release at tier 1 / 2 / 3 → `boost_time` = 0.7 / 1.1 / 1.6 s and `drift_ended(t, s)` with those
  values; release at tier 0 → `drift_ended(0, 0.0)`, `boost_time` unchanged.
- AC-9: Drift yaw at steer = −dir, 0, +dir: Cart 0.40 / 1.25 / 2.10, Bike 0.65 / 1.60 / 2.55 rad/s
  (× `drift_dir`), never the opposite sign.
- AC-10: Drift at tier 2, speed set to 8.39 → drift ends and pays 1.1 s.
- AC-11: Drift onto mud → drift ends with no boost and `surface_drift_ends` = 1.
- AC-12: Drift held with `grounded = false` keeps charging and outputs the air yaw rate, not the drift yaw.

**Boost, hits, start, trick, pads**
- AC-13: Max-merge: `boost_time` 1.2 then a tier-3 release → 1.6 (not 2.8).
- AC-14: `hit()` during a tier-3 drift → no boost paid, `boost_time` 0, no control for 1.1 s (Cart) /
  1.25 s (Bike) ± 1 tick; a second `hit()` during the spin returns false.
- AC-15: Cart slowdown profile 2 from 26 m/s → speed never below 7.235 m/s; after 0.6 s the profile ends.
- AC-16: Start level 3 → `boost_time` 2.0 s; stall → throttle ignored for 1.0 s ± 1 tick, steer still
  works; level 4 → ignored.
- AC-17: Drift pressed 0.30 s before takeoff, airtime 0.25 s → 0.7 s boost on landing; pressed 0.32 s
  before, or airtime 0.24 s → no boost.
- AC-18: Pad input on 3 consecutive ticks → `boost_time` refreshed each tick, `pad_boosted` once.

**Surfaces (TD-004)**
- AC-19: Slick → road: slick grip in force for 0.6 s ± 1 tick, then road. Slick → grass: grass in force
  on the next tick. Slick then respawn: no tail. Slick → `boost_pad` (new core): tail keeps counting.
- AC-20: Rubble at 15.6 m/s: the added yaw is a sine of amplitude 1.1 rad/s whose phase advances with
  distance; two runs give bit-identical yaw sequences.

**Boundary and determinism**
- AC-21: Grep: no `CollisionQuery`, `KartBody` mutation or `src/legacy` reference in
  `src/gameplay/driving/`; no numeric tuning literal (other than 0/1/−1) in `drive()`.
- AC-22: Two runs of the same input sequence produce bit-identical `KartIntent` streams.
- AC-23: Loader rejects `drift_tier_times` not ascending and `drift_boost_times` with ≠ tiers + 1 entries.

**Parity and feel (integration; ADR-0003 Validation Criteria, `production/qa/evidence/core-rebuild-story-001/golden/`)**
- AC-P1: Parity harness noise floor measured on the frozen kart first; every tolerance below sits above it.
- AC-P2: Solo traces (Cart and Bike, Castle Circuit and Dungeon Depths, 4 runs): lap time within ±2%
  of golden (e.g. Castle Circuit Cart 42.27 s → 41.42-43.11 s); sector splits ±3%; top speed ±1%; drift
  boosts ±1 per tier per lap; takeoff, landing and lap counts exact; no interval with speed < 2 m/s for
  more than 1 s after the start. Tolerances are Open decision D3.
- AC-X1 (experiential, owner A1 sign-off): the owner drives the Cart and the Bike on the baked Castle
  Circuit and signs off that drift, boost and surfaces feel like the frozen game. Retained screenshot of
  a tier-3 drift per vehicle in `production/qa/evidence/`.
- AC-X2 (experiential, playtest): playtesters name the tier of a drift from spark colour alone
  (blue / orange / purple) without being told; the owner sets the pass bar.
- AC-X3 (experiential, playtest): snaking on the longest straight of Castle Circuit is tried
  deliberately; the owner judges whether it beats driving straight, and records the call (E-21).

---

## Open decisions for the owner

| ID | Decision | Options | Recommendation |
|---|---|---|---|
| **D1** | **Turbo reserve: yes or no, and its rules** (rows 9 and 28) | A. no reserve (frozen max-merge); B. additive stack with a cap; C. full CTR-style reserve meter | **B (proposal)**, behind `turbo_reserve_enabled = false` until A1 sign-off; `turbo_reserve_max` set by the owner at first playtest, > 2.0 s. See §3.4. Pillar 2 vs Pillars 1 and 3 tension. |
| **D2** | **Physical hop** after the A1 sign-off | keep visual-only (`hop_speed = 0`); enable a physical hop (lets the kart lift over small lips; `hop_airborne` flights never count as tricks) | Decide after A1; keep 0.0 through parity (ADR-0003 §3). Also confirm the hop trigger (drift press edge, §3.1.11). |
| **D3** | **Parity tolerances** | keep ADR-0003's (lap ±2%, sectors ±3%, top speed ±1%, drift boosts ±1 per tier per lap, counts exact); move any of them at the A1 sign-off | Keep as stated until the noise floor is measured; the owner may move them at A1. |
| D4 | Drift start on a held button (E-3) | keep level-triggered (frozen); require a fresh press (MK-style) | Keep frozen behaviour through parity; revisit at A1 if it feels wrong. INTENT UNKNOWN. |
| D5 | Where the pad boost duration lives on the new core (frozen: per track, 1.10 / 0.80) | per track (Course/Track data); per `boost_pad` `SurfaceType` (one value, loses the per-track difference); several pad kinds | Per track, to keep parity; needs a Track Features / ADR-0004 owner. |
| D6 | `floor_drag_mult` (frozen track floor term, INTENT UNKNOWN) | drop it; map it to a surface field | Trace its frozen source first; if no shipped track sets it below the cap, drop it. |
| D7 | Whether a boost pad or trick ramp should cut a slick tail (§3.1.7, E-15) | no (frozen, parity default); yes | No through parity. |

---

## Open Questions and Follow-Up Work

### Flagged Follow-Up Work
- Add loader asserts for E-22 and E-23 (Driving migration story).
- E-16 (unknown surface id) behaviour to be confirmed with the technical director against ADR-0002's
  load check.
- When Items, Track Features, Fall & Respawn, Air Tricks and Turbo Reserve GDDs are written, each must
  reference this document (Dependencies are bidirectional).

## Version History

| Date | Change | By |
|---|---|---|
| 2026-11-22 | First draft, reverse-documented from `src/legacy` at `00b5afc` | game-designer (orchestrated run) |
