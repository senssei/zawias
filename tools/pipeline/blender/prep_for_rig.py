# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Czyści model z generatora (np. Hunyuan3D w ComfyUI) przed riggingiem w Mixamo.

Łączy siatki, ustawia stopy na zero i środek w osi, skaluje do zadanej wysokości,
redukuje liczbę trójkątów i eksportuje FBX z osadzonymi teksturami.

Cleanup (zawsze): scalanie wierzchołków, normalne na zewnątrz, usuwanie drobnych odłamków siatki
(wyspy małe i nieliczne; dłonie jako osobne wyspy zostają).
AO: gdy model ma occlusionTexture (TRELLIS.2 preset final/hero), AO jest wypalane w kolor bazowy (--ao 0.8),
bo renderer Compatibility nie ma SSAO, a samej mapy AO nie używa.
Materiały (opcjonalnie): --max-texture (zmniejsza tekstury), --palette-strength (stała paleta z palette.json),
--grade-ref/--grade (paleta z obrazu referencyjnego),
--glow (emisja z jasnych, ciepłych lub fioletowych miejsc tekstury, np. latarnie, runy).

Użycie:
  blender -b --python prep_for_rig.py -- in.glb out.fbx|out.glb [--height 1.8] [--tris 12000] [--rotate-z 0]
        [--max-texture 1024] [--ao 0.8] [--palette zawias --palette-strength 0.35]
        [--grade-ref styl.png --grade 0.35] [--glow] [--no-cleanup]
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("input")
    p.add_argument("output")
    p.add_argument("--height", type=float, default=1.8, help="docelowa wysokość w metrach")
    p.add_argument("--tris", type=int, default=12000, help="maks. liczba trójkątów (0 = bez redukcji)")
    p.add_argument("--rotate-z", type=float, default=0.0, help="obrót w stopniach, gdy model nie patrzy w -Y")
    p.add_argument("--preview", default="", help="opcjonalny podgląd PNG")
    p.add_argument("--gamma-fix", type=float, default=0.0,
                   help="korekta gammy koloru bazowego (np. 2.2, gdy tekstura jest zapisana liniowo; 0 = wyłączona)")
    p.add_argument("--keep-metal", action="store_true", help="zostaw mapę metaliczności (domyślnie matowy styl)")
    p.add_argument("--no-cleanup", action="store_true", help="pomiń scalanie wierzchołków i usuwanie odłamków")
    p.add_argument("--max-texture", type=int, default=0, help="maks. bok tekstury w px (0 = bez zmian)")
    p.add_argument("--grade-ref", default="", help="obraz referencyjny palety (np. koncept pierwszej postaci)")
    p.add_argument("--grade", type=float, default=0.35, help="siła dopasowania palety 0..1")
    p.add_argument("--ao", type=float, default=0.8, help="siła wypalenia AO w kolor bazowy (0 = wyłączone)")
    p.add_argument("--palette", default="zawias", help="nazwa palety w palette.json")
    p.add_argument("--palette-strength", type=float, default=0.0, help="siła ściągania do palety 0..1 (0 = wyłączone)")
    p.add_argument("--palette-file", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "palette.json"))
    p.add_argument("--glow", action="store_true", help="emisja z jasnych ciepłych/fioletowych miejsc tekstury")
    return p.parse_args(argv)


def import_any(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".ply":
        bpy.ops.wm.ply_import(filepath=path)
    else:
        raise SystemExit("Nieobsługiwany format: " + ext)


def world_bbox(obj):
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def matte(obj):
    """Wyłącza metaliczność i podnosi chropowatość: postacie z generatora bywają zbyt błyszczące."""
    for slot in obj.material_slots:
        m = slot.material
        if not m or not m.use_nodes:
            continue
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                for name, val in (("Metallic", 0.0), ("Roughness", 0.8)):
                    sock = n.inputs[name]
                    for link in list(sock.links):
                        m.node_tree.links.remove(link)
                    sock.default_value = val


def fix_gamma(obj, gamma):
    """Rozjaśnia teksturę koloru bazowego (wartość^(1/gamma)) i pakuje ją z powrotem."""
    import numpy as np
    done = set()
    for slot in obj.material_slots:
        m = slot.material
        if not m or not m.use_nodes:
            continue
        for n in m.node_tree.nodes:
            if n.type != "BSDF_PRINCIPLED":
                continue
            for link in n.inputs["Base Color"].links:
                tex = link.from_node
                if tex.type != "TEX_IMAGE" or not tex.image or tex.image.name in done:
                    continue
                img = tex.image
                px = np.empty(len(img.pixels), dtype=np.float32)
                img.pixels.foreach_get(px)
                px = px.reshape(-1, 4)
                px[:, :3] = np.power(np.clip(px[:, :3], 0, 1), 1.0 / gamma)
                img.pixels.foreach_set(px.ravel())
                img.update()
                img.pack()
                done.add(img.name)
    print("GAMMA_FIX", gamma, sorted(done))


def cleanup(obj):
    """Scala zdublowane wierzchołki, ujednolica normalne i usuwa drobne odłamki siatki."""
    import bmesh
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    mn, mx = world_bbox(obj)
    h = max(mx.z - mn.z, 1e-6)
    v0 = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5 * h)
    merged = v0 - len(bm.verts)
    # wyspy (spójne składowe po krawędziach)
    bm.verts.ensure_lookup_table()
    seen = set()
    islands = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, comp = [v], []
        seen.add(v.index)
        while stack:
            cur = stack.pop()
            comp.append(cur)
            for e in cur.link_edges:
                o = e.other_vert(cur)
                if o.index not in seen:
                    seen.add(o.index)
                    stack.append(o)
        islands.append(comp)
    total = len(bm.verts)
    kill = []
    for comp in islands:
        if len(comp) >= 0.002 * total:
            continue
        xs = [c.co.x for c in comp]; ys = [c.co.y for c in comp]; zs = [c.co.z for c in comp]
        diag = Vector((max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))).length
        if diag < 0.03 * h:
            kill.extend(comp)
    if kill and len(kill) < total:
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.update()
    print("CLEANED merged %d verts, islands %d, removed %d verts" % (merged, len(islands), len(kill)))


def base_color_images(obj):
    """Obrazy podpięte do Base Color (unikalne)."""
    out = {}
    for slot in obj.material_slots:
        m = slot.material
        if not m or not m.use_nodes:
            continue
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                for link in n.inputs["Base Color"].links:
                    if link.from_node.type == "TEX_IMAGE" and link.from_node.image:
                        out[link.from_node.image.name] = (link.from_node.image, m, n)
    return list(out.values())


def limit_textures(max_px):
    done = []
    for img in bpy.data.images:
        w, h = img.size
        if w == 0 or max(w, h) <= max_px:
            continue
        s = max_px / max(w, h)
        img.scale(max(1, round(w * s)), max(1, round(h * s)))
        img.pack()
        done.append("%s %dx%d->%dx%d" % (img.name, w, h, img.size[0], img.size[1]))
    print("TEX_LIMIT", max_px, done)


def _pixels(img):
    import numpy as np
    px = np.empty(len(img.pixels), dtype=np.float32)
    img.pixels.foreach_get(px)
    return px.reshape(-1, 4)


def _srgb_to_lab(rgb):
    import numpy as np
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]], dtype=np.float32)
    xyz = lin @ m.T / np.array([0.95047, 1.0, 1.08883], dtype=np.float32)
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[:, 1] - 16, 500 * (f[:, 0] - f[:, 1]), 200 * (f[:, 1] - f[:, 2])], axis=1)


def _lab_to_srgb(lab):
    import numpy as np
    fy = (lab[:, 0] + 16) / 116
    f = np.stack([fy + lab[:, 1] / 500, fy, fy - lab[:, 2] / 200], axis=1)
    xyz = np.where(f ** 3 > 0.008856, f ** 3, (f - 16 / 116) / 7.787) * np.array([0.95047, 1.0, 1.08883], dtype=np.float32)
    m = np.array([[3.2406, -1.5372, -0.4986], [-0.9689, 1.8758, 0.0415], [0.0557, -0.2040, 1.0570]], dtype=np.float32)
    lin = np.clip(xyz @ m.T, 0, 1)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)


def grade_palette(obj, ref_path, strength):
    """Przesuwa statystyki koloru tekstury (Lab: średnia, odchylenie) w stronę obrazu referencyjnego."""
    import numpy as np
    ref = bpy.data.images.load(ref_path)
    rp = _pixels(ref)[:, :3]
    bg = rp[0]  # róg obrazu = jednolite tło konceptu
    rp = rp[np.abs(rp - bg).max(axis=1) > 0.08]
    if len(rp) < 1000:
        print("GRADE pominięto: za mało pikseli postaci w referencji")
        return
    rl = _srgb_to_lab(rp)
    rmu, rsd = rl.mean(0), rl.std(0) + 1e-3
    for img, _m, _n in base_color_images(obj):
        px = _pixels(img)
        lab = _srgb_to_lab(np.clip(px[:, :3], 0, 1))
        mu, sd = lab.mean(0), lab.std(0) + 1e-3
        moved = (lab - mu) / sd * rsd + rmu
        moved[:, 0] = lab[:, 0] + (moved[:, 0] - lab[:, 0]) * 0.5  # jasność ruszamy ostrożniej
        out = lab + (moved - lab) * strength
        px[:, :3] = _lab_to_srgb(out)
        img.pixels.foreach_set(px.ravel())
        img.update()
        img.pack()
        print("GRADE %s strength %.2f dL %.1f da %.1f db %.1f" % (img.name, strength, *(rmu - mu)))
    bpy.data.images.remove(ref)


def add_glow(obj, strength=2.0):
    """Emisja z jasnych, nasyconych, ciepłych albo fioletowych pikseli koloru bazowego."""
    import numpy as np
    for img, m, bsdf in base_color_images(obj):
        px = _pixels(img)
        rgb = np.clip(px[:, :3], 0, 1)
        mx, mn = rgb.max(1), rgb.min(1)
        sat = (mx - mn) / (mx + 1e-6)
        r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
        warm = (r >= g) & (g >= b * 0.9) & (r > 0.7)
        violet = (b > g * 1.2) & (r > g * 1.1) & (mx > 0.55)
        mask = ((mx > 0.72) & (sat > 0.5) & (warm | violet)).astype(np.float32)
        share = float(mask.mean())
        if share < 1e-4:
            print("GLOW brak świecących miejsc w", img.name)
            continue
        glow = bpy.data.images.new(img.name + "_glow", img.size[0], img.size[1])
        gp = np.zeros_like(px)
        gp[:, :3] = rgb * mask[:, None]
        gp[:, 3] = 1.0
        glow.pixels.foreach_set(gp.ravel())
        glow.pack()
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = glow
        uv_src = None
        for link in bsdf.inputs["Base Color"].links:
            vec = link.from_node.inputs.get("Vector")
            if vec and vec.links:
                uv_src = vec.links[0].from_socket
        if uv_src:
            m.node_tree.links.new(uv_src, tex.inputs["Vector"])
        sock = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
        m.node_tree.links.new(tex.outputs["Color"], sock)
        bsdf.inputs["Emission Strength"].default_value = strength
        print("GLOW %s %.2f%% pikseli" % (img.name, share * 100))


def gltf_occlusion(path):
    """Czy plik glTF/GLB ma occlusionTexture (AO z generatora)."""
    import json
    import struct
    try:
        if path.lower().endswith(".glb"):
            with open(path, "rb") as f:
                head = f.read(20)
                n = struct.unpack("<I", head[12:16])[0]
                js = json.loads(f.read(n))
        elif path.lower().endswith(".gltf"):
            js = json.load(open(path, encoding="utf-8"))
        else:
            return False
    except Exception:
        return False
    return any("occlusionTexture" in m for m in js.get("materials", []))


def _upstream_image(sock, depth=4):
    """Obraz tekstury, z którego (przez Separate Color itp.) wychodzi połączenie do gniazda."""
    for link in sock.links:
        n = link.from_node
        if n.type == "TEX_IMAGE" and n.image:
            return n.image
        if depth > 0:
            for inp in n.inputs:
                img = _upstream_image(inp, depth - 1)
                if img:
                    return img
    return None


def bake_ao(obj, strength):
    """Mnoży kolor bazowy przez AO (kanał R tekstury ORM z glTF). Musi być przed matte(), które odpina ORM."""
    import numpy as np
    for img, m, bsdf in base_color_images(obj):
        ao_img = None
        for n in m.node_tree.nodes:  # importer glTF: grupa „glTF Material Output”/„glTF Settings” z wejściem Occlusion
            if n.type == "GROUP" and "Occlusion" in n.inputs:
                ao_img = _upstream_image(n.inputs["Occlusion"])
        if ao_img is None:  # zapas: obraz podpięty do Roughness/Metallic (ORM)
            ao_img = _upstream_image(bsdf.inputs["Roughness"]) or _upstream_image(bsdf.inputs["Metallic"])
        if ao_img is None or ao_img == img:
            print("AO_SKIP nie znaleziono tekstury AO w", m.name)
            continue
        base = _pixels(img)
        ao = _pixels(ao_img)[:, 0]
        bw, bh = img.size
        aw, ah = ao_img.size
        if (aw, ah) != (bw, bh):  # najbliższy sąsiad
            ys = (np.arange(bh) * ah // bh)[:, None]
            xs = (np.arange(bw) * aw // bw)[None, :]
            ao = ao.reshape(ah, aw)[ys, xs].ravel()
        f = 1.0 - strength * (1.0 - np.clip(ao, 0, 1))
        base[:, :3] *= f[:, None]
        img.pixels.foreach_set(base.ravel())
        img.update()
        img.pack()
        print("AO_BAKED %s strength %.2f mean AO %.2f" % (img.name, strength, float(ao.mean())))


def apply_palette(obj, colors, strength, sigma=18.0):
    """Ściąga kolory tekstury do stałej palety: miękkie przypisanie w Lab (wagi exp(-d²/σ²) po wszystkich barwach),
    odcień i nasycenie przesuwane z pełną siłą, jasność z 30% siły (zachowuje cieniowanie i detal)."""
    import numpy as np
    pal = np.array([[int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5)] for h in colors], dtype=np.float32)
    plab = _srgb_to_lab(pal)
    for img, _m, _n in base_color_images(obj):
        px = _pixels(img)
        lab = _srgb_to_lab(np.clip(px[:, :3], 0, 1))
        out = np.empty_like(lab)
        step = 262144
        for i in range(0, len(lab), step):
            c = lab[i:i + step]
            d2 = ((c[:, None, :] - plab[None, :, :]) * np.array([0.5, 1.0, 1.0], dtype=np.float32)) ** 2
            w = np.exp(-(d2.sum(2) - d2.sum(2).min(1, keepdims=True)) / (sigma * sigma))
            w /= w.sum(1, keepdims=True)
            target = w @ plab
            moved = c + (target - c) * np.array([0.3, 1.0, 1.0], dtype=np.float32) * strength
            out[i:i + step] = moved
        px[:, :3] = _lab_to_srgb(out)
        img.pixels.foreach_set(px.ravel())
        img.update()
        img.pack()
        print("PALETTE %s %d barw, strength %.2f" % (img.name, len(colors), strength))


def render_preview(obj, path):
    """Podgląd: widok z przodu i z 3/4 obok siebie (Workbench, szybki)."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x, sc.render.resolution_y = 1024, 1024
    sc.view_settings.view_transform = "Standard"
    mn, mx = world_bbox(obj)
    h = mx.z - mn.z
    for i, ang in enumerate((0, 35)):
        cam_data = bpy.data.cameras.new("cam%d" % i)
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = h * 1.15
        cam = bpy.data.objects.new("cam%d" % i, cam_data)
        bpy.context.collection.objects.link(cam)
        r = math.radians(ang)
        cam.location = (6 * math.sin(r), -6 * math.cos(r), h / 2)
        cam.rotation_euler = (math.radians(90), 0, r)
        sc.camera = cam
        root, ext = os.path.splitext(path)
        sc.render.filepath = "%s_%d%s" % (root, i, ext or ".png")
        bpy.ops.render.render(write_still=True)


def main():
    a = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    import_any(a.input)

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit("Brak siatek w pliku")
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    for o in list(bpy.context.scene.objects):
        if o != obj:
            bpy.data.objects.remove(o, do_unlink=True)

    obj.rotation_mode = "XYZ"  # importer glTF ustawia kwaterniony
    obj.rotation_euler[2] += math.radians(a.rotate_z)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    mn, mx = world_bbox(obj)
    h = mx.z - mn.z
    if h <= 1e-6:
        raise SystemExit("Model ma zerową wysokość")
    s = a.height / h
    obj.scale = (s, s, s)
    bpy.ops.object.transform_apply(scale=True)
    mn, mx = world_bbox(obj)
    obj.location = Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
    bpy.ops.object.transform_apply(location=True)

    if not a.no_cleanup:
        cleanup(obj)
    before = tri_count(obj)
    if a.tris > 0 and before > a.tris:
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = a.tris / before
        bpy.ops.object.modifier_apply(modifier=mod.name)
    after = tri_count(obj)
    obj.name = "Character"
    if a.ao > 0:
        if gltf_occlusion(a.input):
            bake_ao(obj, a.ao)
        else:
            print("AO_SKIP model bez occlusionTexture (TRELLIS.2: --preset final/hero liczy AO)")
    if not a.keep_metal:
        matte(obj)
    if a.gamma_fix > 0:
        fix_gamma(obj, a.gamma_fix)
    if a.max_texture > 0:
        limit_textures(a.max_texture)
    if a.palette_strength > 0:
        import json
        pals = json.load(open(a.palette_file, encoding="utf-8"))
        apply_palette(obj, list(pals[a.palette].values()), a.palette_strength)
    if a.grade_ref:
        grade_palette(obj, a.grade_ref, a.grade)
    if a.glow:
        add_glow(obj)

    os.makedirs(os.path.dirname(os.path.abspath(a.output)), exist_ok=True)
    if a.output.lower().endswith(".glb"):
        bpy.ops.export_scene.gltf(filepath=a.output, export_format="GLB", use_selection=False, export_yup=True)
    else:
        bpy.ops.export_scene.fbx(
            filepath=a.output, path_mode="COPY", embed_textures=True,
            apply_unit_scale=True, axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE",
        )
    if a.preview:
        render_preview(obj, a.preview)
    mn, mx = world_bbox(obj)
    print("PREP_OK tris %d -> %d, size %.2f x %.2f x %.2f m -> %s" % (
        before, after, mx.x - mn.x, mx.y - mn.y, mx.z - mn.z, a.output))


main()
