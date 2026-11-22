# ADR-0007 section 4 exception: engine Resources held by `Ref<>` (story 067)

Rule (ADR-0007 section 4, `.claude/rules/native-code.md`): constructors touch no server and create no RID; all
server work is in `create()`.

Exception, named: **engine Resources held by `Ref<>` own their RIDs; their holder is registered for release at
SCENE uninit.**

- Where: `QueryCursor` (`native/src/collision/query_cursor.cpp`). `.new()` takes no arguments (the cursor is built once per
  kart with `QueryCursor.new()`, ADR-0002 "Reuse rules"), so it builds its reused engine objects in the constructor:
  `PhysicsRayQueryParameters3D`, `PhysicsIntersectRayResult3D`, `SphereShape3D` (its server shape is the RID),
  `PhysicsShapeQueryParameters3D`, `PhysicsCastMotionResult3D`, `PhysicsGetRestInfoResult3D`. Building them lazily
  would allocate inside the tick, which the same section forbids.
- Who frees the RID: the `SphereShape3D` Resource, in its own destructor, not the cursor.
- Safety at exit and hot reload: the cursor registers itself (add in the constructor, remove in the destructor).
  `uninitialize_module(SCENE)` calls `QueryCursor::release_all_engine_objects()`, which unrefs every registered
  cursor's Resources and clears `built`, **before** `g_servers_alive` is cleared. A cursor used after that is an
  unbuilt object whose methods refuse.
- Servers not alive at construction: the constructor builds nothing and `is_built()` is false.
- Proof: `tools/collision_exit_probe.gd` (a `QueryCursor`, `GroundHit`, `WallHit` and a built `CollisionQuery` held in
  static variables at quit) run by `tools/native_exit_safety.sh`: exit 0, sentinel, no `ERROR:` line, no leak line.
- Rule for the next class: a class that holds engine Resources joins a registry like this one. The rules file
  `.claude/rules/native-code.md` carries the same wording.
