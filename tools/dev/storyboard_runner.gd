# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends RefCounted
## Odtwarza kadry data/storyboard.json przez wejścia gry i zapisuje PNG (poza trybem headless).
## Kadr: "class" (postać szybkiego startu, domyślnie ta z wiersza poleceń), "seed" (stałe rzuty),
## "capture" (sekundy od ostatniego kroku do zrzutu, domyślnie 2.7),
## "expect" ("quest", "ending", "window", "mode", "acting": id postaci, którą gracz steruje).
## Kroki: {"actor"}, {"node", "choice", "roll"?}, {"menu": "map"|"spellbook"}, {"wait": "player_turn"|"companion"},
## {"cast": czar} (wybór z księgi), {"target": aktor} (podgląd celu) albo {"target": aktor, "click": true} (rzut).

const WAIT_TIMEOUT := 30.0


func run(main: Node, id: String, output: String) -> bool:
	var board := DB.entry("storyboard", id)
	if board.is_empty():
		push_error("STORYBOARD: nieznana plansza " + id)
		return false
	var initial := GameState.player.to_dict().duplicate(true)
	for panel in board.panels:
		var pc: Creature = main.quick_character(panel["class"]) if panel.has("class") else Creature.from_dict(initial.duplicate(true))
		GameState.new_game(pc)
		GameState.map_id = id
		if panel.has("seed"):
			Dice.seed_rng(int(panel.seed))
		main.start_world()
		await main.get_tree().process_frame
		var world: Node = main.screen
		world._hush_all()
		world.set_process(false)
		var steps: Array = []
		for step in panel.steps:
			steps.append_array(board[step.sequence] if step.has("sequence") else [step])
		for step in steps:
			if not await _perform(world, step):
				push_error("STORYBOARD: %s: %s" % [panel.id, step])
				return false
		var expected: Dictionary = panel.expect
		if not GameState.check({"quest": expected.quest}) or (
			expected.has("ending") and (GameState.ending != expected.ending or world.mode != "ended")
		) or (expected.has("window") and not world.hud.is_window_open()) or (
			expected.has("mode") and world.mode != expected.mode
		) or (expected.has("acting") and world._acting().id != expected.acting):
			push_error("STORYBOARD: %s: oczekiwano %s" % [panel.id, expected])
			return false
		if DisplayServer.get_name() != "headless":
			# Krótkie komunikaty z wcześniejszych kroków nie zasłaniają kadru (kadr efektu czaru łapie animację).
			await main.get_tree().create_timer(float(panel.get("capture", 2.7))).timeout
			await RenderingServer.frame_post_draw
			var path: String = output.path_join(panel.id + ".png")
			if main.get_viewport().get_texture().get_image().save_png(path) != OK:
				push_error("STORYBOARD: nie zapisano " + path)
				return false
		if expected.get("ending", "") == "portal":
			var xp := GameState.player.xp
			world.hud.end_screen_choice.emit("continue")
			if not await _perform(world, {"actor": "arch"}) or not await _perform(world, {"node": "after_portal", "choice": 0}) or (
				GameState.player.xp != xp or world.mode != "explore"
			):
				push_error("STORYBOARD: ponowne użycie Łuku po finale")
				return false
		print("STORYBOARD_PANEL_OK ", panel.id)
	return true


func _perform(world: Node, step: Dictionary) -> bool:
	if step.has("actor"):
		var actor: Actor = world.actors.get(step.actor)
		if not is_instance_valid(actor):
			return false
		var occupied: Dictionary = world._occupied()
		for direction in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
			var cell: Vector2i = actor.cell + direction
			if world.grid.is_open(cell) and not occupied.has(cell):
				world.player_actor.place(cell)
				for f in world._followers():   # w grze towarzysz idzie za graczem; tu gracz przeskakuje
					f.place(world._free_cell_near(cell))
					f.creature.grid_pos = f.cell
				world._reveal_around(cell)
				world.cam.snap_to(world.player_actor.position)
				world._explore_click(actor.cell)
				return world.mode == "dialogue"
		return false
	if step.has("menu"):
		world._on_menu(step.menu)
		return world.hud.is_window_open()
	if step.has("wait"):
		# Tury wrogów odgrywa _process świata; po kroku znów go wstrzymujemy (trasy NPC, okrzyki).
		# "companion": czekamy na turę sterowanego towarzysza, a tury gracza po drodze kończymy.
		var want_companion: bool = step.wait == "companion"
		var ready := func() -> bool:
			return world.mode == "combat" and world._player_can_act() and (
				not want_companion or world._acting() != GameState.player)
		world.set_process(true)
		var t := 0.0
		while not ready.call() and t < WAIT_TIMEOUT:
			if want_companion and world.mode == "combat" and world._player_can_act():
				world._on_combat_action("end_turn", {})
			await world.get_tree().process_frame
			t += world.get_process_delta_time()
		world.set_process(false)
		return ready.call()
	if step.has("cast"):
		world.hud.spellbook_cast.emit(step.cast)
		return world.selected.get("kind", "") == "spell" and not world.hud.is_window_open()
	if step.has("target"):
		var actor: Actor = world.actors.get(step.target)
		if not is_instance_valid(actor):
			return false
		var screen: Vector2 = world.get_viewport().get_camera_3d().unproject_position(actor.position)
		world._combat_hover(actor.cell, screen)
		if step.get("click", false):
			var before := JSON.stringify(GameState.player.slots)
			world._combat_click(actor.cell)
			world.hud.show_tooltip("", Vector2.ZERO)
			world.set_process(true)   # efekt czaru i dziennik walki
			# czar rzucony = wydany slot (sztuczki bez slotu: sama zmiana wyboru)
			var level := int(Spellcasting.spell(str(world.selected.get("data", {}).get("id", ""))).get("level", 0))
			return world.selected.get("kind", "") == "" and (JSON.stringify(GameState.player.slots) != before or level == 0)
		return true
	var runner: DialogueRunner = world.dialogue
	var choice := int(step.choice)
	if not runner or runner.current_id != step.node:
		return false
	if not runner.visible_choices().any(func(option): return option.index == choice):
		return false
	if step.has("roll"):
		Dice.force([step.roll, step.roll])
	world.hud.dialogue_choice.emit(choice)
	Dice.clear_forced()
	return true
