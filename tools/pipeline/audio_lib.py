"""Wspólne narzędzia audio (numpy): zapis WAV, normalizacja, pętle bez szwu, obwiednie."""
import wave

import numpy as np

SR = 44100


def write_wav(path, x, sr=SR):
    """x: float -1..1, kształt (n,) albo (n, 2)."""
    x = np.clip(np.asarray(x, np.float64), -1.0, 1.0)
    ch = 1 if x.ndim == 1 else x.shape[1]
    pcm = (x * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def normalize(x, peak_db=-1.0, rms_db=None):
    """Szczyt do peak_db; opcjonalnie najpierw głośność RMS do rms_db (z ograniczeniem szczytu)."""
    x = np.asarray(x, np.float64)
    if rms_db is not None:
        rms = np.sqrt(np.mean(x ** 2)) + 1e-12
        x = x * (10 ** (rms_db / 20) / rms)
    peak = np.max(np.abs(x)) + 1e-12
    lim = 10 ** (peak_db / 20)
    if peak > lim:
        x = x * (lim / peak)
    return x


def make_loop(x, sr=SR, xfade=2.0):
    """Pętla bez szwu: koniec przenika w początek (equal-power), wynik krótszy o xfade."""
    n = int(xfade * sr)
    if len(x) <= 2 * n:
        return x
    t = np.linspace(0, np.pi / 2, n)
    fin, fout = np.sin(t), np.cos(t)
    if x.ndim == 2:
        fin, fout = fin[:, None], fout[:, None]
    head = x[:n] * fin + x[-n:] * fout
    return np.concatenate([head, x[n:-n]])


def fade(x, sr=SR, fin=0.005, fout=0.05):
    x = np.array(x, np.float64)
    a, b = int(fin * sr), int(fout * sr)
    if a:
        x[:a] *= np.linspace(0, 1, a)[:, None] if x.ndim == 2 else np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)[:, None] if x.ndim == 2 else np.linspace(1, 0, b)
    return x


def env_exp(n, decay, sr=SR):
    """Obwiednia wykładnicza: decay = czas spadku o 60 dB (s)."""
    t = np.arange(n) / sr
    return np.exp(-6.9 * t / max(decay, 1e-4))


def trim_silence(x, sr=SR, thr_db=-45.0, keep=0.05):
    """Obcina ciszę na początku i końcu (ramki 50 ms poniżej thr_db), zostawia keep s zapasu."""
    mono = x.mean(1) if x.ndim == 2 else x
    win = int(0.05 * sr)
    n = len(mono) // win
    if n == 0:
        return x
    rms = np.sqrt(np.mean(mono[: n * win].reshape(n, win) ** 2, 1))
    loud = np.where(20 * np.log10(rms + 1e-12) > thr_db)[0]
    if len(loud) == 0:
        return x
    a = max(0, loud[0] * win - int(keep * sr))
    b = min(len(x), (loud[-1] + 1) * win + int(keep * sr))
    return x[a:b]
