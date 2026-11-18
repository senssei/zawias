#!/usr/bin/env python3
"""Malowany obszar dla całej mapy: makieta z gry -> malunek FLUX.2 -> usunięcie rekwizytów -> głębia -> assets/.

Użycie (Python z venv ComfyUI):
  paint_map.py <map_id> [--tiles 3x3] [--scale 1.5] [--seed N] [--only 2,5] [--from shots|paint|stitch|depth]
               [--theme "opis klimatu"]

Kroki (wyniki w tools/pipeline/work/paint_<map_id>/):
  shots  Godot (--paintshots): blockout.png (z rekwizytami), blockout_arch.png, blockout_depth.png, projector.json
  paint  kafelki w skali kadru gry (cała mapa naraz rozjeżdża układ budynków): FLUX.2 klein przemalowuje makietę
         z rekwizytami (lepiej trzyma kompozycję), potem usuwa stragany, latarnie, skrzynie i łuki (zostają w 3D)
  stitch sklejenie szwami najmniejszej różnicy (image quilting) -> painted.png (scale x rozdzielczość projektora)
  depth  Depth Anything V2 + kalibracja do makiety (paint_depth.py), kopia do assets/backgrounds/<map_id>_*

Każdy kafelek jest oceniany (udział pustki na platformie z makiety); powyżej --void-thr malowany ponownie
(do --retries prób, zostaje najlepsza). --fix --from paint: przemaluj tylko kafelki, które nie przechodzą progu.
Ręcznie: --only 4 --seed 77 --from paint (tylko kafelek 4, potem sklejenie całości od nowa).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "comfy"))
from comfy_concept import build, run  # noqa: E402
from comfy_gen import req, upload  # noqa: E402

STEPS = ["shots", "paint", "stitch", "depth", "check"]

DEFAULT_THEME = ("a rusty market district on a floating platform in a planar ring-city: ornate art nouveau shops and "
                 "houses with rust-red and verdigris metal roofs, brass ornaments, warm glowing windows and doors, "
                 "weathered stone walls along the platform edge, grey cobblestones with a few dry orange-brown rust "
                 "stains (no red liquid, no puddles), dark violet planar void with faint purple mist around the platform")

PAINT_PROMPT = ("Repaint image 1 as a finished hand-painted isometric fantasy RPG background in the style of classic "
                "painted 1990s isometric RPGs: {theme}. Every large block in image 1 is a building, every low border "
                "block is a wall, small objects are market stalls, lamps, crates and an arch. Keep the exact same "
                "camera angle, composition, layout, building footprints and roughly the same building heights as "
                "image 1. Areas that are plain flat dark background in image 1 must stay empty dark violet void: do not add any "
                "buildings, platforms, bridges or ground there. Painterly texture, soft warm light, high detail, no text, no people.")

EDIT_PROMPT = ("Edit image 1: remove only the small wooden market stalls, the lamp posts and street lamps, the loose "
               "wooden crates, barrels, chests, banners, carts, the free-standing stone arch in the square and any free-standing door frames "
               "standing on the open cobblestone street, and fill those spots with matching cobblestones. Keep every "
               "house and building exactly as it is, with the same shape, size, roof and position, and keep the walls, "
               "the platform edges, the violet void background, the camera angle, framing and painting style exactly "
               "the same. Any red puddles become a few small dry orange-brown rust stains on grey cobblestones.")


def comfy_image(server, prompt, refs, w, h, seed, out, steps=4):
    t0 = time.time()
    names = [upload(server, r) for r in refs]
    # referencja w rozdzielczości wyniku: inaczej FLUX nie trzyma kompozycji 1:1
    outputs = run(server, build(prompt, names, w, h, steps, seed, ref_mp=w * h / 1e6))
    img = next(it for o in outputs.values() for it in o.get("images", []))
    import urllib.parse
    q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""), "type": img.get("type", "output")})
    with open(out, "wb") as f:
        f.write(req(server, "/view?" + q))
    print(f"  {os.path.basename(out)} (seed {seed}, {time.time() - t0:.0f} s)", flush=True)


def contact_sheet(paths, out, cols=2, w=960):
    ims = [Image.open(p).convert("RGB") for p in paths]
    h = int(w * ims[0].height / ims[0].width)
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * w, rows * h), (20, 15, 25))
    from PIL import ImageDraw
    for i, im in enumerate(ims):
        im = im.resize((w, h), Image.LANCZOS)
        ImageDraw.Draw(im).text((12, 8), str(i + 1), fill=(255, 220, 120))
        sheet.paste(im, ((i % cols) * w, (i // cols) * h))
    sheet.save(out)


def free_vram(server):
    """Zwalnia modele w ComfyUI (po dużych przebiegach FLUX zaczyna przerzucać wagi i zwalnia 50x)."""
    try:
        req(server, "/free", json.dumps({"unload_models": True, "free_memory": True}).encode(),
            {"Content-Type": "application/json"})
    except Exception as ex:  # noqa: BLE001
        print("  (nie udało się zwolnić VRAM:", ex, ")")


def tile_boxes(W, H, cols, rows, tw, th):
    """Pozycje kafelków (x0, y0) w pikselach projektora, równomiernie z zakładką."""
    xs = [round(i * (W - tw) / max(cols - 1, 1)) for i in range(cols)]
    ys = [round(j * (H - th) / max(rows - 1, 1)) for j in range(rows)]
    return [(x, y) for y in ys for x in xs]


def min_seam(err, axis):
    """Ścieżka najmniejszego błędu przez pasek zakładki (image quilting).
    axis=1: szew pionowy (dla każdego wiersza kolumna cięcia), axis=0: poziomy (dla każdej kolumny wiersz)."""
    import numpy as np
    e = err if axis == 1 else err.T
    h, w = e.shape
    cost = e.copy()
    back = np.zeros((h, w), np.int64)
    for y in range(1, h):
        prev = cost[y - 1]
        left = np.r_[np.inf, prev[:-1]]
        right = np.r_[prev[1:], np.inf]
        stack = np.stack([left, prev, right])
        k = np.argmin(stack, 0)
        cost[y] += stack[k, np.arange(w)]
        back[y] = np.arange(w) + k - 1
    path = np.zeros(h, np.int64)
    path[-1] = int(np.argmin(cost[-1]))
    for y in range(h - 1, 0, -1):
        path[y - 1] = back[y, path[y]]
    return path


def stitch(tiles, canvas_wh, feather=6):
    """Skleja kafelki (lista (obraz np.float32 HxWx3, x0, y0)) szwami najmniejszej różnicy z lekkim wtopieniem."""
    import numpy as np
    from PIL import ImageFilter
    Wc, Hc = canvas_wh
    canvas = np.zeros((Hc, Wc, 3), np.float32)
    filled = np.zeros((Hc, Wc), bool)
    for img, x0, y0 in tiles:
        th, tw = img.shape[:2]
        reg = canvas[y0:y0 + th, x0:x0 + tw]
        old = filled[y0:y0 + th, x0:x0 + tw]
        take = np.ones((th, tw), bool)
        if old.any():
            err = ((reg - img) ** 2).sum(-1)
            cols_old = np.where(old.all(0))[0]
            rows_old = np.where(old.all(1))[0]
            # zakładka z lewej: kolumny od 0 do końca ciągłego zakresu „stare”
            if len(cols_old) and cols_old[0] == 0:
                ov = int(cols_old[np.where(np.diff(cols_old) > 1)[0][0]] + 1) if np.any(np.diff(cols_old) > 1) else int(cols_old[-1] + 1)
                if ov < tw:
                    path = min_seam(err[:, :ov], 1)
                    take &= np.arange(tw)[None, :] > path[:, None]
            if len(rows_old) and rows_old[0] == 0:
                ov = int(rows_old[np.where(np.diff(rows_old) > 1)[0][0]] + 1) if np.any(np.diff(rows_old) > 1) else int(rows_old[-1] + 1)
                if ov < th:
                    path = min_seam(err[:ov, :], 0)
                    take &= np.arange(th)[:, None] > path[None, :]
        m = Image.fromarray((take * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(feather))
        m = np.asarray(m, np.float32)[..., None] / 255.0
        m = np.where(old[..., None], m, 1.0)
        canvas[y0:y0 + th, x0:x0 + tw] = reg * (1 - m) + img * m
        filled[y0:y0 + th, x0:x0 + tw] = True
    return canvas


def void_score(tile_png, geo_crop, size=(1600, 896), erode=31):
    """Udział „pustki” (fioletowe, nasycone piksele) w obszarze, który w makiecie jest platformą.
    Łapie plamy pustki na bruku i miejsca, gdzie FLUX zwęził/przesunął platformę. None = kafelek bez platformy."""
    import numpy as np
    from PIL import ImageFilter
    g = Image.fromarray((geo_crop * 255).astype(np.uint8)).resize(size).filter(ImageFilter.MinFilter(erode))
    g = np.asarray(g) > 127
    if g.mean() < 0.02:
        return None
    hsv = np.asarray(Image.open(tile_png).convert("RGB").resize(size).convert("HSV")).astype(np.float32)
    h, sat = hsv[..., 0] * 360 / 255, hsv[..., 1] / 255
    vl = (h > 255) & (h < 315) & (sat > 0.30)
    return float((vl & g).sum() / g.sum())


def projector_px(proj, pts):
    """Punkty świata (N,3) -> piksele zrzutu projektora (jak Camera3D ortogonalna w Godocie, Euler YXZ)."""
    import numpy as np
    p, y = np.radians(proj["pitch"]), np.radians(proj["yaw"])
    ry = np.array([[np.cos(y), 0, np.sin(y)], [0, 1, 0], [-np.sin(y), 0, np.cos(y)]])
    rx = np.array([[1, 0, 0], [0, np.cos(p), -np.sin(p)], [0, np.sin(p), np.cos(p)]])
    b = ry @ rx                                   # kolumny: osie x, y, z kamery
    origin = np.array(proj["center"]) + b[:, 2] * proj["dist"]
    v = np.asarray(pts, float) - origin
    xc, yc = v @ b[:, 0], v @ b[:, 1]
    W, H, size = proj["width"], proj["height"], proj["size"]
    half_h, half_w = size / 2, size * W / H / 2
    return np.stack([(xc / half_w + 1) / 2 * W, (1 - yc / half_h) / 2 * H], 1)


def cell_check(work, map_json, boxes=None, tw=0, th=0, tol=0.35):
    """Zgodność malunku z kolizjami tak, jak widzi ją gracz: na polu chodzonym stawiamy „postać” (próbki na
    wysokości 0,4/0,9/1,4 m) i sprawdzamy, czy głębia malunku ją zasłania, choć makieta nie (postać wchodzi
    w namalowany dom). Zasłanianie za prawdziwym budynkiem jest w porządku (pokazuje je sylwetka).
    Zwraca (lista_błędów, {nr_kafelka: liczba}) i zapisuje podgląd cells_check.png."""
    import numpy as np
    from PIL import ImageDraw
    proj = json.load(open(os.path.join(work, "projector.json")))

    def dec(path):
        a = np.asarray(Image.open(path).convert("RGB")).astype(np.float64)
        return 10.0 + 80.0 * (a[..., 0] * 256 + a[..., 1]) / 65535.0
    tp = dec(os.path.join(work, "depth.png"))
    tb = dec(os.path.join(work, "blockout_depth.png"))
    H, W = tb.shape
    p_, y_ = np.radians(proj["pitch"]), np.radians(proj["yaw"])
    ry = np.array([[np.cos(y_), 0, np.sin(y_)], [0, 1, 0], [-np.sin(y_), 0, np.cos(y_)]])
    rx = np.array([[1, 0, 0], [0, np.cos(p_), -np.sin(p_)], [0, np.sin(p_), np.cos(p_)]])
    b = ry @ rx
    origin = np.array(proj["center"]) + b[:, 2] * proj["dist"]
    offs = [(0, 0), (0.2, 0), (-0.2, 0), (0, 0.2), (0, -0.2)]
    bad, per_tile, hidden = [], {}, {}
    for z, row in enumerate(map_json["rows"]):
        for x, ch in enumerate(row):
            if map_json["legend"].get(ch, {}).get("solid"):
                continue
            pts = np.array([(x + 0.5 + dx, hy, z + 0.5 + dz) for hy in (0.4, 0.9, 1.4) for dx, dz in offs])
            px = projector_px(proj, pts)
            iu, iv = px[:, 0].astype(int), px[:, 1].astype(int)
            ok = (iu >= 0) & (iu < W) & (iv >= 0) & (iv < H)
            if ok.sum() < 5:
                continue
            t = (pts[ok] - origin) @ -b[:, 2]
            fp = np.mean(tp[iv[ok], iu[ok]] < t - tol)
            fb = np.mean(tb[iv[ok], iu[ok]] < t - tol)
            hidden[(x, z)] = max(fp, fb)
            if fp > 0.25 and fb < 0.1:
                u, v = projector_px(proj, [(x + 0.5, 0.9, z + 0.5)])[0]
                bad.append({"cell": [x, z], "kind": "zasłania" if fp > 0.5 else "częściowo", "hidden": round(float(fp), 2),
                            "px": [int(u), int(v)]})
                if boxes:
                    for i, (x0, y0) in enumerate(boxes, 1):
                        if x0 + 40 <= u < x0 + tw - 40 and y0 + 40 <= v < y0 + th - 40:
                            per_tile[i] = per_tile.get(i, 0) + 1
    prev = Image.open(os.path.join(work, "painted.png")).convert("RGB").resize((W, H))
    d = ImageDraw.Draw(prev)
    for e in bad:
        u, v = e["px"]
        col = (255, 40, 40) if e["kind"] == "zasłania" else (255, 170, 40)
        d.ellipse((u - 9, v - 9, u + 9, v + 9), outline=col, width=4)
    prev.resize((1920, round(1920 * H / W))).save(os.path.join(work, "cells_check.png"))
    json.dump({"bad": bad, "per_tile": per_tile, "blocked": suggest_blocks(map_json, bad),
               "hidden_spots": hidden_spots(map_json, hidden)},
              open(os.path.join(work, "cells_check.json"), "w"), indent=1, ensure_ascii=False)
    return bad, per_tile


def _key_cells(m):
    """Pola, których nie wolno zablokować: postacie, obiekty, start, wyzwalacze, zamki, drzwi, dekoracje, wrogowie."""
    keys = {tuple(m["player_start"])}
    for n in m.get("npcs", []) + m.get("objects", []):
        keys.add(tuple(n["pos"]))
    for t in m.get("triggers", []):
        keys |= {tuple(c) for c in t["cells"]}
    for lk in m.get("locks", []):
        keys.add(tuple(lk["cell"]))
    for d in m.get("decor", []):
        keys.add(tuple(d["pos"]))
    enc = json.load(open(os.path.join(ROOT, "data", "encounters.json")))
    for e in enc.values():
        keys |= {tuple(s["pos"]) for s in e.get("spawn", [])}
    for z, row in enumerate(m["rows"]):
        for x, ch in enumerate(row):
            if m["legend"].get(ch, {}).get("door"):
                keys.add((x, z))
    return keys


def suggest_blocks(m, bad):
    """Tryb „mapa podąża za malunkiem”: pola, na których malunek wyraźnie zasłania postać (namalowany dom),
    stają się nieprzechodnie w trybie malowanym. Pomija pola kluczowe i takie, których zablokowanie odcięłoby
    jakąkolwiek część mapy albo dostęp do postaci/obiektu (BFS od startu, 8 kierunków)."""
    H, W = len(m["rows"]), len(m["rows"][0])
    walk = {(x, z) for z, row in enumerate(m["rows"]) for x, ch in enumerate(row)
            if not m["legend"].get(ch, {}).get("solid")}
    walk -= {tuple(d["pos"]) for d in m.get("decor", [])}
    keys = _key_cells(m)
    start = tuple(m["player_start"])

    def reach(cells):
        seen, todo = {start}, [start]
        while todo:
            x, z = todo.pop()
            for dx in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    n = (x + dx, z + dz)
                    if n in cells and n not in seen:
                        seen.add(n)
                        todo.append(n)
        return seen
    base = reach(walk)
    blocked = []
    for e in sorted(bad, key=lambda e: -e["hidden"]):
        c = tuple(e["cell"])
        if e["kind"] != "zasłania" or c in keys or c not in walk:
            continue
        trial = walk - {c}
        if reach(trial) == (base & trial):
            walk, base = trial, base - {c}
            blocked.append(list(c))
    return blocked


def hidden_spots(m, hidden):
    """Postacie i obiekty stojące tam, gdzie w trybie malowanym zasłania je budynek (widać tylko sylwetkę)."""
    out = []
    for n in m.get("npcs", []) + m.get("objects", []):
        h = hidden.get(tuple(n["pos"]), 0.0)
        if h > 0.5:
            out.append({"id": n["id"], "pos": n["pos"], "hidden": round(float(h), 2)})
    return out


def mask_void(img, depth_png, void_png, s, roof_px=150, feather=8):
    """Poza platformą (makieta + pas na dachy ponad nią) wstawia malowaną pustkę: FLUX lubi dorabiać tam zabudowę."""
    import numpy as np
    from PIL import ImageFilter
    geo = np.asarray(Image.open(depth_png).convert("RGB"))[..., 2] > 127
    h, w = geo.shape
    allowed = geo.copy()
    has = geo.any(0)
    ytop = np.where(has, geo.argmax(0), h)
    rows = np.arange(h)[:, None]
    allowed |= has[None, :] & (rows >= ytop[None, :] - roof_px) & (rows < ytop[None, :])
    H, Wd = img.shape[:2]
    m = Image.fromarray((allowed * 255).astype(np.uint8)).resize((Wd, H), Image.BILINEAR).filter(ImageFilter.GaussianBlur(feather * s))
    m = np.asarray(m, np.float32)[..., None] / 255.0
    void = np.asarray(Image.open(void_png).convert("RGB").resize((Wd, H), Image.LANCZOS), np.float32) * 0.8
    return img * m + void * (1 - m)


def tiled_depth(a, W, boxes, tw, th, src):
    """Głębia kafelkami w skali malowania: na obrazie całej mapy Depth Anything widzi głównie globalny spadek
    perspektywy i zaniża wysokość domów. Każdy kafelek kalibrowany osobno (podłoga z makiety jest dokładna),
    potem łączenie z miękkim wtapianiem na zakładkach -> depth.png."""
    import numpy as np
    py = sys.executable
    blk_depth = Image.open(W("blockout_depth.png"))
    PW, PH = blk_depth.size
    paint = Image.open(src).convert("RGB")
    s = paint.width / PW
    acc_t = np.zeros((PH, PW))
    acc_w = np.zeros((PH, PW))
    for i, (x0, y0) in enumerate(boxes, 1):
        bcrop = blk_depth.crop((x0, y0, x0 + tw, y0 + th))
        geo = np.asarray(bcrop.convert("RGB"))[..., 2] > 127
        if geo.mean() < 0.02:
            continue
        bcrop.save(W(f"tile{i}_blkdepth.png"))
        paint.crop((round(x0 * s), round(y0 * s), round((x0 + tw) * s), round((y0 + th) * s))).save(W(f"tile{i}_painted.png"))
        subprocess.run([py, os.path.join(HERE, "comfy", "comfy_depth.py"), W(f"tile{i}_painted.png"), W(f"tile{i}_da.png"),
                        "--resolution", "1024", "--server", a.server], check=True, capture_output=True)
        r = subprocess.run([py, "-I", os.path.join(HERE, "paint_depth.py"), W(f"tile{i}_da.png"), W(f"tile{i}_blkdepth.png"),
                            W(f"tile{i}_depth.png")], capture_output=True, text=True)
        if r.returncode != 0:
            print(f"  kafelek {i}: kalibracja nieudana ({r.stderr.strip()[-200:]})")
            continue
        info = next((l for l in r.stdout.splitlines() if l.startswith("floor")), "")
        print(f"  głębia kafelka {i}: {info}", flush=True)
        a_ = np.asarray(Image.open(W(f"tile{i}_depth.png")).convert("RGB")).astype(np.float64)
        t = 10.0 + 80.0 * (a_[..., 0] * 256 + a_[..., 1]) / 65535.0
        scene = a_[..., 2] > 127
        yy, xx = np.mgrid[0:th, 0:tw]
        edge = np.minimum(np.minimum(xx, tw - 1 - xx), np.minimum(yy, th - 1 - yy))
        ok = np.isfinite(t)
        t = np.where(ok, t, 90.0)
        wgt = np.clip(edge / 60.0, 0.02, 1.0) * scene * ok
        acc_t[y0:y0 + th, x0:x0 + tw] += t * wgt
        acc_w[y0:y0 + th, x0:x0 + tw] += wgt
    scene = acc_w > 0.01
    t = np.where(scene, acc_t / np.maximum(acc_w, 1e-9), 90.0)
    q = np.clip(np.round((t - 10.0) / 80.0 * 65535.0), 0, 65535).astype(np.int64)
    out = np.zeros((PH, PW, 3), np.uint8)
    out[..., 0], out[..., 1], out[..., 2] = q // 256, q % 256, np.where(scene, 255, 0)
    Image.fromarray(out).save(W("depth.png"))


def write_blocks(W, dst, map_id):
    """Dopisuje do <map>_paint.json pola blokowane w trybie malowanym i wypisuje raport."""
    cc = json.load(open(W("cells_check.json")))
    pj = os.path.join(dst, f"{map_id}_paint.json")
    p = json.load(open(pj))
    p["blocked"] = cc["blocked"]
    json.dump(p, open(pj, "w"), indent=1)
    print(f"  pola zablokowane w trybie malowanym ({len(cc['blocked'])}): {cc['blocked']}")
    for h in cc["hidden_spots"]:
        print(f"  UWAGA: {h['id']} na {h['pos']} stoi za budynkiem (zasłonięty w {h['hidden']:.0%}), rozważ przestawienie")


def main():
    import numpy as np
    ap = argparse.ArgumentParser()
    ap.add_argument("map_id")
    ap.add_argument("--tiles", default="3x3", help="kolumny x wiersze")
    ap.add_argument("--scale", type=float, default=1.5, help="rozdzielczość malunku względem zrzutu projektora")
    ap.add_argument("--seed", type=int, default=31)
    ap.add_argument("--retries", type=int, default=3, help="próby na kafelek, gdy na platformie jest za dużo pustki")
    ap.add_argument("--void-thr", type=float, default=0.05, help="próg udziału pustki na platformie")
    ap.add_argument("--cells-thr", type=int, default=2, help="--fix: maluj ponownie kafelki z większą liczbą pól niezgodnych z kolizjami")
    ap.add_argument("--fix", action="store_true", help="przemaluj tylko kafelki powyżej progu (reszta zostaje)")
    ap.add_argument("--only", default="", help="tylko te kafelki (np. 2,5), reszta z poprzedniego przebiegu")
    ap.add_argument("--from", dest="start", choices=STEPS, default="shots")
    ap.add_argument("--theme", default="")
    ap.add_argument("--godot", default=shutil.which("godot") or os.path.expanduser("~/.local/bin/godot"))
    ap.add_argument("--server", default=os.environ.get("COMFY_URL", "http://127.0.0.1:8188"))
    a = ap.parse_args()

    work = os.path.join(HERE, "work", f"paint_{a.map_id}")
    os.makedirs(work, exist_ok=True)
    W = lambda n: os.path.join(work, n)  # noqa: E731
    todo = STEPS[STEPS.index(a.start):]
    map_json = json.load(open(os.path.join(ROOT, "data", "maps", f"{a.map_id}.json")))
    theme = a.theme or map_json.get("paint_theme", DEFAULT_THEME)

    if "shots" in todo:
        print("[1/4] zrzuty makiety z projektora (Godot)", flush=True)
        r = subprocess.run([a.godot, "--path", ROOT, "--rendering-driver", "opengl3", "--",
                            "--quickstart", f"--map={a.map_id}", f"--paintshots={work}"],
                           capture_output=True, text=True, timeout=300)
        if "PAINT_SHOTS_OK" not in r.stdout:
            sys.exit("Godot nie zrobił zrzutów:\n" + r.stdout[-2000:] + r.stderr[-2000:])

    blk = Image.open(W("blockout.png")).convert("RGB")
    PW, PH = blk.size
    cols, rows = (int(v) for v in a.tiles.split("x"))
    # kafelek ~ skala kadru gry (w niej FLUX trzyma układ budynków); malowany w 1600x896
    tw, th = round(PW / (cols * 0.84)), round(PH / (rows * 0.84))
    boxes = tile_boxes(PW, PH, cols, rows, tw, th)
    only = {int(v) for v in a.only.split(",") if v}

    if "paint" in todo:
        free_vram(a.server)
        print(f"[2/4] {len(boxes)} kafelków {tw}x{th} px projektora -> 1600x896 (malunek + usunięcie rekwizytów)", flush=True)
        geo = np.asarray(Image.open(W("blockout_depth.png")).convert("RGB"))[..., 2] > 127
        prev_cells = json.load(open(W("cells_check.json"))).get("per_tile", {}) if os.path.exists(W("cells_check.json")) else {}
        report = []
        for i, (x0, y0) in enumerate(boxes, 1):
            if only and i not in only:
                continue
            geo_crop = geo[y0:y0 + th, x0:x0 + tw]
            if a.fix and os.path.exists(W(f"tile{i}_edit.png")):
                sc = void_score(W(f"tile{i}_edit.png"), geo_crop)
                cell_bad = int(prev_cells.get(str(i), 0))
                if cell_bad > a.cells_thr:
                    print(f"  kafelek {i}: {cell_bad} pól niezgodnych z kolizjami -> maluję ponownie", flush=True)
                elif sc is None or sc <= a.void_thr:
                    report.append((i, sc, "ok"))
                    continue
            blk.crop((x0, y0, x0 + tw, y0 + th)).resize((1600, 896), Image.LANCZOS).save(W(f"tile{i}_blockout.png"))
            best = None
            for k in range(a.retries):
                seed = a.seed + i + 1000 * k
                comfy_image(a.server, PAINT_PROMPT.format(theme=theme), [W(f"tile{i}_blockout.png")], 1600, 896,
                            seed, W(f"tile{i}_paint_a{k}.png"))
                comfy_image(a.server, EDIT_PROMPT, [W(f"tile{i}_paint_a{k}.png")], 1600, 896, seed + 100,
                            W(f"tile{i}_edit_a{k}.png"))
                sc = void_score(W(f"tile{i}_edit_a{k}.png"), geo_crop)
                print(f"  kafelek {i} próba {k + 1}: pustka na platformie = {'-' if sc is None else f'{sc:.1%}'}", flush=True)
                if best is None or (sc or 0) < best[1]:
                    best = (k, sc or 0)
                if sc is None or sc <= a.void_thr:
                    break
            shutil.copy(W(f"tile{i}_edit_a{best[0]}.png"), W(f"tile{i}_edit.png"))
            shutil.copy(W(f"tile{i}_paint_a{best[0]}.png"), W(f"tile{i}_paint.png"))
            report.append((i, best[1], f"próba {best[0] + 1}"))
        for i, sc, how in report:
            flag = "" if sc is None or sc <= a.void_thr else "  <- nadal powyżej progu, rozważ --only %d --seed ..." % i
            print(f"  kafelek {i}: {'-' if sc is None else f'{sc:.1%}'} ({how}){flag}")
        contact_sheet([W(f"tile{i}_edit.png") for i in range(1, len(boxes) + 1)], W("candidates_tiles.png"), cols=cols, w=640)

    if "stitch" in todo:
        print("[3/4] sklejanie kafelków", flush=True)
        s = a.scale
        tiles = []
        for i, (x0, y0) in enumerate(boxes, 1):
            im = Image.open(W(f"tile{i}_edit.png")).convert("RGB").resize((round(tw * s), round(th * s)), Image.LANCZOS)
            tiles.append((np.asarray(im, np.float32), round(x0 * s), round(y0 * s)))
        out = stitch(tiles, (round(PW * s), round(PH * s)))
        out = mask_void(out, W("blockout_depth.png"), os.path.join(ROOT, "assets", "backgrounds", "planar_void.png"), s)
        Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(W("painted.png"))
        Image.open(W("painted.png")).resize((1920, round(1920 * PH / PW)), Image.LANCZOS).save(W("painted_preview.png"))

    if "check" in todo and "depth" not in todo:
        bad, per_tile = cell_check(work, map_json, boxes, tw, th)
        print(f"  zgodność z kolizjami: {len(bad)} pól, na których malunek zasłania postać; kafelki: {per_tile}")
        write_blocks(W, os.path.join(ROOT, "assets", "backgrounds"), a.map_id)

    if "depth" in todo:
        src = W("painted.png")
        print("[4/4] głębia z malunku", flush=True)
        free_vram(a.server)
        tiled_depth(a, W, boxes, tw, th, src)
        dst = os.path.join(ROOT, "assets", "backgrounds")
        shutil.copy(src, os.path.join(dst, f"{a.map_id}_paint.png"))
        shutil.copy(W("depth.png"), os.path.join(dst, f"{a.map_id}_depth.png"))
        shutil.copy(W("projector.json"), os.path.join(dst, f"{a.map_id}_paint.json"))
        bad, per_tile = cell_check(work, map_json, boxes, tw, th)
        print(f"  zgodność z kolizjami: {len(bad)} pól, na których malunek zasłania postać"
              f" (podgląd: {W('cells_check.png')}); kafelki: {per_tile}")
        write_blocks(W, dst, a.map_id)
        print(f"PAINT_MAP_OK assets/backgrounds/{a.map_id}_paint.png (+ _depth.png, _paint.json)")


if __name__ == "__main__":
    main()
