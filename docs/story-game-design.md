# Fabuła i game design w pipeline Zawiasu

## Wnioski z researchu

| Podejście | Wniosek dla Zawiasu |
|---|---|
| Scenariusz z węzłami i kilkoma źródłami tropu | Rozpisz każde odkrycie potrzebne do postępu i przypisz mu niezależne źródła. Sprawdź, czy gracz może zmienić kierunek, kiedy ominie rozmówcę albo nie zda testu. [Justin Alexander, Node-Based Scenario Design](https://thealexandrian.net/wordpress/7985/roleplaying-games/node-based-scenario-design-part-3-inverting-the-three-clue-rule) |
| Kilka rozwiązań jednego problemu | Zaplanuj, jakie reguły lub zasoby uruchamia każda droga. Spector opisuje, że w praktyce zespół często musiał projektować te drogi ręcznie. Dla małego zespołu sensowny jest wspólny obszar i wspólny cel z różnymi warunkami wejścia. [Warren Spector, postmortem Deus Ex](https://www.gamedeveloper.com/design/postmortem-ion-storm-s-i-deus-ex-i-) |
| Dialog jako decyzja i ekspresja postaci | W specyfikacji wyboru zapisz zamiar gracza, to, co może przewidzieć, i skutek widoczny w świecie. Przewidź warianty ekspresji postaci także tam, gdzie prowadzą do tego samego wyniku mechanicznego. [Joshua Sawyer, Choice Architecture](https://gdcvault.com/play/1015758/Do-%28Say%29-The-Right-Thing) |
| Automatyczne przechodzenie rozgałęzień | Połącz kontrolę odwołań i przejść z deterministycznymi scenariuszami na silniku. Losowe przebiegi mogą później szukać kombinacji pominiętych w scenariuszach. [Choice of Games, Quicktest i Randomtest](https://www.choiceofgames.com/make-your-own-games/testing-choicescript-games-automatically/) |

## Proponowany przebieg prac

| Etap | Wynik | Jak ocenić |
|---|---|---|
| Brief fabuły i rozgrywki | Jedna strona na zadanie. Stawka, motywacje NPC, decyzja gracza, dostępne działania i konsekwencje. | Czy z briefu wynika, co gracz zrobi i dlaczego wybór ma dla niego znaczenie? |
| Mapa odkryć i decyzji | Lista wymaganych odkryć, źródeł, kosztów, powodów niepowodzenia i dróg odzyskania postępu. Każda droga ma przypisane etapy zadania, flagi, przedmioty i reakcje świata. | Czy jedna chybiona próba zostawia osiągalną drogę dalej? Czy wybór zmienia przygotowanie, ryzyko lub wynik? |
| Grywalny prototyp | Polskie kwestie robocze w istniejącym JSON, wejścia i przeszkody na obecnej mapie oraz minimalna konfiguracja spotkań. | Przejście na silniku. Gracz wie, co zrobić po porażce i potrafi wskazać skutek swojej decyzji. |
| Redakcja i produkcja | Zatwierdzony polski tekst, angielska nakładka, lista zmienionych kwestii do nagrania i lista faktycznie potrzebnych assetów. | Testy i18n i głosów, podgląd zmienionych plików, krótka próba w grze. |

Pierwsza komenda pipeline’u, `pipeline.sh story check`, sprawdza dane zadania. Wypisuje ścieżkę i miejsce błędu. Sprawdza cele przejść, także `starts`, `redirect` i obie strony testów umiejętności, odwołania do spotkań i celów mapy oraz zgodność etapów i przedmiotów. Graf strukturalny może wskazać podejrzane cykle i węzły bez wejścia. Do sprawdzenia dostępności przy konkretnych flagach, zasobach i wynikach rzutów służy `DialogueRunner` z `GameState` w testach Godota.

Polski JSON już zasila grę, angielską nakładkę i generowanie głosów. Ink ma czytelną składnię do pisania rozgałęzień, ale jego eksport JSON jest formatem własnego interpretera. Yarn Spinner daje podgląd grafu i identyfikatory kwestii do lokalizacji. Obie opcje zyskują sens przy realnym problemie z redakcją dużej liczby dialogów. Migracja teraz kosztowałaby spięcie testów SRD, efektów, map i istniejących zapisów. Zmiana kolejności wyborów `once` może zmienić klucz flagi w zapisie, a zmiana identyfikatorów węzłów wpływa na ścieżki tłumaczeń i głosów. [Format JSON Ink](https://github.com/inkle/ink/blob/master/Documentation/ink_JSON_runtime_format.md) · [Edytor Yarn Spinner](https://www.yarnspinner.dev/editor/) · [Lokalizacja Yarn Spinner](https://www.yarnspinner.dev/docs/unity/06-localisation-and-assets/)

Opcjonalny lokalny LLM może szkicować warianty scen i kwestie według zatwierdzonego briefu. `cast_llm.py` już pokazuje wzorzec z kontekstem, schematem odpowiedzi i trybem `--dry-run`. Schemat pilnuje formatu. Sens wyboru, osiągalność ścieżek i zgodność z kanonem wymagają przeglądu oraz testu. Zmiany tekstu powinny przejść redakcję przed uruchomieniem `voice`. [Ollama, structured outputs](https://github.com/ollama/ollama/blob/main/docs/capabilities/structured-outputs.mdx)

## Pilotaż na Kluczu bez drzwi

**Założenie projektowe.** Gracz zaczyna jako osoba wynajęta do odzyskania przedmiotu. Pod koniec ma zdecydować, ile warta jest obietnica złożona Mireli, kiedy poznaje zastosowanie klucza. Odkrycia w śledztwie powinny zmieniać to, jak podejdzie do magazynu i jak zinterpretuje finał.

| Wybór w obecnej grze | Różnica do pokazania w grze | Co sprawdzić w pilotażu |
|---|---|---|
| Kwit | Wskazuje magazyn. W wariancie podszycia się pod wysłannika Kustoszki daje kontrakt, który Hask przyjmuje za oczyszczenie zaułka. Gracz może bez walki podejść do tylnych drzwi. Drzwi wciąż trzeba otworzyć, a nagrody za walkę zostają przypisane do spotkania. | Sprawdzić, czy gracz wraca do Haska na podstawie wpisu w dzienniku lub opisu kontraktu i czy rozumie, że przysługa dotyczy zaułka. |
| Pchła | Może ostrzec o zasadzce, ustawiając `ambush_warned`. | Czy gracz wie o niebezpieczeństwie przed wejściem i zauważa różnicę w otwarciu walki? |
| Lis | Podaje położenie magazynu. Dodatkowy wgląd w zapisy daje argument dla Severa. Lis może też dołączyć do drużyny. | Czy gracz odróżnia wskazówkę o miejscu od wiedzy, której może użyć w rozmowie? Czy wizyta działa także bez rekrutacji? |
| Magazyn i finał | Wejście frontem, tyłem lub walka prowadzą do klucza. Gracz może oddać go Mireli albo użyć w Łuku. | Czy po nieudanym podejściu istnieje czytelna kolejna próba? Czy przed finałem gracz rozumie, co ryzykuje, i widzi skutek wyboru? |

Obecne testy przechodzą dyplomację, skradanie i walkę każdą klasą. Pierwszy przyrost narzędzi powinien dołożyć macierz przypadków na granicach tych dróg: porażkę pierwszego testu, brak pieniędzy, pominięcie rozmówcy, zmianę metody wejścia oraz zapis i wczytanie po uzyskaniu tropu. Osobno w krótkim playteście warto zapytać gracza, dokąd pójdzie, co zmienił zdobyty trop i czego się spodziewa po użyciu klucza. Taki test wychwyci nieczytelne wybory, których sam poprawny stan gry nie ujawnia.

### Game design poza dialogiem

- **Przestrzeń i informacja.** Dla każdej drogi spisz punkt, z którego gracz może ją zauważyć, pierwszą wskazówkę oraz moment wejścia w ryzyko. W pilotażu porównaj, czy gracz zauważa tylne drzwi przed rozmową z odźwiernym i po jego odmowie.
- **Tempo i balans.** Dla wejścia do magazynu porównaj czas od otrzymania tropu, utracone PW i wydane zasoby, przyznane XP oraz wpływ Lis. Przejdź warianty czarodziejem i wojownikiem na Normalnym, samodzielnie i z Lis. Wyniki mechaniczne skonfrontuj z tym, którą drogę gracz wybrał i dlaczego.
- **Koszt produkcji.** Dla każdej konsekwencji zanotuj, czy wystarczy zmiana reguły, tekstu, znacznika lub istniejącego spotkania, czy potrzeba nowej animacji, mapy lub głosu. W pilotażu najpierw porównaj zachowanie graczy na tej samej mapie przy dwóch wariantach przysługi Kwita, zanim powstaną nagrania.
