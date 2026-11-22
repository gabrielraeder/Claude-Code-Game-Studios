# Story 007: Collision benchmark (<= 0.3 ms p95, 12 karts)

> **Epic**: Core Rebuild (Phase A)
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Integration
> **Estimate**: S
> **Manifest Version**: N/A (no control manifest yet)
> **Last Updated**: not started (set by /dev-story)

## Context

**GDD**: `design/gdd/track-collision-and-surfaces.md` (§8 Acceptance Criteria)
**Requirement**: Track Collision AC-20; ADR-0002 Validation Criteria (benchmark); `architecture.md` Performance Budgets (track collision queries 0.3 ms p95)
**Roadmap step**: `architecture.md` Phase A Sequencing step 2-3 (spike follow-through; roadmap item 022 implements `CollisionQuery`, ADR-0002 Migration Plan). Epic story numbers are not roadmap item numbers.

**ADR Governing Implementation**: ADR-0002: Collision Backend and Surface Attributes (Proposed)
**ADR Decision Summary**: Jolt, used only through `PhysicsServer3D`: a RefCounted `CollisionQuery` owns a private space and server-created shapes and bodies, freed in a fixed order; ground is one concave shape whose surface id comes from the triangle `face_index`; walls are one body with one shape per wall attribute on their own layer; queries use the 4.8 non-allocating `_into` methods; moving colliders are evaluated analytically from keyframed pose curves. Budget: collision <= 0.3 ms p95 per tick for 12 karts (spike: 0.06 ms median).

**ADR Version**: ADR-0002 2026-11-22

**Engine**: Godot 4.8-beta3 | **Risk**: HIGH
**Engine Notes**: Jolt 5.6.0 in 4.8. Unit tests are valid only once the main project pins Jolt. `face_index` needs the project setting the load check tests for. Use the 4.8 `_into` query methods (non-allocating); no Dictionary query forms in per-tick code. Probe evidence: `prototypes/collision-spike/out/probe_adr2.txt`.

---

## Acceptance Criteria

*Each criterion cites its source (GDD AC id, ADR Validation Criteria, or `architecture.md`).*

- [ ] **Budget.** In a running tree, from `_physics_process`, 12 karts' worst-case query set per tick (3 wall sweeps, 4 ground rays and the rest check each, ADR-0002 Performance Implications) on a mesh of at least 48k triangles costs <= 0.3 ms p95 on the owner's PC; release export when 4.8 export templates exist, the debug editor build accepted as an upper bound until then (Track Collision AC-20; `architecture.md` Performance Budgets).
- [ ] **Flat per section.** The p95 is reported per track section (at least 4 sections including any branch) and no section exceeds the budget (`architecture.md` rule: no query scans a whole route or track).
- [ ] **No allocation.** `Performance.OBJECT_COUNT` and the server RID count are unchanged across 600 benchmark ticks.
- [ ] **Record.** `production/qa/evidence/core-rebuild-story-007/collision-bench.md` records machine, build, median and p95, and the command; a re-run on the generator-baked Castle mesh is added when story 008 lands.

---

## Implementation Notes

- Mesh: the spike's generator-baked mesh under `prototypes/collision-spike/` loaded by the tool, or a code-built fixture of comparable size; do not wait on story 008.
- Stage timing in the style of `tools/profile_tick.gd` (`Time.get_ticks_usec()` around the query block).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 012: kart body + drive budget.
- Story 024: contact budget.

---

## Files

*Planned; `/dev-story` replaces this list with the files it changed.*

- `tools/bench_collision.gd` (new)
- `production/qa/evidence/core-rebuild-story-007/` (report)

---

## QA Test Cases

*N/A — QL-STORY-READY not run in this autonomous drafting pass; implement against the Acceptance Criteria above.*

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: the integration run named in the criteria; run outputs and reports retained in `production/qa/evidence/core-rebuild-story-007/`
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: `production/epics/core-rebuild/story-006-collision-load-checks-and-mirror.md`
- Unlocks: `production/epics/core-rebuild/story-012-first-slice-budget.md`
