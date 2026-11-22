# Story 037: Blender exporter and fixture .glb files

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Estimate**: M
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: none for the pipeline itself (ADR-0005 is the spec); `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria) for the import refusals
**Requirement**: ADR-0005 Migration Plan step 3 and Validation Criteria (integration fixtures, NV-4, mover round trip, grep); ADR-0001 Validation Criteria (Blender axes)
**Roadmap step**: `architecture.md` Phase A Sequencing step 5 (roadmap item 024: Blender track pipeline end to end). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0005: Blender Track Pipeline (Accepted); ADR-0001: Simulation Conventions and Code Layout (Accepted)
**ADR Decision Summary**:
- ADR-0005: Editor-time import: a headless Blender exporter (`tools/blender/export_track.py`) writes one `.glb` with `kk_*` custom properties; a Godot `EditorScenePostImport` script (`import_script/path`, also run headless with `--import`) validates it (I1-I16) and bakes a binary `TrackPackage` (`.res`); any failed check refuses the file and names the reason. Runtime `GLTFDocument` is kept only as a future front end for user tracks.
- ADR-0001: Godot Y-up, -Z forward, metres; the synced race time is authoritative and the 60 Hz tick follows it with a defined catch-up policy; a fixed step order and one seeded random stream per consumer; our own interpolation with a teleport flag; mirror mode is a proper reflection at track load; the frozen 2.5D game lives in `src/legacy/`, shared data classes in `src/data/`, new code in new folders.

**ADR Version**: ADR-0005 2026-11-22; ADR-0001 2026-11-21

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Open NVs closed in the pipeline stories: NV-1 (keep `art_src/.gdignore` as the real guard), NV-10, NV-15 (fresh-clone first import), NV-16 (verified; re-run). Every script the baker touches is `@tool` and loaded by `preload` path. Blender 5.3 on the platform layer. Tick settings are pinned (`physics_ticks_per_second=60`, `max_physics_steps_per_frame=8`, `physics_interpolation=false`). Since 4.4 every script has a `.uid` sidecar. 4.8: strings can no longer be comments; a script can no longer inherit its own inner classes.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Exporter.** `tools/blender/export_track.py` (with `common.py`) runs headless in Blender and writes one `.glb` with `kk_*` custom properties per `track_schema.json`; an object facing Blender +Y and a pose empty with +Y along travel both arrive facing Godot -Z, +Y up, at 1:1 scale (ADR-0005; ADR-0001 Validation Criteria).
- [ ] **Fixtures.** A fixture Blender script builds committed fixture `.glb` files: an asymmetric track, a vertex at 1,900 m, a mover, and a failing fixture (ADR-0005 Validation Criteria).
- [ ] **Round trips.** Imported headless with `--import`: the asymmetric track's G4 positions reproduce; the 1,900 m vertex round-trips within 1 mm (NV-4); the mover's t = 0 key equals its node and `mover_pose` at t = period/2 matches Blender's sampled pose within 1 mm (ADR-0005 Validation Criteria).
- [ ] **Grep.** No `export_scene.gltf` call outside `tools/blender/` (ADR-0005 Validation Criteria).

---

## Implementation Notes

- Route curves are expanded into points by the exporter at `curve_expand_spacing_m`; the builder re-samples at `sample_spacing_m` (ADR-0004 §14).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 038-039: the post-import checks.
- Story 042: `legacy_to_blend.py`.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tools/blender/export_track.py`, `tools/blender/common.py`, `tools/blender/make_fixtures.py` (new)
- `tests/integration/pipeline/fixtures/*.glb` (new, committed)
- `tests/integration/pipeline/exporter_round_trip_test.gd` (new)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/pipeline/fixtures/*.glb` (new, committed), `tests/integration/pipeline/exporter_round_trip_test.gd` — must exist and pass; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-037/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-036-pipeline-pins-and-schema.md`
- Unlocks: `production/epics/core-rebuild/story-038-post-import-checks-i1-i8.md`
