#!/usr/bin/env python3
"""Muzyka przez ComfyUI + ACE-Step 1.5 turbo (MIT; repack Comfy-Org: Apache 2.0) -> assets/audio/music/<id>.wav.

Użycie: comfy_audio.py <lista.txt> [--only id1,id2] [--force] [--seed N] [--count 1]

Lista: jedna pozycja na linię:
  id [sekundy] [loop] [bpm=90] [key=D minor] [sig=4]: opis stylu (tagi po angielsku)
„loop” = pętla bez szwu (przenikanie końca w początek). Utwory są instrumentalne.
Przy --count > 1 warianty trafiają do work/audio/<id>_N.wav; do assets idzie pierwszy (albo wybierz --seed).
"""
import argparse
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
from audio_lib import SR, make_loop, normalize, write_wav, fade, trim_silence  # noqa: E402

KEYS = ["C", "C#", "Db", "D", "D#", "Eb", "E", "F", "F#", "Gb", "G", "G#", "Ab", "A", "A#", "Bb", "B"]


def parse(path):
    items = []
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        head, desc = line.split(":", 1)
        parts = head.split()
        it = {"id": parts[0], "seconds": 90.0, "loop": False, "bpm": 90, "key": "D minor", "sig": "4", "tags": desc.strip()}
        rest = " ".join(parts[1:])
        m = re.search(r"\[(\d+(?:\.\d+)?)\]", rest)
        if m:
            it["seconds"] = float(m.group(1))
        it["loop"] = "[loop]" in rest
        for k, v in re.findall(r"(\w+)=([^=]+?)(?=\s+\w+=|$)", rest.replace("[loop]", "").strip()):
            it[k] = int(v) if k == "bpm" else v.strip()
        items.append(it)
    return items


def workflow(it, seed):
    secs = it["seconds"] + (8.0 if it["loop"] else 4.0)   # zapas: przenikanie pętli i przycinanie ciszy
    return {
        "unet": {"class_type": "UNETLoader", "inputs": {"unet_name": "acestep_v1.5_turbo.safetensors", "weight_dtype": "default"}},
        "shift": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["unet", 0], "shift": 3.0}},
        "clip": {"class_type": "DualCLIPLoader", "inputs": {"clip_name1": "qwen_0.6b_ace15.safetensors",
                                                             "clip_name2": "qwen_1.7b_ace15.safetensors", "type": "ace", "device": "default"}},
        "vae": {"class_type": "VAELoader", "inputs": {"vae_name": "ace_1.5_vae.safetensors"}},
        "text": {"class_type": "TextEncodeAceStepAudio1.5", "inputs": {
            "clip": ["clip", 0], "tags": it["tags"], "lyrics": "[Instrumental]", "seed": seed, "bpm": int(it["bpm"]),
            "duration": secs, "timesignature": str(it["sig"]), "language": "en", "keyscale": it["key"],
            "generate_audio_codes": True, "cfg_scale": 2.0, "temperature": 0.85, "top_p": 0.9, "top_k": 0, "min_p": 0.0}},
        "neg": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["text", 0]}},
        "latent": {"class_type": "EmptyAceStep1.5LatentAudio", "inputs": {"seconds": secs, "batch_size": 1}},
        "sample": {"class_type": "KSampler", "inputs": {"model": ["shift", 0], "seed": seed, "steps": 8, "cfg": 1.0,
                                                        "sampler_name": "euler", "scheduler": "simple",
                                                        "positive": ["text", 0], "negative": ["neg", 0],
                                                        "latent_image": ["latent", 0], "denoise": 1.0}},
        "decode": {"class_type": "VAEDecodeAudio", "inputs": {"samples": ["sample", 0], "vae": ["vae", 0]}},
        "save": {"class_type": "SaveAudio", "inputs": {"audio": ["decode", 0], "filename_prefix": "zawias/music"}},
    }


def run(server, wf):
    res = json.loads(req(server, "/prompt", json.dumps({"prompt": wf, "client_id": uuid.uuid4().hex}).encode(),
                         {"Content-Type": "application/json"}))
    pid = res["prompt_id"]
    while True:
        time.sleep(1)
        hist = json.loads(req(server, "/history/" + pid))
        if pid not in hist:
            continue
        st = hist[pid].get("status", {})
        if st.get("status_str") == "error":
            sys.exit("Błąd wykonania: " + json.dumps(st.get("messages", []), ensure_ascii=False)[:3000])
        if st.get("completed"):
            return hist[pid]["outputs"]


def decode_audio(data):
    """FLAC z ComfyUI -> float (n, 2) w SR."""
    import av
    c = av.open(io.BytesIO(data))
    rs = av.AudioResampler(format="fltp", layout="stereo", rate=SR)
    chunks = []
    for fr in c.decode(audio=0):
        for o in rs.resample(fr):
            chunks.append(o.to_ndarray())
    return np.concatenate(chunks, axis=1).T.astype(np.float64)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("list")
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--seed", type=int, default=5)
    ap.add_argument("--count", type=int, default=1)
    ap.add_argument("--server", default=os.environ.get("COMFY_URL", "http://127.0.0.1:8188"))
    a = ap.parse_args()
    out_dir = os.path.join(ROOT, "assets", "audio", "music")
    work = os.path.join(PIPE, "work", "audio")
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(work, exist_ok=True)
    only = {s for s in a.only.split(",") if s}
    for it in parse(a.list):
        if only and it["id"] not in only:
            continue
        dst = os.path.join(out_dir, it["id"] + ".wav")
        if os.path.exists(dst) and not a.force:
            print(f"  {it['id']}: jest, pomijam")
            continue
        for i in range(a.count):
            t0 = time.time()
            outs = run(a.server, workflow(it, a.seed + i))
            f = next(x for o in outs.values() for x in o.get("audio", []))
            q = urllib.parse.urlencode({"filename": f["filename"], "subfolder": f.get("subfolder", ""), "type": f.get("type", "output")})
            x = decode_audio(req(a.server, "/view?" + q))
            x = trim_silence(x)
            x = make_loop(x, xfade=3.0) if it["loop"] else fade(x, fin=0.01, fout=2.0)
            x = normalize(x, peak_db=-1.0, rms_db=-18.0)
            path = os.path.join(work, f"{it['id']}_{i + 1}.wav")
            write_wav(path, x)
            print(f"  {it['id']}_{i + 1}: {len(x) / SR:.0f} s (seed {a.seed + i}, {time.time() - t0:.0f} s)", flush=True)
            if i == 0:
                write_wav(dst, x)
    print("AUDIO_OK", out_dir)


if __name__ == "__main__":
    main()
