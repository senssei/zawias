# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends GutTest
## Każdy asset, którego gra użyje, istnieje i daje się wczytać. Wyłapuje figurę zastępczą zamiast modelu
## (np. usunięta wyciągnięta tekstura GLB: plik modelu jest, ale load() zwraca null), brakujące portrety i dźwięki.

const GAME_ANIMS := ["idle", "walk", "attack", "cast", "hit", "death"]
const MAPS := ["rusty_market"]


func _load_scene(path: String, label: String) -> Node:
	var sc = load(path)
	assert_not_null(sc, "%s: %s nie wczytuje się" % [label, path])
	if sc == null:
		return null
	var inst: Node = sc.instantiate()
	return inst


func _anim_names(n: Node) -> Array:
	if n is AnimationPlayer:
		return Array(n.get_animation_list())
	for c in n.get_children():
		var a := _anim_names(c)
		if not a.is_empty():
			return a
	return []


## Model postaci: musi istnieć, wczytać się i mieć animacje, których gra używa (mefit lata proceduralnie).
func _check_actor(ids: Array, label: String, animated := true) -> void:
	var path := Actor.resolve_model(ids)
	assert_ne(path, "", "%s: brak modelu (szukano %s)" % [label, ids])
	if path == "":
		return
	var inst := _load_scene(path, label)
	if inst == null:
		return
	if animated:
		var anims := _anim_names(inst)
		for a in GAME_ANIMS:
			assert_true(a in anims, "%s: %s bez animacji %s" % [label, path, a])
	inst.free()


func test_character_models_load():
	for cls in DB.table("classes").keys():
		_check_actor(["pc_" + cls], "gracz " + cls)
	for map_id in MAPS:
		var m := DB.map(map_id)
		for n in m.npcs:
			_check_actor([n.id, n.get("model", ""), n.get("monster", "")], "NPC " + n.id, n.get("monster", "") != "rust_mephit")
	for enc in DB.table("encounters").values():
		for s in enc.get("spawn", []):
			_check_actor([s.id, s.monster], "spawn " + s.id, s.monster != "rust_mephit")


func test_prop_models_load():
	for map_id in MAPS:
		var m := DB.map(map_id)
		var ids := {}
		for o in m.objects:
			ids[Actor.resolve_model([o.id, o.get("shape", "")], "res://assets/props/")] = o.id
		for d in m.get("decor", []):
			ids["res://assets/props/%s.glb" % d.id] = d.id
		for path in ids.keys():
			assert_ne(path, "", "rekwizyt %s: brak modelu" % ids[path])
			if path != "":
				var inst := _load_scene(path, "rekwizyt " + ids[path])
				if inst:
					inst.free()


func test_every_glb_in_assets_loads():
	for dir in ["res://assets/actors/", "res://assets/props/"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".glb"):
				var inst := _load_scene(dir + f, f)
				if inst:
					inst.free()


func test_portraits_exist():
	var mapping: Dictionary = load("res://scripts/world/world.gd").DIALOGUE_PORTRAITS
	var dir := DirAccess.open("res://data/dialogues")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var id_ := f.get_basename()
		var pid: String = mapping.get(id_, id_)   # np. backdoor -> door
		assert_not_null(HUD.portrait_texture(pid), "dialog %s: brak portretu assets/portraits/%s.png" % [id_, pid])
	for cls in DB.table("classes").keys():
		assert_not_null(HUD.portrait_texture("pc_" + cls), "brak portretu pc_" + cls)


## Identyfikatory dźwięków wyciągnięte z kodu (wywołania Audio.* i mapy id → dźwięk), więc test nadąża za grą.
func test_audio_ids_resolve():
	var ids := {"music": {}, "ambient": {}, "sfx": {}}
	var re_call := RegEx.create_from_string('Audio\\.(sfx|play_music|set_ambient)\\(\\[?"([a-z0-9_]+)"')
	var re_map := RegEx.create_from_string('"[a-z]+": "((?:spell|chest|portal|ui)[a-z0-9_]*)"')
	var re_spell := RegEx.create_from_string('id_ = "([a-z0-9_]+)"')
	var files := []
	for d in ["res://scripts/world/", "res://scripts/ui/", "res://scripts/game/", "res://scripts/"]:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				files.append(d + f)
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		for m in re_call.search_all(src):
			var kind: String = {"sfx": "sfx", "play_music": "music", "set_ambient": "ambient"}[m.get_string(1)]
			ids[kind][m.get_string(2)] = path
		for m in re_map.search_all(src):
			ids.sfx[m.get_string(1)] = path
		if path.ends_with("audio.gd"):
			for m in re_spell.search_all(src):
				ids.sfx[m.get_string(1)] = path
	assert_gt(ids.sfx.size(), 10, "skan kodu znalazł efekty")
	for kind in ids.keys():
		for id_ in ids[kind].keys():
			var base := "res://assets/audio/%s/%s" % [kind, id_]
			var ok := ResourceLoader.exists(base + ".wav") or ResourceLoader.exists(base + "_1.wav")
			assert_true(ok, "%s: brak dźwięku %s (%s)" % [ids[kind][id_].get_file(), base, kind])
