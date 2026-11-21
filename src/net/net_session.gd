class_name NetSession
extends Node
## The network layer (story 002): ENet host/join, the RPCs, ping/pong clock sync and the
## fake-network send queue. It owns no game state; Main injects the clock callables and
## listens to the signals. Must be a child of Main named "NetSession" on every PC so RPC
## paths match.
##
## Messages: rpc_race_start (host -> clients, reliable, carries the protocol version),
## rpc_state (any peer -> all, unreliable ordered, one KartWire array per owned kart),
## rpc_ping / rpc_pong (client <-> host, unreliable). Every send goes through _send() so
## --lag/--jitter/--loss apply, and through _call_if_connected() so a send never reaches a
## peer that has disconnected.

## A peer connected (host side: a joiner; client side: also the host and other clients).
signal peer_joined(peer_id: int)
## A peer disconnected.
signal peer_left(peer_id: int)
## This client connected to the host.
signal connected_to_host
## This client could not connect.
signal connection_failed
## This client lost the host.
signal host_lost
## The host started the race; [param info] holds version, slots, laps and host_time.
signal race_start_received(info: Dictionary)
## A kart state update arrived.
signal state_received(kart_id: int, t: float, d: PackedFloat32Array)
## Host side: a client told us its loadout (racer and vehicle index, story 006).
signal loadout_received(peer_id: int, racer: int, vehicle: int)
## A pong arrived: host race clock, whether the host is racing, and the round trip in seconds.
## Another PC bumped [param kart_id] (owned here) with [param from_kart]'s kart.
signal bump_received(kart_id: int, from_kart: int, impulse: Vector2, strength: float)
## (pong)
signal pong_received(host_race_time: float, host_active: bool, rtt_sample: float)

## Returns the host's race clock (float). Set by Main.
## Item messages (story 004): all reliable.
signal box_take_received(box: int, kart_id: int, wants_item: bool)
signal box_taken_received(box: int, kart_id: int, t: float, item: int)
signal item_spawn_received(seq: int, item: int, owner_id: int, t: float, pos: Vector2, dir: Vector2, target: int)
signal item_hit_received(seq: int, victim: int, blocked: bool, t: float)

var race_clock: Callable
## Returns true while the host is racing. Set by Main.
var race_active: Callable
## Fake network, milliseconds of one-way delay.
var lag_ms: float = 0.0
## Fake network, extra random delay up to this many milliseconds.
var jitter_ms: float = 0.0
## Fake network, percent of position updates dropped.
var loss_pct: float = 0.0

var _config: NetConfig
var _active: bool = false
var _hooked: bool = false
var _queue: Array[Dictionary] = []
var _last_reliable_at: int = 0
var _ping_timer: float = 0.0
var _is_host_flag: bool = false
var _my_id: int = 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Injects the tuning data and fake-network settings.
func setup(config: NetConfig, lag: float, jitter: float, loss: float) -> void:
	_config = config
	lag_ms = lag
	jitter_ms = jitter
	loss_pct = loss


## Starts hosting. Returns OK or an Error.
func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(_config.port, _config.max_racers - 1)
	if err != OK:
		return err
	_open(peer, true)
	return OK


## Joins [param address] ("ip" or "ip:port"). Returns OK or an Error.
func join(address: String) -> Error:
	var port: int = _config.port
	var ip: String = address
	if address.count(":") == 1:
		var parts: PackedStringArray = address.split(":")
		ip = parts[0]
		port = parts[1].to_int()
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, port)
	if err != OK:
		return err
	_open(peer, false)
	return OK


## Closes the connection and drops queued messages.
func close() -> void:
	_active = false
	_queue.clear()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


## True while a host or client connection exists.
func is_active() -> bool:
	return _active


## True when this PC is the host.
func is_host() -> bool:
	return _active and _is_host_flag


## This PC's peer id (1 for the host).
func my_id() -> int:
	if _active and not _is_host_flag and _is_connected():
		_my_id = multiplayer.get_unique_id()
	return _my_id


## Ids of the connected peers.
func peer_ids() -> Array[int]:
	var out: Array[int] = []
	if _active:
		for p in multiplayer.get_peers():
			out.append(p)
	return out


## Host only: disconnects [param id] (used for joins after the race started).
func kick(id: int) -> void:
	if _active and multiplayer.is_server() and multiplayer.get_peers().has(id):
		multiplayer.multiplayer_peer.disconnect_peer(id)


## Host only: sends the race start to every client (reliable).
func broadcast_race_start(info: Dictionary) -> void:
	if not _active:
		return
	_send(func() -> void: rpc_race_start.rpc(info), true, false)


## Sends one kart's state to everyone (unreliable ordered; fake loss applies).
func send_state(kart_id: int, t: float, d: PackedFloat32Array) -> void:
	if not _active:
		return
	_send(func() -> void: rpc_state.rpc(kart_id, t, d), false, true)


## Client to host: this PC's racer and vehicle choice (reliable, story 006).
func send_loadout(racer: int, vehicle: int) -> void:
	if not _active or _is_host_flag:
		return
	_send(func() -> void: rpc_loadout.rpc_id(1, racer, vehicle), true, false, 1)


## Tells [param to_peer], the owner of [param kart_id], that [param from_kart] bumped it.
func send_bump(to_peer: int, kart_id: int, from_kart: int, impulse: Vector2, strength: float) -> void:
	if not _active:
		return
	_send(func() -> void: rpc_bump.rpc_id(to_peer, kart_id, from_kart, impulse.x, impulse.y, strength),
			true, false, to_peer)


## Client to host: "my kart drove through item box [param box]" (reliable). The host decides.
## [param wants_item] is false when the kart already holds an item or its roulette spins: the
## box only breaks. Changed in KartWire.VERSION 5.
func send_box_take(box: int, kart_id: int, wants_item: bool) -> void:
	if not _active:
		return
	_send(func() -> void: rpc_box_take.rpc_id(1, box, kart_id, wants_item), true, false, 1)


## Host to everyone: kart [param kart_id] got [param item] from [param box] at race time [param t].
## [param item] -1 = the box broke and gave nothing (KartWire.VERSION 5).
func send_box_taken(box: int, kart_id: int, t: float, item: int) -> void:
	if not _active:
		return
	_send(func() -> void: rpc_box_taken.rpc(box, kart_id, t, item), true, false)


## Firer to everyone: an item was used (reliable). [param p] holds x, z, dir x, dir z.
func send_item_spawn(seq: int, item: int, owner_id: int, t: float, p: Vector2, dir: Vector2, target: int) -> void:
	if not _active:
		return
	_send(func() -> void: rpc_item_spawn.rpc(seq, item, owner_id, t, p.x, p.y, dir.x, dir.y, target), true, false)


## Victim's PC to everyone: item [param seq] hit [param victim] (or was blocked by its shield).
func send_item_hit(seq: int, victim: int, blocked: bool, t: float) -> void:
	if not _active:
		return
	_send(func() -> void: rpc_item_hit.rpc(seq, victim, blocked, t), true, false)


## Bytes (sent, received) since the last call.
func pop_bandwidth() -> Vector2:
	var p: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if not _active or p == null or p.host == null:
		return Vector2.ZERO
	return Vector2(p.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA),
			p.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))


func _open(peer: ENetMultiplayerPeer, as_host: bool) -> void:
	_is_host_flag = as_host
	_my_id = 1
	multiplayer.multiplayer_peer = peer
	_active = true
	_ping_timer = 0.0
	if not _hooked:
		_hooked = true
		multiplayer.peer_connected.connect(func(id: int) -> void:
			if _active:
				peer_joined.emit(id))
		multiplayer.peer_disconnected.connect(func(id: int) -> void:
			if _active:
				peer_left.emit(id))
		multiplayer.connected_to_server.connect(func() -> void:
			if _active:
				connected_to_host.emit())
		multiplayer.connection_failed.connect(func() -> void:
			if _active:
				connection_failed.emit())
		multiplayer.server_disconnected.connect(func() -> void:
			if _active:
				host_lost.emit())


func _process(delta: float) -> void:
	_flush_queue()
	if _active and not multiplayer.is_server() and _is_connected():
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = _config.ping_interval
			var now_ms: int = Time.get_ticks_msec()
			_send(func() -> void: rpc_ping.rpc_id(1, now_ms), false, false)


func _is_connected() -> bool:
	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	return mp != null and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# Every send goes through here so fake lag / jitter / loss apply to all of it.
func _send(fn: Callable, reliable: bool, droppable: bool, to_peer: int = 0) -> void:
	if droppable and loss_pct > 0.0 and randf() * 100.0 < loss_pct:
		return
	var delay: float = lag_ms + (randf() * jitter_ms if jitter_ms > 0.0 else 0.0)
	if delay <= 0.0:
		_call_if_connected(fn, to_peer)
		return
	var at: int = Time.get_ticks_msec() + int(delay)
	if reliable:
		at = maxi(at, _last_reliable_at)
		_last_reliable_at = at
	_queue.append({"at": at, "fn": fn, "to": to_peer})


# Never calls an RPC while disconnected or towards a peer that is gone.
func _call_if_connected(fn: Callable, to_peer: int = 0) -> void:
	if not _active or not _is_connected():
		return
	if to_peer > 0 and not multiplayer.get_peers().has(to_peer):
		return
	fn.call()


func _flush_queue() -> void:
	if _queue.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var i: int = 0
	while i < _queue.size():
		if int(_queue[i].at) <= now:
			var fn: Callable = _queue[i].fn
			var to: int = _queue[i].to
			_queue.remove_at(i)
			_call_if_connected(fn, to)
		else:
			i += 1


@rpc("authority", "call_remote", "reliable")
func rpc_race_start(info: Dictionary) -> void:
	race_start_received.emit(info)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func rpc_state(kart_id: int, t: float, d: PackedFloat32Array) -> void:
	state_received.emit(kart_id, t, d)


@rpc("any_peer", "call_remote", "reliable")
func rpc_loadout(racer: int, vehicle: int) -> void:
	if multiplayer.is_server():
		loadout_received.emit(multiplayer.get_remote_sender_id(), racer, vehicle)


@rpc("any_peer", "call_remote", "reliable")
func rpc_bump(kart_id: int, from_kart: int, ix: float, iz: float, strength: float) -> void:
	bump_received.emit(kart_id, from_kart, Vector2(ix, iz), strength)


@rpc("any_peer", "call_remote", "reliable")
func rpc_box_take(box: int, kart_id: int, wants_item: bool) -> void:
	if multiplayer.is_server():
		box_take_received.emit(box, kart_id, wants_item)


@rpc("any_peer", "call_remote", "reliable")
func rpc_box_taken(box: int, kart_id: int, t: float, item: int) -> void:
	box_taken_received.emit(box, kart_id, t, item)


@rpc("any_peer", "call_remote", "reliable")
func rpc_item_spawn(seq: int, item: int, owner_id: int, t: float, px: float, pz: float,
		dx: float, dz: float, target: int) -> void:
	item_spawn_received.emit(seq, item, owner_id, t, Vector2(px, pz), Vector2(dx, dz), target)


@rpc("any_peer", "call_remote", "reliable")
func rpc_item_hit(seq: int, victim: int, blocked: bool, t: float) -> void:
	item_hit_received.emit(seq, victim, blocked, t)


@rpc("any_peer", "call_remote", "unreliable")
func rpc_ping(client_ms: int) -> void:
	var from: int = multiplayer.get_remote_sender_id()
	var host_t: float = float(race_clock.call()) if race_clock.is_valid() else 0.0
	var active: bool = bool(race_active.call()) if race_active.is_valid() else false
	_send(func() -> void: rpc_pong.rpc_id(from, client_ms, host_t, active), false, false, from)


@rpc("authority", "call_remote", "unreliable")
func rpc_pong(client_ms: int, host_race_time: float, host_active: bool) -> void:
	pong_received.emit(host_race_time, host_active, (Time.get_ticks_msec() - client_ms) / 1000.0)
