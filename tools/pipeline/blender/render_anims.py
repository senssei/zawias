# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Renderuje klatkę z każdej animacji zriggowanej postaci (kontrola jakości).
Użycie: blender -b --python render_anims.py -- <postać.glb> <katalog_wyjściowy> [--at 0.4]
"""
import argparse, math, os, sys
import bpy
argv = sys.argv[sys.argv.index("--") + 1:]
p = argparse.ArgumentParser(); p.add_argument("glb"); p.add_argument("out"); p.add_argument("--at", type=float, default=0.4)
a = p.parse_args(argv)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=a.glb)
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
sc = bpy.context.scene
cam_data = bpy.data.cameras.new("c"); cam_data.type = "ORTHO"; cam_data.ortho_scale = 2.6
cam = bpy.data.objects.new("c", cam_data); bpy.context.collection.objects.link(cam)
r = math.radians(35); cam.location = (6 * math.sin(r), -6 * math.cos(r), 0.95); cam.rotation_euler = (math.radians(90), 0, r)
sc.camera = cam
sc.render.engine = "BLENDER_WORKBENCH"; sc.display.shading.light = "STUDIO"; sc.display.shading.color_type = "TEXTURE"
sc.display.shading.background_type = "WORLD"; sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.5, 0.5, 0.5)
sc.render.resolution_x = sc.render.resolution_y = 512; sc.view_settings.view_transform = "Standard"
os.makedirs(a.out, exist_ok=True)
if arm.animation_data is None: arm.animation_data_create()
for t in list(arm.animation_data.nla_tracks): arm.animation_data.nla_tracks.remove(t)
names = []
for act in bpy.data.actions:
    arm.animation_data.action = act
    if hasattr(arm.animation_data, "action_slot") and len(act.slots): arm.animation_data.action_slot = act.slots[0]
    f0, f1 = act.frame_range
    sc.frame_set(int(f0 + (f1 - f0) * a.at))
    sc.render.filepath = os.path.join(a.out, act.name + ".png")
    bpy.ops.render.render(write_still=True)
    names.append(act.name)
arm.animation_data.action = None
sc.frame_set(0)
for pb in arm.pose.bones: pb.matrix_basis.identity()
sc.render.filepath = os.path.join(a.out, "_rest.png"); bpy.ops.render.render(write_still=True)
print("ANIMS_OK", names)
