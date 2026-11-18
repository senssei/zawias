"""Generuje testową postać w formacie zbliżonym do Mixamo (szkielet mixamorig:*),
żeby sprawdzić pipeline bez prawdziwych plików z Mixamo.

Tworzy: <out>/base.fbx, idle.fbx, walk.fbx, attack.fbx, cast.fbx, hit.fbx, death.fbx
oraz <out>/raw_model.glb (gęsta siatka bez rigu do testu prep_for_rig.py).

Użycie: blender -b --python make_test_rig.py -- <katalog_wyjściowy>
"""
import math
import os
import sys

import bpy

out = sys.argv[sys.argv.index("--") + 1]
os.makedirs(out, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)

# --- siatka: tułów, głowa, ręce, nogi
parts = []
def add(prim, loc, scale, **kw):
    getattr(bpy.ops.mesh, prim)(location=loc, **kw)
    o = bpy.context.active_object
    o.scale = scale
    parts.append(o)
    return o

add("primitive_cylinder_add", (0, 0, 1.15), (0.22, 0.14, 0.32), vertices=24)          # tułów
add("primitive_uv_sphere_add", (0, 0, 1.65), (0.13, 0.13, 0.15), segments=24, ring_count=12)  # głowa
for side in (-1, 1):
    add("primitive_cylinder_add", (0.36 * side, 0, 1.35), (0.05, 0.05, 0.2), vertices=12, rotation=(0, math.pi / 2, 0))  # ramię
    add("primitive_cylinder_add", (0.1 * side, 0, 0.45), (0.07, 0.07, 0.42), vertices=12)  # noga
bpy.ops.object.select_all(action="DESELECT")
for p in parts:
    p.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
body = bpy.context.active_object
body.name = "Body"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mat = bpy.data.materials.new("Skin")
mat.diffuse_color = (0.75, 0.45, 0.25, 1)
body.data.materials.append(mat)

# surowy, gęsty model do testu prep_for_rig.py (bez rigu, 3x za duży, przesunięty)
raw = body.copy()
raw.data = body.data.copy()
bpy.context.collection.objects.link(raw)
bpy.ops.object.select_all(action="DESELECT")
raw.select_set(True)
bpy.context.view_layer.objects.active = raw
sub = raw.modifiers.new("Sub", "SUBSURF")
sub.levels = 3
bpy.ops.object.modifier_apply(modifier=sub.name)
raw.scale = (3, 3, 3)
raw.location = (2, 1, 0.5)
bpy.ops.export_scene.gltf(filepath=os.path.join(out, "raw_model.glb"), export_format="GLB", use_selection=True)
bpy.data.objects.remove(raw, do_unlink=True)

# --- szkielet w nazewnictwie Mixamo
bpy.ops.object.armature_add(location=(0, 0, 0))
arm = bpy.context.active_object
arm.name = "Armature"
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
eb.remove(eb[0])
def bone(name, head, tail, parent=None):
    b = eb.new(name)
    b.head, b.tail = head, tail
    if parent:
        b.parent = eb[parent]
    return b
bone("mixamorig:Hips", (0, 0, 0.9), (0, 0, 1.05))
bone("mixamorig:Spine", (0, 0, 1.05), (0, 0, 1.45), "mixamorig:Hips")
bone("mixamorig:Head", (0, 0, 1.5), (0, 0, 1.8), "mixamorig:Spine")
bone("mixamorig:LeftArm", (0.18, 0, 1.38), (0.56, 0, 1.35), "mixamorig:Spine")
bone("mixamorig:RightArm", (-0.18, 0, 1.38), (-0.56, 0, 1.35), "mixamorig:Spine")
bone("mixamorig:LeftUpLeg", (0.1, 0, 0.88), (0.1, 0, 0.05), "mixamorig:Hips")
bone("mixamorig:RightUpLeg", (-0.1, 0, 0.88), (-0.1, 0, 0.05), "mixamorig:Hips")
bpy.ops.object.mode_set(mode="OBJECT")

bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type="ARMATURE_AUTO")

# --- animacje
def anim(name, frames, keys):
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    bpy.ops.object.mode_set(mode="POSE")
    for f, pose in keys:
        for pb in arm.pose.bones:
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = (0, 0, 0)
            pb.location = (0, 0, 0)
        for bname, rot in pose.items():
            pb = arm.pose.bones[bname]
            if bname == "mixamorig:Hips" and isinstance(rot, tuple) and len(rot) == 6:
                pb.location = rot[3:]
                rot = rot[:3]
            pb.rotation_euler = [math.radians(r) for r in rot]
        for pb in arm.pose.bones:
            pb.keyframe_insert("rotation_euler", frame=f)
            pb.keyframe_insert("location", frame=f)
    bpy.ops.object.mode_set(mode="OBJECT")
    return act

acts = {
    "idle":   anim("idle", 40, [(1, {"mixamorig:Spine": (0, 0, 0)}), (20, {"mixamorig:Spine": (4, 0, 0)}), (40, {"mixamorig:Spine": (0, 0, 0)})]),
    "walk":   anim("walk", 24, [(1, {"mixamorig:LeftUpLeg": (25, 0, 0), "mixamorig:RightUpLeg": (-25, 0, 0)}),
                                (12, {"mixamorig:LeftUpLeg": (-25, 0, 0), "mixamorig:RightUpLeg": (25, 0, 0), "mixamorig:Hips": (0, 0, 0, 0, 0.3, 0)}),
                                (24, {"mixamorig:LeftUpLeg": (25, 0, 0), "mixamorig:RightUpLeg": (-25, 0, 0), "mixamorig:Hips": (0, 0, 0, 0, 0.6, 0)})]),
    "attack": anim("attack", 20, [(1, {}), (8, {"mixamorig:RightArm": (0, -70, 60)}), (14, {"mixamorig:RightArm": (0, 40, -20), "mixamorig:Spine": (15, 0, -20)}), (20, {})]),
    "cast":   anim("cast", 24, [(1, {}), (12, {"mixamorig:LeftArm": (0, 0, 70), "mixamorig:RightArm": (0, 0, -70)}), (24, {})]),
    "hit":    anim("hit", 12, [(1, {}), (4, {"mixamorig:Spine": (-25, 0, 0), "mixamorig:Head": (-20, 0, 0)}), (12, {})]),
    "death":  anim("death", 30, [(1, {}), (30, {"mixamorig:Hips": (-85, 0, 0, 0, 0, -0.7)})]),
}

def export(path, action=None):
    arm.animation_data.action = action
    sc = bpy.context.scene
    sc.frame_start = 1
    sc.frame_end = int(action.frame_range[1]) if action else 1
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, bake_anim=action is not None,
                             bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False,
                             add_leaf_bones=False)

export(os.path.join(out, "base.fbx"), None)
for n, act in acts.items():
    act.frame_range  # noqa
    export(os.path.join(out, n + ".fbx"), act)
print("TESTRIG_OK", out)
