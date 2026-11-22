@tool
class_name WallAttr
extends Resource
## One wall attribute of the core rebuild (ADR-0002; core-rebuild story 002): how a class of wall
## scales the wall response Kart Physics computes (Track Collision GDD section 3.3). One per class in
## a WallAttrSet. Wall shape k of a track carries the id of its attribute
## (TrackCollisionData.wall_attr_ids, story 003).
##
## There is no "opening" field on purpose: an opening is the absence of wall geometry, and Course
## Data derives WALL_OPENING / OPEN_EDGE from its own lateral wall sweeps (ADR-0004).
## Plain data: read-only after load, safe to read from any thread.
## [codeblock]
## var walls: WallAttrSet = WallAttrSet.load_checked(WallAttrSet.CORE_PATH)
## var rough: WallAttr = walls.attr_of(&"rough")
## var drag_scale: float = rough.scrape_drag_mult  # 2.0
## [/codeblock]

## Name of the class; Blender material wall_<name> maps to it (for example &"standard", &"rough").
@export var name: StringName = &""
## Stable wall-attribute id: unique, >= 0, append-only, a removed id is never reused. -1 = no id
## (rejected by WallAttrSet.load_checked).
@export var id: int = -1
## Multiplier on the wall scrape drag of the kart's VehicleStats (1 = a standard wall; 2 = rough
## stone that grinds a sliding kart twice as hard). Used by the wall response (story 014).
@export_range(0.0, 10.0, 0.01) var scrape_drag_mult: float = 1.0
## Multiplier on VehicleStats.bump_knockback when a kart hits this wall. 1.0 is parity with the
## frozen game, where no wall bounces differently (Track Collision GDD 3.3 / 4.3); > 1 would be a
## bumper-style wall, which is new design (open decision C5). Used by the wall response (story 014).
@export_range(0.0, 10.0, 0.01) var bounce_mult: float = 1.0
