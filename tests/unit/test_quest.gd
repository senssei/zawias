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
	_choose_text(r, "Porozmawiajmy o kluczu")
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
	_choose_text(r, "Przyjrzyj się Łukowi")
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
