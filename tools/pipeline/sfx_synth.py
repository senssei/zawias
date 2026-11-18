#!/usr/bin/env python3
"""Proceduralne efekty dźwiękowe (numpy/scipy, bez zewnętrznych próbek) -> assets/audio/sfx/<id>.wav
oraz ambient -> assets/audio/ambient/<id>.wav. Wszystko własne, bez licencji do pilnowania.

Użycie (Python z numpy+scipy, np. venv ComfyUI): sfx_synth.py [--only id1,id2] [--seed N]
Każdy efekt to funkcja gen_<id>(rng) zwracająca float mono/stereo w SR. Warianty (kroki) mają sufiks _N.
Pliki z assets/audio/sfx można podmienić na nagrania (np. pakiety CC0) o tych samych nazwach.
"""
import argparse
import zlib
import os
import sys

import numpy as np
from scipy import signal

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from audio_lib import SR, env_exp, fade, make_loop, normalize, write_wav  # noqa: E402


def t_(sec):
    return np.arange(int(sec * SR)) / SR


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, btype="low", fs=SR, output="sos"), x)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, btype="high", fs=SR, output="sos"), x)


def noise(rng, sec):
    return rng.standard_normal(int(sec * SR))


def sweep_bp(x, f0, f1, q=4.0, blocks=64):
    """Filtr pasmowy przesuwany w czasie (szum -> „świst”)."""
    out = np.zeros_like(x)
    n = len(x)
    edges = np.linspace(0, n, blocks + 1).astype(int)
    zi = None
    for i in range(blocks):
        f = f0 * (f1 / f0) ** (i / max(blocks - 1, 1))
        sos = signal.butter(2, [f / (1 + 1 / q), min(f * (1 + 1 / q), SR / 2 - 100)], btype="band", fs=SR, output="sos")
        if zi is None or zi.shape[0] != sos.shape[0]:
            zi = np.zeros((sos.shape[0], 2))
        out[edges[i]:edges[i + 1]], zi = signal.sosfilt(sos, x[edges[i]:edges[i + 1]], zi=zi)
    return out


def partials(freqs, amps, decays, sec):
    t = t_(sec)
    return sum(a * np.sin(2 * np.pi * f * t) * np.exp(-6.9 * t / d) for f, a, d in zip(freqs, amps, decays))


def stereo(x, width=0.15, rng=None):
    """Lekka szerokość: drugi kanał przesunięty o kilka ms."""
    d = int(0.004 * SR)
    r = np.concatenate([np.zeros(d), x[:-d]])
    return np.stack([x * (1 - width) + r * width, r * (1 - width) + x * width], 1)


# ------------------------------------------------------------------ efekty

def gen_step_stone(rng):
    """Krok na bruku: krótki trzask (obcas) + głuche tąpnięcie, każdy wariant inny."""
    n = noise(rng, 0.18)
    click = bp(n, 900 + rng.uniform(-200, 300), 4500) * env_exp(len(n), 0.035)
    thump = lp(noise(rng, 0.18), 220) * env_exp(len(n), 0.09) * 2.5
    grit = bp(noise(rng, 0.18), 2500, 8000) * env_exp(len(n), 0.06) * 0.3
    return fade(click + thump + grit, fout=0.03)


def gen_ui_click(rng):
    return fade(partials([2200, 3300], [1, 0.4], [0.02, 0.015], 0.06) + bp(noise(rng, 0.06), 2000, 6000) * env_exp(int(0.06 * SR), 0.01) * 0.3)


def gen_ui_open(rng):
    t = t_(0.35)
    x = sweep_bp(noise(rng, 0.35), 400, 2400, q=3) * np.sin(np.pi * t / t[-1]) * 0.8
    x += partials([880, 1320], [0.3, 0.2], [0.25, 0.2], 0.35)
    return fade(x)


def gen_ui_close(rng):
    t = t_(0.3)
    x = sweep_bp(noise(rng, 0.3), 2200, 500, q=3) * np.sin(np.pi * t / t[-1]) * 0.8
    return fade(x)


def gen_dialogue(rng):
    """Otwarcie rozmowy: miękki dzwonek z mosiądzu."""
    return fade(partials([523, 784, 1046, 1568], [0.6, 0.4, 0.25, 0.1], [0.9, 0.7, 0.5, 0.3], 1.0), fout=0.2)


def gen_dice(rng):
    """Rzut kością: kilka coraz rzadszych i cichszych stuknięć drewna o kamień."""
    sec = 0.9
    x = np.zeros(int(sec * SR))
    tpos, gap, amp = 0.0, 0.05, 1.0
    while tpos < sec - 0.08 and amp > 0.05:
        i = int(tpos * SR)
        hit = bp(noise(rng, 0.05), 1200 + rng.uniform(0, 1500), 7000) * env_exp(int(0.05 * SR), 0.015)
        hit += partials([rng.uniform(1800, 2600)], [0.5], [0.02], 0.05)
        x[i:i + len(hit)] += hit * amp
        tpos += gap * rng.uniform(0.7, 1.4)
        gap *= 1.25
        amp *= 0.78
    return fade(x)


def gen_sword_swing(rng):
    t = t_(0.32)
    x = sweep_bp(noise(rng, 0.32), 300, 2600, q=2.5) * np.sin(np.pi * t / t[-1]) ** 2
    return fade(x)


def gen_miss(rng):
    t = t_(0.28)
    return fade(sweep_bp(noise(rng, 0.28), 500, 1800, q=3) * np.sin(np.pi * t / t[-1]) ** 2 * 0.7)


def gen_sword_hit(rng):
    """Uderzenie metalu: nieharmoniczne alikwoty + trzask."""
    base = rng.uniform(380, 460)
    ring = partials([base * r for r in (1, 2.76, 5.4, 8.93)], [1, 0.6, 0.35, 0.2], [0.45, 0.3, 0.2, 0.12], 0.6)
    crack = bp(noise(rng, 0.6), 1500, 9000) * env_exp(int(0.6 * SR), 0.04) * 2
    return fade(ring * 0.6 + crack, fout=0.1)


def gen_hit_flesh(rng):
    t = t_(0.35)
    thud = np.sin(2 * np.pi * (110 * t - 60 * t * t)) * env_exp(len(t), 0.18) * 1.5
    slap = bp(noise(rng, 0.35), 300, 2500) * env_exp(len(t), 0.05)
    return fade(thud + slap)


def gen_death(rng):
    t = t_(1.0)
    fall = lp(noise(rng, 1.0), 400) * env_exp(len(t), 0.5) * np.clip(t * 8, 0, 1) * 2
    thud = np.sin(2 * np.pi * (70 * t - 25 * t * t)) * env_exp(len(t), 0.4) * (t > 0.35)
    return fade(fall + thud * 1.5, fout=0.2)


def gen_spell_fire(rng):
    """Ogień: narastający szum + trzaski."""
    sec = 1.1
    t = t_(sec)
    roar = lp(noise(rng, sec), 900) * np.minimum(t * 6, 1) * env_exp(len(t), 1.0) * 1.5
    crackle = np.zeros(len(t))
    for _ in range(40):
        i = rng.integers(0, len(t) - 800)
        crackle[i:i + 800] += bp(noise(rng, 800 / SR), 1500, 7000) * env_exp(800, 0.006) * rng.uniform(0.2, 1)
    whoosh = sweep_bp(noise(rng, sec), 200, 1500, q=2) * np.minimum(t * 4, 1) * env_exp(len(t), 0.8)
    return stereo(fade(roar + crackle + whoosh, fout=0.25))


def gen_spell_frost(rng):
    sec = 1.0
    t = t_(sec)
    shimmer = sum(np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * rng.uniform(0.2, 0.5)
                  for f in rng.uniform(2500, 6000, 8)) * env_exp(len(t), 0.7) * np.minimum(t * 20, 1)
    hiss = hp(noise(rng, sec), 4000) * env_exp(len(t), 0.5) * 0.4
    crack = bp(noise(rng, sec), 2000, 8000) * env_exp(len(t), 0.03)
    return stereo(fade(shimmer * 0.5 + hiss + crack))


def gen_spell_heal(rng):
    """Leczenie: wznoszące się arpeggio dzwonków."""
    sec = 1.4
    x = np.zeros(int(sec * SR))
    for i, f in enumerate([523, 659, 784, 1046, 1318]):
        s = int(i * 0.09 * SR)
        n = partials([f, f * 2, f * 3], [0.6, 0.25, 0.1], [0.8, 0.5, 0.3], sec - i * 0.09)
        m = min(len(n), len(x) - s)
        x[s:s + m] += n[:m]
    return stereo(fade(x * 0.5, fout=0.3))


def gen_spell_force(rng):
    """Magiczny pocisk: krótkie „zapy” w dół."""
    sec = 0.6
    t = t_(sec)
    f = 1800 * np.exp(-t * 5) + 200
    zap = signal.sawtooth(2 * np.pi * np.cumsum(f) / SR) * env_exp(len(t), 0.35)
    return stereo(fade(lp(zap, 3500) * 0.6 + bp(noise(rng, sec), 3000, 9000) * env_exp(len(t), 0.1) * 0.3))


def gen_spell_shield(rng):
    sec = 0.9
    t = t_(sec)
    x = partials([660, 990, 1320, 1980], [0.5, 0.4, 0.3, 0.2], [0.8, 0.6, 0.5, 0.4], sec)
    x *= 1 + 0.3 * np.sin(2 * np.pi * 7 * t)
    return stereo(fade(x * 0.6 + sweep_bp(noise(rng, sec), 3000, 800, q=4) * env_exp(len(t), 0.4) * 0.3))


def gen_spell_generic(rng):
    """Czar bez własnego dźwięku: krótki magiczny poszum z alikwotami."""
    sec = 0.8
    t = t_(sec)
    x = sweep_bp(noise(rng, sec), 400, 3000, q=3) * np.sin(np.pi * t / t[-1]) * 0.6
    x += partials([440, 660, 880], [0.3, 0.2, 0.15], [0.6, 0.5, 0.4], sec)
    return stereo(fade(x))


def gen_chest_open(rng):
    """Skrzypienie zawiasu + stuk wieka."""
    sec = 0.9
    t = t_(sec)
    f = 180 + 60 * np.sin(2 * np.pi * 1.3 * t) + rng.uniform(-10, 10)
    creak = bp(signal.sawtooth(2 * np.pi * np.cumsum(f) / SR) * (0.6 + 0.4 * rng.standard_normal(len(t)) * 0.2), 600, 3000)
    creak *= np.sin(np.pi * np.clip(t / 0.7, 0, 1)) ** 0.5
    clunk = np.zeros(len(t))
    i = int(0.72 * SR)
    k = lp(noise(rng, sec - 0.72), 500) * env_exp(len(t) - i, 0.12) * 2
    clunk[i:] = k
    return fade(creak * 0.5 + clunk)


def gen_coin(rng):
    x = partials([2637, 3951, 5274], [0.6, 0.4, 0.2], [0.35, 0.25, 0.15], 0.45)
    y = partials([2489, 3729], [0.4, 0.3], [0.3, 0.2], 0.45)
    out = x.copy()
    d = int(0.07 * SR)
    out[d:] += y[:-d]
    return fade(out * 0.5, fout=0.1)


def gen_portal(rng):
    """Portal w łuku: niski pomruk + migotanie."""
    sec = 2.5
    t = t_(sec)
    hum = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(55, 0.6), (82.5, 0.3), (110, 0.2)]) * np.sin(np.pi * t / t[-1])
    sparkle = sum(np.sin(2 * np.pi * f * t) * 0.15 * (0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(3, 9) * t))
                  for f in rng.uniform(1200, 3500, 6)) * np.sin(np.pi * t / t[-1])
    whoosh = sweep_bp(noise(rng, sec), 150, 2500, q=2) * np.sin(np.pi * t / t[-1]) * 0.5
    return stereo(fade(hum + sparkle + whoosh, fout=0.4), width=0.3)


def gen_level_up(rng):
    sec = 1.8
    x = np.zeros(int(sec * SR))
    for i, f in enumerate([392, 523, 659, 784, 1046]):
        s = int(i * 0.12 * SR)
        n = partials([f, f * 2, f * 4], [0.6, 0.3, 0.1], [1.2, 0.8, 0.4], sec - i * 0.12)
        m = min(len(n), len(x) - s)
        x[s:s + m] += n[:m]
    return stereo(fade(x * 0.45, fout=0.4))


# ------------------------------------------------------------------ ambient (pętle)

def amb_wind_planar(rng):
    """Wiatr planarny: szum z wolno pływającym pasmem i podmuchami."""
    sec = 40
    t = t_(sec)
    n = noise(rng, sec)
    lfo = 0.5 + 0.5 * np.sin(2 * np.pi * t / 9.0) * np.sin(2 * np.pi * t / 23.0 + 1)
    low = lp(n, 500) * (0.4 + 0.6 * lfo)
    whistle = sweep_bp(noise(rng, sec), 600, 900, q=8, blocks=200) * (0.2 + 0.3 * lfo) * 0.6
    x = stereo(low + whistle, width=0.4)
    return make_loop(x, xfade=4.0)


def amb_market(rng):
    """Gwar targu z daleka: wiele „głosów” (pasmowy szum z obwiedniami sylab) + odległe stuknięcia."""
    sec = 40
    n_s = int(sec * SR)
    x = np.zeros(n_s)
    for _ in range(26):
        f = rng.uniform(250, 900)
        voice = bp(noise(rng, sec), f, f * 2.2)
        syl = np.zeros(n_s)
        pos = rng.uniform(0, 2)
        while pos < sec:
            d = rng.uniform(0.08, 0.25)
            i, j = int(pos * SR), int(min(sec, pos + d) * SR)
            syl[i:j] = np.sin(np.linspace(0, np.pi, j - i)) * rng.uniform(0.3, 1)
            pos += d + (rng.uniform(0.02, 0.15) if rng.random() < 0.8 else rng.uniform(0.6, 2.5))
        x += voice * syl * rng.uniform(0.3, 1)
    x = lp(x, 1800)
    for _ in range(30):
        i = rng.integers(0, n_s - 4000)
        x[i:i + 4000] += bp(noise(rng, 4000 / SR), 800, 3000) * env_exp(4000, 0.03) * rng.uniform(0.1, 0.4)
    return make_loop(stereo(x, width=0.5), xfade=4.0)


SFX = {
    "step_stone": (gen_step_stone, 4), "ui_click": (gen_ui_click, 1), "ui_open": (gen_ui_open, 1),
    "ui_close": (gen_ui_close, 1), "dialogue": (gen_dialogue, 1), "dice": (gen_dice, 2),
    "sword_swing": (gen_sword_swing, 2), "miss": (gen_miss, 1), "sword_hit": (gen_sword_hit, 2),
    "hit_flesh": (gen_hit_flesh, 2), "death": (gen_death, 1), "spell_fire": (gen_spell_fire, 1),
    "spell_frost": (gen_spell_frost, 1), "spell_heal": (gen_spell_heal, 1), "spell_force": (gen_spell_force, 1),
    "spell_shield": (gen_spell_shield, 1), "spell_generic": (gen_spell_generic, 1), "chest_open": (gen_chest_open, 1),
    "coin": (gen_coin, 1), "portal": (gen_portal, 1), "level_up": (gen_level_up, 1),
}
AMBIENT = {"wind_planar": amb_wind_planar, "market": amb_market}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--seed", type=int, default=3)
    a = ap.parse_args()
    only = {s for s in a.only.split(",") if s}
    sfx_dir = os.path.join(ROOT, "assets", "audio", "sfx")
    amb_dir = os.path.join(ROOT, "assets", "audio", "ambient")
    os.makedirs(sfx_dir, exist_ok=True)
    os.makedirs(amb_dir, exist_ok=True)
    n = 0
    for sid, (fn, variants) in SFX.items():
        if only and sid not in only:
            continue
        for v in range(variants):
            rng = np.random.default_rng(a.seed * 1000 + zlib.crc32(sid.encode()) % 997 + v)
            x = fn(rng)
            x = x / (np.max(np.abs(x)) + 1e-12) * 10 ** (-3 / 20)   # równy szczyt -3 dB
            name = f"{sid}_{v + 1}" if variants > 1 else sid
            write_wav(os.path.join(sfx_dir, name + ".wav"), x)
            n += 1
    for aid, fn in AMBIENT.items():
        if only and aid not in only:
            continue
        rng = np.random.default_rng(a.seed * 7 + len(aid))
        write_wav(os.path.join(amb_dir, aid + ".wav"), normalize(fn(rng), peak_db=-6.0, rms_db=-24.0))
        n += 1
    print(f"SFX_OK {n} plików -> assets/audio/sfx, assets/audio/ambient")


if __name__ == "__main__":
    main()
