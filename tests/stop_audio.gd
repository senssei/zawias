# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends GutHookScript


func run() -> void:
	var tree: SceneTree = gut.get_tree()
	tree.root.get_node("Audio").stop_for_exit()
	# Pozwól mikserowi zwolnić zatrzymane strumienie, zanim GUT zamknie silnik.
	await tree.create_timer(0.1, true, false, true).timeout
