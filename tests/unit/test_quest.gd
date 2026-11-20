# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends GutTest
## Testy integracyjne: dialogi, flagi i ścieżki questa „Klucz bez drzwi”.

var gs


func before_each():
	Difficulty.current = "normal"
	Dice.clear_forced()
	Dice.seed_rng(3)
	gs = get_tree().root.get_node("GameState")
	var pc := CharacterBuilder.build({
		"name": "T", "species": "human", "background": "criminal", "class": "rogue",
		"scores": {"str": 8, "dex": 15, "con": 14, "int": 12, "wis": 13, "cha": 10}, "bonus": {"dex": 2, "con": 1},
		"skills": ["persuasion", "insight", "deception", "investigation"],
	})
	gs.new_game(pc)


func _choose_text(r: DialogueRunner, fragment: String) -> void:
	for ch in r.visible_choices():
		if fragment in ch.text:
			r.choose(ch.index)
			return
	fail_test("Brak wyboru zawierającego: " + fragment + " w węźle " + r.current_id)


func test_all_dialogues_load():
	for id in ["hask", "kwit", "mirela", "dorn", "lis", "pchla", "odzwierny", "sever", "backdoor", "chest", "arch"]:
		var r := DialogueRunner.new(gs)
		assert_true(r.start(id), id)
		assert_gt(r.visible_choices().size(), 0, id)


func test_mirela_starts_quest():
	var r := DialogueRunner.new(gs)
	r.start("mirela")
	_choose_text(r, "Co się stało")
	_choose_text(r, "Pomogę ci go")
	assert_eq(gs.quest_stage("key"), "started")
	assert_true("potion_healing" in gs.player.inventory)


func test_kwit_exposes_bluff_after_contract_redemption():
	gs.quests["key"] = "started"
	var r := DialogueRunner.new(gs)
	r.start("kwit")
	_choose_text(r, "Mirelę okradziono")
	Dice.force([20])
	_choose_text(r, "Przysyła mnie Kustoszka")
	assert_eq(gs.faction_attitude("inscribed"), "neutral")
	r.start("kwit")
	assert_eq(r.current_id, "start", "kontrakt nie wrócił jeszcze do Kwita")
	r.start("hask")
	_choose_text(r, "Oddaj kontrakt Kwita")
	r.start("kwit")
	assert_eq(r.current_id, "bluff_exposed")
	assert_eq(gs.faction_attitude("inscribed"), "wary")
	assert_eq(gs.faction_attitude("echo"), "neutral")

	var save_data: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.from_dict(save_data)
	assert_eq(gs.faction_attitude("inscribed"), "wary")
	r.start("kwit")
	assert_eq(r.current_id, "start", "konfrontacja odbywa się raz")
	gs.player.gold = 19
	_choose_text(r, "na sprzedaż miksturę")
	assert_false(r.visible_choices().any(func(ch): return "Kupuję" in ch.text))
	gs.player.gold = 20
	_choose_text(r, "[20 sz.")
	assert_eq(gs.player.gold, 0)
	assert_true("potion_healing" in gs.player.inventory)
	_choose_text(r, "Dziękuję")
	assert_false(r.visible_choices().any(func(ch): return "na sprzedaż miksturę" in ch.text))

	save_data.erase("reputation")
	gs.from_dict(save_data)
	assert_eq(gs.faction_attitude("inscribed"), "neutral", "stare zapisy zaczynają od neutralności")


func test_paying_kwit_for_the_lead_unlocks_friendly_price():
	gs.quests["key"] = "started"
	gs.player.gold = 20
	var r := DialogueRunner.new(gs)
	r.start("kwit")
	_choose_text(r, "na sprzedaż miksturę")
	assert_true(r.visible_choices().any(func(ch): return "[10 sz.]" in ch.text))
	_choose_text(r, "Może później")
	_choose_text(r, "Mirelę okradziono")
	_choose_text(r, "Proszę, dziesięć sztuk")
	assert_eq(gs.faction_attitude("inscribed"), "friendly")
	_choose_text(r, "Dziękuję")
	_choose_text(r, "na sprzedaż miksturę")
	_choose_text(r, "[5 sz.")
	assert_eq(gs.player.gold, 5)


func test_diplomacy_path():
	gs.quests["key"] = "started"
	var r := DialogueRunner.new(gs)
	r.start("pchla")
	Dice.force([15])
	_choose_text(r, "Coś cię gryzie")
	assert_true(gs.has_flag("ambush_warned"))
	assert_eq(gs.quest_stage("key"), "lead_warehouse")
	r = DialogueRunner.new(gs)
	r.start("odzwierny")
	Dice.force([18])
	_choose_text(r, "rozmawiać z Severem")
	assert_true(gs.has_flag("front_open"))
	r = DialogueRunner.new(gs)
	r.start("sever")
	Dice.force([19, 19])
	_choose_text(r, "czysta entropia")
	assert_true("key_without_door" in gs.player.inventory)
	assert_eq(gs.quest_stage("key"), "has_key")
	var ended := []
	gs.world_request.connect(func(e): ended.append(e))
	r = DialogueRunner.new(gs)
	r.start("mirela")
	assert_eq(r.current_id, "wanderer_memory")
	assert_eq(gs.quest_stage("wanderer"), "revealed")
	_through_memory(r)
	_choose_text(r, "Oto twój klucz")
	assert_eq(gs.quest_stage("key"), "done_returned")
	assert_eq(gs.quest_stage("wanderer"), "done_stayed")
	assert_false("key_without_door" in gs.player.inventory)
	assert_true(ended.any(func(e): return e.has("end_game")))
	assert_gte(gs.player.level + gs.player.pending_levels, 2, "awans czeka w oknie awansu")


func test_wanderer_clues_and_memory_survive_a_save_before_the_choice():
	var r := DialogueRunner.new(gs)
	r.start("hask")
	_choose_text(r, "ślad na dłoni")
	assert_eq(gs.quest_stage("wanderer"), "trace")
	r.start("lis")
	_choose_text(r, "Znasz znak z bramy")
	assert_eq(gs.quest_stage("wanderer"), "record")
	r.start("hask")
	assert_false(r.visible_choices().any(func(ch): return "ślad na dłoni" in ch.text))
	r.start("mirela")
	_choose_text(r, "Co się stało")
	_choose_text(r, "Pomogę ci go")
	r.start("lis")
	_choose_text(r, "Szukam skradzionego klucza")
	r.start("backdoor")
	Dice.force([15, 15])
	_choose_text(r, "wytrychem")
	_choose_text(r, "Zakradnij")
	assert_true("key_without_door" in gs.player.inventory)
	r.start("arch")
	assert_eq(r.current_id, "wanderer_memory")
	_choose_text(r, "Potrzebuję chwili")
	var slot := "gut_wanderer_%s" % OS.get_process_id()
	assert_true(gs.save_game(slot))
	gs.quests.erase("wanderer")
	gs.player.inventory.erase("key_without_door")
	assert_true(gs.load_game(slot))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.SAVE_DIR.path_join(slot + ".json")))
	assert_eq(gs.quest_stage("wanderer"), "revealed")
	assert_true("key_without_door" in gs.player.inventory)
	r.start("mirela")
	assert_eq(r.current_id, "return", "wspomnienie nie powtarza się w drugiej scenie")
	_choose_text(r, "Oto twój klucz")
	assert_eq(gs.quest_stage("wanderer"), "done_stayed")


func test_stealth_path():
	gs.quests["key"] = "lead_warehouse"
	var r := DialogueRunner.new(gs)
	r.start("backdoor")
	Dice.force([15, 15])
	_choose_text(r, "wytrychem")
	assert_true(gs.has_flag("back_open"))
	_choose_text(r, "Zakradnij")
	assert_true(gs.has_flag("key_stolen"))
	r = DialogueRunner.new(gs)
	r.start("arch")
	assert_eq(r.current_id, "wanderer_memory")
	assert_eq(gs.quest_stage("wanderer"), "revealed")
	_through_memory(r)
	_choose_text(r, "przekręć")
	assert_eq(gs.quest_stage("key"), "done_portal")
	assert_eq(gs.quest_stage("wanderer"), "done_crossed")
	var xp: int = gs.player.xp
	gs.from_dict(JSON.parse_string(JSON.stringify(gs.to_dict())))
	r.start("arch")
	assert_eq(r.current_id, "after_portal")
	_choose_text(r, "Odejdź")
	assert_eq(gs.player.xp, xp, "ponowne podejście do Łuku nie przyznaje nagrody")


func test_failed_check_starts_combat():
	gs.quests["key"] = "lead_warehouse"
	var reqs := []
	gs.world_request.connect(func(e): reqs.append(e))
	gs.player.heroic_inspiration = false
	var r := DialogueRunner.new(gs)
	r.start("sever")
	Dice.force([1])
	_choose_text(r, "czysta entropia")
	assert_eq(r.current_id, "angry")
	_choose_text(r, "Walcz")
	assert_true(reqs.any(func(e): return e.get("start_combat", "") == "warehouse"))


## Stopień sukcesu (docs/decisions/0008): pasy według zapasu, efekty tylko ze swojego pasa, sygnał z pasem.
func test_check_bands():
	assert_eq(DialogueRunner.check_band({"success": true, "total": 18, "dc": 13}), "boon")
	assert_eq(DialogueRunner.check_band({"success": true, "total": 13, "dc": 13}), "cost")
	assert_eq(DialogueRunner.check_band({"success": false, "total": 9, "dc": 13}), "gain")
	assert_eq(DialogueRunner.check_band({"success": false, "total": 8, "dc": 13}), "fail")
	gs.quests["key"] = "lead_warehouse"
	gs.player.heroic_inspiration = false
	var chk := {"skill": "persuasion", "dc": 13}
	var bands := []
	# sukces o włos: Odźwierny wpuszcza, ale zapamiętuje twarz
	var r := DialogueRunner.new(gs)
	r.check_rolled.connect(func(_t, _ok, _n, band): bands.append(band))
	r.start("odzwierny")
	Dice.force([DialogueRunner.natural_for_margin(gs.player, chk, 0)])
	_choose_text(r, "rozmawiać z Severem")
	assert_eq(r.current_id, "let_in")
	assert_eq(gs.faction_attitude("unravelers"), "wary", "cena: nieufność Rozplataczy")
	assert_false(gs.player.heroic_inspiration)
	# wyraźny sukces: inspiracja, reputacja bez zmian
	gs.reputation.erase("unravelers")
	gs.flags.erase("front_open")
	gs.flags.erase("dlg_odzwierny_start_0")   # wybór jednorazowy ("once")
	r = DialogueRunner.new(gs)
	r.check_rolled.connect(func(_t, _ok, _n, band): bands.append(band))
	r.start("odzwierny")
	Dice.force([20])
	_choose_text(r, "rozmawiać z Severem")
	assert_true(gs.player.heroic_inspiration, "korzyść: Heroiczna inspiracja")
	assert_ne(gs.faction_attitude("unravelers"), "wary")
	# porażka o włos przy zamku: podsłuchana warta daje przewagę w środku
	gs.player.heroic_inspiration = false
	r = DialogueRunner.new(gs)
	r.check_rolled.connect(func(_t, _ok, _n, band): bands.append(band))
	r.start("backdoor")
	var lock := {"skill": "sleight_of_hand", "dc": 13}
	Dice.force([DialogueRunner.natural_for_margin(gs.player, lock, -1)])
	_choose_text(r, "wytrych")
	assert_eq(r.current_id, "lock_fail")
	assert_true(gs.has_flag("overheard_guards"), "coś w zamian: podsłuchana warta")
	assert_eq(bands, ["cost", "boon", "gain"])


## Motywacje (docs/decisions/0009): wybór w kreatorze, opcje widoczne tylko przy swojej motywacji,
## inspiracja raz na opcję (także za wadę), zapis.
func test_motivations():
	var pc := CharacterBuilder.build({"name": "M", "species": "human", "background": "soldier", "class": "fighter",
		"scores": {"str": 15, "dex": 14, "con": 13, "int": 10, "wis": 10, "cha": 8},
		"motivations": {"flaw": "greed", "desire": "nonsense"}})
	assert_eq(pc.motivations.flaw, "greed")
	assert_eq(pc.motivations.desire, CharacterBuilder.default_motivations().desire, "nieznana opcja = domyślna")
	assert_eq(pc.motivations.size(), 4)
	gs.player.motivations = pc.motivations.duplicate()
	gs.player.heroic_inspiration = false
	assert_true(gs.check({"motivation": "flaw:greed"}))
	assert_false(gs.check({"motivation": "flaw:anger"}))
	var r := DialogueRunner.new(gs)
	r.start("mirela")
	r.goto("reward")
	var texts: Array = r.visible_choices().map(func(c): return c.text)
	assert_true(texts.any(func(t): return t.begins_with("[Chciwość]")), "opcja wady widoczna z prefiksem")
	assert_false(texts.any(func(t): return t.begins_with("[Dom]")), "cudza motywacja ukryta")
	_choose_text(r, "jałmużna")
	assert_eq(r.current_id, "reward_no")
	assert_true(gs.player.heroic_inspiration, "odegrana wada daje inspirację")
	gs.player.heroic_inspiration = false
	r.goto("reward")
	_choose_text(r, "jałmużna")
	assert_false(gs.player.heroic_inspiration, "drugi raz ta sama opcja nie daje")
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.player.to_dict()))
	assert_eq(Creature.from_dict(d).motivations.get("flaw", ""), "greed", "motywacje w zapisie")


func test_dorn_remembers_the_wanderer():
	gs.player.motivations = {"strength": "loyalty", "flaw": "pride", "desire": "home", "fear": "oblivion"}
	gs.player.gold = 10
	var r := DialogueRunner.new(gs)
	r.start("dorn")
	assert_eq(r.current_id, "grudge", "pierwsza rozmowa: Dorn rozpoznaje znak")
	_choose_text(r, "Jaki znak")
	assert_eq(gs.quest_stage("wanderer"), "trace", "Dorn to drugie źródło śladu")
	r.start("dorn")
	assert_eq(r.current_id, "start", "żal tylko raz")
	r.goto("grudge")
	assert_false(r.visible_choices().any(func(c): return "Jaki znak" in c.text), "znak już znany")
	_choose_text(r, "[Pycha]")
	assert_true(gs.has_flag("dorn_cold"))
	_choose_text(r, "Wróćmy")
	_choose_text(r, "4 sz.")
	assert_eq(gs.player.gold, 6, "pycha: łóżko podwójnie")
	gs.quests["wanderer"] = "revealed"
	r.start("dorn")
	_choose_text(r, "To byłem ja")
	assert_false(gs.has_flag("dorn_cold"), "wyznanie przywraca zwykłą cenę")
	_choose_text(r, "Dziękuję")
	_choose_text(r, "2 sz.")
	assert_eq(gs.player.gold, 4)


func test_remaining_motivations():
	gs.player.motivations = {"strength": "cunning", "flaw": "greed", "desire": "wealth", "fear": "helplessness"}
	gs.quests["key"] = "started"
	var r := DialogueRunner.new(gs)
	r.start("kwit")
	_choose_text(r, "Mirelę okradziono")
	_choose_text(r, "[Przebiegłość]")
	assert_eq(gs.quest_stage("key"), "lead_warehouse", "przebiegłość: trop za darmo")
	gs.quests["key"] = "started"
	r.start("pchla")
	_choose_text(r, "[Bezradność]")
	assert_eq(r.current_id, "scared")
	r.start("mirela")
	r.goto("truth")
	_choose_text(r, "[Bogactwo]")
	assert_true(gs.has_flag("reward_plus"), "bogactwo: nagroda 150")
	_choose_text(r, "Wróćmy")
	assert_false(r.visible_choices().any(func(c): return "[Bogactwo]" in c.text), "raz")
	gs.player.motivations = {"strength": "loyalty", "flaw": "pride", "desire": "freedom", "fear": "closed_doors"}
	gs.player.inventory.append("key_without_door")
	r.start("hidden_door")
	_choose_text(r, "[Zamknięte drzwi]")
	assert_eq(r.current_id, "listen")
	gs.quests["wanderer"] = "revealed"
	r.start("arch")
	assert_eq(r.current_id, "with_key")
	_choose_text(r, "[Wolność]")
	assert_eq(r.current_id, "freedom")


func test_word_register():
	gs.player.gold = 50
	var r := DialogueRunner.new(gs)
	r.start("kwit")
	_choose_text(r, "rejestr wszystkiego")
	assert_eq(r.current_id, "ledger", "pusty rejestr")
	r.start("mirela")
	_choose_text(r, "Co się stało")
	_choose_text(r, "Pomogę ci go")
	assert_eq(gs.word_state("mirela_key"), "open", "obietnica Mireli")
	r.start("kwit")
	_choose_text(r, "rejestr wszystkiego")
	assert_eq(r.current_id, "ledger_open")
	r.start("lis")
	_choose_text(r, "Co Echo zapisze")
	assert_eq(r.current_id, "words", "bez kłamstw")
	r.start("kwit")
	_choose_text(r, "Mirelę okradziono")
	Dice.force([20])
	_choose_text(r, "Przysyła mnie Kustoszka")
	assert_eq(gs.word_state("kwit_custodian"), "hidden", "kłamstwo nieprzyłapane")
	r.start("lis")
	_choose_text(r, "Co Echo zapisze")
	assert_eq(r.current_id, "words_lies", "Echo pamięta ukryte kłamstwa")
	r.start("kwit")
	_choose_text(r, "rejestr wszystkiego")
	assert_eq(r.current_id, "ledger_open", "Zapisani znają tylko jawne")
	gs.apply_effects([{"oath_kept": "kwit_custodian"}, {"lie_exposed": "kwit_custodian"}])
	assert_eq(gs.word_state("kwit_custodian"), "exposed")
	gs.apply_effects([{"oath_kept": "dorn_ardan"}])
	assert_eq(gs.word_state("dorn_ardan"), "", "nie można dotrzymać słowa, które nie padło")
	gs.apply_effects([{"oath": "pchla_silence"}, {"oath_broken": "mirela_key"}, {"oath": "mirela_key"}])
	assert_eq(gs.word_state("mirela_key"), "broken", "złamanego nie da się dać od nowa")
	assert_true(gs.check({"words_min": ["broken", 1]}))
	assert_true(gs.check({"word": ["pchla_silence", "open"]}))
	r.start("kwit")
	_choose_text(r, "rejestr wszystkiego")
	assert_eq(r.current_id, "ledger_bad")
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.words = {}
	gs.from_dict(d)
	assert_eq(gs.word_state("mirela_key"), "broken", "rejestr w zapisie")
	gs.close_words_at_end()
	assert_eq(gs.word_state("pchla_silence"), "kept", "milczenie dotrzymane na koniec")


func test_memory_conversation():
	gs.player.motivations = {"strength": "compassion", "flaw": "anger", "desire": "home", "fear": "loneliness"}
	gs.player.inventory.append("key_without_door")
	gs.quests["key"] = "has_key"
	gs.apply_effects([{"oath": "mirela_key"}, {"lie": "kwit_custodian"}])
	var r := DialogueRunner.new(gs)
	r.start("arch")
	assert_eq(r.current_id, "wanderer_memory")
	assert_false(r.visible_choices().any(func(c): return "Przyjrzyj się Łukowi" in c.text), "decyzja dopiero po rozmowie")
	_choose_text(r, "wróć do wspomnienia")
	assert_eq(r.dialogue_id, "memory")
	assert_eq(r.current_id, "start")
	var texts: Array = r.visible_choices().map(func(c): return c.text)
	assert_eq(texts.size(), 7, "3 ogólne + 4 motywacje")
	assert_true(texts.any(func(t): return t.begins_with("[Samotność]")))
	assert_false(texts.any(func(t): return t.begins_with("[Pycha]")))
	_choose_text(r, "[Samotność]")
	assert_eq(r.current_id, "why_fear")
	assert_true(gs.has_flag("finale_why_fear"))
	_choose_text(r, "Milcz")
	texts = r.visible_choices().map(func(c): return c.text)
	assert_false(texts.any(func(t): return t == "Tak. Każdego, które dałem."), "kłamstwo: brak czystej odpowiedzi")
	_choose_text(r, "Tak. Każdego.")
	assert_eq(gs.word_state("self_kept"), "exposed", "okłamanie siebie trafia do rejestru")
	assert_false(gs.has_flag("finale_honest"))
	_choose_text(r, "Dalej")
	_choose_text(r, "Wędrowcem")
	assert_true(gs.has_flag("memory_done"))
	_choose_text(r, "Wróć pod Łuk")
	assert_eq(r.dialogue_id, "arch")
	assert_eq(r.current_id, "with_key")
	assert_false(r.visible_choices().any(func(c): return "wróć do wspomnienia" in c.text), "rozmowa tylko raz")
	# czyste słowo i szczerość
	gs.words = {"mirela_key": "open"}
	gs.flags.erase("memory_done")
	r.start("mirela")
	r.goto("return")
	_choose_text(r, "wróć do wspomnienia")
	_choose_text(r, "Nie wiem")
	_choose_text(r, "Milcz")
	_choose_text(r, "Tak. Każdego, które dałem.")
	assert_true(gs.has_flag("finale_honest"), "szczerość: inspiracja na kolejny rozdział")
	_choose_text(r, "Dalej")
	_choose_text(r, "Jeszcze nie wiem")
	_choose_text(r, "Wróć do Mireli")
	assert_eq(r.dialogue_id, "mirela")
	assert_eq(r.current_id, "return")


func test_heroic_inspiration_reroll():
	gs.player.heroic_inspiration = true
	var r := DialogueRunner.new(gs)
	Dice.force([1, 20])
	var res := r.roll_check({"skill": "persuasion", "dc": 15})
	assert_true(res.success)
	assert_false(gs.player.heroic_inspiration)


func test_save_load_roundtrip():
	gs.flags["front_open"] = true
	gs.quests["key"] = "has_key"
	gs.player.inventory.append("key_without_door")
	assert_true(gs.save_game("test"))
	gs.new_game(CharacterBuilder.build({"name": "X", "species": "elf", "background": "sage", "class": "wizard",
		"scores": {"str": 8, "dex": 14, "con": 13, "int": 15, "wis": 12, "cha": 10}}))
	assert_true(gs.load_game("test"))
	assert_true(gs.has_flag("front_open"))
	assert_eq(gs.quest_stage("key"), "has_key")
	assert_eq(gs.player.class_id, "rogue")
	assert_true("key_without_door" in gs.player.inventory)


## Rozmowa z dawnym sobą (memory.json): pierwsza widoczna odpowiedź w każdym węźle, aż wróci do sceny.
func _through_memory(r: DialogueRunner) -> void:
	for ch in r.visible_choices():
		if "wróć do wspomnienia" in ch.text:
			r.choose(ch.index)
			break
	var guard := 0
	while r.dialogue_id == "memory" and guard < 10:
		guard += 1
		r.choose(r.visible_choices()[0].index)
