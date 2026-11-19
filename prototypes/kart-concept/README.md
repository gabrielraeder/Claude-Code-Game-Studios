<!-- PROTOTYPE - NOT FOR PRODUCTION -->
<!-- Question: Do drift-for-boost handling plus items make races feel skillful and chaotic? -->
<!-- Date: 2026-11-19 -->

# Kart racer: concept prototype 1 (driving + chaos)

**Status:** concluded. Verdict: **PROCEED** on 2026-11-19. The online part goes to prototype 2.

## Hypothesis

Drifting for boosts plus items make races feel skillful **and** chaotic. It's true if:

- your **lap times improve** as you learn to drift (more orange and purple boosts per race), and
- the **lead changes several times** a race.

Online play is the next prototype (two PCs over ENet host/join). This one is local, against 3 bots.

## How to play

Double-click `play.bat`, or from PowerShell at the repo root:

```powershell
& "C:/Godot/Godot_v4.8-beta3_win64.exe" --path prototypes/kart-concept
```

| Action | Keyboard | Gamepad |
|---|---|---|
| Accelerate / brake (reverse) | W / S or arrow keys | RT / LT |
| Steer | A / D or arrow keys | Left stick |
| **Drift** | Hold Space or Shift while steering | Hold RB (or B) |
| Use item | E or Ctrl | LB (or X) |
| Restart race | R | Start |
| Switch race / time trial | T | Back |

**How drifting works:**

- Hold the drift button while steering at speed. The direction locks in.
- Steer into the turn to tighten it, or away from it to widen.
- Sparks change white → **blue** → **orange** → **purple** the longer you hold, and the bar under
  "Item" fills.
- Release for a boost: the higher the spark level, the longer the boost.

**Items:** drive through the purple boxes. You get better items the further behind you are.

- **Nitro:** a short boost.
- **Bouncer:** fires forward and bounces off walls. It can come back and hit you.
- **Oil slick:** dropped behind you.
- Getting hit spins you out for about 1 second.

**Time trial (T)** is a solo run with no bots and no items, for learning the drift.

## Evidence

Every finished race appends a row to `race_log.csv` in this folder. It records:

- lap times
- drift boosts by level (blue, orange, purple)
- items used, and hits given and taken
- lead changes
- hard wall hits

Things to look for:

- Purple boosts going up while lap times go down: drifting is a learnable skill.
- Lead changes of 5 or more: the races are chaotic.

## Self-test (AI driving, 2026-11-19)

- **Full 3-lap race:** completed in about 1:34. Laps were 29.7, 30.7 and 31.9 s, the lead changed
  10 times, and the player kart was hit 5 times.
- **Drift levels:** the demo autopilot charged orange and purple boosts. The sparks and the drift
  bar showed orange, then purple.
- **Bugs fixed during the self-test:**
  - Boosts stacked past the speed cap: one lap took 13 s, at 213 km/h.
  - Reversing over the finish line could count a lap.
- **Not verified, needs a person:** whether drifting *feels* good on keyboard or gamepad, and
  whether item hits feel fair.

Debug arguments go after `--`:

- `--demo`: the player kart drives itself.
- `--overview`: top-down camera.
- `--fast`: 3x speed.
- `--shots=<dir>`: screenshots at set race times, then quit.

## Cut on purpose

The prototype leaves out:

- Online play (that's prototype 2)
- Menus, characters and art (karts are coloured boxes)
- Sound
- More tracks, shortcuts and split screen

## Findings

- **Player verdict (2026-11-19):** "it's a great prototype"; "the drift feels good enough" for
  an initial version.
- **Race log (1 race):**
  - **Won** (1st/4) in 1:25.7. Laps went from 29.87 to 27.18 to 27.23 s; the bots lap at about 29–30 s.
  - **Drift boosts:** 8 blue, 6 orange, 1 purple. The player used the drift, and it won the race.
  - **Lead changes:** 5. Items used: 2, with 2 hits given and 1 taken. Hard wall hits: 5.
- **Read:** the hypothesis signals are present: drift boosts carry the race and the lead changes
  hands. Improvement *across* races is not shown, since there was only one race.
- **Watch:**
  - The player won comfortably on the first race, so bots may need more speed or smarter items
    once players learn the drift.
  - Purple boosts are rare (1 per race). That's fine as a mastery goal, but check that it stays
    reachable.
