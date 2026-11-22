<!-- PROTOTYPE - NOT FOR PRODUCTION -->
# Native spike (ADR-0007: hot simulation core in C++ via GDExtension)

**Status:** concluded 2026-11-22. Findings: `REPORT.md`.

## Hypothesis
Porting the analytic mover math and wrapping the static `PhysicsServer3D` `_into` queries in a C++ GDExtension (godot-cpp, MSVC) pays enough on this PC to justify ADR-0007, and the toolchain works against the 4.8-beta3 editor binary.

## Layout
- `src/` C++: `register_types.cpp`, `native_spike_query.{h,cpp}` (class `NativeSpikeQuery`, RefCounted). `src/.gdignore` keeps Godot from importing the `.obj` files.
- `SConstruct`, `build_godotcpp.bat` (vcvars64 + venv scons), `native_spike.gdextension`.
- `scripts/`: `gd_movers.gd` and `gd_static.gd` (GDScript references), `bench.gd`, `test_load.gd`, `track_gen.gd` (copy of the collision spike's).
- `run.sh` (one headless run), `run_all.sh` (all measurements, sequential), `out/` (raw outputs), `STATE.md` (progress notes).
- Not in git: `.venv/` (scons), `godot-cpp/` (commit 7fd5c4bc, `--depth 1`), `.godot/`, `bin/*.exp|lib|pdb`, `*.obj`, `*.import`, `~*.dll`, `.sconsign.dblite`. The built `bin/*.dll` are NOT ignored (see REPORT, Q5).

## Run (Windows, from this folder, in Git Bash)
1. One time: `python -m venv .venv`, then `.venv/Scripts/python -m pip install scons`; `git clone --depth 1 https://github.com/godotengine/godot-cpp.git godot-cpp`; in `out/` run the editor with `--headless --dump-extension-api --dump-gdextension-interface --dump-gdextension-interface-json`.
2. Build: `cmd //c ".\\build_godotcpp.bat template_debug"` and the same with `template_release`.
3. `godot --headless --path . --import` once (writes `.godot/extension_list.cfg`).
4. Check: `godot --headless --path . -s res://scripts/test_load.gd`.
5. Measure: `./run_all.sh` (never while compiling, never two Godot processes at once); compare: `./run.sh debug --part=compare`.
Use `--remote-debug tcp://127.0.0.1:24690` for any run that wants a debugger port, never 24680.

## Findings
See `REPORT.md`. Short: the toolchain worked first time; mover math is 22x (one call per query) to 49x (batched) faster in C++; the static path saves 16 to 34 percent; C++ is bit-deterministic against itself but not bit-identical to GDScript.
