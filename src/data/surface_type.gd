class_name SurfaceType
extends Resource
## How one kind of surface feels and looks (story 011). One per kind in a SurfaceSet. The kart
## (KartSim) reads the handling fields, TrackMesh the look fields, KartVisual the puff fields and
## RaceSound the sound fields. Implements design/references/track-features-catalog.md features
## 1-4 and 45; colours follow art bible section 4/6 (flat colours, one low-contrast pattern, brown
## speckle = off-road).

## Kind id: grass, sand, mud, rubble, shallows, slick.
@export var kind: StringName = &"grass"

@export_group("Handling")
## Speed cap on this surface as a share of the kart's max_speed (1 = no cap).
@export_range(0.05, 1.0, 0.01) var max_speed_frac: float = 1.0
## Extra drag (1/s): speed decays by this share per second on the surface (not while lifted by a boost).
@export var drag: float = 0.0
## Multiplier on the kart's grip (1 = unchanged, lower = slides more).
@export_range(0.05, 2.0, 0.01) var grip_mult: float = 1.0
## Multiplier on the steering yaw rate (1 = unchanged).
@export_range(0.1, 2.0, 0.01) var steer_mult: float = 1.0
## False: a drift cannot start here and a held drift ends (without paying its boost).
@export var drift_allowed: bool = true
## Deceleration (m/s^2) toward the cap when the kart is above it (never a hard snap).
@export var surface_decel: float = 14.0
## True: while the kart has boost time (drift boost, pad, War Horn, start boost) the speed cap and the
## extra drag do not apply, so a boost carries it across.
@export var boost_ignores: bool = true
## Seconds the effect stays after leaving the surface (slick: the slide goes on a moment).
@export var tail_time: float = 0.0
## Yaw wobble (rad/s amplitude) while driving here, for bumpy ground (rubble); 0 = smooth.
@export var bump_yaw: float = 0.0
## Wobble cycles per meter driven.
@export var bump_cycles_per_m: float = 0.8
## Visual bounce of the kart body (meters) on bumpy ground.
@export var bump_height: float = 0.0
## True: the zone lies ON the road (slick patch): it is drawn as a glossy overlay at the road's height.
@export var on_road: bool = false

@export_group("Look")
## Ground colour of the zone.
@export var ground_color: Color = Color(0.44, 0.63, 0.35)
## Colour of the speckle (or stripe) pattern drawn over the ground.
@export var pattern_color: Color = Color(0.31, 0.5, 0.26)
## Pattern: speckle (jittered dots), stripe (wave lines across the zone) or none.
@export var pattern: StringName = &"speckle"
## Distance (meters) between pattern marks.
@export var pattern_cell: float = 1.6
## Size (meters) of one pattern mark.
@export var pattern_size: float = 0.32
## Opacity of an on_road overlay (alpha of the ground colour).
@export_range(0.0, 1.0, 0.01) var overlay_alpha: float = 0.6
## Glossy sheen of an on_road overlay: 0 = matte, 1 = mirror.
@export_range(0.0, 1.0, 0.01) var gloss: float = 0.0

@export_group("Puffs (cosmetic)")
## Effect shown while a kart drives here: dust, mud, gravel, splash or none.
@export var effect: StringName = &"dust"
## Puff colour at birth (fades to transparent).
@export var puff_color: Color = Color(0.7, 0.65, 0.45, 0.8)
## Particles alive at once per kart (capped by SurfaceSet.puff_max_amount).
@export var puff_amount: int = 10
## Seconds a puff lives.
@export var puff_lifetime: float = 0.7
## Puff ball radius in meters.
@export var puff_size: float = 0.3
## Launch speed (m/s) of puffs.
@export var puff_velocity: float = 2.5
## Gravity (m/s^2, downward) on the puffs: low for dust, high for a splash.
@export var puff_gravity: float = 3.0
## Cone angle (degrees) the puffs spread in.
@export var puff_spread_deg: float = 30.0
## Kart speed (m/s) under which no puffs are emitted.
@export var puff_min_speed: float = 4.0

@export_group("Sound")
## AudioSet event played when a kart enters the surface (empty = none).
@export var enter_event: StringName = &""
## While the kart stays and moves, the event repeats every this many seconds (0 = once on entry).
@export var repeat_interval: float = 0.0
