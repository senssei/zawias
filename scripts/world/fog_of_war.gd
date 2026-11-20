# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name FogOfWar
extends RefCounted
## Mgła wojny w świecie 3D (malowany obszar): maska odkrytych pól (GameState.explored) jako tekstura dla
## shadera paint_depth. Maska ma SUB próbek na pole (skalowanie kubiczne), więc brzeg mgły jest miękki, a nie schodkowy.
## NPC, obiekty i rekwizyty 3D na nieodkrytych polach są ukryte (model i podpis), ale zostają w świecie: mapa, trasy i klik działają.

const SUB := 4                 # próbek maski na pole
const ACTOR_TICK := 0.25       # s między sprawdzeniami widoczności postaci

var world: Node
var w := 0
var h := 0
var texture: ImageTexture
var _img: Image
var _last := ""
var _t := 0.0


func _init(world_: Node, width: int, height: int) -> void:
	world = world_
	w = width
	h = height
	_img = Image.create(w * SUB, h * SUB, false, Image.FORMAT_L8)
	texture = ImageTexture.create_from_image(_img)


## Przelicza maskę, gdy zmieniły się odkryte pola (tanie porównanie napisu z GameState).
## Pole = piksel, potem skalowanie kubiczne w silniku (C++): miękki brzeg bez pętli po próbkach w GDScript.
func refresh() -> void:
	var s: String = GameState.explored.get(GameState.map_id, "")
	if s == _last:
		return
	_last = s
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	for i in mini(s.length(), w * h):
		if s[i] == "1":
			bytes[i] = 255
	var cells := Image.create_from_data(w, h, false, Image.FORMAT_L8, bytes)
	cells.resize(w * SUB, h * SUB, Image.INTERPOLATE_CUBIC)
	_img = cells
	texture.update(_img)
	# rekwizyty 3D (stragany, beczki) nie są częścią malunku: we mgle ukryte, po odkryciu pola widoczne
	for p in world.get_tree().get_nodes_in_group("prop3d"):
		if p is Node3D and p.is_inside_tree():
			var c := Vector2i(floori(p.global_position.x), floori(p.global_position.z))
			p.visible = GameState.is_explored(GameState.map_id, c, w)


## Postacie we mgle: ukryty model i podpis (gracz, towarzysze i uczestnicy walki zawsze widoczni).
func update_actors(delta: float, force := false) -> void:
	_t += delta
	if _t < ACTOR_TICK and not force:
		return
	_t = 0.0
	for a in world.actors.values():
		if not is_instance_valid(a):
			continue
		var hidden: bool = world.mode != "combat" and not world._is_follower(a) \
			and not GameState.is_explored(GameState.map_id, a.cell, w)
		a.set_fogged(hidden)
