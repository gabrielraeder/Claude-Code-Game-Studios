# Castle Circuit crossover: the owner's decision (2026-11-21)

The owner picked the following from the level designer's proposal (three options: Barbican Spiral, Keep Bridge, Rampart Stair).

## Decisions

- **Crossover: Option A, the Barbican Spiral.** It replaces `village_in` (the 90° right after the gate arch, s ≈ 339-367, control points ~68-73) with:
  - a 280° LEFT curl, radius 16 (R15 allowed), around a round barbican tower outside the gate;
  - then a ~35 m straight ("gate_top") that crosses OVER the gate arch.
  - Everything from the village S-bend onward moves as one rigid block, about (-8, -29) m. The closure solver shortens `free_b` (49 → ~20 m) and lengthens `free_a` (48.5 → ~50 m).
  - The generator's turning assert changes from 360 to 0, with a comment saying why: a closed road with exactly one self-crossing has a net turn of 0° or 720°, never 360°.
- **Heights:**
  - Lower road: the gate arch, 0.0 m, flat and unbanked, inside the drawbridge-junction FLAT window (s 301-331). The crossing is at about s 326.
  - Upper road: 7.0 m (minimum 6.6), with the deck underside at 6.4 m.
  - Climb 0 → 7.0 m over ~92 m (about 7.6% average, ≤ 9% after blur).
  - Add a FLAT window over the first ~25 m of the curl, so the bank lift never raises the lower road at the crossing.
- **Village after the gatehouse: drop into the market**, 7.0 → 4.5 m over ~80 m. The lane split (4.5 m) and plaza (8 m) keep today's profile.
- **Lap length limit:** the owner widened Castle Circuit's track_check length check to about **1,200 m** (it was 1,000-1,150 m). Expected length is ~1,146 m and autopilot laps ~41-42 s.
- **Rampart ramp jump (designer's recommendation):** it moves to the end of `free_b`, landing on `kink2`. Kink2's off-camber moves to its second half, so the castle keeps one off-camber bend.
- **Shortcuts unchanged:**
  - Drawbridge: lands at the gate arch, still saves ~1.15 s.
  - Secret passage: moves with the rigid block, still saves ~1.40 s.
  - Lane split: `lane_heights` follow `main_h(s_of(cp))`.

## Risks the designer listed

- `s_of()` / `ts()` use the nearest point on the centreline, which is ambiguous near a self-crossing. Map turtle distance to spline distance by index.
- The gatehouse prop (`gate_position`, gate arch at 50%) now sits under the deck. Keep it under the 6.4 m underside, or make the deck pillars the gatehouse towers.
- The drawbridge water strip reaches within ~2-4 m of the outer edge of the spiral top. The road at 6 m must take priority over the water, or the strip must be trimmed.
- track_check:
  - (13) needs a "spiral" class for a 280° arc.
  - (7) a random infield start without height (NAN) next to the crossing could pick the other level.
  - (16) "samples over a road below" must become > 0 (the evidence that the crossover exists).
- Theme:
  - a barbican tower anchor at the spiral's centre (TrackTheme and track_scenery);
  - a bone balustrade on the gatehouse-top parapet, and a paw crest on the barbican roof (art bible);
  - `solid_below` makes the spiral a solid rampart ring, with an open deck only above the arch.
- Test a falcon and a dropped spill on the deck; check bots (track_check 11).
