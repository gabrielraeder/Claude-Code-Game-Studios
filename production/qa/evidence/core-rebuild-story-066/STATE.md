# Story 066 state (updated after each step)
Resume from this file. Repo root: c:\writechoice\Claude-Code-Game-Studios. Nothing is committed except efc4923 (.gitattributes).

## GO / NO-GO RESULT: GO (steps 1-2 done)
- gdUnit4 drives native classes: tests/unit/native/native_toolchain_test.gd, 24 cases, PASSED, exit 0 (logs/gdunit-native-7.log).
- Typed factory works: `var probe: ToolchainProbe = ToolchainProbe.create(PackedFloat64Array(...))`; validate_packed typed; .new() unbuilt guards tested per bound method.
- ClassDB.class_call_static works on bind_static_method (Verification Required 9 OK).
- mock()/spy() recorded in mock_spy_result.md (do not intercept native methods; tests drive the real class).

## Files that exist
native/SConstruct, native/GODOT_CPP_COMMIT, native/hash_files.txt, native/src/register_types.{h,cpp}, native/src/core/{build_marker.h,dogworks_core.{h,cpp},toolchain_probe.{h,cpp}},
addons/dogworks_core/{dogworks_core.gdextension,source_hash.gd}, src/core/native_boot_check.gd, tests/unit/native/{native_test_guard.gd,native_toolchain_test.gd},
tools/build_native.{sh,bat}, .gitignore edited (native/godot-cpp, .venv, api, obj). .gdignore in native, godot-cpp, .venv, obj, api.
Built: addons/dogworks_core/bin/ has debug, release, bench DLLs + build_hash.txt; `bash tools/build_native.sh --check` PASS.

## Criteria status
- Build skeleton: built OK, times in logs/build-times.txt. STILL TODO: verify flags dump file (compiler_command_line-*.txt copied), incremental time table.
- Registration, gdUnit4, typed factory: PASS (evidence above).
- Everything else: NOT DONE.

## Remaining TODO (in order)
1. --import after full build: exit 0, no *.obj.import (find native -name '*.obj.import'); record log.
2. Locked-DLL negative run (start own headless Godot holding DLL, e.g. `-s` script that sleeps; stop it yourself).
3. ptrcall measurement + heap (600 ticks double buffer, held-array run) + exit safety (static var, RID owner, deliberate leak -> 139?) via a tools/*.gd script with --mode.
4. Fresh-clone import order (copy tree without .godot to scratch dir, @tool script calling ToolchainProbe during first --import).
5. --check negative runs (stale, bench in debug slot, bench.lock, marker count != 1), --bench/--restore runs, bench DLL load via debug slot.
6. Boot check negative run with extension absent (scratch project with only native_boot_check.gd + source_hash.gd), SH recompute time, 3 callers negative runs, plugin.cfg + plugin.gd (EditorPlugin, not yet written), core_greps.sh rule native_suites_call_guard + negative run.
7. regression.sh + project.yaml commands.test prefix `bash tools/build_native.sh --check &&`.
8. .claude/rules/native-code.md, docs/engine-reference/godot/godot-cpp.md.
9. Crash-repro script tools/crash_repro.sh, headless --quit hang investigation.
10. Hot reload: owner instructions (probe text `DogworksCore.hot_reload_text()` returns "hot-reload text A"; plan: owner changes to "B" in native/src/core/dogworks_core.cpp, runs tools/build_native.sh, observes via an EditorScript tools/hot_reload_probe.gd - NOT yet written).

## Notes / gotchas learned
- .bat: `shift` breaks %~dp0 (HERE var); no `2>nul` on vcvars call; keep LF (hashed file).
- gdUnit4 stops a suite after the first failing test (fail-fast).
- gdUnit4 sees native ERR_FAIL_* as push errors (is_push_error with the macro text).
- ERR_FAIL_* "Condition ..." text is what is matched, not the _MSG text.
- Blocked: recursive rm -rf was denied by permissions; do not delete directories.
- 24690 remote-debug prints "Unable to connect" error line (harmless, existing command uses :0).

## Update 2
- [x] Item 1 import: exit 0, 0 *.obj.import (logs/import-final.log, obj-import-files.txt).
- [x] tools/native_probe_runs.gd written + parse-checked; runs/ has ptrcall, heap, heap_held, exit_clean, exit_rid, exit_leak, exit_leak_cycle. ptrcall net ~0.0125 us int, 0.0100 Vector3, 0.0468 packed(64). heap flat (growth 0); held: +16416 B once then 0. exit_clean/exit_rid exit 0. LEAK DOES NOT CRASH: exit 0 with 4 'RID allocations leaked' errors + ObjectDB warning (139 not reproduced).
- Next: item 2 locked DLL negative run.

## Update 3
- [x] Item 2 locked DLL: runs/locked-dll-negative.txt (exit 2, names pid + dll). build_native.sh links in obj/<v>/dist and moves after success; runs --check after.
- [x] Item 4 fresh-clone: runs/fresh-clone-import-1.log (extension loaded in first_scan_filesystem, importer called ToolchainProbe.create OK) BUT first --import of ANY fresh project with an extension segfaults at exit (139); also with the spike DLL (runs/fresh-control-spike-dll.log); pre-seeded extension_list.cfg => 0; no extension => 0. Second import exit 0.
- [x] Item 5 negative runs + bench: runs/check-negative-and-bench.txt + check-negative-marker-count-2.txt.
- Next: item 3 boot/guards/plugin, core_greps rule, regression.sh, project.yaml, rules docs, crash_repro, hot reload.

## Update 4
- Coordinator decisions: leak exit 0 is a real result (deviation from 139); first-import segfault is engine bug (draft written, not filed). 
- Written: plugin.gd/cfg (NOT enabled in project.godot: needs owner approval of a project.godot edit; demonstrated in a scratch project instead), tools/native_boot_check_run.gd, tools/native_exit_safety.sh (leak lines FAIL; negative control), core_greps rule native_suites_call_guard, regression.sh checks native_check + native_exit (9 checks), project.yaml commands.test prefixed, build_native.sh writes .godot/extension_list.cfg + checkout -f fix, .claude/rules/native-code.md, docs/engine-reference/godot/godot-cpp.md, upstream-bug-draft-first-import-segfault.md, tools/hot_reload_probe.gd + hot-reload-owner-instructions.md, tools/crash_repro.sh.
- RUNNING: clone build in scratchpad/clone066 (runs/clone-build.log); then first --import there (expect exit 0 + probe call).
- TODO still: guard_runs.sh (item 6 negative runs), native_exit_safety run, crash_repro runs + hang repro, plugin scratch demo, final gdunit/parse-check/core_greps logs, regression partial run, report.

## Update 5
- GUI alert incident: the "Can't run project: no main scene defined" dialog came from MY hang repro: `tools/crash_repro.sh quit-noscene-{noext,ext}-N` = `Godot_v4.8-beta3_win64_console.exe --headless --path <scratch project without a main scene> --quit` (6 runs, scratch066/absent and scratch066h/fresh). --headless was passed; Windows still shows the modal alert (the console exe starts the non-console exe). This is very likely the spike's "--quit hang": a modal dialog nobody clicks. No Godot process of mine remains (checked). Rule from now: never run a project without a main scene unless a script/scene is passed.
- Done since update 4: clone build + first import (clone-build.log, clone-first-import.log: exit 0, probe called), guard-runs.txt, native-exit-safety.txt, plugin-scratch-runs.txt, crash-repro-summary.txt.
- TODO: stale test-command negative, gdunit4-final.log, parse-check-final.txt, core_greps, regression CHECKS partial, report.

## Update 6 (final)
- gdunit4-final.log: commands.test (with 24690), CHECK PASS then 224 cases, 0 failures, exit 0, 11 s. test-command-stale-negative.txt: stale DLL stops the chain before gdUnit4.
- parse-check-final.txt all ok (8 files). core_greps-final.txt PASS. regression-partial.txt PARTIAL PASS 3/9.
- Left for owner: hot reload (hot-reload-owner-instructions.md), project.godot plugin enablement, commits.
pass 2 (review fixes) started; see coordinator list A-E

## Update 7 (review pass, in progress)
- Written: C++ (registry + release_all, crash_for_test, live_rid_count, idempotent dispose, zero-fill, empty sum guard, get_class_static), SConstruct (PDB only for symbols, obj path), build_native.sh rewrite (hash list validation, PROBE_FAILED, run_limited tree kill, venv/godot-cpp checks, flag scan, .godot list check, --probe-godot, --scan-flags), source_hash.gd/boot check/plugin/guard rewrites, tests (native_toolchain_test, native_hash_parity_test), native_probe_runs.gd (sentinel, reload, crash), native_exit_safety.sh, core_greps rule, crash_repro.sh (cdb default path), regression.sh (10 checks), native_negative_checks.sh.
- TODO: build (full, background), docs (godot-cpp.md hot reload/ptr/PDB, native-code.md), fresh-clone evidence rerun with exit codes, bug draft trigger, reload test, crash_for_test cdb run, gdunit/regression finals.

## Update 8
- Build final (review) OK: runs/build-final-review.log (flag scan 1126 compile lines for release and bench, none forbidden).
- Native suites: 39 cases pass (29 toolchain + 10 hash parity/guard). Logger capture of create() message works (OS.add_logger).
- Reload: runs/reload-editor.txt (headless editor, GDExtensionManager.reload_extension, live RIDs 3 -> 0, old ref unbuilt, new create works, no leak lines). Plain `-s` script mode: "GDExtension reloading is disabled" (runs/reload.txt).
- cdb crash_for_test: runs/crash-for-test-summary.txt (symbolicated, ToolchainProbe::crash_for_test+0xd3).
- Unseeded first import: runs/fresh-first-import-unseeded.log EXIT_CODE=139 (extension loaded in first scan, importer called probe).
- RUNNING: clone final build (runs/clone-build-final.log) then clone first import.
- TODO: clone import, real-project plugin positive, finals (commands.test literal :0, regression 10/10, stale-stops-regression, parse-check, core_greps), report.

## Update 9 (review pass complete)
- Finals: gdunit4-final.log (literal commands.test with :0: 239 cases, 0 failures, exit 0), regression-full.txt (RESULT PASS 10/10), regression-stale-negative.txt (stale stops regression; includes a note on a restore slip, fixed, --check PASS), parse-check-final.txt (9 ok), core_greps-final.txt PASS, native-negative-final.txt (42 PASS, 0 FAIL), runs/clone-build-final.log + clone-first-import-final.log (exit 0), runs/fresh-first-import-unseeded.log (exit 139), runs/real-project-plugin-positive.txt.
- Not exercised: run_limited timeout kill, SCons version mismatch repair, godot-cpp dirty-tree refusal (implemented only).
