#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Kontrola SPDX/REUSE bez dodatkowych pakietów (odpowiednik `reuse lint` dla tego repo).

Każdy plik z repozytorium (śledzony albo nowy, nieignorowany) musi mieć licencję i prawa autorskie:
nagłówek `SPDX-License-Identifier` / `SPDX-FileCopyrightText` w pierwszych liniach albo wpis w REUSE.toml
(wzorce jak w REUSE: `*` bez `/`, `**` także przez katalogi; przy kilku dopasowaniach wygrywa ostatni).
Każdy użyty identyfikator licencji musi mieć tekst w LICENSES/<id>.txt.

Użycie: python3 tools/dev/spdx_check.py [--list]   (--list: licencja każdego pliku)
"""
import os
import re
import subprocess
import sys
import tomllib

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
IGNORED = re.compile(r"^(LICENSES/|LICENSE|COPYING|REUSE\.toml$|\.git/)")
HEADER_RE = re.compile(r"SPDX-License-Identifier:\s*([^\s*/]+(?:\s+(?:OR|AND|WITH)\s+[^\s*/]+)*)")
COPY_RE = re.compile(r"SPDX-FileCopyrightText:")


def glob_re(pat):
    out, i = "", 0
    while i < len(pat):
        if pat.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif pat.startswith("**", i):
            out += ".*"
            i += 2
        elif pat[i] == "*":
            out += "[^/]*"
            i += 1
        else:
            out += re.escape(pat[i])
            i += 1
    return re.compile("^" + out + "$")


def main():
    files = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard"],
                                    cwd=ROOT, text=True).split("\n")
    files = [f for f in files if f and os.path.isfile(os.path.join(ROOT, f)) and not IGNORED.match(f)]
    conf = tomllib.load(open(os.path.join(ROOT, "REUSE.toml"), "rb"))
    ann = []
    for a in conf.get("annotations", []):
        paths = a["path"] if isinstance(a["path"], list) else [a["path"]]
        ann.append(([glob_re(p) for p in paths], a))
    have = {os.path.splitext(f)[0] for f in os.listdir(os.path.join(ROOT, "LICENSES"))}
    missing, used, table = [], {}, []
    for f in files:
        lic = None
        try:
            head = open(os.path.join(ROOT, f), encoding="utf-8").read(1500)
        except (UnicodeDecodeError, OSError):
            head = ""
        m = HEADER_RE.search(head)
        if m and COPY_RE.search(head):
            lic, src = m.group(1), "nagłówek"
        for pats, a in ann:
            if any(p.match(f) for p in pats):
                if lic is None or a.get("precedence") == "override":
                    lic, src = a["SPDX-License-Identifier"], "REUSE.toml"
        if lic is None:
            missing.append(f)
            continue
        for lid in re.split(r"\s+(?:OR|AND|WITH)\s+", lic):
            used.setdefault(lid, 0)
            used[lid] += 1
        table.append((f, lic, src))
    if "--list" in sys.argv:
        for f, lic, src in table:
            print(f"{lic:14} {src:10} {f}")
    bad_ids = sorted(set(used) - have)
    unused = sorted(have - set(used))
    print("Licencje: " + ", ".join(f"{k} ({v})" for k, v in sorted(used.items())))
    if unused:
        print("Nieużywane teksty w LICENSES/: " + ", ".join(unused))
    if bad_ids:
        print("BRAK tekstu w LICENSES/ dla: " + ", ".join(bad_ids))
    if missing:
        print(f"BRAK licencji ({len(missing)}):")
        for f in missing[:60]:
            print("  " + f)
    ok = not missing and not bad_ids
    print(f"SPDX_{'OK' if ok else 'FAIL'}: {len(table)}/{len(files)} plików z licencją")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
