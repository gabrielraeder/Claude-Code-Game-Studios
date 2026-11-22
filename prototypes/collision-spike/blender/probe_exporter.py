# PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Lists glTF exporter operator properties (Blender 5.3).
import bpy
props = bpy.ops.export_scene.gltf.get_rna_type().properties
for p in props:
    if p.identifier in ("rna_type",):
        continue
    d = getattr(p, "default", None)
    print("GLTFPROP", p.identifier, p.type, d)
