# Story 068: engine check (godot-specialist, 2026-11-22): 1 defect, 8 advisories

## Defect, fix first
- **D1. `end_tick()` clears the event buffer a consumer may still hold** (`race_sim.cpp:511-518`).
  - **Problem:** `next_work = published ^ 1` is the buffer tick N-1 published. A consumer that refreshes every tick still holds it, so the `ptrw()` memset detaches both event arrays, a full copy every tick after a tick with events. That copy is an allocation inside the PER_TICK region, and it breaks ADR-0007 §3's promise.
  - **Why tests missed it:** the heap test emits no events.
  - **Fix:**
    - In `begin_tick`, set `work = published ^ 1` (tick N-2's buffer) and memset only its used rows and payload, then zero the counts.
    - `end_tick` only swaps and moves the overflow flag.
    - Add a heap run that emits at least one event per tick with a consumer that refreshes every tick. Watch it fail on the current code first.
    - Reword the criterion and the ADR-0007 §3 stage 8 text to "cleared before the tick that writes it", or record the deviation.
  - `test_end_tick_clears_the_working_event_buffer` still passes under the fix.

## Advisories
- **A1.** The buffer index alternates per completed tick, not per `tick & 1`.
  - Fix: either derive it from `current_tick & 1` and refuse a `begin_tick` whose parity does not alternate, or change the ADR-0007 and `native-code.md` wording to "alternates per tick". This is the same point as LP finding 3.
- **A2.** `begin_tick` accepts a repeated or decreasing tick.
  - Fix: refuse `p_tick <= current_tick` before any state change.
- **A3.** `race_layout.h` static_asserts cover only part of the layout.
  - Add asserts for:
    - `EVENT_PAYLOAD_MAX >= EVENT_PAYLOAD_KNOCK/PICKUP/ITEM_HIT`;
    - `MAX_SLOTS <= 62`;
    - `SNAP_TICK + 1 == SNAP_STRIDE`, `SNAP_VEL == SNAP_BASIS + 9`, `PLACE_STRIDE == 3 + 9`;
    - flags below 2^24.
  - Also bound-check `p_count` in `emit_event`.
- **A4.** `write_snapshots`, `now_usec`, `all_finite` and `basis_from` sit outside the PER_TICK grep region.
  - Fix: move them inside a marked region, because stories 010, 011 and 022 will fill `write_snapshots`.
- **A5.** The stage-8 timer is recorded before the end-of-tick work, so `stage_usec()[7]` under-reports.
  - Fix: record it just before the copy, and document that the copy itself is excluded.
- **A6.** `debug_emit_event` and `debug_write_progress` are bound in the release DLL. This is the same point as LP finding 5.
  - Fix: bind them only under `DEBUG_ENABLED`, or record the choice as an own call.
- **A7.** Document in `apply_events` that consumers must slice to `event_count()` rows. A full-capacity pass-back is already refused loudly, because a zero kind is unknown.
- **A8.** A refused stage leaves the tick open. Story 050 should know; consider `abandon_tick()`.

## Not assessed by this check
- The factory, stages and suite-base test files.
- Rule bodies in `core_greps.sh` and `native_negative_checks.sh`.
- The ADR-0003 amendment text (owner-approved 2026-11-22).
- The evidence folder.
- `hash_files.txt` coverage of the new files.
- Whether StringName setup keys match String keys.
