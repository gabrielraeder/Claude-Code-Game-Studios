---
paths:
  - "src/**"
  - "tools/**/*.gd"
---

# Tuning Values (Dogworks Racing)

Every number a designer or the owner might want to tune lives in a data file, never as a literal in code. The game's code root is `src/`, split by system (`vehicle`, `ai`, `items`, `track`, `test_track`, `race`, `net`, `ui`, `audio`, `input`, `debug`), so this rule covers all of `src/`. The framework's `gameplay-code.md` only covers `src/gameplay/` and `src/game/`, which this project does not use.

## Goes in data (a `.tres` Resource, with a `##` doc comment on its `@export`)

- Speeds, accelerations, forces, gravity, grip.
- Times, durations, windows, delays, cooldowns.
- Distances, radii, heights, margins, tolerances that change how the game plays or looks.
- Chances, weights, odds, counts, limits.
- Sizes, colours, volumes, pitches and fonts on screen.
- Anything the brief, a story or the owner names as a value.

Where it lives: the system's own Resource. For example `VehicleStats` / `VehicleVisualStats` (`assets/data/vehicles/`), `BotSet` (`assets/data/ai/`), `ItemSet`, `NetConfig`, `TrackData` / `TrackTheme` (the track generators write these), `UiTheme`, `AudioSet`.

## May stay in code

- `0`, `1`, `-1`, `0.0`, `1.0`: resets, identities, signs, array starts.
- Math constants (`PI`, `TAU`, unit conversions such as `3.6` for m/s to km/h) and pure geometry.
- A named `const` with a `##` comment, for something that is not tuning. Examples: an epsilon, a wire field index, a file format version, a protocol magic number.
- Debug and test-tool values that only run behind a debug flag (`src/debug/`, `tools/`). Use a named `const` there too.

## How to work

- A new tuning value gets a data field with a default equal to the intended value, and an explicit entry in the `.tres` when the value differs per vehicle, track or set.
- Report every new data field, with its value and file, in your hand-off (the "choices the story did not specify" list).
- Before you commit, read your own diff's added lines for numeric literals (`git diff --cached -U0`). Move any tuning value to data, or turn it into a named `const` with a comment that says why it is not tuning.

## Examples

Correct:

```gdscript
var boost: float = stats.trick_boost_time            # tuning, from VehicleStats
const EPSILON: float = 0.001                          ## float compare tolerance, not tuning
velocity = Vector2.ZERO                               # reset
```

Incorrect:

```gdscript
var boost: float = 0.7          # VIOLATION: tuning value as a literal
if speed > 24.0: ...            # VIOLATION: a gate speed belongs in TrackData
```

The commit hook `validate-commit.sh` warns when an added line assigns a literal other than 0/1/-1 to a name containing damage, health, speed, rate, chance, cost or duration. It skips comments, `const` lines and `@export` lines, because a data Resource's field default is the data-driven home of the value. It is a heuristic. This rule applies to every tuning value, whatever its name.
