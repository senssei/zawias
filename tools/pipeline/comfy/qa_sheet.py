#!/usr/bin/env python3
"""Skleja klatki kontrolne animacji w jeden arkusz PNG. Użycie: qa_sheet.py <katalog> <wyjście.png>"""
import glob, os, sys
from PIL import Image, ImageDraw
fs = sorted(glob.glob(os.path.join(sys.argv[1], "*.png")))
W = 6; rows = (len(fs) + W - 1) // W
sheet = Image.new("RGB", (W * 256, rows * 276), (40, 40, 40)); d = ImageDraw.Draw(sheet)
for i, f in enumerate(fs):
    im = Image.open(f).convert("RGB").resize((256, 256)); x, y = (i % W) * 256, (i // W) * 276
    sheet.paste(im, (x, y + 20)); d.text((x + 6, y + 4), os.path.basename(f)[:-4], fill=(255, 220, 120))
sheet.save(sys.argv[2]); print("QA_OK", sys.argv[2])
