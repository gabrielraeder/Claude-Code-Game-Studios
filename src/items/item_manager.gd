class_name ItemManager
extends Node3D
## Item boxes, the held item, and the five items (story 004). One per PC, owned by Main.
## Everything is injected: no autoloads. Rules:
##  - A kart that touches a free box asks the host (reliable); the host's first request wins,
##    rolls the item with the race seed and announces it to everyone (box hidden, respawn).
##  - The firer announces every item use (reliable). Each PC simulates the item locally from
##    that message. No per-frame item traffic.
##  - Only the PC that owns a possible victim (the host for bots) tests contact, decides the
##    hit and announces it (reliable). Nobody spins from an item that looked like a miss.

const STEP: float = 1.0 / 60.0
const MAX_CATCHUP: float = 3.0
const ITEM_Y: float = 0.6
const BOX_PINK: Color = Color("FF4FA3")
const BOX_CREAM: Color = Color("FFF1D0")
const SHIELD_BUBBLE: Color = Color(1.0, 0.894, 0.541, 0.35)

## One item flying or lying on the road.
class ActiveItem extends RefCounted:
	var seq: int = 0
	var index: int = 0
	var owner_id: int = 0
	var target_id: int = -1
	var pos: Vector2 = Vector2.ZERO
	var dir: Vector2 = Vector2.ZERO
	var age: float = 0.0
	var bounces: int = 0
	var s: float = 0.0
	var lateral: float = 0.0
	var dead: bool = false
	var node: Node3D
	var ring: Node3D

## Debug: item index every refill gives (--give-item), -1 = off.
var debug_give: int = -1
## Debug: seconds between automatic uses by the autopilot (--item-interval), 0 = off.
var auto_interval: float = 0.0
## Item index held by the local kart, -1 = none.
var held: int = -1
## Hits decided or received this race (debug log lines, for the cross-PC comparison).
var hit_log: Array[String] = []
## Fired whenever an item event happens: kind, text (debug shots and logs).
signal item_event(kind: StringName, text: String)

var _set: ItemSet
var _track: TrackModel
var _racers_fn: Callable
var _local_fn: Callable
var _place_fn: Callable
var _id_at_place_fn: Callable
var _online_fn: Callable
var _net: NetSession
var _seed: int = 0
var _time: float = 0.0
var _box_free_at: PackedFloat32Array = PackedFloat32Array()
var _taken_count: int = 0
var _pending_box: int = -1
var _roulette_end: float = -1.0
var _granted: int = -1
var _prev_item_btn: bool = false
var _auto_timer: float = 0.0
var _next_seq: int = 1
var _active: Array[ActiveItem] = []
var _early_hits: Dictionary = {}
var _shield: Dictionary = {}
var _shield_nodes: Dictionary = {}
var _box_mm: MultiMeshInstance3D
var _mats: Dictionary = {}
var _box_size: float = 1.6
var _puffs: Array = []
var _crests: Array[Node3D] = []
var _cycle: int = 0
var _spin_prev: Dictionary = {}
var _spin_start: Dictionary = {}
var _slick_seen: Dictionary = {}
var _flames: Dictionary = {}


## Wires the manager. [param racers_fn] returns Array[Racer], [param local_fn] the local Racer,
## [param place_fn] (kart_id) -> place, [param id_at_place_fn] (place) -> kart id or -1,
## [param online_fn] () -> bool (true during an online race). [param net] may be null.
func setup(item_set: ItemSet, racers_fn: Callable, local_fn: Callable, place_fn: Callable,
		id_at_place_fn: Callable, online_fn: Callable, net: NetSession) -> void:
	_set = item_set
	_racers_fn = racers_fn
	_local_fn = local_fn
	_place_fn = place_fn
	_id_at_place_fn = id_at_place_fn
	_online_fn = online_fn
	_net = net
	if _net != null:
		_net.box_take_received.connect(_on_box_take)
		_net.box_taken_received.connect(_on_box_taken)
		_net.item_spawn_received.connect(_on_item_spawn)
		_net.item_hit_received.connect(_on_item_hit)


## Starts a fresh race on [param track] with the shared random [param seed].
func reset(track: TrackModel, seed_value: int) -> void:
	_track = track
	_seed = seed_value
	_time = 0.0
	_taken_count = 0
	_pending_box = -1
	_roulette_end = -1.0
	_granted = -1
	_cycle = 0
	held = 0 if debug_give == -2 else debug_give
	_spin_prev.clear()
	_spin_start.clear()
	_slick_seen.clear()
	for p in _puffs:
		(p.node as Node3D).queue_free()
	_puffs.clear()
	for f in _flames.values():
		(f as Node3D).queue_free()
	_flames.clear()
	_auto_timer = 0.0
	_next_seq = 1
	_early_hits.clear()
	_shield.clear()
	hit_log.clear()
	for ai in _active:
		if ai.node != null:
			ai.node.queue_free()
	_active.clear()
	for n in _shield_nodes.values():
		(n as Node3D).queue_free()
	_shield_nodes.clear()
	_box_free_at = PackedFloat32Array()
	_box_free_at.resize(track.data.item_box_spots.size())
	_box_free_at.fill(-1.0)
	_build_boxes()


## Per physics tick, after the karts moved. [param race_time] is the synced race clock.
func update(dt: float, race_time: float) -> void:
	_time = race_time
	var local: Racer = _local_fn.call()
	for i in _box_free_at.size():
		if _box_free_at[i] >= 0.0 and _time >= _box_free_at[i]:
			_box_free_at[i] = -1.0
	if _time > 0.0 and not local.is_finished() and not local.dropped:
		if held < 0 and _roulette_end < 0.0:
			_try_pickup(local)
		_handle_use(local, dt)
	_update_roulette()
	for ai in _active:
		_step_item(ai, dt)
	_test_hits()
	for kid in _shield.keys():
		_shield[kid] = float(_shield[kid]) - dt
		if float(_shield[kid]) <= 0.0:
			_shield.erase(kid)
	_active = _active.filter(func(a: ActiveItem) -> bool: return not a.dead or _free_node(a))
	_sync_visuals()
	_sync_effects()
	_log_spins()


## True when the kart with [param kart_id] has a shield up.
func has_shield(kart_id: int) -> bool:
	return _shield.has(kart_id)


## HUD data: {visible, color, glyph, spinning}.
func hud_icon() -> Dictionary:
	if _roulette_end >= 0.0:
		var n: int = _set.items.size()
		var i: int = int(_time / _set.roulette_tick) % n
		return {"visible": true, "color": _set.items[i].color, "glyph": "?", "spinning": true}
	if held >= 0:
		var d: ItemDef = _set.items[held]
		return {"visible": true, "color": d.color, "glyph": d.display_name.substr(0, 1), "spinning": false}
	return {"visible": false, "color": Color.WHITE, "glyph": "", "spinning": false}


## Number of items flying or lying around (debug).
func active_count() -> int:
	return _active.size()


## Uses the held item now (the ITEM button, or the autopilot).
func use_item() -> void:
	if held < 0:
		return
	var local: Racer = _local_fn.call()
	var idx: int = held
	held = -1
	var def: ItemDef = _set.items[idx]
	var sim: KartSim = local.sim
	if def.id == &"horn":
		sim.boost_time = maxf(sim.boost_time, def.duration)
		item_event.emit(&"horn", "horn kart=%d" % local.kart_id)
		_log("USE horn kart=%d boost=%.2f" % [local.kart_id, def.duration])
		return
	var fwd: Vector2 = sim.forward()
	var p: Vector2 = sim.position
	var dir: Vector2 = fwd
	var target: int = -1
	match def.id:
		&"stone":
			p = sim.position + fwd * def.spawn_offset
		&"spill":
			p = sim.position - fwd * def.spawn_offset
			dir = -fwd
		&"falcon":
			p = sim.position + fwd * def.spawn_offset
			var place: int = int(_place_fn.call(local.kart_id))
			if place > 1:
				target = int(_id_at_place_fn.call(place - 1))
	var seq: int = local.kart_id * 100000 + _next_seq
	_next_seq += 1
	_spawn(seq, idx, local.kart_id, _time, p, dir, target)
	if _is_online() and _net != null:
		_net.send_item_spawn(seq, idx, local.kart_id, _time, p, dir, target)


# ---------------------------------------------------------------- boxes

func _is_online() -> bool:
	return bool(_online_fn.call())


func _is_host() -> bool:
	return not _is_online() or _net == null or _net.is_host()


func _try_pickup(local: Racer) -> void:
	var r2: float = _set.box_pickup_radius * _set.box_pickup_radius
	for i in _box_free_at.size():
		if _box_free_at[i] >= 0.0:
			continue
		if _track.item_box_position(i).distance_squared_to(local.sim.position) <= r2:
			item_event.emit(&"roulette", "box=%d owner=%d" % [i, local.kart_id])
			_pending_box = i
			_roulette_end = _time + _set.roulette_time
			_granted = -1
			if _is_host():
				_grant(i, local.kart_id)
			elif _net != null:
				_net.send_box_take(i, local.kart_id)
			return


func _on_box_take(box: int, kart_id: int) -> void:
	if _is_online() and _is_host():
		_grant(box, kart_id)


# Host (or solo): first request for a free box wins; the loser gets nothing.
func _grant(box: int, kart_id: int) -> void:
	if box < 0 or box >= _box_free_at.size() or _box_free_at[box] >= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_seed, box, _taken_count])
	_taken_count += 1
	var item: int = _set.roll(int(_place_fn.call(kart_id)), rng)
	if _is_online() and _net != null:
		_net.send_box_taken(box, kart_id, _time, item)
	_apply_taken(box, kart_id, _time, item)


func _on_box_taken(box: int, kart_id: int, t: float, item: int) -> void:
	if _is_online():
		_apply_taken(box, kart_id, t, item)


func _apply_taken(box: int, kart_id: int, t: float, item: int) -> void:
	if box < 0 or box >= _box_free_at.size():
		return
	_box_free_at[box] = t + _set.box_respawn
	var local: Racer = _local_fn.call()
	if kart_id == local.kart_id:
		if _roulette_end >= 0.0 and _pending_box == box:
			_granted = item
		elif held < 0 and _roulette_end < 0.0:
			held = item
	elif _pending_box == box and _roulette_end >= 0.0:
		_roulette_end = -1.0
		_pending_box = -1
		_granted = -1
		_log("LOST box %d to kart %d" % [box, kart_id])
	_log("BOX %d kart=%d item=%s" % [box, kart_id, _set.items[item].id])


func _update_roulette() -> void:
	if _roulette_end < 0.0:
		return
	if _time >= _roulette_end and _granted >= 0:
		held = _granted
		_roulette_end = -1.0
		_pending_box = -1
		_granted = -1
	elif _time >= _roulette_end + 3.0:
		_roulette_end = -1.0
		_pending_box = -1


func _handle_use(local: Racer, dt: float) -> void:
	var btn: bool = local.input.item
	if btn and not _prev_item_btn:
		use_item()
	_prev_item_btn = btn
	if auto_interval > 0.0:
		_auto_timer += dt
		if _auto_timer >= auto_interval:
			_auto_timer = 0.0
			if held < 0 and debug_give != -1 and _roulette_end < 0.0:
				if debug_give == -2:
					_cycle = (_cycle + 1) % _set.items.size()
					held = _cycle
				else:
					held = debug_give
			use_item()


# ---------------------------------------------------------------- items in the world

func _on_item_spawn(seq: int, item: int, owner_id: int, t: float, pos: Vector2, dir: Vector2, target: int) -> void:
	if not _is_online() or item < 0 or item >= _set.items.size():
		return
	_spawn(seq, item, owner_id, t, pos, dir, target)


func _spawn(seq: int, idx: int, owner_id: int, t: float, pos: Vector2, dir: Vector2, target: int) -> void:
	var def: ItemDef = _set.items[idx]
	_log("USE %s seq=%d owner=%d target=%d" % [def.id, seq, owner_id, target])
	item_event.emit(def.id, "spawn seq=%d owner=%d" % [seq, owner_id])
	if def.id == &"shield":
		_shield[owner_id] = def.duration
		return
	if _early_hits.has(seq):
		_early_hits.erase(seq)
		return
	var ai := ActiveItem.new()
	ai.seq = seq
	ai.index = idx
	ai.owner_id = owner_id
	ai.target_id = target
	ai.pos = pos
	ai.dir = dir
	if def.id == &"falcon":
		var q: TrackModel.Query = _track.query(pos, -1)
		ai.s = q.s
		ai.lateral = q.lateral
	ai.node = _make_item_node(def)
	add_child(ai.node)
	if def.id == &"falcon" and target >= 0:
		var tor := TorusMesh.new()
		tor.inner_radius = 1.6
		tor.outer_radius = 1.9
		ai.ring = _prim(tor, def.accent, Vector3.ZERO, true)
		add_child(ai.ring)
	_active.append(ai)
	var steps: int = int(clampf(_time - t, 0.0, MAX_CATCHUP) / STEP)
	for i in steps:
		if ai.dead:
			break
		_step_item(ai, STEP)


func _step_item(ai: ActiveItem, dt: float) -> void:
	if ai.dead:
		return
	var def: ItemDef = _set.items[ai.index]
	ai.age += dt
	if ai.age > def.lifetime:
		ai.dead = true
		_log("END %s seq=%d (expired)" % [def.id, ai.seq])
		return
	match def.id:
		&"stone":
			ai.pos += ai.dir * def.speed * dt
			var q: TrackModel.Query = _track.query(ai.pos, -1)
			var limit: float = q.wall_offset - def.radius
			if absf(q.lateral) > limit:
				var n: Vector2 = q.normal * signf(q.lateral)
				if ai.dir.dot(n) > 0.0:
					ai.dir = (ai.dir - 2.0 * ai.dir.dot(n) * n).normalized()
					ai.bounces += 1
					item_event.emit(&"bounce", "seq=%d n=%d" % [ai.seq, ai.bounces])
					if ai.bounces > def.max_bounces:
						ai.dead = true
						_log("END stone seq=%d (bounces)" % ai.seq)
						return
				ai.pos -= n * (absf(q.lateral) - limit)
		&"falcon":
			ai.s += def.speed * dt
			var target: Racer = _racer_by_id(ai.target_id)
			if target != null and not target.dropped:
				var tq: TrackModel.Query = _track.query(target.sim.position, -1)
				var ahead: float = wrapf(tq.s - ai.s, -_track.length * 0.5, _track.length * 0.5)
				if ahead > def.lose_range or ahead < -def.pass_miss:
					ai.dead = true
					_log("END falcon seq=%d (missed)" % ai.seq)
					return
				ai.lateral = move_toward(ai.lateral, tq.lateral, def.turn_rate * dt)
			ai.pos = _track.point_at(ai.s) + _track.normal_at(ai.s) * ai.lateral
			if ai.dir.length_squared() > 0.0:
				ai.dir = _track.tangent_at(ai.s)


func _test_hits() -> void:
	var racers: Array = _racers_fn.call()
	for ai in _active:
		if ai.dead:
			continue
		var def: ItemDef = _set.items[ai.index]
		var reach: float = def.radius + _set.kart_hit_radius
		for r: Racer in racers:
			if not r.owned or r.dropped or r.is_finished():
				continue
			if r.kart_id == ai.owner_id and (def.id != &"spill" or ai.age < def.arm_time):
				continue
			if def.id == &"falcon" and r.kart_id != ai.target_id and ai.target_id >= 0:
				continue
			if r.sim.position.distance_to(ai.pos) > reach:
				continue
			if r.sim.spin_time > 0.0 or r.sim.is_hit_immune() or r.sim.is_sinking():
				continue
			_victim_hit(ai, r)
			break


func _victim_hit(ai: ActiveItem, r: Racer) -> void:
	var blocked: bool = _shield.has(r.kart_id)
	if blocked:
		_shield.erase(r.kart_id)
	else:
		r.sim.hit()
		r.sim.apply_hit_slowdown(_set.hit_slowdown_profile)
		r.sim.start_hit_immunity()
	_log("DECIDE seq=%d item=%s victim=%d blocked=%d bounces=%d age=%.2f" % [ai.seq, _set.items[ai.index].id, r.kart_id, 1 if blocked else 0, ai.bounces, ai.age])
	if _is_online() and _net != null:
		_net.send_item_hit(ai.seq, r.kart_id, blocked, _time)
	_register_hit(ai, r.kart_id, blocked, _time)


func _on_item_hit(seq: int, victim: int, blocked: bool, t: float) -> void:
	if not _is_online():
		return
	for ai in _active:
		if ai.seq == seq:
			if blocked:
				_shield.erase(victim)
			_register_hit(ai, victim, blocked, t)
			return
	_early_hits[seq] = true
	if blocked:
		_shield.erase(victim)
	hit_log.append("HIT seq=%d victim=%d blocked=%d t=%.2f" % [seq, victim, 1 if blocked else 0, t])
	_log(hit_log[-1])


func _register_hit(ai: ActiveItem, victim: int, blocked: bool, t: float) -> void:
	ai.dead = true
	var id: StringName = _set.items[ai.index].id
	var line: String = "HIT seq=%d item=%s victim=%d blocked=%d t=%.2f" % [ai.seq, id, victim, 1 if blocked else 0, t]
	hit_log.append(line)
	_log(line)
	item_event.emit(&"shield_break" if blocked else &"hit", "victim=%d item=%s" % [victim, id])
	var vr: Racer = _racer_by_id(victim)
	if vr != null:
		_spawn_puff(vr, blocked)


func _racer_by_id(id: int) -> Racer:
	for r: Racer in _racers_fn.call():
		if r.kart_id == id:
			return r
	return null


func _free_node(ai: ActiveItem) -> bool:
	if ai.ring != null:
		ai.ring.queue_free()
		ai.ring = null
	if ai.node != null:
		ai.node.queue_free()
		ai.node = null
	return false


func _log(text: String) -> void:
	print("[item] t=%.2f %s" % [_time, text])


# ---------------------------------------------------------------- visuals

func _mat(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var key: String = "%s%s" % [color.to_html(true), emissive]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if emissive:
			m.emission_enabled = true
			m.emission = color
		_mats[key] = m
	return _mats[key]


func _prim(mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO, emissive: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color, emissive)
	mi.position = pos
	return mi


func _make_item_node(def: ItemDef) -> Node3D:
	var n := Node3D.new()
	match def.id:
		&"stone":
			var s := SphereMesh.new()
			s.radius = def.radius
			s.height = def.radius * 2.0
			n.add_child(_prim(s, def.color))
			var e := SphereMesh.new()
			e.radius = def.radius * 0.5
			e.height = def.radius
			n.add_child(_prim(e, def.accent, Vector3(0, 0, def.radius * 1.4), true))
		&"spill":
			var c := CylinderMesh.new()
			c.top_radius = def.radius
			c.bottom_radius = def.radius
			c.height = 0.08
			var slick: MeshInstance3D = _prim(c, def.color, Vector3(0, -ITEM_Y + 0.08, 0), true)
			n.add_child(slick)
			for i in 5:
				var b := SphereMesh.new()
				b.radius = 0.25
				b.height = 0.5
				var a: float = TAU * float(i) / 5.0
				n.add_child(_prim(b, def.accent, Vector3(cos(a), -ITEM_Y + 0.3, sin(a)) * def.radius * 0.5))
		&"falcon":
			var body := BoxMesh.new()
			body.size = Vector3(0.7, 0.6, 1.8)
			n.add_child(_prim(body, def.color))
			var wing := BoxMesh.new()
			wing.size = Vector3(3.0, 0.12, 0.9)
			n.add_child(_prim(wing, def.color, Vector3(0, 0.1, 0.1)))
	return n


func _build_boxes() -> void:
	if _box_mm != null:
		_box_mm.queue_free()
		_box_mm = null
	var count: int = _box_free_at.size()
	if count == 0:
		return
	_box_size = _track.theme.item_box_size if _track.theme != null else 1.6
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	mm.mesh = cube
	mm.instance_count = count * 3
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.1, 0.2)
	_box_mm = MultiMeshInstance3D.new()
	_box_mm.multimesh = mm
	_box_mm.material_override = mat
	add_child(_box_mm)
	for i in count:
		mm.set_instance_color(i * 3, BOX_PINK)
		mm.set_instance_color(i * 3 + 1, BOX_CREAM)
		mm.set_instance_color(i * 3 + 2, BOX_CREAM)
	for c in _crests:
		c.queue_free()
	_crests.clear()
	for i in count:
		var holder := Node3D.new()
		for k in 4:
			var lab := Label3D.new()
			lab.text = "?"
			lab.font_size = 96
			lab.pixel_size = _box_size * 0.012
			lab.modulate = BOX_CREAM
			lab.outline_modulate = Color("8A1F55")
			lab.outline_size = 24
			var a: float = PI * 0.5 * float(k)
			lab.position = Vector3(sin(a), 0.0, cos(a)) * (_box_size * 0.52)
			lab.rotation.y = a
			holder.add_child(lab)
		add_child(holder)
		_crests.append(holder)


func _sync_visuals() -> void:
	if _box_mm != null:
		var mm: MultiMesh = _box_mm.multimesh
		for i in _box_free_at.size():
			var p: Vector2 = _track.item_box_position(i)
			var visible_box: bool = _box_free_at[i] < 0.0
			var sz: float = _box_size if visible_box else 0.0001
			var bob: float = sin(_time * 2.2 + float(i)) * 0.18
			var basis := Basis(Vector3.UP, _time * 1.6 + float(i))
			var origin := Vector3(p.x, _box_size * 1.0 + bob, p.y)
			mm.set_instance_transform(i * 3, Transform3D(basis.scaled(Vector3(sz, sz, sz)), origin))
			if i < _crests.size():
				_crests[i].position = origin
				_crests[i].rotation.y = _time * 1.6 + float(i)
				_crests[i].visible = visible_box
			var slab: float = sz * 1.04
			mm.set_instance_transform(i * 3 + 1, Transform3D(basis.scaled(Vector3(slab, slab, sz * 0.2)), origin))
			mm.set_instance_transform(i * 3 + 2, Transform3D(basis.scaled(Vector3(sz * 0.2, slab, slab)), origin))
	for ai in _active:
		if ai.node == null:
			continue
		ai.node.position = Vector3(ai.pos.x, ITEM_Y, ai.pos.y)
		ai.node.rotation.y = atan2(-ai.dir.x, -ai.dir.y)
		if ai.ring != null:
			var tr: Racer = _racer_by_id(ai.target_id)
			if tr != null:
				ai.ring.position = Vector3(tr.sim.position.x, 1.0, tr.sim.position.y)
				var dist: float = tr.sim.position.distance_to(ai.pos)
				ai.ring.scale = Vector3.ONE * lerpf(0.8, 3.0, clampf(dist / 40.0, 0.0, 1.0))
	for r: Racer in _racers_fn.call():
		var up: bool = _shield.has(r.kart_id) and not r.dropped
		if up and not _shield_nodes.has(r.kart_id):
			var sph := SphereMesh.new()
			sph.radius = 1.7
			sph.height = 3.4
			var bubble: MeshInstance3D = _prim(sph, SHIELD_BUBBLE)
			add_child(bubble)
			_shield_nodes[r.kart_id] = bubble
		elif not up and _shield_nodes.has(r.kart_id):
			(_shield_nodes[r.kart_id] as Node3D).queue_free()
			_shield_nodes.erase(r.kart_id)
		if up:
			(_shield_nodes[r.kart_id] as Node3D).position = Vector3(r.sim.position.x, 0.9, r.sim.position.y)


# Star puff / dust ring (slapstick hit feedback) or a shield-break burst around [param r].
func _spawn_puff(r: Racer, blocked: bool) -> void:
	var root := Node3D.new()
	var color: Color = Color(1.0, 0.894, 0.541) if blocked else Color(1.0, 0.9, 0.3)
	for i in 6:
		var st := SphereMesh.new()
		st.radius = 0.22
		st.height = 0.44
		var a: float = TAU * float(i) / 6.0
		root.add_child(_prim(st, color, Vector3(cos(a), 0.0, sin(a)) * 1.3, true))
	var ring := TorusMesh.new()
	ring.inner_radius = 1.5
	ring.outer_radius = 1.8
	root.add_child(_prim(ring, Color(0.85, 0.8, 0.7, 0.8), Vector3(0, -0.5, 0)))
	add_child(root)
	_puffs.append({"node": root, "racer": r, "until": _time + 1.0})
	var flash := SphereMesh.new()
	flash.radius = 1.25
	flash.height = 2.5
	var fl := Node3D.new()
	fl.add_child(_prim(flash, Color(1, 1, 1, 0.28), Vector3(0, -1.2, 0), false))
	add_child(fl)
	_puffs.append({"node": fl, "racer": r, "until": _time + 0.1})


func _sync_effects() -> void:
	var me: Racer = _local_fn.call()
	for ai in _active:
		if ai.dead or _set.items[ai.index].id != &"spill" or _slick_seen.has(ai.seq):
			continue
		var off: Vector2 = ai.pos - me.sim.position
		if off.length() > 8.0 and off.length() < 22.0 and off.normalized().dot(me.sim.forward()) > 0.9:
			_slick_seen[ai.seq] = true
			item_event.emit(&"slick_ahead", "seq=%d" % ai.seq)
	var keep: Array = []
	for p in _puffs:
		var r: Racer = p.racer
		var n: Node3D = p.node
		if _time >= float(p.until):
			n.queue_free()
			continue
		n.position = Vector3(r.sim.position.x, 2.0, r.sim.position.y)
		n.rotation.y = _time * 8.0
		keep.append(p)
	_puffs = keep
	for r: Racer in _racers_fn.call():
		var burning: bool = r.sim.boost_time > 0.0 and not r.dropped
		if burning and not _flames.has(r.kart_id):
			var cone := CylinderMesh.new()
			cone.top_radius = 0.05
			cone.bottom_radius = 0.45
			cone.height = 1.8
			var f: MeshInstance3D = _prim(cone, Color("FF7A33"), Vector3.ZERO, true)
			add_child(f)
			_flames[r.kart_id] = f
		elif not burning and _flames.has(r.kart_id):
			(_flames[r.kart_id] as Node3D).queue_free()
			_flames.erase(r.kart_id)
		if burning:
			var fn: Node3D = _flames[r.kart_id]
			var back: Vector2 = r.sim.position - r.sim.forward() * 2.4
			fn.position = Vector3(back.x, 0.55, back.y)
			fn.rotation = Vector3(-PI * 0.5, r.sim.yaw, 0.0)
			fn.scale = Vector3.ONE * (0.8 + 0.3 * sin(_time * 40.0))


# Debug log of every spin start/end per kart, to check each spin has a matching hit event.
func _log_spins() -> void:
	for r: Racer in _racers_fn.call():
		var now: float = r.sim.spin_time
		var prev: float = float(_spin_prev.get(r.kart_id, 0.0))
		if prev <= 0.0 and now > 0.0:
			_spin_start[r.kart_id] = _time
			_log("SPIN kart=%d" % r.kart_id)
		elif prev > 0.0 and now <= 0.0:
			_log("SPINEND kart=%d dur=%.2f" % [r.kart_id, _time - float(_spin_start.get(r.kart_id, _time))])
		_spin_prev[r.kart_id] = now
