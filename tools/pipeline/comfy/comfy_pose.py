#!/usr/bin/env python3
"""Wykrywa punkty kluczowe pozy (DWPose, comfyui_controlnet_aux) i zapisuje JSON w formacie OpenPose.

Użycie: comfy_pose.py <obraz.png> <wyjście.json> [--server URL]
"""
import argparse
import json
import os
import sys
import urllib.parse
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comfy_gen import req, upload  # noqa: E402
from comfy_concept import run  # noqa: E402


def main():
    p = argparse.ArgumentParser()
    p.add_argument("image")
    p.add_argument("output")
    p.add_argument("--server", default=os.environ.get("COMFY_URL", "http://127.0.0.1:8188"))
    a = p.parse_args()
    name = upload(a.server, a.image)
    prefix = "zawias/pose_" + uuid.uuid4().hex[:8]
    wf = {
        "1": {"class_type": "LoadImage", "inputs": {"image": name}},
        "2": {"class_type": "DWPreprocessor", "inputs": {
            "image": ["1", 0], "detect_hand": "disable", "detect_body": "enable", "detect_face": "disable",
            "resolution": 1024, "bbox_detector": "yolox_l.torchscript.pt",
            "pose_estimator": "dw-ll_ucoco_384_bs5.torchscript.pt", "scale_stick_for_xinsr_cn": "disable"}},
        "3": {"class_type": "SavePoseKpsAsJsonFile", "inputs": {"pose_kps": ["2", 1], "filename_prefix": prefix}},
        "4": {"class_type": "SaveImage", "inputs": {"images": ["2", 0], "filename_prefix": prefix + "_vis"}},
    }
    run(a.server, wf)
    sub, base = os.path.split(prefix)
    q = urllib.parse.urlencode({"filename": base + "_00001_.json", "subfolder": sub, "type": "output"})
    try:
        data = req(a.server, "/view?" + q)
    except Exception:
        q = urllib.parse.urlencode({"filename": base + "_00001.json", "subfolder": sub, "type": "output"})
        data = req(a.server, "/view?" + q)
    kps = json.loads(data)
    people = kps[0].get("people", [])
    if not people:
        sys.exit("DWPose nie znalazł postaci na obrazie")
    with open(a.output, "w") as f:
        json.dump(kps, f)
    body = people[0]["pose_keypoints_2d"]
    found = sum(1 for i in range(18) if body[i * 3 + 2] > 0.3)
    print(f"POSE_OK {a.output} (punkty ciała: {found}/18)")


if __name__ == "__main__":
    main()
