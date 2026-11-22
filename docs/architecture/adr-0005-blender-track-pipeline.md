# ADR-0005: Blender Track Pipeline

## Status
Proposed

## Date
2026-11-22

## Last Verified
2026-11-22

## Decision Makers
Drafted v1 by tools-programmer (subagent) from the collision and Blender round-trip spike (`prototypes/collision-spike/REPORT.md` Q4 and Recommendations, `out/q4_post_import.txt`, `out/q4_runtime.txt`) and from a re-run of the spike's read-only `blender/probe_exporter.py` on Blender 5.3, 2026-11-22. **v2 (2026-11-22)** is the revision after the joint TD-ADR review of ADR-0004 and ADR-0005 (technical-director: CONCERNS on both). It moves the course derivation into ADR-0004's `CourseBuilder` and applies the owner-side decisions logged with that review. **v3** applies the TD re-review of v2. It adds NV-16, distinct per-object resource ids, a builder-aware `bake_key`, and corrects capsule conversion and stale text.

**Review status:**
- **godot-specialist:** probes ran (`prototypes/collision-spike/out/probe_adr45_*`); their verdicts are in the NV table below. The full validation review (step 5.5) is NOT ASSESSED.
- **technical-director review (TD-ADR):** v1 CONCERNS (joint with ADR-0004). v2 addresses every required item; the v2 re-review returned CONCERNS (narrow text edits), applied in v3; a re-review of v3 is NOT ASSESSED.
- **Owner acceptance:** pending. **Owner approval also pending** for the ADR-0001 §9 amendment in ADR-0004 §15 (legacy extractor), which this ADR's Migration Plan relies on.

## Summary
Tracks are authored in Blender, and the rebuilt core needs them as `TrackCollisionData` (ADR-0002), `CourseData` (ADR-0004), a visual scene and a theme. Validation has to happen before a race ever loads, and the loop must stay fast enough for track iteration.

This ADR chooses an **editor-time import**:
- A headless Blender exporter (`tools/blender/export_track.py`) writes one `.glb` with `kk_*` custom properties.
- A Godot `EditorScenePostImport` script (`import_script/path`, also run headless with `--import`) validates the file and bakes a binary **`TrackPackage` (`.res`)**.
- Any failed check refuses the file and names the reason.
- Runtime `GLTFDocument` is kept only as a future front end for user tracks.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.8-beta3; Blender 5.3 (glTF 2.0 exporter bundled with it) |
| **Domain** | Core (asset import and tooling) |
| **Layer** | Core |
| **Knowledge Risk** | HIGH. Godot 4.8 is post-cutoff and pre-release. Blender 5.x is post-cutoff. **The engine reference does not cover the import pipeline:** NOT SOURCEABLE — `EditorScenePostImport`, scene import options, `GLTFDocument` and `ResourceSaver` behaviour during import are not covered by `docs/engine-reference/godot/` (its only import entry is the FBX importer rename in `breaking-changes.md`). Every claim in this ADR about those APIs comes from the spike or is marked **NEEDS VERIFICATION** (NV-n, listed below). |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `breaking-changes.md`, `deprecated-apis.md` (no import coverage). `prototypes/collision-spike/REPORT.md` Q4, `scripts/post_import.gd`, `scripts/scene_dump.gd`, `scripts/q4_runtime.gd`, `blender/build_track_piece.py`, `import_test/track_piece.glb.import`, `out/q4_post_import.txt`, `out/q4_runtime.txt`. ADR-0001 §1, §2, §7, §9. ADR-0002 "TrackCollisionData", "Boot and load checks", "Mirror". `architecture.md` "Tool layer", Data Flow 6. `tools/blender/common.py` |
| **Post-Cutoff APIs Used** | Godot: none new. `EditorScenePostImport` and `GLTFDocument` predate the cutoff, but they are used here on a post-cutoff engine. The import-time probe check calls ADR-0002's `CollisionQuery`, which uses the 4.8 `_into` query methods. Blender 5.3: the `export_scene.gltf` operator properties listed under "Verified" below |
| **Verified on 4.8-beta3 / Blender 5.3** | See the list below this table |
| **Verification Required** | NV-1 … NV-16 below. Story 024 closes them before this ADR is Accepted, or records the fallback taken |

**Verified (spike Q4, plus the exporter property dump of 2026-11-22):**
1. **B1:** Blender 5.3 exports a valid GLB with `export_format='GLB', export_yup=True, export_extras=True, export_apply=True` (spike `build_track_piece.py`).
2. **B2:** Exporter defaults in Blender 5.3, from the operator property dump:
   - off by default: `export_extras`, `export_apply`, `export_lights`, `export_cameras`, `use_selection`, `use_visible`, `export_hierarchy_full_collections`;
   - on by default: `export_animations`, `export_skins`, `export_texcoords`, `export_normals`, `export_optimize_animation_size`.

   **The exporter therefore passes every flag explicitly.** A forgotten `export_extras` drops every `kk_*` property silently.
3. **G1:** Object custom properties arrive as node meta `extras`, a `Dictionary`.
   - **Integers arrive as `float`** (`kk_index: 0.0`).
   - Bools and strings keep their type.
   - Runtime `GLTFDocument` gives the same result.
4. **G2:** Material custom properties arrive as material meta `extras`. They were seen in the spike, and this ADR does not use them.
5. **G3:** A material's `resource_name` equals its Blender material name (`surf_road`). The imported mesh has **one surface per material**.
6. **G4:** Blender `(x, y, z)` lands as Godot `(x, z, −y)`: marker tip `(0, 2, 0)` → `(0, 0, −2)`, world `(5, 20, 1)` → `(5, 1, −20)`.
   - 1 unit = 1 m.
   - Empty transforms are kept. An `ARROWS` empty's local +Y lands as Godot −Z (`CP_0` faces −Z; `Respawn_0`, rotated 30°, faces `(−0.5, 0, −0.866)`).
7. **G5:** In `_post_import`, `MeshInstance3D.mesh.surface_get_arrays(i)`, read as `ARRAY_VERTEX` + `ARRAY_INDEX` in index order and taken through the node's global transform, gives **Godot-front winding**: `(c − a) × (b − a)` is the outward normal.
   - It points up on road and ramp, and inward on walls authored inward.
   - `surface_get_material(i)` gives the surface's material.
8. **G6:** `import_script/path` on a `.glb` runs an `EditorScenePostImport` under headless `--import`. `set_meta` in `_post_import` persists into the saved scene.
9. **G7:** Runtime `GLTFDocument.append_from_file` + `generate_scene` gives identical nodes, meta, materials and winding (0.55 ms for the test piece).
10. **G8:** Blender exports `doubleSided: true` by default, which imports as `cull_mode = 2` (disabled). This affects the visual only; collision winding is unaffected.
11. **G9:** A wrong vertex order produced outward-facing walls, which are invisible to one-sided Jolt. This is the reason for the wall-normal check.
12. **G10:** A `SINGLE_ARROW` empty is believed to point along local +Z (UNVERIFIED in the spike), so an author aligning one would point the pose wrong. `ARROWS` is verified.

**NEEDS VERIFICATION (each one is closed by story 024, with evidence retained):**

| ID | Claim the design relies on | Fallback if false |
|---|---|---|
| NV-1 | `filesystem/import/blender/enabled = false` exists in 4.8 and stops `.blend` import. A `.gdignore` in `art_src/` hides the folder from the editor | Keep `.blend` files outside the Godot project root |
| NV-2 | Blender collections are not glTF nodes when `export_hierarchy_full_collections = False`. The design does not depend on this either way (see `kk_layer`) | None needed |
| NV-3 | `nodes/use_name_suffixes = false` and `nodes/use_node_type_suffixes = false` turn off Godot's `-col` / `-colonly` / `-noimp` name hints. The keys exist in the spike's `.import`; their behaviour was not exercised | The exporter rejects object names that end in a hint suffix |
| NV-4 | `meshes/force_disable_compression = true` keeps the vertex positions that `_post_import` reads at full float32. Unverified: whether compression or LOD generation runs before the script at all, and the precision at 1.9 km from the origin | Bake from the `GLTFState` buffers through a `GLTFDocumentExtension`, a separate decision |
| NV-5 | What makes a scene import **fail** from `_post_import` (returning `null`, or an error), and whether the `--import` exit status reflects it | **SETTLED (silent failure).** Decide only from the `TRACK_IMPORT RESULT` line. On a fail the post-import script deletes any existing `*.track.res`. Optionally it returns a stripped scene carrying the failure as meta instead of `null` |
| NV-6 | `ResourceSaver.save` of a new `.res` under `res://` from inside `_post_import`, headless, with no reimport loop. Save to a temporary path, then rename over the target on Windows | Return the package as root meta (Resource-valued meta persists, embedded in the imported scene) and have a post-import tool script write it |
| NV-7 | **VERIFIED (probe):** instance methods of non-`@tool` data scripts run from the post-import script, so `@tool` is not required for that. **Decision kept:** every script the baker touches is still marked `@tool` (`src/core/course/*`, `src/data/surface_set.gd`, `surface_type.gd`, `wall_attr_set.gd`; additive per ADR-0001 §9), only as cheap insurance for the fresh-clone case (NV-15), where script classes are not yet registered. The post-import script loads them by `preload("res://…")` path, not by `class_name`. Story 024 proves it on a clean clone in CI. If NV-15 passes without `@tool`, drop the marks | If a script cannot be `@tool`, the baker gets that data through a `@tool` adapter that the post-import script constructs |
| NV-8 | A string extra of about 40 KB (`kk_keys`) arrives intact. This design uses scalar and string extras only; arrays are avoided because they were not exercised | Split keys across `kk_keys_0..n` |
| NV-9 | Blender: `scene.frame_set` + `matrix_world` sampling, collection iteration, and a non-zero process exit on failure (`--python-exit-code`, `sys.exit`) | The wrapper greps the `FAIL` lines whatever the exit code |
| NV-10 | An export preset includes the visual `.glb` scene that the package references only by path string | Reference it as an `ext_resource`, after checking that this causes no dependency cycle during import |
| NV-11 | `.glb.import` `[params]` written by a tool before the first import are honoured by `--import` | The author sets the preset once in the Import dock; track_check still verifies it |
| NV-12 | Runtime `GLTFDocument` for user tracks: cost at 150k triangles, and the safety of loading untrusted files | Deferred. Its own ADR before user tracks ship |
| NV-13 | `FileAccess.get_sha256(path)` on `res://` paths in editor and headless runs | `HashingContext` over the file bytes |
| NV-14 | Negative-scale objects in Blender. How winding survives export and import is unknown, so the design forbids them and only the rejection is needed | None needed |
| NV-15 | **Fresh-clone first import.** On a clean clone (no `.godot/`, no `*.track.res`), one headless `--import` registers the `@tool` scripts, runs the post-import script, bakes the package and saves it, with no second pass. Runs in CI | Two-pass import in `tools/track_build.sh` (script-class scan, then import); if that fails too, Git LFS for the baked package (Alternative 7) |
| NV-16 | **`CollisionQuery` inside `_post_import`.** Running ADR-0002's `CollisionQuery` (private Jolt space, face-index setting) from the post-import script, under headless `--import` and on an editor reimport, is **unprobed** (a probe is running). I11, I15 and the builder depend on it | Return the parsed `CourseAuthoring` and collision data as Resource-valued root meta (it persists) and run I11, I15 and the builder in the `track_build` step from a headless `SceneTree`, which then writes the package |

**Probe verdicts (godot-specialist, 2026-11-22; evidence in `prototypes/collision-spike/out/probe_adr45_*.txt`). Story 024 re-runs and retains them on the real pipeline:**
- **VERIFIED:** NV-2, NV-3, NV-4, NV-6, NV-7, NV-8 (a 40 KB string extra arrives intact), NV-11, NV-13.
- **NV-9 VERIFIED with a fix:** sampling and exit codes work, but an uncaught Python exception exits 0 unless `--python-exit-code 1` is passed (§3), and `tools/track_build.sh` requires the `EXPORTED` line instead of only grepping for FAIL.
- **NV-14 observed:** a negative-scale object flips winding. The forbid rule is right.
- **NV-5 settled as a silent failure:** returning `null` from `_post_import` prints no error and `--import` exits 0. Over an earlier good import the old imported scene stays and keeps loading. Success is decided **only** from the `TRACK_IMPORT RESULT` line (§4).
- **NV-6 correction:** `ResourceSaver.save` to a temporary path then rename inside headless `_post_import` works. **Resource-valued meta does persist**, embedded in the imported scene, so the meta fallback is real.
- **Unverified:** NV-1 (keep `art_src/.gdignore` as the real guard; re-test the setting in story 024), NV-10. **Deferred:** NV-12. **Open until story 024:** NV-15.
- **Surface names verified:** per-surface arrays with `surface_get_material(i).resource_name` give the material name per surface.
- **Byte determinism:** fresh bakes differ by about 15 bytes when sub-resource ids are random and are byte-identical when `resource_scene_unique_id` is set per object from its position (§4). A re-save of a *loaded* copy is not byte-equal to the first save, so determinism is asserted on fresh bakes.

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Accepted): axes, the ±2 km bound, the Blender axis rule, the mirror owner (`src/pipeline/`), `art_src/`. ADR-0002 (Proposed): the `TrackCollisionData` schema this ADR bakes, and the boot and load checks. ADR-0004 (Proposed v2): `CourseData`, `CourseAuthoring` and `CourseBuilder`, which owns the whole derivation; this ADR only parses the `kk_*` empties into `CourseAuthoring` |
| **Enables** | ADR-0007 Blender asset pipeline (reuses the exporter conventions and the fixed export flags). ADR-0006 network snapshot (can put `TrackPackage.source_sha256` in the handshake). ADR-0009 anti-gravity (extends the schema) |
| **Blocks** | Story 024 (Blender track pipeline end to end). Story 025 (Castle Circuit on the new core) needs a working package |
| **Ordering Note** | This ADR cannot be Accepted before ADR-0002 and ADR-0004. The course fields in the `kk_*` table below are the authoring contract for ADR-0004's `CourseAuthoring` (§14 there), and ADR-0004 owns their meaning. If ADR-0004 changes a field, `kk_schema` is bumped. Story 023 builds the mesh track_check that this ADR's package checks plug into. |

## Context

### Problem Statement
Phase A replaces the frozen spline tracks with mesh tracks authored in Blender:
- collision with a surface per triangle and per-wall attributes;
- MK-style course data: checkpoints, routes, respawns, grid, item boxes;
- moving colliders.

Today nothing carries a Blender scene into the formats owned by ADR-0002 and ADR-0004. The systems index names this "unproven import path; a slow loop kills track iteration".

The spike answered whether the data survives Blender → glTF → Godot (it does). It also showed where it silently does not:
- `export_extras` is off by default;
- integers arrive as floats;
- a wrong vertex order makes walls invisible.

The pipeline has to turn those silent failures into loud ones before story 024 builds a real track.

### Constraints
- Blender writes **only glTF**. The Godot import step owns the conversion and refuses a file that fails the schema check, saying why (`architecture.md`, Tool layer).
- **A pipeline never owns a runtime format.** `TrackCollisionData` belongs to Track Collision (ADR-0002), `CourseData` to Course Data (ADR-0004), and the theme type to Track Art & Scenery.
- ADR-0001 §1-§2: Godot +Y up and −Z forward, metres, ±2 km. The importer never rescales or rotates a track. Pose empties point local +Y along travel.
- ADR-0001 §7: mirror is applied **at load**, never at import.
- ADR-0001 §9:
  - `.blend` files live in `art_src/` (with a `.gdignore`);
  - Godot's `.blend` import is off;
  - only `.glb` files live under `assets/`;
  - pipeline code lives in `src/pipeline/`;
  - new code never references `src/legacy/`.
- ADR-0002: no collision nodes, stable surface and wall-attribute ids from the core's `SurfaceSet` and `WallAttrSet` (`assets/data/core/`), and an unknown name fails the import.
- Headless: CI and the author's one-command build run Blender and Godot with no UI.

### Requirements
- One Blender scene yields collision, course data, the visual and the theme reference.
- Each check prints PASS / WARN / FAIL / NOT ASSESSED and names the object and its position in **Blender** coordinates.
- Every check runs on every import: the author sees every error at once, not one per round trip.
- The same `.glb` bakes the same package, byte for byte in its arrays (same-machine reproducibility, ADR-0001 §6).
- Export + import + check of a 150k-triangle collision track stays within the author's flow (target in Performance).
- A failed import never leaves a package that looks valid.

## Decision

### 1. Pipeline shape
```
art_src/tracks/<track_id>.blend                       (Blender 5.3; .gdignore; never imported by Godot)
  │ tools/blender/export_track.py                     (headless; Blender-only checks; stamps kk_layer;
  ▼                                                     bakes mover keys; fixed export flags)
assets/tracks/core/<track_id>/<track_id>.glb          (committed; the only Blender output)
  │ Godot scene import, import_script/path =
  │   res://src/pipeline/track_post_import.gd         (editor, or headless `--import`)
  ▼
TrackBaker.bake(root, source_path) ── parse kk_* → CourseAuthoring ── ADR-0004 CourseBuilder ── all checks ── FAIL → nothing written, lines printed
  │ PASS
  ▼
assets/tracks/core/<track_id>/<track_id>.track.res    (TrackPackage, binary; build product, gitignored)
  + the .glb's imported scene, stripped to Visual nodes and mover nodes (the visual scene)
  │ TrackLoader.load_track(id, mirrored)              (game, tests, track_check)
  ▼
LoadedTrack: TrackCollisionData (mirrored() if asked) · CourseData (mirrored() if asked) · visual · theme
```
- The new core's tracks live under **`assets/tracks/core/<id>/`**, approved as permanent. They never mix with the frozen game's `assets/tracks/<name>/` folders.
- **Theme and catalog.** Blender carries **no theme**. A `TrackDef` catalog entry (owned by Race Flow, `assets/data/core/tracks/`: id, name, cup, theme, music, default laps, hazard binding `mover id → HazardEffect`) references a `SceneryTheme` (Track Art & Scenery, `src/visuals/`; `TrackTheme` is a frozen class name). The package has no theme field.
- **Git LFS (devops follow-up, recommended):** `*.glb` and `art_src/**/*.blend` go to Git LFS. Not decided here.
- **Runtime `GLTFDocument` is not built now.** `TrackBaker.bake` takes a scene root `Node`, so a future user-track front end can call `GLTFDocument.generate_scene` and pass the result to the same baker (G7 shows the data is identical). Its own ADR settles its cost and safety (NV-12).
- **Mirror is not baked.** The package is unmirrored. `TrackLoader` calls `TrackCollisionData.mirrored()` (ADR-0002) and `CourseData.mirrored()` (ADR-0004) once at load and sets the visual root's `scale.x = −1` (ADR-0001 §7).

### 2. Blender authoring conventions

**Scene:** `scene.unit_settings.system = 'METRIC'`, `scale_length = 1.0`. One `.blend` file per track, holding one scene.

**Collections.** Every exported object sits in exactly one of these top-level collections:

| Collection | Holds | Rendered | Read by the baker as |
|---|---|---|---|
| `Ground` | Drivable and off-road meshes: road, grass, ramps, decks | No (see `kk_render_collision`) | Ground triangles + surface id per triangle |
| `Walls` | Wall meshes, one-sided, facing the route | No (see `kk_render_collision`) | Wall triangles grouped by wall attribute |
| `Visual` | Everything the player sees: road art, scenery, mover visuals | Yes | Nothing (the triangle count is reported) |
| `Course` | Empties: track, probe, checkpoints, respawns, grid, item boxes, route points, movers | Mover empties only, as parents of their visuals | `CourseData`, `MoverDef`s, probe, track metadata |

- **Scratch collections:** a collection whose name starts with `_` is skipped, and the exporter prints its object count.
- **Anything else fails:** an object in no known collection, or in two of them, fails the export.
- **Collision may be simplified.** Ground and Walls are separate from Visual on purpose: collision can be a low-poly version of the visible road. The mesh track_check bounds the visible gap (§7).
- **Blockout tracks** set `kk_render_collision = true` on the track empty, and Ground and Walls are then rendered as the visual.

**Materials (collision only):**
- **Ground** faces use `surf_<name>`; `<name>` is a `SurfaceType.kind` in `assets/data/core/` `SurfaceSet`.
- **Walls** faces use `wall_<name>`; `<name>` is an entry in `WallAttrSet` in the same folder.
- **Name pattern:** `^(surf|wall)_[a-z0-9_]+$`. A Blender duplicate suffix (`surf_road.001`) fails.
- **Collection mix-ups fail:** a `wall_` material in `Ground`, or a `surf_` material in `Walls`, fails.
- **Unknown names fail.** A `<name>` that is not registered fails the import (ADR-0002). New surfaces are added to the registry first, never invented in Blender.
- **The material name is the single source** of the surface. Material custom properties (G2) are not read.
- **Visual materials are free-form.** Their backface-culling setting controls `doubleSided` (G8).

**Transforms:**
- **`Ground` / `Walls` meshes** have **applied transforms** (identity: Ctrl+A → All Transforms), no parent and no animation. A negative-determinant object fails (NV-14); use a Mirror modifier instead.
- **`Visual` meshes** may keep object transforms, so instancing stays cheap.
- **Pose empties never have transforms applied:** the pose *is* the transform.
  - Their scale is 1 (|s − 1| ≤ 1e-4).
  - Their display type is **`ARROWS`** (G10); any other display type fails.
  - **Local +Y points along the direction of travel** (ADR-0001 §2). Each one lands as a Godot pose facing −Z (G4).
- **Modifiers** are applied at export (`export_apply=True`).

**`kk_*` custom properties.** These are object custom properties, read on the Godot side from `get_meta("extras")`.
- **Every numeric field is cast** with `int()` or `float()`. An `int` field whose float value is not integral (|v − round(v)| > 1e-6) fails.
- **Unknown fails:** an unknown `kk_type`, or an unknown `kk_` key on a known type, fails. A misspelt optional field is never silently ignored.
- The schema is **single-sourced in `src/pipeline/track_schema.json`**, which both `export_track.py` and `TrackBaker` read.

| `kk_type` | Count | Required fields | Optional | Notes |
|---|---|---|---|---|
| `track` | exactly 1 | `kk_schema: int` (= importer's `SCHEMA`, 1 at first), `kk_track_id: string` (`^[a-z0-9_]+$`, equals the folder name) | `kk_render_collision: bool` (false) | Track metadata. Its pose is ignored. **No `kk_theme`**: the theme comes from the `TrackDef` catalog (§1) |
| `probe` | exactly 1 | `kk_surface: string` (a known surface name) | — | Becomes ADR-0002's `probe_point` / `probe_surface_id`. Placed ≤ `probe_max_drop_m` above a road triangle |
| `checkpoint` | ≥ 3 | `kk_index: int` (unique, contiguous from 0; 0 = start line), `kk_group: int` (branches and shortcuts share a group), `kk_width: float` (> 0, m), `kk_height: float` (> 0, m) | `kk_next: string` (comma list of `kk_index` values; default index + 1, wrapping), `kk_key: bool` (must agree across a group), `kk_respawn: int` (a respawn `kk_index`; default: the nearest respawn behind the gate) | Gate pose with **scale 1**; the origin is authored **on the road**, +Y along travel. `CourseBuilder` lifts the quad centre by half the height (ADR-0004 §3). Meaning is ADR-0004's |
| `respawn` | ≥ 1 | `kk_index: int` (unique) | — | Pose the kart takes. Which gates use it is set by the gates' `kk_respawn` (ADR-0004 §9) |
| `grid` | exactly 12 (`grid_slots`) | `kk_slot: int` (0 … 11, each once) | — | **Exactly 12 explicit empties for MVP.** A generated pattern is future work. The spike's `grid_slot` is renamed `grid` |
| `item_box` | ≥ 0 | `kk_index: int` (unique) | — | Box pose. Odds and respawn time are Items data, not authored here |
| `route_point` | ≥ 3 for `main` | `kk_route_kind: string` (`main`, `branch`, `cpu`, `item`, `cut`), `kk_route: string` (the route id, `^[a-z0-9_]+$`), `kk_index: int` (contiguous from 0 per route) | **Route header** (on the route's first point, or on a `route_header` empty with the same `kk_route`): `kk_closed: bool` (default false; `main` must be closed), `kk_branch_type: string`, `kk_min_speed: float`, `kk_min_boost: float`, `kk_lanes: int`. **Per point (`cpu` routes):** `kk_hint_no_drift: bool`, `kk_hint_speed_cap: float`, `kk_hint_lane_hold: string` (`left` / `right`), `kk_hint_item_hold: bool` | A route is its points in index order. **One vocabulary**, in `track_schema.json` (no `enemy` / `branch_<x>` ids). Half width, surface runs, lanes and spans are **derived by `CourseBuilder`** from collision, not authored. `cpu` routes need no gates. Hints are optional overrides (ADR-0004 §6) |
| `route_header` | ≥ 0 | `kk_route: string` | The route header fields above | Optional carrier for header properties instead of the first point. A route with header fields on both fails |
| `area` | ≥ 0 | `kk_area: string` (`hazard_static`, `hazard_speed_gated`, `cannon_trigger`, `fall_boundary`), `kk_size_x`, `kk_size_y`, `kk_size_z: float` (> 0, full size in m, along the empty's Blender local axes) | Kind params: `kk_min_speed: float` (speed-gated), `kk_cannon_id: int` (cannon trigger), `kk_hazard_id: int` (static) | An **oriented box**: the empty's pose and size, converted like a mover box (§2, Movers). Boost pads and trick ramps are **not** areas: they are `surf_` materials of kinds `boost_pad` / `trick_ramp` (ADR-0002 v4) |
| `mover` | ≥ 0 | `kk_mover_id: int` (≥ 1, unique), `kk_shape: string` (`box`, `capsule`, `cylinder`). For `box`: `kk_size_x`, `kk_size_y`, `kk_size_z: float` (full size, m, along the empty's **Blender** local axes). For `capsule` / `cylinder`: `kk_radius`, `kk_height: float`, with the axis along the empty's Blender local +Z (Godot local +Y) | — | Root-level (no parent). Its keys are baked by the exporter (§2, Movers). `kk_keys` and `kk_period` are **written by the exporter only**; an author-set value fails |

**Course Data seam.** The baker parses these empties into ADR-0004's neutral `CourseAuthoring` (converting poses to Godot space) and hands it to `CourseBuilder`. **Nothing is derived in this ADR**: gate lift, defaults, key groups, respawn choice, route tables, spans and sectors are ADR-0004's.

**Movers (moving colliders):**
- **Authoring:** a mover is a `Course` empty with `kk_type = "mover"`, animated with ordinary object keyframes (an action on the empty).
  - Its visual is any `Visual` mesh parented to it.
  - Its gameplay effect (spin, stop, sink, push-off) is **not** authored in Blender. Track Hazards maps the `kk_mover_id` to a `HazardEffect` in its own data.
- **Baking the keys:** `export_track.py` samples the empty's `matrix_world` at **every frame** of its action's frame range at the scene fps (NV-9). It writes:
  - `kk_period = (frame_end − frame_start) / fps`;
  - `kk_keys`: a string of `t,px,py,pz,qx,qy,qz,qw;…` in Blender space.

  Sampling every frame keeps Blender's curves within one frame's linear segment. ADR-0002 evaluates movers as piecewise linear in position and slerp in rotation.
- **The exporter fails** when the first and last poses differ (loop closure) by more than `loop_pos_m` / `loop_rot_deg`, or when the empty has no animation.
- **glTF animation is not exported** (`export_animations=False`). Keys travel in the extras only, so the imported scene has no `AnimationPlayer` to fight `mover_pose`.
- **The baker converts the keys** to Godot space with the same basis change as glTF. Position `(x, y, z)` → `(x, z, −y)`; basis B → C·B·C⁻¹, with C the map `(x, y, z) → (x, z, −y)`.
- **Size conversion.** Blender full size `(sx, sy, sz)` becomes Godot half extents `(sx/2, sz/2, sy/2)` (the axis swap of the basis change). A **cylinder** keeps `radius` and `half_height = kk_height / 2`. A **capsule** converts as `half_height = (kk_height - 2 * kk_radius) / 2`, because ADR-0002's `half_height` is the half-length of the segment between the cap centres; `kk_height` is the total height including the caps, and a capsule with `kk_height < 2 * kk_radius` FAILs.
- **Scale is forbidden on movers.** The exporter FAILs if any sampled `matrix_world` of a mover has scale ≠ 1 (|s − 1| > 1e-4), at any frame. Size lives in the `kk_size_*` / `kk_radius` / `kk_height` properties only. I7 also covers mover empties.
- **It cross-checks:** the converted key at t = 0 must equal the imported mover node's transform within 1 mm / 0.1°. That catches a conversion bug at once.
- **It fills ADR-0002 v4's `MoverDef`** (a `Resource`): id, a shape enum, `half_extents` (box) or `radius` + `half_height` (capsule, cylinder), `period`, and packed `key_t`, `key_pos`, `key_rot`. ADR-0002 owns the storage; its moving-point velocity query is `mover_point_velocity`.

### 3. Exporter: `tools/blender/export_track.py`
```
"C:/Program Files/Blender Foundation/Blender 5.3/blender.exe" --background --factory-startup --python-exit-code 1 \
    art_src/tracks/<track_id>.blend --python tools/blender/export_track.py -- [--out <path.glb>] [--check] [--auto-gates <N>]
```
`--python-exit-code 1` is required: otherwise an uncaught exception exits 0 (NV-9). `tools/track_build.sh` also requires the `EXPORTED <path>` line, and fails without it.
- **Negative-scale check.** Call `bpy.context.view_layer.update()` before reading `matrix_world.determinant()` (in a fresh script the determinant read 1.0 without it), or test the sign of `matrix_basis` scale.
- It follows the `tools/blender/` conventions: a module docstring with the run line, `ROOT` taken from `__file__`, and an `EXPORTED <path>` line at the end.
- **Authoring cost for MVP.**
  - **Curves:** a Blender curve object in `Course` (with `kk_route_kind`, `kk_route` and the header properties) is expanded by the exporter into in-memory `route_point` empties at `curve_expand_spacing_m` (a value in `track_schema.json`, which the Python exporter reads; the baked sample spacing is ADR-0004's `CourseBuildSettings.sample_spacing_m`). The `.blend` is never changed (it never saves).
  - **Auto-gates:** an optional generator (`--auto-gates <N>`) adds a gate every N metres along `main`, producing `checkpoint` empties in memory. An authored gate within the same stretch overrides the generated one. Key groups are not generated: they are authored.
- **Do not reuse `common.export_glb`:** it exports with `export_extras=False` and strips custom properties on purpose, for story-006 models.
- **It never saves the `.blend`.** Every change (the `kk_layer` stamp, the baked mover keys, the selection) is made in memory.
- **Blender-only checks** are the ones Godot cannot see. Each prints `EXPORT_TRACK PASS|WARN|FAIL <check> <message>`, naming the object.
  - collection membership; scale_length;
  - `.NNN` material suffixes and the material pattern;
  - applied transforms on Ground and Walls; negative determinant;
  - `ARROWS` empties, empty scale (including `area` and mover empties; a mover with scale ≠ 1 at any sampled frame);
  - mover animation and loop closure;
  - object names ending in a Godot hint suffix (`-col`, `-colonly`, `-noimp`, …; NV-3);
  - unknown `kk_` keys (from `track_schema.json`);
  - the Blender version (WARN if not 5.3).
- **`kk_layer` stamp.** Before export it sets `kk_layer` = `ground` / `walls` / `visual` / `course` on every exported object, from its collection.
  - Godot then knows each node's role without depending on how collections map to glTF (NV-2).
  - A node without `kk_layer` tells the importer the file was not made by this script.
- **Export flags, all passed explicitly (B2):**
  ```
  export_format='GLB', export_yup=True, export_extras=True, export_apply=True,
  use_selection=True,            # the selection = objects in the four known collections
  export_animations=False, export_skins=False, export_morph=False,
  export_cameras=False, export_lights=False,
  export_materials='EXPORT', export_texcoords=True, export_normals=True,
  export_hierarchy_full_collections=False
  ```
- **Atomic write:** it writes `<out>.tmp.glb`, then `os.replace` onto `<out>`. A failed check writes nothing.
- **`--check`** runs the checks without exporting.
- **Exit status:** 1 on any FAIL (NV-9). The wrapper reads the lines anyway.

### 4. Godot import
- **The import preset** (per `.glb.import` `[params]`), written by `tools/track_import_preset.gd` before the first import (NV-11) and verified by track_check:
  ```
  import_script/path="res://src/pipeline/track_post_import.gd"
  nodes/use_name_suffixes=false
  nodes/use_node_type_suffixes=false
  meshes/force_disable_compression=true
  meshes/generate_lods=false
  meshes/create_shadow_meshes=false
  animation/import=false
  ```
  The spike ran with suffixes and compression on. Both are wrong for a track (NV-3, NV-4).
- **`project.godot`** pins `filesystem/import/blender/enabled=false` (NV-1). `art_src/.gdignore` is committed.
- **`TrackPostImport._post_import(scene)` is thin:**
  1. load the registries, the limits and the `CourseBuildSettings`; **delete any existing `*.track.res` before baking** (not only on a fail);
  2. `TrackBaker.bake(scene, get_source_file())`;
  3. print every check line as `TRACK_IMPORT <verdict> <check> <message>`;
  4. on a pass, save the package (NV-6) and **strip** the scene: remove Ground and Walls nodes (unless `kk_render_collision`) and every Course node except movers. Mover nodes keep only `kk_mover_id` as meta, and `extras` meta is removed from the rest;
  5. return the scene.

  **On a failure** it writes no package, **deletes any existing `*.track.res`** (a build product) and returns `null` or a stripped scene carrying the failure as meta. Returning `null` is a **silent failure** (NV-5): no error is printed, `--import` exits 0, and over an earlier good import the old imported scene stays and keeps loading. Success is therefore decided **only from the `TRACK_IMPORT RESULT` line**.
- **The post-import script has no `class_name`.** It is referenced by path in the preset, so its editor-only base class (`EditorScenePostImport`) is not registered in exported builds.
- **Forcing a reimport:** touching the `.glb` does not reimport. `tools/track_build.sh` deletes `.godot/imported/<name>-<hash>.md5` for the affected `.glb` files first, then runs `--import`.
- **CI must not grep a bare `ERROR`:** `--import` prints RID-leak `ERROR` lines after a post-import script. CI greps `TRACK_IMPORT RESULT FAIL` and the missing `RESULT` line only.
- **Every script the baker touches is `@tool`** (NV-7): `src/pipeline/*`, `CourseBuilder`, `CourseAuthoring`, `CourseData` and its parts, `CollisionQuery`, `TrackCollisionData`, and `src/data/surface_set.gd`, `surface_type.gd` and the wall-attribute set (marking those `@tool` is additive, ADR-0001 §9). `track_post_import.gd` loads them by `preload("res://…")` path, never by `class_name`. Story 024 proves this on a clean clone in CI (NV-15).
- **`TrackBaker` is pure.** It does no file I/O and keeps no state between calls, and the registries arrive through the constructor. That makes it unit-testable with scenes built in code.
- **It is deterministic:**
  - nodes are visited **sorted by name**, never in tree order;
  - triangles are taken in surface order, then in index order;
  - empties are sorted by `(kk_type, index)`;
  - wall shapes are ordered by wall-attribute id ascending;
  - **distinct, deterministic resource ids:** `resource_scene_unique_id` is set on the package and on every sub-resource, **unique within the file** and derived from each object's position in the package: `package`, `collision`, `course`, `course/route_3`, `mover_7`, and so on (as the probe did). One shared fixed string is wrong. Random ids make fresh bakes differ by about 15 bytes; derived ids make them byte-identical.
- **Triangles come from `surface_get_arrays(i)`** (`ARRAY_VERTEX` + `ARRAY_INDEX`, or sequential if there is no index), through the node's global transform, in index order (G5). Each one takes the surface id of `surface_get_material(i).resource_name` (G3). `Mesh.get_faces()` is not used: it flattens surfaces and loses the material.

### 5. Validation at import (every check runs; any FAIL or NOT ASSESSED refuses the file)

Thresholds live in `TrackImportLimits` (`assets/data/core/track_import_limits.tres`), shared with track_check. The ±2 km bound is ADR-0001's constant, not a tunable.

| ID | Check | FAIL when | WARN when |
|---|---|---|---|
| I1 | Origin | A node lacks `kk_layer` ("not exported by `tools/blender/export_track.py`"); a node's `kk_layer` disagrees with its contents (a mesh in `course`, an empty in `ground`) | — |
| I2 | Schema | `kk_schema` ≠ `SCHEMA` (the message says which side is newer); `kk_track_id` ≠ folder name | — |
| I3 | Fields | Any `kk_*` rule in §2: an unknown type or key, a missing required field, a non-integral int, a wrong type | — |
| I4 | Bounds | Any vertex or empty with \|x\|, \|y\| or \|z\| > 2000 m (ADR-0001 §1); a collision extent < `min_extent_m` (catches cm-unit exports). Never rescaled or rotated | — |
| I5 | Ids known | A `surf_` / `wall_` name not in `SurfaceSet` / `WallAttrSet`; a probe `kk_surface` that is unknown; a `kk_area` kind, `kk_route_kind` or `kk_hint_lane_hold` value outside its list | — |
| I6 | Collision transforms | A Ground or Walls node whose global transform is not identity (1e-5) | — |
| I7 | Pose empties | A basis that is not orthonormal or not scale 1, on any pose empty **including mover empties** (the baked keys' bases too) | — |
| I8 | Ground winding | Any ground triangle with normal.y ≤ 0 (rays from above miss it; ADR-0009 will add an anti-gravity exemption). Lists the count and the first 5 centres in Blender coordinates | Degenerate triangles (area < `degenerate_area_m2`). Jolt drops them and keeps `face_index` aligned (ADR-0002 Verified 1) |
| I9 | Wall normals face the route (runs **after** the `CourseAuthoring` parse, which supplies the route polylines) | A wall triangle whose **front** half-space holds no route sample (all routes, densified to ADR-0004's `sample_spacing_m`, \|Δy\| ≤ `wall_route_max_dy_m`) within `wall_route_max_dist_m`: "wall faces away from every route" (G9) | The nearest route sample is in its **back** half-space (a possibly flipped median face); \|normal.y\| > `wall_flat_normal_y` (ground rays do not see walls, ADR-0002) |
| I10 | Required empties | The counts in §2: track = 1, probe = 1, checkpoints ≥ 3 and contiguous, grid = 12 explicit slots each once, respawn ≥ 1, `main` route ≥ 3 points and contiguous; duplicate `kk_mover_id` | No `item_box` |
| I11 | Probe | A `CollisionQuery` built from the just-baked `TrackCollisionData` (the same code the game runs): a ray down from the probe within `probe_max_drop_m` misses, returns a different surface id, or has normal.y ≤ 0. This also checks the project's face-index setting in the editor | — |
| I12 | Triangle budget | Ground + wall triangles > `collision_tris_fail` (160,000: ADR-0002 measured flat cost up to 154k) | > `collision_tris_warn` (120,000). The Visual count is printed as an observation; its budget belongs to Track Art |
| I13 | Movers | A shape outside the three; a size ≤ 0; fewer than 2 keys; times not strictly increasing; period ≤ 0; the t = 0 key ≠ the node transform (§2) | — |
| I14 | No collision nodes | Any `CollisionShape3D`, `CollisionObject3D` or `NavigationRegion3D` in the imported scene (ADR-0002: no collision nodes; NV-3) | — |
| I15 | Course | `CourseBuilder.build` (ADR-0004 §14) returns any FAIL or NOT_ASSESSED line: the ADR-0004 §13 bake checks (sector rule, key coverage, respawn and grid invariants, areas, routes inside the road). **Runs at every import**; its lines are printed as `TRACK_IMPORT <verdict> I15.<id> …`. A FAIL refuses the file. Needs I11's `CollisionQuery`; NOT_ASSESSED when I5 or I11 failed | ADR-0004's WARN lines |

- **NOT ASSESSED:** a check whose input is missing prints `NOT_ASSESSED` with the reason, and it refuses the file like a FAIL. For example, I9 with no route points, or I11 when I5 failed.
- **It is ranked** below FAIL in the summary and above PASS.
- **The summary line** is `TRACK_IMPORT RESULT PASS|FAIL <n_fail> fail, <n_na> not assessed, <n_warn> warn`. It is always printed.

### 6. `TrackPackage`
- **What it holds** (binary `.res`):
  - `schema`, `track_id`;
  - `source_glb` (the `res://` path of the `.glb`, a **string**, so the package does not depend on its own source during import; NV-10);
  - `source_sha256` (of the `.glb` bytes, NV-13): **the track's identity** for ADR-0006;
  - `bake_key` (below);
  - `collision: TrackCollisionData` (ADR-0002, defined there);
  - `course: CourseData` (ADR-0004, defined there; filled by `CourseBuilder`);
  - `render_collision`;
  - `stats` (triangle counts per layer, for reports).
  - **Every stored field must be `@export` or `@export_storage`.** A plain `var` is not saved (it reloaded as 0 in the probe). The same holds for `TrackCollisionData`, `CourseData` and `CourseRoute`.
- **No theme field.** The theme comes from the `TrackDef` catalog (§1).
- **`bake_key`** is a SHA-256 over: the `.glb` bytes, `track_schema.json`, the registry instances (`SurfaceSet`, `WallAttrSet`), `TrackImportLimits`, the `CourseBuildSettings` instance, `CourseBuilder.BUILDER_VERSION`, `BAKER_VERSION`, `CourseData.FORMAT_VERSION` and `TrackCollisionData.FORMAT_VERSION` (ADR-0002). Changing any of them makes the package stale, not only a changed `.glb`. Rule: any change to `CourseBuilder` output bumps `BUILDER_VERSION`.
- **It is a build product.** `*.track.res` under `assets/tracks/core/` is gitignored and regenerated by `--import`, which a fresh clone and CI already run. The `.glb` is committed. **Fallback:** if the fresh-clone import fails (NV-15), commit the package with Git LFS (Alternative 7).
- **`tools/track_build.sh`** re-imports every affected `.glb` when a `bake_key` input changes (a registry, the schema, the limits), using the md5 deletion recipe of §4.
- **`TrackLoader.load_track(id, mirrored, out)`:**
  1. loads the package and checks `schema`;
  2. **in editor and tool runs only** (`OS.has_feature("editor")`, because exported builds do not ship the source `.glb`), recomputes `bake_key` from the current inputs and refuses a mismatch with "re-import `<path>`" (a changed `.glb` is one such mismatch);
  3. applies mirror (§1);
  4. hands `collision` to `CollisionQuery`, whose load check (ADR-0002) runs at every track load.

  A track that fails loads loudly (Data Flow 5).
- **`source_sha256` is the track's identity.** ADR-0006 may put it in the race config handshake, so two PCs never race different builds of a track.

### 7. How track_check validates the package
The mesh track_check (story 023; working name `tools/track_check_mesh.gd`, headless `SceneTree`, prints `PASS` / `FAIL` lines, exits 1 on a fail) loads the package **through `TrackLoader`**, the same path as the game. It runs every check on the unmirrored **and** the mirrored track.

- **Package checks (this ADR):**
  - **P1:** the package exists and is not stale (`bake_key`);
  - **P2:** the schema matches;
  - **P3:** the `.glb.import` preset matches §4, read as a `ConfigFile`;
  - **P4:** I4, I8, I9, I10, I11, I13 and I15 re-run on the loaded data, so an old or hand-edited package cannot pass;
  - **P5:** the ADR-0002 load check passes on the mirrored collision too.
- **Course checks (owned by ADR-0004 / story 023, listed so they are not lost):**
  - laps complete through the checkpoints in order;
  - every respawn pose sits on Ground collision with clearance;
  - routes stay inside the road (sampled);
  - movers never block the whole road width at any t over one period;
  - all 12 grid slots are on the road, clear of walls and of each other;
  - the visual-versus-collision height gap along the routes is ≤ `visual_gap_max_m`, so simplified collision never visibly floats or sinks the karts.
- **It samples, never simulates 120k ticks** (`architecture.md` Performance Budgets, Tools).
- `tools/regression.sh` gains a `track_check_mesh` check once story 024 lands.

### Architecture Diagram
```
 Blender 5.3 (art_src/, .gdignore)
   Ground (surf_*) · Walls (wall_*) · Visual · Course (kk_* ARROWS empties, movers keyed)
        │ export_track.py: Blender-only checks · kk_layer stamp · mover keys → kk_keys · fixed flags
        ▼
 assets/tracks/core/<id>/<id>.glb ──(Godot import, preset §4)──▶ TrackPostImport (@tool, thin)
                                                                   │
           SurfaceSet / WallAttrSet / TrackImportLimits ──────────▶ TrackBaker.bake(root)  (pure)
           (assets/data/core)            track_schema.json ──────▶   I1…I15 → TrackBakeResult
                                                                   │ PASS            │ FAIL / NOT ASSESSED
                                                                   ▼                 ▼
                         <id>.track.res (TrackPackage)  +  stripped visual scene   lines only, nothing written
                           collision: TrackCollisionData (ADR-0002)
                           course:    CourseData         (ADR-0004)
                           bake_key · source_sha256
                                   │
              TrackLoader.load_track(id, mirrored) ── stale/schema check ── mirrored() ×2 ── scale.x = −1
                     │                         │
        game composition root           mesh track_check (P1…P5 + course checks, both mirror states)
```

### Key Interfaces

Each `class_name` lives in its own file under `src/pipeline/`. None reuses a frozen name: the legacy `Track*` names are `TrackData`, `TrackMesh`, `TrackModel`, `TrackBranch`, `TrackHazard`, `TrackLibrary`, `TrackMover`, `TrackPad` and `TrackRamp`.

```gdscript
@tool
extends EditorScenePostImport                     # src/pipeline/track_post_import.gd: NO class_name; referenced by path
func _post_import(scene: Node) -> Object          # thin: bake, print, save on pass, strip; on fail delete the package, null or meta scene (NV-5)

@tool
class_name TrackBaker extends RefCounted
func _init(surfaces: SurfaceSet, walls: WallAttrSet, limits: TrackImportLimits, schema: Dictionary) -> void
func bake(root: Node, source_path: String) -> TrackBakeResult   # pure; same input → same output

@tool
class_name TrackBakeResult extends RefCounted
var package: TrackPackage                         # null unless ok()
var lines: Array[TrackCheckLine]                  # every check, fixed order
func ok() -> bool                                 # no FAIL and no NOT_ASSESSED

@tool
class_name TrackCheckLine extends RefCounted
enum Verdict { PASS, WARN, NOT_ASSESSED, FAIL }
var check_id: StringName; var verdict: Verdict; var message: String
var blender_positions: PackedVector3Array         # up to 5, in Blender axes, for the author

@tool
class_name TrackPackage extends Resource
@export var schema: int
@export var track_id: StringName
@export var source_glb: String
@export var source_sha256: String
@export var collision: TrackCollisionData         # ADR-0002
@export var course: CourseData                    # ADR-0004
@export var bake_key: String                      # §6; every stored field is @export / @export_storage
@export var render_collision: bool
@export var stats: Dictionary

@tool
class_name TrackImportLimits extends Resource     # thresholds of §5 and §7 (instance in assets/data/core/)

class_name TrackLoader extends RefCounted
func load_track(track_id: StringName, mirrored: bool, out: LoadedTrack) -> Error

class_name LoadedTrack extends RefCounted          # collision, course, visual: PackedScene, theme
```

```
tools/blender/export_track.py   blender … <id>.blend --python tools/blender/export_track.py -- [--out p] [--check]
tools/track_import_preset.gd    godot --headless -s res://tools/track_import_preset.gd -- --track=<id>
tools/track_build.sh <id>       export (needs EXPORTED line) → preset → delete .godot/imported/<name>-<hash>.md5 → godot --headless --import
                                → track_check; decides from the TRACK_IMPORT RESULT line, never a bare ERROR grep; exit 1 on fail
```

### Implementation Guidelines
- Blender **must** export only through `tools/blender/export_track.py`. The export flags **must** be passed explicitly, and `export_extras` **must** be True.
- The exporter **must never** save the `.blend`. It **must** write the `.glb` atomically (temporary file, then `os.replace`) and **must** write nothing on a FAIL.
- Every exported object **must** sit in exactly one of `Ground`, `Walls`, `Visual`, `Course`. Collections starting with `_` **must** be skipped and counted in the output.
- Ground faces **must** use `surf_<name>` and wall faces `wall_<name>`, with `<name>` registered in the core `SurfaceSet` / `WallAttrSet`. An unknown name **must** fail the import. Surface ids **must never** come from material custom properties.
- Pose empties **must** be `ARROWS`, scale 1, local +Y along travel, and **must never** have transforms applied. Ground and Walls meshes **must** have applied transforms, no parent, no animation and a positive determinant.
- Numeric `kk_*` values **must** be cast with `int()` / `float()`, and a non-integral int **must** fail. Unknown `kk_` keys and types **must** fail. The schema **must** be read from `src/pipeline/track_schema.json` by both sides.
- Mover keys **must** be baked by the exporter at every frame, in extras. glTF animation **must not** be exported for tracks. Movers **must** be evaluated only through ADR-0002's `mover_pose` / `mover_point_velocity`, and presentation drives the mover nodes from them.
- `TrackBaker` **must** be pure (no file I/O) and deterministic: sorted by name, never by tree order. Triangles **must** come from per-surface arrays, never `Mesh.get_faces()`.
- Every import check **must** run on every import. A check that cannot run **must** print `NOT_ASSESSED` and refuse the file. The `RESULT` line **must** always print.
- A failed import **must not** write a package. `TrackLoader` **must** refuse a stale (hash) or wrong-schema package in editor and tool runs.
- The import **must never** rescale, rotate or mirror a track. Mirror **must** be applied only by `TrackLoader`, at load, through each owner's `mirrored()`.
- The import preset **must** keep name suffixes, mesh compression, LODs, shadow meshes and animation import off. The imported scene **must** contain no collision or navigation nodes.
- `src/pipeline/` **must not** reference `src/legacy/`, and **must not** define `TrackCollisionData` or `CourseData` fields. Changes to those go through ADR-0002 / ADR-0004.

## Alternatives Considered

### Alternative 1: Runtime `GLTFDocument` as the main path
- **Description**: Ship the `.glb` files; parse and bake when a race loads.
- **Pros**: One code path for shipped and user tracks. No import step.
- **Cons**: Errors surface at race load on every PC, not at authoring time. The baking cost lands on every load. There is no editor feedback.
- **Rejection Reason**: Validation must happen before a race exists (Data Flow 6). The data is identical (G7), so the baker takes a `Node` and a runtime front end can reuse it later for user tracks.

### Alternative 2: Godot's built-in `.blend` import
- **Description**: Godot calls Blender to convert `.blend` files on import.
- **Pros**: No export step.
- **Cons**: Every machine and CI needs the same Blender install. The export flags are hidden behind the importer. It leaves no committed `.glb`.
- **Rejection Reason**: ADR-0001 §9 turns it off and keeps `.blend` files out of the project.

### Alternative 3: Godot name hints (`-col`, `-colonly`) for collision
- **Pros**: Built in.
- **Cons**: It creates collision nodes and carries no per-triangle surface id.
- **Rejection Reason**: ADR-0002 forbids collision nodes. Collision is baked as data.

### Alternative 4: Bake `TrackCollisionData` in Blender (Python writes the arrays)
- **Pros**: Fewer import-side unknowns (NV-4, NV-6).
- **Cons**: A second axis conversion, a second file format, and Blender owning a runtime format. Godot would not see the triangles the game uses.
- **Rejection Reason**: It breaks "Blender writes only glTF" and "a pipeline never owns a runtime format". It stays the fallback named for NV-4, through a `GLTFDocumentExtension` rather than Blender.

### Alternative 5: Collection membership through glTF hierarchy or name prefixes
- **Description**: Use `export_hierarchy_full_collections=True`, or prefixes such as `G_road`.
- **Pros**: No stamping.
- **Cons**: The hierarchy option is unexercised (NV-2). Prefixes are fragile and invisible in the outliner's structure.
- **Rejection Reason**: The `kk_layer` stamp is explicit, survives through the verified extras path (G1), and doubles as the "exported by our script" check (I1).

### Alternative 6: Mover keys through glTF animation
- **Description**: Export actions and convert the imported `AnimationPlayer` tracks to `MoverDef` keys.
- **Pros**: The standard path; animators preview in Godot.
- **Cons**: Animation import was not exercised by the spike. `export_optimize_animation_size` is on by default and drops keys. It needs a second conversion, and it leaves an `AnimationPlayer` that competes with `mover_pose`.
- **Rejection Reason**: Keys sampled in Blender and carried as extras are exact and use only verified mechanisms. ADR-0007 exercises glTF animation for rigged assets; this can be revisited then.

### Alternative 7: Commit the baked `.track.res`
- **Pros**: A clone runs without an import. Reviewers see the package change.
- **Cons**: About 5.5 MB of binary per re-export of a 150k-triangle track (ADR-0002) bloats git. A derived file in git goes stale.
- **Rejection Reason**: `--import` already runs on clone and in CI, and the hash check makes staleness loud. The owner may reverse this; nothing else in the design changes.

### Alternative 8: Surface id from a material custom property (`kk_surface`)
- **Pros**: It arrives intact (G2).
- **Cons**: Two sources of truth (name and property) that can disagree.
- **Rejection Reason**: The material name is visible in every Blender view and is already verified (G3).

## Consequences

### Positive
- Every silent failure the spike found becomes a named FAIL with Blender coordinates: missing extras, ints as floats, outward walls, a wrong empty axis.
- One command (`tools/track_build.sh <id>`) runs export, import and check headless. The editor reimports on focus for the interactive loop.
- The baker is pure and takes a `Node`, so it is unit-testable and reusable for user tracks.
- Collision can be simplified independently of the visual, and track_check bounds the visible gap.
- `source_sha256` gives a track identity for the network handshake.

### Negative
- Authors still place gates, key groups, respawns and the grid by hand. Curve objects are expanded to route points and `--auto-gates` generates gates (§3), so route points are not hand-placed.
- The schema is strict: a new field needs a schema bump and an edit to `track_schema.json`.
- Applied transforms on collision meshes rule out instanced collision pieces. Instancing stays available for Visual.
- The package is a build product: a machine that has not run `--import` has no track. The loader says so loudly.
- Still unverified: NV-1 (the `.blend` import switch), NV-10, NV-15 (fresh-clone first import) and NV-16 (`CollisionQuery` inside `_post_import`). Story 024 may have to take a named fallback.

## Risks
- **Import failure is not reported as a failure (NV-5).** Mitigation: `track_build.sh` and CI decide from the `TRACK_IMPORT RESULT` line and the package hash, never from the `--import` exit code alone.
- **Vertex precision is lost by import compression (NV-4).** Mitigation: the preset turns compression off, and a fixture with vertices at 1,900 m must round-trip within 1 mm (Validation). Otherwise the `GLTFDocumentExtension` fallback is taken.
- **The wall-normal check misjudges median walls (I9).** Mitigation: FAIL only when a face looks at no route at all (the spike's case); a back-side nearest route is a WARN; positions are printed in Blender coordinates.
- **Schema drift against ADR-0004.** Mitigation: the baker only parses into `CourseAuthoring`, ADR-0004 owns every derived field, and `kk_schema` makes a stale `.blend` fail by name. `bake_key` makes a changed `FORMAT_VERSION` or registry stale.
- **A silent import failure (NV-5).** Mitigation: success only from the `RESULT` line; a failed import deletes the package.
- **Fresh-clone first import (NV-15).** Mitigation: CI proof in story 024; two-pass import, then LFS for the package.
- **A Blender upgrade changes exporter defaults.** Mitigation: every flag is explicit, the exporter warns when the version is not 5.3, and `probe_exporter.py` is re-run on each Blender upgrade (as the spike scripts are on each engine re-pin, ADR-0002).
- **A reimport loop from the package save (NV-6).** The probe saw none (NV-6 verified); story 024 re-checks it on the real pipeline.
- **`CollisionQuery` cannot run inside `_post_import` (NV-16).** Mitigation: the root-meta fallback in NV-16.
- **A beta engine changes the scene importer.** Mitigation: the fixture integration tests below run on every re-pin.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| systems-index.md: Blender Track Pipeline (row 7, Core, MVP) | Export collision and course data from one Blender scene; depends on Track Collision and Course Data | The four-collection scene, the exporter, the import bake into `TrackPackage`; the formats stay with their owners |
| systems-index.md: risk table, Blender Track Pipeline | "Unproven import path …; a slow loop kills track iteration"; one round trip before any real track | Built on the spike's round trip (G1-G10); one-command build; all checks per run; performance target below |
| systems-index.md: Track Collision & Surface Attributes (row 2) | Per-triangle attributes from Blender; walls; moving colliders | `surf_` / `wall_` materials to stable ids; wall winding check; movers baked to `MoverDef` keys |
| systems-index.md: Course Data (row 3) | Checkpoints, routes, respawns sit on the collision surface | `kk_*` course empties parsed into `CourseAuthoring`, derived by ADR-0004 `CourseBuilder` (I15); probe and track_check course checks |
| systems-index.md: Track Hazards (row 14) | Dynamic colliders | Mover empties with baked keys; effect keyed by `kk_mover_id` in hazard data |
| systems-index.md: Track Art & Scenery (row 24) | Depends on the Blender Track Pipeline | `Visual` collection, free materials, theme reference; collision separate from art |
| systems-index.md: Grand Prix & Speed Classes (row 31, mirror) | Mirror mode | Unmirrored package; `TrackLoader` mirrors at load (ADR-0001 §7); track_check covers both states |
| architecture.md: Tool layer, Data Flow 6 | Blender writes only glTF; the import refuses a failing file, saying why; `EditorScenePostImport` also headless | §3-§5 |

No system GDD exists yet. This table cites the systems index and the architecture.

## Performance Implications
- **CPU per tick:** none. All of the pipeline's work happens at authoring time or at load.
- **Authoring loop (target, measured in story 024):** export + import + package checks ≤ 20 s for 150k collision and 300k visual triangles on the owner's PC. The mesh track_check runs separately, sampled.
- **Memory:** the package arrays are about 5.5 MB at 154k ground triangles (ADR-0002). The visual scene follows Track Art's budget.
- **Load time:**
  - `.res` load, plus ADR-0002's shape build (27-90 ms), plus two `mirrored()` copies when mirror is on;
  - SHA-256 of the `.glb` in editor and tool runs only.
- **Network:** none directly. `source_sha256` is available to ADR-0006.

## Migration Plan
Nothing existing is migrated. The frozen game keeps its generator tracks (`tools/gen_*.py`, `assets/tracks/<name>/`). Story 024:
1. pins the preset and `project.godot` keys, and closes the open NVs (NV-1, NV-10, NV-15, NV-16; re-runs the verified ones on the real pipeline). It proves a fresh-clone first import in CI;
2. adds `art_src/.gdignore`, the gitignore line for `*.track.res`, and `assets/data/core/` instances of `SurfaceSet` (with `road`), `WallAttrSet` and `TrackImportLimits`;
3. writes `export_track.py`, `track_schema.json`, the `src/pipeline/` classes and `tools/track_build.sh`;
4. authors one test track in Blender end to end.

**Legacy tracks.** Castle Circuit and Dungeon Depths are bootstrapped through ADR-0004 §15: one `tools/legacy_track_export.gd` extractor writes neutral JSON outside `assets/`, and `tools/blender/legacy_to_blend.py` builds the first `.blend` files from it. They then ship only through this pipeline. This needs the ADR-0001 §9 amendment, **pending owner approval**.

**Devops follow-up (recommended, not decided here):** Git LFS for `*.glb` and `art_src/**/*.blend`.

## Validation Criteria
- **Unit tests** (`tests/unit/pipeline/`, gdUnit4), on scenes built in code with meta `extras` and `ArrayMesh` surfaces:
  - each of I1-I15 is **watched failing** on a broken fixture, then passing on a fixed one (a flipped wall; an unknown material; a missing grid slot; a 2,001 m vertex; `kk_index = 1.5`; a node without `kk_layer`; a duplicate mover id; a probe over grass);
  - a missing input yields `NOT_ASSESSED`, not PASS;
  - baking twice gives identical arrays;
  - a shuffled node order gives identical arrays.
- **Integration tests** (`tests/integration/pipeline/`): committed fixture `.glb` files built by a fixture Blender script, imported headless with `--import`. They cover:
  - an asymmetric track (the G4 positions reproduce);
  - a vertex at 1,900 m that round-trips within 1 mm (NV-4);
  - a mover whose t = 0 key equals its node and whose `mover_pose` at t = period/2 matches Blender's sampled pose within 1 mm;
  - a failing fixture that writes no package and prints `TRACK_IMPORT RESULT FAIL`;
  - a stale package (`.glb` changed) that `TrackLoader` refuses.
- **Story 024 evidence:** the NV table closed, with outputs retained. The authoring-loop time is measured against the target. A screenshot of the test track in game is retained in `production/qa/evidence/`.
- **Grep:** no `get_faces()` in `src/pipeline/`; no `src/legacy/` reference in `src/pipeline/`; no `export_scene.gltf` call outside `tools/blender/`.

## Related
- `prototypes/collision-spike/REPORT.md` Q4 and Recommendations; `out/q4_post_import.txt`, `out/q4_runtime.txt` (evidence).
- ADR-0001 (axes, Blender rule, mirror, layout; depends on). ADR-0002 (`TrackCollisionData`, `MoverDef`, registries, load check; depends on). ADR-0004 (`CourseData`, `CourseAuthoring`, `CourseBuilder`; depends on). ADR-0006 (track identity in the handshake). ADR-0007 (asset pipeline; reuses the exporter conventions). ADR-0009 (anti-gravity; extends I8 and the schema).
- `docs/architecture/architecture.md`: Tool layer, Data Flow 6, Module Ownership (Blender Track Pipeline). `design/gdd/systems-index.md` rows 2, 3, 7, 14, 24, 31 and the risk table.
- `tools/blender/common.py` (conventions; its `export_glb` is deliberately not reused).
