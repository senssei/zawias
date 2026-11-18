"""Renderuje prosty „koncept” postaci (A-pose, przód, białe tło) do testów generatora 3D.
Użycie: blender -b --python render_test_concept.py -- out.png
"""
import math
import sys

import bpy

out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)

def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1)
    m.diffuse_color = (*rgb, 1)
    return m

skin, cloak, leather, brass = mat("skin", (0.8, 0.55, 0.4)), mat("cloak", (0.45, 0.12, 0.08)), mat("leather", (0.25, 0.15, 0.08)), mat("brass", (0.8, 0.6, 0.2))

def add(fn, loc, scale, m, rot=(0, 0, 0), **kw):
    getattr(bpy.ops.mesh, fn)(location=loc, rotation=rot, **kw)
    o = bpy.context.active_object
    o.scale = scale
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()

add("primitive_cone_add", (0, 0, 0.75), (0.38, 0.3, 0.75), cloak, vertices=32, radius1=1, radius2=0.45, depth=1)
add("primitive_cylinder_add", (0, 0, 1.25), (0.2, 0.14, 0.25), leather, vertices=32)
add("primitive_uv_sphere_add", (0, 0, 1.68), (0.15, 0.15, 0.18), skin, segments=32, ring_count=16)
add("primitive_cone_add", (0, 0, 1.86), (0.2, 0.2, 0.12), brass, vertices=32)
for s in (-1, 1):
    add("primitive_cylinder_add", (0.33 * s, 0, 1.22), (0.05, 0.05, 0.25), leather, rot=(0, math.radians(35 * s), 0), vertices=16)
    add("primitive_uv_sphere_add", (0.47 * s, 0, 1.02), (0.06, 0.06, 0.06), skin)
    add("primitive_cylinder_add", (0.12 * s, 0, 0.12), (0.07, 0.07, 0.12), leather, vertices=16)
add("primitive_cylinder_add", (0.62, 0, 1.0), (0.025, 0.025, 0.9), brass, vertices=12)  # kostur

bpy.ops.object.camera_add(location=(0, -6, 1.0), rotation=(math.radians(90), 0, 0))
cam = bpy.context.active_object
cam.data.type = "ORTHO"
cam.data.ortho_scale = 2.4
bpy.context.scene.camera = cam
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), math.radians(-20), 0))
bpy.context.active_object.data.energy = 3
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "MATERIAL"
sc.render.resolution_x = sc.render.resolution_y = 1024
sc.world = bpy.data.worlds.new("w")
sc.render.film_transparent = False
sc.display.shading.background_type = "VIEWPORT"
sc.display.shading.background_color = (1, 1, 1)
sc.view_settings.view_transform = "Standard"
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("CONCEPT_OK", out)
