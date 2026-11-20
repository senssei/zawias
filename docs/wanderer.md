# Kim jest Wędrowiec?

Wędrowiec to postać gracza. Była pierwszym strażnikiem przejść Zawiasu. Ludzie zaczęli prosić ją o zgodę na każdą podróż. Oddała więc bramie swoje imię, żeby zrzec się prawa do decydowania, kto przejdzie. Po drugiej stronie ułożyła sobie życie. Imię, klasa i pochodzenie wybrane podczas tworzenia postaci opisują to życie. Klucz bez drzwi zachował jedno wspomnienie z Zawiasu. Budzi je dotyk postaci, gdy klucz wraca do niej na Targu.

## Rdzawy Targ

| Etap | Czego dowiaduje się gracz | Co może zrobić |
|---|---|---|
| Ślad | Trzy kreski na dłoni odpowiadają nacięciom na bramie. | Pokazać znak Haskowi albo usłyszeć od Dorna o babce zawróconej spod bramy, potem pójść do Archiwum Echa. Po wspomnieniu można Dornowi wyznać prawdę. |
| Zapis | Wędrowiec oddał bramie imię. Klucz pamięta, co się wtedy stało. | Zapytać Lis w Archiwum lub podczas podróży. Trop działa również po pominięciu Haska. |
| Wspomnienie | Ręka, która nacięła znak, należy do gracza. Jego własny głos wypowiada przysięgę. | Obejrzeć wspomnienie u Mireli lub przy Łuku. Sceny mają ten sam skutek w dzienniku i występują bez testu umiejętności. Potem rozmowa z dawnym sobą (`memory`): dlaczego oddał imię, czy dotrzymał słowa, kim jest teraz. Gracz może odłożyć decyzję i wrócić później. |
| Decyzja | Wiedza o przeszłości nie odbiera prawa do obecnego imienia ani do wyboru. | Oddać klucz Mireli i zostać na Targu albo przekroczyć Łuk, żeby dowiedzieć się, kto dziś rozporządza drogami. |

Wspomnienie jest dostępne po odzyskaniu klucza każdą z trzech dróg. Oba finały wymagają przejścia przez ten etap. Dodatkowe tropy nadają wspomnieniu kontekst, a sam finał pozostaje czytelny, jeśli gracz ich nie zobaczył.

## Kierunek dalszych rozdziałów

1. **Kto rozporządza przejściami?** Po Targu gracz widzi bramę, którą różne frakcje utrzymują i obsługują na różnych warunkach. Porównuje obecne zasady z własną przysięgą i sprawdza, dla kogo droga jest faktycznie dostępna.
2. **Dlaczego brama przyjęła imię?** Kustoszka zna skutki przysięgi i ma własny powód, by pilnować przejść. Gracz zestawia jej świadectwo z rejestrem Zapisanych i zapisem Echa. Każde źródło daje dostęp do innego działania, także przy niskiej reputacji w jednej z frakcji.
3. **Kto powinien strzec drogi?** Finał całej gry sprawdza przysięgę w praktyce. Gracz decyduje, komu powierzyć odpowiedzialność za przejścia i kto ponosi koszt utrzymywania ich otwartych. To dalszy projekt, a grywalna część kończy się dziś na decyzji na Rdzawym Targu.

## Pipeline

```bash
tools/pipeline/pipeline.sh story arc wanderer
tools/pipeline/pipeline.sh story check
./run_tests.sh
```

`data/story_arcs.json` przypisuje etapy do scen dialogowych, które je ustawiają. Przy kolejnym rozdziale najpierw zapisz odkrycie i wynikającą z niego decyzję. Dodaj scenę w polskim JSON, zaktualizuj manifest osi i etap dziennika, a potem przejdź scenę z tropem i bez niego. Po akceptacji tekstu przygotuj nakładkę angielską i nagrania.

W playteście zapytaj gracza, kiedy podejrzewał związek z Wędrowcem, co ostatecznie go o tym przekonało i dlaczego oddał klucz lub przekroczył Łuk. Oddzielnie sprawdź, czy osoba, która pominęła Haska i Lis, rozumie finał bez dodatkowego wyjaśnienia.

## Mgła ze Szczeliny

Fioletowa mgła wojny ma uzasadnienie w świecie. To pustka ze Szczeliny między planami, która wciska się tam, gdzie
nikt nie patrzy. Miasto stoi, bo ktoś je pamięta, więc mgła rzednieje tam, gdzie postać spojrzy. Wokół Wędrowca
jest jej więcej niż wokół innych przybyszów, bo oddając bramie imię, Wędrowiec wypadł z pamięci miasta. Hask mówi
o tym przy bramie (`hask/fog`). Szepty z mgły i ślady w niej to więc miasto, które próbuje go sobie przypomnieć.

