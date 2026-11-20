class_name BotDebug
extends Node3D
## DEBUG AID (story 005). Added by Main only when a bot debug switch is on the command line:
##   --bot-labels         floating label above every host-owned bot: personality and held item
##   --bot-cam=ID         a camera behind bot ID (kart id) instead of the player's chase camera
##   --bot-shots=DIR      save viewport PNGs: every --bot-shot-every seconds (default 5) and
##                        a moment after any bot uses an item (the camera then follows that bot)

const FOLLOW_BACK: float = 14.0
const FOLLOW_UP: float = 6.0
const ITEM_FOLLOW_TIME: float = 3.0

var _racers_fn: Callable
var _labels: Dictionary = {}
var _cam: Camera3D
var _follow_id: int = -1
var _follow_until: float = 0.0
var _shots_dir: String = ""
var _every: float = 5.0
var _next_shot: float = 6.0
var _clock: float = 0.0
var _shot_n: int = 0
var _item_shots: Dictionary = {}
var _labels_on: bool = false


## [param racers_fn] returns Array[Racer]; [param items] is the ItemManager (item events);
## [param args] the user command-line args.
func setup(racers_fn: Callable, items: ItemManager, args: PackedStringArray) -> void:
	_racers_fn = racers_fn
	_labels_on = "--bot-labels" in args
	for a in args:
		if a.begins_with("--bot-cam="):
			_follow_id = int(a.substr("--bot-cam=".length()))
		elif a.begins_with("--bot-shots="):
			_shots_dir = a.substr("--bot-shots=".length())
		elif a.begins_with("--bot-shot-start="):
			_next_shot = float(a.substr("--bot-shot-start=".length()))
		elif a.begins_with("--bot-shot-every="):
			_every = float(a.substr("--bot-shot-every=".length()))
	if _follow_id >= 0 or _shots_dir != "":
		_cam = Camera3D.new()
		_cam.far = 1500.0
		add_child(_cam)
		_cam.current = true
	if _shots_dir != "":
		DirAccess.make_dir_recursive_absolute(_shots_dir)
		items.item_event.connect(_on_item_event)


func _on_item_event(kind: StringName, text: String) -> void:
	if kind not in [&"horn", &"stone", &"spill", &"falcon", &"shield"]:
		return
	var owner_id: int = -1
	for part in text.split(" "):
		if part.begins_with("owner=") or part.begins_with("kart="):
			owner_id = int(part.get_slice("=", 1))
	var r: Racer = _find(owner_id)
	if r == null or not r.is_bot:
		return
	if int(_item_shots.get(kind, 0)) >= 2:
		return
	_item_shots[kind] = int(_item_shots.get(kind, 0)) + 1
	_follow_id = owner_id
	_follow_until = _clock + ITEM_FOLLOW_TIME
	await get_tree().create_timer(0.35).timeout
	if not is_inside_tree():
		return
	_save("item_%s_kart%d" % [kind, owner_id])


func _find(id: int) -> Racer:
	for r: Racer in _racers_fn.call():
		if r.kart_id == id:
			return r
	return null


func _save(tag: String) -> void:
	var path: String = "%s/%02d_%s.png" % [_shots_dir, _shot_n, tag]
	_shot_n += 1
	print("[bot-debug] screenshot %s (err %d)" % [path, get_viewport().get_texture().get_image().save_png(path)])


func _process(delta: float) -> void:
	_clock += delta
	var seen: Dictionary = {}
	for r: Racer in _racers_fn.call():
		var d: BotDriver = r.driver as BotDriver
		if d == null or r.dropped or r.sim == null:
			continue
		seen[r.kart_id] = true
		if _labels_on:
			if not _labels.has(r.kart_id):
				var l := Label3D.new()
				l.font_size = 48
				l.pixel_size = 0.012
				l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				l.no_depth_test = true
				l.outline_size = 12
				add_child(l)
				_labels[r.kart_id] = l
			var lab: Label3D = _labels[r.kart_id]
			lab.text = d.describe()
			lab.position = Vector3(r.sim.position.x, 3.2, r.sim.position.y)
	for id in _labels.keys():
		(_labels[id] as Label3D).visible = seen.has(id)
	if _cam != null:
		var f: Racer = _find(_follow_id)
		if f != null:
			var fwd: Vector2 = f.sim.forward()
			var p: Vector3 = Vector3(f.sim.position.x, 0.0, f.sim.position.y)
			_cam.global_position = p - Vector3(fwd.x, 0.0, fwd.y) * FOLLOW_BACK + Vector3.UP * FOLLOW_UP
			_cam.look_at(p + Vector3(fwd.x, 0.0, fwd.y) * 8.0 + Vector3.UP * 1.0, Vector3.UP)
	if _shots_dir != "" and _clock >= _next_shot:
		_next_shot = _clock + _every
		_save("t%03d" % int(_clock))
