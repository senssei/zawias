# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends GutTest
## Mapa: mgła (odkrywanie, zapis), znaczniki i cele zadań, przeliczanie pól na ekran (także obrócona minimapa),
## klik na mapie prowadzi do wolnego pola.

const OPTS := {
	"name": "T", "species": "human", "background": "soldier", "class": "fighter",
	"scores": {"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8}, "bonus": {"str": 2, "con": 1},
}


func _gs() -> Node:
	return get_tree().root.get_node("GameState")


func _world() -> Node3D:
	_gs().new_game(CharacterBuilder.build(OPTS))
	var w: Node3D = load("res://scripts/world/world.gd").new()
	add_child_autofree(w)
	return w


func test_reveal_and_save_roundtrip():
	var gs := _gs()
	gs.new_game(CharacterBuilder.build(OPTS))
	assert_false(gs.is_explored("m", Vector2i(2, 1), 4))
	gs.reveal("m", [Vector2i(2, 1), Vector2i(9, 9)], 4, 3)   # pole poza siatką jest pomijane
	assert_true(gs.is_explored("m", Vector2i(2, 1), 4))
	assert_false(gs.is_explored("m", Vector2i(1, 1), 4))
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.new_game(CharacterBuilder.build(OPTS))
	assert_false(gs.is_explored("m", Vector2i(2, 1), 4), "nowa gra = mgła od nowa")
	gs.from_dict(d)
	assert_true(gs.is_explored("m", Vector2i(2, 1), 4), "odkryte pola wracają z zapisu")


func test_world_reveals_start_and_builds_markers():
	var w := _world()
	await wait_frames(3)
	var gs := _gs()
	var start: Vector2i = w.player_actor.cell
	assert_true(gs.is_explored(gs.map_id, start, w.grid.width), "pole startowe odkryte")
	assert_false(gs.is_explored(gs.map_id, Vector2i(34, 15), w.grid.width), "wnętrze magazynu we mgle na starcie")
	# budynek z nazwą odkrywa się w całości, gdy widać jego ścianę
	assert_true(gs.is_explored(gs.map_id, Vector2i(1, 1), w.grid.width), "róg Kancelarii (widać jej ścianę)")
	var kinds := {}
	var quest := []
	for m in w._map_markers():
		kinds[m.kind] = kinds.get(m.kind, 0) + 1
		if m.get("quest", false):
			quest.append(m.name)
	assert_eq(kinds.get("player", 0), 1)
	assert_gt(kinds.get("npc", 0), 5)
	assert_eq(kinds.get("lock", 0), 2, "drzwi magazynu i tylne drzwi zamknięte")
	assert_true("Hask" in quest, "przed zadaniem: Hask jako cel")
	gs.quests["key"] = "lead_warehouse"
	var names: Array = w._map_markers().filter(func(m): return m.get("quest", false)).map(func(m): return m.name)
	assert_false("Hask" in names, "po zmianie etapu cel się przenosi")
	assert_gt(names.size(), 0)
	gs.flags["front_open"] = true
	assert_eq(w._map_markers().filter(func(m): return m.kind == "lock").size(), 1, "otwarte drzwi znikają z mapy")


func test_walk_from_gate_to_mirela_and_get_first_leads():
	var w := _world()
	await wait_physics_frames(3)
	var gs := _gs()
	var mirela: Actor = w.actors["mirela"]
	w._explore_click(mirela.cell)
	await wait_until(func(): return w.mode == "dialogue", 10.0)
	assert_eq(w.mode, "dialogue", "kliknięcie Mireli prowadzi do rozmowy z bramy")
	if w.mode != "dialogue":
		return
	assert_eq(w.dialogue.current_id, "start")
	w.dialogue.choose(0)
	w.dialogue.choose(1)
	assert_eq(w.dialogue.current_id, "accept")
	assert_eq(gs.quest_stage("key"), "started")
	assert_eq(w._quest_targets(), {"kwit": true, "pchla": true, "lis": true})
	w.dialogue.choose(0)
	assert_eq(w.mode, "explore")
	await wait_process_frames(1)
	# P1 orientacja: każdy z trzech rozmówców jest widoczny na mapie (we mgle jako sam romb z podpisem),
	# zwykli NPC we mgle zostają ukryci
	var mv := MapView.new()
	mv.explored = func(c: Vector2i) -> bool: return gs.is_explored(gs.map_id, c, w.grid.width)
	var shown := []
	var hidden_npc := 0
	for m in w._map_markers():
		var vis: String = mv.marker_visibility(m)
		if m.get("quest", false):
			assert_ne(vis, "", "%s: cel zadania widoczny na mapie" % m.name)
			shown.append(m.name)
		elif vis == "":
			hidden_npc += 1
	mv.free()
	assert_eq(shown.size(), 3, "Kwit, Pchła i Lis na mapie: %s" % str(shown))
	gut.p("cele po zleceniu: %s, ukrytych we mgle: %d" % [str(shown), hidden_npc])


func test_map_view_screen_cell_roundtrip_rotated():
	var mv := MapView.new()
	add_child_autofree(mv)
	mv.size = Vector2(220, 180)
	mv.set_map(DB.map("rusty_market"))
	mv.markers_fn = func(): return [{"cell": Vector2i(10, 8), "kind": "player", "name": ""}]
	for yaw_deg in [45.0, 135.0, 225.0, 315.0]:
		mv.rotate_with_camera = true
		mv.yaw = deg_to_rad(yaw_deg)
		mv._update_xf()
		assert_eq(mv.to_cell(mv.size * 0.5), Vector2i(10, 8), "minimapa wyśrodkowana na graczu (yaw %d)" % yaw_deg)
		for c in [Vector2i(3, 4), Vector2i(30, 15)]:
			assert_eq(mv.to_cell(mv.to_screen(Vector2(c) + Vector2(0.5, 0.5))), c)
	# przód kamery wskazuje górę minimapy
	mv.yaw = deg_to_rad(45.0)
	mv._update_xf()
	var fwd := Vector2(-sin(mv.yaw), -cos(mv.yaw))
	var d: Vector2 = mv.to_screen(Vector2(10.5, 8.5) + fwd * 3.0) - mv.size * 0.5
	assert_almost_eq(d.x, 0.0, 0.01)
	assert_lt(d.y, 0.0)


func test_map_click_on_building_walks_to_nearest_free_cell():
	var w := _world()
	await wait_frames(3)
	w._on_map_travel(Vector2i(3, 2))        # środek Kancelarii (pole stałe)
	assert_true(w.walking or not w.walk_queue.is_empty(), "rusza w stronę budynku")
	var goal: Vector2i = w.walk_queue[-1] if not w.walk_queue.is_empty() else w.player_actor.cell
	assert_true(w.grid.is_open(goal), "cel to wolne pole")
	assert_lt(Vector2(goal - Vector2i(3, 2)).length(), 4.5, "obok budynku")


## Łupy (pole "loot" mapy): znacznik na mapie do przeszukania, efekty jednorazowe, sylwetka x-ray,
## torba z ziemi znika, pojemnik zostaje pusty; stan wraca z zapisu.
func test_loot_markers_take_and_save():
	var w := _world()
	await wait_frames(3)
	var gs := _gs()
	var loot: Array = w._map_markers().filter(func(m): return m.kind == "loot")
	assert_eq(loot.size(), w.map.get("loot", []).size(), "każdy łup ma znacznik")
	var bag: Actor = w.actors["loot_courier_bag"]
	assert_not_null(bag._xray, "łup ma sylwetkę za budynkami")
	var gold: int = gs.player.gold
	w._interact(bag)
	assert_eq(gs.player.gold, gold + 12, "złoto z torby")
	assert_false(w.actors.has("loot_courier_bag"), "torba zabrana z ziemi")
	w._interact(w.actors["loot_warehouse_crate"])
	assert_true("potion_healing" in gs.player.inventory, "mikstura ze skrzynki")
	var crate: Actor = w.actors["loot_warehouse_crate"]
	var potions: int = gs.player.inventory.count("potion_healing")
	w._interact(crate)
	assert_eq(gs.player.inventory.count("potion_healing"), potions, "drugi raz pusto")
	var ids: Array = w._map_markers().filter(func(m): return m.kind == "loot").map(func(m): return m.name)
	assert_eq(ids.size(), loot.size() - 2, "przeszukane znikają z mapy")
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.new_game(CharacterBuilder.build(OPTS))
	gs.from_dict(d)
	var w2: Node3D = load("res://scripts/world/world.gd").new()
	add_child_autofree(w2)
	await wait_frames(3)
	assert_false(w2.actors.has("loot_courier_bag"), "po wczytaniu torby nie ma")
	assert_true(w2.actors.has("loot_warehouse_crate"), "pusta skrzynka stoi dalej")


## Mgła wojny 3D: maska ma odkryte pola jasne, nieodkryte ciemne; NPC we mgle ukryty, po odkryciu widoczny.
## Łatanie dziur: pole otoczone odkrytymi (cień straganu) też jest odkryte.
func test_fog_of_war_mask_and_actors():
	var w := _world()
	await wait_frames(3)
	var gs := _gs()
	if w.fog == null:
		w.fog = FogOfWar.new(w, w.grid.width, w.grid.height)   # bez malunku (np. --nopaint) mgła i tak działa
	w.fog.refresh()
	var start: Vector2i = w.player_actor.cell
	var img: Image = w.fog._img   # w trybie headless tekstura GPU nie oddaje danych
	var px := func(c: Vector2i) -> float: return img.get_pixel(c.x * FogOfWar.SUB + 2, c.y * FogOfWar.SUB + 2).r
	assert_gt(px.call(start), 0.9, "pole gracza odkryte w masce")
	assert_lt(px.call(Vector2i(34, 15)), 0.1, "wnętrze magazynu we mgle")
	var sever: Actor = w.actors["sever"]
	w.fog.update_actors(0.0, true)
	assert_true(sever.fogged, "Sever we mgle ukryty")
	assert_true(sever.visible, "aktor zostaje w świecie (mapa, trasy)")
	gs.reveal(gs.map_id, [sever.cell], w.grid.width, w.grid.height)
	w.fog.refresh()
	w.fog.update_actors(0.0, true)
	assert_false(sever.fogged, "po odkryciu widoczny")
	# żadne pole w zasięgu startu nie jest wyspą mgły otoczoną odkrytymi polami
	var holes := []
	for y in range(start.y - 6, start.y + 7):
		for x in range(start.x - 6, start.x + 7):
			var c := Vector2i(x, y)
			if not w.grid.in_bounds(c) or gs.is_explored(gs.map_id, c, w.grid.width):
				continue
			var n := 0
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if gs.is_explored(gs.map_id, c + d, w.grid.width):
					n += 1
			if n == 4:
				holes.append(c)
	assert_eq(holes, [], "dziury w mgle przy starcie")


## Odznaka naturalnego k20 nie zasłania otwartego okna (mapa): stoi pod nim albo nad nim.
func test_d20_badge_does_not_cover_open_window():
	var w := _world()
	await wait_frames(3)
	w._on_menu("map")
	await wait_frames(2)
	assert_true(w.hud.is_window_open())
	w.hud.show_d20(20, "T")
	await wait_frames(1)
	var badge: Rect2 = w.hud.d20_badge.get_rect()
	var win: Rect2 = w.hud.window.get_rect()
	assert_false(badge.intersects(win), "odznaka %s poza oknem %s" % [badge, win])
	w.hud.close_window()
	w.hud.show_d20(1, "T")
	assert_eq(w.hud.d20_badge.position.y, 78.0, "bez okna: pod paskiem menu")


func test_defeat_leads_into_fog_and_back_to_the_gate():
	var w := _world()
	await wait_frames(3)
	var gs := _gs()
	gs.player.gold = 21
	var hp0: int = gs.player.max_hp
	w.start_combat("ambush")
	await wait_frames(2)
	gs.player.hp = 0
	gs.player.dead = true
	w._finish_combat(false, 0)
	assert_eq(w.mode, "cutscene", "przejście w mgłę")
	await wait_seconds(1.7)
	assert_eq(w.mode, "dialogue", "zamiast ekranu porażki: scena w mgle")
	assert_eq(w.dialogue.dialogue_id, "rift")
	assert_eq(w.dialogue.current_id, "fall", "pierwsza klęska: rozpad w pustce")
	assert_true(w.hud.cutscene.visible, "półcutscenka na pełnym ekranie")
	w.dialogue.choose(0)
	assert_eq(w.dialogue.current_id, "queue", "potem pierwszy fragment")
	assert_eq(gs.player.gold, 11, "bandyci zabrali połowę złota")
	assert_true(gs.has_flag("ambush_done"), "zasadzka rozstrzygnięta")
	assert_false("rust_token" in gs.player.inventory, "bez nagrody")
	assert_eq(gs.quest_stage("key"), "lead_warehouse", "trop do magazynu")
	assert_eq(gs.player.max_hp, hp0 - 1, "zapomnienie: -1 maks. PW")
	assert_eq(gs.player.hp, gs.player.max_hp, "pełne PW po bramie")
	assert_false(gs.player.dead)
	assert_eq(w.player_actor.cell, Vector2i(int(w.map.player_start[0]), int(w.map.player_start[1])), "brama przy wejściu")
	assert_false(w.actors.has("bandyta1"), "bandyci odeszli")
	w.dialogue.choose(0)
	await wait_frames(1)
	assert_eq(w.mode, "explore")
	assert_false(w.hud.cutscene.visible, "półcutscenka schowana")
	# magazyn: wrogowie zostają, front zamknięty, klucz głębiej
	gs.flags["front_open"] = true
	w.start_combat("warehouse")
	await wait_frames(2)
	w._finish_combat(false, 0)
	await wait_seconds(1.7)
	assert_eq(w.dialogue.current_id, "fall_again", "druga klęska")
	w.dialogue.choose(0)
	assert_eq(w.dialogue.current_id, "ledger", "drugi fragment")
	assert_false(gs.has_flag("front_open"))
	assert_true(gs.has_flag("key_hidden"))
	assert_eq(gs.faction_attitude("unravelers"), "wary")
	assert_true(w.actors.has("kultysta") or w.actors.keys().any(func(k): return w.actors[k].npc_data.get("encounter", "") == "warehouse"), "Rozplatacze zostali")
	assert_eq(gs.player.max_hp, hp0 - 2)
	w.dialogue.choose(0)
	for i in 3:
		gs.apply_effects([{"forget": 1}])
	assert_eq(gs.forgotten, 3, "najwyżej -3")
	gs.apply_effects([{"remember": true}])
	assert_eq(gs.player.max_hp, hp0, "rozmowa z dawnym sobą przywraca PW")
	assert_eq(gs.forgotten, 0)

