#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Koncept postaci przez ComfyUI + FLUX.2 [klein] 4B (Apache 2.0).

Użycie:
  comfy_concept.py "<opis postaci>" <wyjście.png> [--ref styl.png ...] [--seed N] [--count 1]
                   [--width 896] [--height 1152] [--steps 4] [--raw]

Bez --raw opis jest wstawiany w szablon pod generator 3D i auto-rig (T-pose, przód, jasne tło, cała postać).
--ref: obrazy referencyjne (styl, poza, inna postać do zachowania spójności). W opisie możesz się
do nich odwoływać jako „image 1”, „image 2”.
"""
import argparse
import json
import os
import sys
import time
import urllib.parse
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comfy_gen import req, upload  # noqa: E402

STYLE = ("stylized hand-painted fantasy game character, muted rust, brass and deep violet palette, "
         "art nouveau ornament details, clean readable silhouette")
TEMPLATE = ("Full body character concept for 3D modeling: {desc}. Standing in a strict T-pose: both arms "
            "extended straight out to the sides at shoulder height, palms down, hands open and clearly separated from the "
            "body, legs straight and slightly apart, facing the camera, front view, whole figure "
            "visible from head to feet with margin, centered. Empty hands, no weapons, no held props, no cape. Plain flat light grey background, soft even "
            "studio lighting, no cast shadows, no props on the ground, no text. {style}.")


PROP_STYLE = ("stylized hand-painted fantasy game prop, muted rust, brass and deep violet palette, "
              "art nouveau ornament details, clean readable silhouette")
PROP_TEMPLATE = ("Single game prop concept for 3D modeling: {desc}. One isolated object only, three-quarter front view "
                 "from slightly above, the whole object visible with margin, centered, standing on nothing. Plain flat "
                 "light grey background, soft even studio lighting, no cast shadows, no people, no text. {style}.")


def build(prompt, refs, width, height, steps, seed, init=None, denoise=1.0, ref_mp=1.0):
    g = {
        "unet": {"class_type": "UNETLoader", "inputs": {"unet_name": "flux-2-klein-4b-fp8.safetensors", "weight_dtype": "default"}},
        "clip": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b.safetensors", "type": "flux2", "device": "default"}},
        "vae": {"class_type": "VAELoader", "inputs": {"vae_name": "flux2-vae.safetensors"}},
        "text": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["clip", 0], "text": prompt}},
        "zero": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["text", 0]}},
        "latent": {"class_type": "EmptyFlux2LatentImage", "inputs": {"width": width, "height": height, "batch_size": 1}},
        "sched": {"class_type": "Flux2Scheduler", "inputs": {"steps": steps, "width": width, "height": height}},
        "sampler": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "noise": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
    }
    pos, neg = ["text", 0], ["zero", 0]
    for i, name in enumerate(refs):
        g[f"ref{i}_img"] = {"class_type": "LoadImage", "inputs": {"image": name}}
        g[f"ref{i}_scale"] = {"class_type": "ImageScaleToTotalPixels", "inputs": {
            "image": [f"ref{i}_img", 0], "upscale_method": "lanczos", "megapixels": ref_mp, "resolution_steps": 1}}
        g[f"ref{i}_lat"] = {"class_type": "VAEEncode", "inputs": {"pixels": [f"ref{i}_scale", 0], "vae": ["vae", 0]}}
        g[f"ref{i}_pos"] = {"class_type": "ReferenceLatent", "inputs": {"conditioning": pos, "latent": [f"ref{i}_lat", 0]}}
        g[f"ref{i}_neg"] = {"class_type": "ReferenceLatent", "inputs": {"conditioning": neg, "latent": [f"ref{i}_lat", 0]}}
        pos, neg = [f"ref{i}_pos", 0], [f"ref{i}_neg", 0]
    latent, sigmas = ["latent", 0], ["sched", 0]
    if init:
        # img2img: start z obrazu (np. makiety), trzyma kompozycję mocniej niż sama referencja
        g["init_img"] = {"class_type": "LoadImage", "inputs": {"image": init}}
        g["init_scale"] = {"class_type": "ImageScale", "inputs": {
            "image": ["init_img", 0], "upscale_method": "lanczos", "width": width, "height": height, "crop": "disabled"}}
        g["init_lat"] = {"class_type": "VAEEncode", "inputs": {"pixels": ["init_scale", 0], "vae": ["vae", 0]}}
        g["split"] = {"class_type": "SplitSigmasDenoise", "inputs": {"sigmas": ["sched", 0], "denoise": denoise}}
        latent, sigmas = ["init_lat", 0], ["split", 1]
    g["guider"] = {"class_type": "CFGGuider", "inputs": {"model": ["unet", 0], "positive": pos, "negative": neg, "cfg": 1.0}}
    g["sample"] = {"class_type": "SamplerCustomAdvanced", "inputs": {
        "noise": ["noise", 0], "guider": ["guider", 0], "sampler": ["sampler", 0], "sigmas": sigmas, "latent_image": latent}}
    g["decode"] = {"class_type": "VAEDecode", "inputs": {"samples": ["sample", 0], "vae": ["vae", 0]}}
    g["save"] = {"class_type": "SaveImage", "inputs": {"images": ["decode", 0], "filename_prefix": "zawias/concept"}}
    return g


def run(server, wf):
    res = json.loads(req(server, "/prompt", json.dumps({"prompt": wf, "client_id": uuid.uuid4().hex}).encode(),
                         {"Content-Type": "application/json"}))
    pid = res["prompt_id"]
    while True:
        time.sleep(1)
        hist = json.loads(req(server, "/history/" + pid))
        if pid not in hist:
            continue
        h = hist[pid]
        st = h.get("status", {})
        if st.get("status_str") == "error":
            sys.exit("Błąd wykonania: " + json.dumps(st.get("messages", []), ensure_ascii=False)[:3000])
        if st.get("completed"):
            return h["outputs"]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("description")
    p.add_argument("output")
    p.add_argument("--ref", action="append", default=[])
    p.add_argument("--seed", type=int, default=int(time.time()) % 2**31)
    p.add_argument("--count", type=int, default=1, help="ile wariantów (kolejne seedy)")
    p.add_argument("--width", type=int, default=1152)
    p.add_argument("--height", type=int, default=1152)
    p.add_argument("--steps", type=int, default=4)
    p.add_argument("--init", help="obraz startowy (img2img)")
    p.add_argument("--denoise", type=float, default=0.75)
    p.add_argument("--raw", action="store_true", help="użyj opisu bez szablonu")
    p.add_argument("--kind", choices=["character", "prop"], default="character")
    p.add_argument("--server", default=os.environ.get("COMFY_URL", "http://127.0.0.1:8188"))
    a = p.parse_args()
    try:
        req(a.server, "/system_stats")
    except Exception as ex:
        sys.exit(f"ComfyUI nie odpowiada pod {a.server} ({ex}). Uruchom: tools/pipeline/pipeline.sh comfy")

    if a.raw:
        prompt = a.description
    elif a.kind == "prop":
        prompt = PROP_TEMPLATE.format(desc=a.description, style=PROP_STYLE)
    else:
        prompt = TEMPLATE.format(desc=a.description, style=STYLE)
    if a.ref and not a.raw:
        prompt += (" Match the art style, rendering technique, line quality and color palette of image 1 exactly,"
                   " but draw a completely different %s as described." % ("object" if a.kind == "prop" else "character"))
    refs = [upload(a.server, r) for r in a.ref]
    init = upload(a.server, a.init) if a.init else None
    root, ext = os.path.splitext(a.output)
    os.makedirs(os.path.dirname(os.path.abspath(a.output)) or ".", exist_ok=True)
    for i in range(a.count):
        seed = a.seed + i
        t0 = time.time()
        outputs = run(a.server, build(prompt, refs, a.width, a.height, a.steps, seed, init, a.denoise))
        img = next(it for o in outputs.values() for it in o.get("images", []))
        q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""), "type": img.get("type", "output")})
        path = a.output if a.count == 1 else f"{root}_{i + 1}{ext or '.png'}"
        with open(path, "wb") as f:
            f.write(req(a.server, "/view?" + q))
        print(f"CONCEPT_OK {path} (seed {seed}, {time.time() - t0:.0f} s)", flush=True)


if __name__ == "__main__":
    main()
