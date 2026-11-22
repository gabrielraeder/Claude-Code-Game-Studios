<!-- PROTOTYPE - NOT FOR PRODUCTION -->
# Native spike: report for ADR-0007 (hot simulation core in C++ via GDExtension)

- **Date:** 2026-11-22. **Machine:** AMD Ryzen 7 7800X3D, Windows 11.
- **Engine:** `C:/Godot/Godot_v4.8-beta3_win64_console.exe` (4.8.beta3.official.c51ff06e8), headless debug editor binary in every measurement (the "release" rows are release builds of the extension only).
- **Toolchain:** MSVC 14.44.35207 (VS 2022 Build Tools), Python 3.14.0, SCons 4.11.1 in `.venv`, godot-cpp commit `7fd5c4bc3efda6487fd6e6486c50016faa622f92` (`--depth 1`).
- **Raw outputs:** `out/`. Observed unless marked **UNVERIFIED**. Written from the spike agent's report by the main session, which checked `out/bench_results.txt`.

## Q1. Toolchain

- **API dumps:** `godot --headless --dump-extension-api --dump-gdextension-interface --dump-gdextension-interface-json`, run in `out/`. The JSON flag is needed because current godot-cpp reads `gdextension_interface.json`.
- **Build:** `cmd //c ".\\build_godotcpp.bat template_debug"` (or `template_release`). The .bat calls `...\BuildTools\VC\Auxiliary\Build\vcvars64.bat`, then `.venv\Scripts\scons.exe platform=windows arch=x86_64 target=<t> gdextension_dir=out custom_api_file=out/extension_api.json`. `gdextension_dir=out` is required as well as `custom_api_file`. Bash cannot source the .bat, so MSVC is put on PATH inside `cmd`.
- **Times (15 jobs):**

  | Build | Time |
  |---|---|
  | First debug (godot-cpp plus a stub extension) | 86.5 s |
  | First release | 73.7 s |
  | Incremental, 2 sources changed | 7.8 s |
  | No-op rebuild | 6.8 s |

- **DLL sizes:** debug 437,760 B, release 398,336 B.
- **4.8-beta3 incompatibilities:** none seen. The bindings generated with no warnings; the `*_into` physics methods and result classes are bound.
- **Disk:** `godot-cpp/` 502 MB after the build, `.venv` 40 MB, `.sconsign.dblite` 15 MB. All are gitignored.
- **`.gdignore` is mandatory.** SCons writes `.obj` next to the sources and Godot imports `.obj` as 3D models. The first `--import` wrote four `src/*.obj.import` files, scanned the 500 MB godot-cpp folder, and **segfaulted**. Empty `.gdignore` files in `src/`, `godot-cpp/` and `.venv/` fix it: `--import` exits 0 in 2.6 s. Which of the two caused the segfault is UNVERIFIED.
- **Hang:** one `godot --headless --path . --quit` hung. This project has no main scene. Cause UNVERIFIED.
- **Float flags:** `/fp:precise`, no `/fp:fast`, no `/fp:contract`, no `/arch:AVX2` (plain SSE2), for reproducible rounding on any x86-64 CPU. The rest are godot-cpp defaults (not dumped, UNVERIFIED).

## Q2. Loading and calling

- **Loading:** the extension loads headless. Checked with `scripts/test_load.gd`, a plain SceneTree script; gdUnit4 against the class is **UNVERIFIED**.
- **Construction:** `ClassDB.instantiate("NativeSpikeQuery")` gives a RefCounted. `NativeSpikeQuery.new()` was not tried (UNVERIFIED).
- **Typed arguments and results:** all passed. Vector3 in and out; Transform3D round trip and as a result; PackedFloat32Array in; RID round trip; PackedVector3Array in and PackedFloat64Array out.
- **RID ownership:**
  - The C++ class creates a space, 2 bodies and 3 shapes (6 RIDs) and answers a ray correctly.
  - The destructor frees bodies, then shapes, then the space. After the last reference dropped, freeing each RID again gave 6 "RID has no owner" errors, which shows all were freed.
  - Untested: shutting down the engine while the object is alive, and a wrong free order.

## Q3. Speed (µs per tick; median across 3 runs of each run's median / p95; 600 timed ticks after 120 warm-up)

### Mover math

12 karts × (4 rays + 3 sweeps) against 5 spinning solid 16 m boxes. This is a synthetic layout following the description in `tools/bench_collision.gd`, not its track fixture.

| Mode | median | p95 | vs GDScript |
|---|---|---|---|
| GDScript (copied routines) | 542 | 574 | 1x |
| C++ debug, one call per query (84 calls) | 25 | 27 | 22x |
| C++ release, one call per query | 22 | 24 | 25x |
| C++ debug, one batched call per tick | 11 | 13 | 49x |
| C++ release, one batched call per tick | 12 | 13 | 45x |

Crossing the GDScript/C++ boundary costs about 0.17 µs per call, so about 14 µs per tick for 84 calls.

### Static path

12 × (4 rays + 3 sweeps with rest checks) through `PhysicsServer3D` `_into`, on a 48,006-triangle code-built mesh.

| Mode | median | p95 |
|---|---|---|
| GDScript `_into` calls | 77 | 84 |
| C++ debug, per call | 65 | 74 |
| C++ release, per call | 62 | 69 |
| C++ debug, batched | 51 | 58 |
| C++ release, batched | 51 | 58 |

- The engine floor is about 51 µs.
- The thin GDScript loop adds about 26 µs.
- The real `CollisionQuery` costs 170–190 µs on the static path (story 007). How much of that is GDScript overhead was not measured here (UNVERIFIED).

## Q4. Determinism

- **Run to run:** the SHA-256 of all outputs is identical across runs in each mode. C++ debug, C++ release, per-call and batched all give `80cd8ca5…`. GDScript gives `8aaea6b4…`.
- **GDScript vs C++** (`out/compare_debug.txt`, 720 ticks):
  - rays: 0 of 34,560 differ;
  - sweep fractions: 188 of 25,920 differ, max 4.5e-4;
  - sweep normals: 1,354 of 77,760 differ, max 3.9e-5;
  - mover poses: 63 of 1,000 differ, by at most 2.4e-7 (one float32 ulp);
  - static engine calls: 0 of 60,480 differ.
- **Likely cause (UNVERIFIED):** `Quaternion::slerp` trig compiled differently in the engine and in the extension. A one-ulp pose difference flips bisection comparisons, which amplifies to the sweep tolerance.
- **Consequence:** one implementation must be the source of truth. The GDScript version can serve as an oracle only with a tolerance, not bit equality. Cross-machine determinism was not tested.

## Q5. Workflow

- **Hot reload in the GUI editor:** UNVERIFIED. With `reloadable = true`, Godot loads a `~` copy of the DLL, so the linker can still write the original.
- **Fresh clone needs:** Python, MSVC Build Tools, a venv with SCons, the pinned godot-cpp, the API dumps from the pinned editor, a build (about 90 s cold), then `--import` once.
- **DLLs in git:** the agent's opinion is to build them, or produce them in CI, rather than commit them (about 800 KB of churn per rebuild, and a stale DLL fails silently). Committing them (about 400 KB each) is workable when a PC has no toolchain. This is the owner's call.
- **Export:** not tried, because 4.8-beta3 templates are not installed (UNVERIFIED). A `template_release` build is required. `compatibility_minimum = "4.8"`.
- **On each engine upgrade:** re-dump the API, rebuild every target, and re-test.

## Recommendation (spike agent; not a decision)

1. **Native from story 009 on:** the collision core as one class (mover pose cache, ray and sweep tests, static `_into` queries, RID ownership). It is data in, data out, and has the largest gain (22–49x on mover math).
2. **Batched API:** one call per tick, with packed arrays in and one PackedFloat64Array out.
3. **GDScript first, ported when a profile asks:** vehicle integration, AI, items, UI. Keep the GDScript version as an oracle with a tolerance (about 5e-4 on sweep fractions).
4. **One source of truth** for values that both the simulation and presentation compute (mover pose).
5. **Layout:** `native/` (C++, SConstruct, pinned godot-cpp, `.gdignore`); `bin/` (`.gdextension` plus DLLs); `tools/build_native.bat`; `tests/unit/native/`.
6. **Before committing:** run gdUnit4 against the class, try `.new()`, test hot reload in the GUI editor, and export with real templates.
