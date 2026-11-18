class_name CombatGrid
extends RefCounted
## Siatka mapy (1 pole = 1,5 m). Ściany, trudny teren, ścieżki, linia wzroku.

var width := 0
var height := 0
var rows: Array = []
var legend := {}
var solid := {}          # Vector2i -> true (stałe przeszkody)
var difficult := {}      # Vector2i -> true
var dynamic := {}        # Vector2i -> true (zamknięte drzwi, obiekty)
var astar := AStarGrid2D.new()

const DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


func _init(map: Dictionary = {}) -> void:
	if not map.is_empty():
		load_map(map)


func load_map(map: Dictionary) -> void:
	rows = map.rows
	legend = map.legend
	height = rows.size()
	width = String(rows[0]).length()
	astar.region = Rect2i(0, 0, width, height)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
	astar.update()
	for y in height:
		for x in width:
			var ch := String(rows[y])[x]
			var info: Dictionary = legend.get(ch, {})
			var p := Vector2i(x, y)
			if info.get("solid", false):
				solid[p] = true
				astar.set_point_solid(p, true)
			if info.get("difficult", false):
				difficult[p] = true
				astar.set_point_weight_scale(p, 2.0)


func tile(p: Vector2i) -> String:
	if not in_bounds(p):
		return "#"
	return String(rows[p.y])[p.x]


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func is_open(p: Vector2i) -> bool:
	return in_bounds(p) and not solid.has(p) and not dynamic.has(p)


func set_dynamic_block(p: Vector2i, blocked: bool) -> void:
	if blocked:
		dynamic[p] = true
	else:
		dynamic.erase(p)
	if in_bounds(p):
		astar.set_point_solid(p, blocked or solid.has(p))


func step_cost(p: Vector2i) -> int:
	return 2 if difficult.has(p) else 1


static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func neighbors(p: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		var n: Vector2i = p + d
		if not is_open(n):
			continue
		if d.x != 0 and d.y != 0:
			# bez ścinania rogów
			if not is_open(p + Vector2i(d.x, 0)) or not is_open(p + Vector2i(0, d.y)):
				continue
		out.append(n)
	return out


## Ścieżka poza walką (AStar). occupied: pola zajęte przez postacie.
func find_path(from: Vector2i, to: Vector2i, occupied: Dictionary = {}) -> Array[Vector2i]:
	if not is_open(to) or occupied.has(to):
		return []
	for p in occupied.keys():
		if p != from:
			astar.set_point_solid(p, true)
	var raw := astar.get_id_path(from, to)
	for p in occupied.keys():
		astar.set_point_solid(p, solid.has(p) or dynamic.has(p))
	var out: Array[Vector2i] = []
	for p in raw:
		out.append(p)
	return out


## Dijkstra z limitem kosztu. blocked: pola, przez które nie można przejść (wrogowie).
## no_stop: pola, na których nie można skończyć ruchu (sojusznicy).
func reachable(from: Vector2i, max_cost: int, blocked: Dictionary, no_stop: Dictionary = {}) -> Dictionary:
	var dist := {from: 0}
	var prev := {}
	var frontier: Array = [from]
	while not frontier.is_empty():
		# wybierz najtańszy (siatka mała, więc wystarczy liniowo)
		var bi := 0
		for i in frontier.size():
			if int(dist[frontier[i]]) < int(dist[frontier[bi]]):
				bi = i
		var cur: Vector2i = frontier.pop_at(bi)
		for n in neighbors(cur):
			if blocked.has(n):
				continue
			var nd := int(dist[cur]) + step_cost(n)
			if nd > max_cost:
				continue
			if not dist.has(n) or nd < int(dist[n]):
				dist[n] = nd
				prev[n] = cur
				frontier.append(n)
	var out := {}
	for p in dist.keys():
		if p == from or not no_stop.has(p):
			out[p] = {"cost": dist[p], "prev": prev.get(p, null)}
	out["_prev"] = prev
	return out


static func path_to(reach: Dictionary, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not reach.has(to):
		return out
	var prev: Dictionary = reach["_prev"]
	var cur := to
	while cur != from:
		out.push_front(cur)
		if not prev.has(cur):
			return []
		cur = prev[cur]
	out.push_front(from)
	return out


## Linia wzroku: algorytm Bresenhama, ściany blokują.
func has_los(a: Vector2i, b: Vector2i) -> bool:
	var x0 := a.x
	var y0 := a.y
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	while true:
		var p := Vector2i(x0, y0)
		if p != a and p != b and (solid.has(p) or dynamic.has(p)):
			if not legend.get(tile(p), {}).has("prop"):
				return false
		if x0 == b.x and y0 == b.y:
			return true
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return true
