#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Usuwa pomarańczowe łaty rdzy z miedzianych dachów na malunku mapy (bez przemalowania i bez zmiany głębi).

FLUX dostaje w motywie i „rdzawo-śniedziowe dachy”, i „plamy rdzy na bruku”, więc na patynie dachów lądują te same
okrągłe plamy co na ulicy i wyglądają jak naklejki. Przemalowanie z innym motywem upraszcza budynki, dlatego tu
tylko poprawiamy obraz:
  1. patyna = piksele zielononiebieskie (odcień 150–210°, nasycenie > 0.12),
  2. dach = patyna po domknięciu morfologicznym i wypełnieniu dziur (łata otoczona patyną należy do dachu;
     plamy na szarym bruku nie są otoczone patyną, więc zostają),
  3. rdza w dachu = odcień 0–45°, nasycenie > 0.25, niezbyt jasno (świecące okna lukarn zostają),
  4. inpainting (Telea) z okolicznej patyny + lekka faktura z oryginału, żeby nie było gładkich placków.

Użycie: derust_roofs.py <wejście.png> <wyjście.png> [--blockout work/paint_<map>/blockout.png] [--preview porównanie.png]
Z --blockout (paint_map robi to domyślnie): płaskie dachy, które FLUX namalował jak bruk (wierzchy domów z makiety
bez patyny i bez czerwonej dachówki), dostają kolor łupku ze śniedzią, bez plam, z ciemnym gzymsem na krawędzi,
żeby nie zlewały się z chodnikiem (flat_roofs).
"""
import argparse

import cv2
import numpy as np


def blockout_roofs(blockout_png, shape, dilate=25):
    """Wierzchy domów z makiety (shaders/blockout_paint.gdshader maluje je na kolor śniedzi), w rozmiarze malunku.
    Łapie też dachy, które FLUX namalował bez patyny (np. płaski, szary dach gospody)."""
    b = cv2.imread(blockout_png, cv2.IMREAD_COLOR)
    bf = b.astype(np.int16)
    # szarozielony (oświetlony dach makiety ma ok. 114°, nasycenie ~0.12): zieleń i błękit wyraźnie nad czerwienią
    m = ((bf[..., 1] > bf[..., 2] + 10) & (bf[..., 0] > bf[..., 2] - 4) & (bf[..., 1] > 60)).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    # ciemniejsze pasy blachy na makiecie nie przechodzą progu: wypełnij zamknięte dziury w wierzchach domów
    n, lab, stats, _ = cv2.connectedComponentsWithStats((1 - m).astype(np.uint8), connectivity=4)
    for i in range(1, n):
        if stats[i, cv2.CC_STAT_AREA] < 6000:
            m[lab == i] = 1
    m = cv2.resize(m, (shape[1], shape[0]), interpolation=cv2.INTER_NEAREST)
    return cv2.dilate(m, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (dilate, dilate))) if dilate > 1 else m


def flat_roofs(img_bgr, blockout_png, patina_roof):
    """Płaskie dachy, które FLUX namalował jak bruk (szare kostki z plamami, nie do odróżnienia od ulicy):
    na wierzchach domów z makiety, które nie są ani miedziane (patyna), ani z czerwonej dachówki, usuwa plamy rdzy,
    przyciemnia i barwi na łupek ze śniedzią, a wzdłuż krawędzi dachu kładzie ciemny pas (gzyms/cień), żeby dach
    odcinał się od chodnika. Faktura kostek zostaje (tylko kolor i jasność), głębia bez zmian."""
    m = blockout_roofs(blockout_png, img_bgr.shape, dilate=1)
    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV_FULL).astype(np.float32)
    h, s, v = hsv[..., 0] * 360.0 / 256.0, hsv[..., 1] / 255.0, hsv[..., 2] / 255.0
    rust = ((h < 45) | (h > 345)) & (s > 0.25) & (v < 0.80) & (v > 0.08)
    flat = np.zeros(m.shape, np.uint8)
    n, lab, stats, _ = cv2.connectedComponentsWithStats(m, connectivity=8)
    for i in range(1, n):
        comp = lab == i
        if stats[i, cv2.CC_STAT_AREA] < 3000 or rust[comp].mean() >= 0.4:
            continue              # drobiazg albo czerwona dachówka: zostaje
        flat[comp] = 1
    # miedziane dachy (patyna) zostają; płaski, „brukowy” fragment tego samego budynku już nie
    pn, plab, pstats, _ = cv2.connectedComponentsWithStats((patina_roof > 0).astype(np.uint8), connectivity=8)
    big = img_bgr.shape[0] * img_bgr.shape[1] * 0.004   # prawdziwe miedziane dachy; drobne zielonkawe łaty bruku nie
    for i in range(1, pn):
        if pstats[i, cv2.CC_STAT_AREA] >= big:
            flat[plab == i] = 0
    flat = cv2.morphologyEx(flat, cv2.MORPH_OPEN, np.ones((7, 7), np.uint8))
    if not flat.any():
        return img_bgr, flat
    L = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    lit = (v > 0.92) & (s > 0.35) | (L[..., 0] > 235)   # świecące okna lukarn i latarnie zostają
    # na płaskich dachach także jasne, pastelowe plamy (na ulicy zostają, tu odcinałyby się od łupku)
    rust = (((h < 50) | (h > 345)) & (s > 0.15) & ~lit) | rust
    mix = np.where(rust, 0.9, 0.72)             # plamy rdzy mocniej (bez inpaintingu: fugi kostek zostają)
    # plamy rdzy są jaśniejsze od bruku: dostają jasność okolicznych kostek bez plam (rozmycie ważone maską)
    l0 = L[..., 0].copy()
    clean = (~rust).astype(np.float32)
    local = cv2.GaussianBlur(l0 * clean, (0, 0), 9) / np.maximum(cv2.GaussianBlur(clean, (0, 0), 9), 1e-3)
    tex = l0 - cv2.GaussianBlur(l0, (0, 0), 2)
    l0 = np.where(rust, local + 0.5 * tex, l0)
    # duże jasne łaty (kałuże, przetarcia) spłaszczone, drobna faktura kostek zostaje
    fm = flat > 0
    low = cv2.GaussianBlur(l0, (0, 0), 14)
    mean = float(l0[fm].mean())
    l0 = mean + (low - mean) * 0.35 + (l0 - low)
    graded = L.copy()
    graded[..., 0] = l0 * 0.70 + 8
    graded[..., 1] = L[..., 1] * (1 - mix) + (128 - 9) * mix      # ku zieleni (śniedź)
    graded[..., 2] = L[..., 2] * (1 - mix) + (128 - 7) * mix      # ku błękitowi (łupek)
    # krawędź dachu: ciemny pas 0..10 px od brzegu maski
    dist = cv2.distanceTransform(flat, cv2.DIST_L2, 5)
    rim = np.clip(1.0 - dist / 10.0, 0, 1) * (flat > 0)
    graded[..., 0] *= 1.0 - 0.45 * rim
    out = cv2.cvtColor(np.clip(graded, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)
    w = cv2.GaussianBlur(flat.astype(np.float32), (0, 0), 1.5) * (~lit)
    res = (img_bgr * (1 - w[..., None]) + out * w[..., None]).astype(np.uint8)
    return res, flat


def roof_rust_mask(img_bgr, close_px=71, extra_roof=None):
    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV_FULL).astype(np.float32)
    h, s, v = hsv[..., 0] * 360.0 / 256.0, hsv[..., 1] / 255.0, hsv[..., 2] / 255.0
    patina = ((h > 150) & (h < 215) & (s > 0.12) & (v > 0.18)).astype(np.uint8)
    patina = cv2.morphologyEx(patina, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    # dachy: domknięcie (łata w środku patyny) i wypełnienie zamkniętych dziur
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (close_px, close_px))
    roof = cv2.morphologyEx(patina, cv2.MORPH_CLOSE, k)
    inv = (1 - roof).astype(np.uint8)
    n, lab, stats, _ = cv2.connectedComponentsWithStats(inv, connectivity=4)
    holes = np.zeros_like(roof)
    big = img_bgr.shape[0] * img_bgr.shape[1] * 0.002
    for i in range(1, n):
        if stats[i, cv2.CC_STAT_AREA] < big:
            holes[lab == i] = 1
    roof = np.maximum(roof, holes)
    # odrzuć drobne skrawki „patyny” (np. zielonkawe kamienie)
    n, lab, stats, _ = cv2.connectedComponentsWithStats(roof, connectivity=8)
    keep = np.zeros_like(roof)
    for i in range(1, n):
        if stats[i, cv2.CC_STAT_AREA] > 4000:
            keep[lab == i] = 1
    roof = cv2.erode(keep, np.ones((3, 3), np.uint8))
    rust = ((h < 45) | (h > 345)) & (s > 0.25) & (v < 0.80) & (v > 0.08)
    if extra_roof is not None:
        # dach z makiety, który jest w większości „rdzawy”, to zamierzona czerwona dachówka: zostaje
        n, lab, stats, _ = cv2.connectedComponentsWithStats(extra_roof.astype(np.uint8), connectivity=8)
        for i in range(1, n):
            comp = lab == i
            if rust[comp].mean() < 0.4:
                roof[comp] = 1
    mask = (rust & (roof > 0)).astype(np.uint8)
    mask = cv2.dilate(mask, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5)))
    return mask & roof, roof


def derust(img_bgr, strength=1.0, blockout_png=""):
    mask, roof = roof_rust_mask(img_bgr)
    filled = cv2.inpaint(img_bgr, mask * 255, 9, cv2.INPAINT_TELEA)
    # faktura: jasność oryginału (szczegóły blachy) na odcieniu patyny z inpaintingu
    lab_f = cv2.cvtColor(filled, cv2.COLOR_BGR2LAB).astype(np.float32)
    lab_o = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    hi = lab_o[..., 0] - cv2.GaussianBlur(lab_o[..., 0], (0, 0), 3)
    lab_f[..., 0] += 0.5 * hi
    out = cv2.cvtColor(np.clip(lab_f, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)
    soft = cv2.GaussianBlur(mask.astype(np.float32), (0, 0), 2.0)[..., None] * strength
    res = (img_bgr * (1 - soft) + out * soft).astype(np.uint8)
    if blockout_png:
        res, flat = flat_roofs(res, blockout_png, roof)
        roof = np.maximum(roof, flat)
    return res, mask, roof


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--preview", default="")
    ap.add_argument("--strength", type=float, default=1.0)
    ap.add_argument("--blockout", default="", help="blockout.png z paint_map (wierzchy domów jako dodatkowa maska dachów)")
    a = ap.parse_args()
    img = cv2.imread(a.src, cv2.IMREAD_UNCHANGED)
    alpha = img[..., 3:] if img.shape[2] == 4 else None
    bgr = img[..., :3].copy()
    res, mask, roof = derust(bgr, a.strength, a.blockout)
    out = np.concatenate([res, alpha], axis=2) if alpha is not None else res
    cv2.imwrite(a.dst, out)
    print(f"DERUST_OK {a.dst}: dachy {roof.mean():.1%} obrazu, poprawione {mask.sum()} px ({mask.sum() / max(1, roof.sum()):.1%} dachów)")
    if a.preview:
        vis = bgr.copy()
        vis[roof > 0] = (vis[roof > 0] * 0.6 + np.array([0, 160, 0]) * 0.4).astype(np.uint8)
        vis[mask > 0] = (0, 0, 255)
        cv2.imwrite(a.preview, np.concatenate([vis, res], axis=1))


if __name__ == "__main__":
    main()
