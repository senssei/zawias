#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Automatyczna kontrola obrazów lokalnym modelem wizyjnym (Ollama), zamiast ręcznego oglądania.

  qa_vlm.py concept <katalog work/id> [--kind character|prop]
      ocenia concept_1..N.png, najlepszy kopiuje do concept.png, raport w qa_concept.json
  qa_vlm.py facing <preview_0.png>
      czy model na podglądzie z przodu stoi przodem: front | back | side (wypisuje QA_FACING <wynik>)

Model: QA_MODEL (domyślnie Qwen3.5-9B z vision), serwer: OLLAMA_URL (http://127.0.0.1:11434).
Model zostaje w VRAM przez QA_KEEP (2m) między pytaniami; unload() zwalnia go od razu przed pracą ComfyUI.
"""
import argparse
import base64
import glob
import json
import os
import shutil
import sys
import urllib.request

OLLAMA = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
MODEL = os.environ.get("QA_MODEL", "hf.co/unsloth/Qwen3.5-9B-GGUF:Q4_K_M")
KEEP = os.environ.get("QA_KEEP", "2m")  # między pytaniami w jednej serii model zostaje w VRAM


def available():
    try:
        urllib.request.urlopen(OLLAMA + "/api/tags", timeout=3)
        return True
    except Exception:
        return False


def unload():
    """Zwalnia model z VRAM (przed FLUX/TRELLIS)."""
    try:
        r = urllib.request.Request(OLLAMA + "/api/generate", data=json.dumps({"model": MODEL, "keep_alive": 0}).encode(),
                                   headers={"Content-Type": "application/json"})
        urllib.request.urlopen(r, timeout=30).read()
    except Exception:
        pass


def free_comfy(server):
    """Prosi ComfyUI o zwolnienie modeli z VRAM (przed modelem wizyjnym)."""
    try:
        r = urllib.request.Request(server + "/free", data=json.dumps({"unload_models": True, "free_memory": True}).encode(),
                                   headers={"Content-Type": "application/json"})
        urllib.request.urlopen(r, timeout=30).read()
    except Exception:
        pass


def ask(prompt, image, schema, timeout=300):
    """Jedno pytanie o obraz; odpowiedź jako dict zgodny ze schematem JSON."""
    with open(image, "rb") as f:
        img = base64.b64encode(f.read()).decode()
    body = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt, "images": [img]}],
        "format": schema,
        "stream": False,
        "think": False,
        "keep_alive": KEEP,
        "options": {"temperature": 0},
    }
    r = urllib.request.Request(OLLAMA + "/api/chat", data=json.dumps(body).encode(),
                               headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=timeout) as resp:
        out = json.loads(resp.read())
    return json.loads(out["message"]["content"])


CONCEPT_SCHEMA = {
    "type": "object",
    "properties": {
        "single_figure": {"type": "boolean"},
        "full_body": {"type": "boolean"},
        "tpose": {"type": "boolean"},
        "hands_separated": {"type": "boolean"},
        "no_props": {"type": "boolean"},
        "plain_background": {"type": "boolean"},
        "problems": {"type": "string"},
    },
    "required": ["single_figure", "full_body", "tpose", "hands_separated", "no_props", "plain_background", "problems"],
}
CONCEPT_PROMPT = (
    "This image is a concept for converting into a 3D game character and auto-rigging it. Answer strictly:\n"
    "single_figure: exactly one character is shown.\n"
    "full_body: the whole figure from top of head to feet is visible, nothing cropped.\n"
    "tpose: both arms extend out to the sides roughly horizontally (T-pose or wide A-pose), legs straight.\n"
    "hands_separated: both hands are clearly away from the torso, hips and clothing, with background visible between.\n"
    "no_props: no weapons, staffs or objects held in hands, no backpack, satchel or bag on the back or shoulder, "
    "no cape or cloak hanging behind. If you mention any such item in problems, no_props must be false.\n"
    "plain_background: plain uniform background, no scenery.\n"
    "problems: a short note of anything else that would hurt 3D reconstruction, or empty."
)
PROP_SCHEMA = {
    "type": "object",
    "properties": {
        "single_object": {"type": "boolean"},
        "fully_visible": {"type": "boolean"},
        "plain_background": {"type": "boolean"},
        "no_people": {"type": "boolean"},
        "problems": {"type": "string"},
    },
    "required": ["single_object", "fully_visible", "plain_background", "no_people", "problems"],
}
PROP_PROMPT = (
    "This image is a concept for converting into a 3D game prop. Answer strictly:\n"
    "single_object: exactly one isolated object.\nfully_visible: the whole object is visible, nothing cropped.\n"
    "plain_background: plain uniform background.\nno_people: no people or creatures.\n"
    "problems: a short note of anything that would hurt 3D reconstruction, or empty."
)
WEIGHTS = {"single_figure": 3, "full_body": 3, "tpose": 2, "hands_separated": 2, "no_props": 1, "plain_background": 1,
           "single_object": 3, "fully_visible": 3, "no_people": 1}


def score(ans):
    return sum(w for k, w in WEIGHTS.items() if ans.get(k) is True)


def pick_concept(d, kind="character"):
    """Ocenia warianty concept_N.png w katalogu d, najlepszy kopiuje do concept.png. Zwraca (plik, wynik, max)."""
    cands = sorted(glob.glob(os.path.join(d, "concept_*.png")))
    if not cands:
        return None, 0, 0
    prompt, schema = (PROP_PROMPT, PROP_SCHEMA) if kind == "prop" else (CONCEPT_PROMPT, CONCEPT_SCHEMA)
    best_max = sum(WEIGHTS[k] for k in schema["properties"] if k in WEIGHTS)
    report = {}
    for c in cands:
        try:
            ans = ask(prompt, c, schema)
        except Exception as ex:  # noqa: BLE001
            ans = {"error": str(ex)}
        ans["score"] = score(ans)
        report[os.path.basename(c)] = ans
        print(f"QA_CONCEPT {os.path.basename(c)} {ans['score']}/{best_max} {ans.get('problems', ans.get('error', ''))[:120]}",
              flush=True)
    best = max(cands, key=lambda c: (report[os.path.basename(c)]["score"], -cands.index(c)))
    shutil.copyfile(best, os.path.join(d, "concept.png"))
    report["chosen"] = os.path.basename(best)
    with open(os.path.join(d, "qa_concept.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, ensure_ascii=False)
    return best, report[os.path.basename(best)]["score"], best_max


FACING_SCHEMA = {"type": "object", "properties": {"facing": {"type": "string", "enum": ["front", "back", "side"]}},
                 "required": ["facing"]}


def facing(image):
    """front | back | side dla renderu „z przodu”; None, gdy model nie odpowiada."""
    try:
        ans = ask("This is an orthographic render of a 3D game model taken from where its front should be. "
                  "Is the camera looking at the model's front (face, chest, or the decorated front side of an object), "
                  "its back (back of the head, back of the body), or its side? Answer front, back or side.",
                  image, FACING_SCHEMA)
        return ans.get("facing")
    except Exception as ex:  # noqa: BLE001
        print("QA_FACING błąd:", ex, file=sys.stderr)
        return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=["concept", "facing"])
    p.add_argument("path")
    p.add_argument("--kind", choices=["character", "prop"], default="character")
    a = p.parse_args()
    if not available():
        sys.exit(f"Ollama nie odpowiada pod {OLLAMA} (uruchom: ollama serve)")
    if a.mode == "concept":
        best, s, mx = pick_concept(a.path, a.kind)
        if not best:
            sys.exit("Brak concept_*.png w " + a.path)
        print(f"QA_PICK {os.path.basename(best)} ({s}/{mx}) -> concept.png")
    else:
        print("QA_FACING", facing(a.path))
    unload()


if __name__ == "__main__":
    main()
