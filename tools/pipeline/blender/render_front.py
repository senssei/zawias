# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Renderuje przód postaci kamerą ortogonalną do detekcji pozy i zapisuje mapowanie piksel → metry.

Użycie: blender -b --python render_front.py -- <model.fbx|glb> <out.png> [--res 1024]
Tworzy też <out>.json: {"res", "ortho_scale", "center_z"} (x = (u/res-0.5)*scale, z = center_z+(0.5-v/res)*scale).
"""
import argparse
import json
import math
import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
p = argparse.ArgumentParser()
p.add_argument("model")
p.add_argument("out")
p.add_argument("--res", type=int, default=1024)
a = p.parse_args(argv)

bpy.ops.wm.read_factory_settings(use_empty=True)
if a.model.lower().endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=a.model)
else:
    bpy.ops.import_scene.gltf(filepath=a.model)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
pts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
zmin, zmax = min(q.z for q in pts), max(q.z for q in pts)
xext = max(abs(q.x) for q in pts)
h = zmax - zmin
scale = max(h, 2 * xext) * 1.1
cz = zmin + h / 2

cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = scale
cam = bpy.data.objects.new("cam", cam_data)
bpy.context.collection.objects.link(cam)
cam.location = (0, -10, cz)
cam.rotation_euler = (math.radians(90), 0, 0)
sc = bpy.context.scene
sc.camera = cam
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "TEXTURE"
sc.display.shading.background_type = "WORLD"
sc.world = bpy.data.worlds.new("w")
sc.world.color = (0.55, 0.55, 0.55)
sc.render.resolution_x = sc.render.resolution_y = a.res
sc.view_settings.view_transform = "Standard"
sc.render.filepath = a.out
bpy.ops.render.render(write_still=True)
with open(os.path.splitext(a.out)[0] + ".json", "w") as f:
    json.dump({"res": a.res, "ortho_scale": scale, "center_z": cz}, f)
print("FRONT_OK", a.out)
