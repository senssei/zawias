extends Node
## Przełącza ekrany: menu główne, kreator postaci, świat.

var screen: Node


func _ready() -> void:
	RenderingServer.set_default_clear_color(UI.BG)
	var args := OS.get_cmdline_user_args()
	if "--creation" in args:
		show_creation()
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
	GameState.new_game(CharacterBuilder.build(opts))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			GameState.map_id = a.substr(6)
	start_world()
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


var _fps_samples: Array[float] = []


func _process(_d: float) -> void:
	if "--fps" in OS.get_cmdline_user_args():   # debug: średnie i minimalne FPS z 8 s po rozgrzewce, potem wyjście
		var f := Engine.get_process_frames()
		if f > 120:
			_fps_samples.append(1.0 / maxf(_d, 1e-6))
		if _fps_samples.size() > 0 and Time.get_ticks_msec() > 14000:
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
