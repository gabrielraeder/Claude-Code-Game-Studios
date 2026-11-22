---
paths:
  - "native/**"
---

# Native Code Rules (dogworks_core, C++17 via godot-cpp)

Source of truth: `docs/architecture/adr-0007-native-simulation-core.md` (section 4, Implementation Guidelines). Engine and binding facts: `docs/engine-reference/godot/godot-cpp.md`. Every rule below is the ADR's, restated for `native/**`.

## Language and types
- C++17, godot-cpp at the commit in `native/GODOT_CPP_COMMIT`. Use engine types where a value crosses the boundary or calls the engine.
- Scalars are `double`. Vectors and bases stay godot-cpp float32 types (`Vector3`, `Basis`, `Quaternion`, `Transform3D`).
- `constexpr int SIM_HZ = 60` and `constexpr double SIM_DT = 1.0 / SIM_HZ` live in C++; GDScript keeps its own `SIM_DT`. No time value crosses the boundary: `begin_tick(tick)` takes the tick.
- Tuning values stay in `.tres`. Debug-only constants may be named `constexpr`.

## Per-tick code
- No allocation after build: no `new`/`memnew`, no container growth, no `String`/`Variant`/`Dictionary` creation, no RID creation. Size containers when a track loads or a race is set up.
- Never read a Resource property or a GDScript script property from C++. Read the caller's packed input arrays through `ptr()` (after checking `size() == 0` and returning early: `ptr()` on an empty array is not guaranteed usable), never store them as members, and never write through a packed argument (`ptrw()` on it detaches, so the caller never sees the writes).
- Per-tick paths never print. `ERR_FAIL_*` and `push_error` belong at load-time boundaries; the stage-order assert is not debug-only.
- Step in slot order; iteration never depends on a hash container. Randomness: one `RandomNumberGenerator` per consumer, created at setup and seeded from the GDScript-computed seed. Forbidden in per-tick code: `rand()`, `<random>`, `std::random_device`, the global `randf`, unordered containers.
- Outputs are double-buffered packed arrays (buffer `tick & 1`); a consumer never writes through a returned array.

## Registration and construction
- `GDREGISTER_CLASS` at `MODULE_INITIALIZATION_LEVEL_SCENE`. Not `GDREGISTER_RUNTIME_CLASS` (editor-time `@tool` code must reach the classes). `GDREGISTER_ABSTRACT_CLASS` for non-instantiable bases. `DogworksCore` first; bases and result types before the classes whose APIs use them.
- No static initialisers that call engine APIs. No autoload names a native type.
- In `bind_static_method` and `bind_method` use `get_class_static()` for the class name, not a string literal. Zero-fill output buffers explicitly at `create()`. A function that allocates (for example `marker_part`) says in its doc comment that it is load-time only.
- Native classes take no `.new()` arguments. A class that needs arguments has a bound static `create(packed) -> Ref<Class>` (built with `instantiate()`, null on failure) and a bound static `validate_packed(packed) -> String` that calls the same C++ validation function.
- `.new()` stays callable and gives an unbuilt object. Every bound method guards on the `built` flag with `ERR_FAIL_COND` / `ERR_FAIL_COND_V`. Test one refusal per bound method.
- Constructors touch no server and create no RID; all server work is in `create()`.

## RID ownership and teardown
- A RefCounted owner frees bodies, then shapes, then the space, through one static helper called from both `dispose()` and the destructor.
- `dispose()` is mandatory: the composition root and every test teardown call it. **`dispose()` is idempotent** by convention: on an unbuilt or already disposed object it is a silent no-op (no `ERR_FAIL`), so a teardown can call it without tracking state. It is the one bound method exempt from the `built` refusal; its test asserts the silence.
- Keep a registry of the objects that own server RIDs (add in `create()`, remove in `dispose()` and the destructor). `uninitialize_module(SCENE)` frees every registered owner's server objects and clears its `built` flag **before** it clears `g_servers_alive`, so a hot reload or an exit does not leak RIDs. After a reload GDScript calls `create()` again.
- Every RID-freeing destructor checks `dogworks::g_servers_alive` (set in `initialize_module(SCENE)`, cleared in `uninitialize_module(SCENE)`) and skips when it is clear. `get_singleton() != nullptr` does not prove a server exists.
- `create()` fails loudly (`ERR_FAIL_NULL`) and returns null when a server is missing.
- A leaked native object shows at exit as "RID allocations ... leaked" and "ObjectDB instance ... leaked" lines (exit code 0 on 4.8-beta3, not a crash). `tools/native_exit_safety.sh` fails on those lines.

## Determinism and build
- MSVC `/fp:precise`, no `/fp:fast`, no `/arch:AVX2` (SSE2 baseline), static CRT (`/MT`). The pinned command line is in `production/qa/evidence/core-rebuild-story-066/logs/compiler_command_line-*.txt`.
- Transcendentals are not bit-identical across CPUs (accepted: same-machine determinism only). Golden traces are never compared across PCs.
- Native queries run on the main thread inside the physics tick only; never from a worker thread.

## Layout, docs and workflow
- One subfolder per system under `native/src/` (`collision/`, `kart/`, `drive/`, `course/`, `items/`, `ai/`, `race/`, `core/`), one class per file pair. Every class and public method has a doc comment; bound methods carry their GDScript-facing docs.
- The hashed file list is `native/hash_files.txt`. Every hashed file is LF (`.gitattributes`). A new top-level hashed file goes in that list.
- `tools/build_native.sh` builds; `tools/build_native.sh --check` must pass before tests or regression run. A native class name never equals a GDScript `class_name`.
- Native stories go to `godot-gdextension-specialist`. Tests that depend on tick order go through `RaceSim`. gdUnit4 `mock()`/`spy()` do not work on native classes; tests drive the real class and call `tests/unit/native/native_test_guard.gd` in `before()`.
