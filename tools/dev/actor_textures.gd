# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends SceneTree
## Wypisuje tekstury, których faktycznie używają modele z assets/actors (do sprzątania osieroconych plików).
## godot --headless -s tools/dev/actor_textures.gd

func _walk(n: Node, out: Dictionary) -> void:
	if n is MeshInstance3D and n.mesh:
		for s in n.mesh.get_surface_count():
			var m = n.get_active_material(s)
			if m is BaseMaterial3D:
				for t in [m.albedo_texture, m.normal_texture, m.emission_texture, m.ao_texture]:
					if t:
						out[t.resource_path if t.resource_path != "" else "(wbudowana)"] = true
	for c in n.get_children():
		_walk(c, out)

func _init() -> void:
	var only := OS.get_cmdline_user_args()
	for f in DirAccess.get_files_at("res://assets/actors"):
		if not only.is_empty() and not f.get_basename() in only:
			continue
		if f.ends_with(".glb"):
			var inst: Node = load("res://assets/actors/" + f).instantiate()
			var out := {}
			_walk(inst, out)
			print("TEX ", f, " ", " ".join(out.keys()))
			inst.free()
	quit()
