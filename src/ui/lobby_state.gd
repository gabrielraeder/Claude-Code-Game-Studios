class_name LobbyState
extends RefCounted
## What the lobby shows, owned by the host and sent to every client: who is connected with
## which racer and vehicle, and the host's race setup. Plain data; [method to_dict] and
## [method from_dict] are the wire form (reliable RPC, KartWire.VERSION 6).

## The lobby (the only phase sent for now; a race start is its own message).
const PHASE_LOBBY: String = "lobby"
## Peer id of the host.
const HOST_PEER: int = 1

## Protocol version of the sender (a mismatch makes the client leave).
var version: int = 0
var track: String = ""
var bots: int = 0
var laps: int = 3
## One entry per human, host first, then clients by peer id: {peer, racer, vehicle, ready}.
var entries: Array[Dictionary] = []


## Number of humans in the lobby.
func humans() -> int:
	return entries.size()


## Most bots allowed with this many humans ([param max_racers] is the race total).
func max_bots(max_racers: int) -> int:
	return maxi(max_racers - entries.size(), 0)


## Index of the entry of [param peer] (also its slot and kart id), -1 if absent.
func index_of_peer(peer: int) -> int:
	for i in entries.size():
		if int(entries[i].peer) == peer:
			return i
	return -1


## True when every client (not the host) is ready.
func all_ready() -> bool:
	for e in entries:
		if int(e.peer) != HOST_PEER and not bool(e.ready):
			return false
	return true


## Clients that are not ready yet.
func waiting_count() -> int:
	var n: int = 0
	for e in entries:
		if int(e.peer) != HOST_PEER and not bool(e.ready):
			n += 1
	return n


## Wire form.
func to_dict() -> Dictionary:
	return {"version": version, "phase": PHASE_LOBBY, "track": track, "bots": bots, "laps": laps,
			"entries": entries.duplicate(true)}


## Reads the wire form; missing or odd values become safe defaults.
static func from_dict(d: Dictionary) -> LobbyState:
	var s := LobbyState.new()
	s.version = int(d.get("version", -1))
	s.track = str(d.get("track", ""))
	s.bots = maxi(int(d.get("bots", 0)), 0)
	s.laps = maxi(int(d.get("laps", 3)), 1)
	var raw: Variant = d.get("entries", [])
	if raw is Array:
		for e: Variant in raw as Array:
			if e is Dictionary:
				var ed: Dictionary = e
				s.entries.append({"peer": int(ed.get("peer", 0)), "racer": int(ed.get("racer", 0)),
						"vehicle": int(ed.get("vehicle", 0)), "ready": bool(ed.get("ready", false))})
	return s


## An entry dictionary.
static func make_entry(peer: int, racer: int, vehicle: int, ready: bool) -> Dictionary:
	return {"peer": peer, "racer": racer, "vehicle": vehicle, "ready": ready}
