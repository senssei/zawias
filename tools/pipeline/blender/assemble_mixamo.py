# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Składa postać z Mixamo w jeden plik GLB dla gry.

Katalog wejściowy:
  base.fbx (albo character.fbx)  model z rigiem, pobrany z Mixamo „With Skin”
  idle.fbx, walk.fbx, attack.fbx, cast.fbx, hit.fbx, death.fbx ...
                                 animacje (With albo Without Skin, walk najlepiej „In Place”)
Nazwa pliku animacji staje się nazwą animacji w grze.

Użycie:
  blender -b --python assemble_mixamo.py -- <katalog> <out.glb> [--tris 0] [--in-place walk,run]
"""
import argparse
import glob
import os
import sys

import bpy

BASE_NAMES = ("base", "character", "model", "tpose")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("input_dir")
    p.add_argument("output")
    p.add_argument("--tris", type=int, default=0, help="redukcja siatki (0 = bez)")
    p.add_argument("--in-place", default="walk,run", help="animacje, którym usunąć przesunięcie w poziomie")
    return p.parse_args(argv)


def find_files(d):
    files = sorted({os.path.normcase(f): f for f in glob.glob(os.path.join(d, "*.[fF][bB][xX]"))}.values())
    base = None
    for f in files:
        if os.path.splitext(os.path.basename(f))[0].lower() in BASE_NAMES:
            base = f
    if base is None:
        raise SystemExit("Brak base.fbx / character.fbx w " + d)
    return base, [f for f in files if f != base]


def import_fbx(path):
    before_obj = set(bpy.data.objects)
    before_act = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=False, ignore_leaf_bones=True)
    return set(bpy.data.objects) - before_obj, set(bpy.data.actions) - before_act


def strip_root_motion(action):
    """Usuwa poziomy ruch kości bioder (Hips), żeby chód był w miejscu."""
    for fc in list(_fcurves(action)):
        if "Hips" in fc.data_path and fc.data_path.endswith("location") and fc.array_index in (0, 2):
            first = fc.keyframe_points[0].co[1] if len(fc.keyframe_points) else 0.0
            for kp in fc.keyframe_points:
                kp.co[1] = first
                kp.handle_left[1] = first
                kp.handle_right[1] = first


def _fcurves(action):
    # Blender 4.4+ ma akcje warstwowe (slots/layers); starsze wersje mają action.fcurves
    if hasattr(action, "layers") and len(action.layers) > 0:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    yield from bag.fcurves
    elif hasattr(action, "fcurves"):
        yield from action.fcurves


def main():
    a = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    base, anims = find_files(a.input_dir)
    objs, _ = import_fbx(base)
    arm = next((o for o in objs if o.type == "ARMATURE"), None)
    if arm is None:
        raise SystemExit("base.fbx nie zawiera szkieletu (pobierz z Mixamo z opcją With Skin)")
    arm.name = "Armature"
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = None
    in_place = {n.strip().lower() for n in a.in_place.split(",") if n.strip()}

    names = []
    for f in anims:
        name = os.path.splitext(os.path.basename(f))[0].lower()
        new_objs, new_acts = import_fbx(f)
        src = next((o for o in new_objs if o.type == "ARMATURE"), None)
        act = None
        if src is not None and src.animation_data and src.animation_data.action:
            act = src.animation_data.action
        elif new_acts:
            act = next(iter(new_acts))
        for o in new_objs:
            bpy.data.objects.remove(o, do_unlink=True)
        if act is None:
            print("POMINIĘTO (brak animacji):", f)
            continue
        act.name = name
        act.use_fake_user = True
        if name in in_place:
            strip_root_motion(act)
        track = arm.animation_data.nla_tracks.new()
        track.name = name
        start = int(act.frame_range[0])
        strip = track.strips.new(name, start, act)
        if hasattr(strip, "action_slot") and hasattr(act, "slots") and len(act.slots) > 0:
            strip.action_slot = act.slots[0]
        track.mute = False
        names.append(name)

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if a.tris > 0:
        for m in meshes:
            tris = sum(len(p.vertices) - 2 for p in m.data.polygons)
            if tris > a.tris:
                mod = m.modifiers.new("Decimate", "DECIMATE")
                mod.ratio = a.tris / tris
                bpy.context.view_layer.objects.active = m
                bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
                bpy.ops.object.modifier_apply(modifier=mod.name)

    os.makedirs(os.path.dirname(os.path.abspath(a.output)), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=a.output, export_format="GLB", export_animation_mode="ACTIONS",
        export_skins=True, export_yup=True, export_apply=False,
        export_force_sampling=True, export_optimize_animation_size=True,
    )
    print("ASSEMBLE_OK %s animacje=%s meshes=%d" % (a.output, ",".join(names), len(meshes)))


main()
