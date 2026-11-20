#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Paczki wydania z buildów: dist/zawias-<wersja>-windows.zip i -linux.zip (z plikiem README i licencjami).
Wersja z project.godot (application/config/version). Użycie: python3 tools/release/package.py [--export]
--export najpierw eksportuje oba presety Godotem (GODOT, domyślnie ~/.local/bin/godot)."""
import os, re, stat, subprocess, sys, zipfile, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
version = re.search(r'config/version="([^"]+)"', (ROOT / "project.godot").read_text()).group(1)
godot = os.environ.get("GODOT", os.path.expanduser("~/.local/bin/godot"))
if "--export" in sys.argv:
    for preset, out in [("Windows", "build/windows/zawias.exe"), ("Linux", "build/linux/zawias.x86_64")]:
        subprocess.run([godot, "--headless", "--path", str(ROOT), "--export-release", preset, out], check=True)

README = f"""Zawias: A Tale of the Rusty Market {version}
A 2.5D isometric RPG on the D&D 2024 rules (SRD 5.2). English and Polish (Settings -> Language).

Run: zawias.exe (Windows) or ./zawias.x86_64 (Linux). Requires OpenGL 3.3.
Windows: the executable is not code-signed; if SmartScreen appears, choose "More info" -> "Run anyway".

Controls: left click move/talk/attack/target, right click cancel, WASD/arrows camera, wheel zoom,
C sheet, I inventory, J journal, L level up, R short rest, F5/F9 save/load, Space end turn, Esc close.

Saves and settings: %APPDATA%\\zawias (Windows), ~/.local/share/zawias (Linux).

Licenses: see LICENSES.txt. Rules: SRD 5.2 (c) Wizards of the Coast LLC, CC-BY-4.0.
This release is non-commercial (depth map made with Depth Anything V2 Large, CC-BY-NC-4.0).
"""

LICENSES = (ROOT / "LICENSE-SRD.md").read_text(encoding="utf-8")
if (ROOT / "LICENSE").exists():
    LICENSES = "== Code ==\n" + (ROOT / "LICENSE").read_text(encoding="utf-8") + "\n\n== Rules ==\n" + LICENSES
LICENSES += """

== Game assets and content ==
(c) 2026 Rafal Warzycha, Creative Commons Attribution 4.0 (CC-BY-4.0), except the backdrop depth map
(made with Depth Anything V2 Large): CC-BY-NC-4.0. SPDX metadata per file: REUSE.toml in the source repository.

== Third-party ==
Godot Engine (MIT) (c) Godot Engine contributors, Juan Linietsky, Ariel Manzur. Full notices: in-game Credits.
Quaternius Universal Animation Library (CC0).
Generated locally: FLUX.2 [klein] 4B (Apache 2.0), TRELLIS.2 (MIT), ACE-Step 1.5 (MIT), OmniVoice (Apache 2.0),
Depth Anything V2 Large (CC-BY-NC-4.0, non-commercial use only).
"""

dist = ROOT / "dist"
dist.mkdir(exist_ok=True)
for plat, exe in [("windows", "build/windows/zawias.exe"), ("linux", "build/linux/zawias.x86_64")]:
    src = ROOT / exe
    if not src.exists():
        sys.exit(f"Brak {src} (uruchom z --export)")
    out = dist / f"zawias-{version}-{plat}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        info = zipfile.ZipInfo(f"zawias-{version}/{src.name}", date_time=(2026, 11, 18, 12, 0, 0))
        info.external_attr = (stat.S_IFREG | 0o755) << 16   # bit wykonywalności dla Linuksa
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, src.read_bytes())
        z.writestr(f"zawias-{version}/README.txt", README)
        z.writestr(f"zawias-{version}/LICENSES.txt", LICENSES)
    print(f"PACKAGE_OK {out.relative_to(ROOT)} ({out.stat().st_size / 1e6:.0f} MB)")
