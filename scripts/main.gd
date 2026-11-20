# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends Node
## Przełącza ekrany: menu główne, kreator postaci, świat.

var screen: Node


func _ready() -> void:
	RenderingServer.set_default_clear_color(UI.BG)
	add_child(DebugOverlay.new())                 # F3 (albo --debug): FPS, draw calle, GPU
	var args := OS.get_cmdline_user_args()
	if "--creation" in args:
		show_creation()
		return
	for a in args:
		if a.begins_with("--story-paths="):   # pipeline.sh story paths: przejścia na danych, raport JSON
			_story_paths(a.trim_prefix("--story-paths="))
			return
		if a.begins_with("--story-balance="):   # pipeline.sh story balance: macierz walk, raport JSON
			_story_balance(a.trim_prefix("--story-balance="))
			return
	if "--quickstart" in args:
		_quickstart()
		return
	show_menu()


func _set_screen(n: Node) -> void:
	if screen:
		screen.queue_free()
	screen = n
	add_child(n)


func show_menu() -> void:
	var m := preload("res://scripts/ui/main_menu.gd").new()
	m.new_game.connect(show_creation)
	m.load_game.connect(func(): if GameState.load_game("slot1"): start_world())
	_set_screen(m)


func show_creation() -> void:
	var cc := preload("res://scripts/ui/character_creation.gd").new()
	cc.done.connect(func(pc: Creature):
		GameState.new_game(pc)
		start_world())
	cc.back.connect(show_menu)
	_set_screen(cc)


func start_world() -> void:
	var w := preload("res://scripts/world/world.gd").new()
	w.quit_to_menu.connect(show_menu)
	w.reload_requested.connect(func(slot: String):
		if GameState.load_game(slot):
			start_world())
	_set_screen(w)


## Szybki start do testów: gotowy wojownik.
func _quickstart() -> void:
	var cls := "fighter"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--class="):
			cls = a.substr(8)
	GameState.new_game(quick_character(cls))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			GameState.map_id = a.substr(6)
	start_world()
	await _quickstart_flags()


## story paths dla każdej klasy (--classes=a,b; --difficulty=normal) do pliku JSON, potem wyjście z gry.
func _story_paths(out_path: String) -> void:
	var classes := ["fighter", "rogue", "wizard", "cleric"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--classes="):
			classes = Array(a.trim_prefix("--classes=").split(","))
		if a.begins_with("--difficulty="):
			Difficulty.current = a.trim_prefix("--difficulty=")
	var max_states := 300
	var walks := 200
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--max-states="):
			max_states = int(a.trim_prefix("--max-states="))
		if a.begins_with("--walks="):
			walks = int(a.trim_prefix("--walks="))
	var reports := []
	var script: GDScript = load("res://tools/dev/story_paths.gd")
	if script == null or not script.can_instantiate():
		push_error("STORY_PATHS: nie da się wczytać tools/dev/story_paths.gd")
		get_tree().quit(1)
		return
	for cls in classes:
		GameState.new_game(quick_character(cls))
		var explorer = script.new(GameState)
		explorer.max_states = max_states
		explorer.random_walks = walks
		explorer.debug_keys = "--debug-keys" in OS.get_cmdline_user_args()
		var t0 := Time.get_ticks_msec()
		var rep: Dictionary = explorer.explore()
		rep["seconds"] = (Time.get_ticks_msec() - t0) / 1000.0
		reports.append(rep)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(reports, "  "))
	f.close()
	print("STORY_PATHS_OK ", out_path)
	Audio.stop_for_exit()
	get_tree().quit(0)


## story balance: macierz walk (--classes, --difficulties=story,normal, --seeds=16) do pliku JSON, potem wyjście.
func _story_balance(out_path: String) -> void:
	var classes := ["fighter", "rogue", "wizard", "cleric"]
	var diffs: Array = Difficulty.ORDER.duplicate()
	var seeds := 16
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--classes="):
			classes = Array(a.trim_prefix("--classes=").split(","))
		if a.begins_with("--difficulties="):
			diffs = Array(a.trim_prefix("--difficulties=").split(","))
		if a.begins_with("--seeds="):
			seeds = int(a.trim_prefix("--seeds="))
	var script: GDScript = load("res://tools/dev/story_balance.gd")
	var rows: Array = script.run(GameState, classes, diffs, seeds, quick_character)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(rows, "  "))
	f.close()
	print("STORY_BALANCE_OK ", out_path)
	Audio.stop_for_exit()
	get_tree().quit(0)


## Postać szybkiego startu danej klasy (też dla storyboardu i testów).
static func quick_character(cls: String) -> Creature:
	var opts := {
		"name": Loc.t("Wędrowiec"), "species": "human", "background": "soldier", "class": cls,
		"scores": {"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8},
		"bonus": {"str": 2, "con": 1},
	}
	if cls == "wizard":
		opts.scores = {"str": 8, "dex": 14, "con": 13, "int": 15, "wis": 12, "cha": 10}
		opts.bonus = {"int": 2, "con": 1}
		opts.background = "sage"
	elif cls == "rogue":
		opts.scores = {"str": 8, "dex": 15, "con": 14, "int": 12, "wis": 13, "cha": 10}
		opts.bonus = {"dex": 2, "con": 1}
		opts.background = "criminal"
	elif cls == "cleric":
		opts.scores = {"str": 14, "dex": 8, "con": 13, "int": 10, "wis": 15, "cha": 12}
		opts.bonus = {"wis": 2, "cha": 1}
		opts.background = "acolyte"
	return CharacterBuilder.build(opts)


func _quickstart_flags() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--flags="):
			for f in a.substr(8).split(","):
				GameState.flags[f] = true
		if a.begins_with("--encounter="):
			await get_tree().process_frame
			screen.start_combat(a.substr(12))
		if a.begins_with("--dialogue="):
			await get_tree().process_frame
			screen._open_dialogue(a.substr(11))
		if a.begins_with("--xp="):
			await get_tree().process_frame
			GameState.apply_effects([{"xp": int(a.substr(5))}])
			if "--levelup" in OS.get_cmdline_user_args():
				screen._on_menu("levelup")
		if a.begins_with("--join="):   # debug: towarzysz w drużynie od startu (np. --join=lis)
			await get_tree().process_frame
			GameState.join_party(a.substr(7))
		if a.begins_with("--words="):   # debug: rejestr słowa, np. --words=mirela_key:broken,kwit_custodian:hidden
			for w in a.substr(8).split(","):
				var kv := w.split(":")
				GameState.words[kv[0]] = kv[1]
		if a == "--journal":
			await get_tree().process_frame
			screen._on_menu("journal")
		if a.begins_with("--ending="):
			await get_tree().process_frame
			screen._show_ending(a.substr(9))
		if a == "--openmap":
			await get_tree().process_frame
			screen._on_menu("map")
		if a == "--settings":
			await get_tree().process_frame
			screen.hud.open_settings()
		if a == "--showcase":
			await get_tree().process_frame
			screen.set_showcase_shot()
		if a == "--clean" or a == "--clean=arch":
			await get_tree().process_frame
			screen.set_clean_shot(a == "--clean=arch")
		if a.begins_with("--goto="):
			var xy := a.substr(7).split(",")
			screen.player_actor.place(Vector2i(int(xy[0]), int(xy[1])))
			screen.cam.snap_to(screen.player_actor.position)
			screen._reveal_around(screen.player_actor.cell)
	# Debug kamery: --camyaw=stopnie --zoom=n --camat=x,y; zrzuty do malowania: --paintshots=katalog
	var camyaw := 0.0
	var zoom := 16.0
	var camat := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--camyaw="):
			camyaw = float(a.substr(9))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
		elif a.begins_with("--camat="):
			camat = a.substr(8)
		elif a.begins_with("--walkto="):
			var wt := a.substr(9).split(",")
			await get_tree().process_frame
			screen._explore_click(Vector2i(int(wt[0]), int(wt[1])))
		elif a.begins_with("--paintshots="):
			await get_tree().process_frame
			await screen.paint_shots(a.substr(13))
			get_tree().quit()
			return
	if camyaw != 0.0 or zoom != 16.0 or camat != "":
		await get_tree().process_frame
		if camat != "":
			screen.cam.follow = null
			var xy := camat.split(",")
			screen.cam.target_pos = Vector3(float(xy[0]) + 0.5, 0, float(xy[1]) + 0.5)
		screen.cam.set_view(camyaw, zoom)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--storyboard="):
			var id := a.trim_prefix("--storyboard=")
			var output := ""
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--storyboard-output="):
					output = arg.trim_prefix("--storyboard-output=")
			if DisplayServer.get_name() != "headless" and output.is_empty():
				push_error("STORYBOARD: brak katalogu wyjściowego")
				get_tree().quit(1)
				return
			var ok: bool = await preload("res://tools/dev/storyboard_runner.gd").new().run(self, id, output)
			Audio.stop_for_exit()
			await get_tree().create_timer(0.2, true, false, true).timeout
			get_tree().quit(0 if ok else 1)
			return
		if a.begins_with("--spellfx="):
			var ids := a.substr(10).split(",")
			for id in ids:
				if Spellcasting.spell(id).is_empty():
					push_error("SPELLFX: " + id)
					get_tree().quit(1)
					return
			await _preview_spell_fx(ids)
			return


func _preview_spell_fx(ids: PackedStringArray) -> void:
	var world := screen
	world.begin_spell_fx_preview()
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spellfx-capture="):
			output = arg.trim_prefix("--spellfx-capture=")
	await get_tree().create_timer(0.35).timeout
	while is_instance_valid(world) and screen == world:
		var capture_error := OK
		for id in ids:
			if not is_instance_valid(world) or screen != world:
				return
			world.player_actor.play_anim("idle")
			await get_tree().create_timer(0.2).timeout
			if not is_instance_valid(world) or screen != world:
				return
			var animation: Tween = world.preview_spell_fx(id)
			if not output.is_empty():
				capture_error = await _capture_spell_fx(id, animation, output)
			if animation.is_running():
				await animation.finished
			if capture_error != OK:
				break
			if not output.is_empty() or "--spellfx-once" in OS.get_cmdline_user_args():
				print("SPELLFX_PREVIEW_OK ", id)
		if not output.is_empty() or "--spellfx-once" in OS.get_cmdline_user_args():
			Audio.stop_for_exit()
			await get_tree().create_timer(0.15).timeout
			get_tree().quit(0 if capture_error == OK else 1)
			return
		await get_tree().create_timer(1.1).timeout


func _capture_spell_fx(id: String, animation: Tween, output: String) -> Error:
	var duration := float(DB.entry("spell_fx", id).seconds)
	for phase in [18, 50, 83]:
		while animation.is_running() and animation.get_total_elapsed_time() < duration * phase / 100.0:
			await RenderingServer.frame_post_draw
		var path := output.path_join("%s-%02d.png" % [id, phase])
		var frame := get_viewport().get_texture().get_image()
		var error := frame.save_png(path)
		if error != OK:
			push_error("SPELLFX_CAPTURE: %s (%s)" % [path, error_string(error)])
			return error
		print("SPELLFX_FRAME ", path)
	return OK


var _fps_samples: Array[float] = []
var _fps_from := -1                     # ms pierwszej próbki (wczytywanie bywa dłuższe niż kilka sekund)


func _process(_d: float) -> void:
	if "--fps" in OS.get_cmdline_user_args():   # debug: średnie i minimalne FPS z 8 s po rozgrzewce, potem wyjście
		var f := Engine.get_process_frames()
		if f > 120:
			if _fps_from < 0:
				_fps_from = Time.get_ticks_msec()
			_fps_samples.append(1.0 / maxf(_d, 1e-6))
		if _fps_from >= 0 and Time.get_ticks_msec() - _fps_from > 8000:
			_fps_samples.sort()
			var avg := 0.0
			for v in _fps_samples:
				avg += v
			print("FPS avg %.0f, 1%% low %.0f, klatek %d" % [avg / _fps_samples.size(), _fps_samples[_fps_samples.size() / 100], _fps_samples.size()])
			get_tree().quit()
	for a in OS.get_cmdline_user_args():
		# --shotseq=katalog[,od,co,ile]: seria klatek (np. do oglądania animacji)
		if a.begins_with("--shotseq="):
			var parts := a.substr(10).split(",")
			var start := int(parts[1]) if parts.size() > 1 else 30
			var every := int(parts[2]) if parts.size() > 2 else 4
			var count := int(parts[3]) if parts.size() > 3 else 24
			var f := Engine.get_process_frames() - start
			if f >= 0 and f % every == 0:
				get_viewport().get_texture().get_image().save_png(parts[0].path_join("f%03d.png" % (f / every)))
				if f / every >= count - 1:
					get_tree().quit()
		if a.begins_with("--shot="):
			if Engine.get_process_frames() == 40:
				var img := get_viewport().get_texture().get_image()
				img.save_png(a.substr(7))
				get_tree().quit()
