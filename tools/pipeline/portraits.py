#!/usr/bin/env python3
"""Portrety do dialogów: koncept postaci (work/<id>/concept.png) → malowane popiersie → assets/portraits/<id>.png.

Użycie (Python z venv ComfyUI):
  portraits.py <obsada.txt> [--kind character|prop] [--only id1,id2] [--force] [--seed N] [--count 1]

Obsada jak w cast.py („id: opis”). Koncept jest referencją (wygląd, strój, kolory), opis doprecyzowuje.
Przy --count > 1 powstają warianty <id>_N.png w work/<id>/ i arkusz work/portraits_sheet.png; wybrany
wariant kopiujesz ręcznie albo uruchamiasz ponownie z --seed.
"""
import argparse
import os
import shutil
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.environ.get("WORK", os.path.join(HERE, "work"))
sys.path.insert(0, os.path.join(HERE, "comfy"))
sys.path.insert(0, HERE)
from cast import parse_cast  # noqa: E402
from paint_map import comfy_image  # noqa: E402

STYLE = ("hand-painted fantasy RPG dialogue portrait in the style of classic painted 1990s isometric RPG portraits, "
         "oil painting texture, dramatic warm rim light from the left, muted rust, brass and deep violet palette, "
         "dark violet smoky background with faint planar sparks, art nouveau brass frame motifs at the very edge, "
         "no text, no watermark")
CHAR_PROMPT = ("Tight close-up bust portrait of the same character as in image 1: {desc}. Only the head, neck "
               "and top of the shoulders are visible; the face is large and fills the upper two thirds of the "
               "picture, the image is cut off at the upper chest, no arms, no hands, no legs. Keep the face, hair, "
               "headwear, clothing colors and distinctive details from image 1. Three-quarter view, looking "
               "slightly towards the viewer, expressive face with personality. {style}.")
PROP_PROMPT = ("Close-up illustration of the same object as in image 1: {desc}. Keep its shape, materials and "
               "colors from image 1, shown three-quarter view, filling the frame, slightly mysterious mood. {style}.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cast")
    ap.add_argument("--kind", choices=["character", "prop"], default="character")
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--count", type=int, default=1)
    ap.add_argument("--width", type=int, default=768)
    ap.add_argument("--height", type=int, default=960)
    ap.add_argument("--server", default=os.environ.get("COMFY_URL", "http://127.0.0.1:8188"))
    a = ap.parse_args()

    out_dir = os.path.join(ROOT, "assets", "portraits")
    os.makedirs(out_dir, exist_ok=True)
    only = {s for s in a.only.split(",") if s}
    made = []
    for cid, desc, *_ in parse_cast(a.cast):
        if only and cid not in only:
            continue
        dst = os.path.join(out_dir, f"{cid}.png")
        if os.path.exists(dst) and not a.force:
            print(f"  {cid}: jest, pomijam (--force, żeby wygenerować ponownie)")
            continue
        concept = os.path.join(WORK, cid, "concept.png")
        if not os.path.exists(concept):
            print(f"  {cid}: brak konceptu {concept}, pomijam")
            continue
        tpl = PROP_PROMPT if a.kind == "prop" else CHAR_PROMPT
        prompt = tpl.format(desc=desc, style=STYLE)
        for i in range(a.count):
            out = os.path.join(WORK, cid, f"portrait_{i + 1}.png")
            comfy_image(a.server, prompt, [concept], a.width, a.height, a.seed + i, out)
            made.append((cid, out))
        shutil.copy(os.path.join(WORK, cid, "portrait_1.png"), dst)
    if made:
        w, h = 256, 320
        cols = min(8, len(made))
        rows = (len(made) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * w, rows * h), (20, 15, 25))
        for i, (cid, p) in enumerate(made):
            im = Image.open(p).convert("RGB").resize((w, h), Image.LANCZOS)
            ImageDraw.Draw(im).text((8, 6), cid, fill=(255, 220, 120))
            sheet.paste(im, ((i % cols) * w, (i // cols) * h))
        sheet.save(os.path.join(WORK, "portraits_sheet.png"))
        print(f"PORTRAITS_OK {len(made)} (arkusz: {os.path.join(WORK, 'portraits_sheet.png')})")


if __name__ == "__main__":
    main()
