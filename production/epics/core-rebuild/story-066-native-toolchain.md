# Story 066: Native toolchain, dogworks_core skeleton and stale-DLL guard

> **Epic**: Core Rebuild (Phase A)
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Integration
> **Estimate**: L
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: 2026-11-22

## Context

**GDD**: N/A (toolchain; no GDD system). It enables `design/gdd/track-collision-and-surfaces.md` AC-20 through story 067.
**Requirement**: ADR-0007 Migration Plan step 1; ADR-0007 Verification Required items 1–9; ADR-0007 Validation Criteria (stale-DLL guard negative runs; gdUnit4, typed factory and hot-reload evidence)
**Roadmap step**: `architecture.md` Phase A Sequencing, between steps 2 and 3 (ADR-0007 Ordering Note: toolchain first, then the CollisionQuery port, then the `RaceSim` skeleton, then story 009). The sequencing table gains this row through the ADR-0007 §12 amendment, which has not been made yet. Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0007: Native Simulation Core (C++ via GDExtension) (Accepted)
**ADR Decision Summary**: One C++17 GDExtension, `dogworks_core` (godot-cpp at a pinned commit), owns everything that runs per tick in the simulation. GDScript keeps data Resources (packed once through `pack_native()`), import tools, networking, race flow, input, UI and presentation. Native classes take no `.new()` arguments: a class that needs arguments is built by a bound static `create(packed)` factory, paired with a `validate_packed(packed)` that runs the same C++ validation, and every bound method guards on a `built` flag. The per-tick path is eight `RaceSim` stage calls with double-buffered packed outputs. DLLs are built per clone by `tools/build_native.sh` and never committed. A two-hash stale-DLL guard (`--check`, the boot check, an `@tool` EditorPlugin and a shared test helper) refuses a stale or bench DLL.

**ADR Version**: ADR-0007 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: The GDExtension API can change between 4.8 betas and stable, so dump it from the pinned binary (`--headless --dump-extension-api --dump-gdextension-interface --dump-gdextension-interface-json`; SCons needs `gdextension_dir` as well as `custom_api_file`, spike REPORT Q1). godot-cpp `7fd5c4bc` was used by the spike. Bash cannot source `vcvars64.bat`, so the `.bat` wrapper puts MSVC on PATH inside `cmd`. `.gdignore` is mandatory: the spike's first `--import` scanned godot-cpp and segfaulted. Run CLI commands with `--headless --quit-after` and a scene: the spike saw one `--quit` hang in a project with no main scene. Evidence: `prototypes/native-spike/REPORT.md` and `prototypes/native-spike/out/`.

---

## Acceptance Criteria

*Each criterion cites its source (ADR-0007 section, Verification Required n, or Validation Criteria).*

- [x] **Build skeleton.** `native/` follows the §6 layout. `native/SConstruct` builds the debug, release and bench variants, each into its own `native/obj/` variant folder, with `/fp:precise`, no `/fp:fast`, no `/arch:AVX2` (SSE2 baseline), and a static CRT (`/MT`, `use_static_cpp=True`). `native/GODOT_CPP_COMMIT` is committed. `tools/build_native.sh` is one command (venv, godot-cpp fetch at the pinned commit, API dump from the pinned editor, `tools/build_native.bat` for vcvars64, scons for all variants), with explicit timeouts for the cold build. Cold and incremental build times are recorded, and the real compiler command line is dumped into the evidence (ADR-0007 §4 Determinism, §6, §7 "One command per clone").
- [x] **Godot never scans native sources.** `native/`, `native/godot-cpp/`, `native/.venv/` and `native/obj/` carry `.gdignore`. A headless `--import` after a full build exits 0 and writes no `*.obj.import` file (ADR-0007 §6; Implementation Guidelines).
- [x] **Locked DLL.** `tools/build_native.sh` refuses to build while a Godot process holds the DLL and names the process, links to a temporary name and renames on success, and runs `--check` after the build. A negative run with a headless Godot holding the DLL is recorded (ADR-0007 §7 "Locked DLL").
- [x] **Registration.** `addons/dogworks_core/dogworks_core.gdextension` is committed with `entry_symbol = "dogworks_core_init"`, `compatibility_minimum = "4.8"`, no `compatibility_maximum`, `reloadable = true`, and `windows.debug.x86_64` and `windows.release.x86_64` entries. `DogworksCore` is registered first with `GDREGISTER_CLASS` at `MODULE_INITIALIZATION_LEVEL_SCENE`, and binds the static methods `sim_hz() -> int` (60, from `constexpr int SIM_HZ`), `build_hash() -> String` and `source_hash() -> String`. A module-level `g_servers_alive` flag is set in `initialize_module(SCENE)` and cleared in `uninitialize_module(SCENE)`. There are no static initialisers that call engine APIs (ADR-0007 §4 Registration, `SIM_DT`, Servers-alive flag; §6).
- [x] **gdUnit4 drives a native class.** A gdUnit4 suite under `tests/unit/native/` creates and calls `DogworksCore` and the toolchain probe class (next criterion) and passes from the test command. Whether gdUnit4 `mock()`/`spy()` works on a native class is tried and the result recorded. The ADR expects it not to, and tests drive the real class (ADR-0007 Verification Required 1; Validation Criteria).
- [x] **Construction and typed calls.** A toolchain probe class follows the §4 factory pattern: a bound static `create(packed) -> Ref<…>` that calls the same C++ function as `validate_packed(packed) -> String`, null on failure. From typed GDScript, `validate_packed` and `create` are callable and the result assigns to a typed local. `.new()` gives an unbuilt object whose every bound method refuses with `ERR_FAIL_COND` (a test per bound method). A no-argument class is built with `.new()`. The ptrcall cost per crossing is re-measured from typed code for scalar, `Vector3` and packed-array arguments, and recorded against the spike's ~0.17 µs (ADR-0007 Verification Required 2; §4 Construction pattern; Validation Criteria).
- [x] **Hot reload.** In the GUI editor, a rebuilt debug DLL is hot-reloaded without restarting the editor, and the changed behaviour is observed. The evidence names what changed and how it was seen (ADR-0007 Verification Required 3; §7 "Hot reload is for the editor only"; Validation Criteria).
- [x] **Exit safety.** A native object still alive at quit, including one held by a GDScript static var and one that owns server RIDs, ends with exit code 0 and no RID errors. A deliberately leaked object is shown to crash (exit code 139), so the check can fail (ADR-0007 Verification Required 4; §4 RID ownership, "Leaks crash").
- [x] **Packed-array reuse.** Over 600 ticks of a double-buffered probe output, with the caller refreshing its reference every tick, `OS.get_static_memory_usage()` (or a native allocation counter) does not grow. A second run, with a consumer that holds one array for the whole run, costs one copy for that array and then stays flat. `OBJECT_COUNT` is not used as the measure (ADR-0007 Verification Required 5; §3 Outputs are double-buffered).
- [x] **Fresh-clone import order.** On a clone with no `.godot/`, after `tools/build_native.sh`, the extension loads during the very first `--import` scan, before `.godot/extension_list.cfg` exists, and an import-time (`@tool`) script calls a native class during that scan. `CourseBuilder` does not exist yet, so the probe stands in for it. Story 067 re-runs the check with the native `CollisionQuery` (ADR-0007 Verification Required 6; §7 Fresh-clone import order).
- [x] **Two hashes and the marker.** SH and FH are computed as §7 defines them, over one committed file-list definition that both `tools/build_native.sh` and GDScript read, sorted in byte order (`LC_ALL=C`). The hashed files are pinned `eol=lf` in `.gitattributes`. SCons generates only `native/obj/build_marker.cpp` with the single literal `DOGWORKS_BUILD:<target>:<SH>:<FH>:END`, never a shared `CPPDEFINES` value. A bound function references the marker, and `addons/dogworks_core/bin/build_hash.txt` holds both values per DLL. The regex search finds exactly one marker match in each DLL (debug, release, bench) (ADR-0007 Verification Required 7; §7 Two hashes, How the hash is stored and read).
- [x] **`--check` negative runs.** `tools/build_native.sh --check` passes on a fresh build and FAILs, in recorded negative runs: on a deliberately stale DLL (a hashed source changed and not rebuilt); with a `bench`-target marker in the debug slot; while `addons/dogworks_core/bin/bench.lock` exists; and when the marker count is not exactly one (ADR-0007 §7 Stale-DLL guard; §8; Validation Criteria).
- [x] **Bench DLL.** `tools/build_native.sh --bench` refuses to run while any Godot process is open, including an editor. It then backs up the debug DLL, copies the bench DLL (release flags, `use_hot_reload=yes`) over the debug name, and writes `bench.lock`. The bench DLL loads through the `windows.debug.*` entry. A test run is refused while `bench.lock` exists. Restore copies the backup back, removes `bench.lock` and never rebuilds (ADR-0007 Verification Required 8; §8).
- [x] **Boot check and static call.** `src/core/native_boot_check.gd` names no native type. It checks `ClassDB.class_exists("DogworksCore")` before any native-typed script loads and refuses a missing extension, shown by a negative run with the extension absent. Through `ClassDB.class_call_static` it asserts that `sim_hz() * SIM_DT == 1.0` and that `sim_hz()` equals `physics_ticks_per_second`. In editor builds only (`OS.has_feature("editor")`), it recomputes SH with `FileAccess` and compares it with `DogworksCore.source_hash()`. The measured recompute time is recorded against the UNVERIFIED 100 ms budget. If `class_call_static` does not work on a `bind_static_method` method, the story stops and the ADR is amended before the boot check reads the value another way (ADR-0007 Verification Required 7 and 9; §4 `SIM_DT`; §7 Boot refusal).
- [x] **Editor-panel gap closed.** One shared GDScript function recomputes SH, and three callers run it: `native_boot_check.gd`; an `@tool` EditorPlugin in `addons/dogworks_core/` at editor start; and a shared test helper called in `before()` by every native-test suite. A source-hash mismatch is refused by all three, and each names `tools/build_native.sh`, shown by one negative run each. A `tools/core_greps.sh` rule fails when a suite under `tests/unit/` touches a native class and does not call the helper, shown by a negative run (ADR-0007 §7 "The editor-panel gap is closed"; Validation Criteria).
- [x] **Wired into the gates.** `tools/regression.sh` and `project.yaml` `commands.test` run `tools/build_native.sh --check` first (the `commands.test` change is owner-approved in ADR-0007 Migration Plan step 1). The existing gdUnit4 suite (200/200 at story 007) passes through the new test command, and a stale DLL makes the test command fail before gdUnit4 starts (ADR-0007 §7; Implementation Guidelines "`--check` must pass before tests or regression run").
- [x] **Knowledge and rules.** `.claude/rules/native-code.md` carries the §4 rules for `native/**`. `docs/engine-reference/godot/godot-cpp.md` covers the pinned commit, registration and binding (static methods included), properties and `Ref<>`, no constructor arguments, packed-array copy-on-write, destructor and RID rules, and `ERR_FAIL_*`, with each claim sourced or marked UNVERIFIED (ADR-0007 §4 Coding standards, Knowledge file; Migration Plan step 1).
- [x] **Crash repro and headless hang.** A headless crash-repro script runs a named native test or scene in its own process and reports the exit code and the PDB-symbolicated stack. The cause of the spike's `--quit` hang is recorded, or recorded as not reproduced with the commands tried (ADR-0007 Risks "A native crash during tests", "Unexplained headless hang"; Migration Plan step 1).

---

## Implementation Notes

- **Implementer:** `godot-gdextension-specialist` (ADR-0007 Implementation Guidelines; Risks "Delivery risk"). Give it an explicit turn budget per run. It keeps a `STATE.md` checkpoint in `production/qa/evidence/core-rebuild-story-066/` that is updated after each criterion, so a run that ends mid-story resumes from the file and not from memory (ADR-0007 Risks "An agent turn budget").
- **Order inside the story:** build skeleton and `.gdignore` first, then registration and gdUnit4 (Verification Required 1–2). Those are the go/no-go items: if gdUnit4 cannot drive a native class or the typed factory fails, stop and report, because the ADR is amended before story 009 (ADR-0007 Risks "Unverified gdUnit4-to-native testing").
- **Toolchain probe class:** a small native class used only to prove the factory pattern, RID teardown and double-buffered output (Verification Required 2, 4, 5, 6). Its name must not clash with any GDScript `class_name` (ADR-0007 §5). Whether it stays registered after the story, as a test-only class, or is removed is the implementer's call, and it is recorded under the story's own calls. No production code calls it.
- **Hot reload (Verification Required 3)** needs the GUI editor. If the agent cannot drive the editor, the step is handed to the owner with exact instructions, and the owner's observation is the evidence.
- **The `.gitattributes` `eol=lf` change** re-normalises the hashed files. Do it in its own commit, before the first hash is recorded.
- **`project.yaml`:** only the `commands.test` change is pre-approved. The other §12 config changes (`engine.language`, specialists for `native/**`) and the CLAUDE.md Technology Stack line are not part of this story, and are asked separately.
- Reuse the spike's working commands (`prototypes/native-spike/build_godotcpp.bat`, `run.sh`) as reference only. Prototype code is rewritten, not copied (`.claude/rules/prototype-code.md`).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 067: the native `CollisionQuery`, `QueryCursor`, `GroundHit`, `WallHit`; the oracle move; the `class_name`-vs-`ClassDB` clash check in `core_greps.sh`; the native collision bench.
- Story 068: `RaceSim`, its stages, buffers and stage timers.
- Story 041: the fresh-clone import story's amendment (build before first import) for real tracks.
- Export with the `template_release` DLL (Verification Required 10) and the re-pin procedure (Verification Required 11): later, once the 4.8 export templates exist.
- The ADR-0007 §12 amendments to ADR-0001 to ADR-0006, `architecture.md` and `docs/registry/architecture.yaml`.

---

## Files (planned)

- `native/SConstruct`, `native/GODOT_CPP_COMMIT`, `native/.gdignore`, `native/src/register_types.cpp`, `native/src/dogworks_core.{h,cpp}` (exact folder is the implementer's call within the §4 layout), the probe class sources, the hash file-list definition (new)
- `addons/dogworks_core/dogworks_core.gdextension`, `plugin.cfg`, `plugin.gd` (new); `addons/dogworks_core/bin/` (built, gitignored)
- `src/core/native_boot_check.gd` (new, plus `.uid`)
- `tools/build_native.sh`, `tools/build_native.bat`, the crash-repro script (new); `tools/regression.sh`, `tools/core_greps.sh` (edited)
- `tests/unit/native/` suites and the shared hash-check test helper (new, plus `.uid`)
- `.gitattributes`, `.gitignore` (edited); `project.yaml` `commands.test` (edited, owner-approved)
- `.claude/rules/native-code.md`, `docs/engine-reference/godot/godot-cpp.md` (new)
- `production/qa/evidence/core-rebuild-story-066/` (STATE.md, build logs, compiler command line, negative runs, measurements)

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: the integration runs named in the criteria (build logs, gdUnit4 run, negative `--check`, boot and test-helper runs, heap and ptrcall measurements, fresh-clone import log, hot-reload observation); retained in `production/qa/evidence/core-rebuild-story-066/`
**Status**: [x] Created: production/qa/evidence/core-rebuild-story-066/ (gdunit4-final.log 239/239, regression-full.txt 10/10, native-negative-final.txt 42/42, runs/, hot-reload/)

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-007-collision-benchmark.md` (Complete)
- Unlocks: `production/epics/core-rebuild/story-067-native-collision-query-port.md`

## Completion Notes
**Completed**: 2026-11-22
**Criteria**: 18/18 passing. Go/no-go items (gdUnit4 drives native classes, typed factory, `class_call_static`) passed first. Hot reload observed by the owner in the GUI editor (text A -> B, hash 249eeb1ece57 -> d9d22a8e847a, editor kept open; `hot-reload/`), plus a headless editor reload releasing live RIDs 3 -> 0. Crash repro symbolicated with cdb (`ToolchainProbe::crash_for_test+0xd3`).
**Deviations**: (1) A leaked native object exits 0 with "RID allocations leaked" lines, not 139 (4.8-beta3); exit safety fails on any `ERROR:` line and requires a `PROBE_RAN` sentinel; ADR-0007 §4 amended. (2) The first `--import` of a fresh project with any GDExtension segfaults at exit on 4.8-beta3; `build_native.sh` seeds `.godot/extension_list.cfg` and `--check` fails without it; only the unseeded run proves first-scan loading (exit 139 after a working import); upstream bug drafted, not filed; ADR-0007 §7 amended with a removal trigger. (3) Per-crossing cost measured at about 0.01 µs from typed GDScript, against the spike's 0.17 µs (cause not isolated). (4) Three guards are written but not exercised by a negative run: the timeout tree kill, the SCons version repair, the dirty godot-cpp refusal (advisory). (5) Story started its dependent 067 before close, with the owner's consent. (6) The editor plugin was enabled in `project.godot` with the owner's approval.
**Test Evidence**: production/qa/evidence/core-rebuild-story-066/ (gdunit4-final.log via the literal `commands.test`, 239/239; regression-full.txt RESULT PASS 10/10; native-negative-final.txt 42 PASS; regression-stale-negative.txt; runs/*; logs/compiler_command_line-*.txt and flag_scan-*.txt; hot-reload/RESULT.md with owner screenshots; upstream-bug-draft-first-import-segfault.md)
**Reviewed by**: godot-specialist engine check (5 defects, fixed); lead-programmer (LP-CODE-REVIEW: CONCERNS, fixed); qa-lead (QL-TEST-COVERAGE: GAPS, closed)
Run result: OBSERVED — owner ran the hot-reload probe in the GUI editor; Output showed text A then text B after a rebuild with the editor open (hot-reload/02-after-rebuild-text-B.png)

## Calls beyond the design
- `ToolchainProbe` stays registered as a test-only class, with a debug-only `crash_for_test()` no test or regression calls (`native/src/core/toolchain_probe.*`) · kept 2026-11-22
- The stamp's file list is `native/hash_files.txt`; the full hash covers the compiler version and the build script itself, so a script change forces a rebuild · kept 2026-11-22
- One marker per DLL (debug, release, bench), DLL names `dogworks_core.windows.<target>.x86_64.dll` · kept 2026-11-22
- 900 s limit per build stage, killing the whole process tree on timeout (`tools/build_native.sh`) · kept 2026-11-22
- `dispose()` is a silent no-op on an unbuilt or already-disposed object (`native-code.md`) · kept 2026-11-22
- Tests call Git's `bash.exe` by path because a bare `bash` from Godot opens WSL (`DOG_BASH`) · kept 2026-11-22
- A stale DLL stops `regression.sh` before any Godot starts; regression now has 10 checks · kept 2026-11-22
- Three guards written without a negative run (timeout kill, SCons repair, dirty godot-cpp) · kept 2026-11-22
