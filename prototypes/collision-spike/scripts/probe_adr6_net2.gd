## Scratch probe for ADR-0006 V2 under loss and V5 exact datagram sizes.
## PROTOTYPE - NOT FOR PRODUCTION. One process: host S on 127.0.0.1:24693, client C1 connects through
## an in-process UDP proxy (client side 24694, upstream socket 24695) that sees every datagram and
## can drop them (seeded). Both peers are wrapped in probe_adr6_wrap.gd so the RPC handler can read
## the real channel and mode of the packet being processed.
## Run: godot --headless --path prototypes/collision-spike -s res://scripts/probe_adr6_net2.gd
extends SceneTree

const OUT: String = "res://out/probe_adr6_net2.txt"
const LINK := preload("res://scripts/probe_adr6_link.gd")
const WRAP := preload("res://scripts/probe_adr6_wrap.gd")
const N_SEQ: int = 300

var _lines: PackedStringArray = []
var _api: Dictionary = {}
var _w: Dictionary = {}
var _link: Dictionary = {}
var _down := PacketPeerUDP.new()
var _up := PacketPeerUDP.new()
var _cip: String = ""
var _cport: int = 0
var _drop: float = 0.0
var _rng := RandomNumberGenerator.new()
var _prng := RandomNumberGenerator.new()
var _hist: Dictionary = {"c2s": {}, "s2c": {}}
var _dropped: Dictionary = {"c2s": 0, "s2c": 0}
var _record: bool = false
var _frame: int = 0
var _phase: int = 0
var _t0: int = 0
var _i: int = 0
var _cases: Array = []
var _trial: int = 0
var _t_send: int = 0
var _t_ev: int = -1
var _t_last_ctl: int = -1
var _hol: Array = []


func _p(s: String) -> void:
	print(s)
	_lines.append(s)


func _make(n: String, enet: ENetMultiplayerPeer) -> void:
	var holder := Node.new()
	holder.name = n
	root.add_child(holder)
	var link: Node = LINK.new()
	link.name = "Link"
	holder.add_child(link)
	var api := SceneMultiplayer.new()
	api.server_relay = false
	set_multiplayer(api, NodePath("/root/" + n))
	var w: MultiplayerPeerExtension = WRAP.new(enet)
	_api[n] = api
	_w[n] = w
	_link[n] = link
	api.multiplayer_peer = w


func _initialize() -> void:
	_p("engine %s" % Engine.get_version_info().string)
	_rng.seed = 2
	_prng.seed = 3
	_p("proxy bind down 24694: %s, up 24695: %s" % [error_string(_down.bind(24694, "127.0.0.1")),
			error_string(_up.bind(24695, "127.0.0.1"))])
	_up.set_dest_address("127.0.0.1", 24693)
	var sp := ENetMultiplayerPeer.new()
	_p("create_server(24693, 11): %s" % error_string(sp.create_server(24693, 11)))
	_make("S", sp)
	var cp := ENetMultiplayerPeer.new()
	_p("create_client(127.0.0.1, 24694 proxy): %s" % error_string(cp.create_client("127.0.0.1", 24694)))
	_make("C1", cp)


func _pump() -> void:
	while _down.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _down.get_packet()
		_cip = _down.get_packet_ip()
		_cport = _down.get_packet_port()
		if _record:
			_hist["c2s"][pkt.size()] = int(_hist["c2s"].get(pkt.size(), 0)) + 1
		if _drop > 0.0 and _prng.randf() < _drop:
			_dropped["c2s"] += 1
			continue
		_up.put_packet(pkt)
	while _up.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _up.get_packet()
		if _record:
			_hist["s2c"][pkt.size()] = int(_hist["s2c"].get(pkt.size(), 0)) + 1
		if _drop > 0.0 and _prng.randf() < _drop:
			_dropped["s2c"] += 1
			continue
		if _cport != 0:
			_down.set_dest_address(_cip, _cport)
			_down.put_packet(pkt)


func _rand(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	for i in n:
		b[i] = _rng.randi() & 0xFF
	return b


func _cid() -> int:
	return _api["C1"].get_unique_id()


func _now() -> int:
	return Time.get_ticks_usec()


func _go(p: int) -> void:
	_phase = p
	_t0 = _now()
	_i = 0


func _process(_d: float) -> bool:
	_frame += 1
	_pump()
	if _now() - _t0 > 60_000_000 and _phase > 0:
		_p("TIMEOUT in phase %d" % _phase)
		return _finish()
	match _phase:
		0:
			if _w["C1"].get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and _api["S"].get_peers().size() == 1:
				_p("connected, C1 id %d" % _cid())
				_cases = [["s2c", "snap_bytes", 43], ["s2c", "snap_bytes", 453], ["s2c", "send_bytes", 43],
						["s2c", "ev_bytes", 15], ["c2s", "snap_bytes", 43], ["c2s", "ev_bytes", 15]]
				_p("--- V5: exact UDP payload sizes seen by the proxy (add 28 B for IPv4+UDP headers). 100 sends per case, 20 ms apart, random payload")
				_go(1)
		1:
			_v5()
		2:
			_v2_send()
		3:
			if _v2_done() or _now() - _t0 > 30_000_000:
				_v2_report()
				_go(4)
		4:
			if _hol_step():
				return _finish()
	return false


func _v5() -> void:
	if _i == 0:
		_hist = {"c2s": {}, "s2c": {}}
		_record = true
	var c: Array = _cases[0]
	if _i < 100:
		if _now() - _t0 >= _i * 20000:
			var sender: String = "S" if c[0] == "s2c" else "C1"
			var to: int = _cid() if c[0] == "s2c" else 1
			var b: PackedByteArray = _rand(c[2])
			if c[1] == "snap_bytes":
				_link[sender].snap_bytes.rpc_id(to, b)
			elif c[1] == "ev_bytes":
				_link[sender].ev_bytes.rpc_id(to, b)
			else:
				_api[sender].send_bytes(b, to, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 1)
			_i += 1
		return
	if _now() - _t0 < 100 * 20000 + 200000:
		return
	_record = false
	_p("  %s %s payload %d: datagram sizes s2c %s ; c2s %s" % [c[0], c[1], c[2], _hist["s2c"], _hist["c2s"]])
	_cases.pop_front()
	_i = 0
	_t0 = _now()
	if _cases.is_empty():
		_p("  send log S: %s ; C1: %s (key transfer_channel/transfer_mode)" % [_w["S"].sends, _w["C1"].sends])
		_drop = 0.2
		for n: String in ["S", "C1"]:
			_link[n].got.clear()
		_p("--- V2 under loss: proxy drops 20%% of datagrams both ways (seed 3). %d per kind each way, 10 per frame, 2 ms apart" % N_SEQ)
		_go(2)


func _v2_send() -> void:
	if _now() - _t0 < (_i / 10) * 2000:
		return
	var small: PackedByteArray = _rand(15)
	var big: PackedByteArray = _rand(453)
	for k in 10:
		var i: int = _i
		_link["C1"].ev.rpc_id(1, i, small)
		_link["C1"].snap.rpc_id(1, i, big)
		_link["C1"].ctl.rpc_id(1, i, small)
		_link["C1"].ping.rpc_id(1, i)
		_link["S"].ev.rpc_id(_cid(), i, small)
		_link["S"].snap.rpc_id(_cid(), i, big)
		_link["S"].ctl.rpc_id(_cid(), i, small)
		_i += 1
	if _i >= N_SEQ:
		_phase = 3


func _v2_done() -> bool:
	for n: String in ["S", "C1"]:
		var g: Dictionary = _link[n].got
		if not g.has("ev") or g["ev"].size() < N_SEQ or not g.has("ctl") or g["ctl"].size() < N_SEQ:
			return false
	return true


func _summ(n: String, m: String) -> String:
	var g: Dictionary = _link[n].got
	if not g.has(m):
		return "%s.%s: none" % [n, m]
	var arr: Array = g[m]
	var in_order: bool = true
	var last: int = -1
	var chans: Dictionary = {}
	var modes: Dictionary = {}
	for r: Array in arr:
		if r[0] <= last:
			in_order = false
		last = r[0]
		chans[r[2]] = true
		modes[r[3]] = true
	return "%s.%s: received %d/%d, strictly increasing=%s, channel=%s, mode=%s (0 unreliable, 1 unreliable_ordered, 2 reliable)" % [
			n, m, arr.size(), N_SEQ, in_order, chans.keys(), modes.keys()]


func _v2_report() -> void:
	_p("  done after %.2f s; dropped by proxy c2s %d, s2c %d" % [(_now() - _t0) / 1e6, _dropped["c2s"], _dropped["s2c"]])
	for n: String in ["S", "C1"]:
		for m: String in ["ev", "snap", "ctl", "ping"]:
			_p("  " + _summ(n, m))
	_p("--- HOL: 20%% loss. Each trial: host sends 40 x 1000 B ctl (ch0 reliable) then 1 ev (ch2 reliable) in the same frame; times to C1 arrival")
	_trial = 0
	_t_send = 0


func _hol_step() -> bool:
	var g: Dictionary = _link["C1"].got
	if _t_send == 0:
		g.clear()
		_t_ev = -1
		_t_last_ctl = -1
		for k in 40:
			_link["S"].ctl.rpc_id(_cid(), k, _rand(1000))
		_link["S"].ev.rpc_id(_cid(), 999, _rand(15))
		_t_send = _now()
		return false
	if _t_ev < 0 and g.has("ev"):
		_t_ev = _now() - _t_send
	if _t_last_ctl < 0 and g.has("ctl") and g["ctl"].size() >= 40:
		_t_last_ctl = _now() - _t_send
	if (_t_ev >= 0 and _t_last_ctl >= 0) or _now() - _t_send > 15_000_000:
		_p("  trial %d: ev (ch2) arrived %.1f ms, 40th ctl (ch0) arrived %.1f ms; ev arrived after ctl #%d" % [
				_trial, _t_ev / 1000.0, _t_last_ctl / 1000.0, _ctl_before_ev(g)])
		_trial += 1
		_t_send = 0
		if _trial >= 6:
			return true
	return false


func _ctl_before_ev(g: Dictionary) -> int:
	if not g.has("ev"):
		return -1
	var ev_idx: int = g["ev"][0][4]
	var n: int = 0
	if g.has("ctl"):
		for r: Array in g["ctl"]:
			if r[4] < ev_idx:
				n += 1
	return n


func _finish() -> bool:
	_w["C1"].close()
	_w["S"].close()
	_down.close()
	_up.close()
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	return true
