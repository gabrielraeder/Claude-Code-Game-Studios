# ADR-0006: Network Snapshot for 3D

## Status
Accepted (owner, 2026-11-22)

## Date
2026-11-22

## Last Verified
2026-11-22. v2 checks this ADR against ADR-0003 v4 and the godot-specialist probes on 4.8-beta3 (V1, V2, V3 and V5 verified; V4 still open).

## Decision Makers
- **v1:** drafted by Claude (network-programmer subagent).
- **v2:** revised by the same agent, applying two reviews:
  - **TD-ADR v1 (CONCERNS):** ownership per event kind, the view delay over two hops, the semantics of the remote `events` byte, OQ-5, the stale-bump drop, contact eligibility, and small fixes;
  - **godot-specialist probes** on 4.8-beta3: `prototypes/collision-spike/out/probe_adr6_codec.txt`, `probe_adr6_net.txt` and `probe_adr6_net2.txt`.
- **Decided provisionally (coordinator, v2):** OQ-1, OQ-2 and OQ-7 still need the owner's decision. OQ-4 is to be revisited before room codes (ADR-0008) open play to strangers.
- **Acceptance** needs the owner's confirmation.

## Summary
The rebuilt 3D core needs a wire format, an event channel, a handshake and a clock. They replace the frozen 2.5D `KartWire` VERSION 9, which sends 21 planar float32s per kart.

This ADR fixes protocol **VERSION 10**:
- a quantised 41-byte per-kart record, batched by the host;
- reliable gameplay events on their own channel, with an ownership check per event kind;
- a race config carrying track identity, mirror flag and seed, refused on a mismatch;
- an NTP-style clock with a min-RTT filter and slew, which sets the target tick;
- a `RemoteKartView` that interpolates, caps extrapolation by time, and snaps on a teleport epoch that survives packet loss. It reports events once per consumer.

`NetMetrics` leaves teleports out of the prediction error, which closes TD-010.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.8-beta3 |
| **Domain** | Networking |
| **Layer** | Foundation (Network Session & Sync, `architecture.md` System Layer Map) |
| **Knowledge Risk** | HIGH (4.8 is post-cutoff and pre-release) |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; `docs/engine-reference/godot/modules/networking.md` (lists no 4.5-4.8 networking changes, and marks 4.8 NOT SOURCEABLE); probe evidence `prototypes/collision-spike/out/probe_adr6_codec.txt`, `probe_adr6_net.txt`, `probe_adr6_net2.txt` (godot-specialist, 4.8-beta3, 2026-11-22); the frozen `src/legacy/net/*.gd` as the working reference |
| **Post-Cutoff APIs Used** | None. These pre-cutoff APIs were checked on 4.8-beta3:<br>- `SceneMultiplayer` auth (`auth_callback`, `send_auth`, `complete_auth`);<br>- `SceneMultiplayer.server_relay`;<br>- `@rpc(..., transfer_channel)`;<br>- `ENetMultiplayerPeer`;<br>- `PackedByteArray.encode_u8/u16/u32/s64/half/float/double` and `decode_*`;<br>- `Time.get_ticks_usec()` |
| **Verified on 4.8-beta3** | **V1 codec:**<br>- `encode_half` **truncates toward zero**, and overflow above 65519 gives inf. The pre-round fix in §2 restores the stated bounds; subnormals flush to 0.<br>- The u24 position via u16 + u8 has a measured max error of 1.22×10⁻⁴ m. There is no `encode_u24`.<br>- The quaternion's measured max error is 0.268° against a 0.275° bound.<br>**V2:** ENet negotiates 255 channels with the frozen `create_server`/`create_client` calls. Channel 2 reliable arrives in order at 20% loss, and a channel-0 burst does not block channel 2 on the receive side.<br>**V3:** with `server_relay = false`, clients see only peer 1, and a client's `rpc()` reaches the host only. `rpc_id(other_client)` is a local error.<br>**V5:**<br>- RPC header: 13 B per datagram (11 B for `send_bytes`);<br>- 41 B per datagram including IPv4/UDP, about 61 B on IPv6;<br>- 38 B on-wire ACK per reliable event.<br>**Engine trap found:** `get_packet_channel()` / `get_packet_mode()` called inside an RPC handler describe the **next** queued packet and error when the queue is empty. They are forbidden for metrics (§9) |
| **Verification Required** | **V4 (open):** a v9 frozen host refuses a v10 client cleanly, and the reverse. Both builds run from HEAD; it needs the two real games, so it was not probed |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | **ADR-0001** (Accepted): §5 clock and target tick, §6 determinism and race seed, §7 mirror frame on the wire, §8 interpolation, teleport flag, canonical quaternion, capped extrapolation, §9 class names.<br>**ADR-0003 v4** (must be Accepted): `KartSnapshot` with `throttle`, `KartEvent`, the pinned §8 event-bit table, the `contact_eligible` mask, the stale-bump drop via `last_teleport_tick`, and the remote broadphase on distance sampled at the tick.<br>**ADR-0004** (must be Accepted): wire meaning of `lap` and `distance`; finish ordering.<br>**ADR-0005** (must be Accepted): `TrackPackage.source_sha256` and `bake_key`.<br>**ADR-0002 v5** (must be Accepted): `surface_id` on the wire is ADR-0002's stable registry id (u8, ids ≤ 255) |
| **Enables** | **ADR-0008** room codes and relay. It inherits this ADR's network-side contract: one UDP port, ENet, 30 Hz, the bandwidth figures.<br>**ADR-0010** time-trial ghost format. Ghosts record snapshot streams (Data Flow 3), and the per-packet version byte lets a stored stream be decoded |
| **Blocks** | Story 025's network sub-story (Castle Circuit online with bots, checkpoint **A2**) |
| **Ordering Note** | `NetConfig` (`src/data/`) gains fields **additively** only (ADR-0001 §9), including `contact_extrapolation_max`, which ADR-0003 v4 names. The frozen `assets/data/net/net_config.tres` is never read by new code; the new core reads `assets/data/core/net_config.tres`. ADR-0005 v3 hashes LF-normalised text inputs into `bake_key`, which removes the line-ending risk of §6 |

## Context

### Problem Statement
The frozen game's `KartWire` VERSION 9 sends one RPC per kart, relayed by the host (`server_relay`). Each RPC carries an int kart id, a float race time and a `PackedFloat32Array` of 21 fields:
- planar `x, z` and a scalar `yaw`;
- a separate `height` and `vy`;
- lap and finish data.

The rebuilt core has 3D state that does not fit:
- an orientation `Basis` (ADR-0001 §3);
- total world velocity (ADR-0003 §7);
- a signed race distance (ADR-0004 §5);
- teleports that must not count as prediction error. Under TD-010, the frozen `NetStats` counts a moat respawn as a huge error.

Checkpoint A2 (Castle Circuit online with bots) cannot be reached without:
- a wire format and an event set;
- a track-identity check;
- the clock rule that ADR-0001 §5 delegates here.

### Constraints
- **Owner-authoritative** (architecture Data Flow 3). Each PC simulates its own kart, and the host simulates all bots and decides shared events. Remote karts are interpolated, never simulated. There is no cross-machine determinism (ADR-0001 §6), so lockstep and rollback are out.
- **Up to 12 racers** (`NetConfig.max_racers`), any mix of humans and host bots. Players are friends on home connections.
- **±2 km geometry bound** (ADR-0001 §1). `Vector3` and `Quaternion` are float32.
- **Frozen game:** VERSION 9 keeps running from HEAD until A3. The two games never play together, and the handshake must refuse cleanly both ways.
- **No autoloads; dependency injection.** Only the RPC endpoint may be a `Node`. Codecs, clock and views are `RefCounted` and unit-testable.
- **Latency design point** (OQ-7, provisional, owner decision):
  - **150 ms RTT, 30 ms jitter, 5% loss** per client↔host link;
  - a **degraded-but-playable band up to about 250 ms RTT**.

  Client-owned karts reach other clients over **two hops**, about RTT + host hold.

### Requirements
- One snapshot record per kart, bounded in size, under one MTU for 12 karts.
- Quantisation error bounds stated and unit-tested.
- Reliable events for bump impulse, item hit, hazard hit result and finish (with race time), on a channel that lobby traffic cannot stall on the receive side.
- A handshake that refuses a different protocol version, and a race config that refuses a different track build, mirror state or seed.
- A clock that every PC turns into the same target tick (ADR-0001 §5), and a defined start tick.
- Remote interpolation in 3D with time-capped extrapolation, and a teleport snap and event report that survive packet loss and fire once per consumer.
- `NetMetrics` that excludes teleports from prediction error.
- Every sync parameter in `NetConfig`, none in code.

## Decision

### 1. Protocol version and coexistence
- **Version.** `SnapshotCodec.VERSION = 10` is the single protocol version for the whole RPC set, as `KartWire.VERSION` was. Bump it when any message layout or meaning changes, or when the RPC set changes. That includes renumbering any of the ADR-0003 v4 §8 event bits 0-7.
- **Auth handshake (`HandshakeCodec`).** It keeps the frozen 8-byte layout: 4 ASCII bytes `DWKR`, then the version as an s32 LE. Longer packets stay accepted, so later versions may append.
  - The host answers with its own version and calls `complete_auth` only on an exact match.
  - On a mismatch it answers, then drops the peer once the answer is delivered (the frozen `_refuse` pattern).
- **Coexistence.** There is **no interop, by design** (architecture API Boundaries). Both games may use the same port; the refusal is the guard. V4 is still to be run.
  - A v9 frozen host reads `10`, logs "it runs version 10, this host 9" and refuses.
  - A v10 host refuses a v9 client the same way.
  - A v10 client facing a v9 host gets `handshake_failed(9)` and shows "different game version".
- **Per-packet version byte.** Every snapshot packet starts with `VERSION & 0xFF`.
  - After the handshake it can only differ through a bug: the packet is dropped and an anomaly is logged.
  - It exists so stored snapshot streams (ghosts, ADR-0010; traces) are self-describing.

### 2. Snapshot record (VERSION 10)

There is one record per kart: **41 bytes**, little-endian. `SnapshotCodec` writes it from a `KartSnapshot` plus the kart's lap (from `CourseProgress`, ADR-0004 §4). It is the only place a snapshot is serialised (architecture API Boundaries).

| Off | Field | Type | Encoding | Source |
|---|---|---|---|---|
| 0 | `slot` | u8 | `RacerRegistry` slot | registry |
| 1 | `tick` | u32 | sender's sim tick of this snapshot; time = `tick × SIM_DT` race time | `KartSnapshot.tick` |
| 5 | `flags` | u8 | bit0 grounded, bit1 sinking, bit2 hop_airborne, bit3 position_clamped, bit4 reserved (0), **bits 5-7 teleport epoch** (mod 8, §5) | snapshot + sender accumulators |
| 6 | `pos.x`, `pos.y`, `pos.z` | 3 × u24 (each `encode_u16` low + `encode_u8` high) | `q = clamp(roundi((p + 2048) × 4096), 0, 2²⁴−1)`; `p = q / 4096 − 2048` | `position` |
| 15 | `rot` | u32 | smallest-three quaternion: bits 30-31 hold the index of the dropped largest component; three 10-bit fields hold the others in index order, each mapping [−1/√2, +1/√2] to [0, 1023] | `basis` → `Quaternion` |
| 19 | `vel.x`, `vel.y`, `vel.z` | 3 × f16 | **pre-rounded half** (below) | `velocity` (**total world velocity**, ADR-0003 §7) |
| 25 | `speed` | f16 | pre-rounded half, signed (reverse) | `speed` |
| 27 | `drift_state` | u8 | the `DriveState` drift int, packing drifting, direction and tier 0-3. **Driving & Drift owns the packing** (`design/gdd/driving-and-drift.md` §3.3 item 7, §6). The codec asserts 0-255 | `drift_state` |
| 28 | `boost` | u16 | remaining seconds × 1000, clamped 0-65535. Data max is 2.0 s (`start_boost_times[3]`, `driving-and-drift.md` §3.2) | `boost` |
| 30 | `spin` | u16 | remaining seconds × 1000, clamped 0-65535. Data max is 1.25 s (`spin_time`, `driving-and-drift.md` §3.2) | `spin` |
| 32 | `steer` | s8 | `roundi(clamp(v, −1, 1) × 127)` | `steer` |
| 33 | `throttle` | s8 | as `steer`. It is `throttle − brake` in [−1, 1] (ADR-0003 v4; it replaces v1's `accel`) | `throttle` |
| 34 | `surface_id` | u8 | asserted 0-255 (remote dust, splash and audio) | `surface_id` |
| 35 | `events` | u8 | OR of the low 8 bits of `KartSnapshot.events` over all ticks since the previous send. **Bit meanings are ADR-0003 v4 §8's pinned table** (0 `EV_TOOK_OFF`, 1 `EV_LANDED`, 2 `EV_WALL_TOUCH`, 3 `EV_WALL_IMPACT`, 4 `EV_BUMPED`, 5 `EV_TELEPORTED`, 6 `EV_HOP_AIRBORNE`, 7 reserved = 0). Renumbering bumps VERSION. Cosmetic: the byte may be lost with a packet. Teleport detection uses the epoch, never bit 5 | sender accumulator |
| 36 | `lap` | u8 | `CourseProgress.lap`, clamped 0-255 | Lap & Position input |
| 37 | `distance` | f32 | signed race distance, negative on the grid, continuous across laps (ADR-0004 §5) | `distance` |

**Not on the wire:** `support_id`, `air_time`, `moved`, `land_airtime`, `land_impact`, `wall_angle` and `bump_strength`. The decoder sets them to 0 (`support_id` to −1).

Finish is **not** in the snapshot. Unlike VERSION 9's `FINISHED` / `FINISH_TIME`, it is a reliable event (§4).

**f16 encoding (V1 fix, tested in `probe_adr6_codec.txt`).** `encode_half` truncates toward zero, which doubles the error and biases it. Each f16 field is therefore encoded in three steps:
1. `v = clampf(v, −65504.0, 65504.0)`. This prevents the inf above 65519, which the decoder would reject as non-finite, dropping the record.
2. Take the float32 bits `b` of `v` and pre-round them to nearest-even on the 13 dropped mantissa bits: `b = b + 0x0FFF + ((b >> 13) & 1)`.
3. `encode_half` of the float with those bits.

Subnormals (|v| < 6.1×10⁻⁵) flush to 0, which is harmless for these fields.

**Quaternion canonical sign (ADR-0001 §8).**
- **Encoder:** it takes the quaternion from the just-orthonormalised basis and canonicalises it to w ≥ 0. For smallest-three, it then negates the whole quaternion if the dropped component is negative; that is the same rotation.
- **Decoder:** it reconstructs the dropped component as `sqrt(max(0, 1 − a² − b² − c²))`, normalises, and **re-canonicalises to w ≥ 0**, so every decoded quaternion obeys ADR-0001 §8. It then builds `Basis(q)`.

**Packet:** `[VERSION u8][count u8][count × 41-byte records]`. 12 records come to 494 B, under one 1200 B safe MTU, so there is never fragmentation.

### 3. Quantisation error bounds

| Field | Step | Max error | Against the ±2 km bound, and use |
|---|---|---|---|
| position (u24, range [−2048, +2048) m) | 2⁻¹² m = 0.244 mm | **0.122 mm** per axis (measured 1.22×10⁻⁴ m) | Covers ±2000 m with 48 m spare. The wire step is twice float32's spacing of 2⁻¹³ near 2 km, so the max error equals one float32 ulp there. Out of range: clamp, set `position_clamped` and log an anomaly. This cannot happen on a valid track: import enforces ±2 km, and fall-respawn fires long before |
| orientation (smallest-three, 10 bits) | √2/1023 ≈ 1.38×10⁻³ per component | 2·asin(√12·e) with e = 6.9×10⁻⁴: **≈ 0.275°** (measured 0.268°); the test asserts < 0.28° | ≈ 4.8 mm at a 1 m half-length (the contact segment, ADR-0003 §7) |
| velocity, speed (pre-rounded f16) | relative 2⁻¹⁰ | ≤ 0.0156 m/s below 64 m/s, ≤ 0.031 m/s up to 128 m/s (measured with the fix; unbiased) | Over the 0.25 s extrapolation cap: ≤ 8 mm. Clamped to ±65504 |
| boost, spin (u16 ms) | 1 ms | 0.5 ms; saturates at 65.535 s | the data maxima are 2.0 s and 1.25 s |
| steer, throttle (snorm8) | 1/127 | 0.0039 | audio and visuals only |
| distance (f32) | 2⁻⁹ m at 16 km | ≈ 1 mm at 16 km | the resolution ADR-0004 §5 states |
| tick (u32) | exact | — | wraps after 2.27 years at 60 Hz |

### 4. Reliable events and ownership

**Channel plan.** Everything goes through `NetLink` with `SceneMultiplayer.server_relay = false`.

V3 verified what that means: clients see only peer 1, so every client message goes to the host, and only the host routes. A client cannot address another client (`rpc_id(other)` is a local error). **Owner and slot identity therefore come only from the `RaceConfig` slot table.** The host maps `multiplayer.get_remote_sender_id()` to the slots that peer owns.

| Tier | Traffic | Mode / channel | Rate |
|---|---|---|---|
| P0 events | bump, item hit, hazard hit, finish | `reliable`, **channel 2** | bursts |
| P0 control | race config, ready, go, results, lobby, peer left | `reliable`, channel 0 | rare |
| P1 state | snapshot packets | `unreliable_ordered`, **channel 1** | `send_hz` 30 |
| P2 clock | ping / pong | `unreliable`, channel 0 | 1 / `ping_interval` (2 Hz) |

**Why a separate reliable channel (V2).** ENet orders reliable delivery per channel. A lost channel-0 packet therefore never holds back channel-2 delivery on the receive side; the probe saw ordered channel 2 at 20% loss under a channel-0 burst. **The send window is shared per peer**, though, so a large channel-0 burst can still delay channel-2 *sends*. Control messages are kept small for that reason (a `RaceConfig` is under 1 KB).

**Envelope.** `rpc_event(bytes: PackedByteArray)`, encoded by `NetEventCodec` (pure, unit-tested) as `[kind u8][payload]`.

| Kind | Payload | Size | Route | **Ownership field checked by the host** | Receiver rule |
|---|---|---|---|---|---|
| 1 BUMP | to_slot u8, from_slot u8, tick u32, impulse 3 × f16, strength f16 | 15 B | detecting PC → host → owner of `to_slot` (the host applies it itself for a bot) | **`from_slot`** (the detecting PC owns the kart that hit); also dropped if `from_slot == to_slot` | `KartEvent` bump, applied at the **start of the owner's next tick** with max-merge dedup (ADR-0003 §7, §8). **Dropped by the owner if `tick < last_teleport_tick`** (ADR-0003 v4 §7, §8) |
| 2 ITEM_HIT | seq u32, victim u8, blocked u8, tick u32, item_kind u8 | 12 B | victim's PC (victim-confirmed) → host → all | **`victim`** | Items owns the meaning of the payload; the network only transports it |
| 3 HAZARD_HIT | slot u8, collider_id u32, outcome u8, tick u32 | 11 B | victim's PC (the victim decides, architecture Hazards) → host → all | **`slot`** | for presentation, audio and spectate. The effect already ran on the victim's PC that tick, and the snapshot carries spin and sinking |
| 4 FINISH | slot u8, finish_time f64 (race seconds) | 10 B | owner (the host for bots) → host → all | **`slot`** | Lap & Position orders finished karts by `finish_time`, ties by slot (ADR-0004 §5) |

**Snapshot records** are checked on **`slot`**. Events the host raises for its own bots are local and not checked.

**BUMP tick.** It is the **tick of the record whose pose was sampled** for the victim (record a while lerping or holding, the newest record while extrapolating), which `RemoteKartView` returns as the sampled `KartSnapshot.tick`. It is never later than `floor((n × SIM_DT − view_delay) / SIM_DT)`, so legitimate bumps are unaffected, and it closes the hold window: when the victim respawns at tick T on an off-send tick, a sample in [T·dt, (T+1)·dt) still draws pre-teleport record a and reports a's tick (< T), so the bump is dropped. The same holds while a pre-teleport record is extrapolated because the teleported packet is late or lost. Validation 4 covers the hold window.

**Other rules:**
- Item spawn and box-take messages (frozen `rpc_item_spawn`, `rpc_box_take`, `rpc_box_taken`) move into this envelope as kinds 5 and up when the Items story defines them. Adding a kind bumps VERSION.
- An unknown kind is dropped and logged as an anomaly (rate-limited).
- Impulses are in the world frame of the loaded, possibly mirrored track (ADR-0001 §7), so no conversion is needed.
- Every reliable event costs one 38 B on-wire ACK (V5).

### 5. Sending, batching, teleport epoch
- **Send ticks.** `send_every_ticks = roundi(60 / send_hz)` (= 2). At load the code **asserts that `60 % send_every_ticks == 0`** and that `60 / send_every_ticks == send_hz`.
  - A slot simulated here is sent on ticks where `tick % send_every_ticks == 0`.
  - A catch-up call that runs several ticks sends at most **one** packet per `_physics_process` call, carrying each slot's latest end-of-tick snapshot.
- **Accumulators per sent slot:**
  - `events_or |= snap.events & 0xFF` every tick, cleared on send;
  - `teleport_epoch = (teleport_epoch + 1) % 8` on every tick whose snapshot has `teleported` (respawn, launch, resync hold, `place`).
- **Why an epoch, not a bit.** A teleport bit on one record is lost with that packet, and the next record would then streak. A 3-bit counter survives any loss shorter than 8 teleports.
  - A record is `teleported` when its epoch differs from the previous record buffered for that slot.
  - **The first record buffered for a slot is always a teleport.**
- **Amended 2026-11-22 (ADR-0007): the epoch stays here, in the GDScript sender.** The native core only sets `teleported` in the snapshot (respawn, launch, `place`, resync hold). The sender reads `teleported` and `events` from the double-buffered `RaceSim.snapshots()` after `end_tick()`, and keeps the accumulators and the `teleport_epoch` counter as above. Nothing in the wire format changes.
- **Clients** send one packet per send tick to the host (`rpc_id(1)`), holding their own record(s).
- **The host owns bots.** On each send tick it sends one packet per client, holding:
  - its own kart and every bot;
  - the newest **not-yet-forwarded** record of every other client;
  - never the receiving client's own slot.
- **Held client records.** Forwarded records keep their original `tick`. A held record waits 0-33 ms at the host (16.7 ms on average).
  - **When a newer record from the same client replaces a held one, the host ORs the old record's `events` into the new one.** The epoch needs no merge: it is a counter, and the newer value already includes the count.
- **Receivers** drop any record whose `tick` is less than or equal to the newest tick buffered for that slot (a duplicate or a reorder).
- **Host-side hard drops** (logged as anomalies):
  - a record or event whose ownership field (§4) is not owned by the sender in the `RaceConfig` slot table;
  - any non-finite f16 or f32;
  - any `tick` farther than `max_tick_skew` from the host's target tick.
- **Logged only (OQ-4, provisional for A2):** speed and finish plausibility.

### 6. Race handshake: track identity, mirror, seed
`RaceConfig` is a RefCounted (`encode()` / `decode()` through `StreamPeerBuffer`, unit-tested). It travels reliably on channel 0, host → clients, and carries:
- `version` (= VERSION);
- `track_key` (the package path);
- `source_sha256` (64 hex characters);
- `bake_key` (64 hex characters);
- `mirror` (bool);
- `race_seed` (s64, ADR-0001 §6);
- `laps` (u8);
- `go_tick` (u32, the countdown length from Race Flow);
- the slot table: `slot`, `owner_peer`, racer id, vehicle id, `is_bot`.

**Start sequence:**
1. The host sends `RaceConfig`.
2. Each client loads the `TrackPackage`, applies `mirror` (ADR-0001 §7) and replies `race_ready(code)`. The checks run in this order:

   | Code | Meaning | Shown as |
   |---|---|---|
   | 0 | OK | — |
   | 1 | TRACK_MISSING | — |
   | 2 | SOURCE_MISMATCH (`source_sha256`) | "different track" |
   | 3 | BAKE_MISMATCH (`bake_key`) | "different game build" |
   | 4 | CLOCK_NOT_SYNCED (fewer than `clock_min_samples` after `race_ready_timeout`) | — |
   | 5 | LOAD_FAILED | — |

   A client replies OK only once it holds `clock_min_samples` clock samples.
3. After every client has replied, or `race_ready_timeout` has passed, the host sends `race_go(race_epoch, excluded_slots, finished, results_so_far)`:
   - `race_epoch` is the host's session time now + `race_epoch_lead`;
   - `finished` lists (slot, finish_time) for karts that have already finished; it is empty at a normal start;
   - `results_so_far` is also empty at a normal start. Both are filled for late joiners and spectators.
4. **Refused or silent clients** (OQ-1, provisional, owner decision): their slots are excluded from that race, and they stay in the lobby with the reason shown.
5. **On receiving `race_go`**, every PC clears all `RemoteKartView`s (`RemoteKartSet.clear()`), so no record or epoch baseline from a previous race survives.
6. **Race time** = synced session time − `race_epoch`.
   - **Tick 0 is the grid tick**, at race time 0, and racing starts at **`go_tick`**.
   - Below race time 0 the sim steps no ticks (ADR-0001 "ahead of target: wait").
7. **Late joiners and spectators** receive the same `RaceConfig` and `race_go`, including `finished` and `results_so_far`. Their target tick jumps to the current one. They own no kart, so nothing stalls.

**`bake_key` refusal (OQ-6, resolved: keep it).**
- **Why:** the same `.glb` baked by a different `CourseBuilder` gives different `distance` values, and so a silently wrong ranking and broadphase. ADR-0005's intent is that "two PCs never race different builds of a track".
- **Order:** `source_sha256` is checked first and `bake_key` second, so the message names the right cause.
- **Line endings:** ADR-0005 v3 hashes LF-normalised text inputs, so a line-ending difference cannot cause a false refusal.

### 7. Clock sync (owned here per ADR-0001 §5)
- **Session clock.** The host's session time is its monotonic `Time.get_ticks_usec()` since the session opened. A client keeps an applied offset: `synced_session = local_usec / 1e6 + offset_applied`.
- **Samples (NTP-style).** Every `ping_interval` (0.5 s, in the lobby and in the race), the client sends `t0` (its send time in µs). The host's pong carries `t0`, `t1` (host receive time, f64) and `t2` (host send time, f64). When the pong arrives at `t3` (local):
  - `rtt = (t3 − t0) − (t2 − t1)`;
  - `offset_i = ((t1 − t0) + (t2 − t3)) / 2`, in consistent units.

  Carrying `t1` and `t2` removes the host's processing delay from both values.
- **Estimate.** `ClockSync` keeps the last `clock_sample_window` (16, ≈ 8 s) samples. **The estimate is the offset of the minimum-RTT sample in the window**, the sample least inflated by queuing.
- **First sample.** It sets `offset_applied` directly; there is nothing to slew from.
- **Applying it** (each `_process`, real `dt`), with `err = estimate − offset_applied`:
  - |err| ≤ `clock_deadband` (2 ms): no change;
  - |err| > `clock_snap_threshold` (0.25 s): snap. If the sim is then behind, ADR-0001's catch-up and resync apply (the epoch is bumped); if ahead, it waits;
  - otherwise **slew**: `offset_applied += clamp(err, ±clock_slew_rate × dt)`, with `clock_slew_rate` = 0.02 s/s. A 50 ms error closes in 2.5 s.

  Race time never runs backwards except on a snap.
- **The host** has offset 0; it is the clock authority.
- **Target tick** = `floor(race_time / SIM_DT)` (ADR-0001 §5), with `catch_up_ticks_max` = 3 and `resync_ticks` = 30 (0.5 s), both in `NetConfig`.
- **Error bound:** half the path asymmetry of the minimum-RTT sample. Symmetric paths are assumed, which is accepted for home links.
- **What this replaces:** the frozen rule `lerp(race_time, host + rtt / 2, 0.15)` above a 20 ms threshold. That rule could step the clock backwards on any pong and followed the jitter of single samples.

### 8. RemoteKartView: buffer, interpolate, extrapolate, snap, report
- **One view per remote slot.** Each has a **preallocated ring** of `snapshot_buffer_size` (40, ≈ 1.3 s at 30 Hz) decoded records (`NetKartRecord`: slot, lap, epoch, a `KartSnapshot`). There is no `Dictionary` per snapshot (the frozen view's habit).
- **View delay: one value per receiving PC, the maximum over source peers.**
  - `NetMetrics` tracks lateness per source owner peer p: `lateness = synced_race_now − tick × SIM_DT` at arrival, giving `late_avg_p` and `late_dev_p`.
  - `view_delay = clamp(max_p(late_avg_p + 2·late_dev_p) + 1 / send_hz, view_delay_min 0.05, view_delay_max 0.35)`, smoothed by `view_delay_smoothing`.
  - Client-owned karts make two hops (client → host → client, about RTT + hold), so they set the maximum. **Bots and the host's kart are drawn later than they need to be; this is accepted** (Alternative 7). Using one value keeps every remote kart on one timeline and keeps ADR-0003's single-delay sample call.
  - The sim freezes the value once per tick.
- **Sample time:**
  - presentation: `synced_race_now − view_delay`;
  - simulation (contact and the remote broadphase, ADR-0003 v4): `n × SIM_DT − view_delay`.

  The remote broadphase uses the `distance` **sampled at that tick time**, not the newest record's.
- **Between records a and b** (a.t ≤ rt ≤ b.t):
  - lerped: position, velocity, `distance`, `speed`, `steer`, `throttle`;
  - slerped (`Quaternion.slerp`): orientation;
  - taken from a: the discrete fields (flags, `drift_state`, `surface_id`, `lap`, `boost`, `spin`).
  - **If b is teleported** (its epoch changed), the view **holds a until b.t, then snaps to b**. It never lerps across the jump.
- **Once-only reporting (events and teleport).** Each view keeps **one cursor per consumer**: `SIM` and `PRESENTATION`. A sample reports a record's `events` byte, and its teleport, **once**: at the consumer's first sample whose time is at or after the record's `t`.
  - If one sample passes several records (a long frame, or a catch-up run), it reports the OR of their `events` and `teleported = true` if any of them was a teleport.
  - Otherwise the sample reports `events = 0` and `teleported = false`.
  - The cursors are independent, so the sim and the presentation each see every event exactly once.
- **Past the newest record.** Position is extrapolated along the newest velocity for `min(rt − newest.t, max_extrapolation)` (0.25 s), then held. Orientation is held, because the wire carries no angular velocity.
  - **Remote karts never run collision queries.**
  - The sample reports `extrapolated_for` in seconds.
- **Before the oldest record:** the oldest is held.
- **Empty buffer:** EMPTY. The kart is not drawn.
- **After `peer_left`:** STALE (§10).
- **Contact eligibility** (ADR-0003 v4 `contact_eligible` mask). `RemoteKartSet.sample_into` writes 0 for a kart that is:
  - STALE;
  - EMPTY;
  - extrapolated past `contact_extrapolation_max` (0.1 s, `NetConfig`, owned here).

  The composition root adds FROZEN for its own karts (ADR-0003).
- **Ranking and broadphase** read the sampled `lap` and `distance` (ADR-0004 §5). Receivers never recompute remote progress.

### 9. NetMetrics (closes TD-010)
- **Prediction error.** On each buffered record b after a: `|b.pos − (a.pos + a.vel × (b.t − a.t))|`.
  - **It is skipped when b is teleported** (an epoch change, or b is the first record), and counted under `teleports` instead.
  - So TD-010 is closed by construction, and a lost flagged packet cannot leak a teleport into the average.
- **Unflagged jump.** If b has the same epoch but `|b.pos − a.pos| > teleport_jump_speed × (b.t − a.t)` (120 m/s), the jump is still counted as error **and** logged as anomaly `unflagged_jump`. A sender that forgot to bump the epoch is found, not hidden.
- **Counters:**
  - RTT (smoothed and max);
  - the clock's `err` and `offset_applied`;
  - per-peer lateness and the view delay;
  - snapshots per second and the extrapolated-frame percentage;
  - decode failures and anomalies by kind.
- **Byte counting.**
  - **Outgoing:** counted at the send sites, as payload size + 41 B per datagram (V5, IPv4).
  - **Incoming:** counted per RPC method from `bytes.size()` in the handler, + 41 B.
  - **`get_packet_channel()` / `get_packet_mode()` are forbidden for this purpose.** Inside an RPC handler they describe the next queued packet and error when the queue is empty (probe finding).
- **Rate-limited anomaly logging:** at most one line per kind per `anomaly_log_interval` (1 s), with the count since the last line.
- **Ported:** the frozen CSV net log and the `[net-summary]` line, with new columns.

### 10. Disconnection
- **A client drops.** The host broadcasts `peer_left(peer, slots)` on channel 0.
  - Views for those slots stop at the extrapolation cap and report STALE, which makes them contact-ineligible.
  - **For A2 the kart is parked** where it stopped, drawn as disconnected (OQ-2, provisional, owner decision). A bot takeover may come later.
- **The host drops.** The race ends for everyone. **There is no host migration** in v10: the host simulates the bots and the shared events.
- **Reconnect mid-race** is not supported. A returning player rejoins as a spectator through `race_go`, with `finished` and `results_so_far` (the frozen v7 late-joiner rule).

### Sync parameters (all in `NetConfig`; new-core instance `assets/data/core/net_config.tres`)

| Parameter | Value | Safe range | Sized by (design point 150 ms RTT / 30 ms jitter / 5% loss) |
|---|---|---|---|
| `send_hz` (existing) | 30 | 15, 20, 30, 60 (`roundi(60 / send_hz)` must divide 60) | bandwidth table; ADR-0001 §8 |
| `view_delay_min` / `view_delay_max` (existing) | 0.05 / 0.35 s | 0.03-0.1 / 0.25-0.5 | **Client, two hops:** 75 + 17 (hold) + 75 ms ≈ 0.167 s mean lateness; + 2 × ~30 ms dev; + 33 ms ≈ **0.26 s**. **Host, one hop:** ≈ 75 + 60 + 33 ≈ **0.17 s**. At 250 ms RTT the client value (≈ 0.36 s) hits the clamp, and client-owned karts extrapolate about 10 ms on average (degraded band) |
| `view_delay_smoothing` (existing) | 0.05 | 0.01-0.2 | frozen value |
| `max_extrapolation` (existing) | 0.25 s | 0.1-0.4 | ≈ 7 lost sends |
| `contact_extrapolation_max` (**new**, named by ADR-0003 v4) | 0.1 s | 0.03-0.25 | 3 lost sends; past it, a ghost pose would bump falsely |
| `snapshot_buffer_size` (existing) | 40 | ≥ (view_delay_max + max_extrapolation) × send_hz + 4 | 1.3 s |
| `ping_interval` (existing) | 0.5 s | 0.25-2 | 16 samples in 8 s |
| `clock_sample_window` (**new**) | 16 | 4-64 | span of the min-RTT filter |
| `clock_min_samples` (**new**) | 4 | 1-16 | required before `race_ready` OK |
| `clock_deadband` (**new**) | 0.002 s | 0-0.01 | well below one tick (16.7 ms) |
| `clock_slew_rate` (**new**) | 0.02 s/s | 0.005-0.1 | invisible rate change |
| `clock_snap_threshold` (**new**) | 0.25 s | 0.1-1.0 | beyond it, slewing would take too long |
| `catch_up_ticks_max` (**new**, named by ADR-0001) | 3 | 1-8 | 3 × the 2 ms tick budget fits one frame |
| `resync_ticks` (**new**, named by ADR-0001) | 30 | 6-120 | 0.5 s behind: stall rather than spiral |
| `race_ready_timeout` (**new**) | 10 s | 3-60 | track load time on the minimum PC (not measured) |
| `race_epoch_lead` (**new**) | 1.0 s | ≥ 2 × rtt_max + 0.2 | `race_go` must arrive before race time 0 |
| `max_tick_skew` (**new**) | 120 ticks | 30-600 | 2 s, far beyond any real lateness |
| `teleport_jump_speed` (**new**) | 120 m/s | > 1.5 × top boosted speed | anomaly detection only |
| `anomaly_log_interval` (**new**) | 1.0 s | 0.5-10 | rate limit |

- **Kept for the frozen game, never read by the new core:** `clock_correct_threshold` and `clock_correct_rate`. Their meaning is unchanged.
- **Not applicable to an owner-authoritative model.** These are stated so nobody adds them:
  - a reconciliation threshold and correction speed (there are no server corrections of an own kart);
  - an input delay (it is 0).

  The only cross-PC correction is a bump event.

### Bandwidth (payload exact; overhead measured, V5)

Sizes:
- record: 41 B;
- client packet: 2 + 41 = **43 B**;
- host-to-client packet with the 11 other karts: 2 + 11 × 41 = **453 B**;
- overhead: **41 B per datagram** on IPv4 (RPC header + ENet + UDP/IPv4), about 61 B on IPv6.

| Per player | Payload | On wire (IPv4) | On wire (IPv6) |
|---|---|---|---|
| Client upload (own kart) | 43 × 30 = 1.29 KB/s | (43 + 41) × 30 = **2.5 KB/s** | 3.1 KB/s |
| Client download (11 karts) | 453 × 30 = 13.6 KB/s | (453 + 41) × 30 = **14.8 KB/s** | 15.4 KB/s |
| Host upload, 3 clients (4 humans + 8 bots) | 40.8 KB/s | 44.5 KB/s | 46.3 KB/s |
| Host upload, 11 clients (12 humans) | 149.5 KB/s | **163 KB/s ≈ 1.3 Mbit/s** | 170 KB/s |
| Clock ping and pong, per client | ~0.05 KB/s each way | ~0.13 KB/s each way | ~0.17 KB/s |
| Events | 10-15 B + 41 B per event, plus a 38 B ACK | negligible | negligible |

This is about half of `architecture.md`'s estimate (~84 B per kart, ~30 KB/s per client down, ~330 KB/s host upload before overhead). That line is a Migration follow-up.

**Relevancy culling is not needed at 12 karts.** If a stress run shows the host's upload over budget, the first lever is to send karts far behind in `distance` at 15 Hz. That lever is not decided here.

### Architecture Diagram

```
 owner PC (client)                         host PC (owns bots, clock, routing, slot table)    other client
 tick n end-of-tick KartSnapshot ─┐        ┌─ own kart + 11 bots snapshots
 + CourseProgress.lap             │        │
 accumulators: events_or, epoch   │        │
 SnapshotCodec.write_record ──[43 B, ch1 unreliable_ordered]──▶ check slot owner / tick / finite ──▶ held per slot (events OR-merged)
                                                                │
                                   per client, every send tick: [VER][n][≤11 × 41 B] ─ch1─▶ SnapshotCodec.read ─▶ RemoteKartView ring
                                                                                                    │ sample(t − view_delay, cursor SIM | PRESENTATION)
                                                                                                    │ events + teleport reported once per cursor
                                                                                                    └▶ contact_eligible (STALE/EMPTY/extrap > 0.1 s → 0)
 KartContactSolver ─ bump(pose_tick) ─▶ NetEventCodec [ch2 reliable] ─▶ host (check from_slot) ─▶ owner of to_slot ─▶ drop if < last_teleport_tick, else tick n+1
 victim PC ─ ITEM_HIT (victim) / HAZARD_HIT (slot), owner ─ FINISH (slot) ─▶ host ─▶ all [ch2 reliable]
 ping(t0) ─ch0─▶ host pong(t0,t1,t2) ─▶ ClockSync (min-RTT of 16, first sample sets, slew 2%) ─▶ RaceClock ─▶ target tick = floor((S − epoch)/SIM_DT)
 RaceConfig(sha256 → bake_key, mirror, seed, go_tick, slots) ─ch0─▶ race_ready(code) ─▶ race_go(epoch, excluded, finished, results) ─▶ views cleared
 NetMetrics: view_delay = max over peers · pred error skipped on teleport (TD-010) · bytes at send sites / per RPC · anomalies rate-limited
```

### Key Interfaces

Each `class_name` lives in its own file under `src/networking/`. Only `NetLink` is a `Node`.

```gdscript
class_name SnapshotCodec extends RefCounted
const VERSION: int = 10
const HEADER_SIZE: int = 2
const RECORD_SIZE: int = 41
const POS_RANGE: float = 2048.0          ## metres; wire covers [-POS_RANGE, +POS_RANGE)
const POS_SCALE: float = 4096.0          ## steps per metre (0.244 mm)
const HALF_MAX: float = 65504.0          ## f16 clamp before the pre-round
## Writes the packet header for count records; returns the offset of the first record.
static func write_header(buf: PackedByteArray, count: int) -> int
## Writes one record at offset; returns the next offset. buf is preallocated by the caller.
static func write_record(buf: PackedByteArray, offset: int, slot: int, snap: KartSnapshot,
        lap: int, events_or: int, teleport_epoch: int) -> int
## Returns the record count, or -1 (wrong version, short or inconsistent length).
static func read_header(buf: PackedByteArray) -> int
## Decodes one record into out (preallocated); false on non-finite fields.
static func read_record(buf: PackedByteArray, offset: int, out: NetKartRecord) -> bool
static func encode_half_rounded(buf: PackedByteArray, offset: int, v: float) -> void   ## clamp + pre-round + encode_half
static func encode_rotation(b: Basis) -> int            ## smallest-three, canonical w >= 0 in
static func decode_rotation(bits: int) -> Quaternion    ## canonical w >= 0 out

class_name NetKartRecord extends RefCounted      ## one decoded record
var slot: int; var lap: int; var teleport_epoch: int; var position_clamped: bool
var snap: KartSnapshot                           ## tick, position, basis, velocity, ..., throttle, events, distance

class_name NetEventCodec extends RefCounted
enum Kind { BUMP = 1, ITEM_HIT = 2, HAZARD_HIT = 3, FINISH = 4 }
static func encode_bump(e: KartEvent, pose_tick: int) -> PackedByteArray   ## pose_tick on the victim's timeline (§4)
static func encode_hazard_hit(slot: int, collider_id: int, outcome: int, tick: int) -> PackedByteArray
static func encode_item_hit(seq: int, victim: int, blocked: bool, tick: int, item_kind: int) -> PackedByteArray
static func encode_finish(slot: int, finish_time: float) -> PackedByteArray
static func kind_of(bytes: PackedByteArray) -> int            ## -1 if empty or unknown
static func owner_slot(bytes: PackedByteArray) -> int         ## the field the host checks: from_slot / victim / slot; -1 if malformed
static func decode_bump(bytes: PackedByteArray, out: KartEvent) -> bool

class_name HandshakeCodec extends RefCounted     ## same 8-byte layout as the frozen NetHandshake
const MAGIC: String = "DWKR"
static func encode(version: int) -> PackedByteArray
static func decode(data: PackedByteArray) -> int              ## -1 if not ours

class_name RaceConfig extends RefCounted
var version: int; var track_key: String; var source_sha256: String; var bake_key: String
var mirror: bool; var race_seed: int; var laps: int; var go_tick: int
var slots: Array[RaceSlot]                                     ## slot, owner_peer, racer_id, vehicle_id, is_bot
func encode() -> PackedByteArray
static func decode(bytes: PackedByteArray) -> RaceConfig       ## null on bad input
## 0 OK, 1 TRACK_MISSING, 2 SOURCE_MISMATCH (checked first), 3 BAKE_MISMATCH (4, 5 come from NetLink)
func check_package(pkg: TrackPackage) -> int
func owner_of(slot: int) -> int                                ## owner_peer; the only source of ownership

class_name ClockSync extends RefCounted          ## pure; times injected for tests
func _init(config: NetConfig) -> void
func add_sample(t0_usec: int, t1_host: float, t2_host: float, t3_usec: int) -> void   ## first sample sets offset_applied
func step(dt: float) -> void                     ## slew or snap toward the min-RTT estimate
func synced_session_time(local_usec: int) -> float
func sample_count() -> int
var last_error: float                            ## estimate - applied, for NetMetrics

class_name RemoteKartView extends RefCounted
enum SampleState { EMPTY, INTERPOLATED, EXTRAPOLATED, HELD, STALE }
enum Consumer { SIM, PRESENTATION }
func _init(slot: int, config: NetConfig, metrics: NetMetrics) -> void
func push(rec: NetKartRecord, synced_now: float) -> void       ## copies into the ring; first record or epoch change → teleported
func sample(t: float, consumer: Consumer, out: KartSnapshot) -> SampleState   ## t already minus view_delay; events/teleported once per consumer
func lap_at(t: float) -> int
var extrapolated_for: float
func mark_stale() -> void
func clear() -> void

class_name RemoteKartSet extends RefCounted      ## what ADR-0003's tick calls remote_views
func sample_into(snaps: Array[KartSnapshot], t: float, consumer: int,
        out_state: PackedByteArray, contact_eligible: PackedByteArray) -> void   ## eligible = 0: STALE, EMPTY, extrap > contact_extrapolation_max
func clear() -> void                             ## on race_go

class_name NetMetrics extends RefCounted
var view_delay: float; var rtt: float
func record_arrival(owner_peer: int, lateness: float) -> void  ## per-peer avg/dev; view_delay = max over peers
func record_prediction(a: NetKartRecord, b: NetKartRecord, b_teleported: bool) -> void   ## skips teleports (TD-010)
func record_frame(state: int) -> void
func record_rtt(sample: float) -> void
func record_bytes(tier: int, payload_bytes: int, outgoing: bool) -> void   ## + 41 B per datagram; called at send sites / per RPC
func anomaly(kind: StringName) -> void                                     ## rate-limited log
func close_window() -> Dictionary

class_name NetLink extends Node                  ## the only Node; owns SceneMultiplayer, RPCs, routing
signal handshake_failed(host_version: int)
signal race_config_received(cfg: RaceConfig)
signal race_go_received(race_epoch: float, excluded: PackedByteArray, finished: Array, results: Array)
signal snapshot_packet(bytes: PackedByteArray, from_peer: int)
signal event_received(bytes: PackedByteArray, from_peer: int)
signal peer_left(peer: int, slots: PackedByteArray)
func host(config: NetConfig) -> Error
func join(address: String, config: NetConfig) -> Error
func send_snapshots(bytes: PackedByteArray, to_peer: int) -> void    ## ch1 unreliable_ordered
func send_event(bytes: PackedByteArray, to_peer: int) -> void        ## ch2 reliable
```

**Superseded 2026-11-22 (ADR-0007), the simulation-facing calls only.** Where the simulation is native, the tick no longer takes `Array[KartSnapshot]` or `KartBody.apply_event`. Wire formats, `NetLink`, the codecs and `NetMetrics` are unchanged. The new form, beside the old:
```gdscript
# RemoteKartSet.sample_into(snaps: Array[KartSnapshot], t, consumer, out_state, contact_eligible)   <- superseded for the tick
func RemoteKartSet.sample_into_packed(t: float, consumer: int, out_snaps: PackedFloat32Array, out_state: PackedByteArray) -> int   # returns the contact_eligible bitmask
# The caller then passes both to RaceSim.set_remote(remote_snaps_packed, contact_eligible_mask) between step_bodies() and step_contact().
# Received BUMP events (decoded by NetEventCodec) go in through RaceSim.apply_events(headers, payload) at the start of the tick.
# Events out of the sim: RaceSim.event_headers() / event_payload() / event_count() / events_overflowed(), double-buffered.
```
The packed layout of the remote record rows is fixed by the `RaceSim` story. `contact_eligible` keeps its rules (STALE, EMPTY, over-extrapolated, FROZEN give 0). The host's bots go through the same stages as local karts.

### Implementation Guidelines
- **Serialisation boundary.**
  - `SnapshotCodec` **must** be the only code that serialises a `KartSnapshot`.
  - Kart Physics **must never** reference `src/networking/`.
- **Versioning.**
  - Every change to a message layout or meaning **must** bump `SnapshotCodec.VERSION`, and so **must** any renumbering of ADR-0003 v4 §8 event bits 0-7.
  - The handshake **must** refuse any version other than its own, with a message on both sides.
- **Names and boundaries.**
  - New code **must never** reuse the frozen `class_name`s (`KartWire`, `NetHandshake`, `NetSession`, `RemoteKart`, `NetStats`).
  - New code **must not** reference `src/legacy/`.
- **Encoding.**
  - f16 fields **must** be clamped to ±65504 and pre-rounded before `encode_half`. A bare `encode_half` is forbidden, because it truncates.
  - Wire quaternions **must** come from a just-orthonormalised basis.
  - Decoded quaternions **must** be re-canonicalised to w ≥ 0.
  - Positions outside ±2048 m **must** be clamped, flagged and logged, never wrapped.
- **Teleports.**
  - A teleport **must** be signalled by bumping the 3-bit epoch.
  - Receivers **must** detect it as an epoch change, or as the first record for a slot. They **must never** detect it from a single-record bit or a distance heuristic.
- **Remote samples.**
  - Remote `events` and teleports **must** be reported once per consumer cursor (SIM, PRESENTATION).
  - The host **must** OR a replaced held record's events into its replacement.
  - `NetMetrics` **must never** count a teleported record as prediction error.
  - Remote karts **must never** run collision queries.
  - Extrapolation **must** stop at `max_extrapolation`.
  - A remote kart **must** be contact-ineligible when STALE, EMPTY, or extrapolated past `contact_extrapolation_max`.
  - The sim **must** sample remote karts, and their broadphase `distance`, at `n × SIM_DT − view_delay`, with one `view_delay` value (the maximum over source peers) frozen per tick.
- **Bumps.**
  - A BUMP **must** carry the pose tick on the victim's timeline.
  - The owner **must** drop it if `tick < last_teleport_tick` (ADR-0003 v4).
  - Otherwise it **must** apply at the start of the owner's next tick through `KartBody.apply_event`.
  - **Amended 2026-11-22 (ADR-0007):** in the native core "apply at the start of the next tick" means `RaceSim.apply_events(headers, payload)` (stage 2). The rules above are unchanged. An item pickup roll still happens in GDScript and reaches the kart one tick later as a `pickup` event.
- **Channels and routing.**
  - Snapshots **must** go on channel 1 `unreliable_ordered`.
  - Gameplay events **must** go on channel 2 `reliable`.
  - Control **must** stay on channel 0, and control messages **must** stay small (the per-peer send window is shared).
  - `server_relay` **must** be false.
- **Ownership.**
  - Ownership **must** come only from the `RaceConfig` slot table.
  - The host **must** drop any record or event whose per-kind ownership field (§4) the sender does not own.
- **Race start.**
  - A client **must not** reply `race_ready` OK unless `source_sha256` and then `bake_key` match and it holds `clock_min_samples`.
  - Every PC **must** clear all remote views on `race_go`.
- **Clock.**
  - Race time **must** be `synced_session − race_epoch`.
  - The first clock sample **must** set `offset_applied` directly.
  - Simulation code **must never** read the continuous clock inside a tick (ADR-0001 §5).
- **Config.**
  - Every sync parameter **must** come from `NetConfig`.
  - `NetConfig` **must** change only additively.
  - At load, the code **must** assert that `roundi(60 / send_hz)` divides 60.
- **Metrics and logging.**
  - Byte counters **must** count at send sites and per received RPC method.
  - `get_packet_channel()` / `get_packet_mode()` **must never** be used for metrics.
  - Anomaly logs **must** be rate-limited per kind.
- **Allocation.** Per-tick and per-frame paths **must not** allocate a `Dictionary` or `Array` per snapshot. Rings and records are preallocated.

## Alternatives Considered

### Alternative 1: Extend the VERSION 9 float array to 3D
- **Description:** keep the `PackedFloat32Array` with one RPC per kart, and add `y`, `vy`, a full quaternion and velocity: about 30 floats, or 120 B per kart.
- **Pros:** the smallest code change, and it matches the frozen code's shape.
- **Cons:**
  - about 3× the bytes;
  - no stated error bounds;
  - one RPC per kart multiplies the datagram count, and so the 41 B overhead, by up to 11.
- **Rejection Reason:** bandwidth and datagram count.

### Alternative 2: Batched, but with unquantised float32 fields
- **Description:** the same batching, but with raw float32 `Vector3` and `Quaternion`: about 64 B per record.
- **Pros:** no quantisation code, and the values are bit-exact to the sender's float32.
- **Cons:** about 1.6× the bytes: host upload ≈ 264 KB/s of payload for 12 humans.
- **Rejection Reason:** the quantised codec is verified on 4.8-beta3 (V1) and halves the host's upload. **This is the fallback** if a codec bug is found late; it needs only a VERSION bump.

### Alternative 3: SceneMultiplayer server relay of client packets
- **Description:** clients broadcast, and the host relays each packet to every other peer as it arrives.
- **Pros:** no host hold, which saves 0-33 ms on client-to-client karts.
- **Cons:**
  - With 12 humans, 11 × 11 datagrams per send instead of 11.
  - Spoofed-slot checks would need custom relay hooks anyway.
- **Rejection Reason:** datagram count and validation. The hold sits inside the view delay.

### Alternative 4: Input lockstep or rollback
- **Description:** send inputs, and let every PC simulate every kart.
- **Pros:** tiny packets and consistent contacts.
- **Cons:**
  - It needs cross-machine bit-exactness, which ADR-0001 §6 explicitly does not provide.
  - Rollback suits frame-exact genres such as fighting games; a kart racer tolerates interpolation.
- **Rejection Reason:** it contradicts ADR-0001 §6.

### Alternative 5: Delta compression against an acknowledged baseline
- **Description:** send only the fields that changed relative to the last acknowledged record.
- **Pros:** maybe 40-60% fewer bytes.
- **Cons:** it needs an ack stream over unreliable delivery and a baseline per peer, and it is harder to test.
- **Rejection Reason:** 41 B per record is already small. Deferred until a measurement says otherwise.

### Alternative 6: `MultiplayerSynchronizer` / `MultiplayerSpawner`
- **Description:** engine-driven property replication of nodes.
- **Pros:** less hand-written code.
- **Cons:** sim objects are `RefCounted`, not nodes. It offers no control over quantisation, tick stamping or batching.
- **Rejection Reason:** incompatible with the `RefCounted` core.

### Alternative 7: A view delay per source peer
- **Description:** keep a separate adaptive delay per source peer, so the host's karts (bots) are drawn closer to live.
- **Pros:** about 0.09 s less delay on bots at the design point.
- **Cons:**
  - Remote karts would be drawn on different timelines, so visual passes between a bot and a client kart would not match the ranking.
  - ADR-0003's sample call assumes one delay.
- **Rejection Reason:** TD-ADR v1. v2 uses one value, the maximum over peers, and accepts the later-drawn bots. Revisit after A2 measurements.

## Consequences

### Positive
- About half the bandwidth of the earlier estimate, measured against real overhead. One datagram per peer per send, and no fragmentation.
- Error bounds are stated and verified on 4.8-beta3. Quaternions are canonical on both ends.
- TD-010 is closed by construction. A lost teleport packet cannot cause a streak, pollute the metrics or double an event.
- Ownership checks match each event's real owner, so legitimate bumps pass and spoofed ones are dropped.
- The track build, mirror state and seed can never silently differ between PCs.
- The clock ignores the jitter of single samples and never steps backwards outside a snap.
- Codecs, clock, views and metrics are pure `RefCounted` classes, so they can be unit-tested without a network.

### Negative
- Client-to-client karts take an extra 0-33 ms from the host hold.
- Bots are drawn at the client-kart delay, which is later than they need.
- The host is a single point of failure (no migration), and its upload grows linearly with the number of clients.
- The codec is more code than a float array, with an engine trap (`encode_half` truncation) that a review must catch.
- The `events` byte is lossy for remote karts, and landing magnitudes are not sent at all. Both are cosmetic.

## Risks
- **Engine drift at 4.8 stable:** the probes ran on 4.8-beta3, and `modules/networking.md` marks 4.8 NOT SOURCEABLE. Mitigation: re-run the probe scripts in `prototypes/collision-spike/` at `/setup-engine refresh` when 4.8 reaches stable.
- **A future `encode_half` fix:** if Godot changes `encode_half` to round, the pre-round becomes a double rounding with at most one ulp of extra error. Mitigation: the codec unit test asserts the bounds and the near-zero mean bias, so a change shows up as a failing test.
- **V4 not run:** the frozen and new builds might not refuse each other as written. Mitigation: Validation 8 runs it before A2.
- **Clock asymmetry:** asymmetric routes bias the offset by half the asymmetry. Mitigation: the min-RTT filter, and the view delay absorbs a constant bias. It is logged as the clock `err`.
- **Owner trust:** a modified client can report any state or finish time. For A2, friends-only, the hard drops limit spoofing (ownership per kind, finite values, tick skew). The plausibility checks only log (OQ-4). **This must be revisited with security-engineer before room codes (ADR-0008) open play to strangers.**
- **Degraded band:** between 250 ms RTT and the clamp, client-owned karts extrapolate more often. Mitigation: `view_delay_max` is tunable up to 0.5 s; NetMetrics reports the extrapolated percentage.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| design/gdd/kart-physics.md §3.2 | `drift_state`, `boost`, `spin`, `sinking` are copied in from `DriveState` into the snapshot | §2 encodes all four (drift_state u8, boost and spin u16 ms, sinking flag) |
| design/gdd/driving-and-drift.md §3.3 item 7, §6 (Networking row) | provides `drift_state`, `boost`, `spin` and `sinking` in the snapshot; remote karts are interpolated, never driven | §2 encoding with the GDD's data maxima (boost 2.0 s, spin 1.25 s, §3.2); §8 interpolation only |
| design/gdd/driving-and-drift.md §3.2 | `start_boost_times` max 2.0 s; `spin_time` max 1.25 s | u16 ms fits with a 30× margin (§3) |
| design/gdd/systems-index.md row 4, Network Session & Sync | "migrate: 3D snapshot, wire version bump"; "host/join, owner-authoritative karts, wire format" | §1 VERSION 10 with refusal; §2 the 3D record; §4-§5 owner-authoritative routing |
| systems-index.md High-Risk table, "Network wire migration" | 3D state (position, velocity, basis, grounded) needs a new snapshot and a version bump | §2 carries position, quaternion, total velocity and the grounded flag |
| systems-index.md Seams (lines 185-187) | the snapshot contract carries inbound events (bump impulses, item hits) | §4 BUMP and ITEM_HIT on reliable channel 2 |
| systems-index.md Circular Dependencies (lines 241-245) | Kart Physics knows nothing of the network; Network Sync uses a snapshot contract | `SnapshotCodec` reads and writes `KartSnapshot`; Core never references `src/networking/` |
| systems-index.md row 8, Race Session & Synced Clock | a shared synced race clock | §7 NTP-style min-RTT clock with slew; §6 epoch and start tick |
| systems-index.md row 11, Lap & Position Tracking | ranking across PCs | the wire's `lap` and `distance` (§2); the FINISH event (§4); late joiners get `finished` (§6) |
| systems-index.md row 14, Track Hazards | hits are decided on the victim's PC | HAZARD_HIT is sent by the victim and checked on `slot` (§4) |
| systems-index.md row 15, Items & Item Boxes | victim-confirmed hits | ITEM_HIT is checked on `victim` (§4); later item kinds join the same envelope |
| systems-index.md row 17, Race Flow & Lobby | post-finish spectating and late joiners | §6 `race_go` with `finished` and `results_so_far`; §10 disconnect contract |
| systems-index.md row 36, Room Codes & Relay | depends on Network Session & Sync | the network-side contract for ADR-0008: one UDP port, ENet, 30 Hz, the bandwidth table; OQ-4 must be revisited first |
| systems-index.md row 41, Spectate & Broadcast | reads the item event stream | ITEM_HIT, HAZARD_HIT and FINISH are broadcast to all (§4) |

**GDD sync: NOT ASSESSED in full.** This pass read only these parts of `driving-and-drift.md`: the `drift_state` lines (§3.3 item 7, §6) and the `boost_time` / `spin_time` maxima (§3.2). Of `kart-physics.md` it read only the §3.2 heading list and line 391. The GDDs' remaining names were not compared with this ADR's Key Interfaces, for example whether either GDD still says `accel` where ADR-0003 v4 says `throttle`.

## Performance Implications
- **CPU (estimates, not measured):**
  - encoding 12 records and decoding 11 per send tick: ≤ 0.05 ms p95 on the owner's PC. This fits `architecture.md`'s 0.15 ms row for "race logic, lap/progress, net send";
  - remote sampling, 11 karts, per tick (sim cursor) and per frame (presentation cursor): ≤ 0.05 ms.
- **Memory.** A GDScript `KartSnapshot` object is about 1 KB. 11 views × 40 records ≈ 440 records ≈ **0.45 MB** of rings, all preallocated. The packet buffers are preallocated at 494 B.
- **Load Time:** none. `RaceConfig.check_package` compares two strings.
- **Network:** see the bandwidth table.
  - A client uses ≈ 14.8 KB/s down and 2.5 KB/s up.
  - The host's upload is ≈ 44.5 KB/s with 3 clients and ≈ 163 KB/s with 11.
  - Figures are for IPv4; IPv6 is about 4% more.

## Migration Plan
1. **Probe:** done for V1, V2, V3 and V5 (evidence in `prototypes/collision-spike/out/`). V4 is still to run (Validation 8).
2. **Story 025's network sub-story, test-first, in `src/networking/`:**
   - first, the codecs (with the f16 pre-round), `RaceConfig`, `ClockSync`, `RemoteKartView` / `RemoteKartSet` and `NetMetrics`, with unit tests;
   - then `NetLink`. It ports host, join, auth and the fake-network queue from the frozen `NetSession`, and adds channel 2, `server_relay = false`, host aggregation with event OR-merge, and the ownership checks per kind.
3. **`NetConfig`:** add the new fields additively, with defaults and `##` comments, including `contact_extrapolation_max`. Fork `assets/data/core/net_config.tres` and add the new values.
4. **Composition root:**
   - wire `ClockSync` → `RaceClock` → target tick;
   - send snapshots on send ticks;
   - call `RemoteKartSet.sample_into` (SIM cursor, `contact_eligible`) in ADR-0003 v4's tick order;
     - **Amended 2026-11-22 (ADR-0007):** the root runs the eight `RaceSim` stage calls, and does its network I/O between them: inbox events before `begin_tick`, `sample_into` then `set_remote` between `step_bodies` and `step_contact`, and the send and event encode after `end_tick`. `RaceSim` asserts the stage order.
   - clear the views on `race_go`.
5. **Frozen game:** untouched. VERSION 9 stays in `src/legacy/net/`.
6. **Follow-ups for other owners:**
   - **`docs/registry/architecture.yaml`:** `race_clock` gets `referenced_by: ADR-0006` now. After acceptance it gets a per-player bandwidth budget entry and `api_decisions` for wire VERSION 10 and the clock sync (min-RTT filter + slew). This goes through the `/architecture-decision` registry step with user approval.
   - **`docs/architecture/architecture.md`:**
     - the Performance Budgets bandwidth line needs this ADR's table;
     - **line 82** (Module Ownership, Network Session & Sync, Exposes) still says `SnapshotCodec.pack/unpack`. It should name `SnapshotCodec.write_record/read_record`, `NetEventCodec` and `RemoteKartView`.
   - **ADR-0005:** hash LF-normalised text inputs into `bake_key` (the coordinator is adding this).
   - **The Items story:** define event kinds 5 and up.
   - **security-engineer:** review OQ-4 before ADR-0008.

## Validation Criteria
1. **Codec unit tests** (`tests/unit/networking/`):
   - the record size is 41 and the header size is 2;
   - the position round-trip error is ≤ 0.123 mm over a grid that includes ±2000 m and both range edges, and a clamp sets `position_clamped`;
   - 10,000 seeded random quaternions decode within **0.28°**, with w ≥ 0;
   - the f16 fields have error ≤ 0.0156 below 64 and ≤ 0.031 up to 128. Their mean signed error over a seeded sweep is ≈ 0 (no truncation bias). ±70000 encodes as ±65504, not inf;
   - the u16 and snorm8 bounds hold;
   - a wrong version byte or a short buffer returns −1.
2. **Event codec tests:** every kind round-trips. `owner_slot` returns `from_slot` for BUMP, `victim` for ITEM_HIT, and `slot` for HAZARD_HIT and FINISH. An unknown kind returns −1.
3. **ClockSync test** (injected times, seeded jitter):
   - at 150 ms RTT ± 30 ms jitter and 5% loss, |err| < 5 ms within 8 s;
   - the first sample sets the offset exactly;
   - race time is monotonic under slew;
   - a 0.5 s step snaps.
4. **RemoteKartView tests:**
   - the interpolation midpoint is correct;
   - extrapolation stops at 0.25 s;
   - contact eligibility drops at 0.1 s of extrapolation and when STALE or EMPTY;
   - an epoch change holds, then snaps, even when the flagged record was dropped;
   - the first record is a teleport;
   - a record's events are reported exactly once to SIM and once to PRESENTATION, including when one sample passes three records;
   - duplicate and older ticks are ignored;
   - `clear()` resets the epoch baselines.
5. **Host aggregation test:** replacing a held record ORs its events into the new one. A record or BUMP from a peer that does not own the checked field is dropped and logged.
6. **NetMetrics TD-010 test:**
   - a respawn sequence produces no prediction-error sample and one `teleports` count;
   - an unflagged 30 m jump produces one rate-limited `unflagged_jump` anomaly;
   - `view_delay` equals the maximum over peers.
7. **RaceConfig tests:**
   - the encode/decode round-trip is exact;
   - `check_package` returns 2 on a `source_sha256` mismatch even when `bake_key` also differs, and 3 on a `bake_key` mismatch alone.
8. **Integration and coexistence** (`tests/integration/networking/`, two ENet peers on localhost):
   - a v10 handshake with v10 passes, and a constant v9 packet is refused;
   - a race start with a `bake_key` mismatch excludes that client;
   - **V4:** a frozen host with a new client, and the reverse, both refuse with a message. The log is retained in `production/qa/evidence/`.
9. **Online run at A2, re-derived from the OQ-7 design point.**
   - **Setup:** 4 PCs, or the net_stress harness, with fake lag 75 ms each way per link (150 ms RTT), 30 ms jitter and 5% loss.
   - **Clock:** |clock err| < 5 ms at every client after 10 s.
   - **View delay:** at clients, 0.26 s ± 0.04 (two-hop maximum); at the host, ≤ 0.20 s.
   - **Extrapolated frames:** < 5% at clients and < 2% at the host.
   - **Bandwidth** (`NetMetrics`, IPv4): client download 14.8 KB/s ± 15%; host upload 44.5 KB/s ± 15% with 3 clients.
   - **Teleport:** a moat respawn draws as a snap, not a streak, with no remote bump on the respawned kart. A capture is retained in `production/qa/evidence/`.
   - **Degraded check at 250 ms RTT:** the race completes, client-side extrapolated frames are < 25%, and no kart becomes STALE.

## Open Questions (v2: provisional answers adopted)

| ID | Question | v2 answer | Status |
|---|---|---|---|
| OQ-1 | A client refused at race start | Exclude it from that race; it stays in the lobby with the reason shown | **Owner decision**, provisional |
| OQ-2 | A client that disconnects mid-race | Park the kart for A2 (drawn disconnected, contact-ineligible); a bot takeover may come later | **Owner decision**, provisional |
| OQ-3 | Contact eligibility of an extrapolated remote kart | Accepted in ADR-0003 v4: `contact_eligible` = 0 for STALE, EMPTY, extrapolated > `contact_extrapolation_max` (0.1 s) | Resolved |
| OQ-4 | Validation boundary under owner authority | For A2, plausibility is logged only, plus the hard drops (ownership per kind, finite values, tick skew) | Provisional; **revisit with security-engineer before room codes open play to strangers** |
| OQ-5 | Field meanings | `boost` and `spin` are remaining seconds (max 2.0 s and 1.25 s); `drift_state` packs drifting, direction and tier 0-3, and Driving owns that packing; `throttle` replaces `accel` | Resolved (driving-and-drift.md, kart-physics.md, ADR-0003 v4) |
| OQ-6 | Keep the `bake_key` refusal | Yes. `source_sha256` is checked first ("different track"), then `bake_key` ("different game build"); ADR-0005 hashes LF-normalised text | Resolved |
| OQ-7 | Latency design point | 150 ms RTT / 30 ms jitter / 5% loss; degraded but playable up to about 250 ms | **Owner decision**, provisional |

## Related
- **Depends on:**
  - ADR-0001: clock §5, determinism §6, mirror §7, interpolation §8, names §9;
  - ADR-0003 v4: `KartSnapshot` with `throttle`, `KartEvent`, the §8 pinned bit table, `contact_eligible`, `last_teleport_tick`, contact §7;
  - ADR-0004: the wire meaning of lap and distance, §5;
  - ADR-0005: `source_sha256` and `bake_key`, §6.
- **Supersedes, for the new core only:** the frozen `src/legacy/net/kart_wire.gd` (VERSION 9), `net_handshake.gd`, `net_session.gd`, `remote_kart.gd` and `net_stats.gd`. They are not modified, and the frozen game keeps them unchanged.
- **Enables:** ADR-0008 (room codes and relay) and ADR-0010 (ghost format).
- **Design:** `design/gdd/driving-and-drift.md` and `design/gdd/kart-physics.md` (snapshot fields); `design/gdd/systems-index.md` (rows 4, 8, 11, 14, 15, 17, 36 and 41, the Seams list, the High-Risk table).
- **Architecture:** `docs/architecture/architecture.md` (Data Flow 2-3, API Boundaries, Performance Budgets, line 82 follow-up); `docs/registry/architecture.yaml` (follow-up).
- **Evidence:** `prototypes/collision-spike/out/probe_adr6_codec.txt`, `probe_adr6_net.txt`, `probe_adr6_net2.txt`.
- **TD-010** (respawn teleports counted as prediction error): closed by §5 and §9 once implemented.
- **Amended 2026-11-22** by ADR-0007 (native simulation core): the tick order as `RaceSim` stage calls, packed remote poses and the event pair, and the teleport epoch staying in the GDScript sender. Wire format unchanged.

## v2.1 note (TD-ADR re-review, 2026-11-22)
- BUMP tick = sampled record's tick (above), mirrored in ADR-0003 §7.
- **`frozen` on the wire:** a spare bit of the flags byte carries the owner's `BodyState.mode == FROZEN` (sinking/falling, ADR-0003 v4 P6). Receivers set `contact_eligible = 0` for a frozen remote kart, so nobody takes full separation off a sinking ghost. The flags-byte layout is pinned in §3; using the spare bit bumps VERSION only if a released build already used it (none has).
