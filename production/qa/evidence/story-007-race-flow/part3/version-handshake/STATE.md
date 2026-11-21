# Story 007 part 3: version handshake (old-build refusal): STATE

Step 0 DONE (2026-11-20): inputs read (net_session.gd host/join/_open, kart_wire, net_config(.tres), net_options,
main.gd net wiring 231-248, _begin_joining, _on_connected_to_host, _leave_network, in-payload checks 960/1421),
old-build-refusal logs (host_v7 42 ERROR, client_v3 1378 ERROR), engine reference
(docs/engine-reference/godot/modules/networking.md: no MultiplayerAPI change listed for 4.5-4.8, marked NOT SOURCEABLE for 4.8).

Step 1 DONE: engine probe in the scratchpad (throwaway project authprobe/, port 24690, not in the repo), Godot 4.8-beta3:
 - SceneMultiplayer has auth_callback / auth_timeout / send_auth / complete_auth / peer_authenticating / peer_authentication_failed.
 - host v8 + client v8 (both with auth): handshake in about 10 ms, then peer_connected / connected_to_server, RPC works. 0 ERROR both.
 - host v9 + client v8: host send_auth(reply) then ENetPacketPeer.peer_disconnect_later(): the client gets the reply
   (sees host v9) BEFORE the disconnect; host gets peer_authentication_failed, never peer_connected. 0 ERROR both.
 - host with auth + client WITHOUT auth (what an old build is): host gets peer_authenticating, then peer_authentication_failed
   after exactly auth_timeout (3 s), never peer_connected. BUT the engine prints one ERROR per non-auth packet the
   old client sends while pending (verbatim):
     ERROR: Condition "len < 2 || (packet[0] & CMD_MASK) != NETWORK_COMMAND_SYS || packet[1] != SYS_COMMAND_AUTH" is true. Continuing.
        at: poll (modules/multiplayer/scene_multiplayer.cpp:97)
   Game code cannot see or drop those packets (they are read inside SceneMultiplayer.poll). Count scales with what the old
   client sends in auth_timeout seconds (the probe spammed 200 RPCs -> 200 lines; a real v3 client sends a loadout plus
   2 pings/s, so expect roughly 5-15 lines). The client without auth printed 0 ERROR (it believes it is connected until dropped).
 - Client side: while the host is still pending, MultiplayerPeer status is already CONNECTED, so NetSession._is_connected()
   would let rpc_ping go out to a not-yet-admitted host. The fix must also require multiplayer.get_peers().has(1) on clients.

Step 2 BLOCKED ON APPROVAL: the change edits existing source and config, which the agent's protocol does not allow
without the user's own yes. Draft returned to the caller. Files to change:
 - NEW src/net/net_handshake.gd (NetHandshake: encode/decode of "DWKR" + s32 version, 8 bytes)
 - src/net/net_session.gd (auth callback, peer_authenticating / peer_authentication_failed handlers, handshake_failed
   signal, advertised_version, refusal via peer_disconnect_later, _is_connected gate on admission, host_lost suppressed after a failed check)
 - src/net/net_config.gd + assets/data/net/net_config.tres (auth_timeout = 3.0)
 - src/net/net_options.gd (--net-version-override=N)
 - src/net/kart_wire.gd (VERSION 7 -> 8 + history line)
 - src/main.gd (apply override after _net.setup, connect handshake_failed -> _leave_network(message))

Verify plan once approved (sequential, port 24690, logs here):
 1. match/: host  $G --headless --path . -- --host --port=24690 --players=2 --bots=2 --laps=1 --autopilot --quit-after=40
           client $G --headless --path . -- --join=127.0.0.1:24690 --autopilot --quit-after=35   (start 1 s later)
 2. old-client/: same host; client $G --headless --path c:/writechoice/ccgs-baseline -- --join=127.0.0.1:24690 --autopilot --quit-after=35
 3. host-mismatch/: host with --net-version-override=99 --players=2; current client: expect the mismatch message, host keeps racing.
 4. bot_race/ (QUIT=60 SCALE=4 bash tools/bot_race_test.sh <dir> castle_circuit 11 1 1), item_net/ (bash tools/item_net_test.sh <dir> castle_circuit 1),
    spectate/ (host --players=2 --bots=2 --laps=2, client1 at +1 s, client2 --join at about +10 s into the race).
 5. parse check of each changed .gd.

Step 2 DONE (2026-11-21, user approval relayed by the coordinator: "Sim, aplicar"): code written as drafted
(net_handshake.gd new; net_session, net_config(.gd/.tres auth_timeout 3.0), net_options --net-version-override, kart_wire VERSION 8, main).
--import ok; parse check of the 6 scripts exit 0 (parse_check.log). Runner: scratchpad pair.sh (host repo, client --path X).
Verify 1 DONE (match/): handshake logged on host, race start 4 karts on both, items exchanged; host 0 ERROR 0 WARNING, client 0 ERROR 0 WARNING.
Verify 2 (old-client/): IN PROGRESS
Verify 2 DONE: three runs, old client = ccgs-baseline (v3), all host ERROR lines are the engine's scene_multiplayer.cpp:97 line, 0 from game code, 0 WARNING:
 - old-client/ (host --players=2): host 7 ERROR; "[net] dropped peer N: no version check within 3.0 s"; host never lists it, keeps waiting in the lobby (players=2). Old client 0 ERROR, prints "[net] leaving network: Lost the connection to the host." and exits at its quit-after.
 - old-client-solo-host/ (host --players=1, racing; old client joins 3 s later): host 7 ERROR (same line), race goes on alone with 2 bots (items to t=33 s), no spectator added. Old client 0 ERROR, same leave line.
 - old-client-lobby/ (host --players=2, old client at +1 s, current client at +6 s): old one dropped after 3.0 s, race starts with 4 karts (host + current client + 2 bots). host 7 ERROR (engine line), old 0, current 0.
Verify 3 (host-mismatch/): IN PROGRESS
Verify 3 DONE (host-mismatch/): host --players=1 --net-version-override=99 racing with 2 bots; current client joins at +3 s.
 Host: "[net] refused peer N: it runs version 8, this host 99", race goes on (17 item events), 0 ERROR 0 WARNING.
 Client: "[net] version check failed: host 99, this build 8" then "[net] leaving network: The host runs a different version of the game (host v99, you v8). Update to the same build." (-> _show_main_menu(message)); 0 ERROR 0 WARNING.
 No screenshot of the menu message: no debug hook saves a picture after leaving the network (would need a new debug option).
Verify 3b (old-host/, extra): baseline v3 host + current client: IN PROGRESS
Verify 3b DONE (old-host/): v3 host + current client: client drops after 3.0 s with "The host did not answer the version check; it may run an older build of the game (you v8). Update to the same build."; client 137 ERROR, all the engine line scene_multiplayer.cpp:97 (old host's 30 Hz state packets while pending), 0 from game code. Old v3 host: 1 engine ERROR 'Condition "len != 2" is true' (scene_multiplayer.cpp:127, our auth packet) and it still started its race with the client counted (old build, cannot be fixed from here).
Verify 4a (bot_race/): IN PROGRESS
Verify 4a DONE (bot_race/, bot_race.summary.txt): 12 karts, host finished the lap (38.3 s), client rtt 6 ms; host 0 ERROR 0 WARNING, client1 0 ERROR 0 WARNING.
Verify 4b (item_net/): IN PROGRESS
Verify 4b DONE (item_net/, item_net.summary.txt): hits host/c1/c2 IDENTICAL (34), 0 ERROR 0 WARNING all three.
Verify 4c (spectate/): IN PROGRESS. host --players=2 --bots=2 --laps=1 --quit-after=65; client1 +1 s; client2 +12 s (--quit-after=45)
Verify 4c DONE (spectate/): client2 joined about 7.6 s into the race: host "peer N connecting: checking its version" then "[spectate] host: peer N joined during the race and watches it"; client2 "[spectate] watching the running race: 4 karts, race clock 7.6 s", kart=-1, camera follows the leader. host/client1/client2 0 ERROR 0 WARNING.
Verify 5 DONE (parse_check.log): net_handshake, net_session, net_config, net_options, kart_wire, main: exit 0 each (after --import; no edits since).
Step 3: report.
