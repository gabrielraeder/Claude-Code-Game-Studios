<!-- PROTOTYPE - NOT FOR PRODUCTION -->
<!-- Question: Can 2+ PCs race smoothly over host/join with owner-authoritative karts? -->
<!-- Date: 2026-11-19 -->

# Kart racer: prototype 2 (online test)

**Status:** concluded for the technical question. Verdict: **PROCEED** on 2026-11-19. The feel test with two humans is still open.

## Question

Can 2+ PCs race smoothly over **host/join, peer to peer** with no game server? Signals:

- Remote karts move smoothly. The game rarely has to guess ahead (extrapolate), and when a new
  update arrives the kart doesn't visibly jump.
- Item hits across the network feel fair.
- Both PCs agree on the race: positions, finish order and lead changes.

## How it works (the model under test)

- **Host and join:** one player hosts (UDP port 24680) and the others join by IP. On the internet
  without opening router ports, use Tailscale or ZeroTier and join the host's 100.x / virtual IP.
  The host also owns the bots.
- **Owner-authoritative:**
  - Each PC simulates only its own karts and sends their state 30 times a second.
  - Other karts are drawn slightly in the past, interpolated between updates.
  - The **view delay adapts** to the connection: one-way delay plus jitter plus one send interval.
- **Items:**
  - The firer spawns the item and announces it, and every PC simulates it.
  - **Only the victim's PC decides a hit.** Nobody spins out from something they saw miss.
  - Item boxes: whoever takes one announces it.
- **Fake bad network:** `--lag=ms` (added one-way delay on this PC's sends), `--jitter=ms` and
  `--loss=%`. Loss applies to position updates only; items and hits are always delivered.

## How to run

- **Host:** double-click `play_host.bat`. Windows may ask about the firewall: allow it on Private
  networks. Your IP is shown on screen.
- **Join:** double-click `play_join.bat` and type the host's IP.
- The race starts when 2 players are in, or the host presses Enter. After the race, the host
  presses Enter or R for a rematch.

Debug arguments go after `--`:

- `--autopilot`: your kart drives itself.
- `--players=N`: how many players to wait for.
- `--bots=N`: how many bots.
- `--quit-after-race`: close after the race.
- `--shots=DIR`: take screenshots.
- `--netlog=PATH`: write the network log.
- `--lag`, `--jitter` and `--loss`: fake bad network, as above.

Each PC writes `net_log_<role>.csv` once a second, with:

- round-trip time
- updates received per second
- % of frames extrapolated
- prediction error

It prints a `[net-summary]` line at the end of a race.

## Results so far

**Same PC, 2 copies, autopilot, 2 players + 2 bots, 2026-11-19:**

| Fake network on the client | RTT avg | View delay | Extrapolated frames (host / client) | Prediction error avg / max | Lead changes (host / client) |
|---|---|---|---|---|---|
| 60 ms delay, 20 ms jitter, 2% loss | 85 ms | 100 ms (fixed) | 4.3% / 0.5% | 0.01 m / 0.6 m | 10 / 23 *(ranking bug)* |
| 100 ms delay, 40 ms jitter, 5% loss | 134 ms | 100 ms (fixed) | 28.9% / 21.9% | 0.01 m / 0.46 m | 179 / 31 *(ranking bug)* |
| 100 ms delay, 40 ms jitter, 5% loss | 134 ms | **adaptive: 120 / 94 ms** | **5.8% / 6.8%** | 0.01 m / 0.53 m | **9 / 9** |

**Fixes made from the tests:**

- **Fixed view delay → adaptive.** With 100 ms of delay, the fixed 100 ms view delay ran dry and
  the game guessed ahead on 29% of frames.
- **Remote karts are ranked by where they are now.** Remote progress is projected forward by
  speed and age before ranking, and lead changes are debounced.
  - This was a real gameplay bug: remote karts were ranked from older data than local ones, so
    the shown position flickered.
- **The test harness waits for every human to finish** before closing.

**Two real PCs, 2026-11-19:**

- **Machines:** this PC hosts, with a window. The laptop (`Work_laptop`) joins over home Wi-Fi/LAN,
  headless with the autopilot, started over SSH.
- **Race:** 2 players + 2 bots.
- **Logs:** `logs/host_lan*.csv` and `logs/client_lan*.csv`.

| Network | RTT avg (client) | View delay host / client | Extrapolated frames host / client | Prediction error avg / max | Lead changes host / client |
|---|---|---|---|---|---|
| Real LAN, no fake lag | 14 ms | 50 / 63 ms | 1.6% / 1.5% | 0.01 m / 0.29 m | 7 / 7 |
| Real LAN + fake internet **both ways** (80 ms, 30 ms jitter, 3% loss each side) | 216 ms | 146 / 166 ms | 6.4% / 7.1% | 0.01 m / 0.40 m | 9 / 9 |

- Items hit in both directions in both runs, and no errors were logged.
- The host's RTT column shows ENet's real round trip (about 20 ms). It does not include the fake
  delay, which is added inside the game.

## Findings

- **Verdict: PROCEED.** Peer-hosted, owner-authoritative online play holds up technically:
  - Two real PCs agree on the race.
  - Remote karts are drawn from real data at least 93% of the time, even at about 216 ms round trip.
  - Corrections average about 1 cm, at most 40 cm.
- **Carry into the production design:**
  - Each PC owns and simulates its own karts. Remote karts are interpolated.
  - The **view delay adapts** to the measured lateness plus jitter.
  - **The victim decides item hits.**
  - **Remote progress is projected to "now" before ranking.** Without this, the shown positions
    flicker. This was found in testing.
  - The race clock syncs to the host's clock through ping/pong.
- **Still open:**
  - **Feel:** two humans driving. Does a 150 ms view delay make bumping and item aim feel unfair?
  - **The real internet**, through Tailscale/ZeroTier or Steam relay. NAT traversal is unproven.
    Only LAN plus fake lag was tested.
  - **Cheating:** owner-authoritative trusts each client. That's fine for friends, but not for
    strangers.
  - **Host migration** when the host leaves.
