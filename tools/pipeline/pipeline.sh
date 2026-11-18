#!/usr/bin/env bash
# Pipeline modeli postaci: wygenerowany model -> Mixamo -> GLB w grze.
#
#   ./pipeline.sh comfy
#       uruchamia ComfyUI w tle (czysty LD_LIBRARY_PATH, żeby cuDNN z venv nie kolidował z ~/.local)
#   ./pipeline.sh concept "<opis>" <id> [--count 4] [--seed N] [--ref styl.png]
#       FLUX.2 klein: opis -> work/<id>/concept[_N].png (A-pose, przód, jasne tło)
#   ./pipeline.sh castgen "<opis po polsku>" cast/<plik>.txt [--kind prop] [--context data/maps/x.json ...] [--dry-run]
#       lokalny LLM (Ollama) dopisuje linie obsady zgodne z szablonem konceptu i bez nazw cudzych settingów
#   ./pipeline.sh cast <obsada.txt> [--preset draft|final|hero] [--ref styl.png] [--only a,b] [--force]
#                 [--rigger mixano|ual] [--qa] [--grade-ref styl.png] [--out-dir dir] [--max-texture 1024]
#                 [--tris N]   (budżet: NPC 7000, linia `id [tris=12000]: ...` go zmienia)
#       wsadowo cała obsada (linie „id: opis”): koncepty -> modele 3D (GPU) -> cleanup -> rig (mixano) -> walidacja
#   ./pipeline.sh character "<opis>" <id> [--preset ...] [--ref styl.png]
#       jedna postać: opis -> koncept -> model z teksturą -> rig + animacje -> assets/actors/<id>.glb
#   ./pipeline.sh rig <id> [--qa] [--grade-ref styl.png] [--tris N] [ual]
#       prep + rig mixano (UAL, CC0): work/<id>/model.glb -> assets/actors/<id>.glb; `ual` = dawny rig przez DWPose + Blender
#   ./pipeline.sh validate <plik.glb>... [--kind actor|prop]
#       budżet trójkątów, szkielet i animacje gry, rozmiar tekstur i pliku
#   ./pipeline.sh gen <koncept.png> <id> [--engine trellis2|hunyuan] [--preset draft|final|hero] [--seed N]
#       ComfyUI: obraz -> work/<id>/model.glb (TRELLIS.2: z teksturą PBR), potem automatycznie prep + podgląd
#   ./pipeline.sh prep <model.glb|obj|fbx> <id> [--height 1.8] [--tris 12000] [--rotate-z 0]
#       -> work/<id>/mesh.fbx
#   ./pipeline.sh assemble <id> [--tris 0]   (alternatywa: rig z Mixamo)
#       work/<id>/mixamo/{base,idle,walk,attack,cast,hit,death}.fbx -> assets/actors/<id>.glb
#   ./pipeline.sh paint <map_id> [--tiles 3x3] [--only N --seed S] [--from shots|paint|stitch|depth] [--theme "..."]
#       malowany obszar całej mapy: makieta -> kafelki FLUX.2 (bez rekwizytów) -> sklejenie -> głębia -> assets/backgrounds/
#   ./pipeline.sh portraits <obsada.txt> [--kind prop] [--only a,b] [--force] [--count 3]
#       portrety do dialogów z konceptów (work/<id>/concept.png) -> assets/portraits/<id>.png
#   ./pipeline.sh music [lista.txt] [--only id] [--force] [--count 2]
#       muzyka ACE-Step 1.5 (domyślnie cast/audio_music.txt) -> assets/audio/music/<id>.wav (pętle bez szwu)
#   ./pipeline.sh sfx [--only id]
#       proceduralne efekty i ambient (bez próbek) -> assets/audio/sfx, assets/audio/ambient
#   ./pipeline.sh test
#       pełny test na wygenerowanej postaci testowej (bez Mixamo)
#
# BLENDER: ścieżka do blendera (domyślnie Blender 5.2 z Windowsa albo `blender` z PATH)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="${WORK:-$HERE/work}"

if [[ -z "${BLENDER:-}" ]]; then
  if command -v blender >/dev/null; then BLENDER=blender
  else BLENDER="$(ls -d /mnt/c/Program\ Files/Blender\ Foundation/Blender\ */blender.exe 2>/dev/null | sort -V | tail -1)"; fi
fi
[[ -x "$BLENDER" || -n "$(command -v "$BLENDER" 2>/dev/null)" ]] || { echo "Nie znaleziono Blendera (ustaw BLENDER=...)"; exit 1; }

# Blender z Windowsa potrzebuje ścieżek w formacie Windows
p() { if [[ "$BLENDER" == *.exe ]]; then wslpath -w "$(realpath -m "$1")"; else realpath -m "$1"; fi; }

run_blender() {
  local script="$1"; shift
  "$BLENDER" -b --factory-startup --python "$(p "$HERE/blender/$script")" -- "$@" 2>&1 \
    | grep -E "_OK|GAMMA_FIX|CLEANED|FALLBACK|SMOOTH|BRAK|Error|ERROR|Traceback|POMINIĘTO|^  File|SystemExit" || true
}

COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"
COMFY_URL="${COMFY_URL:-http://127.0.0.1:8188}"

comfy_up() { curl -s -m 2 "$COMFY_URL/system_stats" >/dev/null; }

cmd="${1:-}"; shift || true
case "$cmd" in
  comfy)
    if comfy_up; then echo "ComfyUI już działa: $COMFY_URL"; exit 0; fi
    mkdir -p "$WORK"
    (cd "$COMFY_DIR" && LD_LIBRARY_PATH=/usr/lib/wsl/lib nohup .venv/bin/python main.py --listen 127.0.0.1 --port 8188 > "$WORK/comfy.log" 2>&1 &)
    for _ in $(seq 1 60); do sleep 2; comfy_up && { echo "ComfyUI działa: $COMFY_URL (log: $WORK/comfy.log)"; exit 0; }; done
    echo "ComfyUI nie wystartował, zajrzyj do $WORK/comfy.log"; exit 1
    ;;
  concept)
    desc="$1"; id="$2"; shift 2
    comfy_up || "$0" comfy
    mkdir -p "$WORK/$id"
    "$COMFY_DIR/.venv/bin/python" "$HERE/comfy/comfy_concept.py" "$desc" "$WORK/$id/concept.png" --server "$COMFY_URL" "$@"
    ;;
  character)
    desc="$1"; id="$2"; shift 2
    mkdir -p "$WORK"; tmp="$WORK/.cast_$id.txt"; printf '%s: %s\n' "$id" "$desc" > "$tmp"
    "$COMFY_DIR/.venv/bin/python" "$HERE/cast.py" "$tmp" "$@"; rc=$?; rm -f "$tmp"; exit $rc
    ;;
  cast)
    file="$1"; shift
    exec "$COMFY_DIR/.venv/bin/python" "$HERE/cast.py" "$file" "$@"
    ;;
  castgen)
    exec python3 -I "$HERE/cast_llm.py" "$@"
    ;;
  rig)
    exec "$COMFY_DIR/.venv/bin/python" "$HERE/cast.py" --rig "$@"
    ;;
  validate)
    exec python3 -I "$HERE/validate_glb.py" "$@"
    ;;
  gen)
    src="$1"; id="$2"; shift 2
    comfy_up || "$0" comfy
    mkdir -p "$WORK/$id/mixamo"
    engine=trellis2; rot=0; extra=()
    for arg in "$@"; do [[ "$arg" == "hunyuan" ]] && { engine=hunyuan; rot=0; extra=(); }; done
    "$COMFY_DIR/.venv/bin/python" "$HERE/comfy/comfy_gen.py" "$src" "$WORK/$id/model.glb" --server "$COMFY_URL" "$@"
    # oba silniki zwracają model przodem; przy niejasnych konceptach sprawdź podgląd (prep --rotate-z 180)
    "$0" prep "$WORK/$id/model.glb" "$id" --rotate-z "$rot" --preview "$WORK/$id/preview.png" "${extra[@]}"
    ;;
  prep)
    src="$1"; id="$2"; shift 2
    mkdir -p "$WORK/$id/mixamo"
    args=(); prev=""
    for arg in "$@"; do if [[ "$prev" == "--preview" ]]; then args+=("$(p "$arg")"); else args+=("$arg"); fi; prev="$arg"; done
    run_blender prep_for_rig.py "$(p "$src")" "$(p "$WORK/$id/mesh.fbx")" "${args[@]}"
    echo "Dalej: ./pipeline.sh rig $id  (albo Mixamo: wgraj mesh.fbx, FBX-y do $WORK/$id/mixamo/, potem assemble)"
    ;;
  assemble)
    id="$1"; shift
    run_blender assemble_mixamo.py "$(p "$WORK/$id/mixamo")" "$(p "$ROOT/assets/actors/$id.glb")" "$@"
    ;;
  portraits)
    comfy_up || "$0" comfy
    exec "$COMFY_DIR/.venv/bin/python" "$HERE/portraits.py" "$@" --server "$COMFY_URL"
    ;;
  music)
    comfy_up || "$0" comfy
    list="${1:-$HERE/cast/audio_music.txt}"; [[ $# -gt 0 ]] && shift
    exec "$COMFY_DIR/.venv/bin/python" "$HERE/comfy/comfy_audio.py" "$list" "$@" --server "$COMFY_URL"
    ;;
  sfx)
    exec "$COMFY_DIR/.venv/bin/python" -I "$HERE/sfx_synth.py" "$@"
    ;;
  paint)
    comfy_up || "$0" comfy
    exec "$COMFY_DIR/.venv/bin/python" "$HERE/paint_map.py" "$@" --server "$COMFY_URL"
    ;;
  test)
    T="$WORK/_test"; rm -rf "$T"; mkdir -p "$T/mixamo"
    run_blender make_test_rig.py "$(p "$T/mixamo")"
    run_blender prep_for_rig.py "$(p "$T/mixamo/raw_model.glb")" "$(p "$T/to_mixamo.fbx")" --tris 3000
    rm -f "$T/mixamo/raw_model.glb"
    run_blender assemble_mixamo.py "$(p "$T/mixamo")" "$(p "$T/test_actor.glb")"
    ls -la "$T"/*.glb "$T"/*.fbx
    ;;
  *)
    sed -n '2,36p' "$0"; exit 1;;
esac
