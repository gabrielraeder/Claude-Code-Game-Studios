# Story 068: LP-CODE-REVIEW (2026-11-22): CONCERNS, nothing REJECTs

The reviewer read `race_sim.{h,cpp}`, `race_layout.h`, the stage and buffer tests, `refuses()` and the `core_greps` race rule.

It did not read the ADR-0003 amendment, `race_layout.gd`, the layout test or the generic per-tick greps, so the "no allocation in stage code" and "layouts pinned" criteria are not assessed from source.

## Findings to apply next session
1. **Progress state.** The state of record lives in float32 output buffers that are copied forward each tick (`race_sim.cpp:367-370, 668-680`).
   - Fix: move progress into native `SlotState`, stored as doubles, and project it into `prog_buf` in `end_tick`.
   - Settle this before story 051. The `PROG_*` layout can stay.
2. **`place` and the published snapshot.** `place` does not touch the published snapshot, so `teleported` and the new pose only appear after the next tick, while ADR-0007 §3 says `place` marks the snapshot (`race_sim.cpp:572-586, 319-345`).
   - Fix: write the row into the published buffer in `place`, or document "read after the first `end_tick`".
   - Add a test for whichever is chosen.
3. **Buffer choice vs the docs.** Buffers are chosen by "not published", not by tick parity. That is accepted as an own call.
   - Fix: amend the ADR-0007 and `native-code.md` text to "alternates at each `end_tick()`", and say consumers must not infer the buffer from the tick.
4. **Finite check in `step_drive`.** It does not check driver rows for finite values (`race_sim.cpp:400-425`).
   - Fix: add `all_finite` and a negative test.
5. **Test seams.** `debug_*` seams mutate production state and are bound in the release DLL.
   - Fix: add a `core_greps` rule that `debug_` appears only under `tests/` and `native/`.
   - Remove the counters and seams when their owning story fills the hook.
6. **Heap test coverage.** The heap test never emits events, overflows, or calls `place`/`hold`, and the 2048 B tolerance is loose (`race_sim_buffers_test.gd:238-285`).
   - Fix: exercise those paths and tighten the tolerance.
7. **`refuses()` calls twice.** It calls the callable twice (`race_suite_base.gd:21-32`).
   - Fix: capture once.
8. **Thin "state unchanged" check.** It only compares a few fields (`race_sim_stages_test.gd:91-101`).
   - Fix: also compare `snapshots()`, `progress()` and `event_count()`.
9. **Refused stage leaves the tick part-way.** Accepted.
   - Fix: say in the amendment that the caller must finish or retry the stage. Consider `abandon_tick()` for story 050's restart.

## Contract notes for stories 009+ and 043-048
- Event rows carry no tick or sequence field. The ADR-0006 codec must supply ordering and dedup; say so in the ADR-0003 amendment.
- `event_headers()` and `event_payload()` are full-capacity arrays. Consumers iterate only the first `event_count()` rows.
- Roles are fixed at `create()`: a bot cannot take over a disconnected remote slot without rebuilding. Confirm this is intended before story 050.
- `SNAP_FLAG_BUMPED` and `SNAP_KNOCK` are not written yet. Story 022 fills them.
