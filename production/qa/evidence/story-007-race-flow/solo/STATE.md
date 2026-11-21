# Solo setup task state
Step 0: reading current main.gd / net_session.gd / lobby_screen.gd (parts 2+3 landed).
Step 1: code edits done (net_session host_offline, lobby set_offline, main _start_solo/_restart/_finish_check, auto-ui=solo). Next: parse, shots, auto run, regressions.
Step 1: code edits done. Next parse/shots/auto run/regressions
Step 2: parse OK; setup/results shots opened (heading fix pending re-shot). Running scripted solo run -> solo/auto_run.log
Step 3: first auto run OK flow (2 races, restart) but exit ERROR '2 resources in use' -> added NetSession._exit_tree close(); rerunning auto run.
Step 4: auto run PASS (8 karts, restart -> 2nd race, 0 ERROR). Next: reshoot setup, open shots, regressions (bot_race_test, item_net_test), report.
Step 5: real-run results shot + setup shots opened OK. Next: regressions.
Step 6: bot_race_test 3 bots 0 ERROR done; running 11 bots + 1 client (no SCALE: scale is unsafe with clients) then item_net_test.
Step 7: ALL DONE. Regressions: bot 3 bots, bot 11 bots+1 client, item_net_test all 0 ERROR; item hits IDENTICAL. Report only.
