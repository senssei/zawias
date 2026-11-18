#!/usr/bin/env python3
"""Porównanie estymatorów głębi dla malowanego obszaru (Python z venv ComfyUI).

Użycie: depth_compare.py <work/paint_<map>> [--methods da2_large,da2_guided,da2_small,depthpro]

Dla każdej metody: mapa „bliskości” (16-bit PNG) -> ta sama kalibracja (paint_depth.py) -> depth_<m>.png
oraz metryki:
  edge_prec  – jaka część krawędzi wypiętrzenia (skok > 0,25 m na piksel) leży do 2 px od krawędzi malunku
  soft_ratio – udział „rozmytych” przejść (0,03–0,25 m/px) wśród wszystkich przejść; mniej = ostrzej
  med_err    – mediana |głębia − makieta| na bryłach makiety (m); malunek bywa wyższy, więc tylko orientacyjnie
oraz arkusz z wycinkami: malunek z konturem wypiętrzenia > 0,5 m (czerwony) dla każdej metody.
"""
import argparse
import os
import subprocess
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
PIPE = os.path.join(HERE, "..", "pipeline")
T0, T1 = 10.0, 90.0


def save16(arr, path):
    a = (arr - arr.min()) / max(arr.max() - arr.min(), 1e-9)
    Image.fromarray((a * 65535).astype(np.uint16)).save(path)


def hf_depth(model_id, img, inverse):
    import torch
    from transformers import AutoImageProcessor, AutoModelForDepthEstimation
    proc = AutoImageProcessor.from_pretrained(model_id)
    model = AutoModelForDepthEstimation.from_pretrained(model_id, torch_dtype=torch.float16).to("cuda").eval()
    inp = proc(images=img, return_tensors="pt").to("cuda")
    inp = {k: (v.half() if v.dtype == torch.float32 else v) for k, v in inp.items()}
    with torch.no_grad():
        out = model(**inp)
    pred = out.predicted_depth.float()
    pred = torch.nn.functional.interpolate(pred[:, None], size=img.size[::-1], mode="bicubic", align_corners=False)[0, 0]
    arr = pred.cpu().numpy()
    del model
    torch.cuda.empty_cache()
    if inverse:   # głębia metryczna (dalej = większa) -> bliskość
        arr = 1.0 / np.maximum(arr, 1e-3)
    return arr


def guided(guide, src, r=6, eps=1e-4):
    """Filtr prowadzony (He i in.): krawędzie mapy głębi dociągnięte do krawędzi malunku."""
    I, p = guide.astype(np.float64), src.astype(np.float64)
    box = lambda x: cv2.boxFilter(x, -1, (2 * r + 1, 2 * r + 1))  # noqa: E731
    mI, mp = box(I), box(p)
    a = (box(I * p) - mI * mp) / (box(I * I) - mI * mI + eps)
    b = mp - a * mI
    return box(a) * I + box(b)


def decode(path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.float64)
    return T0 + (T1 - T0) * (a[..., 0] * 256 + a[..., 1]) / 65535.0, a[..., 2] > 127


def metrics(depth_png, blk_png, paint_small):
    t, m = decode(depth_png)
    tb, mb = decode(blk_png)
    gx = cv2.Sobel(t, cv2.CV_64F, 1, 0, ksize=1)
    gy = cv2.Sobel(t, cv2.CV_64F, 0, 1, ksize=1)
    g = np.hypot(gx, gy) * m
    # ziemia ma stały gradient wzdłuż wiersza (~0,025 m/px), więc od progu to odcinamy
    sharp = g > 0.25
    soft = (g > 0.06) & (g <= 0.25)
    gray = cv2.GaussianBlur(cv2.cvtColor(paint_small, cv2.COLOR_RGB2GRAY).astype(np.float64), (3, 3), 0)
    ig = np.hypot(cv2.Sobel(gray, cv2.CV_64F, 1, 0), cv2.Sobel(gray, cv2.CV_64F, 0, 1))
    iedge = ig > np.percentile(ig, 85)
    iedge = cv2.dilate(iedge.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
    prec = float((sharp & iedge).sum() / max(sharp.sum(), 1))
    soft_ratio = float(soft.sum() / max(soft.sum() + sharp.sum(), 1))
    err = float(np.median(np.abs(t - tb)[mb & m]))
    return {"edge_prec": prec, "soft_ratio": soft_ratio, "med_err": err}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("work")
    ap.add_argument("--methods", default="da2_large,da2_guided,da2_small,depthpro")
    ap.add_argument("--crops", default="0.30,0.30;0.62,0.38;0.70,0.70", help="środki wycinków (x,y względnie)")
    a = ap.parse_args()
    W = lambda n: os.path.join(a.work, n)  # noqa: E731
    out = W("depth_compare")
    os.makedirs(out, exist_ok=True)
    blk = Image.open(W("blockout_depth.png"))
    bw, bh = blk.size
    paint = Image.open(W("painted.png")).convert("RGB")
    paint_small = np.asarray(paint.resize((bw, bh), Image.LANCZOS))
    gray = cv2.cvtColor(paint_small, cv2.COLOR_RGB2GRAY).astype(np.float64) / 255.0
    # wejście do sieci: malunek w ~rozdzielczości projektora (sieci i tak skalują wewnętrznie)
    net_in = paint.resize((bw, bh), Image.LANCZOS)
    results = {}
    for mth in a.methods.split(","):
        near = None
        if mth == "da2_large":
            near = np.asarray(Image.open(W("da.png")).convert("L").resize((bw, bh), Image.BILINEAR)).astype(np.float64)
        elif mth == "da2_guided":
            base = np.asarray(Image.open(W("da.png")).convert("L").resize((bw, bh), Image.BILINEAR)).astype(np.float64) / 255
            near = guided(gray, base)
        elif mth == "da2_large_hf":
            near = hf_depth("depth-anything/Depth-Anything-V2-Large-hf", net_in, inverse=False)
        elif mth == "da2_large_hf_guided":
            base = hf_depth("depth-anything/Depth-Anything-V2-Large-hf", net_in, inverse=False)
            base = (base - base.min()) / max(base.max() - base.min(), 1e-9)
            near = guided(gray, base, r=2, eps=1e-3)
        elif mth.startswith("file="):   # gotowa mapa bliskości, np. z ComfyUI w innej rozdzielczości
            near = np.asarray(Image.open(os.path.join(a.work, mth[5:])).convert("L").resize((bw, bh), Image.BILINEAR)).astype(np.float64)
        elif mth == "da2_small":
            near = hf_depth("depth-anything/Depth-Anything-V2-Small-hf", net_in, inverse=False)
        elif mth == "depthpro":
            near = hf_depth("apple/DepthPro-hf", net_in, inverse=True)
        else:
            print("nieznana metoda", mth)
            continue
        mth = mth.replace("file=", "").replace(".png", "")
        npath = os.path.join(out, f"near_{mth}.png")
        save16(near, npath)
        dpath = os.path.join(out, f"depth_{mth}.png")
        r = subprocess.run([sys.executable, "-I", os.path.join(PIPE, "paint_depth.py"), npath, W("blockout_depth.png"), dpath],
                           capture_output=True, text=True)
        calib = [l for l in r.stdout.splitlines() if l.startswith("floor")]
        results[mth] = metrics(dpath, W("blockout_depth.png"), paint_small)
        print(f"{mth:12s} edge_prec={results[mth]['edge_prec']:.2f} soft_ratio={results[mth]['soft_ratio']:.2f} "
              f"med_err={results[mth]['med_err']:.2f} m  | {calib[0] if calib else r.stderr[-300:]}", flush=True)

    # arkusz: wiersz = metoda, kolumny = wycinki z konturem wypiętrzenia > 0,5 m
    crops = [tuple(float(v) for v in c.split(",")) for c in a.crops.split(";")]
    cw, ch = 420, 300
    sheet = Image.new("RGB", (cw * len(crops) + 150, ch * len(results)), (20, 15, 25))
    draw = ImageDraw.Draw(sheet)
    for row, mth in enumerate(results):
        t, m = decode(os.path.join(out, f"depth_{mth}.png"))
        # kontur skoków głębi (krawędzie przesłaniania)
        gx = cv2.Sobel(t, cv2.CV_64F, 1, 0, ksize=1)
        gy = cv2.Sobel(t, cv2.CV_64F, 0, 1, ksize=1)
        edge = (np.hypot(gx, gy) > 0.25) & m
        vis = paint_small.copy()
        vis[edge] = [255, 40, 40]
        for col, (cx, cy) in enumerate(crops):
            x0 = int(cx * bw - cw / 2)
            y0 = int(cy * bh - ch / 2)
            sheet.paste(Image.fromarray(vis[y0:y0 + ch, x0:x0 + cw]), (150 + col * cw, row * ch))
        rr = results[mth]
        draw.text((8, row * ch + 10), f"{mth}\nkrawędzie\nzgodne {rr['edge_prec']:.0%}\nrozmyte {rr['soft_ratio']:.0%}",
                  fill=(255, 220, 120))
    sheet.save(os.path.join(out, "sheet.png"))
    print("SHEET", os.path.join(out, "sheet.png"))


if __name__ == "__main__":
    main()
