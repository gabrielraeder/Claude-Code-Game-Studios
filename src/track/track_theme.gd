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
