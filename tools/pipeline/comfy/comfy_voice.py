#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Głosy postaci i narrator przez ComfyUI + OmniVoice (k2-fsa, Apache 2.0; węzły ComfyUI-OmniVoice-TTS)
-> assets/audio/voice/<lang>/<dialog>/<węzeł>_<n>.ogg + <lang>/manifest.json

Użycie: comfy_voice.py [--lang en] [--only mirela,_narrator] [--node theft] [--force] [--force-ref]
                       [--no-narrator] [--dry-run] [--tries 4] [--no-check] [--steps 32]

Tekst węzła dzieli się na fragmenty po kolei: kwestie w cudzysłowie mówi postać (głos z obsady o id dialogu),
opis wokół czyta narrator (głos _narrator; kwestie obiektów spoza obsady też). Ta sama reguła co
VoiceLines.segments w grze. Obsada: assets/audio/voice/voices.json. Dla każdego głosu:
  1. próbka: Voice Design (instruct + ref_text, stały seed) -> work/voice/<id>/ref.wav (po zmianie obsady sama
     się odświeża; --force-ref wymusza),
  2. każdy fragment: Voice Clone z tej próbki, więc barwa się nie rozjeżdża.
Każda próbka i fragment przechodzi kontrolę Whisperem (tools/dev/voice_check.py); przy złym wyniku kolejny seed.
Manifest trzyma tekst każdego fragmentu: zmieniony tekst = fragment do odświeżenia, a nieużywane pliki są
usuwane (test w grze pilnuje, żeby nic nie zostało przeterminowane). Nagrania z dawnego formatu (<węzeł>.ogg,
sama wypowiedź) są przenoszone bez generowania, gdy tekst się zgadza.
"""
import argparse
import glob
import hashlib
import io
import json
import os
import re
import sys
import time
import urllib.parse
import uuid

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
PIPE = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(PIPE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, PIPE)
from comfy_gen import req  # noqa: E402

sys.path.insert(0, os.path.join(ROOT, "tools", "dev"))

VOICE_DIR = os.path.join(ROOT, "assets", "audio", "voice")
CAST = os.path.join(VOICE_DIR, "voices.json")
WORK = os.path.join(PIPE, "work", "voice")
SR = 24000
SPOKEN_RE = re.compile(r"[„“\"]([^„“”\"]+)[”\"]")
DEFAULT_MODEL = "OmniVoice (auto download)"


NARRATOR = "_narrator"
LETTER_RE = re.compile(r"[^\W\d_]")


def _clean(s):
    s = s.replace("…", "...").strip()
    while s and s[0] in ".,;:—–- ":
        s = s[1:].strip()
    return s


def segments(text):
    """Jak VoiceLines.segments (scripts/dialogue/voice_lines.gd): [{"who": "speaker"|"narrator", "text"}]."""
    parts, pos = [], 0
    for m in SPOKEN_RE.finditer(text):
        parts.append(("narrator", text[pos:m.start()]))
        parts.append(("speaker", m.group(1)))
        pos = m.end()
    parts.append(("narrator", text[pos:]))
    out = []
    for who, raw in parts:
        t = _clean(raw)
        if not LETTER_RE.search(t):
            continue
        if out and out[-1]["who"] == who:
            out[-1]["text"] += " " + t
        else:
            out.append({"who": who, "text": t})
    return out


def spoken(text):
    return " ".join(s["text"] for s in segments(text) if s["who"] == "speaker")


def tts_text(text):
    """Drobne poprawki wymowy dla modelu (nie zmieniają manifestu)."""
    t = text.replace("—", ", ").replace("–", ", ")
    t = re.sub(r"\s+", " ", t).strip()
    return t


def nodes(lang, cast):
    """[(dialog, węzeł, [{"who", "text", "voice"}])] dla wszystkich dialogów. Kwestie postaci spoza obsady
    (np. obiektów) czyta narrator."""
    overlay = {}
    if lang != "pl":
        p = os.path.join(ROOT, "i18n", lang, "data.json")
        overlay = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}
    out = []
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "dialogues", "*.json"))):
        did = os.path.basename(path)[:-5]
        d = json.load(open(path, encoding="utf-8"))
        for nid, node in d.get("nodes", {}).items():
            text = overlay.get(f"dialogues/{did}:nodes/{nid}/text", node.get("text", ""))
            segs = []
            # "narrator_quotes": [i] w węźle: i-tą wypowiedź w cudzysłowie czyta narrator (np. przysięga
            # wypowiadana głosem gracza we wspomnieniu, nie głosem rozmówcy)
            narrated = set(node.get("narrator_quotes", []))
            spoken_i = 0
            for sg in segments(text):
                own = sg["who"] == "speaker" and did in cast
                if sg["who"] == "speaker":
                    own = own and spoken_i not in narrated
                    spoken_i += 1
                sg["voice"] = did if own else NARRATOR
                segs.append(sg)
            if segs:
                out.append((did, nid, segs))
    # okrzyki na targu (data/barks.json): jeden fragment głosem postaci, klucz barks/<npc>_<n>
    bp = os.path.join(ROOT, "data", "barks.json")
    barks = json.load(open(bp, encoding="utf-8")) if os.path.exists(bp) else {}
    for npc, items in barks.items():
        for i, it in enumerate(items):
            t = _clean(overlay.get(f"barks:{npc}/{i}/text", it.get("text", "")))
            if LETTER_RE.search(t):
                out.append(("barks", f"{npc}_{i}", [{"who": "speaker", "text": t, "voice": npc if npc in cast else NARRATOR}]))
    return out


# ------------------------------------------------------------------ ComfyUI

COMMON = {"guidance_scale": 2.0, "t_shift": 0.1, "duration": 0.0, "device": "auto", "dtype": "auto",
          "attention": "auto", "position_temperature": 5.0, "class_temperature": 0.0,
          "layer_penalty_factor": 5.0, "denoise": True, "postprocess_output": True, "keep_model_loaded": True}


def wf_design(model, text, instruct, seed, speed, steps):
    return {
        "tts": {"class_type": "OmniVoiceVoiceDesignTTS", "inputs": dict(COMMON, model=model, text=text,
                voice_instruct=instruct, steps=steps, speed=speed, seed=seed)},
        "save": {"class_type": "SaveAudio", "inputs": {"audio": ["tts", 0], "filename_prefix": "zawias/voice"}},
    }


def wf_clone(model, text, ref_name, ref_text, seed, speed, steps):
    return {
        "ref": {"class_type": "LoadAudio", "inputs": {"audio": ref_name}},
        "tts": {"class_type": "OmniVoiceVoiceCloneTTS", "inputs": dict(COMMON, model=model, text=text,
                ref_audio=["ref", 0], ref_text=ref_text, steps=steps, speed=speed, seed=seed,
                preprocess_prompt=True, instruct="")},
        "save": {"class_type": "SaveAudio", "inputs": {"audio": ["tts", 0], "filename_prefix": "zawias/voice"}},
    }


def run(server, wf, timeout=900):
    res = json.loads(req(server, "/prompt", json.dumps({"prompt": wf, "client_id": uuid.uuid4().hex}).encode(),
                         {"Content-Type": "application/json"}))
    pid = res["prompt_id"]
    t0 = time.time()
    while time.time() - t0 < timeout:
        time.sleep(0.5)
        hist = json.loads(req(server, "/history/" + pid))
        if pid not in hist:
            continue
        st = hist[pid].get("status", {})
        if st.get("status_str") == "error":
            sys.exit("Błąd wykonania: " + json.dumps(st.get("messages", []), ensure_ascii=False)[:3000])
        if st.get("completed"):
            outs = hist[pid]["outputs"]
            f = next(x for o in outs.values() for x in o.get("audio", []))
            q = urllib.parse.urlencode({"filename": f["filename"], "subfolder": f.get("subfolder", ""),
                                        "type": f.get("type", "output")})
            return decode(req(server, "/view?" + q))
    sys.exit("Przekroczony czas generowania")


def upload_audio(server, path, name):
    boundary = uuid.uuid4().hex
    with open(path, "rb") as f:
        payload = f.read()
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"{name}\"\r\n"
            f"Content-Type: audio/wav\r\n\r\n").encode() + payload + \
           (f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"subfolder\"\r\n\r\nzawias_voice"
            f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue"
            f"\r\n--{boundary}--\r\n").encode()
    out = json.loads(req(server, "/upload/image", body, {"Content-Type": f"multipart/form-data; boundary={boundary}"}))
    return out["name"] if not out.get("subfolder") else out["subfolder"] + "/" + out["name"]


# ------------------------------------------------------------------ audio

def decode(data):
    """Plik z ComfyUI -> mono float32 w SR."""
    import av
    c = av.open(io.BytesIO(data))
    rs = av.AudioResampler(format="fltp", layout="mono", rate=SR)
    chunks = [o.to_ndarray()[0] for fr in c.decode(audio=0) for o in rs.resample(fr)]
    chunks += [o.to_ndarray()[0] for o in rs.resample(None)]
    return np.concatenate(chunks).astype(np.float32)


def polish(x):
    """Cisza z brzegów (zostawia oddech), krótkie wejście/wyjście, głośność mowy ~ -20 dBFS RMS."""
    thr = 10 ** (-45 / 20)
    idx = np.where(np.abs(x) > thr)[0]
    if len(idx):
        a = max(0, idx[0] - int(0.05 * SR))
        b = min(len(x), idx[-1] + int(0.15 * SR))
        x = x[a:b]
    n = min(len(x) // 4, int(0.01 * SR))
    if n > 0:
        x[:n] *= np.linspace(0, 1, n)
        x[-n:] *= np.linspace(1, 0, n)
    rms = float(np.sqrt(np.mean(x ** 2))) + 1e-9
    x = x * (10 ** (-20 / 20) / rms)
    peak = float(np.max(np.abs(x))) + 1e-9
    if peak > 0.89:
        x = x * (0.89 / peak)
    return x.astype(np.float32)


def write_wav(path, x):
    import wave
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def write_ogg(path, x, bitrate=80000):
    """Vorbis (natywny enkoder FFmpeg obsługuje tylko stereo, więc mono idzie na oba kanały)."""
    import av
    tmp = path + ".tmp"
    c = av.open(tmp, "w", format="ogg")
    s = c.add_stream("vorbis", rate=SR, layout="stereo")
    s.bit_rate = bitrate
    s.options = {"strict": "experimental"}
    data = np.ascontiguousarray(np.stack([x, x]).astype(np.float32))
    step = 4096
    for i in range(0, data.shape[1], step):
        fr = av.AudioFrame.from_ndarray(np.ascontiguousarray(data[:, i:i + step]), format="fltp", layout="stereo")
        fr.sample_rate = SR
        fr.pts = i
        for p in s.encode(fr):
            c.mux(p)
    for p in s.encode(None):
        c.mux(p)
    c.close()
    os.replace(tmp, path)


# ------------------------------------------------------------------ kontrola

def check_note(w):
    return "" if w is None else f", WER {w:.2f}"


def generate_checked(a, make_wf, text, seed, max_tries):
    """Generuje i sprawdza Whisperem (tools/dev/voice_check.py); przy złym wyniku kolejny seed.
    Zwraca (audio, seed, WER najlepszej próby albo None bez kontroli)."""
    if a.no_check:
        return polish(run(a.server, make_wf(seed))), seed, None
    from voice_check import acceptable, score, transcribe, words
    best = None
    for k in range(max_tries):
        sd = seed + k * 1000
        x = polish(run(a.server, make_wf(sd)))
        w, wps = score(text, transcribe(x, SR, a.lang), len(x) / SR)
        if best is None or w < best[2]:
            best = (x, sd, w)
        if acceptable(w, wps, n_words=len(words(text))):
            return x, sd, w
        print(f"      seed {sd}: WER {w:.2f}, {wps:.1f} sł/s, próbuję dalej", flush=True)
    return best


# ------------------------------------------------------------------ main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", default="en")
    ap.add_argument("--only", default="", help="id dialogów albo głosów (np. _narrator), po przecinku")
    ap.add_argument("--node", default="", help="tylko te węzły, po przecinku")
    ap.add_argument("--force", action="store_true", help="generuj wypowiedzi od nowa")
    ap.add_argument("--force-ref", action="store_true", help="generuj od nowa próbki głosu (i wszystkie kwestie)")
    ap.add_argument("--dry-run", action="store_true", help="tylko wypisz, co by powstało")
    ap.add_argument("--steps", type=int, default=32)
    ap.add_argument("--tries", type=int, default=4, help="prób na kwestię/próbkę, zanim przyjmie słabą (kontrola Whisperem)")
    ap.add_argument("--no-check", action="store_true", help="bez kontroli Whisperem (szybciej, bez gwarancji)")
    ap.add_argument("--no-narrator", action="store_true", help="bez fragmentów narratora")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--server", default=os.environ.get("COMFY_URL", "http://127.0.0.1:8188"))
    a = ap.parse_args()

    cast = json.load(open(CAST, encoding="utf-8"))["voices"]
    only = {s for s in a.only.split(",") if s}
    sel_nodes = {s for s in a.node.split(",") if s}
    dialogue_ids = {os.path.basename(p)[:-5] for p in glob.glob(os.path.join(ROOT, "data", "dialogues", "*.json"))} | {"barks"}
    unknown = only - set(cast) - dialogue_ids
    if unknown:
        sys.exit(f"Nie ma takiego dialogu ani głosu: {', '.join(sorted(unknown))}")
    out_dir = os.path.join(VOICE_DIR, a.lang)
    man_path = os.path.join(out_dir, "manifest.json")
    manifest = json.load(open(man_path, encoding="utf-8")) if os.path.exists(man_path) else {}
    all_nodes = nodes(a.lang, cast)

    def cast_sig(v):
        return hashlib.sha1(json.dumps([v["instruct"], v["ref_text"], v.get("seed", 0)]).encode()).hexdigest()[:12]

    def selected(d, n, sg):
        if sg["voice"] == NARRATOR and a.no_narrator:
            return False
        return (not only or d in only or sg["voice"] in only) and (not sel_nodes or n in sel_nodes)

    # plan: każdy fragment albo zostaje (aktualny plik), albo jest przenoszony ze starego formatu, albo generowany
    new_manifest, pending, moves = {}, [], []
    for d, n, segs in all_nodes:
        key = f"{d}/{n}"
        old = manifest.get(key, {})
        old_segs = {sg.get("file"): sg for sg in old.get("segments", [])}
        entry = []
        for i, sg in enumerate(segs):
            fname = f"{n}_{i}.ogg"
            rec = {"who": sg["who"], "text": sg["text"], "file": fname, "voice": sg["voice"]}
            sig = cast_sig(cast[sg["voice"]])
            prev = old_segs.get(fname, {})
            dst = os.path.join(out_dir, d, fname)
            fresh = (os.path.exists(dst) and prev.get("text") == sg["text"] and prev.get("who") == sg["who"]
                     and prev.get("sig") == sig)
            # dawny format (jedno nagranie z samą wypowiedzią postaci): przenieś, jeśli tekst się zgadza
            legacy = os.path.join(out_dir, d, n + ".ogg")
            if (not fresh and "text" in old and sg["who"] == "speaker" and old.get("text") == sg["text"]
                    and old.get("voice") == sig and os.path.exists(legacy)):
                moves.append((legacy, dst))
                rec.update(sig=sig, seconds=old.get("seconds"), seed=old.get("seed"), wer=old.get("wer"))
                entry.append(rec)
                continue
            if fresh and not (a.force or a.force_ref) or not selected(d, n, sg):
                if fresh:
                    rec.update({k: prev.get(k) for k in ("sig", "seconds", "seed", "wer")})
                    entry.append(rec)
                continue
            rec["sig"] = sig
            pending.append((d, n, i, rec))
        new_manifest[key] = entry

    n_segs = sum(len(s) for _, _, s in all_nodes)
    print(f"Głosy [{a.lang}]: {len(all_nodes)} węzłów, {n_segs} fragmentów; przeniesienie {len(moves)}, "
          f"do wygenerowania {len(pending)}")
    if a.dry_run:
        for d, n, i, rec in pending:
            print(f"  {d}/{n}_{i} [{rec['voice']}]: {rec['text']}")
        return

    def save():
        os.makedirs(out_dir, exist_ok=True)
        clean = {k: {"segments": [{kk: vv for kk, vv in r.items() if vv is not None} for r in sorted(v, key=lambda r: r["file"])]}
                 for k, v in sorted(new_manifest.items()) if v}
        with open(man_path, "w", encoding="utf-8") as f:
            json.dump(clean, f, ensure_ascii=False, indent=1)
            f.write("\n")

    for src, dst in moves:
        os.replace(src, dst)

    os.makedirs(WORK, exist_ok=True)
    refs = {}
    for vid in sorted({rec["voice"] for _, _, _, rec in pending}):
        v = cast[vid]
        wd = os.path.join(WORK, vid)
        os.makedirs(wd, exist_ok=True)
        ref = os.path.join(wd, "ref.wav")
        sig_path = os.path.join(wd, "ref.sig")
        sig = cast_sig(v)
        old_sig = open(sig_path).read().strip() if os.path.exists(sig_path) else ""
        if a.force_ref or not os.path.exists(ref) or old_sig != sig:
            t0 = time.time()
            x, seed, w = generate_checked(a, lambda sd: wf_design(a.model, v["ref_text"], v["instruct"], sd,
                                                                  float(v.get("speed", 1.0)), a.steps),
                                          v["ref_text"], int(v.get("seed", 0)), max_tries=max(a.tries, 8))
            write_wav(ref, x)
            open(sig_path, "w").write(sig)
            print(f"  {vid}: próbka głosu {len(x) / SR:.1f} s, seed {seed}{check_note(w)} ({time.time() - t0:.0f} s) -> {ref}",
                  flush=True)
        refs[vid] = upload_audio(a.server, ref, f"{vid}_ref.wav")

    t_all = time.time()
    weak = []
    for k, (d, n, i, rec) in enumerate(pending, 1):
        v = cast[rec["voice"]]
        t0 = time.time()
        t = rec["text"]
        x, seed, w = generate_checked(a, lambda sd: wf_clone(a.model, tts_text(t), refs[rec["voice"]], v["ref_text"], sd,
                                                             float(v.get("speed", 1.0)), a.steps),
                                      t, int(v.get("seed", 0)), max_tries=a.tries)
        dst = os.path.join(out_dir, d, rec["file"])
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        write_ogg(dst, x)
        rec.update(seconds=round(len(x) / SR, 2), seed=seed, wer=None if w is None else round(w, 3))
        new_manifest[f"{d}/{n}"].append(rec)
        if w is not None and w > 0.2 and len(t.split()) > 6:
            weak.append(f"{d}/{rec['file']}")
        save()
        print(f"  [{k}/{len(pending)}] {d}/{rec['file']} [{rec['voice']}]: {len(x) / SR:.1f} s{check_note(w)} "
              f"({time.time() - t0:.0f} s)", flush=True)
    save()

    # pliki, których manifest już nie zna (stary format, usunięte węzły, zmieniony podział)
    keep = {os.path.join(out_dir, k.split("/")[0], r["file"]) for k, v in new_manifest.items() for r in v}
    for p in glob.glob(os.path.join(out_dir, "*", "*.ogg")) + glob.glob(os.path.join(out_dir, "*", "*.wav")):
        if p not in keep:
            os.remove(p)
            for extra in (p + ".import",):
                if os.path.exists(extra):
                    os.remove(extra)
            print(f"  usunięto nieużywane {os.path.relpath(p, out_dir)}")
    if weak:
        print("UWAGA, fragmenty poniżej progu po wszystkich próbach (posłuchaj albo zmień tekst/obsadę):")
        for k in weak:
            print("  " + k)
    print(f"VOICE_OK {out_dir} ({time.time() - t_all:.0f} s)")


if __name__ == "__main__":
    main()
