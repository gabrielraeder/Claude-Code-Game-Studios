# Hot reload check: what to do in the Godot editor (about 10 minutes)

Why you: this needs the real editor window, and the agent cannot drive it. You are checking that a rebuilt native DLL is picked up by the editor you already have open, without closing the editor.

You need: the Godot 4.8-beta3 editor (not the console), Git Bash, and this project. Nothing else should be running: close every other Godot window first.

## Steps
1. In Git Bash, in the project folder, run `bash tools/build_native.sh --check`. It must print `CHECK PASS`. If it does not, run `bash tools/build_native.sh` first (about 35 seconds).
2. Open the project in the Godot editor. Wait until it has finished loading.
3. In the editor, open the file `res://tools/hot_reload_probe.gd` (FileSystem dock, double click).
4. With that script open, choose `File > Run` (shortcut Ctrl+Shift+X). Look in the Output panel at the bottom. You should see one line like:
   `HOT_RELOAD_PROBE text='hot-reload text A' target=debug build_hash=xxxxxxxxxxxx`
   Write down the text and the 12 characters after `build_hash=`. Do not close the editor from now on.
5. Open `native/src/core/dogworks_core.cpp` in any text editor (not the Godot editor). Find the line `return "hot-reload text A";` and change `A` to `B`. Save.
6. In Git Bash run `bash tools/build_native.sh`. It takes about 35 seconds.
   - If it says `refusing to build: a Godot process holds the DLL`, copy that message (it names the process). This is a result too: it means the editor locks the DLL and hot reload cannot work on this machine. Stop here and send the message.
   - Otherwise it ends with `CHECK PASS`.
7. Go back to the Godot editor window and click on it (the editor checks for changed files when it gets focus). Wait about 5 seconds. The Output panel may print a line about reloading the extension. Copy any such line.
8. Run the script again as in step 4. Expected: `text='hot-reload text B'` and different characters after `build_hash=`. The editor must not have been restarted by you and must not have crashed.
9. Put it back: change `B` back to `A` in `native/src/core/dogworks_core.cpp`, save, run `bash tools/build_native.sh` again, click the editor, and run the script once more. You should see `A` again. This leaves the project in its normal state.

## What to send back
- The Output lines from steps 4, 7 and 8 (copy and paste them).
- Whether the editor stayed open all the time, and whether any error pop-up appeared.
- Whether step 6 was refused.

## What counts as a pass
Step 8 shows text B and a new hash while the same editor window stays open. If it still shows text A, the editor did not pick up the rebuilt DLL: tell the agent, and add whether closing and reopening the editor shows B (it should).
