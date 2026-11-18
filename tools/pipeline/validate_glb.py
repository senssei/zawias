#!/usr/bin/env python3
"""Sprawdza GLB-y przed wrzuceniem do gry: budżet trójkątów, szkielet i animacje, tekstury, rozmiar pliku.

Użycie: validate_glb.py <plik.glb>... [--kind actor|prop] [--max-tris N] [--max-texture 1024] [--max-mb 6]
Kod wyjścia 0, gdy wszystkie pliki przechodzą. Linie: VALID_OK / VALID_FAIL <plik>: <powody>.
"""
import argparse
import json
import os
import struct
import sys

REQUIRED_ANIMS = ("idle", "walk", "attack", "cast", "hit", "death")
LIMITS = {"actor": {"tris": 12500, "mb": 6.0}, "prop": {"tris": 6500, "mb": 4.0}}


def read_glb(path):
    b = open(path, "rb").read()
    magic, _ver, _total = struct.unpack("<III", b[:12])
    if magic != 0x46546C67:
        raise ValueError("to nie jest GLB")
    n, kind = struct.unpack("<II", b[12:20])
    if kind != 0x4E4F534A:
        raise ValueError("brak bloku JSON")
    js = json.loads(b[20:20 + n])
    off = 20 + n
    binary = b[off + 8:] if len(b) > off + 8 else b""
    return js, binary


def png_size(data):
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    if data[:2] == b"\xff\xd8":  # JPEG: szukaj SOF
        i = 2
        while i < len(data) - 9:
            if data[i] != 0xFF:
                i += 1
                continue
            m = data[i + 1]
            if m in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", data[i + 5:i + 9])
                return w, h
            i += 2 + struct.unpack(">H", data[i + 2:i + 4])[0]
    return 0, 0


def stats(path):
    js, binary = read_glb(path)
    acc = js.get("accessors", [])
    tris = 0
    for m in js.get("meshes", []):
        for p in m["primitives"]:
            if "indices" in p:
                tris += acc[p["indices"]]["count"] // 3
            else:
                tris += acc[p["attributes"]["POSITION"]]["count"] // 3
    textures = []
    for im in js.get("images", []):
        if "bufferView" in im:
            bv = js["bufferViews"][im["bufferView"]]
            o = bv.get("byteOffset", 0)
            textures.append(png_size(binary[o:o + bv["byteLength"]]))
    mats = js.get("materials", [])
    return {
        "tris": tris,
        "skins": len(js.get("skins", [])),
        "anims": [a.get("name", "") for a in js.get("animations", [])],
        "textures": textures,
        "normal": any("normalTexture" in m for m in mats),
        "emissive": any("emissiveTexture" in m for m in mats),
        "mb": os.path.getsize(path) / 1e6,
    }


def check(path, kind, max_tris, max_tex, max_mb):
    try:
        s = stats(path)
    except Exception as ex:  # noqa: BLE001
        return False, [f"nie da się odczytać ({ex})"], {}
    bad = []
    if s["tris"] > max_tris:
        bad.append(f"{s['tris']} trójkątów > {max_tris}")
    if kind == "actor":
        if s["skins"] != 1:
            bad.append(f"skins={s['skins']} (oczekiwany 1)")
        missing = [a for a in REQUIRED_ANIMS if a not in s["anims"]]
        if missing:
            bad.append("brak animacji: " + ",".join(missing))
    big = [f"{w}x{h}" for w, h in s["textures"] if max(w, h) > max_tex]
    if big:
        bad.append(f"tekstury > {max_tex}: {' '.join(big)}")
    if not s["textures"]:
        bad.append("brak tekstur")
    if s["mb"] > max_mb:
        bad.append(f"{s['mb']:.1f} MB > {max_mb} MB")
    return not bad, bad, s


def main():
    p = argparse.ArgumentParser()
    p.add_argument("files", nargs="+")
    p.add_argument("--kind", choices=["actor", "prop"], default="actor")
    p.add_argument("--max-tris", type=int, default=0)
    p.add_argument("--max-texture", type=int, default=1024)
    p.add_argument("--max-mb", type=float, default=0)
    a = p.parse_args()
    lim = LIMITS[a.kind]
    ok_all = True
    for f in a.files:
        ok, bad, s = check(f, a.kind, a.max_tris or lim["tris"], a.max_texture, a.max_mb or lim["mb"])
        ok_all &= ok
        info = ""
        if s:
            tex = " ".join(f"{w}x{h}" for w, h in s["textures"])
            info = (f" [{s['tris']} tris, {len(s['anims'])} anim, tex {tex}"
                    f"{', normal' if s['normal'] else ''}{', emisja' if s['emissive'] else ''}, {s['mb']:.1f} MB]")
        print(f"{'VALID_OK' if ok else 'VALID_FAIL'} {f}{info}" + ("" if ok else ": " + "; ".join(bad)))
    sys.exit(0 if ok_all else 1)


if __name__ == "__main__":
    main()
