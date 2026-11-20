# Zasady pisania scenariusza

Osiem zasad, według których piszemy Zawias. Każda scena, zadanie i rozdział powinny spełniać przynajmniej część
z nich, a brief zadania (etap 1 w [pipeline'ie fabuły](story-pipeline.md)) wskazuje, które. Kolumna „Kontrola”
mówi, co pilnuje zasady automatycznie, a „W Zawiasie” pokazuje, gdzie już działa.

1. **Pytanie o tożsamość zamiast celu do wykonania.** Gracz nie pyta „jak pokonać zło”, tylko „kim jestem i kim
   byłem”. Każde odkrycie zmienia sposób, w jaki patrzy na swoją postać.
2. **Przeszłość, która odpowiada.** Ludzie reagują na to, co zrobiłeś w poprzednim życiu, a nie tylko na obecne
   decyzje. Ktoś cię kocha, ktoś nienawidzi, a ty nie wiesz dlaczego. To mocniejsze niż jakiekolwiek wprowadzenie
   w świat.
3. **Słowa jako czyny.** Dialog jest głównym sposobem gry. Statystyki (Inteligencja, Mądrość, Charyzma) otwierają
   opcje, a kłamstwa, przysięgi i obietnice mają konsekwencje, czasem wiążące. Dużo konfliktów da się rozwiązać
   bez walki.
4. **Porażka i śmierć jako część opowieści.** Przegrana nie kończy gry, tylko prowadzi dalej, czasem do czegoś
   ważnego. Gracz przestaje się bać eksperymentować.
5. **Frakcje jako idee, a nie drużyny.** Każda frakcja to filozofia (entropia, rejestr, pamięć), z którą gracz
   może się zgodzić lub spierać.
6. **Towarzysze z własną raną.** Ich historie łączą się z przeszłością bohatera, mają zdanie o twoich wyborach
   i potrafią odejść albo się zmienić.
7. **Konkretny, dziwny świat i gęste pisanie.** Małe poboczne historie, które zostają w pamięci, i świat, który
   nie przypomina generycznego fantasy.
8. **Finał jako rozmowa.** Kulminacją jest konfrontacja z pytaniem, a nie walka z bossem.

## Jak to sprawdzamy

| # | Kontrola | W Zawiasie | Braki |
|---|---|---|---|
| 1 | `story check`: oś Wędrowca ma źródło dla każdego etapu | oś `wanderer`, ślady w mgle (`memories`) | kolejne rozdziały osi |
| 2 | (planowana) `story lint`: NPC z odniesieniem do Wędrowca | Hask, Lis i Dorn rozpoznają znak, szepty w mgle; Dorn ma żal o zawróconą babkę | ktoś, kto Wędrowcowi coś zawdzięcza |
| 3 | `story lint`: porażka z wyjściem; `story paths`: drogi bez walki do każdego finału | dyplomacja, skradanie, walka; obietnice frakcji; rejestr słowa (Kwit, Lis, ekran końca) | skutki liczbowe złamanego słowa (opcja 3 w [ADR 0010](decisions/0010-word-register.md)) |
| 4 | `story lint`: porażka testu zostawia drogę dalej | wskazówki w dzienniku po porażkach | przegrana walka prowadząca dalej ([todo](todo.md)) |
| 5 | `story lint`: obietnice frakcji | trzy frakcje z opisem idei i skutkami ([ADR 0005](decisions/0005-visible-faction-consequences.md)) | spór o idee w dialogu, nie tylko reputacja |
| 6 | (planowana) towarzysz ma okrzyki `companion` i co najmniej jedną własną opcję | komentarze i opcja Lis u Severa | osobisty wątek Lis ([todo](todo.md)) |
| 7 | redakcja | Rdzawy Targ, Łuk bez drzwi, Klucz bez drzwi | poboczne historie |
| 8 | `story paths`: finał osiągalny bez walki | finał przy Mireli albo Łuku po wspomnieniu | finał jako pytanie ([todo](todo.md)) |

Przy przeglądzie sceny zapytaj, którą zasadę realizuje. Jeśli żadnej, scena prawdopodobnie jest tylko
przekazaniem informacji. Wtedy warto ją połączyć z decyzją albo odkryciem.
