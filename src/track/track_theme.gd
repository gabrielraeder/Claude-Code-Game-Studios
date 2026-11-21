class_name TrackTheme
extends Resource
## Look of a track: colors, sizes and scenery positions. The defaults reproduce the plain
## test-loop look; Castle Circuit and later Dungeon Depths override them in a .tres.
## Implements design/game-brief.md, "Look and references".

## Which scenery builder TrackScenery uses: plain (nothing extra), castle, later dungeon.
@export var style: StringName = &"plain"

@export_group("World")
@export var sky_top_color: Color = Color(0.25, 0.5, 0.9)
@export var sky_horizon_color: Color = Color(0.7, 0.82, 0.95)
@export var ground_horizon_color: Color = Color(0.5, 0.6, 0.45)
@export var ground_color: Color = Color(0.32, 0.55, 0.25)
## Side length of the ground plane in meters.
@export var ground_size: float = 700.0
@export var ambient_energy: float = 0.7
## Ambient light color (a warm neutral keeps stone grey in shade; the blue sky made it blue).
@export var ambient_color: Color = Color(0.86, 0.83, 0.78)
## Sun light color and energy.
@export var sun_color: Color = Color(1.0, 0.96, 0.88)
@export var sun_energy: float = 1.1

@export_group("Road")
@export var road_color: Color = Color(0.22, 0.22, 0.25)
@export var curb_color_a: Color = Color(0.85, 0.15, 0.15)
@export var curb_color_b: Color = Color(0.95, 0.95, 0.95)
@export var line_color_a: Color = Color(1, 1, 1)
@export var line_color_b: Color = Color(0.05, 0.05, 0.05)
@export var curb_stripe_segments: int = 2

@export_group("Walls")
@export var wall_color_a: Color = Color(0.75, 0.75, 0.78)
@export var wall_color_b: Color = Color(0.6, 0.6, 0.65)
@export var wall_height: float = 0.9
## Extra height of every second block (crenellation); 0 = a plain wall.
@export var merlon_height: float = 0.0
## Wall thickness in meters.
@export var wall_thickness: float = 0.05
@export var wall_stripe_segments: int = 4

@export_group("Castle scenery")
@export var banner_spacing: float = 22.0
@export var banner_pole_color: Color = Color(0.35, 0.25, 0.15)
## Banner cloth colors, alternating: parchment cream and mascot red-orange.
@export var banner_color_a: Color = Color(0.95, 0.9, 0.74)
@export var banner_color_b: Color = Color(0.9, 0.38, 0.15)
@export var banner_height: float = 6.0
@export var banner_distance_from_wall: float = 1.2
@export var tower_color: Color = Color(0.58, 0.58, 0.6)
@export var roof_color: Color = Color(0.72, 0.28, 0.16)
@export var tower_radius: float = 4.5
@export var tower_height: float = 16.0
@export var roof_height: float = 7.0
@export var keep_center: Vector2 = Vector2.ZERO
@export var keep_size: Vector3 = Vector3(18, 20, 18)
@export var tower_positions: PackedVector2Array = PackedVector2Array()
@export var gate_tower_positions: PackedVector2Array = PackedVector2Array()
@export var house_positions: PackedVector2Array = PackedVector2Array()
@export var house_size: Vector3 = Vector3(9, 5, 7)
@export var house_wall_color: Color = Color(0.9, 0.84, 0.66)
@export var house_roof_color: Color = Color(0.72, 0.28, 0.16)
@export var arch_color: Color = Color(0.6, 0.6, 0.63)
@export var start_arch_color: Color = Color(0.95, 0.9, 0.74)
@export var item_box_color: Color = Color(0.9, 0.38, 0.15)
@export var item_box_size: float = 1.6

@export_group("Round 2: hazards, pads, zones")
## Moat water color (hazard kind water).
@export var water_color: Color = Color(0.22, 0.48, 0.72)
## Boost pad base and chevron colors.
@export var pad_color_a: Color = Color(0.15, 0.75, 0.85)
@export var pad_color_b: Color = Color(1.0, 0.9, 0.35)
## Scenery anchors written by tools/gen_castle_circuit.py (x, z).
@export var statue_position: Vector2 = Vector2.ZERO
@export var well_position: Vector2 = Vector2.ZERO
@export var lists_center: Vector2 = Vector2.ZERO
@export var orchard_center: Vector2 = Vector2.ZERO
@export var windmill_position: Vector2 = Vector2.ZERO
@export var gate_position: Vector2 = Vector2.ZERO
## Main-loop distance range (from, to) of each castle zone.
@export var zone_tourney: Vector2 = Vector2.ZERO
@export var zone_moat: Vector2 = Vector2.ZERO
@export var zone_village: Vector2 = Vector2.ZERO
@export var zone_keep: Vector2 = Vector2.ZERO
@export var zone_gardens: Vector2 = Vector2.ZERO

@export_group("Scenery road clearance")
## Meters every scenery prop footprint (its half extent, not just its centre) keeps clear of the
## drivable area: inside the walls of the main road and of every branch. Karts collide only with
## road walls, so a prop that reaches over that line is driven through (bugfix 2026-11-20).
@export var scenery_road_margin: float = 0.15
## Pieces whose bottom is at or above this height (m) are over the karts (arch tops, beams,
## awnings, signs) and may hang over the road.
@export var scenery_clear_height: float = 2.5
## Pieces whose top is at or below this height (m) are drive-over surface detail (rail sleepers,
## low curb stones) and may lie on the road.
@export var scenery_flat_height: float = 0.3
## Farthest (m) a prop that reaches over the road is moved away from it; one that still does not
## fit is left out.
@export var scenery_max_nudge: float = 3.0
## Story 008 part 3: a prop whose centre is within this many meters outside a road's wall (or over
## the road) belongs to that road and is raised with it (walls, posts, banners, arches along a
## raised road); farther props (houses, trees) stay on the ground.
@export var scenery_attach_reach: float = 3.0
## Story 008 part 4: a prop raised with its road by more than this (meters) whose centre is beyond
## the road's deck edge stands on a plinth down to the ground (TrackData.deck_under_color), so it
## never floats beside a raised road.
@export var scenery_plinth_min_lift: float = 0.3
## Margin (meters) added around the props' footprint for that plinth, and its smallest side.
@export var scenery_plinth_margin: float = 0.3

@export_group("Round 3: dungeon world and anchors")
## Fog (Dungeon Depths: purple-brown). Off by default.
@export var fog_enabled: bool = false
@export var fog_color: Color = Color(0.2, 0.12, 0.13)
@export var fog_density: float = 0.006
## Lava colors (art bible section 4): core, bright and crust; crystal blue marks shortcuts.
@export var lava_core_color: Color = Color(1.0, 0.416, 0.102)
@export var lava_bright_color: Color = Color(1.0, 0.761, 0.29)
@export var lava_crust_color: Color = Color(0.231, 0.114, 0.094)
@export var crystal_color: Color = Color(0.35, 0.62, 1.0)
## Scenery anchors written by tools/gen_dungeon_depths.py (x, z).
@export var stalagmite_position: Vector2 = Vector2.ZERO
@export var crusher_position: Vector2 = Vector2.ZERO
@export var pulley_position: Vector2 = Vector2.ZERO
@export var lake_center: Vector2 = Vector2.ZERO
@export var lake_radius: float = 40.0
@export var forge_glow_position: Vector2 = Vector2.ZERO
## Main-loop distance ranges of the dungeon zones, and of the pillar hall.
@export var zone_cellar: Vector2 = Vector2.ZERO
@export var zone_torch: Vector2 = Vector2.ZERO
@export var zone_cavern: Vector2 = Vector2.ZERO
@export var zone_mine: Vector2 = Vector2.ZERO
@export var zone_forge: Vector2 = Vector2.ZERO
@export var hall_range: Vector2 = Vector2.ZERO

@export_group("Round 2: zone props (warm storybook palette)")
## Spacing in meters between prop slots along each road edge (one slot per side).
@export var prop_spacing: float = 9.0
@export var stone_light: Color = Color(0.72, 0.7, 0.68)
@export var stone_dark: Color = Color(0.5, 0.49, 0.5)
@export var crowd_colors: PackedColorArray = PackedColorArray([Color(0.9, 0.38, 0.15), Color(0.95, 0.9, 0.74), Color(0.55, 0.36, 0.2), Color(0.85, 0.75, 0.55), Color(0.35, 0.5, 0.75), Color(0.75, 0.25, 0.2)])
@export var tent_color_a: Color = Color(0.9, 0.38, 0.15)
@export var tent_color_b: Color = Color(0.95, 0.9, 0.74)
@export var wood_color: Color = Color(0.55, 0.36, 0.2)
@export var dark_wood_color: Color = Color(0.32, 0.2, 0.12)
@export var foliage_color: Color = Color(0.3, 0.55, 0.22)
@export var foliage_alt_color: Color = Color(0.42, 0.62, 0.25)
@export var fruit_color: Color = Color(0.9, 0.3, 0.15)
@export var hedge_color: Color = Color(0.22, 0.45, 0.2)
@export var torch_color: Color = Color(1.0, 0.62, 0.2)
@export var tapestry_color: Color = Color(0.62, 0.12, 0.12)
@export var statue_color: Color = Color(0.78, 0.76, 0.7)
