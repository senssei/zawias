extends GutTest

var grid: CombatGrid


func before_each():
	Difficulty.current = "normal"
	Dice.clear_forced()
	Dice.seed_rng(7)
	grid = CombatGrid.new(DB.map("rusty_market"))


func _pc() -> Creature:
	var c := CharacterBuilder.build({
		"name": "Bohater", "species": "human", "background": "soldier", "class": "fighter",
		"scores": {"str": 15, "dex": 13, "con": 14, "int": 8, "wis": 12, "cha": 10},
		"bonus": {"str": 2, "con": 1}, "choice": "defense",
	})
	return c


func test_grid_basics():
	assert_eq(grid.width, 40)
	assert_eq(grid.height, 20)
	assert_false(grid.is_open(Vector2i(0, 0)))
	assert_true(grid.is_open(Vector2i(1, 8)))
	assert_true(grid.difficult.has(Vector2i(24, 8)))
	var path := grid.find_path(Vector2i(1, 8), Vector2i(16, 6))
	assert_gt(path.size(), 10)
	assert_true(grid.has_los(Vector2i(2, 8), Vector2i(20, 8)))
	assert_false(grid.has_los(Vector2i(20, 11), Vector2i(34, 15)))


func test_reachable_respects_difficult_terrain():
	var r := grid.reachable(Vector2i(22, 8), 2, {})
	assert_true(r.has(Vector2i(20, 8)))
	assert_true(r.has(Vector2i(23, 8)))  # zwykłe
	assert_false(r.has(Vector2i(25, 8)))  # 23(1) + 24(~,2) = 3 > 2


func test_full_combat_runs_to_end():
	var pc := _pc()
	pc.grid_pos = Vector2i(10, 8)
	var b1 := CharacterBuilder.create_monster("bandit", "b1")
	b1.grid_pos = Vector2i(14, 8)
	var b2 := CharacterBuilder.create_monster("bandit", "b2")
	b2.grid_pos = Vector2i(16, 6)
	var mgr := CombatManager.new(grid)
	var events := []
	mgr.event.connect(func(e): events.append(e))
	mgr.start([pc], [b1, b2])
	var safety := 0
	while mgr.active and safety < 60:
		safety += 1
		assert_eq(mgr.current(), pc)
		var target: Creature = null
		for e in [b1, b2]:
			if e.is_conscious():
				target = e
				break
		var opt := Attack.weapon_option(pc, "longsword")
		if CombatGrid.distance(pc.grid_pos, target.grid_pos) > 1:
			var reach := mgr.reachable_for(pc)
			var best := pc.grid_pos
			for p in reach.keys():
				if p is Vector2i and CombatGrid.distance(p, target.grid_pos) < CombatGrid.distance(best, target.grid_pos):
					best = p
			if best != pc.grid_pos:
				mgr.move(pc, best)
		if mgr.active and mgr.can_attack(pc, opt, target) == "":
			mgr.attack(pc, opt, target)
		if pc.hp < 6 and pc.resource("second_wind") > 0 and mgr.active:
			mgr.do_action(pc, "second_wind")
		if mgr.active:
			mgr.end_turn()
	assert_false(mgr.active)
	assert_true(mgr.finished)
	var types := events.map(func(e): return e.type)
	assert_true("initiative" in types)
	assert_true("attack" in types)
	assert_true("end" in types)


func test_opportunity_attack():
	var pc := _pc()
	pc.grid_pos = Vector2i(10, 8)
	var b := CharacterBuilder.create_monster("bandit", "b1")
	b.grid_pos = Vector2i(11, 8)
	var mgr := CombatManager.new(grid)
	var logs := []
	mgr.event.connect(func(e): if e.type == "log": logs.append(e.text))
	Dice.force([20, 1])  # inicjatywa: gracz 20, bandyta 1
	mgr.start([pc], [b])
	assert_eq(mgr.current(), pc)
	mgr.move(pc, Vector2i(7, 8))
	assert_true(logs.any(func(t): return "okazyjny" in t))


func test_spell_area_sleep():
	var c := CharacterBuilder.build({
		"name": "Mag", "species": "human", "background": "sage", "class": "wizard",
		"scores": {"str": 8, "dex": 14, "con": 14, "int": 15, "wis": 12, "cha": 10}, "bonus": {"int": 2, "con": 1},
	})
	c.grid_pos = Vector2i(10, 8)
	var a := CharacterBuilder.create_monster("cultist", "a")
	a.grid_pos = Vector2i(15, 8)
	var b := CharacterBuilder.create_monster("cultist", "b")
	b.grid_pos = Vector2i(16, 9)
	var mgr := CombatManager.new(grid)
	Dice.force([20, 1, 1])
	mgr.start([c], [a, b])
	assert_eq(mgr.spell_targets(c, "sleep", Vector2i(15, 8)).size(), 2)
	Dice.force([1, 1])
	assert_eq(mgr.cast(c, "sleep", Vector2i(15, 8)), "")
	assert_true(a.has_condition("unconscious"))
	assert_true(b.has_condition("unconscious"))
	assert_false(mgr.active)  # wszyscy wrogowie śpią -> zwycięstwo


func test_sleep_spares_caster_in_area():
	# SRD 5.2: Uśpienie działa na istoty według wyboru, więc mag w obszarze nie usypia sam siebie
	var c := CharacterBuilder.build({
		"name": "Mag", "species": "human", "background": "sage", "class": "wizard",
		"scores": {"str": 8, "dex": 14, "con": 14, "int": 15, "wis": 12, "cha": 10}, "bonus": {"int": 2, "con": 1},
	})
	c.grid_pos = Vector2i(10, 8)
	var a := CharacterBuilder.create_monster("cultist", "a")
	a.grid_pos = Vector2i(11, 8)
	var mgr := CombatManager.new(grid)
	Dice.force([20, 1])
	mgr.start([c], [a])
	var t := mgr.spell_targets(c, "sleep", Vector2i(11, 8))
	assert_eq(t.size(), 1)
	assert_false(c in t)
