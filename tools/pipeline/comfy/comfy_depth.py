#!/usr/bin/env python3
"""Mapa głębi (Depth Anything V2, względna: jaśniej = bliżej) dla obrazu przez ComfyUI.

Użycie: comfy_depth.py <wejście.png> <wyjście.png> [--resolution 1024] [--ckpt depth_anything_v2_vitl.pth]
"""
import argparse
import os
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comfy_gen import req, upload  # noqa: E402
from comfy_concept import run  # noqa: E402


def main():
    p = argparse.ArgumentParser()
    p.add_argument("input")
    p.add_argument("output")
    p.add_argument("--resolution", type=int, default=1024)
    p.add_argument("--ckpt", default="depth_anything_v2_vitl.pth")
    p.add_argument("--server", default=os.environ.get("COMFY_URL", "http://127.0.0.1:8188"))
    a = p.parse_args()
    name = upload(a.server, a.input)
    wf = {
        "img": {"class_type": "LoadImage", "inputs": {"image": name}},
        "depth": {"class_type": "DepthAnythingV2Preprocessor", "inputs": {
            "image": ["img", 0], "ckpt_name": a.ckpt, "resolution": a.resolution}},
        "save": {"class_type": "SaveImage", "inputs": {"images": ["depth", 0], "filename_prefix": "zawias/depth"}},
    }
    outputs = run(a.server, wf)
    img = next(it for o in outputs.values() for it in o.get("images", []))
    q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""), "type": img.get("type", "output")})
    with open(a.output, "wb") as f:
        f.write(req(a.server, "/view?" + q))
    print("DEPTH_OK", a.output, flush=True)


if __name__ == "__main__":
    main()
