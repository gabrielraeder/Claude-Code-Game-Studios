# Story 007 sound: placeholder audio

Synthesised by `tools/synth_audio.py` (numpy, fixed seed, deterministic; regenerate with `python tools/synth_audio.py`). 22.05 kHz 16-bit mono. Wiring/tuning: `assets/data/audio/audio_set.tres`; code: `src/audio/`; check: `tools/audio_check.gd`.

| file | use | dur s | peak | RMS | dominant Hz | centroid Hz | loop seam |
|---|---|---|---|---|---|---|---|
| boost.wav | Whoosh on boost | 0.80 | 0.89 | 0.157 | 230 | 4632 | - |
| bump.wav | Kart-kart bump thud | 0.28 | 0.89 | 0.156 | 86 | 2584 | - |
| drift_loop.wav | Hissy scrape + sparks while drifting (loop) | 1.00 | 0.70 | 0.054 | 5071 | 5593 | 0.1210 ( |
| engine_loop.wav | Kart engine hum (loop), pitch-scaled by speed | 1.00 | 0.80 | 0.478 | 55 | 272 | 0.0070 ( |
| falcon_screech.wav | Falcon item screech | 0.75 | 0.89 | 0.275 | 2665 | 4102 | - |
| finish.wav | Victory fanfare | 2.00 | 0.89 | 0.250 | 784 | 2453 | - |
| horn_go.wav | Longer, higher horn for GO | 1.20 | 0.89 | 0.339 | 440 | 1746 | - |
| item_hit.wav | Comic hit when an item lands | 0.45 | 0.89 | 0.099 | 471 | 3360 | - |
| item_horn.wav | Brass war-horn burst (item; countdown 3-2-1 at pitch 0.9) | 0.70 | 0.89 | 0.397 | 220 | 884 | - |
| item_pickup.wav | Item box chime | 0.54 | 0.89 | 0.206 | 1319 | 1654 | - |
| lap.wav | Lap fanfare | 1.00 | 0.89 | 0.294 | 659 | 2535 | - |
| lava_sizzle.wav | Lava sizzle | 0.90 | 0.89 | 0.091 | 150 | 5692 | - |
| music_loop.wav | 24 s music loop, 120 BPM, C major, drone + lute arpeggio + flute melody | 24.00 | 0.45 | 0.114 | 65 | 1070 | 0.0016 ( |
| shield_break.wav | Shield breaks | 0.55 | 0.88 | 0.130 | 3635 | 5863 | - |
| shield_up.wav | Shield activates | 0.60 | 0.89 | 0.191 | 790 | 880 | - |
| spill_splash.wav | Spill puddle splash | 0.60 | 0.89 | 0.152 | 597 | 2288 | - |
| spin.wav | Cartoon wobble when spun out | 0.90 | 0.89 | 0.358 | 214 | 557 | - |
| splash.wav | Moat splash | 0.70 | 0.89 | 0.122 | 173 | 4379 | - |
| stone_launch.wav | Stone thrown | 0.50 | 0.87 | 0.272 | 74 | 3122 | - |
| ui_accept.wav | Menu accept | 0.27 | 0.71 | 0.208 | 659 | 1355 | - |
| ui_back.wav | Menu back | 0.24 | 0.62 | 0.217 | 988 | 1285 | - |
| ui_move.wav | Menu move tick | 0.06 | 0.49 | 0.146 | 900 | 940 | - |
| wall.wav | Wall scrape + thud | 0.45 | 0.89 | 0.135 | 118 | 1481 | - |

Seam = |first sample - last sample|; for loops it is on the order of one normal sample step, since engine/drift noise is built periodic and music wraps note tails. Mute is not heard-tested by a human; nobody listened to these files, judge by ear.