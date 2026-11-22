# Story 001: Freeze the 2.5D game and capture the regression oracle

> **Epic**: Core Rebuild (Phase A)
> **Status**: In Progress
> **Layer**: Foundation
> **Type**: Integration
> **Estimate**: L
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: 2026-11-21

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

- [ ] **Golden traces.** A capture tool records, per tick, for scripted headless autopilot runs (Castle Circuit and Dungeon Depths, armored cart and war-bike, 1 lap each) and one headless bot race per track (host + 11 bots, 1 lap): kart id, tick, position (x, z), height, speed, yaw, drift state, boost, lap, lap times. Traces are stored under `production/qa/evidence/core-rebuild-story-001/golden/`.
- [ ] **Reproducibility.** Two captures in a row on the same machine are identical; if any run is not, the story names the source of non-determinism and either fixes it in a hotfix-scoped way or records the tolerance the comparison uses.
- [ ] **Comparison tool.** A compare tool reports IDENTICAL, or the first diverging tick, kart and field, with the two values.
- [ ] **One regression command.** `tools/regression.sh` runs `track_check` on both tracks, the existing shell tests (`bot_race_test.sh`, `item_net_test.sh`, `bump_test.sh`, a short `net_stress_test.sh`), the trace capture and the compare, prints one PASS/FAIL line per check and exits non-zero on any failure. It uses port 24690 and never kills processes it did not start.
- [ ] **Performance baseline.** The host's ms per tick for 12 karts (1 autopilot + 11 bots) on Castle Circuit is recorded (median and 95th percentile), with the machine it ran on.
- [ ] **Test framework.** gdUnit4 is installed, `tests/unit/` and `tests/integration/` exist, and one example test passes with `commands.test` from `project.yaml`.
- [ ] **Tag.** `v0.11-2.5d` tags the last commit before the move.
- [ ] **The move.** The frozen code is in `src/legacy/` and the shared data classes in `src/data/`, done as ADR-0001 §9 says (move commit, then path commit, then cache rebuild); the shared set is closed (no `src/data/` script references a `src/legacy/` class); `run/main_scene` points at `res://src/legacy/main.tscn`; loading the project prints no uid warnings.
- [ ] **Same game after the move.** `tools/regression.sh` passes and the golden traces reproduce exactly (or within the recorded tolerance) after the move.
- [ ] **Settings and 4.8 checks.** The tick settings above are pinned in `project.godot`; greps for string-as-comment blocks and inner-class self-inheritance in the frozen code are clean (or fixed as hotfixes).
- [ ] **Still playable.** The game launches windowed from the moved main scene and a race starts; a retained screenshot shows it.

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

- `tools/capture_traces.gd`, `tools/compare_traces.py` (or `.gd`), `tools/regression.sh` (new)
- `addons/gdUnit4/`, `tests/unit/`, `tests/integration/` (new)
- `src/legacy/**`, `src/data/**` (moved), `project.godot`
- `production/qa/evidence/core-rebuild-story-001/` (traces, perf baseline, screenshot, STATE.md)

---

## QA Test Cases

*N/A — no qa-lead specs for this story; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tools/regression.sh` output before and after the move, the golden traces and compare reports, the gdUnit4 example test run, a retained screenshot
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: ADR-0001 (Accepted)
- Unlocks: the collision and Blender round-trip spike; story 022
