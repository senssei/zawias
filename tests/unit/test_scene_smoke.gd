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
