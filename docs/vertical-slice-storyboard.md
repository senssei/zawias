# Audyt vertical slice’a i storyboard produkcyjny

Slice ma kompletną pętlę na Rdzawym Targu: wejście, zlecenie Mireli, śledztwo, magazyn, ujawnienie tożsamości Wędrowca oraz decyzję o kluczu. Kolejny etap powinien przede wszystkim sprawdzić, czy gracz sam odczytuje dostępne działania i rozumie ich konsekwencje.

## Braki i priorytety

| Priorytet | Ustalenie | Kryterium domknięcia |
|---|---|---|
| P0 — finał | Łuk wybiera `with_key` na podstawie posiadania klucza. `portal` zachowuje przedmiot i przyznaje 300 PD. Po wybraniu „Zwiedzaj dalej” dane pozwalają znów otworzyć tę samą gałąź. To ryzyko potwierdzone przez odczyt warunków, do odtworzenia w scenie gry. | Ponowne użycie Łuku po przejściu i po wczytaniu pozwala obejrzeć jego stan po finale. PD i ekran zakończenia wyzwalają się raz. |
| P1 — orientacja | Test dojścia do Mireli wywołuje klik po stronie świata na jej polu. Potwierdza trasę i zmianę celów, ale nie mierzy, czy gracz sam zauważy Mirelę, wskazówkę o mapie albo drogę do Lis. Znaczniki podlegają mgle. | Świeży gracz znajduje Mirelę i po przyjęciu zlecenia potrafi wskazać pierwszy krok bez pomocy prowadzącego. |
| P1 — drogi i porażki | Testy przechodzą dyplomację, skradanie i walkę każdą klasą, lecz ścieżka skradania dla postaci bez wytrychów zaczyna się rozmową z Odźwiernym. Test walki próbuje kolejnych ziaren. To dowód osiągalności, z ograniczonym pokryciem czytelności i balansu. | Próby obejmują jawną odmowę Odźwiernego, brak pieniędzy, zaklinowany zamek oraz walkę czarodziejem bez Lis. Po porażce gracz potrafi nazwać inną drogę. |
| P1 — stawka wyboru | Testy potwierdzają oba wyniki i zachowanie wspomnienia w zapisie. Brakuje obserwacji, czy gracz rozumie, kim był Wędrowiec i dlaczego oddanie klucza oraz otwarcie Łuku są różnymi decyzjami. | Dwie próby z nowymi graczami, z tropami oraz po pominięciu Haska i Lis. Po finale gracz własnymi słowami wyjaśnia odkrycie i swoją decyzję. |
| P2 — prezentacja | Test głosów porównuje istniejące wpisy manifestu z tekstem. Nie wykrywa całkowicie nienagranej sceny. Test księgi i efektów sprawdza mechanikę oraz sprzątanie geometrii. Czytelność HUD-u, dźwięku i przejść między nimi wymaga próby na ekranie. | Przed nagraniami zatwierdzić tekst scen kluczowych. Raport wypisuje brak nagrania dla tych scen. Obejrzeć sekwencję w PL i EN, w tym księgę, wybór celu i finał w tej samej rozgrywce. |

### Stan po przeglądzie 2026-11-19

| Punkt | Co zrobiono | Co zostaje |
|---|---|---|
| P0 — finał | Węzeł `after_portal` w Łuku. Storyboard sprawdza powrót do Łuku po finale bez ponownych PD. | — |
| P1 — orientacja | Cele zadania są widoczne na mapie także we mgle, jako romb z podpisem bez sylwetki. Test mapy sprawdza, że po zleceniu widać Kwita, Pchłę i Lis. | Obserwacja świeżego gracza. |
| P1 — drogi i porażki | Odmowa Odźwiernego, zaklinowany zamek, nieudane wyważenie, milczenie Pchły i odmowa Kwita dopisują do dziennika inną drogę. Ta sama porażka nie dubluje wpisu. Nowe testy obejmują odmowę z wyważeniem i walką frontem, brak złota z tropem od Lis oraz zaklinowany zamek z wejściem frontem. | Skalowanie solo (`"solo": {"skip": [...]}` w `encounters.json`), bez towarzysza zasadzka ma jednego bandytę (na obu poziomach), a mefit nie walczy w magazynie (tylko na Normalnym, `solo_scaling` w `Difficulty.PRESETS`). Zasadzka jest skalowana także na „Opowieści” (`"difficulty"` w spotkaniu), bo bez tego była tam trudniejsza niż na Normalnym. Zasadzka daje 250 PD, więc gracz wchodzi do magazynu na 2. poziomie. Taktyka testowa pije mikstury i nie rzuca czarów dystansowych z bliska. Czarodziej solo na Normalnym: zasadzka 10/12, magazyn 9/12. Do sprawdzenia w playteście. |
| P1 — stawka wyboru | Storyboard ma 10 kadrów: bramę, mapę, trop u Lis, odmowę z mapą, trzy kadry walki czarodziejem (księga, cel, efekt), wspomnienie z odłożoną decyzją i oba finały. | Dwie próby z nowymi graczami. |
| P2 — mgła | Mgła wojny w świecie 3D: fioletowa, ruchoma mgła nad nieodkrytym malunkiem z miękkim brzegiem. NPC, obiekty i rekwizyty we mgle są ukryte, a pole walki się odkrywa. Na mapie brzeg mgły jest miękki, a dziury w cieniu straganów są łatane. | Ocena na ekranie. |
| P2 — prezentacja | `pipeline.sh story voice` wypisuje węzły bez nagrania, a `story check` ostrzega o brakach w scenach kluczowych (źródła osi i węzły kadrów). | Nagrania EN są kompletne (24 nowe fragmenty, kontrola Whisperem). Przysięgę we wspomnieniu u Mireli czyta narrator (`narrator_quotes`). Zostają głosy PL. |

Podstawa audytu to [testy dróg](../tests/unit/test_slice.gd), [testy mapy](../tests/unit/test_map.gd), [Łuk](../data/dialogues/arch.json), [testy głosu](../tests/unit/test_voice.gd) i [projekt Wędrowca](wanderer.md). Wykonane kontrole `story check` oraz `spellfx check` przeszły. Audyt nie obejmował obserwacji nowych graczy ani ponownego uruchomienia GUT.

## Storyboard pilotażowy

| Kadr | Co gracz widzi i robi | Co powinien zrozumieć | Punkt kontrolny |
|---|---|---|---|
| Brama | Widok startowy, Hask i opcja pokazania znaku. | Rozmowa pomaga ustalić, dokąd iść. Znak wiąże postać z bramą. | Nowa gra, wariant z tropem i bez niego. |
| Mirela | Zlecenie, po zamknięciu dialogu dziennik i mapa. | Ma odzyskać klucz i może zacząć od dowolnego z trzech rozmówców. | `key=started`, widoczne tropy stosownie do odkrytych pól. |
| Śledztwo | Lis odczytuje znak. Alternatywne kadry pokazują ostrzeżenie Pchły albo umowę z Kwitem. | Wskazówki zmieniają przygotowanie, nie tylko wskazują magazyn. | Oddzielne stany dla każdego tropu. Nie łączyć ich w jedną obowiązkową trasę. |
| Podejście | Odźwierny odmawia albo tylne drzwi są zamknięte. | Porażka zamyka próbę, lecz istnieje kolejna droga. | Osobne kadry wejścia frontem, tyłem i walki. |
| Walka | Jedna pełna sekwencja księga → cel → efekt → stan tury. | Widać, kogo obejmie czar i kiedy koszt został wydany. | Stałe ziarno i pozycje, czytelne w tym samym ujęciu co reszta UI. |
| Wspomnienie | Klucz ujawnia przysięgę u Mireli albo przy Łuku. | Postać gracza była Wędrowcem. Może odłożyć decyzję. | `wanderer=revealed`, zapis i odczyt przed wyborem. |
| Decyzja | Oddanie klucza lub przekroczenie progu, potem powrót do interakcji po finale. | Wybór dotyczy tego, czy zostać, czy sprawdzić, kto dziś kontroluje przejścia. | Oddzielne finały, brak ponownej nagrody po powrocie do Łuku. |

## Storyboard jako pipeline

Proponowany interfejs to `pipeline.sh storyboard check rusty_market` oraz `pipeline.sh storyboard review rusty_market <katalog> --lang pl|en`. Pierwsza wersja obejmuje siedem wierszy powyżej, z osobnymi wariantami istotnych rozgałęzień.

1. Manifest storyboardu trzyma identyfikator kadru, wejście w scenę, obserwowaną czynność, oczekiwany stan i pytanie do playtestu. Odwołuje się do istniejących map, aktorów i węzłów dialogu oraz etapów z manifestu osi. Tekst kwestii zostaje w dialogach i nakładce językowej.
2. `check` weryfikuje referencje i istnienie plików potrzebnych do odtworzenia kadru. Tryb testowy Godota dochodzi do punktu kontrolnego przez normalne wejścia, np. opcję dialogową albo przycisk księgi, ze stałym ziarnem i osobnym katalogiem zapisów. Brak oczekiwanego stanu kończy odtworzenie błędem.
3. `review` publikuje lokalny HTML i klatki po udanym odtworzeniu. Wykorzystuje wzorzec `spellfx review` z renderowaniem w Godot, nazwanymi klatkami i względnymi linkami. Przy każdym kadrze pokazuje wariant trasy, oczekiwany stan oraz pytanie dla osoby oceniającej. PNG nie zastępuje zapisu wyniku testu ani obserwacji gracza.
4. Pilotaż zacząć od bramy, mapy po zleceniu i obu finałów. To najmniejszy zestaw, który sprawdza orientację, moment zwrotu i domknięcie. Dopiero po sprawdzeniu rejestracji scen dodać warianty magazynu, walkę i kontrolę brakujących nagrań.
