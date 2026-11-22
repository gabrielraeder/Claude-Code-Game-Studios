# DRAFT (not filed): first `--import` of a fresh project with a GDExtension exits with a segfault

Status: draft for the owner. Nothing here has been submitted anywhere (`.claude/docs/coordination-rules.md` rule 7). Written by core-rebuild story 066.

## Summary
On Godot 4.8-beta3 (Windows), the first `--headless --import` of a project that has a `.gdextension` file but no `.godot/extension_list.cfg` imports everything and prints "loading_editor_layout ... DONE", then the process dies with a segmentation fault (exit code 139 under Git Bash). The same command run a second time exits 0. It happens with an extension built from this project and with an unrelated, earlier spike extension, with `reloadable = true` and `reloadable = false`, and with no editor plugin enabled. Pre-creating `.godot/extension_list.cfg` avoids it.

## Versions
- Godot `4.8.beta3.official.c51ff06e8`, `Godot_v4.8-beta3_win64_console.exe`, headless debug editor binary.
- Windows 11 Pro 10.0.26200, Git Bash. godot-cpp commit `7fd5c4bc3efda6487fd6e6486c50016faa622f92` (MSVC 14.44.35207, `/MT`).
- Locale of the editor output is Portuguese; not related.

## Steps
1. Make an empty folder with a `project.godot` containing only `config_version=5` and an application name.
2. Put one GDExtension in it: a `.gdextension` file (`entry_symbol`, `compatibility_minimum = "4.8"`, `reloadable = true`, a `windows.debug.x86_64` entry) and its DLL. Any godot-cpp extension reproduces it, including one that registers a single `RefCounted` class.
3. Make sure `.godot/` does not exist.
4. Run `Godot_v4.8-beta3_win64_console.exe --headless --path . --import`.

## Expected
Exit code 0, as when the same extension is loaded from an existing `.godot/extension_list.cfg`.

## Actual
The log reaches `loading_editor_layout ... DONE`, then `Segmentation fault`, exit code 139. `.godot/extension_list.cfg` was written by then (it lists the `.gdextension`). Running step 4 again exits 0.

## Variations tried (all in `production/qa/evidence/core-rebuild-story-066/runs/`)
| Variation | Result |
|---|---|
| Extension, no plugin, `reloadable = true` (`fresh-control-noplugin*.log`) | 139 on three fresh projects |
| Extension, `reloadable = false` (`fresh-control-noreload.log`) | 139 |
| The earlier spike extension DLL, another entry symbol (`fresh-control-spike-dll.log`) | 139 |
| Extension plus an `EditorImportPlugin` that calls a native class during the first scan (`fresh-clone-import-1.log`) | the extension loads in `first_scan_filesystem`, the importer runs and the native class works, then 139 |
| Same project, a second `--import` (`fresh-clone-import-2.log`) | 0 |
| `.godot/extension_list.cfg` pre-created with the `.gdextension` path (`fresh-control-preseeded-extlist.log`) | 0 |
| No `.gdextension` in the project (`fresh-control-noext.log`) | 0 |

## Notes
- The crash is at shutdown after the import has finished, so imported data is complete. Only the exit code is wrong, which matters for scripts that gate on it.
- The cause was not investigated (no engine symbols, the editor binary is stripped). The pre-seeding workaround makes `tools/build_native.sh` write the list file.
- A related earlier report in the spike (`prototypes/native-spike/REPORT.md`, Q1) blamed scanning godot-cpp for a first-`--import` segfault. This run had `.gdignore` files in place, so that explanation does not cover this crash.

## Removal trigger for the workaround
`tools/build_native.sh` seeds `.godot/extension_list.cfg` (function `ensure_extension_list`) only because of this crash. Re-test on every engine re-pin (`/setup-engine refresh`, ADR-0007 section 9): run the "Steps" above on a fresh folder. When a first `--import` of a fresh project with an extension exits 0, delete `ensure_extension_list`, the `.godot/extension_list.cfg` check in `--check`, and the `native_negative` case `missing_extension_list`.

## What each run proves (read this before citing the logs)
- Only the run with **no** `extension_list.cfg` before the import proves that the extension loads during the very first scan and that an import-time script can call it; that run ends with exit 139 (`runs/fresh-first-import-unseeded.log`, exit code written at its end).
- The run in a clone after `tools/build_native.sh` (which seeds the list) tests the workaround: exit 0 and the probe call works (`runs/clone-first-import-final.log`). It does not prove first-scan loading, because the list already existed.
