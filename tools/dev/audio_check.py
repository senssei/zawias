#!/usr/bin/env python3
"""Szybka kontrola plików WAV bez słuchania: długość, RMS, szczyt, cisza, przester, spektrogram (PNG).
Użycie: audio_check.py <plik.wav>... [--sheet wynik.png]"""
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw
from scipy import signal


def load(p):
    with wave.open(p) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float64) / 32768
        ch, sr = w.getnchannels(), w.getframerate()
    return (x.reshape(-1, ch).mean(1) if ch > 1 else x), sr


args = [a for a in sys.argv[1:] if not a.startswith("--")]
sheet_path = sys.argv[sys.argv.index("--sheet") + 1] if "--sheet" in sys.argv else None
if sheet_path in args:
    args.remove(sheet_path)
rows = []
for p in args:
    x, sr = load(p)
    rms = 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
    peak = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
    win = sr // 10
    frames = np.sqrt(np.mean(x[: len(x) // win * win].reshape(-1, win) ** 2, 1))
    silent = np.mean(20 * np.log10(frames + 1e-12) < -50)
    clip = np.mean(np.abs(x) > 0.999)
    seam = abs(x[0] - x[-1])
    print(f"{p.split('/')[-1]:28s} {len(x) / sr:6.1f} s  RMS {rms:6.1f} dB  szczyt {peak:5.1f} dB  cisza {silent:4.0%}  przester {clip:.4%}  skok na szwie {seam:.3f}")
    f, t, S = signal.spectrogram(x, sr, nperseg=2048, noverlap=1024)
    S = 10 * np.log10(S[: np.searchsorted(f, 8000)] + 1e-12)
    S = np.clip((S - S.max() + 80) / 80, 0, 1)[::-1]
    im = Image.fromarray((S * 255).astype(np.uint8)).resize((900, 160))
    ImageDraw.Draw(im).text((4, 2), p.split("/")[-1], fill=255)
    rows.append(im)
if sheet_path and rows:
    out = Image.new("L", (900, 160 * len(rows)))
    for i, r in enumerate(rows):
        out.paste(r, (0, i * 160))
    out.save(sheet_path)
