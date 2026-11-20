class_name ItemDef
extends Resource
## Tuning for one item (story 004). Every number the item uses lives here, none in code.

## Short id: horn, stone, spill, falcon, shield.
@export var id: StringName = &""
@export var display_name: String = ""
## Flat HUD icon color and the color of the item in the world (art bible Section 2).
@export var color: Color = Color.WHITE
## Secondary color (ember trail, shield bubble, lock-on ring).
@export var accent: Color = Color.WHITE
## Horn: boost seconds. Shield: seconds before it fades if unused. Spill and Stone: unused.
@export var duration: float = 0.0
## Stone and Falcon flight speed in m/s.
@export var speed: float = 0.0
## Contact radius of the item in meters (added to the kart radius).
@export var radius: float = 1.0
## Stone: wall bounces before it breaks.
@export var max_bounces: int = 0
## Seconds an item stays in the world (stone, spill, falcon).
@export var lifetime: float = 0.0
## Spill: seconds before the owner can also be hit by its own slick.
@export var arm_time: float = 0.0
## Meters in front of (stone) or behind (spill) the kart where the item appears.
@export var spawn_offset: float = 2.5
## Falcon: sideways meters per second it can steer (the target dodges by out-running it).
@export var turn_rate: float = 0.0
## Falcon: it gives up when the target is farther ahead than this many meters along the track.
@export var lose_range: float = 0.0
## Falcon: it counts as a miss once it is this many meters past the target without a hit.
@export var pass_miss: float = 8.0
