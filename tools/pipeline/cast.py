#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Wsadowe generowanie obsady: opis → koncept → model 3D → rig + animacje → assets/actors/<id>.glb.

Kolejność jest ułożona pod jedną kartę graficzną:
  faza A: wszystkie koncepty (FLUX.2 ładuje się raz),
  faza B: modele 3D jeden po drugim (TRELLIS.2 zostaje w VRAM); rig i klatki kontrolne
          poprzedniej postaci liczą się w tle w Blenderze (CPU), gdy GPU generuje następną.

Plik obsady: jedna postać na linię „id: opis”; puste linie i # są pomijane.

Rigger (--rigger): mixano (domyślnie, ~/repos/prototypes/mixano, < 1 s na postać, bez DWPose)
albo ual (dawna ścieżka: render przodu → DWPose → autorig_ual.py w Blenderze).
--qa: model wizyjny w Ollamie wybiera najlepszy z 3 konceptów i sprawdza, czy model stoi przodem.
Na końcu validate_glb.py sprawdza budżety (VALID_OK / VALID_FAIL).

Użycie: cast.py <obsada.txt> [--preset draft|final|hero] [--ref styl.png] [--only id1,id2]
                [--force] [--force-concept] [--seed N] [--rigger mixano|ual] [--qa]
                [--grade-ref styl.png] [--out-dir katalog] [--max-texture 1024]
                [--palette-strength 0.35] [--ao 0.8] [--tris N]

Budżet trójkątów: NPC 7000 (test 2026-11-18: w kadrze gry nie do odróżnienia od 12000), rekwizyty 6000.
Linia obsady może go zmienić: `bandit [tris=12000]: ...` (płaszcze i luźne tkaniny psują się przy 7000,
postacie gracza mają 12000).
"""
import argparse
import concurrent.futures
import glob
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.environ.get("WORK", os.path.join(HERE, "work"))
COMFY_URL = os.environ.get("COMFY_URL", "http://127.0.0.1:8188")
PY = sys.executable
UAL = os.path.join(HERE, "third_party", "ual", "UAL1_Standard.glb")
MIXANO_DIR = os.path.expanduser(os.environ.get("MIXANO_DIR", "~/repos/prototypes/mixano"))
NPC_TRIS = 7000
MIXANO = os.environ.get("MIXANO", os.path.join(MIXANO_DIR, "target", "release", "mixano"))
sys.path.insert(0, HERE)
import qa_vlm  # noqa: E402


def find_blender():
    if os.environ.get("BLENDER"):
        return os.environ["BLENDER"]
    if shutil.which("blender"):
        return "blender"
    cands = sorted(glob.glob("/mnt/c/Program Files/Blender Foundation/Blender */blender.exe"))
    if not cands:
        sys.exit("Nie znaleziono Blendera (ustaw BLENDER=...)")
    return cands[-1]


BLENDER = find_blender()


def bp(path):
    """Ścieżka w formacie zrozumiałym dla Blendera (Windows gdy blender.exe)."""
    path = os.path.abspath(path)
    if BLENDER.endswith(".exe"):
        return subprocess.check_output(["wslpath", "-w", path], text=True).strip()
    return path


def log(msg):
    print(time.strftime("[%H:%M:%S] ") + msg, flush=True)


def blender(steps, tag):
    """Uruchamia kroki w jednym procesie Blendera. Zwraca (ok, linie z markerami)."""
    os.makedirs(WORK, exist_ok=True)
    spec = os.path.join(WORK, f".steps_{tag}_{os.getpid()}_{time.time_ns()}.json")
    with open(spec, "w", encoding="utf-8") as f:
        json.dump([{"script": s, "args": a} for s, a in steps], f)
    out = subprocess.run([BLENDER, "-b", "--factory-startup", "--python", bp(os.path.join(HERE, "blender", "run_steps.py")),
                          "--", bp(spec)], capture_output=True, text=True, errors="replace")
    os.remove(spec)
    lines = [l for l in out.stdout.splitlines() if any(k in l for k in (
        "_OK", "STEP_FAILED", "STEPS_", "CLEANED", "FALLBACK", "SMOOTH", "BRAK", "Error", "Traceback"))]
    return "STEPS_DONE" in out.stdout, lines


def run(cmd):
    out = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    tail = (out.stdout + out.stderr).strip().splitlines()[-3:]
    return out.returncode == 0, tail


def comfy_up():
    try:
        urllib.request.urlopen(COMFY_URL + "/system_stats", timeout=3)
        return True
    except Exception:
        return False


def parse_cast(path):
    """Linie „id: opis” albo „id [wysokość] / [wysokość glow]: opis” → (id, opis, wysokość, glow)."""
    chars = []
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        cid, desc = line.split(":", 1)
        cid, height, glow, tris = cid.strip(), 0.0, False, 0
        if "[" in cid and cid.endswith("]"):
            cid, spec = cid[:-1].split("[", 1)
            cid = cid.strip()
            for tok in spec.replace(",", " ").split():
                if tok == "glow":
                    glow = True
                elif tok.startswith("tris="):
                    tris = int(tok[5:])
                else:
                    height = float(tok)
        chars.append((cid, desc.strip(), height, glow, tris))
    return chars


def rig_job(cid, out_glb=None):
    """Faza tła: auto-rig + klatki kontrolne (CPU, Blender)."""
    d = os.path.join(WORK, cid)
    out_glb = out_glb or os.path.join(ROOT, "assets", "actors", cid + ".glb")
    t0 = time.time()
    shutil.rmtree(os.path.join(d, "qa"), ignore_errors=True)
    ok, lines = blender([
        ("autorig_ual.py", [bp(os.path.join(d, "mesh.fbx")), bp(os.path.join(d, "pose.json")),
                            bp(os.path.join(d, "front.json")), bp(UAL), bp(out_glb)]),
        ("render_anims.py", [bp(out_glb), bp(os.path.join(d, "qa"))]),
    ], cid + "_rig")
    if ok:
        run([PY, os.path.join(HERE, "comfy", "qa_sheet.py"), os.path.join(d, "qa"), os.path.join(d, "qa_sheet.png")])
    return cid, ok, time.time() - t0, lines


def ensure_mixano():
    if not os.path.exists(MIXANO):
        log(f"Buduję mixano ({MIXANO_DIR})")
        subprocess.run(["cargo", "build", "--release"], cwd=MIXANO_DIR, check=True)
    return MIXANO


def prep_args(d, out, height=0.0, tris=12000, max_texture=1024, grade_ref="", rotate=0, glow=False,
              palette=0.35, ao=0.8):
    args = [bp(os.path.join(d, "model.glb")), bp(out), "--tris", str(tris), "--max-texture", str(max_texture),
            "--preview", bp(os.path.join(d, "preview.png")), "--ao", str(ao), "--palette-strength", str(palette)]
    if height:
        args += ["--height", str(height)]
    if grade_ref:
        args += ["--grade-ref", bp(grade_ref)]
    if rotate:
        args += ["--rotate-z", str(rotate)]
    if glow:
        args.append("--glow")
    return args


def prep_with_qa(cid, out, qa, tag, **kw):
    """prep w Blenderze; z --qa model wizyjny sprawdza podgląd i odwraca model, gdy stoi tyłem.
    Zwraca (ok, linie, facing) — facing to "front" po potwierdzeniu, inaczej None."""
    d = os.path.join(WORK, cid)
    ok, lines = blender([("prep_for_rig.py", prep_args(d, out, **kw))], tag)
    if not ok or not qa:
        return ok, lines, None
    f = qa_vlm.facing(os.path.join(d, "preview_0.png"))
    if f == "back":
        log(f"  {cid}: QA_ROTATED model stał tyłem, prep z --rotate-z 180")
        ok, lines = blender([("prep_for_rig.py", prep_args(d, out, rotate=180, **kw))], tag + "_rot")
        f = qa_vlm.facing(os.path.join(d, "preview_0.png")) if ok else None
    elif f == "side":
        log(f"  {cid}: QA_WARN podgląd z boku, sprawdź work/{cid}/preview_0.png")
    return ok, lines, ("front" if f == "front" else None)


def mixano_rig(cid, out_glb, max_texture=1024, facing=None):
    """mixano: work/<id>/mesh.glb → GLB z animacjami gry + arkusze kontrolne."""
    d = os.path.join(WORK, cid)
    t0 = time.time()
    os.makedirs(os.path.dirname(out_glb), exist_ok=True)
    cmd = [ensure_mixano(), "rig", os.path.join(d, "mesh.glb"), "-o", out_glb, "--preset", "planescape",
           "--anims-from", UAL, "--max-texture", str(max_texture)]
    if facing == "front":
        cmd += ["--facing", "+z"]  # prep eksportuje przód Blendera (−Y) jako +Z glTF
    ok, tail = run(cmd)
    if ok:
        run([MIXANO, "preview", out_glb, "-o", os.path.join(d, "qa_sheet.png"), "-a", "attack", "--frames", "6",
             "--size", "220", "--yaw", "35"])
        run([MIXANO, "preview", out_glb, "-o", os.path.join(d, "qa_weights.png"), "-a", "idle", "--time", "0.6",
             "--bones", "--weights", "--size", "300"])
    return cid, ok, time.time() - t0, tail


def validate(paths, kind, max_texture):
    if not paths:
        return {}
    out = subprocess.run([PY, "-I", os.path.join(HERE, "validate_glb.py"), *paths, "--kind",
                          "prop" if kind == "prop" else "actor", "--max-texture", str(max_texture)],
                         capture_output=True, text=True, errors="replace")
    res = {}
    for line in out.stdout.splitlines():
        log("  " + line.replace(ROOT + os.sep, ""))
        tag, _, rest = line.partition(" ")
        path = rest.split(" [")[0].split(": ")[0]
        res[os.path.splitext(os.path.basename(path))[0]] = tag == "VALID_OK"
    return res


def cast_tris(cid):
    """Budżet z linii obsady (`id [tris=N]: ...`) w dowolnym cast/*.txt, inaczej NPC_TRIS."""
    for f in sorted(glob.glob(os.path.join(HERE, "cast", "*.txt"))):
        for c in parse_cast(f):
            if c[0] == cid and c[4]:
                return c[4]
    return NPC_TRIS


def rig_single_mixano(cid, qa=False, grade_ref="", tris=0):
    d = os.path.join(WORK, cid)
    if not os.path.exists(os.path.join(d, "model.glb")):
        sys.exit(f"Brak {d}/model.glb (najpierw gen)")
    if qa and not qa_vlm.available():
        log("QA: Ollama nie odpowiada, pomijam kontrolę")
        qa = False
    tris = tris or cast_tris(cid)
    log(f"{cid}: budżet {tris} trójkątów")
    ok, lines, facing = prep_with_qa(cid, os.path.join(d, "mesh.glb"), qa, cid + "_prep", grade_ref=grade_ref, tris=tris)
    if not ok:
        sys.exit(f"prep BŁĄD {lines[-3:]}")
    out_glb = os.path.join(ROOT, "assets", "actors", cid + ".glb")
    cid, ok, dt, tail = mixano_rig(cid, out_glb, facing=facing)
    log(f"RIG_{'OK' if ok else 'BŁĄD'} {cid} ({dt:.1f} s) → assets/actors/{cid}.glb, kontrola: work/{cid}/qa_sheet.png"
        + ("" if ok else f" {tail}"))
    if ok:
        validate([out_glb], "character", 1024)
    sys.exit(0 if ok else 1)


def rig_single(cid):
    """Sam rig dla istniejącego work/<id>/mesh.fbx: render przodu → DWPose → auto-rig + kontrola."""
    d = os.path.join(WORK, cid)
    if not os.path.exists(os.path.join(d, "mesh.fbx")):
        sys.exit(f"Brak {d}/mesh.fbx (najpierw gen albo prep)")
    if not comfy_up():
        subprocess.run([os.path.join(HERE, "pipeline.sh"), "comfy"], check=True)
    ok, lines = blender([("render_front.py", [bp(os.path.join(d, "mesh.fbx")), bp(os.path.join(d, "front.png"))])], cid + "_front")
    if not ok:
        sys.exit(f"Render przodu BŁĄD {lines}")
    ok, tail = run([PY, os.path.join(HERE, "comfy", "comfy_pose.py"), os.path.join(d, "front.png"),
                    os.path.join(d, "pose.json"), "--server", COMFY_URL])
    log(" ".join(tail[-1:]))
    if not ok:
        sys.exit(f"Poza BŁĄD {tail}")
    cid, ok, dt, lines = rig_job(cid)
    for l in lines:
        log("  " + l[:200])
    log(f"RIG_{'OK' if ok else 'BŁĄD'} {cid} ({dt:.0f} s) → assets/actors/{cid}.glb, kontrola: work/{cid}/qa_sheet.png")
    sys.exit(0 if ok else 1)


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--rig":
        rest = sys.argv[3:]
        if "ual" in rest:
            rig_single(sys.argv[2])
        grade = rest[rest.index("--grade-ref") + 1] if "--grade-ref" in rest else ""
        tris = int(rest[rest.index("--tris") + 1]) if "--tris" in rest else 0
        rig_single_mixano(sys.argv[2], qa="--qa" in rest, grade_ref=grade, tris=tris)
    p = argparse.ArgumentParser()
    p.add_argument("cast")
    p.add_argument("--preset", choices=["draft", "final", "hero"], default="draft")
    p.add_argument("--ref", default="", help="obraz referencyjny stylu dla konceptów")
    p.add_argument("--only", default="", help="lista id oddzielona przecinkami")
    p.add_argument("--force", action="store_true", help="generuj model ponownie, nawet gdy istnieje")
    p.add_argument("--force-concept", action="store_true", help="generuj koncepty ponownie")
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--kind", choices=["character", "prop"], default="character",
                   help="prop: rekwizyty bez riggingu → assets/props/<id>.glb (wysokość w pliku: id [2.2]: opis)")
    p.add_argument("--rigger", choices=["mixano", "ual"], default="mixano")
    p.add_argument("--qa", action="store_true", help="kontrola modelem wizyjnym (Ollama): wybór konceptu, kierunek modelu")
    p.add_argument("--grade-ref", default="", help="obraz referencyjny palety dla tekstur (np. work/mirela/concept.png)")
    p.add_argument("--out-dir", default="", help="katalog wynikowy zamiast assets/actors|props")
    p.add_argument("--max-texture", type=int, default=1024)
    p.add_argument("--palette-strength", type=float, default=0.35, help="stała paleta z palette.json (0 = wyłączona)")
    p.add_argument("--tris", type=int, default=0, help="budżet trójkątów dla całej listy (domyślnie NPC 7000, rekwizyt 6000)")
    p.add_argument("--ao", type=float, default=0.8, help="wypalenie AO w kolor bazowy (działa przy --preset final/hero)")
    a = p.parse_args()
    out_dir = a.out_dir or os.path.join(ROOT, "assets", "props" if a.kind == "prop" else "actors")
    out_dir = os.path.abspath(out_dir)
    if a.qa and not qa_vlm.available():
        log("QA: Ollama nie odpowiada, kontrola wyłączona")
        a.qa = False
    if a.rigger == "mixano" and a.kind == "character":
        ensure_mixano()

    chars = parse_cast(a.cast)
    if a.only:
        keep = {x.strip() for x in a.only.split(",")}
        chars = [c for c in chars if c[0] in keep]
    if not chars:
        sys.exit("Pusta obsada")
    if not comfy_up():
        subprocess.run([os.path.join(HERE, "pipeline.sh"), "comfy"], check=True)
    t_start = time.time()
    results = {}

    # --- faza A: koncepty
    log(f"Faza A: koncepty ({len(chars)} postaci)")
    qa_todo = []
    for i, (cid, desc, *_rest) in enumerate(chars):
        d = os.path.join(WORK, cid)
        os.makedirs(d, exist_ok=True)
        concept = os.path.join(d, "concept.png")
        if os.path.exists(concept) and not a.force_concept:
            log(f"  {cid}: koncept istnieje, pomijam")
            continue
        cmd = [PY, os.path.join(HERE, "comfy", "comfy_concept.py"), desc, concept, "--seed", str(a.seed + i),
               "--server", COMFY_URL, "--kind", a.kind]
        if a.kind == "prop":
            cmd += ["--width", "1024", "--height", "1024"]
        if a.ref:
            cmd += ["--ref", a.ref]
        if a.qa:
            cmd += ["--count", "3"]
        ok, tail = run(cmd)
        log(f"  {cid}: {'OK' if ok else 'BŁĄD'} {tail[-1] if tail else ''}")
        if not ok:
            results[cid] = ("koncept", False)
        elif a.qa:
            qa_todo.append(cid)

    if qa_todo:
        log(f"QA konceptów ({len(qa_todo)}): model wizyjny wybiera najlepszy z 3")
        qa_vlm.free_comfy(COMFY_URL)
        for cid in qa_todo:
            best, sc, mx = qa_vlm.pick_concept(os.path.join(WORK, cid), a.kind)
            log(f"  {cid}: {os.path.basename(best) if best else '?'} ({sc}/{mx})"
                + ("  QA_WARN słaby koncept, sprawdź ręcznie" if best and sc < mx - 2 else ""))
        qa_vlm.unload()

    # --- faza B: modele 3D na GPU, rig w tle
    log(f"Faza B: modele 3D (TRELLIS.2/{a.preset}) + rig w tle")
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)
    facing_jobs = []  # (id, wynik prep, wynik końcowy, argumenty prep) do kontroli kierunku po fazie B
    futures = []
    for i, (cid, _desc, height, glow, tris) in enumerate(chars):
        tris = tris or a.tris or (6000 if a.kind == "prop" else NPC_TRIS)
        if cid in results:
            continue
        d = os.path.join(WORK, cid)
        out_glb = os.path.join(out_dir, cid + ".glb")
        if os.path.exists(out_glb) and not a.force:
            log(f"  {cid}: {out_glb} istnieje, pomijam (--force, żeby nadpisać)")
            continue
        t0 = time.time()
        ok, tail = run([PY, os.path.join(HERE, "comfy", "comfy_gen.py"), os.path.join(d, "concept.png"),
                        os.path.join(d, "model.glb"), "--engine", "trellis2", "--preset", a.preset,
                        "--seed", str(a.seed + i), "--server", COMFY_URL])
        if not ok:
            log(f"  {cid}: model 3D BŁĄD {tail}")
            results[cid] = ("model", False)
            continue
        t_model = time.time() - t0
        if a.kind == "prop":
            os.makedirs(out_dir, exist_ok=True)
            kw = dict(height=height or 1.0, tris=tris, max_texture=a.max_texture, grade_ref=a.grade_ref, glow=glow,
                      palette=a.palette_strength, ao=a.ao)
            ok, lines, _f = prep_with_qa(cid, out_glb, False, cid + "_prop", **kw)
            results[cid] = ("prep", ok)
            if ok:
                facing_jobs.append((cid, out_glb, out_glb, kw))
            log(f"  {cid}: model {t_model:.0f} s, rekwizyt {'OK' if ok else 'BŁĄD'} → {out_glb}"
                + ("" if ok else f" {lines[-3:]}"))
            continue
        if a.rigger == "mixano":
            kw = dict(tris=tris, max_texture=a.max_texture, grade_ref=a.grade_ref, palette=a.palette_strength, ao=a.ao)
            ok, lines, facing = prep_with_qa(cid, os.path.join(d, "mesh.glb"), False, cid + "_prep", **kw)
            if not ok:
                log(f"  {cid}: prep BŁĄD {lines[-3:]}")
                results[cid] = ("prep", False)
                continue
            cid, ok, dt, tail = mixano_rig(cid, out_glb, a.max_texture, facing)
            results[cid] = ("rig", ok)
            if ok:
                facing_jobs.append((cid, os.path.join(d, "mesh.glb"), out_glb, kw))
            log(f"  {cid}: model {t_model:.0f} s, rig mixano {'OK' if ok else 'BŁĄD'} ({dt:.1f} s)" + ("" if ok else f" {tail}"))
            continue
        ok, lines = blender([
            ("prep_for_rig.py", [bp(os.path.join(d, "model.glb")), bp(os.path.join(d, "mesh.fbx")),
                                 "--tris", str(tris), "--preview", bp(os.path.join(d, "preview.png"))]),
            ("render_front.py", [bp(os.path.join(d, "mesh.fbx")), bp(os.path.join(d, "front.png"))]),
        ], cid + "_prep")
        if not ok:
            log(f"  {cid}: prep BŁĄD {lines[-3:]}")
            results[cid] = ("prep", False)
            continue
        ok, tail = run([PY, os.path.join(HERE, "comfy", "comfy_pose.py"), os.path.join(d, "front.png"),
                        os.path.join(d, "pose.json"), "--server", COMFY_URL])
        if not ok:
            log(f"  {cid}: poza BŁĄD {tail}")
            results[cid] = ("poza", False)
            continue
        log(f"  {cid}: model {t_model:.0f} s, {tail[-1] if tail else ''}; rig w tle")
        futures.append(pool.submit(rig_job, cid, out_glb))

    for fut in concurrent.futures.as_completed(futures):
        cid, ok, dt, lines = fut.result()
        results[cid] = ("rig", ok)
        log(f"  {cid}: rig {'OK' if ok else 'BŁĄD'} ({dt:.0f} s)" + ("" if ok else f" {lines[-4:]}"))
    pool.shutdown()
    if a.qa and facing_jobs:
        # Po fazie B: TRELLIS zwolniony, model wizyjny ma kartę dla siebie.
        log(f"QA kierunku ({len(facing_jobs)} modeli)")
        qa_vlm.free_comfy(COMFY_URL)
        for cid, prep_out, out_glb, kw in facing_jobs:
            f = qa_vlm.facing(os.path.join(WORK, cid, "preview_0.png"))
            if f != "back":
                log(f"  {cid}: {f or '?'}" + ("  QA_WARN sprawdź work/%s/preview_0.png" % cid if f == "side" else ""))
                continue
            ok, lines = blender([("prep_for_rig.py", prep_args(os.path.join(WORK, cid), prep_out, rotate=180, **kw))],
                                cid + "_rot")
            if ok and a.kind == "character" and a.rigger == "mixano":
                _c, ok, _dt, _t = mixano_rig(cid, out_glb, a.max_texture, "front")
            results[cid] = ("QA obrót", ok)
            log(f"  {cid}: QA_ROTATED stał tyłem, prep z --rotate-z 180 {'OK' if ok else 'BŁĄD'}")
        qa_vlm.unload()

    done = [os.path.join(out_dir, c + ".glb") for c, (_, ok) in results.items() if ok]
    if done:
        log("Walidacja GLB")
        for c, valid in validate(done, a.kind, a.max_texture).items():
            if not valid:
                results[c] = ("walidacja", False)

    total = time.time() - t_start
    good = [c for c, (_, ok) in results.items() if ok]
    bad = {c: stage for c, (stage, ok) in results.items() if not ok}
    log(f"CAST_DONE {len(good)} gotowych, {len(bad)} błędów, {total / 60:.1f} min"
        + (f" (błędy: {bad})" if bad else ""))
    for c in good:
        check = "preview_1.png" if a.kind == "prop" else "qa_sheet.png"
        log(f"  {os.path.join(out_dir, c + '.glb')}  (kontrola: {os.path.join(WORK, c, check)})")


if __name__ == "__main__":
    main()
