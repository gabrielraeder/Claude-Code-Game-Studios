@tool
class_name WallAttrSet
extends Resource
## The core rebuild's registry of wall attributes (ADR-0002; core-rebuild story 002): one WallAttr
## per wall class, each with a stable id. Shipped as assets/data/core/wall_attr_set.tres. The frozen
## game never uses it.
##
## Id policy (same as surfaces): unique, >= 0, append-only, a removed id is never reused. The array
## index is never the id. A new class is added here first, never invented in Blender.
## Read-only after load: attr_of() keeps no cache, so it is safe to call from any thread.
## [codeblock]
## var walls: WallAttrSet = WallAttrSet.load_checked(WallAttrSet.CORE_PATH)
## if walls == null:
##     return  # the registry is broken: refuse to import or load the track
## var attr: WallAttr = walls.attr_of(&"rough")  # material wall_rough
## if attr == null:
##     push_error("unknown wall material")  # an unknown name fails the import
## [/codeblock]

## Resource path of the shipped core set.
const CORE_PATH: String = "res://assets/data/core/wall_attr_set.tres"
## Largest wall-attribute id, the same u8 bound as SurfaceSet.MAX_ID (ADR-0002). A format limit,
## not tuning.
const MAX_ID: int = 255

## One entry per wall class.
@export var attrs: Array[WallAttr] = []


## The WallAttr named [param attr_name] (the <name> of a wall_<name> material), or null when the
## set has none (an unknown name is not found).
## [codeblock]
## var standard: WallAttr = walls.attr_of(&"standard")
## var missing: WallAttr = walls.attr_of(&"marble")  # null
## [/codeblock]
func attr_of(attr_name: StringName) -> WallAttr:
	for a in attrs:
		if a != null and a.name == attr_name:
			return a
	return null


## Loads the WallAttrSet at [param path] and checks it (ADR-0002). Returns null, after a push_error
## naming the path and the problem, when: the path has no resource; it is not a WallAttrSet; an
## attribute is null; a name is empty or repeated; or an id is outside 0..MAX_ID or repeated.
## Reads only; safe to call from any thread, but the returned set is shared through the resource
## cache, so treat it as read-only.
## [codeblock]
## var walls: WallAttrSet = WallAttrSet.load_checked(WallAttrSet.CORE_PATH)
## [/codeblock]
static func load_checked(path: String) -> WallAttrSet:
	if not ResourceLoader.exists(path):
		push_error("WallAttrSet.load_checked: %s not found" % path)
		return null
	var loaded: WallAttrSet = load(path) as WallAttrSet
	if loaded == null:
		push_error("WallAttrSet.load_checked: %s is not a WallAttrSet" % path)
		return null
	var seen_names: Dictionary[StringName, bool] = {}
	var seen_ids: Dictionary[int, bool] = {}
	for i in loaded.attrs.size():
		var a: WallAttr = loaded.attrs[i]
		if a == null:
			push_error("WallAttrSet.load_checked: %s has a null attribute at index %d" % [path, i])
			return null
		if a.name.is_empty():
			push_error("WallAttrSet.load_checked: %s has an attribute with an empty name at index %d" % [path, i])
			return null
		if seen_names.has(a.name):
			push_error("WallAttrSet.load_checked: %s repeats name %s" % [path, a.name])
			return null
		if a.id < 0 or a.id > MAX_ID:
			push_error("WallAttrSet.load_checked: %s attribute %s has id %d, outside 0..%d" % [path, a.name, a.id, MAX_ID])
			return null
		if seen_ids.has(a.id):
			push_error("WallAttrSet.load_checked: %s repeats wall-attribute id %d (%s)" % [path, a.id, a.name])
			return null
		seen_names[a.name] = true
		seen_ids[a.id] = true
	return loaded
