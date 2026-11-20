# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends GutTest
## Okrzyki na targu: dane, wybór najbliższej postaci, warunki stanu gry, przerwy, dymek.

const OPTS := {
	"name": "T", "species": "human", "background": "soldier", "class": "fighter",
	"scores": {"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8}, "bonus": {"str": 2, "con": 1},
}


func test_barks_reference_map_npcs():
	var ids: Array = DB.map("rusty_market").npcs.map(func(n): return n.id)
	for npc in DB.table("barks").keys():
		assert_true(npc in ids, "okrzyki %s: NPC jest na mapie" % npc)
		for b in DB.table("barks")[npc]:
			assert_true(str(b.get("text", "")).length() > 3, npc)


func test_pick_bark_near_npc_with_conditions_and_cooldown():
	var gs: Node = get_tree().root.get_node("GameState")
	gs.new_game(CharacterBuilder.build(OPTS))
	var w: Node3D = load("res://scripts/world/world.gd").new()
	add_child_autofree(w)
	await wait_frames(3)
	var mirela: Actor = w.actors["mirela"]
	w.player_actor.place(mirela.cell + Vector2i(0, 2))
	w._reveal_around(w.player_actor.cell)    # w grze krok odkrywa okolicę; postać we mgle nie woła
	if w.fog:
		w.fog.update_actors(0.0, true)
	var b: Dictionary = w.pick_bark(1000.0)
	assert_eq(b.get("npc", ""), "mirela", "najbliższa postać woła")
	assert_eq(b.index, 0, "przed zadaniem: „Klucze!”")
	gs.quests["key"] = "started"
	assert_eq(w.pick_bark(1000.0).index, 1, "po kradzieży: kwestia o zamkach")
	w._bark_last["mirela"] = 1000.0
	assert_ne(w.pick_bark(1010.0).get("npc", ""), "mirela", "przerwa po okrzyku")
	w.player_actor.place(Vector2i(37, 15))
	assert_true(w.pick_bark(5000.0).is_empty() or w.pick_bark(5000.0).npc != "mirela", "daleko = cisza")
	mirela.say("Test")
	w.hud.bubble(mirela, "Mirela", "Test", 1.0)
	assert_eq(w.hud._bubbles.filter(func(x): return x.target == mirela).size(), 1, "dymek w HUD")
	assert_true(mirela.is_barking(), "dymek widoczny")
	w._hush_all()
	assert_false(mirela.is_barking())
	assert_eq(w.hud._bubbles.size(), 0)
