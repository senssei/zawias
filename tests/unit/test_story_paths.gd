# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends GutTest
## story paths (tools/dev/story_paths.gd) na małych limitach: oba finały osiągalne, walki w raporcie,
## wybory z dialogów widziane, stan gry przywrócony po przejściach.

func test_explorer_reaches_endings_and_restores_state():
	var gs = get_tree().root.get_node("GameState")
	gs.new_game(load("res://scripts/main.gd").quick_character("rogue"))
	var before: String = JSON.stringify(gs.to_dict().player)
	var ex = load("res://tools/dev/story_paths.gd").new(gs)
	ex.max_states = 40
	ex.random_walks = 40
	var r: Dictionary = ex.explore()
	assert_has(r.endings, "portal", "finał przy Łuku osiągalny")
	assert_has(r.endings, "returned", "finał u Mireli osiągalny")
	assert_true(r.combats.has("warehouse"), "walka w magazynie w raporcie")
	assert_eq(r.dead_end_count, 0, "bez ślepych zaułków blisko startu")
	assert_false("backdoor/start/0" in r.unseen_choices, "łotrzyk widzi wytrych")
	assert_eq(JSON.stringify(gs.to_dict().player), before, "stan gry przywrócony")
