---
paths:
  - "src/**"
  - "tools/**/*.gd"
---

# RefCounted Cycles (Dogworks Racing)

Many of the game's simulation objects are `RefCounted`, not Nodes: `KartSim`, `TrackModel`, `LapCounter`, drivers, items' runtime state. A RefCounted object is freed only when nothing references it. If its own signal stores a callable that holds the object strongly, it can never be freed. The leaked objects are torn down late at engine exit, which crashes the game with no backtrace (exit code 139). This happened twice: in story 007 (race sounds, also leaking "resources still in use at exit") and in story 009 (a bot hazard log, a crash at exit on every track with bots).

## The rule

Never connect a lambda or bound callable that captures or binds a RefCounted object **strongly** to a signal of that same object, or of anything that object keeps alive.

- **Wrong:** `sim.mover_hit.connect(func(i: int) -> void: print(sim.speed))`. The lambda captures `sim`, and `sim` stores the lambda.
- **Wrong:** `sim.kart_bumped.connect(_on_bump.bind(sim))`. The bound argument holds `sim` strongly.
- **Right:** bind a `WeakRef` and resolve it in a named method:

```gdscript
sim.mover_hit.connect(_on_mover_hit.bind(weakref(sim)))

func _on_mover_hit(mover_index: int, sim_ref: WeakRef) -> void:
    var sim: KartSim = sim_ref.get_ref() as KartSim
    if sim == null:
        return
    ...
```

- **Also fine:**
  - a lambda that captures only Nodes, or values (ints, floats, strings), or `self` when `self` is a Node or outlives the object;
  - a method of an object that does not keep the emitter alive.
- **Disconnect** connections to long-lived objects when the short-lived side goes away. Also clear static vars that hold Nodes or Resources (they survive until exit) in `_exit_tree`.

## How to check before you hand off

- Any new `connect(` in your diff: does the callable capture or bind the emitting object, or something that owns it? If so, use the WeakRef form.
- Run a host with bots and quit early. It must exit with code 0:

  ```
  godot --headless --path . -- --host --port=24690 --players=1 --bots=3 --autopilot --laps=1 --track=castle_circuit --quit-after=8; echo $?
  ```

  It must also print no new "resources still in use at exit" lines.

## Cleanup in `NOTIFICATION_PREDELETE` (found in core-rebuild story 003)

On Godot 4.8-beta3, inside a RefCounted's `_notification(NOTIFICATION_PREDELETE)`, calling an instance method (`dispose()`) fails with "Attempt to call function ... in base 'null instance'": `self` is already unusable. A fallback that must free server RIDs (PhysicsServer3D bodies, shapes, spaces) therefore calls a **static** function with the RIDs as arguments, e.g. `CollisionQuery._free_server_objects(bodies, shapes, space)`, which both `dispose()` and the PREDELETE fallback use. Test it: drop the object without `dispose()` and check every RID is freed.
