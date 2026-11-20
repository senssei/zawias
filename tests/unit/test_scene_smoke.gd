# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends GutTest
## Test dymny: świat (world.gd, actor.gd, HUD, audio) ładuje się i buduje bez błędów skryptów.
## Łapie błędy składni w skryptach sceny, których testy zasad nie dotykają.


func test_world_loads_with_actors():
	var gs: Node = get_tree().root.get_node("GameState")
	gs.new_game(CharacterBuilder.build({
		"name": "T", "species": "human", "background": "soldier", "class": "fighter",
		"scores": {"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8}, "bonus": {"str": 2, "con": 1},
	}))
	var world_script := load("res://scripts/world/world.gd")
	assert_not_null(world_script, "world.gd się kompiluje")
	var w: Node3D = world_script.new()
	add_child_autofree(w)
	await wait_frames(3)
	assert_not_null(w.player_actor, "gracz utworzony")
	assert_gt(w.actors.size(), 5, "NPC i obiekty utworzone")
	assert_true(w.player_actor.has_method("walk_step"))
	# krok: ruch i zatrzymanie bez błędów
	var tw: Tween = w.player_actor.walk_step(w.player_actor.cell + Vector2i(1, 0), 4.0, true, true)
	await tw.finished
	w.player_actor.stop_walk()
	assert_false(w.player_actor.is_walking())
	w._on_menu("inventory")
	assert_eq(w.hud.window_title.text, "Ekwipunek")
	var details: Array = w.hud.window_body.find_children("*", "Label", true, false)
	assert_true(details.any(func(label): return label.text.begins_with("Pancerz:")))
	w.hud.show_d20(7, "T")
	assert_false(w.hud.d20_badge.visible)
	w.hud.show_d20(1, "T")
	assert_true(w.hud.d20_badge.visible)
	assert_eq(w.hud.d20_number.text, "1")
	w.hud.show_d20(20, "T")
	assert_eq(w.hud.d20_number.text, "20")


func test_spellbook_casts_through_the_normal_combat_targeting():
	var gs: Node = get_tree().root.get_node("GameState")
	var pc := CharacterBuilder.build({
		"name": "Mag", "species": "human", "background": "sage", "class": "wizard",
		"scores": {"str": 8, "dex": 14, "con": 14, "int": 15, "wis": 12, "cha": 10},
		"bonus": {"int": 2, "con": 1},
	})
	gs.new_game(pc)
	var w: Node3D = load("res://scripts/world/world.gd").new()
	add_child_autofree(w)
	w._on_menu("spellbook")
	assert_eq(w.hud.window_title.text, "Księga czarów")
	assert_null(_spell_button(w.hud, "Magiczny pocisk"))

	pc.grid_pos = w.player_actor.cell
	var enemy := CharacterBuilder.create_monster("bandit", "b")
	enemy.grid_pos = pc.grid_pos + Vector2i(2, 0)
	w.combat = CombatManager.new(w.grid)
	w.mode = "combat"
	Dice.force([20, 1])
	w.combat.start([pc], [enemy])
	Dice.clear_forced()
	w._on_menu("spellbook")
	assert_null(_spell_button(w.hud, "Prestidigitacja"))
	assert_null(_spell_button(w.hud, "Tarcza"))
	var button := _spell_button(w.hud, "Magiczny pocisk")
	assert_not_null(button)
	if button == null:
		return
	assert_false(button.disabled)
	var slots_before := int(pc.slots["1"].cur)
	button.pressed.emit()
	assert_false(w.hud.is_window_open())
	assert_eq(w.selected.kind, "spell")
	assert_eq(w.selected.data.id, "magic_missile")
	assert_eq(int(pc.slots["1"].cur), slots_before, "wybór celu nie wydaje miejsca")
	Dice.force([1, 1, 1])
	w._combat_click(enemy.grid_pos)
	Dice.clear_forced()
	assert_eq(int(pc.slots["1"].cur), slots_before - 1)
	assert_lt(enemy.hp, enemy.max_hp)
	w._on_menu("spellbook")
	assert_true(_spell_button(w.hud, "Magiczny pocisk").disabled)


func _spell_button(hud: HUD, spell_name: String) -> Button:
	for row in hud.window_body.get_children():
		if row is HBoxContainer and row.get_child(0).get_child(0).text == spell_name:
			return row.get_child(1) as Button if row.get_child_count() > 1 else null
	return null


func test_spell_fx_profiles_render_geometry_and_release_it_after_playback():
	var stage := Node3D.new()
	add_child_autofree(stage)
	var profiles := DB.table("spell_fx")
	var spells := DB.table("spells")
	assert_eq(profiles.size(), spells.size())
	for id in spells:
		assert_true(profiles.has(id), id)
		SpellFX.play(stage, id, Vector3.ZERO, Vector3(3, 0, 0), [Vector3(3, 0, 0)], 2)
		assert_gt(stage.get_child(-1).get_child_count(), 0, id)
	await wait_until(func(): return stage.get_child_count() == 0, 3.0)
	assert_eq(stage.get_child_count(), 0, "efekty usuwają geometrię po animacji")
