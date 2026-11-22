## Scratch probe for ADR-0006 V2 (channel 2 reliable beside channel 1 unreliable_ordered),
## V3 (server_relay = false) and V5 (per-packet overhead).
## PROTOTYPE - NOT FOR PRODUCTION. One process, three SceneMultiplayer instances on 127.0.0.1:24690
## (host /root/S, clients /root/C1 and /root/C2), each with a child "Link" so RPC paths match.
## Run: godot --headless --path prototypes/collision-spike -s res://scripts/probe_adr6_net.gd
extends SceneTree

const OUT: String = "res://out/probe_adr6_net.txt"
const PORT: int = 24690
const LINK := preload("res://scripts/probe_adr6_link.gd")
const N_SEQ: int = 300

var _lines: PackedStringArray = []
var _api: Dictionary = {}    # name -> SceneMultiplayer
var _peer: Dictionary = {}   # name -> ENetMultiplayerPeer
var _link: Dictionary = {}   # name -> Link node
var _events: Dictionary = {"S": [], "C1": [], "C2": []}
var _frame: int = 0
var _phase: int = 0
var _phase_start: int = 0
var _sent: int = 0
var _v5_cases: Array = []
var _v5_i: int = 0
var _v5_warm: int = 0
var _v5_random: bool = true
var _rng := RandomNumberGenerator.new()


func _p(s: String) -> void:
	print(s)
	_lines.append(s)


func _make(name_: String) -> void:
	var holder := Node.new()
	holder.name = name_
	root.add_child(holder)
	var link: Node = LINK.new()
	link.name = "Link"
	link.tag = name_
	holder.add_child(link)
	var api := SceneMultiplayer.new()
	api.server_relay = false
	set_multiplayer(api, NodePath("/root/" + name_))
	_api[name_] = api
	_link[name_] = link
	api.peer_connected.connect(func(id: int) -> void: _events[name_].append("peer_connected %d" % id))
	api.peer_disconnected.connect(func(id: int) -> void: _events[name_].append("peer_disconnected %d" % id))
	api.connected_to_server.connect(func() -> void: _events[name_].append("connected_to_server"))
	api.connection_failed.connect(func() -> void: _events[name_].append("connection_failed"))


func _initialize() -> void:
	_p("engine %s" % Engine.get_version_info().string)
	for n: String in ["S", "C1", "C2"]:
		_make(n)
	var sp := ENetMultiplayerPeer.new()
	var err: Error = sp.create_server(PORT, 11)  # as the frozen NetSession: create_server(port, max_racers - 1)
	_p("create_server(%d, 11) -> %s" % [PORT, error_string(err)])
	_peer["S"] = sp
	_api["S"].multiplayer_peer = sp
	for n: String in ["C1", "C2"]:
		var cp := ENetMultiplayerPeer.new()
		err = cp.create_client("127.0.0.1", PORT)  # as the frozen NetSession: two arguments only
		_p("%s create_client(127.0.0.1, %d) -> %s" % [n, PORT, error_string(err)])
		_peer[n] = cp
		_api[n].multiplayer_peer = cp


func _id(n: String) -> int:
	return _api[n].get_unique_id()


func _next(p: int) -> void:
	_phase = p
	_phase_start = _frame
	_sent = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > 20000:
		_p("TIMEOUT in phase %d" % _phase)
		return _finish()
	match _phase:
		0:
			var ok: bool = _peer["C1"].get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
					and _peer["C2"].get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
					and _api["S"].get_peers().size() == 2
			if ok:
				_p("connected after %d frames: S=%d C1=%d C2=%d" % [_frame, _id("S"), _id("C1"), _id("C2")])
				_report_channels()
				_next(1)
		1:
			_v2_send()
		2:
			if _v2_done() or _frame - _phase_start > 3000:
				_v2_report()
				_next(3)
		3:
			_v3_send()
			_next(4)
		4:
			if _frame - _phase_start > 120:
				_v3_report()
				_v5_setup()
				_next(5)
		5:
			if _v5_step():
				return _finish()
	return false


func _report_channels() -> void:
	_p("--- ENet channel counts (ENetPacketPeer.get_channels)")
	var sh: ENetConnection = _peer["S"].host
	for pid: int in _api["S"].get_peers():
		_p("  host side peer %d: %d channels" % [pid, _peer["S"].get_peer(pid).get_channels()])
	for n: String in ["C1", "C2"]:
		_p("  %s side, peer 1 (host): %d channels" % [n, _peer[n].get_peer(1).get_channels()])
	_p("  host ENetConnection max channels: %s" % (str(sh.get_max_channels()) if sh.has_method("get_max_channels") else "n/a"))
	_p("  peers visible to C1 (relay off): %s ; to C2: %s" % [_api["C1"].get_peers(), _api["C2"].get_peers()])


# V2: both directions, interleave ch2 reliable, ch1 unreliable_ordered (large), ch0 reliable,
# ch0 unreliable; 10 of each per frame for 30 frames.
func _v2_send() -> void:
	var small := PackedByteArray()
	small.resize(15)
	var big := PackedByteArray()
	big.resize(453)
	var lc: Node = _link["C1"]
	var ls: Node = _link["S"]
	for k in 10:
		var i: int = _sent
		lc.ev.rpc_id(1, i, small)
		lc.snap.rpc_id(1, i, big)
		lc.ctl.rpc_id(1, i, small)
		lc.ping.rpc_id(1, i)
		ls.ev.rpc_id(_id("C1"), i, small)
		ls.snap.rpc_id(_id("C1"), i, big)
		ls.ctl.rpc_id(_id("C1"), i, small)
		_sent += 1
	if _sent >= N_SEQ:
		_next(2)


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
	var senders: Dictionary = {}
	for r: Array in arr:
		if r[0] <= last:
			in_order = false
		last = r[0]
		chans[r[2]] = true
		modes[r[3]] = true
		senders[r[1]] = true
	return "%s.%s: received %d, strictly increasing=%s, packet_channel=%s, packet_mode=%s (0 unrel,1 unrel_ord,2 rel), senders=%s" % [
			n, m, arr.size(), in_order, chans.keys(), modes.keys(), senders.keys()]


func _v2_report() -> void:
	_p("--- V2 (%d per kind each way, 10 per frame; frames %d..%d)" % [N_SEQ, _phase_start, _frame])
	for n: String in ["S", "C1"]:
		for m: String in ["ev", "snap", "ctl", "ping"]:
			_p("  " + _summ(n, m))
	for n: String in ["S", "C1"]:
		_link[n].got.clear()


# V3: relay off. C1 -> C2 direct, C1 broadcast, C1 -> host, host -> C2, host broadcast.
func _v3_send() -> void:
	_p("--- V3 send: C1 rpc_id(C2=%d, 1), C1 rpc(2) broadcast, C1 rpc_id(1, 3), S rpc_id(C2, 4), S rpc(5) broadcast" % _id("C2"))
	var lc: Node = _link["C1"]
	lc.direct.rpc_id(_id("C2"), 1)
	lc.direct.rpc(2)
	lc.direct.rpc_id(1, 3)
	_link["S"].direct.rpc_id(_id("C2"), 4)
	_link["S"].direct.rpc(5)


func _v3_report() -> void:
	_p("--- V3 results (after 120 frames)")
	for n: String in ["S", "C1", "C2"]:
		var g: Dictionary = _link[n].got
		var recv: Array = []
		if g.has("direct"):
			for r: Array in g["direct"]:
				recv.append("seq %d from %d" % [r[0], r[1]])
		_p("  %s got: %s" % [n, recv])
	for n: String in ["S", "C1", "C2"]:
		_p("  %s multiplayer events: %s" % [n, _events[n]])


func _v5_setup() -> void:
	# method, payload size; host -> C1 only, one send per frame.
	_rng.seed = 5
	_v5_cases = [["idle", 0], ["snap_bytes", 43], ["snap_bytes", 453], ["send_bytes", 43], ["send_bytes", 453],
			["ev_bytes", 15], ["ev_bytes", 453], ["zeros", 0], ["snap_bytes", 453]]
	_v5_i = 0
	_v5_warm = 0
	_p("--- V5: host -> C1, 1 send per frame, 300 frames per case, after 20 warm-up sends; random payload bytes (seed 5) unless after the zeros marker; stats from ENetConnection.pop_statistic (ENet bytes, UDP/IP headers excluded)")


func _v5_send(m: String, size: int) -> void:
	if m == "idle":
		return
	if m == "zeros":
		_v5_random = false  # following cases use all-zero payloads (compressibility check)
		return
	var b := PackedByteArray()
	b.resize(size)
	if _v5_random:
		for i in size:
			b[i] = _rng.randi() & 0xFF
	if m == "snap_bytes":
		_link["S"].snap_bytes.rpc_id(_id("C1"), b)
	elif m == "ev_bytes":
		_link["S"].ev_bytes.rpc_id(_id("C1"), b)
	else:
		_api["S"].send_bytes(b, _id("C1"), MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 1)


func _v5_step() -> bool:
	if _v5_i >= _v5_cases.size():
		return true
	var c: Array = _v5_cases[_v5_i]
	var sh: ENetConnection = _peer["S"].host
	var ch: ENetConnection = _peer["C1"].host
	if _v5_warm < 20:
		_v5_send(c[0], c[1])
		_v5_warm += 1
		if _v5_warm == 20:
			# flush counters at the start of the measured window
			for st: int in [ENetConnection.HOST_TOTAL_SENT_DATA, ENetConnection.HOST_TOTAL_SENT_PACKETS,
					ENetConnection.HOST_TOTAL_RECEIVED_DATA, ENetConnection.HOST_TOTAL_RECEIVED_PACKETS]:
				sh.pop_statistic(st)
				ch.pop_statistic(st)
			_phase_start = _frame
		return false
	if _frame - _phase_start < 300:
		_v5_send(c[0], c[1])
		return false
	if _frame - _phase_start < 310:
		return false  # let the last ones land
	var sd: float = sh.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var spk: float = sh.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
	var crd: float = ch.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	var crp: float = ch.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)
	var csd: float = ch.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var csp: float = ch.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
	var per: String = "n/a"
	if spk > 0 and c[1] > 0:
		per = "%.2f" % (sd / spk - c[1])
	_p("  %-10s payload %3d B: host sent %d B in %d datagrams (%.2f B/datagram, overhead/datagram %s); C1 received %d B in %d; C1 sent %d B in %d (acks/pings)" % [
			c[0], c[1], sd, spk, (sd / spk if spk > 0 else 0.0), per, crd, crp, csd, csp])
	var g: Dictionary = _link["C1"].got
	var counts: Dictionary = {}
	for k: String in g:
		counts[k] = g[k].size()
	_p("    C1 handler calls so far: %s" % counts)
	_v5_i += 1
	_v5_warm = 0
	return false


func _finish() -> bool:
	for n: String in ["C1", "C2", "S"]:
		_peer[n].close()
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	return true
