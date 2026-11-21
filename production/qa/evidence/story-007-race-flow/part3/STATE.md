# Story 007 part 3 — spectators + controls menu — STATE

Step 0: started 2026-11-20. Reading inputs (part1 STATE, main.gd, net_session, input_actions, ui_screen, main_menu, race_hud, auto_ui_driver).
Step 0 DONE: inputs read. Design:
 - Controls: InputActions gets REBINDABLE + reset_to_defaults() (defaults stay there); NEW src/input/input_bindings.gd (InputBindings: bind() with swap, save/load ConfigFile, robust load);
   NEW src/ui/binding_text.gd (names of keys/buttons/axes from ui_theme texts; fills "{k:accel/brake}" / "{p:...}" templates); NEW src/ui/controls_menu.gd (ControlsMenu: rows x Keyboard/Controller cells, capture, swap msg, reset, back);
   main menu Controls button enabled + pause menu Controls button; HUD hints + menu hint from templates; --controls-file=PATH debug option (shots never touch user://controls.cfg).
 - Spectators: no new RPC (rpc_race_start reused with "spectate": true, host_time = host race clock) so v6 builds are refused by version; KartWire.VERSION 7.
   Host stores _race_info; _on_peer_joined in NET_RACE -> send spectate info to that peer (+ results if results open); spectator: local kart dropped/hidden, kart id -1, remote karts only,
   camera follows place N (1 = leader), steer_left/right cycle; HUD spectate mode (standings column, banner); host HUD net line + results note show waiting count; lobby role tag "New".
Step 1 (controls code): IN PROGRESS. input_actions.gd modified, input_bindings.gd written.
Step 1 DONE (controls code): input_bindings.gd, binding_text.gd, controls_menu.gd (new); input_actions, ui_theme(.gd/.tres texts+Controls/Spectating groups), race_flow_ui, main_menu (Controls enabled, hint from InputMap), pause_menu (Controls button), race_hud (hints from InputMap, refresh_hints), ui_shot_runner (controls, controls-capture, controls-swap), debug_options (--controls-file=).
Step 2 DONE (spectator code): main.gd (_add_spectator, _begin/_end_spectating, _spectate_tick, shots spectate_1/2), net_session (send_race_start_to, send_race_results_to), kart_wire VERSION 7, lobby_state "new", lobby_screen tag, results_screen set_note, auto_ui_driver spectating_fn.
Parse check: 18 scripts ok, exit 0 (after --import).
Step 3 (controls check script tools/controls_check.gd): IN PROGRESS
Step 3 DONE: tools/controls_check.gd -> part3/controls_check.log: RESULT PASS (24 checks), 0 ERROR; 2 expected WARNINGs (corrupt file, bad entry). Saved format switched to JSON user://controls.json (ConfigFile corrupt parse prints an engine ERROR; JSON.parse does not). load_saved is two-pass (swapped bindings reload correctly).
Step 4 (screenshots controls/menu): IN PROGRESS. cmd: $G --path . --resolution WxH --windowed -- --ui-shot=NAME --shots=part3/shots
Step 4a: controls_1280 opened: bottom buttons cut off, panel too wide, hint listed Enter/Keypad Enter/Space. Fixed: compact cells (margins 2, font 20), panel shrink-centre, {k1:}/{p1:} first-input placeholders. Re-shooting.
Step 4 DONE: opened controls_1280 (fixed), controls-swap_1280 (fixed grey cells), controls-capture_1280 (fixed clipped text), controls-capture_1920, controls-swap_1920, menu_1280 (Controls + Sound buttons, hint from InputMap). All shot runs 0 ERROR.
Step 5 (spectator e2e, 3 procs, scratchpad e2e.sh): IN PROGRESS -> part3/e2e/
Step 5 DONE: e2e (castle, 2 bots, 2 laps, 2 races; client2 windowed 1280x720 joined ~12 s into race 1): client2 '[spectate] watching the running race: 4 karts, race clock 12.2 s', camera follows leader (switches logged), results shown '(seen as spectator)', then '[net] race start: 5 karts ... kart=2' (raced the rematch), results 2, done. Host: '[spectate] host: peer ... watches it', '1 watcher(s) join this race as racers'. host/client1/client2: 0 ERROR 0 WARNING. Shots e2e/shots/spectate_1.png, spectate_2.png. Note: client2 log shows camera place 2/3/4 cycling not scripted (likely keyboard/controller input on the focused window).
Step 6: opening spectate shots
Step 6: opened e2e/shots/spectate_1.png (1280x720: standings, banner, follow line, place 1st/4, minimap ring on followed kart; fixed net line 'karts' counting hidden local kart). CLI-path spectator run cli_spectate_1080 (dungeon, 1920x1080 windowed late joiner): 3 logs 0 ERROR 0 WARNING; leader switch logged (kart 0 -> kart 3); opened cli_spectate_1080/shots/spectate_2.png.
Step 7 (regressions bot_race_test + item_net_test): IN PROGRESS
Step 7a: bot_race_headless (QUIT=60 SCALE=4 castle 11 bots 1 lap): host.log 0 ERROR 0 WARNING, race start 12 karts, net-summary printed. 7b item_net running.
Step 7 DONE: item_net (castle 1 lap): hits IDENTICAL host/c1/c2 (21), 0 ERROR 0 WARNING all 3. Step 8: tools/controls_capture_check.gd (fake events through the screen).
Step 8 DONE: controls_capture_check.log RESULT PASS (14 checks, 0 ERROR): Enter opens capture on release and next Enter is bound, Esc cancels, light trigger ignored, RT captured + swap, keyboard ignored in controller capture, Y bound. Opened shots/pause_1280x720.png (Controls button fits). Final parse check of changed scripts ok.
Step 9: report.
