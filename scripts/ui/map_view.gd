# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name MapView
extends Control
## Mapa z siatki mapy (data/maps/<id>.json): budynki i ulice w kolorach legendy, mgła nieodkrytych pól,
## znaczniki (gracz, postacie, cele zadania, wrogowie, zamknięte drzwi), podpisy budynków.
## Minimapa (rotate_with_camera): wyśrodkowana na graczu i obrócona tak, żeby góra mapy była kierunkiem kamery.
## Pełna mapa: cała siatka dopasowana do kontrolki, północ u góry, klik = pole (cell_clicked).

signal cell_clicked(cell: Vector2i)

## Znacznik: {"cell": Vector2i, "kind": "player"|"npc"|"object"|"loot"|"enemy"|"ally"|"lock", "name": String, "quest": bool}
var markers_fn: Callable
var map: Dictionary
var rotate_with_camera := false
var yaw := 0.0                       # kąt kamery (rad), tylko dla minimapy
var cell_px := 8.0                   # minimapa; pełna mapa dopasowuje sama
var show_names := false
var explored: Callable               # (Vector2i) -> bool; brak = wszystko odkryte

var _rows: Array = []
var _legend: Dictionary = {}
var _size := Vector2i.ZERO
var _labels: Array = []              # [{text, at: Vector2 (pole)}]
var _xf := Transform2D.IDENTITY
var _t := 0.0

const FOG := Color(0.07, 0.05, 0.05)
const MARK := {
	"player": Color("#5fa8d3"), "npc": Color("#e8c98a"), "object": Color("#a39a8c"),
	"enemy": Color("#e0634f"), "ally": Color("#8fcf7a"), "lock": Color("#e0634f"),
	"loot": Color("#f2c14e"),
}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func set_map(m: Dictionary) -> void:
	map = m
	_rows = m.get("rows", [])
	_legend = m.get("legend", {})
	_size = Vector2i(_rows[0].length() if not _rows.is_empty() else 0, _rows.size())
	# podpisy budynków: środek pól z danym znakiem legendy, który ma "label"
	var acc := {}
	for y in _size.y:
		var row: String = _rows[y]
		for x in row.length():
			var ch := row[x]
			if _legend.get(ch, {}).has("label"):
				if not acc.has(ch):
					acc[ch] = [Vector2.ZERO, 0, x, x]
				acc[ch][0] += Vector2(x + 0.5, y + 0.5)
				acc[ch][1] += 1
				acc[ch][2] = mini(acc[ch][2], x)
				acc[ch][3] = maxi(acc[ch][3], x)
	_labels.clear()
	for ch in acc.keys():
		_labels.append({"text": str(_legend[ch].label), "at": acc[ch][0] / acc[ch][1], "char": ch,
			"width": acc[ch][3] - acc[ch][2] + 1})
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


## Środek widoku w polach: minimapa = gracz, pełna mapa = środek siatki.
func _center() -> Vector2:
	if rotate_with_camera:
		for m in _markers():
			if m.kind == "player":
				return Vector2(m.cell) + Vector2(0.5, 0.5)
	return Vector2(_size) * 0.5


func _scale() -> float:
	if rotate_with_camera or _size.x == 0:
		return cell_px
	return minf(size.x / _size.x, size.y / _size.y)


## Kąt, o który obracamy mapę, żeby kierunek patrzenia kamery wskazywał górę kontrolki.
func _angle() -> float:
	if not rotate_with_camera:
		return 0.0
	var fwd := Vector2(-sin(yaw), -cos(yaw))     # przód kamery na płaszczyźnie (x, z)
	return -PI / 2.0 - fwd.angle()


func _update_xf() -> void:
	_xf = Transform2D(_angle(), Vector2.ONE * _scale(), 0.0, size * 0.5) * Transform2D(0.0, -_center())


func to_screen(p: Vector2) -> Vector2:
	return _xf * p


func to_cell(screen: Vector2) -> Vector2i:
	var p := _xf.affine_inverse() * screen
	return Vector2i(floori(p.x), floori(p.y))


func _markers() -> Array:
	return markers_fn.call() if markers_fn.is_valid() else []


## Jak rysować znacznik: "" = ukryty we mgle, "fog" = cel zadania we mgle (sam romb i podpis), "full" = cały.
func marker_visibility(m: Dictionary) -> String:
	if m.kind == "player" or _is_explored(m.cell):
		return "full"
	return "fog" if m.get("quest", false) else ""


func _is_explored(c: Vector2i) -> bool:
	return explored.call(c) if explored.is_valid() else true


## Nieodkryte pole: im więcej odkrytych sąsiadów, tym bardziej prześwituje teren (miękki brzeg mgły).
func _fog_fringe(c: Vector2i, ch: String) -> Color:
	var n := 0
	for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
		if _is_explored(c + d):
			n += 1
	if n == 0:
		return FOG
	return FOG.lerp(_cell_color(ch), 0.12 + 0.05 * n)


func _cell_color(ch: String) -> Color:
	var l: Dictionary = _legend.get(ch, {})
	var c := Color(str(l.get("color", "#555555")))
	if l.get("solid", false):
		if l.has("label") or ch in ["=", "c"]:
			return c.lightened(0.25)          # budynki i stragany jaśniejsze niż ulica
		return c.darkened(0.25)               # mury i zabudowa bez nazwy
	if l.get("door", false):
		return Color("#c08a4a")
	return c.darkened(0.1)


func _draw() -> void:
	if _size == Vector2i.ZERO:
		return
	_update_xf()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.045, 0.045, 0.92))
	draw_set_transform_matrix(_xf)
	for y in _size.y:
		var row: String = _rows[y]
		for x in row.length():
			var c := Vector2i(x, y)
			var col := _cell_color(row[x]) if _is_explored(c) else _fog_fringe(c, row[x])
			draw_rect(Rect2(Vector2(x, y), Vector2(1.02, 1.02)), col)
	draw_rect(Rect2(Vector2.ZERO, Vector2(_size)), Color(UI.BRASS, 0.35), false, 2.0 / _scale())   # granice mapy we mgle
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var font := get_theme_default_font()
	var s := _scale()
	# podpisy budynków (pełna mapa albo minimapa w dużym powiększeniu)
	if show_names:
		for lb in _labels:
			var at: Vector2 = lb.at
			if not _is_explored(Vector2i(at)):
				continue
			var fs := clampi(int(s * 0.8), 11, 18)
			# dłuższy niż budynek: dwie linie (sąsiednie budynki nie zlewają podpisów)
			var lines := _wrap(lb.text, font, fs, lb.width * s * 1.15)
			var y0 := to_screen(at).y - (lines.size() - 1) * fs * 0.6 + fs * 0.35
			for i in lines.size():
				var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var p := Vector2(to_screen(at).x - w / 2, y0 + i * fs * 1.2)
				p.x = clampf(p.x, 4.0, maxf(4.0, size.x - w - 4.0))      # podpis przy krawędzi nie ucieka poza mapę
				draw_string_outline(font, p, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
				draw_string(font, p, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.TEXT)
	# znaczniki
	var r := clampf(s * 0.42, 3.5, 9.0)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var player_m := {}
	for m in _markers():
		var cell: Vector2i = m.cell
		var vis := marker_visibility(m)
		if vis == "":
			continue
		var fogged := vis == "fog"
		var p := to_screen(Vector2(cell) + Vector2(0.5, 0.5))
		if not Rect2(Vector2.ZERO, size).grow(r).has_point(p):
			continue
		var col: Color = MARK.get(m.kind, Color.WHITE)
		# cel zadania we mgle: sam romb z podpisem (wiadomo, dokąd iść, ale nie co tam stoi)
		match "fog" if fogged else m.kind:
			"fog":
				pass
			"player":
				player_m = m
				continue
			"lock":
				var d := r * 0.8
				draw_line(p + Vector2(-d, -d), p + Vector2(d, d), col, 2.0)
				draw_line(p + Vector2(-d, d), p + Vector2(d, -d), col, 2.0)
			"object":
				draw_rect(Rect2(p - Vector2(r, r) * 0.7, Vector2(r, r) * 1.4), col)
			"loot":
				# złota czteroramienna gwiazdka: nie myli się z kaflami (na obróconej minimapie kwadraty to romby)
				var k := maxf(r * 1.1, 6.0)
				var star := PackedVector2Array()
				for i in 8:
					var ang := i * PI / 4.0 - PI / 2.0
					star.append(p + Vector2(cos(ang), sin(ang)) * (k if i % 2 == 0 else k * 0.38))
				draw_colored_polygon(star, col)
				draw_polyline(star + PackedVector2Array([star[0]]), Color(0, 0, 0, 0.85), 1.0)
			_:
				draw_circle(p, r, col)
				draw_arc(p, r, 0, TAU, 16, Color(0, 0, 0, 0.7), 1.0)
		if m.get("quest", false):
			var q := r + 3.0 + pulse * 3.0
			var pts := PackedVector2Array([p + Vector2(0, -q), p + Vector2(q, 0), p + Vector2(0, q), p + Vector2(-q, 0), p + Vector2(0, -q)])
			draw_polyline(pts, UI.BRASS, 2.0)
		if show_names and str(m.get("name", "")) != "":
			var fs2 := clampi(int(s * 0.65), 10, 14)
			var tp := p + Vector2(r + 3, fs2 * 0.35)
			draw_string_outline(font, tp, m.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 3, Color(0, 0, 0, 0.9))
			draw_string(font, tp, m.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, UI.BRASS if m.get("quest", false) else UI.MUTED)
	# gracz na wierzchu: strzałka w kierunku kamery na pełnej mapie, kropka z obwódką na minimapie
	if not player_m.is_empty():
		var pp := to_screen(Vector2(player_m.cell) + Vector2(0.5, 0.5))
		var pr := r * 1.15
		draw_circle(pp, pr + 2.0 + pulse * 2.0, Color(MARK.player, 0.25))
		if rotate_with_camera:
			var tri := PackedVector2Array([pp + Vector2(0, -pr * 1.5), pp + Vector2(pr, pr), pp + Vector2(-pr, pr)])
			draw_colored_polygon(tri, MARK.player)
			draw_polyline(tri + PackedVector2Array([tri[0]]), Color.WHITE, 1.5)
		else:
			draw_circle(pp, pr, MARK.player)
			draw_arc(pp, pr, 0, TAU, 20, Color.WHITE, 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(UI.BRASS, 0.5), false, 1.0)


## Dzieli podpis na dwie linie przy spacji najbliższej środka, gdy jest szerszy niż max_w.
static func _wrap(text: String, font: Font, fs: int, max_w: float) -> PackedStringArray:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w or not " " in text:
		return PackedStringArray([text])
	var best := -1
	for i in text.length():
		if text[i] == " " and (best < 0 or absi(i - text.length() / 2) < absi(best - text.length() / 2)):
			best = i
	return PackedStringArray([text.substr(0, best), text.substr(best + 1)])


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var c := to_cell(ev.position)
		if c.x >= 0 and c.y >= 0 and c.x < _size.x and c.y < _size.y:
			cell_clicked.emit(c)
			accept_event()
