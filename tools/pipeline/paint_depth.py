#!/usr/bin/env python3
"""Kalibracja głębi z malunku (Depth Anything, względna) do metrów na podstawie zrzutu głębi makiety.

Użycie (Python z numpy i PIL, np. ~/ComfyUI/.venv/bin/python):
  paint_depth.py <da.png> <blockout_depth.png> <wyjście_depth.png> [--debug podgląd.png]

blockout_depth.png pochodzi z gry (--depthshot): R/G = odległość wzdłuż osi kamery (16 bit, T0..T1), B = geometria.
Wyjście w tym samym kodowaniu; czyta je shaders/paint_depth.gdshader.
"""
import argparse

import numpy as np
from PIL import Image

T0, T1 = 10.0, 90.0


def decode(path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.float64)
    q = a[..., 0] * 256 + a[..., 1]
    return T0 + (T1 - T0) * q / 65535.0, a[..., 2] > 127


def encode(t, mask):
    q = np.clip(np.round((t - T0) / (T1 - T0) * 65535.0), 0, 65535).astype(np.int64)
    out = np.zeros(t.shape + (3,), np.uint8)
    out[..., 0] = q // 256
    out[..., 1] = q % 256
    out[..., 2] = np.where(mask, 255, 0)
    return out


def load_nearness(path, size):
    """Mapa „bliskości” (jaśniej = bliżej) jako float 0..1: PNG 8-bit (ComfyUI) albo 16-bit (narzędzia porównawcze)."""
    im = Image.open(path)
    if im.mode in ("I;16", "I;16B", "I", "F"):
        arr = np.asarray(im).astype(np.float64)
        lo, hi = arr.min(), arr.max()
        arr = (arr - lo) / max(hi - lo, 1e-9)
        return np.asarray(Image.fromarray(arr.astype(np.float32), "F").resize(size, Image.BILINEAR)).astype(np.float64)
    return np.asarray(im.convert("L").resize(size, Image.BILINEAR)).astype(np.float64) / 255.0


def box_blur(a, r):
    """Rozmycie pudełkowe (oś 0 i 1) przez sumy skumulowane, 3 przebiegi ~ Gauss."""
    for _ in range(3):
        for ax in (0, 1):
            c = np.cumsum(np.pad(a, [(r + 1, r) if i == ax else (0, 0) for i in range(2)], mode="edge"), axis=ax)
            hi = np.take(c, np.arange(2 * r + 1, c.shape[ax]), axis=ax)
            lo = np.take(c, np.arange(0, c.shape[ax] - 2 * r - 1), axis=ax)
            a = (hi - lo) / (2 * r + 1)
    return a


def norm_blur(val, sel, r):
    w_ = box_blur(sel.astype(np.float64), r)
    v = box_blur(np.where(sel, val, 0.0), r)
    out = v / np.maximum(w_, 1e-6)
    # tam, gdzie w pobliżu nie ma podłogi, większy promień
    far = w_ < 0.05
    if far.any():
        w2 = box_blur(sel.astype(np.float64), r * 4)
        v2 = box_blur(np.where(sel, val, 0.0), r * 4)
        out[far] = (v2 / np.maximum(w2, 1e-6))[far]
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("da")
    p.add_argument("blockout")
    p.add_argument("output")
    p.add_argument("--debug")
    a = p.parse_args()
    tb, mb = decode(a.blockout)
    h, w = tb.shape
    d = load_nearness(a.da, (w, h))

    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    ys /= h
    xs /= w

    def plane_fit(val, sel, iters=5, keep=0.15, quad=False):
        """Odporna płaszczyzna (lub powierzchnia 2. stopnia) val(x, y) na pikselach sel."""
        cur = sel.copy()
        terms = [np.ones_like(xs), xs, ys] + ([xs * xs, xs * ys, ys * ys] if quad else [])
        for _ in range(iters):
            A = np.stack([t_[cur] for t_ in terms], 1)
            c, *_ = np.linalg.lstsq(A, val[cur], rcond=None)
            pl = sum(ci * t_ for ci, t_ in zip(c, terms))
            r = np.abs(val - pl)
            cur = sel & (r < max(keep, np.percentile(r[sel], 60)))
        return pl, cur

    # 1) Podłoga makiety: w kamerze ortogonalnej głębia podłogi zależy tylko od wiersza (t = a + b*y).
    #    RANSAC: największy zbiór pikseli na jednej takiej prostej to podłoga.
    rng = np.random.default_rng(0)
    yy, xx = np.nonzero(mb)
    pick = rng.choice(len(yy), min(len(yy), 200000), replace=False)   # próbka do liczenia zgodności
    sy, sx = yy[pick], xx[pick]
    cands = []
    for _ in range(400):
        i, j = rng.integers(0, len(yy), 2)
        if abs(yy[i] - yy[j]) < 50:
            continue
        b = (tb[yy[i], xx[i]] - tb[yy[j], xx[j]]) / (yy[i] - yy[j])
        a_ = tb[yy[i], xx[i]] - b * yy[i]
        n = int((np.abs(tb[sy, sx] - (a_ + b * sy)) < 0.03).sum())
        cands.append((n, a_, b))
    # Duże płaskie dachy też są takimi płaszczyznami; podłoga to najdalsza (największa głębia) z dużych.
    top_n = max(c[0] for c in cands)
    big = [c for c in cands if c[0] >= 0.25 * top_n]
    _, a0, b0 = max(big, key=lambda c: c[1] + c[2] * h / 2)
    best = (a0, b0)
    rows = np.arange(h, dtype=np.float64)[:, None]
    t_ground = np.broadcast_to(best[0] + best[1] * rows, (h, w)).copy()
    floor = mb & (np.abs(tb - t_ground) < 0.03)
    relief_b = np.where(mb, t_ground - tb, 0.0)          # o ile bryła makiety jest bliżej niż podłoga
    floor &= relief_b < 0.1
    # 2) Podłoga w DA: rozmycie znormalizowane po pikselach podłogi (DA nie jest liniowa w ortografii);
    #    piksele, gdzie malunek wystaje ponad podłogę makiety (wyższe dachy), odrzucamy iteracyjnie
    fsel = floor.copy()
    for _ in range(3):
        d_ground = norm_blur(d, fsel, 24)
        fsel = floor & (d - d_ground < 0.015)
    rel = d - d_ground                                    # względne wypiętrzenie z malunku
    # 3) Skala: wypiętrzenie DA -> metry głębi, na bryłach makiety (mediana ilorazów, odporna na różnice kształtu)
    bsel = mb & (relief_b > 0.8) & (rel > 0.02)
    scale = float(np.median(relief_b[bsel] / rel[bsel])) if bsel.sum() > 200 else float("nan")
    if not np.isfinite(scale):
        scale = 20.0   # za mało brył w kadrze: typowa skala z innych kafelków
        print("  (mało brył makiety: domyślna skala wypiętrzenia)")
    relief = np.clip(rel * scale, 0.0, None)
    relief[relief < 0.3] = 0.0                            # szum na bruku -> płasko
    fit = t_ground - relief
    err = np.abs(fit - tb)
    print(f"floor px={floor.mean():.0%} scale={scale:.1f} m/DA  median|err| floor={np.median(err[floor]):.2f} m"
          f" bryły={np.median(err[mb & (relief_b > 0.8)]):.2f} m")
    # Maska sceny: makieta + to, co wystaje ponad platformę (dachy na tle pustki); pustka pod platformą odpada
    scene = mb.copy()
    for x in range(w):
        col = mb[:, x]
        if not col.any():
            continue
        ytop = int(np.argmax(col))
        # dach nad murem musi być w DA co najmniej tak blisko jak krawędź platformy pod nim
        scene[:ytop, x] = (relief[:ytop, x] > 0.5) & (d[:ytop, x] >= d[ytop, x] - 0.02)
    t = np.where(scene, fit, T1)
    Image.fromarray(encode(t, scene)).save(a.output)
    print("DEPTH_CAL_OK", a.output)
    if a.debug:
        lo, hi = np.percentile(t[scene], [1, 99])
        g = (1 - np.clip((t - lo) / (hi - lo), 0, 1)) * 255 * scene
        r = np.clip(np.abs(fit - tb) / 3.0, 0, 1) * 255 * mb
        dbg = np.concatenate([np.stack([g] * 3, -1), np.stack([r, r * 0.3, r * 0], -1)], 1).astype(np.uint8)
        Image.fromarray(dbg).resize((w, h // 2)).save(a.debug)


if __name__ == "__main__":
    main()
