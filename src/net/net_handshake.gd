class_name NetHandshake
extends RefCounted
## The version handshake packet (KartWire.VERSION 8). It travels through SceneMultiplayer
## authentication (send_auth) before any RPC, so two builds with different RPC sets never
## exchange an RPC. Layout: 4 ASCII bytes of magic (the game id) followed by the sender's
## protocol version as a little-endian signed 32-bit integer. Longer packets are accepted,
## so later versions may append fields. The host answers with the same packet carrying its
## own version and completes the handshake only when the two versions match.

## Identifies this game, so another program talking to the port is refused as well.
const MAGIC: String = "DWKR"
## Bytes of a version 8 packet (magic + version).
const SIZE: int = 8


## Builds the handshake packet carrying [param version].
static func encode(version: int) -> PackedByteArray:
	var out: PackedByteArray = MAGIC.to_ascii_buffer()
	out.resize(SIZE)
	out.encode_s32(MAGIC.length(), version)
	return out


## Returns the version carried by [param data], or -1 when it is not a handshake packet of
## this game (too short or wrong magic).
static func decode(data: PackedByteArray) -> int:
	if data.size() < SIZE:
		return -1
	if data.slice(0, MAGIC.length()).get_string_from_ascii() != MAGIC:
		return -1
	return data.decode_s32(MAGIC.length())
