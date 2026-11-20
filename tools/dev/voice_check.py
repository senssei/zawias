#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Kontrola nagrań głosów bez słuchania: Whisper (large-v3-turbo, MIT) przepisuje każde nagranie i porównuje
z tekstem z manifestu (WER na słowach), plus długość i tempo. Uruchamiać pythonem z venv ComfyUI.

Użycie: voice_check.py [--lang en] [--only mirela,_narrator] [--max-wer 0.2] [--json wynik.json]
Sprawdza każdy fragment z manifestu (kwestie postaci i narratora).
Wypisuje kwestie podejrzane (WER ponad próg, tempo poza 1.1–4.8 słowa/s) i ich id do ponownego wygenerowania:
  pipeline.sh voice --only <dialog> --node <węzeł> --force
"""
import argparse
import json
import os
import re
import sys

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
VOICE_DIR = os.path.join(ROOT, "assets", "audio", "voice")


def words(s):
    s = s.lower().replace("’", "'")
    return [w.strip("'") for w in re.findall(r"[a-z0-9ąćęłńóśźż']+", s) if w.strip("'")]


COMMON_CAPS = {"the", "a", "an", "i", "it", "you", "he", "she", "we", "they", "but", "and", "no", "yes", "then", "not"}


def names(text):
    """Słowa pisane wielką literą (imiona i nazwy: Whisper zapisuje je po swojemu, np. Kwit -> Quit)."""
    return {w.lower() for w in re.findall(r"\b[A-ZĄĆĘŁŃÓŚŹŻ][a-ząćęłńóśźż]+\b", text) if w.lower() not in COMMON_CAPS}


def wer(ref, hyp):
    r, h = words(ref), words(hyp)
    d = np.zeros((len(r) + 1, len(h) + 1), dtype=np.int32)
    d[:, 0] = np.arange(len(r) + 1)
    d[0, :] = np.arange(len(h) + 1)
    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            d[i, j] = min(d[i - 1, j] + 1, d[i, j - 1] + 1, d[i - 1, j - 1] + (r[i - 1] != h[j - 1]))
    return d[len(r), len(h)] / max(1, len(r))


_asr = None


def transcribe(x, sr, lang="en"):
    """Whisper large-v3-turbo (ładowany raz); x: mono float32 w sr."""
    global _asr
    import torch
    from transformers import pipeline
    if _asr is None:
        _asr = pipeline("automatic-speech-recognition", model="openai/whisper-large-v3-turbo",
                        dtype=torch.float16, device="cuda:0" if torch.cuda.is_available() else "cpu")
    if sr != 16000:
        from scipy.signal import resample_poly
        from math import gcd
        g = gcd(16000, sr)
        x = resample_poly(x, 16000 // g, sr // g).astype(np.float32)
    return _asr({"raw": x, "sampling_rate": 16000}, generate_kwargs={"language": lang, "task": "transcribe"},
                return_timestamps=len(x) > 16000 * 29)["text"].strip()


NUMBERS = {"100": "hundred", "150": "hundred fifty", "10": "ten"}


def score(text, heard, seconds):
    """(WER, słowa/s). Nie liczą się jako błąd: liczby zapisane cyframi, przedimek przed nimi, imiona zapisane
    inaczej (podobieństwo pisowni >= 0.5)."""
    from difflib import SequenceMatcher
    h = [w for w in " ".join(NUMBERS.get(w, w) for w in words(heard)).split() if w not in ("a", "one")]
    r = [w for w in words(text) if w not in ("a", "one")]
    nm = names(text)
    for i, hw in enumerate(h):
        if hw not in r:
            for rw in nm:
                if SequenceMatcher(None, rw, hw).ratio() >= 0.5:
                    h[i] = rw
                    break
    return wer(" ".join(r), " ".join(h)), len(words(text)) / max(0.1, seconds)


def acceptable(w, wps, max_wer=0.2, n_words=99):
    """Krótkie zdania mogą mieć jeden błąd (np. „Hask sighs” -> „Hask size”)."""
    errors = w * max(1, n_words)
    return (w <= max_wer or (n_words <= 6 and errors <= 1.01)) and 1.1 <= wps <= 4.8


def load(path, sr=16000):
    import av
    c = av.open(path)
    rs = av.AudioResampler(format="fltp", layout="mono", rate=sr)
    chunks = [o.to_ndarray()[0] for fr in c.decode(audio=0) for o in rs.resample(fr)]
    chunks += [o.to_ndarray()[0] for o in rs.resample(None)]
    return np.concatenate(chunks).astype(np.float32)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", default="en")
    ap.add_argument("--only", default="")
    ap.add_argument("--max-wer", type=float, default=0.2)
    ap.add_argument("--json", default="")
    a = ap.parse_args()
    man = json.load(open(os.path.join(VOICE_DIR, a.lang, "manifest.json"), encoding="utf-8"))
    only = {s for s in a.only.split(",") if s}
    bad, report = [], {}
    for key, m in man.items():
        d, n = key.split("/")
        for sg in m.get("segments", []):
            if only and d not in only and sg.get("voice") not in only:
                continue
            k = f"{d}/{sg['file']}"
            x = load(os.path.join(VOICE_DIR, a.lang, d, sg["file"]))
            hyp = transcribe(x, 16000, a.lang)
            w, wps = score(sg["text"], hyp, len(x) / 16000)
            ok = acceptable(w, wps, a.max_wer, len(words(sg["text"])))
            report[k] = {"wer": round(w, 3), "wps": round(wps, 2), "heard": hyp}
            print(f"  {'ok ' if ok else 'ZŁE'} {k} [{sg['who']}]: WER {w:.2f}, {wps:.1f} sł/s"
                  + ("" if ok else f"\n      tekst: {sg['text']}\n      słychać: {hyp}"), flush=True)
            if not ok:
                bad.append((d, n))
    if a.json:
        json.dump(report, open(a.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"VOICE_CHECK {len(report) - len(bad)}/{len(report)} ok")
    for d, n in sorted(set(bad)):
        print(f"  pipeline.sh voice --only {d} --node {n} --force")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
