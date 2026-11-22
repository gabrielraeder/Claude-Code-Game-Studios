# Story 001: Freeze the 2.5D game and capture the regression oracle

> **Epic**: Core Rebuild (Phase A)
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Integration
> **Estimate**: L
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: 2026-11-22

## Context

**GDD**: none (infrastructure; spec is `docs/architecture/architecture.md` Rebuild Strategy and Test Harness sections)
**Requirement**: architecture.md "Rebuild Strategy" (freeze, capture the oracle, retire don't delete) and "Test Harness and Regression Oracle"

**ADR Governing Implementation**: ADR-0001: Simulation Conventions and Code Layout
**ADR Decision Summary**: The frozen 2.5D code moves as-is to `src/legacy/` in two commits (a pure move with `.uid`/`.import` sidecars, then a scripted rewrite of every plain `res://src/...` path, including `run/main_scene`), shared data class scripts (`VehicleStats`, `VehicleVisualStats`, `SurfaceSet`, `SurfaceType`, `ItemDef`, `ItemSet`, `RacerDef`, `RacerSet`, `BotPersonality`, `NetConfig`, `AudioEventDef`, `AudioSet`, `UiTheme`, `HitSlowdownProfile`, `PennantStyle`) move to `src/data/` and must form a set closed under the types they reference; the tick settings are pinned (`physics_ticks_per_second=60`, `max_physics_steps_per_frame=8`, `physics_interpolation=false`, `physics_jitter_fix=0.0` if the key exists in 4.8); the golden traces must reproduce exactly after the move.
**ADR Version**: 2026-11-21

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Since 4.4 every script has a `.uid` sidecar and `uid://` is the primary reference; a moved script must keep its sidecar or every uid reference breaks. 4.8 breaks: strings can no longer be comments; a script can no longer inherit its own inner classes (grep the frozen code for both).

---

## Acceptance Criteria

- [x] **Golden traces.** A capture tool records, per tick, for scripted headless autopilot runs (Castle Circuit and Dungeon Depths, armored cart and war-bike, 1 lap each) and one headless bot race per track (host + 11 bots, 1 lap): kart id, tick, position (x, z), height, speed, yaw, drift state, boost, lap, lap times. Traces are stored under `production/qa/evidence/core-rebuild-story-001/golden/`.
- [x] **Reproducibility.** Two captures in a row on the same machine are identical; if any run is not, the story names the source of non-determinism and either fixes it in a hotfix-scoped way or records the tolerance the comparison uses.
- [x] **Comparison tool.** A compare tool reports IDENTICAL, or the first diverging tick, kart and field, with the two values.
- [x] **One regression command.** `tools/regression.sh` runs `track_check` on both tracks, the existing shell tests (`bot_race_test.sh`, `item_net_test.sh`, `bump_test.sh`, a short `net_stress_test.sh`), the trace capture and the compare, prints one PASS/FAIL line per check and exits non-zero on any failure. It uses port 24690 and never kills processes it did not start.
- [x] **Performance baseline.** The host's ms per tick for 12 karts (1 autopilot + 11 bots) on Castle Circuit is recorded (median and 95th percentile), with the machine it ran on.
- [x] **Test framework.** gdUnit4 is installed, `tests/unit/` and `tests/integration/` exist, and one example test passes with `commands.test` from `project.yaml`.
- [x] **Tag.** `v0.11-2.5d` tags the last commit before the move.
- [x] **The move.** The frozen code is in `src/legacy/` and the shared data classes in `src/data/`, done as ADR-0001 §9 says (move commit, then path commit, then cache rebuild); the shared set is closed (no `src/data/` script references a `src/legacy/` class); `run/main_scene` points at `res://src/legacy/main.tscn`; loading the project prints no uid warnings.
- [x] **Same game after the move.** `tools/regression.sh` passes and the golden traces reproduce exactly (or within the recorded tolerance) after the move.
- [x] **Settings and 4.8 checks.** The tick settings above are pinned in `project.godot`; greps for string-as-comment blocks and inner-class self-inheritance in the frozen code are clean (or fixed as hotfixes).
- [x] **Still playable.** The game launches windowed from the moved main scene and a race starts; a retained screenshot shows it.

---

## Implementation Notes

- Capture tools live under `tools/` (debug-only values may be named constants there). New tools must not add gameplay values to code.
- The move and the path rewrite are separate commits; the path rewrite is done by a script and covers `.tscn`, `.tres`, `.gd` (`preload`/`load`), `project.godot`, `.cfg`, `.json`, tools and tests. Keep `uid=` values unchanged.
- The frozen code's behaviour must not change. Any fix needed for 4.8 checks or determinism is a hotfix to the frozen game and is listed under Completion Notes.
- Follow `.claude/rules/godot-refcount.md` for any new `connect(`.

---

## Out of Scope

- Any new-core code (collision, kart body, course data): later stories.
- Changing tuning values or behaviour of the frozen game.
- Deleting `src/legacy/` (owner-approved, after A3).

---

## Files

- `tools/capture_traces.gd`, `tools/capture_all_traces.sh`, `tools/compare_traces.py`, `tools/regression.sh`, `tools/check_data_closure.py` (new)
- `addons/gdUnit4/` (v6.2.3), `tests/unit/data/item_set_roll_test.gd`, `tests/integration/.gitkeep` (new)
- `src/legacy/**` and `src/data/**` (moved, 164 pure renames), 22 `.tres`/`.tscn`/`.gd` path rewrites, `tools/gen_*.py` path rewrites
- `project.godot` (main scene path, pinned `[physics]` tick settings), `.godot/global_script_class_cache.cfg`
- `production/qa/evidence/core-rebuild-story-001/` (oracle, scripts, reports, screenshots)

## QA Test Cases

*N/A — no qa-lead specs for this story; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tools/regression.sh` output before and after the move, the golden traces and compare reports, the gdUnit4 example test run, a retained screenshot
**Status**: [x] Created: production/qa/evidence/core-rebuild-story-001/ (regression-before/after, golden + compare, perf-baseline.md, gdunit4-example-run.txt, screenshots/drive_t10.png)

---

## Dependencies

- Depends on: ADR-0001 (Accepted)
- Unlocks: the collision and Blender round-trip spike; story 022

## Completion Notes
**Completed**: 2026-11-22
**Criteria**: 11/11 passing (golden traces IDENTICAL x6 and reproducible; one-command regression RESULT PASS (6/6 checks) after hardening; perf baseline 3.4 ms median / 6.3 ms p95; gdUnit4 3/3; tag v0.11-2.5d; move and path commits clean, data set CLOSED, no uid warnings; settings pinned; 4.8 greps clean; windowed race screenshot)
**Deviations**: (1) Pinning `physics_jitter_fix = 0.0` (ADR-0001) changes the frozen game's windowed frame pacing slightly from the engine default 0.5; the headless oracle (`--fixed-fps 60`) does not cover windowed play. (2) TD-011: a near-tie for first can show a different lead-change sequence per PC in net_stress (about 1 in 5 runs, finish places always agree); reported as WARN by regression.sh, not fixed in the frozen game. (3) Oracle tools hardened after LP-CODE-REVIEW (no vacuous PASS: CHECKS names, track_check ALL PASS line, empty traces, expected golden count, empty hit logs, empty closure dirs, wider error patterns), each proven by a negative run in production/qa/evidence/core-rebuild-story-001/harden/.
**Test Evidence**: production/qa/evidence/core-rebuild-story-001/ (golden/, regression-*.txt, harden/full.txt, harden/neg-*.txt, compare-negative.txt, gdunit4-after-move.txt, harden/gdunit4.txt, perf-baseline.md, perf-per-system.md, screenshots/drive_t10.png)
**Reviewed by**: lead-programmer (LP-CODE-REVIEW: CONCERNS, revised and re-run); qa-lead (QL-TEST-COVERAGE: GAPS, closed by runs)

## Calls beyond the design
- Extra tools `tools/capture_all_traces.sh` (run list) and `tools/check_data_closure.py` (repeatable closure check) · kept 2026-11-22
- `tools/regression.sh`: `CHECKS=` subsets, default output `production/qa/regression/<timestamp>`, PASS rules per check · kept 2026-11-22
- Trace format: tick 0 is the first racing tick; extra fields race_time, track_s, drifting, drift_dir; exact float text · kept 2026-11-22
- Race seed 1001 for traces; bot traces end when the host's autopilot finishes · kept 2026-11-22
- Perf measured headless by recorder nodes around the frozen tick · kept 2026-11-22
- gdUnit4 editor plugin not enabled (CLI runner needs none); example test on `ItemSet.roll` with an in-test set · kept 2026-11-22
- Data classes flat in `src/data/`; path rewrite scope src/, assets/, tools/, tests/, project.godot; annotated tag · kept 2026-11-22
