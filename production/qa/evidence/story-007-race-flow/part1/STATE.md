# Story 007 part 1 state
Updated: all code written + parse OK; ui_theme.tres done; main.gd wired; debug runners done.
Lobby layout fixed (buttons+status in left column, setup in right). menu_1280x720 opened OK.
REMAINING: open lobby_1280x720 again; shots menu/lobby/lobby-client/results/results-client/results-solo/pause at 1280x720 and 1920x1080 (--resolution WxH --windowed -- --ui-shot=N --shots=DIR);
e2e 2 processes port 24690 (--auto-ui=host / --auto-ui=join:127.0.0.1 --auto-pick=3,1 --auto-track=dungeon_depths --auto-bots=2 --autopilot --port=24690);
CLI regression: bash tools/bot_race_test.sh <newdir> castle_circuit 3 1 0 (QUIT=60 SCALE=4); report.
Step: all 14 static screenshots at 1280x720 + 1920x1080 taken and opened, OK (results col widths + preview camera fixed). Next: e2e (logs e2e_host.log / e2e_client.log in this folder), CLI regression, report.
Step: e2e PASSED (logs e2e_host.log/e2e_client.log). Next: CLI regression, report.
Step: CLI regression PASSED (cli_bot_test/, 0 ERROR, race started, net-summary printed). ALL DONE; only the report remains.
