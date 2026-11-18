"""Wypisuje szkielet (kości z pozycjami) i animacje z pliku GLB/FBX."""
import sys, bpy
path = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
if path.lower().endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=path)
else:
    bpy.ops.import_scene.gltf(filepath=path)
for o in bpy.context.scene.objects:
    print("OBJ", o.type, o.name, "parent=", o.parent.name if o.parent else None, "scale=", tuple(round(s, 3) for s in o.scale))
    if o.type == "ARMATURE":
        for b in o.data.bones:
            h = o.matrix_world @ b.head_local
            t = o.matrix_world @ b.tail_local
            print("BONE %-28s parent=%-22s head=(%.3f,%.3f,%.3f) tail=(%.3f,%.3f,%.3f)" % (
                b.name, b.parent.name if b.parent else "-", h.x, h.y, h.z, t.x, t.y, t.z))
print("ACTIONS", len(bpy.data.actions))
for a in bpy.data.actions:
    print("ACT", a.name, tuple(int(x) for x in a.frame_range))
