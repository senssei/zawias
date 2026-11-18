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
	while gs.player.pending_levels > 0:
		var o := Leveling.level_up_options(gs.player)
		var spells: Array = o.spell_choices.slice(0, o.spell_picks)
		var sub: String = o.subclasses[0] if not o.subclasses.is_empty() else ""
		Leveling.apply_level(gs.player, {"hp": "avg", "subclass": sub, "spells": spells})


## Walka jak w świecie: wrogowie ze spawnów spotkania i z NPC przypisanych do spotkania; AI po obu stronach.
func _fight(enc_id: String, player_cell: Vector2i) -> bool:
	var map := DB.map("rusty_market")
	var grid := CombatGrid.new(map)
	var enc := DB.entry("encounters", enc_id)
	for f in enc.get("unlock", []):
		gs.flags[f] = true
	var pc: Creature = gs.player
	pc.grid_pos = player_cell
	var enemies: Array = []
	for s in enc.get("spawn", []):
		var m := CharacterBuilder.create_monster(s.monster, s.id, s.get("name", ""))
		m.grid_pos = Vector2i(int(s.pos[0]), int(s.pos[1]))
		enemies.append(m)
	for n in map.npcs:
		if n.get("encounter", "") == enc_id and n.has("monster") and not n.get("flees", false):
			var m := CharacterBuilder.create_monster(n.monster, n.id, n.name)
			m.grid_pos = Vector2i(int(n.pos[0]), int(n.pos[1]))
			enemies.append(m)
	assert_gt(enemies.size(), 0, enc_id + ": brak wrogów")
	var mgr := CombatManager.new(grid)
	if dbg_log:
		mgr.event.connect(func(e): if e.type in ["log", "turn"]: print("EV ", e.get("text", e.get("id", ""))))
	var surprised: bool = enc.has("surprise_unless_flag") and not gs.has_flag(enc.surprise_unless_flag)
	mgr.start([pc], enemies, surprised)
	var guard := 0
	while mgr.active and guard < 200:
		guard += 1
		var c := mgr.current()
		if c == pc:
			_player_turn(mgr, pc, enemies)
		else:
			AIBasic.take_turn(mgr, c)
		if mgr.active:
			mgr.end_turn()
	assert_false(mgr.active, "%s: walka %s nie skończyła się w 200 turach" % [pc.class_id, enc_id])
	if mgr.victory:
		var xp := 0
		for e in enemies:
			xp += int(DB.entry("monsters", e.template_id).get("xp", 0))
		gs.apply_effects([{"xp": xp}] + enc.get("on_victory", []))
		for e in enemies:
			if not e.id in gs.removed_npcs:
				gs.removed_npcs.append(e.id)
	pc.effects.clear()
	pc.concentration = ""
	return mgr.victory


## Prosta taktyka gracza: leczenie przy niskich PW, najlepszy dostępny czar na najbliższego wroga,
## potem to, co robi AI (podejście i atak bronią). Słabsza od człowieka, ale korzysta z narzędzi klasy.
const SPELL_PRIORITY := ["sleep", "guiding_bolt", "magic_missile", "inflict_wounds", "burning_hands",
	"chromatic_orb", "fire_bolt", "sacred_flame", "ray_of_frost"]


func _player_turn(mgr: CombatManager, pc: Creature, enemies: Array) -> void:
	if pc.hp <= pc.max_hp * 0.4:
		if pc.resource("second_wind") > 0:
			mgr.do_action(pc, "second_wind")
		for sp in ["healing_word", "cure_wounds"]:
			if sp in pc.spells and mgr.can_cast(pc, sp, pc.grid_pos) == "":
				mgr.cast(pc, sp, pc.grid_pos, 1)
				break
	var target: Creature = null
	for e in enemies:
		if e.is_conscious() and (target == null or CombatGrid.distance(pc.grid_pos, e.grid_pos) < CombatGrid.distance(pc.grid_pos, target.grid_pos)):
			target = e
	if target == null or not mgr.active:
		return
	for sp in SPELL_PRIORITY:
		if not (sp in pc.spells or sp in pc.cantrips):
			continue
		var lvl := int(Spellcasting.spell(sp).get("level", 0))
		if mgr.can_cast(pc, sp, target.grid_pos) == "":
			mgr.cast(pc, sp, target.grid_pos, lvl)
			return
	AIBasic.take_turn(mgr, pc)


func _ending() -> Array:
	var ended := []
	gs.world_request.connect(func(e): if e.has("end_game"): ended.append(e))
	return ended


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
		assert_eq(r.current_id, "return", cls)
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
		assert_eq(r.current_id, "with_key", cls)
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
	if not _fight("ambush", Vector2i(31, 6)):
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
		_choose(r, "Oto twój klucz")
		assert_eq(ended.size(), 1, cls + ": zakończenie")
		_take_levels()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.SAVE_DIR.path_join("slice_test.json")))
