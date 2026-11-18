#!/usr/bin/env python3
"""Generuje model 3D z obrazu przez API ComfyUI (Hunyuan3D-2) i zapisuje GLB.

Użycie: comfy_gen.py <obraz.png> <wyjście.glb> [--seed N] [--steps 30] [--octree 256]
        [--workflow plik.api.json] [--server http://127.0.0.1:8188]
"""
import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))

# Presety TRELLIS.2: kroki etapów (struktura, bryła, upsample, tekstura) i rozdzielczości.
PRESETS = {
    "draft": {"steps": {"14": 8, "19": 12, "21": 8, "24": 8}, "upsample": 1024, "remesh": 384,
              "texture": 1024, "faces": 15000, "ao": False},
    "final": {"steps": {"14": 12, "19": 20, "21": 12, "24": 12}, "upsample": 1024, "remesh": 512,
              "texture": 2048, "faces": 20000, "ao": True},
    "hero":  {"steps": {"14": 16, "19": 28, "21": 16, "24": 16}, "upsample": 1536, "remesh": 768,
              "texture": 4096, "faces": 30000, "ao": True},
}


def apply_preset(wf, name, faces=0, texture=0):
    pr = PRESETS[name]
    tex = texture or pr["texture"]
    for nid, steps in pr["steps"].items():
        if nid in wf and wf[nid]["class_type"] == "KSampler":
            wf[nid]["inputs"]["steps"] = steps
    for node in wf.values():
        ct, ins = node["class_type"], node["inputs"]
        if ct == "Trellis2UpsampleStage":
            ins["target_resolution"] = pr["upsample"]
        elif ct == "RemeshMesh":
            ins["resolution"] = pr["remesh"]
        elif ct == "DecimateMesh":
            ins["target_face_count"] = faces or pr["faces"]
        elif ct == "BakeTextureFromVoxel":
            ins["texture_size"] = tex
        elif ct in ("UnwrapMesh", "BakeNormalMapFromMesh"):
            ins["resolution"] = tex
    if not pr["ao"]:
        for nid, node in list(wf.items()):
            if node["class_type"] == "BakeAmbientOcclusion":
                del wf[nid]
                for other in wf.values():
                    for k, v in list(other["inputs"].items()):
                        if isinstance(v, list) and v and v[0] == nid:
                            del other["inputs"][k]


def req(server, path, data=None, headers=None):
    r = urllib.request.Request(server + path, data=data, headers=headers or {})
    with urllib.request.urlopen(r, timeout=60) as resp:
        return resp.read()


def upload(server, path):
    boundary = uuid.uuid4().hex
    name = os.path.basename(path)
    with open(path, "rb") as f:
        payload = f.read()
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"{name}\"\r\n"
            f"Content-Type: image/png\r\n\r\n").encode() + payload + \
           (f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue"
            f"\r\n--{boundary}--\r\n").encode()
    out = json.loads(req(server, "/upload/image", body, {"Content-Type": f"multipart/form-data; boundary={boundary}"}))
    return out["name"] if not out.get("subfolder") else out["subfolder"] + "/" + out["name"]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("image")
    p.add_argument("output")
    p.add_argument("--seed", type=int, default=int(time.time()) % 2**31)
    p.add_argument("--steps", type=int, default=30)
    p.add_argument("--octree", type=int, default=256)
    p.add_argument("--engine", choices=["trellis2", "hunyuan"], default="trellis2",
                   help="trellis2: geometria + tekstura PBR; hunyuan: sama geometria (szybciej)")
    p.add_argument("--preset", choices=list(PRESETS), default="draft",
                   help="trellis2: draft (szybki), final, hero (najwyższa jakość)")
    p.add_argument("--faces", type=int, default=0, help="nadpisz liczbę trójkątów presetu")
    p.add_argument("--texture", type=int, default=0, help="nadpisz rozdzielczość tekstury presetu")
    p.add_argument("--workflow", default="")
    p.add_argument("--server", default=os.environ.get("COMFY_URL", "http://127.0.0.1:8188"))
    a = p.parse_args()

    try:
        req(a.server, "/system_stats")
    except Exception as ex:
        sys.exit(f"ComfyUI nie odpowiada pod {a.server} ({ex}). Uruchom: tools/pipeline/pipeline.sh comfy")

    wf_path = a.workflow or os.path.join(HERE, {"trellis2": "trellis2_image_to_model.api.json",
                                                 "hunyuan": "hunyuan3d_image_to_model.api.json"}[a.engine])
    wf = json.load(open(wf_path))
    tag = os.path.splitext(os.path.basename(a.output))[0] + "_" + uuid.uuid4().hex[:6]
    for node in wf.values():
        ins = node["inputs"]
        if node["class_type"] == "LoadImage":
            ins["image"] = upload(a.server, a.image)
        if node["class_type"] == "KSampler":
            ins["seed"] = a.seed + int(ins.get("seed", 0))
            if a.engine == "hunyuan":
                ins["steps"] = a.steps

        if node["class_type"] == "VAEDecodeHunyuan3D":
            ins["octree_resolution"] = a.octree
        if "filename_prefix" in ins:
            ins["filename_prefix"] = ins["filename_prefix"].replace("OUTPUT", tag)

    if a.engine == "trellis2":
        apply_preset(wf, a.preset, a.faces, a.texture)

    client = uuid.uuid4().hex
    try:
        res = json.loads(req(a.server, "/prompt", json.dumps({"prompt": wf, "client_id": client}).encode(),
                             {"Content-Type": "application/json"}))
    except urllib.error.HTTPError as ex:
        sys.exit("Błąd walidacji workflow:\n" + ex.read().decode()[:3000])
    pid = res["prompt_id"]
    print(f"Zlecono {pid} (seed {a.seed}, {a.engine}{'/' + a.preset if a.engine == 'trellis2' else ''}), czekam…", flush=True)
    t0 = time.time()
    while True:
        time.sleep(2)
        hist = json.loads(req(a.server, "/history/" + pid))
        if pid not in hist:
            continue
        h = hist[pid]
        st = h.get("status", {})
        if st.get("status_str") == "error":
            msgs = [m for m in st.get("messages", []) if m[0] == "execution_error"]
            sys.exit("Błąd wykonania: " + json.dumps(msgs, ensure_ascii=False)[:3000])
        if st.get("completed"):
            break
    glb = None
    for out in h["outputs"].values():
        for key in ("3d", "result", "meshes", "files", "images"):
            for item in out.get(key, []) or []:
                if isinstance(item, dict) and str(item.get("filename", "")).endswith(".glb"):
                    glb = item
    if glb is None:
        sys.exit("Brak pliku GLB w wynikach: " + json.dumps(h["outputs"])[:2000])
    q = urllib.parse.urlencode({"filename": glb["filename"], "subfolder": glb.get("subfolder", ""), "type": glb.get("type", "output")})
    data = req(a.server, "/view?" + q)
    os.makedirs(os.path.dirname(os.path.abspath(a.output)), exist_ok=True)
    with open(a.output, "wb") as f:
        f.write(data)
    print(f"COMFY_OK {a.output} ({len(data)/1e6:.1f} MB, {time.time()-t0:.0f} s)")


if __name__ == "__main__":
    main()
