# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Auto-rig postaci szkieletem Quaternius UAL (CC0) i przeniesienie animacji, w pełni lokalnie.

Wejście: siatka (po prep, stopy na 0, przód w -Y), punkty pozy z DWPose na renderze przodu
(render_front.py + comfy_pose.py) oraz biblioteka UAL1_Standard.glb.

Algorytm:
 1. Szkielet UAL dopasowany do proporcji postaci (pozycje stawów z punktów pozy, głębokość z siatki).
    Każda kość zachowuje orientację z UAL, więc animacje UAL działają bez retargetingu.
 2. Kopia szkieletu jest ustawiana w pozie siatki (ręce w A-pose) i do niej liczone są wagi (bone heat).
 3. Siatka jest deformowana do T-pose szkieletu UAL i przepinana na właściwy szkielet.
 4. Wybrane animacje są przemianowane na nazwy gry, a przesunięcia bioder przeskalowane do wzrostu.

Użycie: blender -b --python autorig_ual.py -- <mesh.fbx|glb> <pose.json> <front.json> <UAL1.glb> <out.glb>
"""
import argparse
import json
import os
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ANIMS = {
    "idle": "Idle_Loop", "walk": "Walk_Loop", "run": "Jog_Fwd_Loop", "attack": "Sword_Attack",
    "cast": "Spell_Simple_Shoot", "hit": "Hit_Chest", "death": "Death01", "talk": "Idle_Talking_Loop",
    "punch": "Punch_Jab", "interact": "Interact",
}
KP = {n: i for i, n in enumerate(
    "nose neck r_sho r_elb r_wri l_sho l_elb l_wri r_hip r_kne r_ank l_hip l_kne l_ank r_eye l_eye r_ear l_ear".split())}


def parse():
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    for n in ("mesh", "pose", "front", "ual", "out"):
        p.add_argument(n)
    p.add_argument("--min-conf", type=float, default=0.3)
    return p.parse_args(argv)


def fcurves(action):
    if hasattr(action, "layers") and len(action.layers) > 0:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    yield from bag.fcurves
    elif hasattr(action, "fcurves"):
        yield from action.fcurves


def select_only(objs, active):
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active


def main():
    a = parse()
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # --- biblioteka UAL
    bpy.ops.import_scene.gltf(filepath=a.ual)
    rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    ual_mesh = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    ual_top = max((o.matrix_world @ v.co).z for o in ual_mesh if o.parent == rig for v in o.data.vertices)
    for o in ual_mesh:
        bpy.data.objects.remove(o, do_unlink=True)
    rig.name = "Armature"
    if rig.animation_data:
        rig.animation_data.action = None
        for t in list(rig.animation_data.nla_tracks):
            rig.animation_data.nla_tracks.remove(t)

    # --- postać
    before = set(bpy.context.scene.objects)
    if a.mesh.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=a.mesh)
    else:
        bpy.ops.import_scene.gltf(filepath=a.mesh)
    new = [o for o in bpy.context.scene.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    select_only(meshes, meshes[0])
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    if len(meshes) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    for o in new:
        if o != body and o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)
    body.rotation_mode = "XYZ"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    body.name = "Body"
    verts = [v.co.copy() for v in body.data.vertices]
    zmax = max(v.z for v in verts)
    bvh = BVHTree.FromPolygons(verts, [p.vertices[:] for p in body.data.polygons])

    # --- punkty pozy → metry
    front = json.load(open(a.front))
    kpd = json.load(open(a.pose))[0]
    body_kp = kpd["people"][0]["pose_keypoints_2d"]
    sx = front["res"] / kpd["canvas_width"]
    sy = front["res"] / kpd["canvas_height"]

    def depth(x, z):
        hits = []
        for origin, d in (((x, -5.0, z), (0, 1, 0)), ((x, 5.0, z), (0, -1, 0))):
            loc, *_ = bvh.ray_cast(Vector(origin), Vector(d))
            if loc:
                hits.append(loc.y)
        if len(hits) == 2:
            return (hits[0] + hits[1]) / 2
        loc, *_ = bvh.find_nearest(Vector((x, 0, z)))
        return loc.y if loc else 0.0

    def J(name):
        i = KP[name]
        u, v, c = body_kp[i * 3] * sx, body_kp[i * 3 + 1] * sy, body_kp[i * 3 + 2]
        if c < a.min_conf:
            raise SystemExit("Za mało pewny punkt pozy: %s (%.2f). Sprawdź render przodu." % (name, c))
        x = (u / front["res"] - 0.5) * front["ortho_scale"]
        z = front["center_z"] + (0.5 - v / front["res"]) * front["ortho_scale"]
        return Vector((x, depth(x, z), z))

    jt = {n: J(n) for n in ("neck", "nose", "r_sho", "r_elb", "r_wri", "l_sho", "l_elb", "l_wri",
                             "r_hip", "r_kne", "r_ank", "l_hip", "l_kne", "l_ank")}

    # --- dopasowanie szkieletu (orientacje kości z UAL, zmieniamy pozycje i długości)
    select_only([rig], rig)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones
    ref = {b.name: (b.head.copy(), b.tail.copy(), b.length) for b in eb}
    for b in eb:
        b.use_connect = False

    def H(n):
        return ref[n][0]

    def place(n, head, scale=1.0, length=None):
        h, t, ln = ref[n]
        d = (t - h).normalized()
        b = eb[n]
        b.head = head
        b.tail = head + d * (length if length is not None else ln * scale)

    hip_z = (jt["l_hip"].z + jt["r_hip"].z) / 2
    sho_z = (jt["l_sho"].z + jt["r_sho"].z) / 2
    ual_hip, ual_sho = H("DEF-thigh.L").z, H("DEF-upper_arm.L").z
    anchors = [(0.0, 0.0), (ual_hip, hip_z), (ual_sho, sho_z), (ual_top, zmax)]

    def mapz(z):
        for (z0, t0), (z1, t1) in zip(anchors, anchors[1:]):
            if z <= z1 or (z1, t1) == anchors[-1]:
                return t0 + (z - z0) * (t1 - t0) / (z1 - z0)
        return z

    torso_k = (sho_z - hip_z) / (ual_sho - ual_hip)
    head_k = (zmax - sho_z) / (ual_top - ual_sho)
    cx = (jt["l_hip"].x + jt["r_hip"].x) / 2
    for n, k in (("DEF-hips", torso_k), ("DEF-spine.001", torso_k), ("DEF-spine.002", torso_k),
                 ("DEF-spine.003", torso_k), ("DEF-neck", head_k), ("DEF-head", head_k)):
        z = mapz(H(n).z)
        place(n, Vector((cx, depth(cx, z), z)), k)

    width_k = (jt["l_sho"].x - jt["r_sho"].x) / (H("DEF-upper_arm.L").x - H("DEF-upper_arm.R").x)
    leg_ref = (H("DEF-thigh.L") - H("DEF-foot.L")).length
    for s, side in (("L", "l"), ("R", "r")):
        # nogi
        hip, kne, ank = jt[side + "_hip"], jt[side + "_kne"], jt[side + "_ank"]
        leg_k = (hip - ank).length / leg_ref
        place("DEF-thigh." + s, hip, length=(kne - hip).length)
        place("DEF-shin." + s, eb["DEF-thigh." + s].tail.copy(), length=(ank - kne).length)
        place("DEF-foot." + s, eb["DEF-shin." + s].tail.copy(), leg_k)
        place("DEF-toe." + s, eb["DEF-foot." + s].tail.copy(), leg_k)
        # ręce: T-pose UAL o długościach postaci
        sho, elb, wri = jt[side + "_sho"], jt[side + "_elb"], jt[side + "_wri"]
        l1, l2 = (elb - sho).length, (wri - elb).length
        arm_k = (l1 + l2) / ((H("DEF-forearm." + s) - H("DEF-upper_arm." + s)).length
                             + (H("DEF-hand." + s) - H("DEF-forearm." + s)).length)
        sh_off = (H("DEF-upper_arm." + s) - H("DEF-shoulder." + s)) * width_k
        place("DEF-shoulder." + s, sho - sh_off, width_k)
        place("DEF-upper_arm." + s, sho, length=l1)
        place("DEF-forearm." + s, eb["DEF-upper_arm." + s].tail.copy(), length=l2)
        hand_head = eb["DEF-forearm." + s].tail.copy()
        place("DEF-hand." + s, hand_head, arm_k)
        for b in eb:
            if b.name.startswith(("DEF-f_", "DEF-thumb")) and b.name.endswith("." + s):
                place(b.name, hand_head + (H(b.name) - H("DEF-hand." + s)) * arm_k, arm_k)
    bpy.ops.object.mode_set(mode="OBJECT")
    for b in rig.data.bones:
        b.use_deform = b.name.startswith("DEF-")

    # --- kopia szkieletu w pozie siatki (ręce jak na modelu)
    rig_a = rig.copy()
    rig_a.data = rig.data.copy()
    rig_a.animation_data_clear()
    bpy.context.collection.objects.link(rig_a)
    select_only([rig_a], rig_a)
    bpy.ops.object.mode_set(mode="POSE")
    for s, side in (("L", "l"), ("R", "r")):
        for bone, a_from, a_to in (("DEF-upper_arm.", side + "_sho", side + "_elb"),
                                   ("DEF-forearm.", side + "_elb", side + "_wri")):
            pb = rig_a.pose.bones[bone + s]
            bpy.context.view_layer.update()
            cur = pb.matrix.copy()
            cur_dir = (cur.to_3x3() @ Vector((0, 1, 0))).normalized()
            want = (jt[a_to] - jt[a_from]).normalized()
            q = cur_dir.rotation_difference(want)
            pb.matrix = Matrix.Translation(cur.translation) @ q.to_matrix().to_4x4() @ cur.to_3x3().to_4x4()
            bpy.context.view_layer.update()
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")

    if os.environ.get("AUTORIG_DEBUG_BLEND"):
        bpy.ops.wm.save_as_mainfile(filepath=os.environ["AUTORIG_DEBUG_BLEND"])
    # --- wagi liczone na szkielecie w pozie siatki
    auto_weights(body, rig_a)
    groups = {g.index: g.name for g in body.vertex_groups}
    unweighted = sum(1 for v in body.data.vertices if sum(g.weight for g in v.groups) < 1e-4)
    print("DEBUG po bone heat: groups=%d unweighted=%d" % (len(body.vertex_groups), unweighted))
    if unweighted > len(body.data.vertices) * 0.02:
        print("WEIGHTS_FALLBACK: %d wierzchołków bez wag, liczę na proxy" % unweighted)
        weights_via_proxy(body, rig_a)
        unweighted = sum(1 for v in body.data.vertices if sum(g.weight for g in v.groups) < 1e-4)
        if unweighted > len(body.data.vertices) * 0.02:
            print("WEIGHTS_FALLBACK2: bone heat zawiódł też na proxy, wagi z odległości do kości")
            weights_by_distance(body, rig_a)

    clean_arm_weights(body, rig_a, near=0.07 * zmax / 1.8, far=0.16 * zmax / 1.8)
    smooth_weights(body)

    # --- siatka do T-pose: ustaw kopię w pozie spoczynkowej docelowego szkieletu i zapisz deformację
    select_only([rig_a], rig_a)
    bpy.ops.object.mode_set(mode="POSE")
    order = sorted(rig_a.pose.bones, key=lambda pb: len(pb.bone.parent_recursive))
    for pb in order:
        pb.matrix = rig.data.bones[pb.name].matrix_local.copy()
        bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode="OBJECT")
    select_only([body], body)
    mod = next(m for m in body.modifiers if m.type == "ARMATURE")
    bpy.ops.object.modifier_apply(modifier=mod.name)
    body.parent = None
    bpy.data.objects.remove(rig_a, do_unlink=True)
    body.parent = rig
    body.matrix_parent_inverse = Matrix.Identity(4)
    m2 = body.modifiers.new("Armature", "ARMATURE")
    m2.object = rig
    del groups

    # --- animacje
    height_k = hip_z / ual_hip
    keep = {}
    for dst, src in ANIMS.items():
        act = bpy.data.actions.get(src)
        if act is None:
            print("BRAK ANIMACJI w UAL:", src)
            continue
        act.name = dst
        act.use_fake_user = True
        for fc in fcurves(act):
            if fc.data_path.endswith("location"):
                for kp in fc.keyframe_points:
                    kp.co[1] *= height_k
                    kp.handle_left[1] *= height_k
                    kp.handle_right[1] *= height_k
        keep[dst] = act
    for act in list(bpy.data.actions):
        if act.name not in keep:
            bpy.data.actions.remove(act)
    if rig.animation_data is None:
        rig.animation_data_create()
    for name, act in keep.items():
        tr = rig.animation_data.nla_tracks.new()
        tr.name = name
        st = tr.strips.new(name, int(act.frame_range[0]), act)
        if hasattr(st, "action_slot") and hasattr(act, "slots") and len(act.slots):
            st.action_slot = act.slots[0]
    rig.animation_data.action = None

    unw = sum(1 for v in body.data.vertices if sum(g.weight for g in v.groups) < 1e-4)
    if unw > len(body.data.vertices) * 0.02:
        raise SystemExit("Brak wag dla %d/%d wierzchołków, rig nieudany" % (unw, len(body.data.vertices)))
    print("DEBUG groups=%d unweighted=%d/%d mods=%s parent=%s" % (
        len(body.vertex_groups), unw, len(body.data.vertices), [(m.type, getattr(m, "object", None) and m.object.name) for m in body.modifiers],
        body.parent and body.parent.name))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=a.out, export_format="GLB", export_animation_mode="ACTIONS", export_skins=True,
        export_yup=True, export_force_sampling=True, export_optimize_animation_size=True,
    )
    print("AUTORIG_OK %s animacje=%s wzrost=%.2f m, biodra=%.2f, barki=%.2f" % (
        a.out, ",".join(keep), zmax, hip_z, sho_z))


def _seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12)))
    return (a + ab * t - p).length


def clean_arm_weights(body, arm, near, far):
    """Usuwa wagi rąk z wierzchołków daleko od kości ręki (np. spódnica przy dłoniach w A-pose)."""
    names = {g.index: g.name for g in body.vertex_groups}
    by_name = {g.name: g for g in body.vertex_groups}
    segs = {}
    for side in ("L", "R"):
        chain = []
        for n in ("DEF-shoulder.", "DEF-upper_arm.", "DEF-forearm.", "DEF-hand."):
            b = arm.data.bones[n + side]
            chain.append((arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local))
        hb = arm.data.bones["DEF-hand." + side]
        h, t = arm.matrix_world @ hb.head_local, arm.matrix_world @ hb.tail_local
        chain.append((t, t + (t - h).normalized() * 0.12))  # palce
        segs[side] = chain
    torso = [b for b in arm.data.bones if b.use_deform and not any(
        k in b.name for k in ("shoulder", "upper_arm", "forearm", "hand", "f_", "thumb"))]
    fixed = 0
    mw = body.matrix_world
    for v in body.data.vertices:
        p = mw @ v.co
        for side in ("L", "R"):
            arm_groups = [g for g in v.groups if names[g.group].endswith("." + side) and any(
                k in names[g.group] for k in ("shoulder", "upper_arm", "forearm", "hand", "f_", "thumb"))]
            if not arm_groups:
                continue
            d = min(_seg_dist(p, a, b) for a, b in segs[side])
            if d <= near:
                continue
            if d <= far:
                dt = min(_seg_dist(p, arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local) for b in torso)
                if dt >= d:
                    continue
            for g in arm_groups:
                body.vertex_groups[g.group].remove([v.index])
            fixed += 1
            if sum(g.weight for g in v.groups) < 1e-4:
                best = min(torso, key=lambda b: _seg_dist(p, arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local))
                by_name[best.name].add([v.index], 1.0, "REPLACE")
    print("ARM_WEIGHTS_CLEANED", fixed)


def smooth_weights(body):
    """Wygładza przejścia wag (mniej szpikulców), ogranicza do 4 kości na wierzchołek i normalizuje."""
    select_only([body], body)
    body.vertex_groups.active_index = 0
    bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
    try:
        bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=0.5, repeat=4, expand=0.0)
        bpy.ops.object.vertex_group_clean(group_select_mode="ALL", limit=0.02, keep_single=True)
        bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
        bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
        print("WEIGHTS_SMOOTHED")
    except RuntimeError as ex:
        print("WEIGHTS_SMOOTH_SKIPPED", ex)
    bpy.ops.object.mode_set(mode="OBJECT")


def scale_apply(objs, k):
    for o in objs:
        select_only([o], o)
        o.scale = o.scale * k
        o.location = o.location * k
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)


def auto_weights(mesh, arm, k=10.0):
    """Bone heat zawodzi na małych siatkach, więc liczymy wagi w skali x10 i wracamy."""
    if mesh.parent:
        mesh.parent = None
    scale_apply([mesh, arm], k)
    select_only([mesh, arm], arm)
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    mesh.parent = None
    scale_apply([mesh, arm], 1.0 / k)
    mesh.parent = arm
    mesh.matrix_parent_inverse.identity()
    for m in mesh.modifiers:
        if m.type == "ARMATURE":
            m.object = arm


def weights_by_distance(body, arm, k=3, power=4.0):
    """Wagi z odwrotności odległości do k najbliższych kości (palce liczone jako dłoń). Zawsze działa."""
    bones = []
    for b in arm.data.bones:
        if not b.use_deform or b.name.startswith(("DEF-f_", "DEF-thumb")):
            continue
        h, t = arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local
        if b.name.startswith("DEF-hand"):
            t = t + (t - h).normalized() * 0.1
        bones.append((b.name, h, t))
    body.vertex_groups.clear()
    groups = {n: body.vertex_groups.new(name=n) for n, _, _ in bones}
    for b in arm.data.bones:
        if b.use_deform and b.name not in groups:
            body.vertex_groups.new(name=b.name)
    mw = body.matrix_world
    for v in body.data.vertices:
        p = mw @ v.co
        ds = sorted(((_seg_dist(p, h, t), n) for n, h, t in bones))[:k]
        ws = [1.0 / max(d, 1e-3) ** power for d, _ in ds]
        tot = sum(ws)
        for (d, n), w in zip(ds, ws):
            groups[n].add([v.index], w / tot, "REPLACE")


def weights_via_proxy(body, arm):
    """Wagi liczone na zamkniętej siatce zastępczej (remesh) i przeniesione na model."""
    proxy = body.copy()
    proxy.data = body.data.copy()
    proxy.vertex_groups.clear()
    for m in list(proxy.modifiers):
        proxy.modifiers.remove(m)
    bpy.context.collection.objects.link(proxy)
    rm = proxy.modifiers.new("Remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = 0.012
    select_only([proxy], proxy)
    bpy.ops.object.modifier_apply(modifier=rm.name)
    auto_weights(proxy, arm)
    body.vertex_groups.clear()
    for g in proxy.vertex_groups:
        body.vertex_groups.new(name=g.name)
    dt = body.modifiers.new("WeightsXfer", "DATA_TRANSFER")
    dt.object = proxy
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    select_only([body], body)
    bpy.ops.object.datalayout_transfer(modifier=dt.name)
    bpy.ops.object.modifier_move_to_index(modifier=dt.name, index=0)
    bpy.ops.object.modifier_apply(modifier=dt.name)
    unw = sum(1 for v in body.data.vertices if sum(g.weight for g in v.groups) < 1e-4)
    pw = sum(1 for v in proxy.data.vertices if sum(g.weight for g in v.groups) < 1e-4)
    print("DEBUG proxy: verts=%d bez wag na proxy=%d, na modelu po transferze=%d" % (len(proxy.data.vertices), pw, unw))
    bpy.data.objects.remove(proxy, do_unlink=True)


main()
