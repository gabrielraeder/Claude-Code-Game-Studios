# ADR-0006: Network Snapshot for 3D

## Status
Proposed

## Date
2026-11-22

## Last Verified
2026-11-22 (drafted against ADR-0001, ADR-0003, ADR-0004, ADR-0005 and `architecture.md` as of this date; no engine API in this ADR has been exercised on 4.8-beta3 yet, see Engine Compatibility)

## Decision Makers
Claude (network-programmer subagent) drafted v1. Not yet reviewed: godot-specialist validation (Step 5.5) and TD-ADR (Step 5.6) have **not run** on this draft. Acceptance needs the owner's confirmation.

## Summary
The rebuilt 3D core needs a wire format, an event channel, a handshake and a clock that replace the frozen 2.5D `KartWire` VERSION 9, which carries planar state in 21 float32s per kart. This ADR fixes protocol **VERSION 10**: a quantised 41-byte per-kart record batched by the host, reliable gameplay events on their own channel, a race config that carries track identity, mirror and seed and is refused on a mismatch, a min-RTT slewed clock that sets the target tick, and a `RemoteKartView` that interpolates, caps extrapolation by time and snaps on a loss-proof teleport epoch, with `NetMetrics` leaving teleports out of prediction error (closes TD-010).

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.8-beta3 |
| **Domain** | Networking |
| **Layer** | Foundation (Network Session & Sync, `architecture.md` System Layer Map) |
| **Knowledge Risk** | HIGH (4.8 is post-cutoff and pre-release) |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`. **No networking module reference was read for this draft.** Whether 4.5-4.8 changed `SceneMultiplayer`, `ENetMultiplayerPeer` or `@rpc` is NOT SOURCEABLE from what was read. The frozen `src/legacy/net/*.gd` uses the same API family and is the working reference. |
| **Post-Cutoff APIs Used** | None intended. Pre-cutoff APIs relied on: `SceneMultiplayer` authentication (`auth_callback`, `send_auth`, `complete_auth`; the frozen game already uses these), `SceneMultiplayer.server_relay`, `@rpc(..., transfer_channel)`, `ENetMultiplayerPeer`, `PackedByteArray.encode_u8/u16/u32/s64/half/float/double` and the matching `decode_*`, `Time.get_ticks_usec()` |
| **Verification Required** | (V1) `PackedByteArray.encode_half` / `decode_half` exist on 4.8-beta3 and round-trip IEEE binary16 (rounding to nearest). (V2) An `@rpc` on `transfer_channel` 2 is delivered on its own ENet channel, apart from channel 1, with the `ENetMultiplayerPeer` created the way `NetLink` creates it. That means checking the channel count argument of `create_server` / `create_client`. The frozen game only proves channel 1. (V3) `SceneMultiplayer.server_relay = false` stops client-to-client relay, and `rpc_id(1, ...)` from a client still reaches the host. (V4) A v9 frozen host refuses a v10 client cleanly and the reverse, both run from HEAD. (V5) The per-packet overhead (UDP/IPv4 + ENet + SceneMultiplayer RPC header + `PackedByteArray` Variant header), estimated at about 60 B below, measured with `NetMetrics` byte counters against an ENet-level capture or the peer's statistics |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Accepted; §5 clock and target tick, §6 determinism and race seed, §7 mirror frame on the wire, §8 interpolation, teleport flag, canonical quaternion, capped extrapolation, §9 class names). ADR-0003 (`KartSnapshot`, `KartEvent`, remote contact model; must be Accepted). ADR-0004 (wire meaning of `lap` and `distance`, finish ordering; must be Accepted). ADR-0005 (`TrackPackage.source_sha256`, `bake_key`; must be Accepted) |
| **Enables** | ADR-0008 room codes and relay (it inherits this ADR's network-side contract: one UDP port, ENet, 30 Hz, the bandwidth figures). ADR-0010 time-trial ghost format (ghosts record snapshot streams, Data Flow 3; the per-packet version byte lets a stored stream be decoded) |
| **Blocks** | Story 025's network sub-story (Castle Circuit online with bots, checkpoint **A2**) |
| **Ordering Note** | `NetConfig` (`src/data/`) gains fields **additively** only (ADR-0001 §9). The frozen `assets/data/net/net_config.tres` is never read by new code; the new core reads `assets/data/core/net_config.tres`. Open question OQ-3 (contact eligibility of an extrapolated remote kart) needs a one-line ADR-0003 amendment if accepted. |

## Context

### Problem Statement
The frozen game's `KartWire` VERSION 9 sends one RPC per kart. Each carries an int kart id, a float race time and a `PackedFloat32Array` of 21 fields: planar `x, z`, a scalar `yaw`, a separate `height` and `vy`, and lap and finish data. Clients relay through the host (`server_relay`). The rebuilt core has 3D state with an orientation `Basis` (ADR-0001 §3), total world velocity (ADR-0003 §7), a signed race distance (ADR-0004 §5), and teleports that must not count as prediction error (TD-010: the frozen `NetStats` counts a moat respawn as a huge error).

None of that fits VERSION 9. Checkpoint A2 (Castle Circuit online with bots) cannot be reached without a wire format, an event set, a track-identity check and the clock rule that ADR-0001 §5 delegates here.

### Constraints
- **Owner-authoritative** (architecture Data Flow 3): each PC simulates its own kart, the host simulates all bots and decides shared events, and remote karts are interpolated, never simulated. There is no cross-machine determinism (ADR-0001 §6), so lockstep and rollback are out.
- **Up to 12 racers** (`NetConfig.max_racers`), any mix of humans and host bots. Friends over home connections.
- **±2 km** geometry bound (ADR-0001 §1); `Vector3` / `Quaternion` are float32.
- **Frozen game:** VERSION 9 keeps running from HEAD until A3. The two games never play together; the handshake must refuse cleanly both ways.
- **No autoloads; dependency injection.** Only the RPC endpoint may be a `Node`. Codecs, clock and views are `RefCounted` and unit-testable.
- **Latency target:** none was found in the documents read for this draft. The design uses the agent default of **150 ms RTT** with 30 ms jitter and 5% loss (the frozen fake-network knobs model the same).

### Requirements
- One snapshot record per kart, bounded size, under one MTU for 12 karts.
- Quantisation error bounds stated and unit-tested.
- Reliable events for bump impulse, item hit, hazard hit result and finish (with race time), on a channel that lobby traffic cannot stall.
- A handshake that refuses a different protocol version, and a race config that refuses a different track build, mirror state or seed.
- A clock that every PC turns into the same target tick (ADR-0001 §5), and a defined start tick.
- Remote interpolation on 3D with a time-capped extrapolation and a teleport snap that survives packet loss.
- `NetMetrics` that excludes teleports from prediction error.
- Every sync parameter in `NetConfig`, none in code.

## Decision

### 1. Protocol version and coexistence
- **`SnapshotCodec.VERSION = 10`** is the single protocol version for the whole RPC set, as `KartWire.VERSION` was. Bump it when any message layout or meaning changes, or when the RPC set changes.
- **Auth handshake (`HandshakeCodec`)**: the frozen 8-byte layout is kept unchanged: 4 ASCII bytes `DWKR` + s32 LE version. Longer packets stay accepted, so later versions may append. The host answers with its own version and calls `complete_auth` only on an exact match; on a mismatch it answers, then drops the peer after delivery (frozen `_refuse` pattern).
- **Coexistence:** a v9 frozen host reads `10`, logs "it runs version 10, this host 9" and refuses. A v10 host refuses a v9 client the same way. A v10 client facing a v9 host gets `handshake_failed(9)` and shows "different game version". **No interop, by design** (architecture API Boundaries). Both may use the same port; the refusal is the guard.
- **Per-packet version byte:** every snapshot packet starts with `VERSION & 0xFF`. After the handshake it can only differ through a bug (logged as an anomaly, packet dropped). It exists so stored snapshot streams (ghosts, ADR-0010; traces) are self-describing.

### 2. Snapshot record (VERSION 10)

One record per kart, **41 bytes**, little-endian. It is written by `SnapshotCodec` from a `KartSnapshot` plus the kart's lap (from `CourseProgress`, ADR-0004 §4), and it is the only place the snapshot is serialised (architecture API Boundaries).

| Off | Field | Type | Encoding | Source |
|---|---|---|---|---|
| 0 | `slot` | u8 | `RacerRegistry` slot | registry |
| 1 | `tick` | u32 | sender's sim tick of this snapshot; time = `tick × SIM_DT` race time | `KartSnapshot.tick` |
| 5 | `flags` | u8 | bit0 grounded, bit1 sinking, bit2 hop_airborne, bit3 position_clamped, bit4 reserved (0), **bits5-7 teleport epoch** (mod 8, §5) | snapshot + sender accumulators |
| 6 | `pos.x`, `pos.y`, `pos.z` | 3 × u24 | `q = clamp(roundi((p + 2048) × 4096), 0, 2²⁴−1)`; `p = q / 4096 − 2048` | `position` |
| 15 | `rot` | u32 | smallest-three quaternion: bits 30-31 index of the dropped largest component, 3 × 10-bit fields for the others in index order, each mapping [−1/√2, +1/√2] to [0, 1023] | `basis` → `Quaternion` |
| 19 | `vel.x`, `vel.y`, `vel.z` | 3 × f16 | IEEE half | `velocity` (**total world velocity**, ADR-0003 §7) |
| 25 | `speed` | f16 | IEEE half, signed (reverse) | `speed` |
| 27 | `drift_state` | u8 | value of `DriveState`'s drift int, asserted 0-255; its meaning is Driving & Drift's | `drift_state` |
| 28 | `boost` | u16 | remaining seconds × 1000, clamped 0-65535 | `boost` |
| 30 | `spin` | u16 | remaining seconds × 1000, clamped 0-65535 | `spin` |
| 32 | `steer` | s8 | `roundi(clamp(v, −1, 1) × 127)` | `steer` |
| 33 | `accel` | s8 | as `steer` (assumes [−1, 1], the throttle pass-through; see OQ-5) | `accel` |
| 34 | `surface_id` | u8 | asserted 0-255 (remote dust, splash and audio) | `surface_id` |
| 35 | `events` | u8 | OR of `KartSnapshot.events` low 8 bits over all ticks since the previous send (cosmetic; may be lost with a packet) | sender accumulator |
| 36 | `lap` | u8 | `CourseProgress.lap`, clamped 0-255 | Lap & Position input |
| 37 | `distance` | f32 | signed race distance, negative on the grid, continuous across laps (ADR-0004 §5) | `distance` |

**Not on the wire:** `support_id`, `air_time`, `land_airtime`, `land_impact`, `wall_angle`, `bump_strength`. The decoder sets them to 0 / −1. Finish is **not** in the snapshot (it is a reliable event, §4), unlike VERSION 9's `FINISHED` / `FINISH_TIME`.

**Quaternion canonical sign (ADR-0001 §8).** The encoder takes the quaternion from the just-orthonormalised basis and canonicalises it to w ≥ 0. For smallest-three it then negates the whole quaternion if the dropped component is negative; this is the same rotation. The decoder reconstructs the dropped component as `sqrt(max(0, 1 − a² − b² − c²))`, normalises, and **re-canonicalises to w ≥ 0**, so every decoded quaternion obeys ADR-0001 §8. `Basis(q)` is then built and used as is.

**Packet:** `[VERSION u8][count u8][count × 41-byte records]`. With 12 records that is 494 B, under one 1200 B safe MTU, so there is never fragmentation.

### 3. Quantisation error bounds

| Field | Step | Max error | Check against the ±2 km bound and use |
|---|---|---|---|
| position (u24, range [−2048, +2048) m) | 2⁻¹² m = 0.244 mm | **0.122 mm** per axis | Covers ±2000 m with 48 m spare. Equal to float32's own spacing at 2 km (2⁻¹²), so no precision is lost at the edge. Out of range: clamp, set `position_clamped`, log an anomaly (cannot happen on a valid track: import enforces ±2 km and fall-respawn fires long before). |
| orientation (smallest-three, 10 bits) | √2/1023 ≈ 1.38×10⁻³ per component | ≈ 0.14° (2·asin(√3 × 6.9×10⁻⁴)); test asserts < 0.2° | ≈ 2.4 mm at a 1 m half-length (the contact segment, ADR-0003 §7) |
| velocity, speed (f16) | relative 2⁻¹⁰ | ≤ 0.016 m/s below 64 m/s, ≤ 0.031 m/s to 128 m/s | Over the 0.25 s extrapolation cap: ≤ 8 mm. Range ±65504, so cannons fit |
| boost, spin (u16 ms) | 1 ms | 0.5 ms; saturates at 65.535 s | assumes remaining seconds (frozen `BOOST_TIME`/`SPIN_TIME` meaning; OQ-5) |
| steer, accel (snorm8) | 1/127 | 0.0039 | audio and visuals only |
| distance (f32) | 2⁻⁹ m at 16 km | ≈ 1 mm at 16 km | ADR-0004 §5's stated resolution |
| tick (u32) | exact | — | wraps after 2.27 years at 60 Hz |

### 4. Reliable events

**Channel plan** (all through `NetLink`, `SceneMultiplayer.server_relay = false`; every client message goes to the host, which routes it):

| Tier | Traffic | Mode / channel | Rate |
|---|---|---|---|
| P0 events | bump, item hit, hazard hit, finish | `reliable`, **channel 2** | bursts |
| P0 control | race config, ready, go, results, lobby, peer left | `reliable`, channel 0 | rare |
| P1 state | snapshot packets | `unreliable_ordered`, **channel 1** | `send_hz` 30 |
| P2 clock | ping / pong | `unreliable`, channel 0 | 1 / `ping_interval` (2 Hz) |

Events get their own reliable channel so a lobby or results burst never delays a bump behind ENet's per-channel reliable ordering, and the reverse. V2 must verify the channel.

**Envelope:** `rpc_event(bytes: PackedByteArray)`, encoded by `NetEventCodec` (pure, unit-tested): `[kind u8][payload]`. The tick is the sender's sim tick of origin.

| Kind | Payload | Size | Sender → route | Receiver rule |
|---|---|---|---|---|
| 1 BUMP | to_slot u8, from_slot u8, tick u32, impulse 3 × f16, strength f16 | 15 B | detecting PC → host → owner of `to_slot` (the host applies it itself for a bot) | `KartEvent` bump, applied at the **start of the owner's next tick** with max-merge dedup (ADR-0003 §7, §8) |
| 2 ITEM_HIT | seq u32, victim u8, blocked u8, tick u32, item_kind u8 | 12 B | victim's PC (victim-confirmed) → host → all | Items owns the payload's meaning; network only transports it |
| 3 HAZARD_HIT | slot u8, collider_id u32, outcome u8, tick u32 | 11 B | victim's PC (victim decides, architecture Hazards) → host → all | presentation, audio and spectate; the effect already ran on the victim's PC that tick, and the snapshot carries spin and sinking |
| 4 FINISH | slot u8, finish_time f64 (race seconds) | 10 B | owner (the host for bots) → host → all | Lap & Position orders finished karts by `finish_time`, ties by slot (ADR-0004 §5) |

- Item spawn and box-take messages (frozen `rpc_item_spawn`, `rpc_box_take`, `rpc_box_taken`) move into this envelope as kinds 5+ when the Items story defines them. Adding a kind bumps VERSION.
- An unknown kind is dropped and logged as an anomaly (rate-limited).
- Impulses are world-frame in the loaded, possibly mirrored frame (ADR-0001 §7), so no conversion.

### 5. Sending, batching and teleport epoch
- **Send ticks:** a slot simulated here is sent on ticks where `tick % send_every_ticks == 0`, with `send_every_ticks = 60 / send_hz` (= 2). At load, the code asserts that `send_hz` divides 60. If a catch-up call runs several ticks, at most **one** packet is sent per `_physics_process` call, carrying each slot's latest end-of-tick snapshot.
- **Accumulators per sent slot:** `events_or |= snap.events` every tick, cleared on send. `teleport_epoch = (teleport_epoch + 1) % 8` on every tick whose snapshot has `teleported` (respawn, launch, resync hold, `place`).
- **The teleport is an epoch, not a bit.** A teleport bit on one record is lost with that packet, and the next record would streak. A 3-bit counter survives any loss shorter than 8 teleports. The receiver treats a record as `teleported` **iff its epoch differs from the previous record it buffered for that slot.**
- **Clients** send one packet per send tick to the host (`rpc_id(1)`) with their own record(s).
- **The host owns bots** and sends one packet per client per send tick. It holds its own kart, every bot, and the newest **not-yet-forwarded** record of every other client, and leaves out the receiving client's own slot. Records keep their original `tick`. A forwarded client record therefore waits 0-33 ms at the host (16.7 ms on average). The adaptive view delay absorbs it.
- **Receivers** drop a record whose `tick` ≤ the newest buffered tick for that slot (duplicate or reordered).
- **Host-side checks:** it drops and logs any record or event for a slot whose `RacerRegistry` owner is not the sending peer (no spoofing of other karts), any non-finite f16 or f32, and any `tick` farther than `max_tick_skew` from the host's target tick. It *logs only* speeds above a plausibility band. The policy boundary is for security-engineer (OQ-4).

### 6. Handshake of the race: track identity, mirror, seed
`RaceConfig` (RefCounted, `encode()` / `decode()` through `StreamPeerBuffer`, unit-tested) travels reliably on channel 0, host → clients:

`version` (= VERSION) · `track_key` (package path) · `source_sha256` (64 hex) · `bake_key` (64 hex) · `mirror` (bool) · `race_seed` (s64, ADR-0001 §6) · `laps` (u8) · `go_tick` (u32, countdown length from Race Flow) · slot table (`slot`, `owner_peer`, racer id, vehicle id, `is_bot`).

**Start sequence:**
1. The host sends `RaceConfig`.
2. Each client loads the `TrackPackage`, applies `mirror` (ADR-0001 §7) and replies `race_ready(code)`:
   - 0 OK;
   - 1 TRACK_MISSING;
   - 2 SOURCE_MISMATCH (`package.source_sha256 ≠ config`);
   - 3 BAKE_MISMATCH (`package.bake_key ≠ config`);
   - 4 CLOCK_NOT_SYNCED (fewer than `clock_min_samples` after `race_ready_timeout`);
   - 5 LOAD_FAILED.

   A client replies OK only once it holds `clock_min_samples` clock samples.
3. After every client has replied, or `race_ready_timeout` has passed, the host sends `race_go(race_epoch, excluded_slots)`:
   - `race_epoch` = host session time now + `race_epoch_lead`;
   - a refused or silent client's slots are excluded from that race, and that client stays in the lobby with the reason shown (OQ-1).
4. **Race time** = synced session time − `race_epoch`. **Tick 0 is the grid tick** at race time 0. Racing starts at **`go_tick`**. Below race time 0 the sim steps no ticks (ADR-0001 "ahead of target: wait").
5. **Late joiners and spectators** get the same `RaceConfig` and `race_go`. Their target tick jumps to the current one. They own no kart, so nothing stalls.

**Deviation from the brief, flagged:** the brief names `source_sha256` + mirror + seed. This ADR also refuses on **`bake_key`**, because the same `.glb` baked by a different `CourseBuilder` gives different `distance` values and so a silently wrong ranking and broadphase. ADR-0005 states the intent "two PCs never race different builds of a track". Risk: a line-ending difference in a text `.tres` or `.json` input could make the keys differ on identical content (see Risks).

### 7. Clock sync (owned here per ADR-0001 §5)
- **Session clock.** The host's session time is its monotonic `Time.get_ticks_usec()` since the session opened. A client keeps an applied offset: `synced_session = local_usec / 1e6 + offset_applied`.
- **Samples.** Every `ping_interval` (0.5 s, lobby and race) the client sends its send time in µs. The host replies with that value and its session time as f64. On receipt:
  - `rtt = recv − send`;
  - `offset_i = host_t + rtt / 2 − recv_local`.

  `ClockSync` keeps the last `clock_sample_window` (16, ≈ 8 s) samples. **The estimate is the offset of the minimum-RTT sample in the window**, the one least inflated by queuing, so jitter does not move the clock.
- **Applying it** (each `_process`, real `dt`), with `err = estimate − offset_applied`:
  - |err| ≤ `clock_deadband` (2 ms): no change;
  - |err| > `clock_snap_threshold` (0.25 s): snap. If that leaves the sim behind, ADR-0001's catch-up and resync apply (teleport epoch bump); if ahead, the sim waits;
  - otherwise **slew**: `offset_applied += clamp(err, ±clock_slew_rate × dt)`, with `clock_slew_rate` = 0.02 s/s. A 50 ms error closes in 2.5 s. Because the rate is below 1, race time never runs backwards except on a snap.
- **The host** has offset 0; it is the clock authority.
- **Target tick** = `floor(race_time / SIM_DT)` (ADR-0001 §5), with `catch_up_ticks_max` = 3 and `resync_ticks` = 30 (0.5 s), both in `NetConfig`.
- **Error bound:** half the path asymmetry of the minimum-RTT sample. Symmetric paths are assumed; that is accepted for friends' home links.
- This replaces the frozen `lerp(race_time, host + rtt / 2, 0.15)` above a 20 ms threshold. That rule could step the clock backwards on every pong and followed the jitter of single samples.

### 8. RemoteKartView: buffer, interpolate, extrapolate, snap
- **One view per remote slot.** Each holds a **preallocated ring** of `snapshot_buffer_size` (40, ≈ 1.3 s at 30 Hz) decoded records (`NetKartRecord`: slot, lap, epoch, a `KartSnapshot`). There is no `Dictionary` per snapshot (the frozen view's habit).
- **Sample time:**
  - presentation: `synced_race_now − view_delay`;
  - simulation (contact, ADR-0003 §7): `n × SIM_DT − view_delay`.

  `view_delay` is **one value per receiving PC** (frozen behaviour, ADR-0001 §8): `clamp(late_avg + 2 × late_dev + 1 / send_hz, view_delay_min 0.05, view_delay_max 0.35)`, smoothed by `view_delay_smoothing`, where lateness = `synced_race_now − tick × SIM_DT` at arrival. The sim freezes the value once per tick, so every remote kart in a tick is sampled with the same delay.
- **Between records a, b** (a.t ≤ rt ≤ b.t):
  - position and velocity are lerped and orientation slerped (`Quaternion.slerp`);
  - `distance` is lerped;
  - `speed`, `steer` and `accel` are lerped;
  - discrete fields (flags, `drift_state`, `surface_id`, `lap`, `boost`, `spin`) are taken from a.
  - **If b is teleported** (epoch changed), the view **holds a until b.t, then snaps to b**: no lerp across the jump. The sampled `KartSnapshot.teleported` is true on the first sample at or after b.t.
- **Past the newest record:** position is extrapolated along the newest velocity for `min(rt − newest.t, max_extrapolation)` (0.25 s) and then held. Orientation is held (no angular velocity on the wire). **Remote karts never run collision queries.** The sample reports `extrapolated_for` seconds.
- **Before the oldest record:** the oldest is held. An empty buffer reports EMPTY, and the composition root leaves the kart undrawn and out of contact.
- **Ranking and broadphase** read the sampled `lap` and `distance` (ADR-0004 §5). Receivers never recompute remote progress.

### 9. NetMetrics (closes TD-010)
- **Prediction error** on each buffered record b after a: `|b.pos − (a.pos + a.vel × (b.t − a.t))|`. **Skipped when b's epoch differs from a's** (respawn, cannon, resync), and counted as `teleports` instead. TD-010 is closed by construction, and a lost flagged packet still cannot leak a teleport into the average.
- **Unflagged jump:** same epoch but `|b.pos − a.pos| > teleport_jump_speed × (b.t − a.t)` (120 m/s). It is still counted as error *and* logged as anomaly `unflagged_jump`. A sender that forgot to bump the epoch is found, not hidden. This replaces the frozen reach heuristic, which used per-vehicle stats.
- **Counters:**
  - RTT (smoothed, max) and clock `err` / `offset_applied`;
  - snapshots per second and extrapolated-frame percentage;
  - view delay;
  - bytes in and out per second, per channel tier;
  - decode failures and anomalies by kind.
- **Anomaly logging is rate-limited:** at most one line per kind per `anomaly_log_interval` (1 s), with the count since the last line. The frozen CSV net log and the `[net-summary]` line are ported with the new columns.

### 10. Disconnection
- **A client drops:** the host broadcasts `peer_left(peer, slots)` on channel 0. Views for those slots stop at the extrapolation cap and report STALE. Race Flow decides whether the kart is removed or parked (ported frozen behaviour; OQ-2).
- **The host drops:** the race ends for everyone. **There is no host migration** in v10: the host simulates the bots and the shared events.
- **Reconnect mid-race:** not supported. A returning player rejoins as a spectator through `race_go` (frozen v7 late-joiner rule).

### Sync parameters (all in `NetConfig`; new core instance `assets/data/core/net_config.tres`)

| Parameter | Value | Safe range | Sized by |
|---|---|---|---|
| `send_hz` (existing) | 30 | 15, 20, 30, 60 (must divide 60) | bandwidth below, ADR-0001 §8 |
| `view_delay_min` / `_max` (existing) | 0.05 / 0.35 s | 0.03-0.1 / 0.2-0.5 | 150 ms RTT: ≈ 75 ms one way + 17 ms host hold + 2σ jitter + 33 ms ≈ 0.16-0.2 s |
| `view_delay_smoothing` (existing) | 0.05 | 0.01-0.2 | frozen value |
| `max_extrapolation` (existing) | 0.25 s | 0.1-0.4 | ≈ 7 lost sends; position error ≤ v × t of a turning kart |
| `snapshot_buffer_size` (existing) | 40 | ≥ (view_delay_max + max_extrapolation) × send_hz + 4 | 1.3 s |
| `ping_interval` (existing) | 0.5 s | 0.25-2 | 16 samples in 8 s |
| `clock_sample_window` (**new**) | 16 | 4-64 | min-RTT filter span |
| `clock_min_samples` (**new**) | 4 | 1-16 | before `race_ready` OK |
| `clock_deadband` (**new**) | 0.002 s | 0-0.01 | below one tick's 16.7 ms |
| `clock_slew_rate` (**new**) | 0.02 s/s | 0.005-0.1 | invisible rate change; 50 ms in 2.5 s |
| `clock_snap_threshold` (**new**) | 0.25 s | 0.1-1.0 | above it, slewing takes too long |
| `catch_up_ticks_max` (**new**, named by ADR-0001) | 3 | 1-8 | 3 × 2 ms tick budget fits a frame |
| `resync_ticks` (**new**, named by ADR-0001) | 30 | 6-120 | 0.5 s behind: stall instead of a spiral |
| `race_ready_timeout` (**new**) | 10 s | 3-60 | track load on the minimum PC (unmeasured) |
| `race_epoch_lead` (**new**) | 1.0 s | ≥ 2 × rtt_max + 0.2 | `race_go` must arrive before race time 0 |
| `max_tick_skew` (**new**) | 120 ticks | 30-600 | 2 s: far beyond any real lateness |
| `teleport_jump_speed` (**new**) | 120 m/s | > top boosted speed × 1.5 | anomaly only |
| `anomaly_log_interval` (**new**) | 1.0 s | 0.5-10 | rate limit |

- **Kept for the frozen game, unread by the new core:** `clock_correct_threshold`, `clock_correct_rate`. Their meaning is unchanged.
- **Not applicable to an owner-authoritative model, stated so nobody adds them:**
  - reconciliation threshold and correction speed: there are no server corrections of an own kart;
  - input delay: 0;
  - the only cross-PC correction is a bump event.

### Bandwidth (payload exact; overhead estimated at ~60 B per packet, V5)

Record 41 B; client packet 2 + 41 = **43 B**; host-to-client packet with all 11 other karts 2 + 11 × 41 = **453 B**.

| Per player | Payload | With ~60 B overhead |
|---|---|---|
| Client upload (own kart) | 43 × 30 = 1.29 KB/s | 3.1 KB/s |
| Client download (11 karts) | 453 × 30 = 13.6 KB/s | **15.4 KB/s** |
| Host upload, 3 clients (4 humans + 8 bots) | 40.8 KB/s | 46 KB/s |
| Host upload, 11 clients (12 humans) | 149.5 KB/s | **169 KB/s ≈ 1.35 Mbit/s** |
| Clock pings, per client each way | ~0.05 KB/s | ~0.17 KB/s |
| Events | bursts of 10-15 B | negligible |

This is about half of `architecture.md`'s estimate (~84 B per kart, ~30 KB/s per client down, ~330 KB/s host upload before overhead). That line should be amended by its owner when this ADR is Accepted. **Relevancy culling is not needed at 12 karts.** If V5 or a stress run shows the host upload over budget, the first lever is sending karts far behind in `distance` at 15 Hz. That is not decided here.

### Architecture Diagram

```
 owner PC (client)                         host PC (owns bots, clock, routing)               other client
 tick n end-of-tick KartSnapshot ─┐        ┌─ own kart + 11 bots snapshots
 + CourseProgress.lap             │        │
 accumulators: events_or, epoch   │        │
 SnapshotCodec.write_record ──[43 B, ch1 unreliable_ordered]──▶ check owner/tick/finite ──▶ latest-unsent per slot
                                                                │
                                   per client, every send tick: [VER][n][≤11 × 41 B] ─ch1─▶ SnapshotCodec.read ─▶ RemoteKartView ring
                                                                                                    │ sample at now − view_delay (draw)
 KartContactSolver ─ bump ─▶ NetEventCodec [ch2 reliable] ─▶ host route ─▶ owner of to_slot ─▶ KartEvent at its tick n+1
 victim PC ─ ITEM_HIT / HAZARD_HIT, owner ─ FINISH ─▶ host ─▶ all [ch2 reliable]
 ping(µs) ─ch0 unreliable─▶ host pong(µs, host_t) ─▶ ClockSync (min-RTT of 16, slew 2%) ─▶ RaceClock ─▶ target tick = floor((S − epoch)/SIM_DT)
 RaceConfig(track sha256 + bake_key, mirror, seed, go_tick, slots) ─ch0─▶ race_ready(code) ─▶ race_go(epoch, excluded)
 NetMetrics: pred error skipped when epoch changes (TD-010) · anomalies rate-limited · bytes per tier
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
## Writes the packet header for count records; returns the offset of the first record.
static func write_header(buf: PackedByteArray, count: int) -> int
## Writes one record at offset; returns the next offset. buf is preallocated by the caller.
static func write_record(buf: PackedByteArray, offset: int, slot: int, snap: KartSnapshot,
        lap: int, events_or: int, teleport_epoch: int) -> int
## Returns the record count, or -1 (wrong version, short or inconsistent length).
static func read_header(buf: PackedByteArray) -> int
## Decodes one record into out (preallocated); false on non-finite fields.
static func read_record(buf: PackedByteArray, offset: int, out: NetKartRecord) -> bool
static func encode_rotation(b: Basis) -> int     ## smallest-three, canonical w >= 0 in
static func decode_rotation(bits: int) -> Quaternion   ## canonical w >= 0 out

class_name NetKartRecord extends RefCounted      ## one decoded record
var slot: int; var lap: int; var teleport_epoch: int; var position_clamped: bool
var snap: KartSnapshot                           ## tick, position, basis, velocity, ..., distance

class_name NetEventCodec extends RefCounted
enum Kind { BUMP = 1, ITEM_HIT = 2, HAZARD_HIT = 3, FINISH = 4 }
static func encode_bump(e: KartEvent, tick: int) -> PackedByteArray
static func encode_hazard_hit(slot: int, collider_id: int, outcome: int, tick: int) -> PackedByteArray
static func encode_item_hit(seq: int, victim: int, blocked: bool, tick: int, item_kind: int) -> PackedByteArray
static func encode_finish(slot: int, finish_time: float) -> PackedByteArray
static func kind_of(bytes: PackedByteArray) -> int            ## -1 if empty or unknown
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
## 0 OK, 1 TRACK_MISSING, 2 SOURCE_MISMATCH, 3 BAKE_MISMATCH (4, 5 come from NetLink)
func check_package(pkg: TrackPackage) -> int

class_name ClockSync extends RefCounted          ## pure; times injected for tests
func _init(config: NetConfig) -> void
func add_sample(send_usec: int, recv_usec: int, host_time: float) -> void
func step(dt: float) -> void                     ## slew / snap toward the min-RTT estimate
func synced_session_time(local_usec: int) -> float
func sample_count() -> int
var last_error: float                            ## estimate - applied, for NetMetrics

class_name RemoteKartView extends RefCounted
enum SampleState { EMPTY, INTERPOLATED, EXTRAPOLATED, HELD, STALE }
func _init(slot: int, config: NetConfig, metrics: NetMetrics) -> void
func push(rec: NetKartRecord, synced_now: float) -> void       ## copies into the ring; epoch → teleported
func sample(t: float, out: KartSnapshot) -> SampleState         ## t already minus view_delay
func lap_at(t: float) -> int
var extrapolated_for: float
func clear() -> void

class_name RemoteKartSet extends RefCounted      ## what ADR-0003's tick calls remote_views
func sample_into(snaps: Array[KartSnapshot], t: float, out_state: PackedByteArray) -> void

class_name NetMetrics extends RefCounted
var view_delay: float; var rtt: float
func record_arrival(lateness: float) -> void
func record_prediction(a: NetKartRecord, b: NetKartRecord) -> void   ## skips a changed epoch (TD-010)
func record_frame(state: int) -> void
func record_rtt(sample: float) -> void
func record_bytes(tier: int, bytes: int, outgoing: bool) -> void
func anomaly(kind: StringName) -> void                                ## rate-limited log
func close_window() -> Dictionary

class_name NetLink extends Node                  ## the only Node; owns SceneMultiplayer, RPCs, routing
signal handshake_failed(host_version: int)
signal race_config_received(cfg: RaceConfig)
signal race_go_received(race_epoch: float, excluded: PackedByteArray)
signal snapshot_packet(bytes: PackedByteArray, from_peer: int)
signal event_received(bytes: PackedByteArray, from_peer: int)
signal peer_left(peer: int, slots: PackedByteArray)
func host(config: NetConfig) -> Error
func join(address: String, config: NetConfig) -> Error
func send_snapshots(bytes: PackedByteArray, to_peer: int) -> void    ## ch1 unreliable_ordered
func send_event(bytes: PackedByteArray, to_peer: int) -> void        ## ch2 reliable
```

### Implementation Guidelines
- `SnapshotCodec` **must** be the only code that serialises a `KartSnapshot`. Kart Physics **must never** reference `src/networking/`.
- Every message layout or meaning change **must** bump `SnapshotCodec.VERSION`. The handshake **must** refuse any version other than its own, with a message on both sides.
- New code **must never** reuse the frozen `class_name`s (`KartWire`, `NetHandshake`, `NetSession`, `RemoteKart`, `NetStats`) and **must not** reference `src/legacy/`.
- Wire quaternions **must** be taken from a just-orthonormalised basis, and decoded quaternions **must** be re-canonicalised to w ≥ 0.
- Positions outside ±2048 m **must** be clamped, flagged and logged, never wrapped.
- A teleport **must** be signalled by bumping the 3-bit epoch. Receivers **must** detect it as an epoch change, never from a single-record bit or a distance heuristic.
- `NetMetrics` **must never** count a record whose epoch changed as prediction error.
- Remote karts **must never** run collision queries. Extrapolation **must** stop at `max_extrapolation`.
- The sim **must** sample remote karts at `n × SIM_DT − view_delay`, with one `view_delay` value frozen per tick.
- Snapshots **must** go on channel 1 `unreliable_ordered`; gameplay events **must** go on channel 2 `reliable`; control **must** stay on channel 0.
- `server_relay` **must** be false. Clients **must** send only to the host, and the host **must** drop records and events for slots the sender does not own.
- Received bumps **must** apply at the start of the owner's next tick, through `KartBody.apply_event` (ADR-0003).
- A client **must not** reply `race_ready` OK unless `source_sha256` and `bake_key` match and `clock_min_samples` are held.
- Race time **must** be `synced_session − race_epoch`. Simulation code **must never** read the continuous clock inside a tick (ADR-0001 §5).
- Every sync parameter **must** come from `NetConfig`. `NetConfig` **must** change only additively.
- Anomaly logs **must** be rate-limited per kind.
- Per-tick and per-frame paths **must not** allocate a `Dictionary` or `Array` per snapshot. Rings and records are preallocated.

## Alternatives Considered

### Alternative 1: Extend the VERSION 9 float array to 3D
- **Description:** keep the `PackedFloat32Array`, one RPC per kart. Add `y`, `vy`, a full quaternion and velocity: about 30 floats = 120 B per kart.
- **Pros:** smallest code change; matches the frozen code's shape.
- **Cons:** about 3× the bytes. No stated error bounds. One RPC per kart multiplies the packet count, and so the ~60 B overhead, by up to 11.
- **Rejection Reason:** bandwidth and packet count. The frozen relay pattern is the main cost at 12 humans.

### Alternative 2: Batched, but unquantised float32 fields
- **Description:** the same batching, but `Vector3` and `Quaternion` as raw float32: about 64 B per record.
- **Pros:** no quantisation code; bit-exact to the sender's float32.
- **Cons:** about 1.6× the bytes: host upload ≈ 264 KB/s payload for 12 humans.
- **Rejection Reason:** the 24-bit position already equals float32 spacing at the ±2 km edge, and 0.14° orientation is far below visual or contact relevance. Quantisation costs one tested codec and halves host upload. **This is the fallback** if a quantisation bug is found late (VERSION bump only).

### Alternative 3: SceneMultiplayer server relay of client packets
- **Description:** clients broadcast. The host relays each packet to every other peer as it arrives.
- **Pros:** no host hold (saves 0-33 ms on client-to-client karts); simpler host.
- **Cons:** 12 humans → 11 × 11 packets per send instead of 11, so ~1.6× host upload with overhead. Spoofed-slot checks need custom relay hooks anyway.
- **Rejection Reason:** packet count and validation. The hold is inside the adaptive view delay.

### Alternative 4: Input lockstep or rollback
- **Description:** send inputs; every PC simulates every kart.
- **Pros:** tiny packets; consistent contacts.
- **Cons:** needs cross-machine bit-exactness, which ADR-0001 §6 explicitly does not provide. Rollback is suited to frame-exact genres (fighting), and a kart racer tolerates interpolation.
- **Rejection Reason:** contradicts ADR-0001 §6 and the proven owner-authoritative model.

### Alternative 5: Delta compression against an acknowledged baseline
- **Description:** send changed fields relative to the last acked record.
- **Pros:** maybe 40-60% fewer bytes.
- **Cons:** needs an ack stream over unreliable delivery and per-peer baselines, so it is harder to test.
- **Rejection Reason:** 41 B is already small. Deferred until a measurement says otherwise.

### Alternative 6: `MultiplayerSynchronizer` / `MultiplayerSpawner`
- **Description:** engine property replication of nodes.
- **Pros:** less hand-written code.
- **Cons:** sim objects are `RefCounted`, not nodes (ADR-0001 §8, ADR-0003). It gives no control over quantisation, tick stamping or batching, and the 4.8 behaviour is unsourced.
- **Rejection Reason:** incompatible with the `RefCounted` core.

### Alternative 7: Per-owner view delay
- **Description:** a separate adaptive delay per source peer, so host karts (bots) are drawn closer to live.
- **Pros:** about 17-50 ms less delay on bots.
- **Cons:** remote karts from different owners are drawn at different time offsets. ADR-0003's sample call assumes one delay.
- **Rejection Reason:** deferred. Revisit after A2 measurements.

## Consequences

### Positive
- About half the bandwidth of the earlier estimate, a single packet per peer per send, and no fragmentation.
- Error bounds are stated and unit-testable. Quaternions are canonical on both ends.
- TD-010 is closed by construction, and a lost teleport packet cannot streak or pollute metrics.
- The track build, mirror state and seed can never silently differ between PCs.
- The clock no longer follows single-sample jitter and never steps backwards outside a snap.
- Codecs, clock, views and metrics are pure `RefCounted` classes, so they can be unit-tested without a network.

### Negative
- Client-to-client karts get 0-33 ms extra delay from the host hold.
- The host is a single point of failure (no migration), and its upload grows linearly with clients.
- The codec is more code than a float array, and its bugs would be subtle. Mitigated by round-trip tests.
- Event bits and landing magnitudes are lossy for remote karts (cosmetic).
- A `bake_key` refusal may annoy developers on mismatched dev builds.

## Risks
- **Engine API drift (HIGH knowledge risk):** `encode_half`, channel 2 and `server_relay` behaviour on 4.8-beta3 are unverified (V1-V3). Mitigation: a 30-minute probe before the codec story, the godot-specialist review of this draft, and Alternative 2 if `encode_half` is missing.
- **`bake_key` false refusals:** `bake_key` hashes text inputs, so a line-ending difference (git `autocrlf`) between machines could make the keys differ on identical content. Mitigation: devops-engineer pins `eol=lf` for `.tres` / `.json` / `.gd` in `.gitattributes`, and friends sessions use one exported build. If it still bites, fall back to refusing on `source_sha256` only and logging `bake_key` (OQ-6).
- **Overhead estimate wrong (V5):** if the real overhead is far above 60 B, the host-upload figures move. Mitigation: `NetMetrics` per-tier byte counters, and the 15 Hz far-kart lever.
- **Clock asymmetry:** asymmetric routes bias the offset by half the asymmetry. Mitigation: the min-RTT filter, and the view delay absorbs a constant bias. Logged as `clock err`.
- **False bumps against an extrapolated remote kart:** an extrapolated pose may collide where the real kart is not. Mitigation: OQ-3 proposes ignoring remote karts extrapolated beyond 0.1 s in contact.
- **Owner trust:** a modified client can report any state or finish time. Accepted for friends-only play; the host's slot-ownership, finiteness and tick-skew checks limit spoofing. Anything stronger is for security-engineer (OQ-4).
- **Unknown field meanings:** `drift_state`, `boost`, `spin` and `accel` units are assumed (OQ-5). A different meaning changes the encoding and bumps VERSION before release.

## GDD Requirements Addressed

No system GDDs exist (`architecture.md` ADR Audit: TR baseline deferred). Rows cited from `design/gdd/systems-index.md`:

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| systems-index.md row 4, Network Session & Sync | "migrate: 3D snapshot, wire version bump"; summary line 131 "host/join, owner-authoritative karts, wire format" | §1 VERSION 10 and refusal; §2 3D record; owner-authoritative routing §5 |
| systems-index.md High-Risk table, "Network wire migration" | 3D state (position, velocity, basis, grounded) needs a new snapshot and a version bump | §2 carries position, quaternion, total velocity and the grounded flag; §1 bumps to 10 |
| systems-index.md Seams (lines 185-187) | the snapshot contract carries inbound events (bump impulses, item hits) as well as outbound state | §4 BUMP and ITEM_HIT on reliable channel 2 |
| systems-index.md Circular Dependencies (lines 241-245) | Kart Physics owns the state and knows nothing of the network; Network Sync reads and writes it through a snapshot contract | `SnapshotCodec` reads and writes `KartSnapshot`; Core never references `src/networking/` |
| systems-index.md row 8, Race Session & Synced Clock | shared synced race clock | §7 min-RTT slewed clock, race epoch and target tick; §6 start tick |
| systems-index.md row 11, Lap & Position Tracking | ranking across PCs | wire `lap` u8 + `distance` f32 (§2); FINISH event with race time (§4) |
| systems-index.md row 14, Track Hazards | hits decided on the victim's PC; effects pure functions of the clock | HAZARD_HIT sent by the victim (§4); a shared clock (§7) keeps hazard phases aligned |
| systems-index.md row 15, Items & Item Boxes | depends on Network Session & Sync; victim-confirmed hits | ITEM_HIT envelope (§4); further item kinds join the same envelope |
| systems-index.md row 17, Race Flow & Lobby | post-finish spectating, late joiners | §6 late joiner and spectator via `race_go`; §10 disconnect contract |
| systems-index.md row 36, Room Codes & Relay | depends on Network Session & Sync | network-side contract for ADR-0008: one UDP port (`NetConfig.port`), ENet, 30 Hz, bandwidth table |
| systems-index.md row 41, Spectate & Broadcast | reads the item event stream | ITEM_HIT, HAZARD_HIT and FINISH broadcast to all (§4) |

## Performance Implications
- **CPU:**
  - Encode 12 records + decode 11 per send tick: an estimated ≤ 0.05 ms p95 on the owner's PC (unmeasured). This fits the "race logic, lap/progress, net send" 0.15 ms row of `architecture.md`.
  - Remote sampling for 11 karts per tick (contact) and per frame (draw): ring search O(1) amortised from the last index, estimated ≤ 0.05 ms. This is part of the kart-visuals 0.5 ms frame row.
- **Memory:** 11 views × 40 records × (~200 B `KartSnapshot` + record) ≈ 100 KB, preallocated. Packet buffers are preallocated at 494 B.
- **Load Time:** none. `RaceConfig.check_package` compares two strings.
- **Network:** see the bandwidth table. Client ≈ 15.4 KB/s down and 3.1 KB/s up. Host up ≈ 46 KB/s with 3 clients and ≈ 169 KB/s with 11 (≈ 1.35 Mbit/s).

## Migration Plan
1. **Probe (before code):** V1-V3 on 4.8-beta3 in a scratch project. Record the results in this ADR's Engine Compatibility.
2. **Story 025 network sub-story, test-first** in `src/networking/`:
   - write the codecs, `RaceConfig`, `ClockSync`, `RemoteKartView` / `RemoteKartSet` and `NetMetrics` with unit tests;
   - then `NetLink`, porting the frozen `NetSession`'s host/join/auth/fake-network queue and adding channel 2, `server_relay = false` and host aggregation.
3. **`NetConfig`:** add the new fields with defaults and `##` comments, additively. Fork `assets/data/core/net_config.tres` from the frozen instance, plus the new values.
4. **Composition root:**
   - wire `ClockSync` → `RaceClock` → target tick;
   - send on send ticks;
   - call `RemoteKartSet.sample_into` in the ADR-0003 tick order.
5. **Frozen game:** untouched. VERSION 9 stays in `src/legacy/net/`. Run the coexistence check (V4) once.
6. **Follow-ups for other owners:**
   - amend `architecture.md`'s bandwidth line to this ADR's table;
   - ADR-0003 amendment if OQ-3 is accepted;
   - Items story defines kinds 5+;
   - devops-engineer: `.gitattributes` for `bake_key` stability.

## Validation Criteria
1. **Codec unit tests** (`tests/unit/networking/`):
   - record size is 41 and header size is 2;
   - position round-trip error ≤ 0.123 mm over a grid including ±2000 m and both range edges;
   - clamp sets `position_clamped`;
   - 10,000 seeded random quaternions decode within 0.2° with w ≥ 0;
   - f16 fields are within half-ulp; u16 and snorm8 bounds hold;
   - a wrong version byte or a short buffer gives −1.
2. **Event codec tests:** every kind round-trips; an unknown kind gives −1.
3. **ClockSync test** (injected times, seeded jitter):
   - at 150 ms RTT ± 30 ms jitter and 5% loss, |err| < 5 ms within 8 s;
   - race time is monotonic under slew;
   - a 0.5 s step snaps.
4. **RemoteKartView tests:**
   - interpolation midpoint;
   - extrapolation stops at 0.25 s;
   - an epoch change holds-then-snaps even when the flagged record was dropped;
   - duplicates and older ticks are ignored.
5. **NetMetrics TD-010 test:** a respawn sequence produces no prediction-error sample and one `teleports` count; an unflagged 30 m jump produces one rate-limited `unflagged_jump` anomaly.
6. **RaceConfig tests:** encode/decode round-trip; `check_package` returns 2 and 3 on the respective mismatches.
7. **Integration** (`tests/integration/networking/`, two ENet peers on localhost): handshake v10/v10 passes, and v10 against a constant v9 packet is refused. Race start with a `bake_key` mismatch excludes that client.
8. **Coexistence (V4):** frozen host + new client, and the reverse, both refuse with a message. Log retained in `production/qa/evidence/`.
9. **Online run at A2** (4 PCs or the net_stress harness, 150 ms / 30 ms / 5% fake network):
   - extrapolated frames < 5%;
   - view delay ≤ 0.25 s;
   - `NetMetrics` client download ≤ 18 KB/s, and host upload within ±25% of the table;
   - a moat respawn draws as a snap, not a streak. Screenshot / capture retained in `production/qa/evidence/`.

## Open Questions

| ID | Question | Owner |
|---|---|---|
| OQ-1 | A client refused at race start (track missing or mismatched): exclude it from that race and keep it in the lobby (this draft), or abort the race for everyone? | game-designer / owner |
| OQ-2 | A client that disconnects mid-race: its kart is removed, parked, or taken over by a bot? | game-designer (Race Flow) |
| OQ-3 | Exclude a remote kart from contact when it has been extrapolated longer than `contact_extrapolation_max` (proposed 0.1 s)? Needs a contact-eligible mask in ADR-0003's `resolve_all` | lead-programmer / ADR-0003 owner |
| OQ-4 | Validation boundary under owner authority: are log-only speed and finish plausibility checks enough for friends play, or should the host reject outside a tolerance band (for example speed > 1.5 × boosted top speed for more than 3 records)? | security-engineer; technical-director if unresolved |
| OQ-5 | Confirm the meanings of `drift_state` (fits a u8?), `boost` and `spin` (remaining seconds?) and `accel` (throttle in [−1, 1] or m/s²?) from Driving & Drift | gameplay-programmer |
| OQ-6 | Keep the `bake_key` refusal (this draft, beyond the brief) or refuse on `source_sha256` only? | owner / technical-director |
| OQ-7 | No project latency target was found; this draft is sized for 150 ms RTT. Confirm or state one | owner / technical-director |

## Related
- **Depends on** ADR-0001 (clock §5, determinism §6, mirror §7, interpolation §8, names §9), ADR-0003 (`KartSnapshot`, `KartEvent`, contact §7, events §8), ADR-0004 (lap and distance wire meaning §5), ADR-0005 (`source_sha256`, `bake_key`, §6).
- **Supersedes for the new core** (does not modify) the frozen `src/legacy/net/kart_wire.gd` (VERSION 9), `net_handshake.gd`, `net_session.gd`, `remote_kart.gd` and `net_stats.gd`. The frozen game keeps them unchanged.
- **Enables** ADR-0008 (room codes and relay) and ADR-0010 (ghost format).
- `docs/architecture/architecture.md`: Data Flow 2-3, API Boundaries, Performance Budgets (the bandwidth line to amend).
- `design/gdd/systems-index.md` rows 4, 8, 11, 14, 15, 17, 36, 41, the Seams list and the High-Risk table.
- TD-010 (respawn teleports counted as prediction error): closed by §5 and §9 when implemented.
