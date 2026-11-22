# Hot reload in the GUI editor: PASS (owner, 2026-11-22)

- Where: a separate clone at commit 23800b5 (`C:/writechoice/dogworks-editor-test`), so the parallel story 067/008 agents could not interfere.
- Editor: `C:/Godot/Godot_v4.8-beta3_win64.exe` (GUI), project imported, `tools/hot_reload_probe.gd` run with File > Run.
- Before: `HOT_RELOAD_PROBE text='hot-reload text A' target=debug build_hash=249eeb1ece57` (01-before-text-A.png).
- Change: `native/src/core/dogworks_core.cpp` text A -> B, `bash tools/build_native.sh` with the editor open: not refused (the editor holds only its `~` copy), CHECK PASS (build-B.log).
- After: owner clicked the editor, ran the probe again: `text='hot-reload text B' build_hash=d9d22a8e847a` (02-after-rebuild-text-B.png). The editor was not restarted and did not crash.
- No extension-reload line was printed in Output.
