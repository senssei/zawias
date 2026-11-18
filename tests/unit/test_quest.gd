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
	assert_eq(r.current_id, "return")
	_choose_text(r, "Oto twój klucz")
	assert_eq(gs.quest_stage("key"), "done_returned")
	assert_false("key_without_door" in gs.player.inventory)
	assert_true(ended.any(func(e): return e.has("end_game")))
	assert_gte(gs.player.level + gs.player.pending_levels, 2, "awans czeka w oknie awansu")


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
	assert_eq(r.current_id, "with_key")
	_choose_text(r, "przekręć")
	assert_eq(gs.quest_stage("key"), "done_portal")


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
