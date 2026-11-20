# Lista zadań

Otwarte prace. Zrobione przenosimy do ADR-ów albo dokumentacji, a stąd usuwamy.

## Fabuła (według [zasad pisania](writing-rules.md))

- [ ] **NPC, którzy znali Wędrowca.** Ktoś na Targu pamięta dawną decyzję Wędrowca, na przykład komu kiedyś
  odmówił przejścia, i ma do gracza żal. Przeszłość staje się wtedy osobista. (zasada 2)
- [ ] **Przysięgi i kłamstwa.** Gra zapisuje, czy postać dotrzymuje słowa (Mireli, Kwitowi), i wraca do tego
  w finale, który i tak dotyczy przysięgi. (zasady 3, 8)
- [ ] **Porażka z treścią.** Przegrana walka czasem przenosi gracza „za bramę” albo do wspomnienia zamiast na
  ekran porażki. (zasada 4)
- [ ] **Osobisty wątek Lis.** Jej własna sprawa, związana z zapisem Echa o Wędrowcu. (zasada 6)
- [ ] **Finał jako pytanie zadane graczowi.** Na przykład „dlaczego oddałeś imię?”, z odpowiedziami zależnymi
  od tego, co postać zrobiła na Targu. (zasada 8)

## Rozgrywka

- [ ] **Więcej drzwi, których nie ma.** Pierwsze działają (strażnica Wędrowca w murze targu, obiekt 3D zamiast
  przemalowania). Kolejne przy następnych mapach; księga przejść może wrócić w finale jako dowód.
- [ ] **Znikająca osłona w entropii.** Rdza i zacięta broń działają ([ADR 0006](decisions/0006-unraveler-entropy.md));
  rozpad osłony czeka na system osłon na siatce walki.

## Mechaniki narracyjne (pomysły z Genesys, pod własnymi nazwami)

Kolejność: 1, potem 2, a 3 i 4 przy następnym rozdziale. Każda dostaje ADR przed wdrożeniem.

- [ ] **1. Stopień sukcesu: korzyść i cena.** Wynik o 5 i więcej ponad ST daje korzyść, a o 5 i więcej poniżej
  ST komplikację, ale też coś w zamian. Nowe gałęzie testu obok `success_effects`/`fail_effects`, np.
  `success_cost` i `fail_gain`. Przykłady: przekonujesz Odźwiernego, ale zapamiętuje twoją twarz (reputacja);
  nie otwierasz zamka, ale słyszysz rozmowę za drzwiami (trop). Realizuje zasadę 4. Koszt: dane i
  rozszerzenie `DialogueRunner.roll_check`.
- [ ] **2. Motywacje postaci: siła, wada, pragnienie, lęk.** Gracz wybiera po jednej w kreatorze, a dialogi mają
  opcje odblokowane motywacją (warunek jak `class` czy `skill_prof`). Działanie zgodne z motywacją daje
  Heroiczną inspirację. Pasuje do tematu tożsamości: obecne motywacje zderzają się w finale z tym, kim był
  Wędrowiec („dlaczego oddałeś imię?”). Zasady 1 i 8.
- [ ] **3. Napięcie w konfliktach słownych.** Osobny tor wytrzymałości w dłuższych sporach (Sever, Kustoszka
  w kolejnym rozdziale). Każdy argument rani przeciwnika albo ciebie, a przegrana oznacza ustępstwo, nie śmierć.
  Zasady 3 i 8.
- [ ] **4. Wspólna pula przeznaczenia.** Żetony dzielone między gracza a grę. Gracz wydaje żeton na przewagę albo
  fakt fabularny („znam kogoś w Kancelarii”), a żeton przechodzi na stronę gry, która wydaje go potem przeciw
  graczowi (komplikacja, dodatkowy wróg). To Heroiczna inspiracja z ceną, która nadaje rytm napięciu.

Pasują słabiej i tylko je odnotowujemy:
- kostki narracyjne z symbolami (osobne UI i nauka; oś korzyść/cena z punktu 1 daje to samo na k20);
- piramida talentów (dubluje atuty i podklasy z SRD);
- sloty inicjatywy (przy jednej towarzyszce mały zysk).

Licencja: mechaniki jako idee nie są chronione, ale nazwy, symbole kości i teksty Genesys należą do
Fantasy Flight / Edge. Wdrażamy pod własnymi nazwami (np. „cena” zamiast „threat”), bez ich terminologii i grafiki.

## Pipeline fabuły ([propozycja](story-pipeline.md))

- [x] `story lint`
- [x] `story keys`
- [x] `story paths`
- [ ] Decyzja: czy magazyn ma być dostępny na 1. poziomie bez PD (groźba wobec Odźwiernego działa od startu;
  wykrył to `story paths`)
- [x] `story balance` (macierz poziom × klasa × solo/Lis × spotkanie, `--strict` łapie odwróconą kolejność poziomów)
- [x] `story report` (do obejrzenia i dopracowania wyglądu)
- [ ] Decyzja balansowa: z Lis zasadzka na 1. poziomie jest trudniejsza niż solo (czarodziej Normalny 10/16
  zamiast 13/16), bo skalowanie solo się wyłącza, a Lis ma mało PW
- [ ] Decyzja balansowa: łotrzyk i kapłan solo mają magazyn łatwiejszy na Normalnym niż na Opowieści
  (mefit walczy na Opowieści, ADR 0001)
- [ ] Brief i rozszerzona mapa odkryć dla rozdziału „Kto rozporządza przejściami?”
- [ ] **Pipeline cutscenek.** Scenariusz sceny w danych: ujęcia, kamera, kto mówi i kwestie z dialogów,
  ruch aktorów, efekty, muzyka i dźwięk. Z niego powstaje animatik (kadry jak w `storyboard review`, z głosami),
  podgląd do akceptacji i gotowa scena odtwarzana w silniku. Kontrole: odwołania do aktorów, węzłów i nagrań,
  długość względem nagrań, kadry przed i po. Kandydaci: wspomnienie Wędrowca, przejście przez Łuk, finał.

## Produkcja i wydanie

- [ ] Polskie głosy (`pipeline.sh voice --lang pl`).
- [ ] Głosy szeptów i śladów w mgle (dziś tylko dymek i dziennik).
- [ ] Portret i model „Drzwi, których nie ma” (dziś portret i bryła tylnych drzwi).
- [ ] Mapa głębi z Depth Anything Small przed wydaniem komercyjnym (`*_depth.png` jest dziś CC-BY-NC).
- [ ] Upload na itch.
- [ ] Playtest z nowymi graczami: orientacja, czytelność porażek, zrozumienie Wędrowca, balans magazynu.
