## PROTOTYPE - NOT FOR PRODUCTION. RPC endpoint for probe_adr6_net.gd (ADR-0006 V2, V3, V5).
extends Node

var tag: String = ""
## method -> Array of [seq, sender, packet_channel, packet_mode]
var got: Dictionary = {}
var arrivals: int = 0


func _note(method: String, seq: int) -> void:
	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	if not got.has(method):
		got[method] = []
	got[method].append([seq, multiplayer.get_remote_sender_id(), mp.get_packet_channel(), mp.get_packet_mode(), arrivals])
	arrivals += 1


@rpc("any_peer", "call_remote", "reliable", 2)
func ev(seq: int, _b: PackedByteArray) -> void:
	_note("ev", seq)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func snap(seq: int, _b: PackedByteArray) -> void:
	_note("snap", seq)


@rpc("any_peer", "call_remote", "reliable")
func ctl(seq: int, _b: PackedByteArray) -> void:
	_note("ctl", seq)


@rpc("any_peer", "call_remote", "unreliable")
func ping(seq: int) -> void:
	_note("ping", seq)


@rpc("any_peer", "call_remote", "reliable")
func direct(seq: int) -> void:
	_note("direct", seq)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func snap_bytes(_b: PackedByteArray) -> void:
	_note("snap_bytes", 0)


@rpc("any_peer", "call_remote", "reliable", 2)
func ev_bytes(_b: PackedByteArray) -> void:
	_note("ev_bytes", 0)
