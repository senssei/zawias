# Modele postaci

Pliki `<id>.glb` z tego katalogu gra wczytuje automatycznie w miejsce figur zastępczych.

Kolejność szukania:
- gracz: `pc_<klasa>_<gatunek>.glb`, `pc_<klasa>.glb`, `pc.glb` (np. `pc_wizard_elf.glb`)
- NPC: `<id NPC>.glb` (np. `mirela.glb`), potem `<potwór>.glb` (np. `cultist.glb`), potem `npc.glb`
- wrogowie ze spotkań: `<id>.glb`, potem `<potwór>.glb` (np. `bandit.glb`, `rust_mephit.glb`)

Obsługiwane nazwy animacji: `idle`, `walk` (zapętlone), `attack`, `cast`, `hit`, `death`. Brakujące animacje gra pomija.
Model jest skalowany do 1,75 m i stawiany stopami na ziemi. Przód to +Z w glTF (domyślny kierunek z Mixamo).

Pliki powstają przez `tools/pipeline/pipeline.sh` (opis w `tools/pipeline/README.md`).
