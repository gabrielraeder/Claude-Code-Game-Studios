# godot-cpp (C++ GDExtension bindings) - project reference

Written by core-rebuild story 066 for ADR-0007. Last verified 2026-11-22 against the pinned source and the story's runs. Each claim carries a source: **SRC** (godot-cpp file at the pinned commit, under `native/godot-cpp/`, fetched by `tools/build_native.sh`), **OBS** (observed in this project, evidence in `production/qa/evidence/core-rebuild-story-066/`), **ADR** (decided in `docs/architecture/adr-0007-native-simulation-core.md`) or **UNVERIFIED**.

## Pin
- Commit `7fd5c4bc3efda6487fd6e6486c50016faa622f92` (commit date 2026-11-19), in `native/GODOT_CPP_COMMIT`. **SRC** `git rev-parse HEAD` in `native/godot-cpp`.
- Built against the API dumped from the pinned editor (`Godot 4.8.beta3.official.c51ff06e8`): `--headless --dump-extension-api --dump-gdextension-interface --dump-gdextension-interface-json`. SCons needs `gdextension_dir=api` and `custom_api_file=api/extension_api.json`. **OBS** `native/SConstruct`, spike REPORT Q1.
- Forward compatible only: a DLL built for 4.8 does not load in an earlier editor. `compatibility_minimum = "4.8"`, no `compatibility_maximum`. **ADR** section 9; godot-cpp README (UNVERIFIED here, not re-read).

## Registration and binding
- Entry symbol `dogworks_core_init` (an `extern "C"` function marked `GDE_EXPORT`, defined in `include/godot_cpp/core/defs.hpp`) builds a `GDExtensionBinding::InitObject`, registers an initialiser and a terminator, and sets the minimum level. **SRC** `defs.hpp:93`, **OBS** `native/src/register_types.cpp`.
- `GDREGISTER_CLASS(T)` expands to `ClassDB::register_class<T>()`; `GDREGISTER_ABSTRACT_CLASS`, `GDREGISTER_INTERNAL_CLASS` and `GDREGISTER_RUNTIME_CLASS` exist. **SRC** `include/godot_cpp/core/class_db.hpp:387-391`. This project registers at `MODULE_INITIALIZATION_LEVEL_SCENE`, not RUNTIME, so `@tool` code reaches the classes. **ADR** section 4; **OBS** `DogworksCore` is callable during the editor's first import scan.
- Instance methods: `ClassDB::bind_method(D_METHOD("name", "arg"), &Class::name)` inside `static void _bind_methods()`. **OBS** `native/src/core/toolchain_probe.cpp`.
- Static methods: `ClassDB::bind_static_method("Class", D_METHOD("name"), &Class::name)` (`class_db.hpp:187`, **SRC**). GDScript calls them as `Class.name()` and `ClassDB.class_call_static(&"Class", &"name")` reaches them too. **OBS** `test_class_call_static_reaches_bind_static_method` (Verification Required 9).
- Class constants are integer-only. A float cannot be bound as a constant, so `SIM_DT` is not bound; `sim_hz()` is. **ADR** section 4.
- Properties: `ADD_PROPERTY(PropertyInfo(...), "set", "get")` after binding the setter and getter. No property is bound by this story. **UNVERIFIED** in this project (not exercised).

## `Ref<T>` and construction
- RefCounted classes are held in `Ref<T>`. `Ref<T>::instantiate(args...)` forwards its arguments to the **C++** constructor (**SRC** `include/godot_cpp/classes/ref.hpp:193`). It is not what GDScript `.new()` calls.
- A GDScript `.new()` on a registered class takes **no arguments** and gives an object built with the default constructor. A class that needs arguments uses a bound static `create(packed) -> Ref<Class>` and `validate_packed(packed) -> String` that share one C++ validation function; `create` returns null on failure. **ADR** section 4; **OBS** `ToolchainProbe.create`/`validate_packed` called from typed GDScript, result assigned to `var probe: ToolchainProbe`.
- `.new()` gives an unbuilt object; every bound method guards on `built` with `ERR_FAIL_COND*`. **OBS** one passing refusal test per bound method.
- Do not use `new`/`delete` for Godot objects (`memnew`/`memdelete`); nodes added to the tree belong to the tree. **UNVERIFIED** here (no Node class in this story).
- Crossing cost measured from typed GDScript on the debug editor binary: about 0.01 us net for an int or a `Vector3` argument and about 0.05 us for a 64-float packed argument that C++ sums. The spike's 0.17 us figure is lower than the ADR's budget input and these figures are lower still; both are observations on one PC. **OBS** `runs/ptrcall.txt`.

## Packed arrays
- Packed arrays are copy-on-write. Returning a member array hands the caller an alias; a later `ptrw()` write while the caller still holds it detaches the buffer (one full copy), and the holder keeps the old data intact. **OBS** `runs/heap_held.txt`: a held 16 KiB array cost one 16,416-byte growth, then 0; the held array stayed intact. A caller that refreshes its reference every tick: 0 growth over 600 ticks (`runs/heap.txt`).
- Read input arrays through `ptr()`; never store them; never write through an input (`ptrw()` on an argument detaches, so the caller sees nothing). **ADR** section 3.
- `OBJECT_COUNT` cannot see packed arrays; measure with `OS.get_static_memory_usage()`. **ADR** Verification Required 5; **OBS** same runs.

## Destructors, RIDs and exit
- Free RIDs through one static helper called from both `dispose()` and the destructor, body then shape then space, and skip when `g_servers_alive` is clear. **ADR** section 4; **OBS** `ToolchainProbe`.
- A native object alive at quit, held by a GDScript static var, exits 0 with no RID error, with or without server RIDs. **OBS** `runs/exit_clean.txt`, `runs/exit_rid.txt`.
- A deliberately leaked object (extra `reference()` or a self-containing Array) does **not** crash on 4.8-beta3: exit code 0 plus "RID allocations of type ... were leaked at exit" and "ObjectDB instance was leaked at exit" lines. The ADR's "exit 139" expectation is not reproduced. **OBS** `runs/exit_leak.txt`, `runs/exit_leak_cycle.txt`.
- `NOTIFICATION_PREDELETE` in GDScript cannot call instance methods; irrelevant for native destructors. **OBS** `.claude/rules/godot-refcount.md`.

- `ptr()` on an empty packed array is not guaranteed to return a usable pointer (the engine returns null for an empty array on some paths). A native method that reads a packed argument checks `size() == 0` first and returns before calling `ptr()` (`ToolchainProbe::sum_packed` does, with a test). **UNVERIFIED** as an engine guarantee (godot-cpp wraps the engine call; not read here); the guard costs nothing.

## Hot reload (editor only)
- When the editor reloads a rebuilt extension, godot-cpp runs the terminator for each level, then `ClassDB::deinitialize`: `GDExtensionBinding::deinitialize_level` calls `init_data->terminate_callback(level)` first and `ClassDB::deinitialize(level)` after (`native/godot-cpp/src/godot.cpp:269-282`, **SRC**). The servers are still alive at the SCENE level when the terminator runs.
- So `uninitialize_module(SCENE)` frees the server objects of every live RID owner (a registry kept in `create()`, `dispose()` and the destructor) and clears each owner's `built` flag **before** it clears `g_servers_alive`. Otherwise an owner destroyed later skips its frees and its RIDs leak. **ADR** section 4; **OBS** `native/src/register_types.cpp`, `ToolchainProbe::release_all_server_objects`, and the `reload` mode of `tools/native_probe_runs.gd` (`runs/reload.txt`).
- After a reload, every native object is unbuilt (or replaced) and GDScript must call `create()` again. Only bound properties survive. **ADR** section 7.

## `ERR_FAIL_*`
- `ERR_FAIL_COND(cond)`, `ERR_FAIL_COND_V(cond, ret)`, `ERR_FAIL_NULL_V_MSG(p, ret, msg)`, `ERR_FAIL_COND_V_MSG` and `ERR_FAIL_V_MSG(ret, msg)` exist (`include/godot_cpp/core/error_macros.hpp`, **SRC**). They log an error and return.
- gdUnit4 6.2.3 classifies them as push errors: assert with `assert_error(callable).is_push_error(text)`. The text matched is the macro's own (`Condition "!built" is true. Returning: 0`, `Method/function failed. Returning: Ref<ToolchainProbe>()`), not the custom `_MSG` text. **OBS** `tests/unit/native/native_toolchain_test.gd`.
- Per-tick paths never print. **ADR** section 4.

## Engine and tooling observations
- gdUnit4 `mock(NativeClass)` returns an object, but its bound methods still run the native code; `spy(native_instance)` returns a copy that does not forward to the built original. Tests drive the real class. **OBS** `mock_spy_result.md`.
- `tools/build_native.sh` writes `.godot/extension_list.cfg` when it is missing, because the first `--import` of a project with an extension discovered during the first scan segfaults at exit (139) on 4.8-beta3, also with the spike DLL. **OBS** `upstream-bug-draft-first-import-segfault.md`.
- godot-cpp builds one target per scons run; `native/SConstruct` builds three variants (debug, release, bench) each with its own godot-cpp objects under `native/obj/<variant>/`. Cold build about 85 s per variant, incremental about 10 s. **OBS** `logs/build-times.txt`.
- The `/Z7` flag on compile lines comes from the SCons `PDB` variable. `native/SConstruct` sets `PDB` only for the variant that wants symbols (debug), so release and bench compile lines carry neither `/Z7` nor `/Zi`. godot-cpp's own `debug_symbols=yes` adds `/Zi`; with both set, MSVC prints warning D9025 ("overriding /Zi with /Z7"), which is harmless. **OBS** `logs/compile_lines-*.txt`, `logs/flag_scan-*.txt`.
