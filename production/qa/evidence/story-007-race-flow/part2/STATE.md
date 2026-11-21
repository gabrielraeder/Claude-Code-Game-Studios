# Story 007 part 2 — HUD + minimap + sound wiring — STATE

Step 0: started 2026-11-20. Reading inputs.
Step 0 done: inputs read (story, art bible s4+s7, race_hud, ui_theme, main.gd, item_manager, kart_sim, lap_counter, start_sequence, audio_director).
Plan: HUD = CanvasLayer scaled to 720 base; item circle top-left, lap/time/speed+drift pips pills under it, place banner top-right,
minimap bottom-right (static track Control cached + dots Control redrawn per frame), hints bottom-left. All values in ui_theme.tres (HUD group + hud_* texts).
Sound: AudioDirector in main; per-frame engines; edge detection per racer (spin, sink, boost start); local/bot signals for wall(hard)/bump; item_manager gets a sound_cue signal (kind, kart_id).
Step 1 (HUD rewrite): IN PROGRESS
Step 1 DONE: race_hud.gd rewritten (place banner, item circle+icons, lap/time/speed pills, drift pips, minimap MinimapTrack cached + MinimapDots per frame); HUD values in ui_theme.gd group "Race HUD" + hud_* texts in ui_theme.tres; item_manager hud_icon has "id".
Step 2 DONE: src/audio/race_sound.gd (new, RaceSound); AudioSet group "Race events" (event mapping); roulette_land event in audio_set.tres; item_manager signal sound_cue; input action MUTE (M, JOY_BUTTON_BACK); UiScreen: sound_fn, focus/accept/back UI sounds, _add_sound_button; Sound button in main menu (after Controls) and pause (before Quit); RaceFlowUi: mute_requested (PROCESS_MODE_ALWAYS), set_sound_player, set_sound_state; main.gd: _setup_audio, _update_minimap, _on_item_sound_cue, _toggle_mute.
Parse check: all 11 changed scripts ok, exit 0 (after --import).
Step 3 (automation 0 ERROR): IN PROGRESS
Step 3a: bot_race_headless (QUIT=60 SCALE=4 castle 11 bots 1 lap): host.log 0 ERROR lines. Evidence dir part2/bot_race_headless.
Step 3b: item_net (tools/item_net_test.sh part2/item_net castle_circuit 1): running.
Next shots: direct windowed host cmd: $G --path . --resolution WxH -- --host --port=24690 --players=1 --bots=11 --autopilot --quit-after=60 --laps=1 --track=T --shots=part2/shots_T_WxH
Step 3b result 1 (item_net): hits IDENTICAL host/c1/c2 (21), but each log had "ERROR: N resources still in use at exit" + ObjectDB leak WARNING (new; not in earlier evidence). Cause suspected: RaceSound lambdas capturing Racer on the sim's own signals (RefCounted cycle). Fixed: bound methods + WeakRef. Rerun -> part2/item_net2 (running).
item_net2: still leak (verbose probe: AudioStreamWAV playbacks active at quit: engine_loop, music_loop, finish). Fix: AudioDirector plays nothing under headless (_silent = DisplayServer "headless") + shutdown() on _exit_tree. leak_probe3: 0 ERROR 0 WARNING. Rerunning item_net3 + bot_race_headless2.
Step 3 DONE: item_net3 host/c1/c2 0 ERROR 0 WARNING, hits IDENTICAL (8); bot_race_headless2 0 ERROR 0 WARNING.
Step 4 (screenshots): IN PROGRESS (helper: scratchpad shots.sh track WxH outdir)
shots_castle_720 opened (countdown, start_go, drive_t10, spark_tier2): fixes -> hint text had broken spacing (tres string newlines -> escaped), unlit pips looked black (parchment under), minimap triangles 15x8. Note: harness shots lag HUD by one frame (tier2 shot shows tier1 pips).
shots_castle_1080 opened (drive_t03, drive_t20 holding Spill): hints fixed, reads well. Added gold ring outside cream ring when local leads.
shots_dungeon_720 opened (drive_t10 shield held, item_hit_1 falcon SPUN OUT): good contrast on dark track; leader+local double ring visible.
shots_dungeon_1080 opened (countdown "2", drive_t03 2nd place): readable. Step 4 DONE.
Step 5 (fps run, windowed, no shots): running -> part2/fps_castle_windowed
Step 5 DONE: fps_castle_windowed (seed 2661212103, 11 bots, 3 laps, windowed, audio not silenced): 144 race rows, fps min 59 / p5 60 / median 60; frame_max_ms median 18.1, p95 21.6, worst 39.4; host.log 0 ERROR 0 WARNING.
Final parse check: all 12 changed scripts ok, exit 0.
Step 6: report delivered.
