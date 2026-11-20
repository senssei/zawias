# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends GutTest
## Towarzyszka (Lis): dołączenie z dialogu, poziom gracza, zapis, chodzenie za graczem, walka pod AI, odejście.

const OPTS := {
	"name": "T", "species": "human", "background": "soldier", "class": "fighter",
	"scores": {"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8}, "bonus": {"str": 2, "con": 1},
}


func _gs() -> Node:
	return get_tree().root.get_node("GameState")


func after_each():
	_gs().companions = []


func test_join_from_dialogue_levels_and_saves():
	var gs := _gs()
	gs.new_game(CharacterBuilder.build(OPTS))
	gs.quests["key"] = "started"
	gs.apply_effects([{"xp": 300}])           # gracz: poziom 2 (awans czeka w oknie)
	var r := DialogueRunner.new(gs)
	r.start("lis")
	var labels: Array = r.visible_choices().map(func(c): return c.text)
	assert_true(labels.any(func(t): return t.begins_with("Pójdziesz ze mną")), "opcja zabrania Lis po przyjęciu zadania")
	r.goto("join")
	r.choose(0)
	var lis: Creature = gs.companion("lis")
	assert_not_null(lis, "Lis w drużynie")
	assert_eq(lis.team, "party")
	assert_false(lis.is_player)
	assert_eq(lis.class_id, "wizard")
	assert_eq(lis.level, 2, "dogania poziom gracza")
	assert_true(gs.has_flag("lis_joined"))
	assert_true(gs.check({"in_party": "lis"}))
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.new_game(CharacterBuilder.build(OPTS))
	assert_null(gs.companion("lis"))
	gs.from_dict(d)
	assert_not_null(gs.companion("lis"), "towarzyszka wraca z zapisu")
	assert_eq(gs.companion("lis").max_hp, lis.max_hp)
	r.start("lis")
	assert_eq(r.current_id, "companion", "rozmowa z towarzyszką")
	r.choose(1)
	assert_null(gs.companion("lis"), "odesłana do Archiwum")
	assert_false(gs.has_flag("lis_joined"))


func test_follower_trails_player_and_swaps():
	var gs := _gs()
	gs.new_game(CharacterBuilder.build(OPTS))
	var w: Node3D = load("res://scripts/world/world.gd").new()
	add_child_autofree(w)
	await wait_frames(3)
	gs.join_party("lis")
	var lis: Actor = w.actors["lis"]
	assert_true(w._is_follower(lis), "aktor Lis jest towarzyszem")
	assert_false(w._occupied().has(lis.cell), "nie blokuje drogi graczowi")
	var kinds: Array = w._map_markers().filter(func(m): return m.name == lis.display_name).map(func(m): return m.kind)
	assert_eq(kinds, ["ally"], "na mapie jako sojusznik")
	# ustaw obok gracza i przejdź dwa kroki: Lis idzie śladem
	w.player_actor.place(Vector2i(10, 8))
	lis.place(Vector2i(9, 8))
	w._follow(Vector2i(10, 8), Vector2i(11, 8), 50.0, false)
	w.player_actor.place(Vector2i(11, 8))
	w._follow(Vector2i(11, 8), Vector2i(12, 8), 50.0, true)
	await wait_seconds(0.3)
	assert_eq(lis.creature.grid_pos, Vector2i(11, 8), "na polu, które gracz zwolnił")
	# gracz wchodzi na pole towarzyszki: zamiana
	w.player_actor.place(Vector2i(12, 8))
	w._follow(Vector2i(12, 8), Vector2i(11, 8), 50.0, true)
	assert_eq(lis.creature.grid_pos, Vector2i(12, 8), "zamiana miejscami")


func test_companion_fights_with_ai_and_casts():
	var gs := _gs()
	gs.new_game(CharacterBuilder.build(OPTS))
	gs.quests["key"] = "started"
	var lis: Creature = gs.join_party("lis")
	assert_true(lis.cantrips.size() > 0, "czarodziejka ma sztuczki")
	var grid := CombatGrid.new(DB.map("rusty_market"))
	var pc: Creature = gs.player
	pc.grid_pos = Vector2i(10, 8)
	lis.grid_pos = Vector2i(9, 8)
	var foe := CharacterBuilder.create_monster("bandit", "b1", "Bandyta")
	foe.grid_pos = Vector2i(16, 8)
	var mgr := CombatManager.new(grid)
	var spells := []
	mgr.event.connect(func(e): if e.type == "spell" and e.id == "lis": spells.append(e.spell))
	Dice.seed_rng(7)
	mgr.start([pc, lis], [foe], false)
	var guard := 0
	while mgr.active and guard < 40:
		guard += 1
		if mgr.current() == pc:
			mgr.end_turn()
		else:
			break
	assert_true(spells.size() > 0 or not mgr.active, "Lis rzuca sztuczkę w swojej turze (AI)")
	assert_true(not mgr.active or mgr.current() != lis, "tura towarzyszki nie czeka na gracza")


## Sterowanie towarzyszką: z control_party tura Lis czeka na gracza, a świat podaje jej pasek akcji,
## księgę i kliknięcia (czar Lis, nie gracza). Bez control_party (ustawienie wyłączone) walczy sama.
func test_player_controls_companion_turn():
	var gs := _gs()
	gs.new_game(CharacterBuilder.build(OPTS))
	gs.quests["key"] = "started"
	var lis: Creature = gs.join_party("lis")
	var grid := CombatGrid.new(DB.map("rusty_market"))
	var pc: Creature = gs.player
	pc.grid_pos = Vector2i(10, 8)
	lis.grid_pos = Vector2i(9, 8)
	var foe := CharacterBuilder.create_monster("bandit", "b1", "Bandyta")
	foe.grid_pos = Vector2i(16, 8)
	var mgr := CombatManager.new(grid)
	mgr.control_party = true
	Dice.seed_rng(7)
	mgr.start([pc, lis], [foe], false)
	var guard := 0
	while mgr.active and mgr.current() != lis and guard < 20:
		guard += 1
		if mgr.current() == pc:
			mgr.end_turn()
	assert_eq(mgr.current(), lis, "tura Lis czeka na gracza")
	assert_true(mgr.is_controlled(lis))
	assert_false(mgr.is_controlled(foe))
	# świat: _acting() to Lis, a kliknięcie w wroga z wybranym czarem rzuca czar Lis
	var w: Node3D = load("res://scripts/world/world.gd").new()
	add_child_autofree(w)
	await wait_frames(3)
	w.combat = mgr
	w.mode = "combat"
	assert_true(w._player_can_act())
	assert_eq(w._acting(), lis)
	var casts := []
	mgr.event.connect(func(e): if e.type == "spell": casts.append(e.id))
	var cantrip: String = lis.cantrips.filter(func(c): return Spellcasting.spell(c).get("target", "") == "enemy")[0]
	w._on_combat_action("spell", {"id": cantrip})
	w._combat_click(foe.grid_pos)
	assert_eq(casts, ["lis"], "czar rzuciła Lis")
	w.mode = "explore"
	w.combat = null
	# ustawienie wyłączone: AI
	var mgr2 := CombatManager.new(grid)
	assert_false(mgr2.is_controlled(lis), "domyślnie w menedżerze: towarzysze pod AI")
