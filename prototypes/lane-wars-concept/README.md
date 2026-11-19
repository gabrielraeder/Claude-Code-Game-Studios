<!-- PROTOTYPE - NOT FOR PRODUCTION -->
<!-- Question: Is building a tower maze in one lane fun and readable from an angled 3D camera? -->
<!-- Date: 2026-11-19 -->

# Lane Wars TD: concept prototype

**Status:** in progress

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

_To be filled after play._
