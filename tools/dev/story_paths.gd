# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends RefCounted
## story paths (docs/story-pipeline.md): przechodzi grę na danych i GameState, bez świata 3D.
## Stan = flagi, zadania, reputacja, przedmioty, złoto, PD, drużyna, usunięci NPC. Akcja = rozmowa z postacią albo
## obiektem z mapy. Każdy test umiejętności rozgałęzia się na sukces i porażkę (wymuszone kości), walka kończy się
## wygraną (porażka w grze = wczytanie gry, więc jej nie śledzimy). Przejście do postaci za aktywnym wyzwalaczem
## (zasadzka w zaułku) najpierw odpala walkę. Raport: finały, PD i poziom przed walkami, ślepe zaułki, wybory,
## których nie widać w żadnym przebiegu.

const SUCCESS := [20, 20, 20, 20, 20, 20]
const FAIL := [1, 1, 1, 1, 1, 1]

var gs: Node
var map: Dictionary
var grid: CombatGrid
var max_states := 300          # przeszukiwanie wszerz: najkrótsze drogi, ślepe zaułki blisko startu
var max_depth := 16
var random_walks := 200         # losowe przejścia: pokrycie wyborów, rozkład finałów, PD przed walkami
var walk_steps := 40
var rng := RandomNumberGenerator.new()

var _visited := {}            # hash stanu -> true
var _seen_choices := {}       # "dialog/węzeł/i" -> true
var _endings := {}            # zakończenie -> {"count", "path", "level", "xp"}
var _combats := {}            # spotkanie -> {"min_level", "max_level", "min_xp", "max_xp", "solo", "party", "path_min"}
var _dead_ends := []
var _states := 0
var _truncated := false


# Co w ogóle wpływa na przebieg: flagi, przedmioty i progi złota z warunków (dialogi, mapa, spotkania, zamki).
# Klucz stanu bierze tylko je, więc fakty ustawiane, ale nigdzie niesprawdzane (mikstury, dokładne złoto, flagi
# czysto informacyjne) nie mnożą stanów. Osiągalność się nie zmienia.
var _rel_flags := {}
var _rel_items := {}
var _gold_steps := []


func _init(game_state: Node, map_id := "rusty_market") -> void:
	gs = game_state
	map = DB.map(map_id)
	grid = CombatGrid.new(map)
	for dlg in _dialogue_ids():
		_collect(DB.dialogue(dlg))
	_collect(map)
	_collect(DB.table("encounters"))
	_gold_steps.sort()


func _collect(v) -> void:
	if v is Dictionary:
		for k in v.keys():
			var x = v[k]
			match k:
				"flag", "not_flag", "unless_flag", "surprise_unless_flag", "hide_if":
					_rel_flags[str(x)] = true
				"flags", "any_flag":
					for f in x:
						_rel_flags[str(f)] = true
				"has_item", "not_item":
					_rel_items[str(x)] = true
				"gold":
					if x is float or x is int:
						if int(x) > 0 and not int(x) in _gold_steps:
							_gold_steps.append(int(x))
			_collect(x)
	elif v is Array:
		for x in v:
			_collect(x)


## Przechodzi grę od bieżącego stanu GameState: przeszukiwanie wszerz z limitem stanów i losowe przejścia
## (stanów jest wykładniczo dużo, kilkadziesiąt niezależnych faktów). Zwraca raport (słownik gotowy do JSON).
func explore() -> Dictionary:
	gs.any_motivation = true   # opcje motywacji (ADR 0009) zależą od kreatora: przechodzimy wszystkie
	var start := _snap()
	_bfs()
	rng.seed = 7
	_walk_endings = {}
	for i in random_walks:
		_restore(start)
		_random_walk()
	_restore(start)
	gs.any_motivation = false
	return _report()


var _walk_endings := {}       # zakończenie -> liczba losowych przejść, które do niego doszły
var _walk_stuck := 0          # losowe przejścia bez finału po walk_steps rozmowach


func _random_walk() -> void:
	var path := []
	for step in walk_steps:
		var actors := _actors()
		if actors.is_empty():
			break
		var actor: Dictionary = _pick_actor(actors)
		var trig := _trigger_on_way(Vector2i(int(actor.pos[0]), int(actor.pos[1])))
		if trig != "":
			_fight(trig)
			_take_levels()
			path.append("walka:" + trig)
		var r := DialogueRunner.new(gs)
		if not r.start(actor.dialogue):
			continue
		path.append(actor.id)
		var guard := 0
		while guard < 30:
			guard += 1
			var choices := r.visible_choices()
			# pokrycie: częściej wybór, którego jeszcze nie było (ale nie zawsze, żeby znane drogi też się mieszały)
			var fresh := choices.filter(func(c): return not _seen_choices.has("%s/%s/%d" % [r.dialogue_id, r.current_id, c.index]))
			var pool: Array = fresh if not fresh.is_empty() and rng.randf() < 0.7 else choices
			var ch: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
			_seen_choices["%s/%s/%d" % [r.dialogue_id, r.current_id, ch.index]] = true
			var requests := []
			var done := [false]
			var on_req := func(e): requests.append(e)
			var on_fin := func(): done[0] = true
			gs.world_request.connect(on_req)
			r.finished.connect(on_fin)
			if ch.choice.has("check"):
				Dice.force(SUCCESS if rng.randf() < 0.5 else FAIL)
			r.choose(ch.index)
			Dice.clear_forced()
			gs.world_request.disconnect(on_req)
			r.finished.disconnect(on_fin)
			var ending := ""
			var combat := ""
			for e in requests:
				if e.has("start_combat"):
					combat = e.start_combat
				if e.has("end_game"):
					ending = e.end_game
				if e.has("remove_npc") and not e.remove_npc in gs.removed_npcs:
					gs.removed_npcs.append(e.remove_npc)
			if combat != "":
				_fight(combat)
				path.append("walka:" + combat)
			_take_levels()
			if ending != "":
				_walk_endings[ending] = int(_walk_endings.get(ending, 0)) + 1
				_record_ending(ending, path, _snap())
				return
			if done[0] or combat != "":
				break
	_walk_stuck += 1


## Rozmówca losowany z wagą 1 + liczba niewidzianych jeszcze wyborów w jego dialogu.
func _pick_actor(actors: Array) -> Dictionary:
	var weights := []
	var total := 0.0
	for a in actors:
		var nodes: Dictionary = DB.dialogue(a.dialogue).get("nodes", {})
		var unseen := 0
		for node in nodes.keys():
			for i in nodes[node].get("choices", []).size():
				if not _seen_choices.has("%s/%s/%d" % [a.dialogue, node, i]):
					unseen += 1
		var wgt := 1.0 + unseen
		weights.append(wgt)
		total += wgt
	var x := rng.randf() * total
	for i in actors.size():
		x -= weights[i]
		if x <= 0.0:
			return actors[i]
	return actors.back()


func _bfs() -> void:
	var queue := [{"snap": _snap(), "path": []}]
	_visited[_hash()] = true
	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		_states += 1
		if _states > max_states:
			_truncated = true
			break
		_restore(item.snap)
		var progressed := false
		for actor in _actors():
			_restore(item.snap)
			for out in _act(actor, item.path):
				progressed = true
				var path: Array = item.path + out.steps
				if out.ending != "":
					_record_ending(out.ending, path, out.snap)
					continue
				var h := _hash_of(out.snap)
				if _visited.has(h) or path.size() > max_depth:
					continue
				_visited[h] = true
				queue.append({"snap": out.snap, "path": path})
		if not progressed:
			_restore(item.snap)
			if not gs.quest_stage("key").begins_with("done"):
				_dead_ends.append({"path": item.path, "key": gs.quest_stage("key")})


# ------------------------------------------------------------------ akcje
func _actors() -> Array:
	var out := []
	for group in ["npcs", "objects"]:
		for e in map.get(group, []):
			if e.get("dialogue", "") == "" or e.id in gs.removed_npcs:
				continue
			if e.has("if") and not gs.check(e["if"]):
				continue
			if _path_to(Vector2i(int(e.pos[0]), int(e.pos[1]))).is_empty():
				continue   # za zamkniętymi drzwiami (skrzynia, Sever w magazynie)
			out.append(e)
	return out


## Wszystkie wyniki rozmowy z aktorem: [{"snap", "steps", "ending"}] (tylko te, które zmieniają stan).
func _act(actor: Dictionary, path: Array) -> Array:
	var before := _hash()
	var start_snap := _snap()
	var results := []
	var pre_steps := []
	# wyzwalacz na drodze do aktora (np. zasadzka w zaułku) odpala walkę przed rozmową
	var trig := _trigger_on_way(Vector2i(int(actor.pos[0]), int(actor.pos[1])))
	if trig != "":
		_fight(trig)
		_take_levels()
		pre_steps.append("walka:" + trig)
		start_snap = _snap()
	var r := DialogueRunner.new(gs)
	if not r.start(actor.dialogue):
		return []
	var outcomes := []
	_walk(r, actor.dialogue, r.current_id, _snap(), [actor.id], outcomes, {})
	for o in outcomes:
		_restore(o.snap)
		if o.combat != "":
			_fight(o.combat)
		_take_levels()
		var snap := _snap()
		if o.ending == "" and _hash_of(snap) == before:
			continue
		results.append({"snap": snap, "steps": pre_steps + o.steps + (["walka:" + o.combat] if o.combat != "" else []),
			"ending": o.ending})
	return results


## Przeszukiwanie rozmowy w głąb: każdy widoczny wybór, test rozgałęziony na sukces i porażkę.
func _walk(r: DialogueRunner, dlg: String, node: String, snap: Dictionary, steps: Array, out: Array, seen: Dictionary) -> void:
	var key := "%s|%s|%s" % [dlg, node, _hash_of(snap)]
	if seen.has(key):
		return
	seen[key] = true
	_restore(snap)
	r.use_dialogue(dlg)
	r.current_id = node
	for ch in r.visible_choices():
		var i: int = ch.index
		_seen_choices["%s/%s/%d" % [dlg, node, i]] = true
		var variants: Array = _check_variants(ch.choice) if ch.choice.has("check") else [[]]
		for dice in variants:
			_restore(snap)
			r.use_dialogue(dlg)
			r.current_id = node
			var requests := []
			var done := [false]
			var on_req := func(e): requests.append(e)
			var on_fin := func(): done[0] = true
			gs.world_request.connect(on_req)
			r.finished.connect(on_fin)
			Dice.force(dice)
			r.choose(i)
			Dice.clear_forced()
			gs.world_request.disconnect(on_req)
			r.finished.disconnect(on_fin)
			var step := "%s:%s#%d%s" % [dlg, node, i, _variant_mark(dice)]
			var combat := ""
			var ending := ""
			for e in requests:
				if e.has("start_combat"):
					combat = e.start_combat
				if e.has("end_game"):
					ending = e.end_game
				if e.has("remove_npc") and not e.remove_npc in gs.removed_npcs:
					gs.removed_npcs.append(e.remove_npc)
			if done[0] or combat != "" or ending != "":
				out.append({"snap": _snap(), "steps": steps + [step], "combat": combat, "ending": ending})
			else:
				_walk(r, r.dialogue_id, r.current_id, _snap(), steps + [step], out, seen)


# ------------------------------------------------------------------ walki i wyzwalacze
## Najkrótsza droga od startu mapy do pola obok celu; zamknięte drzwi (map.locks) są przeszkodą, więc do tylnych
## drzwi idzie się zaułkiem, a do skrzyni w magazynie dopiero po otwarciu drzwi. [] = nie da się dojść.
func _path_to(target: Vector2i) -> Array:
	var start := Vector2i(int(map.player_start[0]), int(map.player_start[1]))
	var blocked := {}
	for lk in map.get("locks", []):
		if not gs.has_flag(lk.unless_flag):
			blocked[Vector2i(int(lk.cell[0]), int(lk.cell[1]))] = true
	var best := []
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if blocked.has(target + d):
			continue
		var path := grid.find_path(start, target + d, blocked)
		if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
			best = path
	if best.is_empty() and start.distance_to(target) <= 1.5:
		best = [start]
	return best


func _trigger_on_way(target: Vector2i) -> String:
	var path := _path_to(target)
	for t in map.get("triggers", []):
		if not gs.check(t.get("if", {})):
			continue
		for c in t.cells:
			if Vector2i(int(c[0]), int(c[1])) in path:
				return str(t.encounter)
	return ""


## Wygrana walka jak w świecie: PD za wrogów (ze skalowaniem solo), on_victory, usunięci wrogowie.
func _fight(enc_id: String) -> void:
	var enc := DB.entry("encounters", enc_id)
	var party: int = 1 + gs.companions.size()
	var stat: Dictionary = _combats.get(enc_id, {"min_level": 99, "max_level": 0, "min_xp": 1 << 30, "max_xp": 0,
		"solo": 0, "party": 0, "count": 0})
	var lvl: int = gs.player.level + gs.player.pending_levels
	var xp0: int = gs.player.xp
	stat.count += 1
	stat["party" if party > 1 else "solo"] += 1
	if lvl < stat.min_level:
		stat.min_level = lvl
		stat.min_level_xp = xp0
	stat.max_level = maxi(stat.max_level, lvl)
	stat.min_xp = mini(stat.min_xp, xp0)
	stat.max_xp = maxi(stat.max_xp, xp0)
	_combats[enc_id] = stat
	for f in enc.get("unlock", []):
		gs.flags[f] = true
	var skip := Difficulty.solo_skip(enc, party)
	var xp := 0
	for s in enc.get("spawn", []):
		if not s.id in skip:
			xp += int(DB.entry("monsters", s.monster).get("xp", 0))
	for n in map.npcs:
		if n.get("encounter", "") != enc_id or n.id in gs.removed_npcs:
			continue
		if n.has("monster") and not n.get("flees", false) and not n.id in skip:
			xp += int(DB.entry("monsters", n.monster).get("xp", 0))
		gs.removed_npcs.append(n.id)
	gs.apply_effects([{"xp": xp}] + enc.get("on_victory", []))


func _take_levels() -> void:
	while gs.player.pending_levels > 0:
		var o := Leveling.level_up_options(gs.player)
		var spells: Array = o.spell_choices.slice(0, o.spell_picks)
		var sub: String = o.subclasses[0] if not o.subclasses.is_empty() else ""
		Leveling.apply_level(gs.player, {"hp": "avg", "subclass": sub, "spells": spells})


# ------------------------------------------------------------------ stan
func _snap() -> Dictionary:
	var d: Dictionary = gs.to_dict()
	d.erase("log")
	d.erase("time")
	d.erase("explored")
	return JSON.parse_string(JSON.stringify(d))


func _restore(snap: Dictionary) -> void:
	gs.from_dict(snap.duplicate(true))


func _hash() -> String:
	return _hash_of(_snap())


func _hash_of(s: Dictionary) -> String:
	var p: Dictionary = s.player
	var inv: Array = p.get("inventory", []).duplicate()
	inv.sort()
	var removed: Array = s.get("removed_npcs", []).duplicate()
	removed.sort()
	var comp: Array = s.get("companions", []).map(func(c): return c.get("id", ""))
	comp.sort()
	# bez PD: wynikają z drogi, a scalenie stanów różniących się tylko PD skraca przeszukiwanie wielokrotnie
	# (poziom przed walką raport zbiera osobno, BFS dochodzi do stanu najpierw najkrótszą drogą)
	# tylko to, co sprawdzają warunki: flagi i przedmioty z warunków, flagi jednorazowych wyborów (ukrywają wybory),
	# złoto jako liczba przekroczonych progów z warunków
	var flags := []
	for k in s.flags.keys():
		if s.flags[k] and (_rel_flags.has(str(k)) or str(k).begins_with("dlg_")):
			flags.append(str(k))
	flags.sort()
	inv = inv.filter(func(i): return _rel_items.has(str(i)))
	var gold := 0
	for g in _gold_steps:
		if int(p.get("gold", 0)) >= g:
			gold += 1
	var key := {"f": flags, "q": s.quests, "r": s.reputation, "i": inv, "g": gold,
		"rm": removed, "c": comp, "e": s.get("ending", "")}
	var h := JSON.stringify(key, "", true).sha1_text()
	if debug_keys and not _key_dump.has(h):
		_key_dump[h] = key
	return h


var debug_keys := false
var _key_dump := {}


func _record_ending(ending: String, path: Array, snap: Dictionary) -> void:
	var e: Dictionary = _endings.get(ending, {"count": 0, "path": [], "level": 0, "xp": 0})
	e.count += 1
	if e.path.is_empty() or path.size() < e.path.size():
		e.path = path
		e.level = int(snap.player.get("level", 1))
		e.xp = int(snap.player.get("xp", 0))
	_endings[ending] = e


func _report() -> Dictionary:
	var unseen := []
	for dlg in _dialogue_ids():
		var nodes: Dictionary = DB.dialogue(dlg).get("nodes", {})
		for node in nodes.keys():
			if nodes[node].get("effects", []).any(func(e): return e.has("end_game")):
				continue   # gra kończy się przy wejściu w węzeł, jego wyborów nie zobaczy nikt
			for i in nodes[node].get("choices", []).size():
				var k := "%s/%s/%d" % [dlg, node, i]
				if not _seen_choices.has(k):
					unseen.append(k)
	unseen.sort()
	return {"class": gs.player.class_id, "difficulty": Difficulty.current, "states": _states,
		"truncated": _truncated, "endings": _endings, "combats": _combats,
		"walks": random_walks, "walk_endings": _walk_endings, "walk_stuck": _walk_stuck,
		"dead_ends": _dead_ends.slice(0, 10), "dead_end_count": _dead_ends.size(), "unseen_choices": unseen,
		"keys": _key_dump.values() if debug_keys else []}


func _dialogue_ids() -> Array:
	var out := []
	for group in ["npcs", "objects"]:
		for e in map.get(group, []):
			if e.get("dialogue", "") != "" and not e.dialogue in out:
				out.append(e.dialogue)
	return out


## Rzuty do sprawdzenia przy teście: k20 = 20 i 1, a przy pasach cost/gain także sukces i porażka o włos
## (docs/decisions/0008). Wynik wymuszony sześć razy, bo przewaga i Heroiczna inspiracja biorą kolejne kości.
func _check_variants(choice: Dictionary) -> Array:
	var out: Array = [SUCCESS, FAIL]
	var chk: Dictionary = choice.check
	if chk.has("cost_effects"):
		out.append(_repeat(DialogueRunner.natural_for_margin(gs.player, chk, 1)))
	if chk.has("gain_effects"):
		out.append(_repeat(DialogueRunner.natural_for_margin(gs.player, chk, -1)))
	return out


static func _repeat(n: int) -> Array:
	var a := []
	for k in 6:
		a.append(n)
	return a


static func _variant_mark(dice: Array) -> String:
	if dice.is_empty():
		return ""
	if dice == SUCCESS:
		return "+"
	if dice == FAIL:
		return "-"
	return "~"

