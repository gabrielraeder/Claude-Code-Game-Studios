# Story 006 code state

Done: data (war_bike.tres + notes, vehicle_set, racer_set, net_config colours), RacerDef/RacerSet/VehicleSet/PennantStyle,
Pennant + shader, KartVisual model pipeline with fallback, main.gd loadouts + start info (KartWire.VERSION 4),
NetSession loadout RPC, --racer/--vehicle/--lineup flags, LineupShowcase, parse checks ok.
Lineup v3 (real glbs) rendered: shots/lineup-v3 (needs viewing).

Remaining: view lineup-v3; 2-peer net race (port 24690); cart vs bike lap times on both tracks; 12-kart grid shot; report.

UPDATE: all verification done (net2peer, lap-* logs, grid12, solo-chase, lineup-v3). Nothing remaining except user review.

FIX ROUND started: MUST1 bike bot sinks, MUST2 loadout race, SMALL items.

FIX ROUND: bot sink root cause = drift in the s~145 corner before the moat open edge (slide + release boost); fixed in bot_set/bot_driver. MUST2 + SMALLs coded and parse-checked. Remaining: batches, net rerun, lineup-v5, report.

PERF PASS started: add draw-call columns, baseline, optimise KartVisual.

BASELINE (perf-before): fps min 57 p5 60 median 60, draw calls median 241 max 795, objects median 647 (dip at race_time 6.0).
Code edits made: ModelBatcher, pennant merge+cache+prewarm, no-shadow list, bind(slot). Next: lineup-v6, after-run.

lineup-v6b look verified identical (v6 had a packed-array bug, fixed). Running perf-after.

perf-after run1: fps min 56 (at race_time -2.0, race start), p5 60, median 60; draw calls median 154 max 357 (before 241/795); objects median 551 (before 647). Adding KartVisual.prewarm to remove the start hitch; rerun as perf-after2.

perf-after2: min 58 (only the race-start sample, race_time -2.0; building 12 karts takes ~37 ms in one frame, measured by new [net] built line), p5 60, median 60, draw med 154 max 357. Added pole mesh cache; final run perf-after3.

perf-after3 final: see report.
