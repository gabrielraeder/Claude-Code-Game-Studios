## PROTOTYPE - NOT FOR PRODUCTION. Pass-through MultiplayerPeerExtension around ENetMultiplayerPeer
## that remembers the channel and mode of the packet SceneMultiplayer is processing (ADR-0006 V2),
## and logs the channel and mode SceneMultiplayer asks for on each send.
extends MultiplayerPeerExtension

var inner: ENetMultiplayerPeer
var last_ch: int = -1
var last_mode: int = -1
var sends: Dictionary = {}  # "ch/mode" -> count


func _init(p: ENetMultiplayerPeer) -> void:
	inner = p
	inner.peer_connected.connect(func(id: int) -> void: peer_connected.emit(id))
	inner.peer_disconnected.connect(func(id: int) -> void: peer_disconnected.emit(id))


func _get_available_packet_count() -> int:
	return inner.get_available_packet_count()


func _get_max_packet_size() -> int:
	return 1 << 24


func _get_packet_script() -> PackedByteArray:
	last_ch = inner.get_packet_channel()
	last_mode = inner.get_packet_mode()
	return inner.get_packet()


func _put_packet_script(b: PackedByteArray) -> Error:
	var k: String = "%d/%d" % [inner.transfer_channel, inner.transfer_mode]
	sends[k] = int(sends.get(k, 0)) + 1
	return inner.put_packet(b)


func _get_packet_channel() -> int:
	return last_ch


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return last_mode as MultiplayerPeer.TransferMode


func _set_transfer_channel(c: int) -> void:
	inner.transfer_channel = c


func _get_transfer_channel() -> int:
	return inner.transfer_channel


func _set_transfer_mode(m: MultiplayerPeer.TransferMode) -> void:
	inner.transfer_mode = m


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return inner.transfer_mode


func _set_target_peer(p: int) -> void:
	inner.set_target_peer(p)


func _get_packet_peer() -> int:
	return inner.get_packet_peer()


func _is_server() -> bool:
	return inner.get_unique_id() == 1


func _poll() -> void:
	inner.poll()


func _close() -> void:
	inner.close()


func _disconnect_peer(p: int, force: bool) -> void:
	inner.disconnect_peer(p, force)


func _get_unique_id() -> int:
	return inner.get_unique_id()


func _set_refuse_new_connections(e: bool) -> void:
	inner.refuse_new_connections = e


func _is_refusing_new_connections() -> bool:
	return inner.refuse_new_connections


func _is_server_relay_supported() -> bool:
	return inner.is_server_relay_supported()


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return inner.get_connection_status()
