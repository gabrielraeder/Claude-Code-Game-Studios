<!-- PROTOTYPE - NOT FOR PRODUCTION -->
<!-- Question: Is building a tower maze in one lane fun and readable from an angled 3D camera? -->
<!-- Date: 2026-11-19 -->

# Lane Wars TD: concept prototype

**Status:** concluded. Verdict: **PROCEED (parked)** on 2026-11-19. The concept works, but the
project switched to a kart racer, so this folder is kept for reference only.

## Hypothesis

If a player builds a tower maze on a grid in their lane, watching creeps take the long way round
will feel clever. It's true if, within 10 minutes, the player **rebuilds the maze between waves to
lengthen the path** (not just adds towers) and can read from the angled camera where creeps will go.

## How to run

Double-click `C:/Godot/Godot_v4.8-beta3_win64.exe`, choose **Import**, and pick this folder's
`project.godot`. Then press **F5**.

Or double-click `play.bat` in this folder.

Or from PowerShell at the repo root (the `&` is required):

```powershell
& "C:/Godot/Godot_v4.8-beta3_win64.exe" --path prototypes/lane-wars-concept
```

Add `-- --demo` to start with a sample serpentine maze and wave 1 already running.

**Controls:**

- Left-click: build a tower (10 gold)
- Right-click: sell a tower (100% refund between waves, 50% during a wave)
- Space: send the next wave
- Mouse wheel: zoom
- WASD: pan
- F: toggle 2x speed

## What to look at

- The **yellow ribbon** is the creeps' current route. The HUD shows its length against the straight line (21).
- Hover a cell to see a **cyan ribbon**: the route as it would be if you built there, with the change (+N).
- You cannot fully block the path: the ghost turns red and the build is refused.
- Every wave appends a row to `playtest_log.csv` in this folder: path length, towers, built and sold
  before the wave, kills, leaks. **Sold before wave > 0 with path length going up = the rebuild signal.**

## Cut on purpose

The prototype leaves out:

- Co-op, multiple lanes, PvP and networking
- Menus, game over screen, sound and art
- Upgrades and extra tower or creep types

## Findings

- **Player verdict (2026-11-19, the person who played it):** "it was a great proof of concept".
- **Recorded:** grid mazing with a live path ribbon reads clearly from the angled 3D camera.
  The demo maze stretched the route from 21 to 61 cells (+190%), and creeps re-route correctly.
- **Playtest log (1 session, 2026-11-19, all 10 waves):**
  - **Hypothesis confirmed.**
    - The path grew from 31 to 83 cells (+295% over the straight 21).
    - The player rebuilt the maze twice, selling 4 towers before wave 1 and 5 before wave 9.
    - The path got longer each time, which is the rebuild signal the hypothesis asked for.
  - **Far too easy.**
    - 0 leaks in all 10 waves, 20/20 lives at the end.
    - Gold piled up, peaking at 286.
    - Waves 3, 5, 6 and 8 were sent with no new towers.
    - Creep HP growth (×1.35 per wave) and gold income need retuning before any balance conclusion.
- **If resumed:** next steps were co-op (two lanes into one shared base), then PvP creep sending,
  then online host/join. Production code gets rewritten from scratch, not grown from this folder.
