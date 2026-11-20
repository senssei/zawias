# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends GutTest
## Trasy NPC: dane (przystanki wolne i osiągalne), chód po trasie, postój przy rozmowie i poza zwiedzaniem,
## gracz omija NPC, który wszedł mu w drogę.

const OPTS := {
	"name": "T", "species": "human", "background": "soldier", "class": "fighter",
	"scores": {"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8}, "bonus": {"str": 2, "con": 1},
}

var _w: Node3D


func before_each():
	Engine.time_scale = 1.0


func after_each():
	Engine.time_scale = 1.0


func _world() -> Node3D:
	var gs: Node = get_tree().root.get_node("GameState")
	gs.new_game(CharacterBuilder.build(OPTS))
	var w: Node3D = load("res://scripts/world/world.gd").new()
	add_child_autofree(w)
	await wait_frames(3)
	return w


func test_route_data_is_walkable():
	var m: Dictionary = DB.map("rusty_market")
	var grid := CombatGrid.new(m)
	var taken := {}
	for d in m.get("decor", []):
		grid.set_dynamic_block(Vector2i(int(d.pos[0]), int(d.pos[1])), true)
	for o in m.get("objects", []):
		taken[Vector2i(int(o.pos[0]), int(o.pos[1]))] = o.id
	var lamps: Array = load("res://scripts/world/world.gd").LAMP_POSTS
	var with_route := 0
	for n in m.npcs:
		if not n.has("route"):
			continue
		with_route += 1
		assert_false(n.has("encounter"), "%s: trasa tylko dla NPC spoza walk" % n.id)
		assert_true(n.route.get("mode", "loop") in ["loop", "pingpong"], n.id)
		var pts := NpcRoutes.route_points(n)
		assert_true(pts.size() >= 2, "%s: co najmniej jeden przystanek" % n.id)
		for i in pts.size():
			var p: Vector2i = pts[i]
			assert_true(grid.is_open(p), "%s: przystanek %s wolny (bez murów i dekoracji)" % [n.id, p])
			assert_false(p in lamps, "%s: przystanek %s nie na latarni" % [n.id, p])
			assert_false(taken.has(p), "%s: przystanek %s nie na obiekcie" % [n.id, p])
			var nxt: Vector2i = pts[(i + 1) % pts.size()]
			assert_true(grid.find_path(p, nxt).size() > 1, "%s: z %s da się dojść do %s" % [n.id, p, nxt])
		for other in m.npcs:
			if other.id != n.id:
				assert_false(Vector2i(int(other.pos[0]), int(other.pos[1])) in pts.slice(1), "%s: przystanek na miejscu %s" % [n.id, other.id])
	assert_true(with_route >= 3, "kilka postaci chodzi po targu")


func test_npc_walks_route_and_waits():
	var w: Node3D = await _world()
	var dorn: Actor = w.actors["dorn"]
	var st: Dictionary = w.routes.routes["dorn"]
	var goal: Vector2i = st.points[1]
	w.player_actor.place(Vector2i(1, 5))
	Engine.time_scale = 8.0
	st.timer = 0.0
	await wait_until(func(): return dorn.cell == goal and not st.moving, 5.0)
	assert_eq(dorn.cell, goal, "Dorn doszedł do przystanku")
	await wait_frames(2)
	assert_eq(st.idx, 0, "pingpong: następny cel to start")
	assert_true(st.timer > 0.0, "postój na przystanku")
	st.timer = 0.0
	await wait_until(func(): return dorn.cell == st.points[0] and not st.moving, 5.0)
	assert_eq(dorn.cell, st.points[0], "wrócił na start")


func test_npc_stops_for_talk_and_outside_explore():
	var w: Node3D = await _world()
	var dorn: Actor = w.actors["dorn"]
	var st: Dictionary = w.routes.routes["dorn"]
	var start := dorn.cell
	w.player_actor.place(Vector2i(1, 5))
	w.pending_interact = dorn
	st.timer = 0.0
	Engine.time_scale = 8.0
	await wait_seconds(0.5)
	assert_eq(dorn.cell, start, "gracz idzie do Dorna: Dorn czeka")
	w.pending_interact = null
	w.mode = "dialogue"
	st.timer = 0.0
	await wait_seconds(0.5)
	assert_eq(dorn.cell, start, "w dialogu nikt nie chodzi")
	w.mode = "explore"
	st.timer = 0.0
	await wait_until(func(): return dorn.cell != start, 2.0)
	assert_ne(dorn.cell, start, "po rozmowie wraca na trasę")
	assert_false(w.routes.blocked_for(dorn).has(dorn.cell), "własne pole nie blokuje")
	assert_true(w.routes.blocked_for(dorn).has(w.player_actor.cell), "nie wchodzi na gracza")


func test_player_repaths_around_npc():
	var w: Node3D = await _world()
	for id_ in w.routes.routes.keys():
		w.routes.routes[id_].timer = 999.0
	w.player_actor.place(Vector2i(14, 11))
	var path: Array = w.grid.find_path(Vector2i(14, 11), Vector2i(20, 11), w._occupied())
	assert_true(path.size() > 3)
	var npc: Actor = w.actors["pchla"]
	Engine.time_scale = 8.0
	w._start_walk(path)
	npc.place(path[2])                  # NPC wchodzi na drogę przed graczem
	await wait_until(func(): return not w.walking, 5.0)
	assert_eq(w.player_actor.cell, Vector2i(20, 11), "gracz obszedł NPC i doszedł do celu")
