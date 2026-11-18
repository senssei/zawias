# Pipeline postaci: ComfyUI → Blender → Godot (w pełni lokalnie)

## Skrót: opis → gra (z mixano i kontrolą jakości)

```
./pipeline.sh castgen "dwóch tragarzy z targu" cast/rusty_market.txt --context ../../data/maps/rusty_market.json
./pipeline.sh cast cast/rusty_market.txt --qa --grade-ref work/mirela/concept.png --only tragarz_a,tragarz_b
./pipeline.sh rig <id> [--qa]          # sam rig z istniejącego work/<id>/model.glb (~6 s)
./pipeline.sh validate ../../assets/actors/*.glb
```

| krok | narzędzie | uwagi |
|---|---|---|
| opis → `cast/*.txt` | `cast_llm.py`, Ollama `qwen3:14b` (`CAST_MODEL`) | dopisuje linie; odrzuca id zajęte, opisy nie po angielsku, przedmioty w dłoniach/peleryny i nazwy cudzych settingów (jedna poprawka przez model) |
| koncept | FLUX.2 klein | z `--qa`: 3 warianty, model wizyjny wybiera najlepszy (`work/<id>/qa_concept.json`) |
| model 3D | TRELLIS.2 | bez zmian |
| cleanup + materiały | `prep_for_rig.py` | zawsze: scalanie wierzchołków, normalne, usuwanie drobnych odłamków (dłonie-wyspy zostają); `--max-texture 1024`; **AO wypalane w kolor bazowy** (`--ao 0.8`, tylko gdy model ma AO, czyli `--preset final/hero`: Compatibility nie ma SSAO); **stała paleta** `palette.json` (13 barw rdza/mosiądz/fiolet + skóra i neutralne, `--palette-strength 0.35`, 0 wyłącza); opcjonalnie `--grade-ref` (paleta z jednego obrazu), `--glow` (emisja) |
| kierunek | `qa_vlm.py facing` | z `--qa`, po fazie GPU: model tyłem → prep z `--rotate-z 180` (`QA_ROTATED`) |
| rig + animacje | **mixano** (`~/repos/prototypes/mixano`, `MIXANO`/`MIXANO_DIR`) | `--preset planescape` z UAL, normal mapa zachowana, < 1 s; arkusze `qa_sheet.png`, `qa_weights.png`; dawna ścieżka: `--rigger ual` |
| walidacja | `validate_glb.py` | aktor ≤ 12,5 tys. trójkątów, 1 skin, `idle walk attack cast hit death`, tekstury ≤ 1024, ≤ 6 MB; rekwizyt ≤ 6,5 tys., ≤ 4 MB |

**Budżet trójkątów:** NPC 7000, rekwizyty 6000. Linia obsady zmienia go przez `id [tris=12000]: opis`, tak jak w `cast/rusty_market.txt`
dla postaci gracza i bandyty. Test z 2026-11-18: w kadrze gry (postać ma ok. 100–225 px) 7000 nie różni się od 12000,
ale płaszcze i luźne tkaniny psują się przy decymacji. Pliki są mniejsze tylko o ok. 8%, bo większość wagi to tekstury.
Bandyta został przy starym rigu (UAL), bo mixano gorzej radzi sobie z jego płaszczem. `pipeline.sh rig <id>` bierze budżet z linii obsady,
a `--tris N` go nadpisuje. Osierocone tekstury po przerobieniu modelu pokaże `godot --headless -s tools/dev/actor_textures.gd`
(zaimportowana scena GLB odwołuje się do nich binarnie, więc grep po plikach tekstowych ich nie znajdzie).

Rekwizyty: `id [wysokość glow]: opis` – `glow` włącza emisję (latarnie, runy). `--out-dir katalog` zapisuje wyniki poza `assets/`.
Model wizyjny: `QA_MODEL` (domyślnie Qwen3.5-9B z vision w Ollamie). Bez Ollamy `--qa` jest pomijane z ostrzeżeniem.
VRAM: QA konceptów i kierunku działa, gdy ComfyUI zwolni modele (`/free`), a model wizyjny jest zwalniany przed fazą GPU.

```
./pipeline.sh cast cast/rusty_market.txt --ref work/mirela/concept.png   # cała obsada wsadowo (preset draft)
./pipeline.sh character "opis postaci" <id> --preset final               # jedna postać od opisu do gry
```
Plik obsady ma jedną postać na linię w formacie `id: opis`; `id` jest nazwą pliku w `assets/actors/`.
`cast` pomija postacie, które już mają koncept albo model; `--force` i `--force-concept` wymuszają ponowne generowanie, `--only a,b` ogranicza listę.

**Kolejność pod jedną kartę graficzną:** najpierw wszystkie koncepty (FLUX ładuje się raz), potem modele 3D po kolei (TRELLIS zostaje w VRAM).
Rig i klatki kontrolne poprzedniej postaci liczą się w tle w Blenderze, kiedy GPU generuje następną.
Kroki Blendera są zgrupowane (`run_steps.py`): prep z renderem przodu w jednym procesie, rig z kontrolą w drugim.

**Presety TRELLIS.2** (`--preset`):

| preset | kroki | upsample | tekstura | trójkąty | AO | czas modelu (RTX 5070) |
|---|---|---|---|---|---|---|
| `draft` (domyślny) | 8/12/8/8 | 1024 | 1024 | 15 tys. | nie | ok. 130 s |
| `final` | 12/20/12/12 | 1024 | 2048 | 20 tys. | tak | ok. 240 s |
| `hero` | 16/28/16/16 | 1536 | 4096 | 30 tys. | tak | ok. 2× final |

`--ref obraz.png` przy konceptach każe FLUX-owi trzymać styl obrazu referencyjnego (np. pierwszej postaci).
albo krok po kroku:
```
./pipeline.sh concept "opis" <id> --count 4      # FLUX.2 klein → work/<id>/concept_N.png (wybierz jeden jako concept.png)
./pipeline.sh gen work/<id>/concept.png <id>     # TRELLIS.2 → work/<id>/model.glb → mesh.fbx (+ podgląd)
./pipeline.sh rig <id>                           # DWPose + szkielet UAL → assets/actors/<id>.glb (+ work/<id>/qa_sheet.png)
```
Czas na RTX 5070: koncept ok. 6 s, model 3–5 min, rig ok. 25 s.

Blender: domyślnie `C:\Program Files\Blender Foundation\Blender 5.x\blender.exe` (uruchamiany z WSL w trybie wsadowym). Inną ścieżkę ustawisz przez `BLENDER=...`.
Test bez Mixamo: `./pipeline.sh test` buduje postać testową i składa ją do `work/_test/test_actor.glb`.

## 1. ComfyUI: koncept i model 3D (RTX 5070, 12 GB)

```
./pipeline.sh comfy                                   # uruchamia ComfyUI w tle (http://127.0.0.1:8188)
./pipeline.sh gen koncept.png mirela --seed 7         # TRELLIS.2: geometria + tekstura (ok. 5 min)
./pipeline.sh gen koncept.png mirela --engine hunyuan # Hunyuan3D-2: sama bryła (ok. 2 min)
```
`gen` wysyła obraz do workflow w `comfy/*.api.json` (same natywne węzły ComfyUI, bez kompilacji), zapisuje `work/<id>/model.glb`, a potem automatycznie odpala `prep` z podglądem `work/<id>/preview_0.png` (przód) i `preview_1.png` (3/4).

| silnik | workflow | co daje | czas (12 GB) |
|---|---|---|---|
| `trellis2` (domyślny) | `trellis2_image_to_model.api.json` | bryła, remesh, ok. 20 tys. trójkątów, UV, tekstury 2048 (kolor, normal, AO) | ok. 320 s |
| `hunyuan` | `hunyuan3d_image_to_model.api.json` | sama bryła, bez tekstury | ok. 105 s |

Opcje TRELLIS.2: `--faces 20000` (trójkąty), `--texture 2048` (rozdzielczość tekstur).
Pliki `.api.json` możesz też wczytać w interfejsie ComfyUI (Workflow → Open).

Modele (już pobrane do `~/ComfyUI/models`):
- TRELLIS.2: `diffusion_models/trellis_2_int8_convrot`, `vae/trellis_2_shape_vae_bf16`, `vae/trellis_2_texture_vae_bf16`, `clip_vision/dino_v3_vit_l` (Comfy-Org/TRELLIS.2)
- Hunyuan3D-2: `checkpoints/hunyuan3d-dit-v2_fp16` (Comfy-Org/hunyuan3D_2.0_repackaged; wersji mini nie ma w formacie natywnym)
- tło: `background_removal/birefnet` (Comfy-Org/BiRefNet)

Poprawki w `prep`:
- styl matowy (metaliczność 0, chropowatość 0,8), bo TRELLIS.2 zawyża metal; wyłącza go `--keep-metal`;
- `--rotate-z 180`, gdy na podglądzie model stoi tyłem (zdarza się przy symetrycznych, niejasnych konceptach);
- `--gamma-fix 2.2` tylko wtedy, gdy tekstura wyjdzie wyraźnie za ciemna (na normalnych konceptach niepotrzebne).

Koncept postaci (FLUX.2 klein 4B, Apache 2.0, ok. 6 s na obraz po rozgrzaniu):
```
./pipeline.sh concept "opis postaci" mirela --count 4    # warianty concept_1..4.png
./pipeline.sh concept "opis" kwit --ref work/mirela/concept.png   # spójny styl z inną postacią
./pipeline.sh character "opis" lis                       # opis → koncept → model 3D → to_mixamo.fbx
```
Opis jest wstawiany w szablon (A-pose, przód, jasne tło, styl rdza/mosiądz/fiolet). `--raw` wyłącza szablon.
Modele: `diffusion_models/flux-2-klein-4b-fp8`, `text_encoders/qwen_3_4b`, `vae/flux2-vae`.

**Uwaga (cuDNN):** globalny `LD_LIBRARY_PATH` z bibliotekami CUDA 12 w `~/.local` (TensorRT) psuje cuDNN 9.24 z venv ComfyUI (`CUDNN_STATUS_SUBLIBRARY_LOADING_FAILED`).
`./pipeline.sh comfy` uruchamia ComfyUI z `LD_LIBRARY_PATH=/usr/lib/wsl/lib`.

**Koncept:** A-pose, przodem, cała postać, jednolite jasne tło, mocne kolory. Najlepiej SDXL/Flux z ControlNet OpenPose i IPAdapterem (masz oba węzły), żeby trzymać jeden styl.
Nie używaj nazw cudzych settingów ani nazwisk artystów.

## 2. `prep`: czyszczenie pod rigging

```
./pipeline.sh prep ~/ComfyUI/output/mirela.glb mirela --height 1.7 --tris 12000
```
Skrypt łączy siatki, stawia model stopami na 0 i wyśrodkowuje go, skaluje do zadanej wysokości, redukuje trójkąty i eksportuje FBX z teksturami.
`--rotate-z 90|180|270`, jeśli model nie patrzy przodem w -Y (przód w Blenderze).

## 3. `rig`: lokalny auto-rig i animacje (zamiast Mixamo)

```
./pipeline.sh rig mirela
```
1. `render_front.py` renderuje przód modelu kamerą ortogonalną (piksel → metry).
2. `comfy_pose.py` uruchamia DWPose (`comfyui_controlnet_aux`) i zwraca 18 punktów ciała.
3. `autorig_ual.py`:
   - dopasowuje szkielet **Quaternius Universal Animation Library** (CC0, `third_party/ual/`) do proporcji postaci, a głębokość stawów bierze z przekroju siatki; orientacje kości zostają z UAL, więc animacje działają bez retargetingu;
   - liczy wagi (bone heat na zamkniętej siatce zastępczej w skali x10, bo na surowej siatce z TRELLIS bone heat zawodzi), usuwa wagi rąk z wierzchołków daleko od rąk, wygładza i ogranicza do 4 kości na wierzchołek;
   - prostuje siatkę do T-pose szkieletu UAL i eksportuje GLB z animacjami: `idle, walk, run, attack, cast, hit, death, talk, punch, interact`.
4. `render_anims.py` i `qa_sheet.py` składają arkusz kontrolny `work/<id>/qa_sheet.png` z klatką z każdej animacji.

Najlepsze wyniki daje koncept w T-pose z dłońmi odsuniętymi od ciała, i taki jest domyślny szablon `concept`.
Postacie, których dłonie dotykają tułowia albo sukni, mogą mieć artefakty w wagach.
Potwory nieczłekokształtne (np. mefit) wymagają osobnego rigu.

## 4. Mixamo (opcjonalnie, zamiast `rig`)

1. Wgraj `work/<id>/mesh.fbx` i ustaw markery (podbródek, nadgarstki, łokcie, kolana, pachwina).
2. Pobierz model w T-pose: **FBX Binary, With Skin**. Zapisz jako `work/<id>/mixamo/base.fbx`.
3. Pobierz animacje (FBX Binary, Without Skin, 30 fps) i zapisz pod nazwami, których używa gra:
   `idle.fbx`, `walk.fbx` (zaznacz **In Place**), `attack.fbx`, `cast.fbx`, `hit.fbx`, `death.fbx`.
   Inne nazwy też przejdą do GLB, ale gra ich sama nie użyje.

Mixamo nie ma oficjalnego API, więc ten krok zostaje ręczny. Gdyby trzeba go zautomatyzować, można sięgnąć po UniRig (lokalnie) albo API Meshy/Tripo.

## 5. `assemble`: GLB z plików Mixamo

```
./pipeline.sh assemble mirela            # -> assets/actors/mirela.glb
```
Skrypt łączy animacje w jeden szkielet (nazwa pliku staje się nazwą animacji) i usuwa poziomy ruch bioder z `walk`/`run`, na wypadek gdyby zabrakło In Place.
Opcja `--tris N` dodatkowo redukuje siatkę.
Nazwy plików w `assets/actors/` opisuje `assets/actors/README.md`.

## Malowany obszar mapy (architektura malowana, rekwizyty i postacie w 3D)

```
tools/pipeline/pipeline.sh paint <map_id>                                 # całość, ~5–6 min
tools/pipeline/pipeline.sh paint <map_id> --only 4,5 --seed 91 --from paint   # przemaluj wybrane kafelki i sklej od nowa
tools/pipeline/pipeline.sh paint <map_id> --fix --from paint --seed 201    # przemaluj tylko kafelki z pustką na platformie
tools/pipeline/pipeline.sh paint <map_id> --from stitch                   # tylko sklejenie + głębia
```

Kroki (`paint_map.py`, wyniki w `work/paint_<map_id>/`):
1. **shots** – Godot (`--paintshots=`) renderuje z ortogonalnego projektora obejmującego całą mapę (2560×1440):
   makietę z rekwizytami, samą architekturę i głębię makiety (`projector.json` opisuje kamerę).
2. **paint** – siatka 3×3 kafelków w skali kadru gry (cała mapa naraz rozjeżdża układ budynków). Każdy kafelek:
   FLUX.2 klein przemalowuje makietę z rekwizytami (referencja w pełnej rozdzielczości, inaczej kompozycja pływa),
   potem edycja usuwa stragany, latarnie, skrzynie i łuki. Podgląd: `candidates_tiles.png` (numery kafelków).
   Kontrola jakości: udział fioletowej pustki w obszarze, który w makiecie jest platformą (plamy na bruku,
   zwężona/przesunięta platforma). Powyżej `--void-thr` (5%) kafelek jest malowany ponownie, do `--retries` (3) prób,
   zostaje najlepsza; na końcu raport kafelków, które nadal nie przechodzą.
3. **stitch** – sklejenie szwami najmniejszej różnicy (image quilting), poza platformą malowana pustka
   (`assets/backgrounds/planar_void.png`), bo FLUX dorabia zabudowę w pustych narożnikach. Podgląd: `painted_preview.png`.
4. **depth** – Depth Anything V2 + `paint_depth.py`: głębia liczona kafelkami (na całej mapie DA zaniża domy),
   podłoga z makiety (RANSAC, dokładna), wysokości z DA. Kopia do `assets/backgrounds/<map_id>_paint.png`,
   `_depth.png`, `_paint.json`.
5. **check** – zgodność z kolizjami tak, jak widzi ją gracz: na każdym polu chodzonym stawiana jest „postać”
   (próbki na 0,4/0,9/1,4 m) i sprawdzane, czy malunek ją zasłania, choć makieta nie. Wynik w `cells_check.png`
   (czerwone: zasłania, pomarańczowe: częściowo) i `cells_check.json`. Pola wyraźnie zabudowane na malunku
   trafiają do `blocked` w `_paint.json` (gra blokuje je w trybie malowanym), z pominięciem pól kluczowych
   (postacie, obiekty, drzwi, wyzwalacze, spawny) i takich, których blokada odcięłaby część mapy. Raport ostrzega
   też o postaciach stojących za budynkiem. Sam krok: `--from check`.

Makieta do malowania (`World._paintify_blockout`): domy 2,9 m, mury 1,0 m, proste materiały. Wpis legendy mapy
może to zmienić: `"paint_height": 1.6` (wysokość), `"paint_kind": "wall"` (malowany jako mur, np. dziedziniec
magazynu: wysoki budynek przy tym kącie kamery zasłania podwórze i FLUX zamalowuje je dachami).

Gra włącza tryb sama, gdy te pliki istnieją (`--nopaint` wyłącza). Postacie zasłonięte przez budynek widać
jako sylwetkę (`shaders/xray.gdshader`), a kamera nie wyjeżdża poza malunek. Shader `shaders/paint_depth.gdshader`:
siatka przesunięta na głębię z malunku (cienie 3D) + DEPTH na piksel (przesłanianie). Obrót kamery zablokowany.
Po zmianie mapy (budynki, rekwizyty) trzeba malować od nowa. Gałąź shaderów dla Forward+ (Vulkan) nieprzetestowana.


## Portrety

`pipeline.sh portraits cast/rusty_market.txt`: popiersia z konceptów (`work/<id>/concept.png`) do `assets/portraits/<id>.png`.
Rekwizyty: `pipeline.sh portraits cast/rusty_market_props_portraits.txt --kind prop`. Gra pokazuje portret rozmówcy
w oknie dialogu (id dialogu, `backdoor` -> `door`, węzeł może podać `"portrait"`) i portret `pc_<klasa>` w HUD.

## Dźwięk

- **Muzyka:** `pipeline.sh music` (ACE-Step 1.5 turbo w ComfyUI, MIT/Apache 2.0). Lista `cast/audio_music.txt`:
  `id [sekundy] [loop] bpm=.. key=..: tagi`. Cisza na brzegach jest przycinana, pętle przenikają koniec w początek.
  Kontrola bez słuchania: `tools/dev/audio_check.py plik.wav --sheet spektrogram.png` (cisza, przester, szew).
  Warianty: `--count 2`, wybrane kopiujesz z `work/audio/` (model czasem robi długie przerwy w środku utworu).
- **Efekty i ambient:** `pipeline.sh sfx` – synteza w numpy (`sfx_synth.py`), bez próbek i licencji.
  Nazwy plików są kontraktem z grą (`scripts/game/audio.gd`): można je podmienić na nagrania, np. pakiety CC0.
- **W grze:** autoload `Audio` (szyny Music/Ambient/SFX, ustawienia w `user://settings.cfg`), kroki zsynchronizowane
  z fazą animacji chodu (`Actor.FOOTFALLS`). Debug: `--audiolog`. W WSL nie ma urządzenia ALSA, więc dźwięk słychać
  dopiero w buildzie/na Windowsie.
