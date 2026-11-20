# Pipeline fabuły: propozycja

Status: propozycja (2026-11-19). Rozwija przebieg z [researchu fabuły i game designu](story-game-design.md)
o to, czego brakowało przy pracy nad Rdzawym Targiem. Każdy etap kończy się plikiem w repozytorium
i automatyczną kontrolą. Człowiek decyduje o treści, a narzędzia pilnują, żeby nic się nie rozjechało.

## Co pokazała praca nad slice'em

| Problem | Jak go znaleźliśmy | Czego zabrakło |
|---|---|---|
| Porażka zamykała drogę bez wskazówki (Odźwierny, zamek, Kwit) | ręczny audyt | kontroli „porażka → inna droga” |
| Gracz wchodził do magazynu na 1. poziomie | przypadkiem, przy balansie | symulacji PD na drogach |
| Opowieść była trudniejsza od Normalnego | po poprawie taktyki testowej | stałego pomiaru balansu w macierzy |
| Dopisany efekt przesuwał klucze tłumaczeń | test i18n po fakcie | wykrywania przesunięć i migracji kluczy |
| Przysięgę gracza czytałby głos Mireli | podgląd przed nagraniem | kontroli „kto mówi ten cytat” |
| Opis skutków frakcji obiecuje coś, czego w danych nie ma | (ryzyko) | kontroli obietnic |

## Etapy

| Etap | Plik | Kontrola | Stan |
|---|---|---|---|
| 1. Brief zadania | `docs/quests/<id>.md`: stawka, motywacje NPC, decyzja gracza, konsekwencje, które [zasady pisania](writing-rules.md) realizuje | przegląd człowieka | nowy |
| 2. Mapa odkryć i dróg | `data/story_arcs.json` rozszerzony o odkrycia, drogi, porażki i konsekwencje | `story check`: każde wymagane odkrycie ma co najmniej 2 źródła, każda porażka ma drogę dalej | częściowo (etapy osi) |
| 3. Sceny po polsku | `data/dialogues/*.json`, okrzyki, szepty, ślady | `story check` (odwołania, przejścia), `story lint` (niżej) | jest; `story lint` wdrożony, oba w `run_tests.sh` |
| 4. Przejścia automatyczne | raport dróg z Godota | `story paths`: dojście do każdego finału każdą klasą, PD przed każdą walką, ślepe zaułki | nowy |
| 5. Balans | macierz poziom × klasa × solo/drużyna | `story balance`, wynik do ADR | ręcznie dziś, do zautomatyzowania |
| 6. Storyboard | `data/storyboard.json` | `storyboard check/review` | jest |
| 7. Tłumaczenie i nagrania | `i18n/en`, `assets/audio/voice` | `story keys`, testy i18n, `story voice`, Whisper | częściowo |
| 8. Raport do przeglądu | jedna strona HTML | wszystko powyżej w jednym miejscu | nowy |

## Nowe polecenia

### `story lint`: reguły pisania jako kontrole

Wdrożone (`pipeline.sh story lint [--strict]`, w `run_tests.sh` w trybie ścisłym): porażka z wyjściem, obietnice
frakcji (w obie strony), kto mówi i okrzyki towarzysza. Przy wdrożeniu lint znalazł dwie sprawy: nieudane
odczytanie run Łuku nie zostawiało śladu, a komentarz Lis nie miał warunku. Obie są poprawione.

- **Porażka z wyjściem.** Węzeł porażki testu, który kończy rozmowę, musi dopisać wpis do dziennika albo mieć wybór
  prowadzący gdzie indziej. Dziś pilnują tego ręcznie napisane testy w `test_slice.gd`.
- **Obietnice frakcji.** Każde `effects[nastawienie]` w `factions.json` musi mieć w danych warunek `reputation`
  albo `reputation_not` z tą frakcją i tym nastawieniem. Każdy taki warunek bez opisu to skutek, którego gracz
  nie zobaczy w dzienniku.
- **Kto mówi.** Cytat poprzedzony frazą w rodzaju „własnym głosem”, „słyszysz swój głos” czy „szepcze” w węźle bez
  `narrator_quotes` daje ostrzeżenie przed nagraniem.
- **Jednorazowe okrzyki towarzysza.** Okrzyk `companion` bez warunku dostaje ostrzeżenie: padnie raz, w przypadkowym
  miejscu.
- **Ślady osi.** Każdy etap osi ma co najmniej jedną scenę i opcjonalnie ślad w mgle (`memories`) przed sobą.

### `story keys`: stabilne klucze tłumaczeń i nagrań

Wdrożone. Zamiast porównania z gitem, które nie działa przy niezacommitowanej pracy, `i18n/<lang>/data.source.json`
trzyma polski tekst, z którego powstało każde tłumaczenie. Polecenie znajduje klucze przesunięte (ten sam tekst
pod innym indeksem; `--fix` przemianowuje klucz i nagranie okrzyku z plikiem `.ogg`), nieaktualne (polski tekst
się zmienił) i bez źródła. Działa w `run_tests.sh` w trybie ścisłym. Flag `once` w zapisach gry nie migruje,
a przesunięty wybór `once` widać w raporcie jako przesunięty klucz tłumaczenia.

### `story paths`: automatyczne przechodzenie

Wdrożone: `pipeline.sh story paths [--classes] [--difficulty] [--max-states 300] [--walks 200] [--json plik]`,
eksplorator w `tools/dev/story_paths.gd`, test `tests/unit/test_story_paths.gd`.

- **Klucz stanu bez śmieci.** Stan opisują tylko fakty, które sprawdza jakiś warunek: flagi i przedmioty
  z warunków, flagi jednorazowych wyborów, przekroczone progi złota, etapy, reputacja, drużyna i usunięci NPC.
- **Za dużo stanów na pełne przeszukanie.** Nawet tak opisanych stanów jest wykładniczo dużo (około 25
  niezależnych faktów), więc eksplorator łączy krótkie przeszukiwanie wszerz (najkrótsze drogi, ślepe zaułki blisko
  startu) z losowymi przejściami.
- **Losowanie ukierunkowane na pokrycie.** Rozmówców losuje z wagą zależną od liczby niewidzianych jeszcze wyborów,
  a w rozmowie częściej wybiera wybory nowe.
- **Pierwsze znalezisko.** Do magazynu można wejść na 1. poziomie bez żadnych PD, bo groźba wobec Odźwiernego
  nie ma warunku.

Pierwotny opis:

Tryb Godota bez okna, który przechodzi graf dialogów przez `DialogueRunner` i `GameState`. Każdy test umiejętności
rozgałęzia przebieg na sukces i porażkę, a walki mają dwa wyniki: wygrana albo wczytanie gry. Dla każdej klasy
raport podaje:

- osiągnięte finały i liczbę dróg do nich;
- stany bez postępu (zadanie nie może ruszyć dalej);
- PD i poziom przed każdą walką (wykryłby wejście do magazynu na 1. poziomie);
- wybory nieosiągalne w żadnym przebiegu.

Limit głębokości i zapamiętywanie odwiedzonych stanów (flagi, etapy, przedmioty, reputacja) ograniczają eksplozję
kombinacji. To odpowiednik Quicktest i Randomtest z ChoiceScript.

### `story balance`: macierz walk

Uogólnienie pomiarów z [ADR 0001](decisions/0001-solo-encounter-scaling.md): dla każdego spotkania, poziomu
trudności, klasy i składu (solo, z Lis) N ziaren. PD i poziom na wejściu biorą się z `story paths`. Wynik to tabela
Markdown gotowa do wklejenia w ADR i progi regresji w teście.

### `story report`: jedna strona do przeglądu

HTML (wzorem `storyboard review`) z sekcjami:

- oś fabuły i jej źródła;
- macierz konsekwencji (frakcje, przedmioty, flagi i miejsce, w którym je widać);
- porażki i ich wyjścia;
- pokrycie nagrań;
- tabela balansu;
- kadry storyboardu.

Służy do przeglądu przed playtestem i do decyzji zapisywanych w ADR.

## Kolejność wdrażania

1. ~~`story lint`~~: wdrożony 2026-11-19.
2. ~~`story keys`~~: wdrożony 2026-11-19 (źródła w `i18n/<lang>/data.source.json`, test `tools/pipeline/test_story_keys.py`).
3. ~~`story paths`~~: wdrożony 2026-11-19 (przeszukiwanie wszerz z limitem i losowe przejścia ukierunkowane na pokrycie).
4. ~~`story balance`~~: wdrożony 2026-11-19 (symulacja w `tools/dev/combat_sim.gd`, wspólna z `test_slice.gd`; około 5 s). Próg problemu od 2026-11-20: różnica ponad 2 błędy standardowe (`story.clearly_worse`), a nie stała „1 wygrana”; domyślnie 64 ziarna na komórkę.
5. Brief i rozszerzona mapa odkryć przy następnym rozdziale („Kto rozporządza przejściami?”).
6. ~~`story report`~~: wdrożony 2026-11-19 (`pipeline.sh story report --out <katalog>`); wygląd dopracowany 2026-11-20 (karty stanu, decyzje z odnośnikami, mapa cieplna balansu, porażki bez wskazówki). Szybka iteracja: `--paths-json` i `--balance-json` z wcześniejszych `story paths --json` i `story balance --json`.

Lokalny LLM (wzorzec z `cast_llm.py`) może szkicować warianty scen z briefu. Wynik i tak przechodzi lint, testy
dróg i redakcję przed nagraniem.
