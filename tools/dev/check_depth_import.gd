# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends SceneTree
## Sprawdza, że mapa głębi wczytana jako zasób (jak w eksporcie) jest identyczna z plikiem PNG.
## godot --headless -s res://tools/dev/check_depth_import.gd -- rusty_market
func _init() -> void:
	var id: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "rusty_market"
	var path := "res://assets/backgrounds/%s_depth.png" % id
	var a: Image = (load(path) as Texture2D).get_image()
	var b := Image.load_from_file(ProjectSettings.globalize_path(path))
	b.convert(a.get_format())
	print("format ", a.get_format(), " mipmaps ", a.has_mipmaps(), " size ", a.get_size())
	print("DEPTH_IMPORT_", "OK" if a.get_data() == b.get_data() else "DIFF")
	quit()
