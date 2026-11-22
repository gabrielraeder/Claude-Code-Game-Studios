# Story 068: QL-TEST-COVERAGE (2026-11-22): GAPS

The core logic is tested and passes: 115/115 new tests, 426/426 overall, regression 10/10. The release-DLL order run is valid with caveats: it used the bench template_release build, not the shipped one; the buffers suite did not run on it; and the retained run is recorded as FAILED because `before()` refused while `bench.lock` existed. Heap-flat is real: the measurement sees a 240 B copy.

## Missing items to apply next session
1. **Criterion 6, double buffering.** The held-array tests pass even with a single buffer, because packed arrays are copy-on-write.
   - Add a test that tells buffer A from buffer B, through a parity debug accessor or a native copy counter.
   - Add `event_payload()` to the held-array tests.
2. **Criterion 11, greps.**
   - `write_snapshots` (and the other per-tick helpers) sit outside the PER_TICK region. Same finding as engine A4 and LP.
   - The rule does not see unordered-container iteration declared in headers.
   - Plant `<random>` and `random_device` separately.
3. **Meta-test.** It checks a hand-copied `covered` list. Build `covered` and `test_parameters` from one const, and assert the list is non-empty.
4. **Signatures.** Test the §3 signatures via `ClassDB.class_get_method_list`: argument names, types and return types.
5. **"State unchanged".** Compare `snapshots()` and `progress()` contents before and after a refused call. Same finding as LP 8.
6. **`place`/`hold`.** Test refusal at every in-tick position, and test that a held slot is not FROZEN (`SNAP_STATE`).
7. **No allocation on read.** Test that reading allocates nothing during a tick, and run the timer `> 0` check on the release DLL.
8. **Inputs not kept.** Add a hold-a-copy-and-compare test for `apply_events`, `step_drive`, `set_remote` and `place`.
9. **Heap.** Assert `first_cost >= held.size()*4` (a lower bound, not only an upper bound).
10. **Event payload fields.** Pin the per-kind field meaning (knock, pickup, item hit), not only the size.

## Recorded
- ADR-0003 amendment: approved by the owner on 2026-11-22, about 20:50 (asked in the session before the WIP commit 1ec4cd8).
- Story file: criteria are unticked and Test Evidence is pending, so the story is not closed. It closes after the fixes, the own-calls question and the commit.
