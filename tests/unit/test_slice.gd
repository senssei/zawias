# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends GutTest
## Test przejścia vertical slice'a: każda z 4 klas przechodzi 3 drogi questu „Klucz bez drzwi”
## (dyplomacja, skradanie, walka). Walki rozgrywa AI po obu stronach, rzuty są z ziarna (powtarzalne).
## W drodze walki gra jest zapisywana i wczytywana w połowie, a oczekujące awanse są przyjmowane jak w oknie awansu.

const CLASSES := ["fighter", "rogue", "wizard", "cleric"]

var gs
var dbg_log := false


func before_each():
	Difficulty.current = "normal"
	Dice.clear_forced()
	gs = get_tree().root.get_node("GameState")


## Postać jak w szybkim starcie (main.gd), z umiejętnościami potrzebnymi na drogach questu.
func _new_game(cls: String) -> void:
	var opts := {
		"name": "Test", "species": "human", "background": "soldier", "class": cls,
		"scores": {"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8},
		"bonus": {"str": 2, "con": 1},
	}
	match cls:
		"wizard":
			opts.scores = {"str": 8, "dex": 14, "con": 13, "int": 15, "wis": 12, "cha": 10}
			opts.bonus = {"int": 2, "con": 1}
			opts.background = "sage"
		"rogue":
			opts.scores = {"str": 8, "dex": 15, "con": 14, "int": 12, "wis": 13, "cha": 10}
			opts.bonus = {"dex": 2, "con": 1}
			opts.background = "criminal"
		"cleric":
			opts.scores = {"str": 14, "dex": 8, "con": 13, "int": 10, "wis": 15, "cha": 12}
			opts.bonus = {"wis": 2, "cha": 1}
			opts.background = "acolyte"
	gs.new_game(CharacterBuilder.build(opts))


func _choose(r: DialogueRunner, fragment: String) -> bool:
	for ch in r.visible_choices():
		if fragment in ch.text:
			r.choose(ch.index)
			return true
	fail_test("%s: brak wyboru „%s” w węźle %s (dialog %s)" % [gs.player.class_id, fragment, r.current_id, r.dialogue_id])
	return false


func _talk(id: String, choices: Array, dice: Array = []) -> DialogueRunner:
	var r := DialogueRunner.new(gs)
	assert_true(r.start(id), id)
	if not dice.is_empty():
		Dice.force(dice)
	for c in choices:
		if not _choose(r, c):
			break
	return r


## Przyjmuje wszystkie oczekujące awanse (średnie PW, pierwsza podklasa, pierwsze czary z listy).
func _take_levels() -> void:
	CombatSim.take_levels(gs.player)


## Walka jak w świecie (tools/dev/combat_sim.gd, ta sama symulacja co w pipeline.sh story balance).
func _fight(enc_id: String, player_cell: Vector2i) -> bool:
	var log_cb := (func(t): print("EV ", t)) if dbg_log else Callable()
	return CombatSim.fight(gs, enc_id, player_cell, log_cb)


func _ending() -> Array:
	var ended := []
	gs.world_request.connect(func(e): if e.has("end_game"): ended.append(e))
	return ended


func test_kwit_contract_skips_ambush_once_without_combat_rewards():
	_new_game("rogue")
	_talk("mirela", ["Co się stało", "Pomogę ci go"])
	_talk("kwit", ["Mirelę okradziono", "Przysyła mnie Kustoszka"], [20])
	assert_true("kwit_contract" in gs.player.inventory)
	assert_eq(gs.quest_stage("key"), "lead_warehouse")
	var map := DB.map("rusty_market")
	var ambush: Dictionary = map.triggers[0]
	assert_true(gs.check(ambush["if"]), "sam kontrakt nie wyłącza zasadzki")

	var xp_before: int = gs.player.xp
	var r := _talk("hask", ["Oddaj kontrakt Kwita"])
	assert_eq(r.current_id, "clear_alley")
	assert_false("kwit_contract" in gs.player.inventory)
	assert_false("rust_token" in gs.player.inventory)
	assert_eq(gs.player.xp, xp_before)
	assert_eq(gs.quest_stage("key"), "lead_warehouse")
	assert_false(gs.check(ambush["if"]))
	r.choose(0)

	var saved: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	_new_game("rogue")
	gs.from_dict(saved)
	assert_false("kwit_contract" in gs.player.inventory)
	assert_false(gs.check(ambush["if"]))
	r = _talk("hask", [])
	assert_false(r.visible_choices().any(func(ch): return "Oddaj kontrakt Kwita" in ch.text))
	var world: Node3D = load("res://scripts/world/world.gd").new()
	add_child_autofree(world)
	await wait_physics_frames(3)
	for cell in ambush.cells:
		assert_false(world._check_triggers(Vector2i(int(cell[0]), int(cell[1]))))
	assert_eq(world.mode, "explore")


func test_diplomacy_path_all_classes():
	for cls in CLASSES:
		Dice.seed_rng(11)
		_new_game(cls)
		_talk("mirela", ["Co się stało", "Pomogę ci go"])
		assert_eq(gs.quest_stage("key"), "started", cls)
		_talk("pchla", ["Coś cię gryzie"], [15])
		assert_eq(gs.quest_stage("key"), "lead_warehouse", cls)
		_talk("odzwierny", ["rozmawiać z Severem"], [18])
		assert_true(gs.has_flag("front_open"), cls)
		_talk("sever", ["czysta entropia"], [19, 19])
		assert_eq(gs.quest_stage("key"), "has_key", cls)
		var ended := _ending()
		var r := _talk("mirela", [])
		assert_eq(r.current_id, "wanderer_memory", cls)
		_choose(r, "Porozmawiajmy o kluczu")
		_choose(r, "Oto twój klucz")
		assert_eq(gs.quest_stage("key"), "done_returned", cls)
		assert_eq(ended.size(), 1, cls + ": zakończenie")
		_take_levels()
		assert_gte(gs.player.level, 2, cls)


func test_stealth_path_all_classes():
	for cls in CLASSES:
		Dice.seed_rng(12)
		_new_game(cls)
		_talk("mirela", ["Co się stało", "Pomogę ci go"])
		_talk("pchla", ["Coś cię gryzie"], [15])
		if "thieves_tools" in gs.player.inventory:   # łotrzyk: wytrych w tylnych drzwiach
			_talk("backdoor", ["wytrychem"], [15, 15])
			assert_true(gs.has_flag("back_open"), cls)
		else:                                        # pozostali: Odźwierny wpuszcza frontem
			_talk("odzwierny", ["rozmawiać z Severem"], [18])
			assert_true(gs.has_flag("front_open"), cls)
		_talk("chest", ["po cichu"], [16, 16])   # ciężki pancerz: utrudnienie, dwie kości
		assert_true("key_without_door" in gs.player.inventory, cls)
		var ended := _ending()
		var r := _talk("arch", [])
		assert_eq(r.current_id, "wanderer_memory", cls)
		_choose(r, "Przyjrzyj się Łukowi")
		_choose(r, "przekręć")
		assert_eq(gs.quest_stage("key"), "done_portal", cls)
		assert_eq(ended.size(), 1, cls + ": zakończenie")


## Czy drogę walki da się przejść (nie balans): każda klasa musi wygrać na którymś z kilku ziaren.
## Balans mierzy symulacja opisana w README (tryb „Opowieść” jest domyślny, bo slice jest solowy).
func _combat_path(cls: String, seed: int) -> bool:
	Dice.seed_rng(seed)
	_new_game(cls)
	_talk("mirela", ["Co się stało", "Pomogę ci go"])
	_talk("kwit", ["Mirelę okradziono", "dziesięć sztuk"])
	if not gs.has_flag("asked_about_key"):
		return false
	if not _fight("ambush", Vector2i(37, 7)):
		return false
	_take_levels()
	gs.player.hp = gs.player.max_hp   # długi odpoczynek przed magazynem
	assert_true(gs.save_game("slice_test"), cls)
	_new_game("fighter" if cls != "fighter" else "rogue")
	assert_true(gs.load_game("slice_test"), cls)
	assert_eq(gs.player.class_id, cls, "wczytanie w połowie")
	assert_eq(gs.quest_stage("key"), "lead_warehouse", cls)
	return _fight("warehouse", Vector2i(29, 15))


func test_combat_path_all_classes_with_save_load():
	Difficulty.current = "story"
	for cls in CLASSES:
		var won := false
		for k in 20:
			if _combat_path(cls, 13 + k * 101):
				won = true
				break
		assert_true(won, cls + ": nie udało się przejść drogi walki na 20 ziarnach")
		if not won:
			continue
		assert_true(gs.has_flag("warehouse_cleared"), cls)
		_talk("chest", ["Zabierz wszystko"])
		assert_true("key_without_door" in gs.player.inventory, cls)
		var ended := _ending()
		var r := _talk("mirela", [])
		_choose(r, "Porozmawiajmy o kluczu")
		_choose(r, "Oto twój klucz")
		assert_eq(ended.size(), 1, cls + ": zakończenie")
		_take_levels()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.SAVE_DIR.path_join("slice_test.json")))


## Porażki wymuszają [1, 1]: pierwszy rzut i automatyczny przerzut z Heroicznej inspiracji (człowiek).

## P1 porażki: po odmowie Odźwiernego dziennik wskazuje tylne drzwi, a wojownik bez wytrycha je wyważa.
## Słaby czarodziej, któremu nie wyjdzie ani rozmowa, ani wyważenie, wciąż ma wejście siłą frontem.
func test_doorkeeper_refusal_points_to_back_door():
	for cls in ["fighter", "wizard"]:
		_new_game(cls)
		_talk("mirela", ["Co się stało", "Pomogę ci go"])
		_talk("pchla", ["Coś cię gryzie"], [15])
		var r := _talk("odzwierny", ["rozmawiać z Severem"], [1, 1])
		assert_eq(r.current_id, "refuse", cls)
		assert_true(gs.journal.back().contains("tylne drzwi"), cls + ": dziennik wskazuje inną drogę")
		_choose(r, "[Odejdź]")
		r = _talk("odzwierny", [])
		assert_false(r.visible_choices().any(func(ch): return "rozmawiać z Severem" in ch.text), cls + ": prośba była jednorazowa")
		var requests := []
		gs.world_request.connect(func(e): requests.append(e))
		if cls == "fighter":
			r = _talk("backdoor", ["Wyważ"], [20])
			assert_true(gs.has_flag("back_open"), cls)
			_choose(r, "[Walcz]")
			assert_true(requests.any(func(e): return e.get("start_combat", "") == "warehouse"), cls + ": walka w magazynie")
		else:
			r = _talk("backdoor", ["Wyważ"], [1, 1])
			assert_eq(r.current_id, "force_fail", cls)
			assert_true(gs.journal.back().contains("Odźwierny"), cls + ": dziennik wraca do frontu")
			_choose(r, "[Odejdź]")
			r = _talk("backdoor", [])
			assert_false(r.visible_choices().any(func(ch): return "Wyważ" in ch.text), cls)
			r = _talk("odzwierny", ["Zejdź mi z drogi", "[Walcz]"])
			assert_true(requests.any(func(e): return e.get("start_combat", "") == "warehouse"), cls + ": ostatnia droga to walka")


## P1 porażki: bez pieniędzy i po nieudanej rozmowie z Kwitem dziennik kieruje do Pchły i Lis; Lis daje trop za darmo.
func test_no_money_kwit_refuses_then_lis_gives_lead():
	_new_game("fighter")
	_talk("mirela", ["Co się stało", "Pomogę ci go"])
	gs.player.gold = 0
	var r := _talk("kwit", ["Mirelę okradziono"])
	assert_false(r.visible_choices().any(func(ch): return "dziesięć sztuk" in ch.text), "bez złota nie ma opcji zapłaty")
	r = _talk("kwit", ["Mirelę okradziono", "inną umowę"], [1, 1])
	assert_eq(r.current_id, "no_deal")
	assert_true(gs.journal.back().contains("Lis"), "dziennik wskazuje inne źródło")
	_choose(r, "Do widzenia")
	r = _talk("kwit", ["Mirelę okradziono", "Kustoszka"], [1, 1])
	assert_eq(r.current_id, "no_deal")
	assert_eq(gs.journal.filter(func(j): return j.begins_with("Kwit nie powie")).size(), 1, "ta sama porażka nie dubluje wpisu")
	r = _talk("pchla", [])
	assert_false(r.visible_choices().any(func(ch): return "(5 sz.)" in ch.text), "Pchła też chce złota")
	_talk("lis", ["Szukam skradzionego klucza"])
	assert_eq(gs.quest_stage("key"), "lead_warehouse")


## P1 porażki: zaklinowany zamek u łotrzyka zostawia wyważenie i front; z frontu łotrzyk kradnie klucz po cichu.
func test_jammed_lock_leaves_front_door():
	_new_game("rogue")
	_talk("mirela", ["Co się stało", "Pomogę ci go"])
	_talk("pchla", ["Coś cię gryzie"], [15])
	var r := _talk("backdoor", ["wytrychem"], [1, 1])
	assert_eq(r.current_id, "lock_fail")
	assert_true(gs.journal.back().contains("Odźwiernego"), "dziennik wskazuje front")
	_choose(r, "Spróbuję inaczej")
	assert_false(r.visible_choices().any(func(ch): return "wytrychem" in ch.text), "zamek zaklinowany")
	assert_true(r.visible_choices().any(func(ch): return "Wyważ" in ch.text), "zostaje wyważenie")
	_choose(r, "[Odejdź]")
	_talk("odzwierny", ["rozmawiać z Severem"], [18])
	assert_true(gs.has_flag("front_open"))
	_talk("chest", ["po cichu"], [18])
	assert_true("key_without_door" in gs.player.inventory)


## P1 balans: czarodziej sam, bez Lis, na Normalnym (zasadzka bez ostrzeżenia, potem magazyn po odpoczynku),
## ze skalowaniem solo ze spotkań (bez drugiego bandyty i bez mefita).
## Mierzy odsetek wygranych na stałych ziarnach. Wymaga tylko, żeby droga była osiągalna; liczba trafia do raportu GUT.
func test_wizard_solo_normal_combat_rate():
	Difficulty.current = "normal"
	var wins := {"ambush": 0, "warehouse": 0}
	var runs := 12
	for k in runs:
		Dice.seed_rng(500 + k * 37)
		_new_game("wizard")
		_talk("mirela", ["Co się stało", "Pomogę ci go"])
		_talk("kwit", ["Mirelę okradziono", "dziesięć sztuk"])
		if _fight("ambush", Vector2i(37, 7)):
			wins.ambush += 1
		else:   # w grze porażka = wczytanie i ponowna próba; magazyn mierzymy na poziomie po wygranej zasadzce
			gs.apply_effects([{"xp": 275}])
		_take_levels()
		Rest.long_rest(gs.player)
		if _fight("warehouse", Vector2i(29, 15)):
			wins.warehouse += 1
	gut.p("czarodziej solo, Normalny: zasadzka %d/%d, magazyn %d/%d (poziom %d)" % [wins.ambush, runs, wins.warehouse, runs, gs.player.level])
	# próg regresji dla skalowania solo (encounters.json "solo"); taktyka testowa nie pije mikstur, człowiek gra lepiej
	assert_eq(gs.player.level, 2, "po zasadzce gracz wchodzi do magazynu na 2. poziomie")
	assert_gte(wins.ambush, 9, "zasadzka solo do wygrania na Normalnym")
	assert_gte(wins.warehouse, 6, "magazyn solo do wygrania na Normalnym")
