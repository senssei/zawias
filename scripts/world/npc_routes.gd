# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name NpcRoutes
extends RefCounted
## Trasy NPC w trybie zwiedzania. NPC z polem "route" w mapie chodzi spacerem od punktu do punktu i na każdym
## stoi chwilę. Format:
##   "route": {"points": [[x, y], ...], "wait": [min_s, max_s], "mode": "loop" | "pingpong", "if": {warunek}}
## Punkt startowy to "pos" NPC, a "points" to kolejne przystanki. "loop" wraca z ostatniego na start,
## "pingpong" zawraca tą samą drogą. "if" (warunek jak w dialogach) włącza trasę tylko w danym stanie gry.
## NPC staje, gdy gracz do niego idzie, gdy woła okrzyk i poza trybem zwiedzania (dialog, walka).
## Pozycji nie zapisujemy: po wczytaniu gry NPC zaczyna z "pos".

const RETRY := 0.6            # s do ponownej próby, gdy droga jest zajęta
const GIVE_UP := 6            # po tylu nieudanych próbach NPC idzie do następnego przystanku
const DEFAULT_WAIT := [3.0, 8.0]

var world: Node
var routes := {}              # actor_id -> stan trasy


func _init(w: Node) -> void:
	world = w


## Trasy z danych mapy dla aktorów, którzy już stoją na swoich polach.
func setup(actors: Dictionary) -> void:
	routes.clear()
	for id_ in actors.keys():
		var a: Actor = actors[id_]
		if not is_instance_valid(a) or a.is_object:
			continue
		var r: Dictionary = a.npc_data.get("route", {})
		if r.is_empty():
			continue
		var pts: Array[Vector2i] = [a.cell]
		for p in r.get("points", []):
			pts.append(Vector2i(int(p[0]), int(p[1])))
		if pts.size() < 2:
			continue
		var w: Array = r.get("wait", DEFAULT_WAIT)
		var wait := Vector2(float(w[0]), float(w[1]))
		routes[id_] = {
			"points": pts, "wait": wait, "pingpong": r.get("mode", "loop") == "pingpong", "if": r.get("if", {}),
			"idx": 1, "dir": 1, "timer": randf_range(0.5, wait.y), "moving": false, "tries": 0,
		}


func update(delta: float) -> void:
	if world.mode != "explore":
		return
	for id_ in routes.keys():
		var a: Actor = world.actors.get(id_)
		if a == null or not is_instance_valid(a) or not a.visible or world._is_follower(a):
			continue
		var st: Dictionary = routes[id_]
		if st.moving:
			continue
		if not GameState.check(st["if"]) or is_busy(a):
			if a.is_walking():
				a.stop_walk()
			st.timer = maxf(st.timer, 0.8)
			continue
		st.timer -= delta
		if st.timer > 0.0:
			continue
		var target: Vector2i = st.points[st.idx]
		if a.cell == target:
			_advance(st)
			st.timer = randf_range(st.wait.x, st.wait.y)
			continue
		var path: Array = world.grid.find_path(a.cell, target, blocked_for(a))
		if path.size() < 2:
			st.tries += 1
			st.timer = RETRY
			if st.tries >= GIVE_UP:
				_advance(st)
			continue
		st.tries = 0
		var next: Vector2i = path[1]
		var last := next == target
		st.moving = true
		var tw: Tween = a.walk_step(next, Actor.WALK_SPEED / world.grid.step_cost(next), not a.is_walking(), last)
		tw.finished.connect(func():
			st.moving = false
			if last or world.mode != "explore" or is_busy(a):
				a.stop_walk())


## NPC stoi: gracz właśnie do niego idzie (żeby rozmowa zaczęła się tam, gdzie kliknięto) albo woła okrzyk.
func is_busy(a: Actor) -> bool:
	return world.pending_interact == a or a.is_barking()


## Pola, na które NPC nie wejdzie: inni aktorzy, gracz i jego najbliższe kroki, towarzysze, latarnie.
func blocked_for(a: Actor) -> Dictionary:
	var occ: Dictionary = world._occupied(a)
	if is_instance_valid(world.player_actor):
		occ[world.player_actor.cell] = true
	for i in mini(2, world.walk_queue.size()):
		occ[world.walk_queue[i]] = true
	for f in world._followers():
		occ[f.cell] = true
	for p in world.LAMP_POSTS:
		occ[p] = true
	occ.erase(a.cell)
	return occ


## Wszystkie pola tras (do kontroli danych): kolejne odcinki muszą być osiągalne po pustej mapie.
static func route_points(n: Dictionary) -> Array[Vector2i]:
	var pts: Array[Vector2i] = [Vector2i(int(n.pos[0]), int(n.pos[1]))]
	for p in n.get("route", {}).get("points", []):
		pts.append(Vector2i(int(p[0]), int(p[1])))
	return pts


func _advance(st: Dictionary) -> void:
	st.tries = 0
	var n: int = st.points.size()
	if st.pingpong:
		if st.idx + st.dir >= n or st.idx + st.dir < 0:
			st.dir = -st.dir
		st.idx += st.dir
	else:
		st.idx = (st.idx + 1) % n
