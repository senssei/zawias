extends Node3D
## Świat gry: mapa 2.5D, eksploracja, dialogi, walka turowa.

signal quit_to_menu
signal reload_requested(slot: String)

var map: Dictionary
var grid: CombatGrid
var cam: IsoCamera
var hud: HUD
var player_actor: Actor
var actors := {}                 # id -> Actor (NPC, obiekty, wrogowie)
var mode := "explore"            # explore | dialogue | combat | ended
var walk_queue: Array = []
var walking := false
var pending_interact: Actor
var dialogue: DialogueRunner
var pending_requests: Array = []
var combat: CombatManager
var encounter_id := ""
var event_queue: Array = []
var processing := false
var selected := {"kind": "", "data": {}}
var layers := {}                 # nazwa -> MultiMeshInstance3D
var hover_cell := Vector2i(-999, -999)


func _ready() -> void:
	map = DB.map(GameState.map_id)
	grid = CombatGrid.new(map)
	_build_environment()
	_build_map()
	cam = IsoCamera.new()
	add_child(cam)
	hud = HUD.new()
	add_child(hud)
	_connect_hud()
	GameState.log_added.connect(hud.add_log)
	GameState.state_changed.connect(_on_state_changed)
	GameState.world_request.connect(_on_world_request)
	_spawn_actors()
	for n in ["reach", "path", "area", "hover"]:
		layers[n] = _make_layer(n)
	_on_state_changed()
	cam.snap_to(player_actor.position)
	cam.follow = player_actor
	try_painted_area()
	Audio.play_music(map.get("music", "explore"))
	Audio.set_ambient(map.get("ambient", ["market", "wind_planar"]))
	if GameState.journal.size() <= 1 and GameState.quests.is_empty():
		hud.show_toast(Loc.t("Rdzawy Targ, Zawias"))
		GameState.add_log(Loc.t("Witaj w Zawiasie. Strażnik Hask stoi niedaleko bramy. Kliknij go, żeby porozmawiać."))


func _exit_tree() -> void:
	if GameState.log_added.is_connected(hud.add_log):
		GameState.log_added.disconnect(hud.add_log)
	if GameState.state_changed.is_connected(_on_state_changed):
		GameState.state_changed.disconnect(_on_state_changed)
	if GameState.world_request.is_connected(_on_world_request):
		GameState.world_request.disconnect(_on_world_request)


# ================================================================== budowa świata

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#1d1420")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8a6f7a")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color("#3a2433")
	env.fog_density = 0.008
	var backdrop_path := "res://assets/backgrounds/%s.png" % map.get("backdrop", "planar_void")
	if ResourceLoader.exists(backdrop_path):
		# Malowane tło za sceną (kamera ortogonalna nie widzi nieba, więc tło jest warstwą 2D)
		env.background_mode = Environment.BG_CANVAS
		env.background_canvas_max_layer = -1
		_backdrop_layer = CanvasLayer.new()
		_backdrop_layer.layer = -10
		add_child(_backdrop_layer)
		_backdrop = TextureRect.new()
		_backdrop.texture = load(backdrop_path)
		_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_backdrop_layer.add_child(_backdrop)
		_fit_backdrop()
		get_viewport().size_changed.connect(_fit_backdrop)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffc58a")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-52, -35, 0)
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#8f6fd8")
	rim.light_energy = 0.35
	rim.rotation_degrees = Vector3(-30, 150, 0)
	add_child(rim)


const PROP_DIR := "res://assets/props/"
const BACKDROP_MARGIN := 0.12
var _backdrop_layer: CanvasLayer
var _backdrop: TextureRect


## Kadr do przemalowania: sama makieta z kamery gry (bez postaci, HUD-u, napisów i tła).
func set_clean_shot(arch_only := false) -> void:
	if arch_only:
		# Sama architektura i bruk: rekwizyty i obiekty zostaną w 3D na malunku
		for n in get_tree().get_nodes_in_group("prop3d"):
			n.visible = false
		for a in actors.values():
			if is_instance_valid(a) and a.is_object:
				a.visible = false
	for r in get_tree().get_nodes_in_group("fx_rock"):
		r.visible = false
	hud.visible = false
	player_actor.visible = false
	for a in actors.values():
		if is_instance_valid(a):
			a.visible = a.is_object and not arch_only
			a.hide_labels()
	for ch in get_children():
		if ch is Label3D:
			ch.visible = false
	if _backdrop_layer:
		_backdrop_layer.visible = false
	_clear_layers()


# ================================================================== malowany obszar
# Architektura i bruk są malunkiem (FLUX) rzutowanym z ortogonalnego „projektora” obejmującego całą mapę;
# rekwizyty, obiekty i postacie zostają w 3D. Głębia malunku (Depth Anything, kalibrowana do makiety)
# daje przesłanianie i powierzchnię dla cieni. Pliki: assets/backgrounds/<mapa>_paint.png/_depth.png/_paint.json.

const PAINT_DIR := "res://assets/backgrounds/"
const DEPTH_T0 := 10.0
const DEPTH_T1 := 90.0
const PAINT_PROP_TINT := Color(0.72, 0.68, 0.74)
var paint_mode := ""             # "" | "painted"


## Projektor obejmujący całą mapę (z zapasem na wysokość budynków), w kącie widzenia kamery gry.
func projector_for_map(w_px := 2560, h_px := 1440) -> Dictionary:
	var basis := Basis.from_euler(Vector3(deg_to_rad(IsoCamera.PITCH), deg_to_rad(45.0), 0.0))
	var c0 := Vector3(grid.width / 2.0, 0.0, grid.height / 2.0)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for x in [0.0, float(grid.width)]:
		for z in [0.0, float(grid.height)]:
			for y in [-0.2, 3.5]:
				var d := Vector3(x, y, z) - c0
				var v := Vector2(d.dot(basis.x), d.dot(basis.y))
				lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
				hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	var mid := (lo + hi) / 2.0
	var center := c0 + basis.x * mid.x + basis.y * mid.y
	var aspect := float(w_px) / float(h_px)
	var size := maxf(hi.y - lo.y, (hi.x - lo.x) / aspect) * 1.06
	return {"center": [center.x, center.y, center.z], "yaw": 45.0, "pitch": IsoCamera.PITCH,
		"dist": IsoCamera.DIST, "size": size, "width": w_px, "height": h_px}


func _projector_basis(p: Dictionary) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(float(p.pitch)), deg_to_rad(float(p.yaw)), 0.0))


func _projector_center(p: Dictionary) -> Vector3:
	return Vector3(float(p.center[0]), float(p.center[1]), float(p.center[2]))


## Globalna transformacja kamery projektora (jak IsoCamera: obrót osi + odsunięcie o dist).
func _projector_xform(p: Dictionary) -> Transform3D:
	var b := _projector_basis(p)
	return Transform3D(b, _projector_center(p) + b.z * float(p.dist))


func _projector_matrix(p: Dictionary) -> Projection:
	var proj := Projection.create_orthogonal_aspect(float(p.size), float(p.width) / float(p.height), 0.1, 200.0, false)
	return proj * Projection(_projector_xform(p).affine_inverse())


## Zrzuty do malowania (z rekwizytami, sama architektura, głębia) z projektora, do katalogu dir.
func paint_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var p := projector_for_map()
	var sv := SubViewport.new()
	sv.size = Vector2i(int(p.width), int(p.height))
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.msaa_3d = Viewport.MSAA_4X
	add_child(sv)
	var c := Camera3D.new()
	c.projection = Camera3D.PROJECTION_ORTHOGONAL
	c.size = float(p.size)
	c.near = 0.1
	c.far = 200.0
	sv.add_child(c)
	c.global_transform = _projector_xform(p)
	c.current = true
	_paintify_blockout()
	set_clean_shot(false)
	await _grab(sv, dir.path_join("blockout.png"))
	set_clean_shot(true)
	await _grab(sv, dir.path_join("blockout_arch.png"))
	sv.msaa_3d = Viewport.MSAA_DISABLED
	set_depth_shot(c.global_position, -c.global_transform.basis.z)
	await _grab(sv, dir.path_join("blockout_depth.png"))
	p["heights"] = {"house": PAINT_HOUSE_HEIGHT, "wall": PAINT_WALL_HEIGHT}
	for ch in map.legend.keys():   # własna wysokość w makiecie do malowania (np. niski magazyn z dziedzińcem)
		if map.legend[ch].has("paint_height"):
			p["heights"][ch] = float(map.legend[ch].paint_height)
	var f := FileAccess.open(dir.path_join("projector.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(p, "  "))
	f.close()
	print("PAINT_SHOTS_OK ", dir)


const PAINT_HOUSE_HEIGHT := 2.9   # domy w zrzutach do malowania (makieta gry ma 1,1–1,3 m)
const PAINT_WALL_HEIGHT := 1.0


## Na czas zrzutów do malowania: realistyczne wysokości i materiały (bruk, tynk z oknami, dach, mur),
## żeby FLUX odtwarzał bryły zamiast je wymyślać. Kolizje gry są per pole, więc to tylko obraz.
func _paintify_blockout() -> void:
	var sh := load("res://shaders/blockout_paint.gdshader")
	var mats := {}
	for k in 4:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("kind", k)
		mats[k] = m
	for g in _blockout_nodes():
		var ch: String = g.get_meta("tile", ".")
		var info: Dictionary = map.legend.get(ch, {})
		var solid: bool = info.get("solid", false)
		var prop: String = info.get("prop", "")
		var kind := 0
		if prop == "rust":
			kind = 3
		elif solid and (ch == "#" or info.get("paint_kind", "") == "wall"):
			kind = 2
		elif solid and prop == "":
			kind = 1
		g.material_override = mats[kind]
		if g is MultiMeshInstance3D and kind in [1, 2]:
			var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
			var hh := PAINT_HOUSE_HEIGHT if kind == 1 else PAINT_WALL_HEIGHT
			hh = float(info.get("paint_height", hh))
			for i in mm.instance_count:
				var t := mm.get_instance_transform(i)
				t.basis = Basis().scaled(Vector3(1, hh, 1))
				t.origin.y = hh / 2.0
				mm.set_instance_transform(i, t)


func _grab(sv: SubViewport, path: String) -> void:
	for i in 6:
		await RenderingServer.frame_post_draw
	sv.get_texture().get_image().save_png(path)


## Bryły makiety bezpośrednio pod światem (bez rekwizytów 3D, postaci, napisów i podświetleń).
func _blockout_nodes() -> Array:
	var out := []
	for ch in get_children():
		if ch is GeometryInstance3D and not (ch is Label3D) and not ch.is_in_group("prop3d") \
				and not ch.is_in_group("fx_rock") and not (ch in layers.values()) and ch.name != "PaintedArea":
			out.append(ch)
	return out


func _flat_env() -> void:
	for ch in get_children():
		if ch is WorldEnvironment:
			var env: Environment = ch.environment
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			env.glow_enabled = false
			env.fog_enabled = false


## Głębia samej makiety zakodowana w kolorze (do kalibracji głębi z malunku).
func set_depth_shot(origin: Vector3, forward: Vector3) -> void:
	set_clean_shot(true)
	_flat_env()
	for ch in get_children():
		if ch is WorldEnvironment:
			ch.environment.background_mode = Environment.BG_COLOR
			ch.environment.background_color = Color.BLACK
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/depth_encode.gdshader")
	mat.set_shader_parameter("proj_origin", origin)
	mat.set_shader_parameter("proj_forward", forward)
	mat.set_shader_parameter("t0", DEPTH_T0)
	mat.set_shader_parameter("t1", DEPTH_T1)
	for g in _blockout_nodes():
		g.material_override = mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Włącza malowany obszar, jeśli mapa ma gotowy malunek (i nie wyłączono go argumentem --nopaint).
func try_painted_area() -> bool:
	var args := OS.get_cmdline_user_args()
	if "--nopaint" in args:
		return false
	for a in args:
		if a.begins_with("--paintshots"):
			return false
	var base := PAINT_DIR + GameState.map_id
	if not (FileAccess.file_exists(base + "_paint.json") and ResourceLoader.exists(base + "_paint.png")):
		return false
	var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "_paint.json"))
	var img: Image = (load(base + "_paint.png") as Texture2D).get_image()
	# głębia jako zasób: import bezstratny, bez mipmap i bez kompresji VRAM (_depth.png.import), działa też w eksporcie
	var dimg: Image = (load(base + "_depth.png") as Texture2D).get_image()
	if dimg.is_compressed() or dimg.get_format() != Image.FORMAT_RGB8:
		push_warning("Mapa głębi %s_depth.png ma zły import (%d): ustaw Lossless bez mipmap" % [base, dimg.get_format()])
		if dimg.is_compressed():
			dimg.decompress()
		dimg.convert(Image.FORMAT_RGB8)
	setup_painted_area(img, dimg, p)
	return true


func setup_painted_area(img: Image, dimg: Image, p: Dictionary) -> void:
	paint_mode = "painted"
	if not img.has_mipmaps():
		img.generate_mipmaps()
	var basis := _projector_basis(p)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/paint_depth.gdshader")
	mat.set_shader_parameter("paint", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("pdepth", ImageTexture.create_from_image(dimg))
	mat.set_shader_parameter("proj_view", _projector_matrix(p))
	mat.set_shader_parameter("proj_origin", _projector_xform(p).origin)
	mat.set_shader_parameter("proj_forward", -basis.z)
	mat.set_shader_parameter("t0", DEPTH_T0)
	mat.set_shader_parameter("t1", DEPTH_T1)
	for g in _blockout_nodes():
		g.visible = false
	for r in get_tree().get_nodes_in_group("fx_rock"):
		r.visible = false
	if _backdrop_layer:
		_backdrop_layer.visible = false
	_flat_env()
	_match_painting_light()
	# pola, na których malunek ma zabudowę (pipeline: paint_map.py suggest_blocks), są w tym trybie nieprzechodnie
	for c in p.get("blocked", []):
		var bc := Vector2i(int(c[0]), int(c[1]))
		if player_actor == null or bc != player_actor.cell:   # stary zapis na takim polu: nie zamykaj gracza
			grid.set_dynamic_block(bc, true)
	if cam:
		cam.yaw_locked = true
		cam.paint_center = _projector_center(p)
		cam.paint_half = Vector2(float(p.size) * float(p.width) / float(p.height), float(p.size)) / 2.0
	var plane := MeshInstance3D.new()
	plane.name = "PaintedArea"
	var qm := QuadMesh.new()
	var aspect := float(p.width) / float(p.height)
	qm.size = Vector2(float(p.size) * aspect, float(p.size)) * 1.02
	qm.subdivide_width = 640
	qm.subdivide_depth = 360
	plane.mesh = qm
	plane.material_override = mat
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plane.extra_cull_margin = 100.0
	add_child(plane)
	plane.global_transform = Transform3D(basis, _projector_center(p))


## Światło dla modeli 3D na malunku: przygaszone, chłodniejsze, bez drugiego światła kierunkowego
## (shader malunku traktuje każde światło kierunkowe jako źródło cienia).
func _match_painting_light() -> void:
	var first := true
	for ch in get_children():
		if ch is DirectionalLight3D:
			if first:
				ch.light_energy = 0.75
				ch.light_color = Color("#ffd2a6")
				first = false
			else:
				ch.visible = false
		elif ch is WorldEnvironment:
			var env: Environment = ch.environment
			env.ambient_light_color = Color("#7a7590")
			env.ambient_light_energy = 0.6
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color("#120d17")
	# Rekwizyty z pipeline'u są jaśniejsze i bardziej nasycone niż malunek: przygaszamy albedo
	var done := {}
	var nodes: Array = get_tree().get_nodes_in_group("prop3d")
	for a in actors.values():
		if is_instance_valid(a) and a.is_object:
			nodes.append(a)
	for n in nodes:
		_tint_materials(n, PAINT_PROP_TINT, done)


func _tint_materials(n: Node, tint: Color, done: Dictionary) -> void:
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			var m: Material = n.mesh.surface_get_material(i)
			if m is BaseMaterial3D and not done.has(m):
				done[m] = true
				(m as BaseMaterial3D).albedo_color *= tint
	for ch in n.get_children():
		_tint_materials(ch, tint, done)


## Zrzut porównawczy: postacie zostają, bez HUD-u, napisów i podświetleń.
func set_showcase_shot() -> void:
	hud.visible = false
	player_actor.hide_labels()
	for a in actors.values():
		if is_instance_valid(a):
			a.hide_labels()
	for ch in get_children():
		if ch is Label3D:
			ch.visible = false
	_clear_layers()


func _fit_backdrop() -> void:
	if _backdrop == null:
		return
	var vs := get_viewport().get_visible_rect().size
	_backdrop.size = vs * (1.0 + BACKDROP_MARGIN * 2.0)
	_backdrop.position = -vs * BACKDROP_MARGIN


func _process(_delta: float) -> void:
	# Lekka paralaksa tła względem ruchu kamery
	if _backdrop and cam:
		var vs := get_viewport().get_visible_rect().size
		var off := Vector2(cam.position.x - 20.0, cam.position.z - 10.0) * 4.0
		off = off.clamp(-vs * BACKDROP_MARGIN, vs * BACKDROP_MARGIN)
		_backdrop.position = -vs * BACKDROP_MARGIN - off
var _prop_cache := {}


## Scena rekwizytu z assets/props albo null, gdy nie wygenerowano modelu.
func _prop_scene(id_: String) -> PackedScene:
	if not _prop_cache.has(id_):
		var path := PROP_DIR + id_ + ".glb"
		_prop_cache[id_] = load(path) if ResourceLoader.exists(path) else null
		if ResourceLoader.exists(path) and _prop_cache[id_] == null:
			push_error("Rekwizyt %s istnieje, ale nie da się go wczytać" % path)
	return _prop_cache[id_]


const PROP_SCALE := {"stall": 0.8}


func _place_prop(id_: String, pos: Vector3, yaw: float = 0.0) -> bool:
	var sc := _prop_scene(id_)
	if sc == null:
		return false
	var inst: Node3D = sc.instantiate()
	inst.position = pos
	inst.rotation.y = yaw
	inst.scale = Vector3.ONE * float(PROP_SCALE.get(id_, 1.0))
	inst.add_to_group("prop3d")
	add_child(inst)
	return true


func _build_map() -> void:
	var by_char := {}
	for y in grid.height:
		for x in grid.width:
			var ch := grid.tile(Vector2i(x, y))
			if not by_char.has(ch):
				by_char[ch] = []
			by_char[ch].append(Vector2i(x, y))
	for ch in by_char.keys():
		var info: Dictionary = map.legend.get(ch, {})
		var cells: Array = by_char[ch]
		var color := Color(info.get("color", "#777777"))
		var prop_id: String = info.get("prop", "")
		if prop_id in ["stall", "crate"] and _prop_scene(prop_id) != null:
			# Rekwizyt z pipeline'u zamiast bryły: podłoga + model z lekkim, deterministycznym obrotem
			for c in cells:
				var f := MeshInstance3D.new()
				var fm := BoxMesh.new()
				fm.size = Vector3(1, 0.1, 1)
				var fmat := StandardMaterial3D.new()
				fmat.albedo_color = Color(map.legend["."].color)
				fm.material = fmat
				f.mesh = fm
				f.position = Vector3(c.x + 0.5, -0.05, c.y + 0.5)
				add_child(f)
				var yaw := (_hash(c) - 0.5) * 0.5 if prop_id == "stall" else float(int(_hash(c) * 4.0)) * PI / 2.0
				_place_prop(prop_id, Vector3(c.x + 0.5, 0.0, c.y + 0.5), yaw)
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var mesh := BoxMesh.new()
		var solid: bool = info.get("solid", false)
		var prop: String = info.get("prop", "")
		mesh.size = Vector3(1, 1, 1) if solid else Vector3(1, 0.1, 1)
		if prop == "crate":
			mesh.size = Vector3(0.8, 1, 0.8)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.9
		if prop == "rust":
			mat.emission_enabled = true
			mat.emission = Color("#6e2a10")
			mat.emission_energy_multiplier = 0.4
		mesh.material = mat
		mm.mesh = mesh
		mm.instance_count = cells.size()
		for i in cells.size():
			var c: Vector2i = cells[i]
			var h: float = info.get("height", 0.1)
			var t := Transform3D.IDENTITY
			var jitter := _hash(c) * 0.12 - 0.06
			if solid:
				var hh := h
				if prop == "":
					hh = h + (_hash(Vector2i(c.x / 3, c.y / 3)) - 0.5) * 0.5
				t = t.scaled(Vector3(1, hh, 1))
				t.origin = Vector3(c.x + 0.5, hh / 2.0, c.y + 0.5)
			else:
				t.origin = Vector3(c.x + 0.5, -0.05, c.y + 0.5)
			mm.set_instance_transform(i, t)
			mm.set_instance_color(i, color.lightened(jitter) if jitter > 0 else color.darkened(-jitter))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.set_meta("tile", ch)
		add_child(mmi)
		# Podłoga pod przeszkodami niskimi
		if solid and prop != "":
			for c in cells:
				var f := MeshInstance3D.new()
				var fm := BoxMesh.new()
				fm.size = Vector3(1, 0.1, 1)
				var fmat := StandardMaterial3D.new()
				fmat.albedo_color = Color(map.legend["."].color)
				fm.material = fmat
				f.mesh = fm
				f.position = Vector3(c.x + 0.5, -0.05, c.y + 0.5)
				add_child(f)
				if prop == "stall":
					_add_awning(c)
		if ch == "d":
			for c in cells:
				_add_lamp(Vector3(c.x + 0.5, 1.8, c.y + 0.5), Color("#ff9a4a"), 3.5)
	# Lampy targowe
	for p in [Vector2i(8, 8), Vector2i(19, 7), Vector2i(26, 11), Vector2i(4, 9), Vector2i(12, 11), Vector2i(22, 14), Vector2i(34, 6)]:
		_add_lamp(Vector3(p.x + 0.5, 2.2, p.y + 0.5), Color("#ffb066"), 6.0, true)
	_add_lamp(Vector3(16.5, 2.0, 9.5), UI.PLANAR, 5.0)
	# Dekoracje (beczki, skrzynie): modele z pipeline'u, blokują pole
	for d in map.get("decor", []):
		var dc := Vector2i(int(d.pos[0]), int(d.pos[1]))
		if _place_prop(d.id, Vector3(dc.x + 0.5, 0.0, dc.y + 0.5), float(d.get("yaw", _hash(dc) * TAU))):
			grid.set_dynamic_block(dc, true)
	# Szyldy budynków
	var labels := {"N": Vector2i(3, 4), "M": Vector2i(16, 4), "I": Vector2i(3, 13), "A": Vector2i(11, 13), "W": Vector2i(30, 13)}
	for ch in labels.keys():
		var info: Dictionary = map.legend.get(ch, {})
		if info.has("label"):
			var l := Label3D.new()
			l.text = info.label
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.font_size = 48
			l.pixel_size = 0.007
			l.outline_size = 10
			l.modulate = UI.BRASS
			var p: Vector2i = labels[ch]
			l.position = Vector3(p.x + 0.5, float(info.height) + 1.0, p.y + 0.5)
			add_child(l)
	# Pływające odłamki planów wokół mapy
	for i in 14:
		var rock := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * randf_range(0.4, 1.4)
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color("#3b2a36")
		rm.emission_enabled = true
		rm.emission = UI.PLANAR.darkened(0.3)
		rm.emission_energy_multiplier = 0.5
		bm.material = rm
		rock.mesh = bm
		var side := randi() % 4
		var pos := Vector3.ZERO
		match side:
			0: pos = Vector3(randf_range(0, 40), randf_range(-6, -2), -3)
			1: pos = Vector3(randf_range(0, 40), randf_range(-6, -2), 23)
			2: pos = Vector3(-3, randf_range(-6, -2), randf_range(0, 20))
			_: pos = Vector3(43, randf_range(-6, -2), randf_range(0, 20))
		rock.position = pos
		rock.rotation = Vector3(randf(), randf(), randf()) * TAU
		rock.add_to_group("fx_rock")
		add_child(rock)
		var tw := rock.create_tween().set_loops()
		tw.tween_property(rock, "position:y", pos.y + 0.6, randf_range(2.5, 4.5)).set_trans(Tween.TRANS_SINE)
		tw.tween_property(rock, "position:y", pos.y, randf_range(2.5, 4.5)).set_trans(Tween.TRANS_SINE)


func _hash(c: Vector2i) -> float:
	var h := (c.x * 73856093) ^ (c.y * 19349663)
	return float(absi(h) % 1000) / 1000.0


func _add_awning(c: Vector2i) -> void:
	var m := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(1.1, 0.35, 1.1)
	var mat := StandardMaterial3D.new()
	var cols := [Color("#a8452a"), Color("#c99a3a"), Color("#6a4a8a"), Color("#3f7a6a")]
	mat.albedo_color = cols[(c.x + c.y) % cols.size()]
	pm.material = mat
	m.mesh = pm
	m.position = Vector3(c.x + 0.5, 1.6, c.y + 0.5)
	add_child(m)
	for dx in [-0.45, 0.45]:
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 0.03
		cm.height = 1.5
		pole.mesh = cm
		pole.position = Vector3(c.x + 0.5 + dx, 0.75, c.y + 0.5 + 0.45)
		add_child(pole)


func _add_lamp(p: Vector3, color: Color, rng: float, post := false) -> void:
	if post and _place_prop("lamp", Vector3(p.x, 0.0, p.z), _hash(Vector2i(int(p.x), int(p.z))) * TAU):
		var l2 := OmniLight3D.new()
		l2.light_color = color
		l2.light_energy = 1.4
		l2.omni_range = rng
		l2.position = Vector3(p.x, 2.4, p.z)
		add_child(l2)
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.4
	light.omni_range = rng
	light.position = p
	add_child(light)
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	sm.material = mat
	bulb.mesh = sm
	bulb.add_to_group("prop3d")
	bulb.position = p
	add_child(bulb)
	if post:
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.04
		cm.bottom_radius = 0.06
		cm.height = p.y
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color("#2a201c")
		cm.material = pmat
		pole.mesh = cm
		pole.position = Vector3(p.x, p.y / 2.0, p.z)
		add_child(pole)


func _make_layer(n: String) -> MultiMeshInstance3D:
	var colors := {"reach": Color(0.35, 0.6, 0.9, 0.22), "path": Color(0.95, 0.8, 0.4, 0.55),
		"area": Color(0.6, 0.45, 0.95, 0.45), "hover": Color(1, 1, 1, 0.35)}
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.9, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colors[n]
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = n != "reach"
	pm.material = mat
	mm.mesh = pm
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position.y = 0.02 + 0.005 * layers.size()
	add_child(mmi)
	return mmi


func _draw_layer(n: String, cells: Array) -> void:
	var mm: MultiMesh = layers[n].multimesh
	mm.instance_count = cells.size()
	for i in cells.size():
		var c: Vector2i = cells[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(c.x + 0.5, 0, c.y + 0.5)))


func _clear_layers() -> void:
	for n in layers.keys():
		layers[n].multimesh.instance_count = 0


# ================================================================== aktorzy

func _spawn_actors() -> void:
	var pc := GameState.player
	player_actor = Actor.new()
	add_child(player_actor)
	player_actor.setup("player", pc.name, Color("#5fa8d3"))
	player_actor.creature = pc
	player_actor.try_load_model(["pc_" + pc.class_id + "_" + pc.species_id, "pc_" + pc.class_id, "pc"])
	var start := GameState.player_pos
	if start.x < 0:
		start = Vector2i(int(map.player_start[0]), int(map.player_start[1]))
	player_actor.place(start)
	pc.grid_pos = start
	player_actor.set_highlight(true, Color("#5fa8d3"))
	for n in map.get("npcs", []):
		if n.id in GameState.removed_npcs:
			continue
		var a := Actor.new()
		add_child(a)
		var shape := "mephit" if n.get("monster", "") == "rust_mephit" else "humanoid"
		a.setup(n.id, n.name, Color(n.get("color", "#cccccc")), shape)
		a.npc_data = n
		a.try_load_model([n.id, n.get("model", ""), n.get("monster", ""), "npc"])
		a.set_xray_color(Color(0.95, 0.82, 0.55, 0.4))
		a.place(Vector2i(int(n.pos[0]), int(n.pos[1])))
		actors[n.id] = a
	for o in map.get("objects", []):
		var a := Actor.new()
		add_child(a)
		a.is_object = true
		a.setup(o.id, o.name, Color("#7c7469"), o.get("shape", "box"))
		a.try_load_model([o.id, o.get("shape", "")], PROP_DIR, 0.0)
		a.npc_data = o
		a.place(Vector2i(int(o.pos[0]), int(o.pos[1])))
		actors[o.id] = a


func _actor_at(c: Vector2i) -> Actor:
	for a in actors.values():
		if is_instance_valid(a) and a.visible and a.cell == c:
			return a
	return null


func _occupied(except: Actor = null) -> Dictionary:
	var d := {}
	for a in actors.values():
		if is_instance_valid(a) and a.visible and a != except:
			d[a.cell] = true
	return d


func _on_state_changed() -> void:
	for lk in map.get("locks", []):
		var cell := Vector2i(int(lk.cell[0]), int(lk.cell[1]))
		grid.set_dynamic_block(cell, not GameState.has_flag(lk.unless_flag))
	for o in map.get("objects", []):
		if o.has("hide_if") and actors.has(o.id) and is_instance_valid(actors[o.id]):
			actors[o.id].visible = not GameState.has_flag(o.hide_if)
	for id_ in GameState.removed_npcs:
		if actors.has(id_) and is_instance_valid(actors[id_]) and mode != "combat":
			actors[id_].queue_free()
			actors.erase(id_)
	hud.refresh_portrait(GameState.player)
	var pend := GameState.player.pending_levels
	if pend > _last_pending:
		Audio.sfx("level_up")
		hud.show_toast(Loc.t("Awans! Kliknij „★ Awans” przy portrecie [L]"), UI.BRASS)
	_last_pending = pend


var _last_pending := 0


# ================================================================== wejście

func _connect_hud() -> void:
	hud.menu_pressed.connect(_on_menu)
	hud.dialogue_choice.connect(func(i): if dialogue: dialogue.choose(i))
	hud.action_selected.connect(_on_combat_action)
	hud.item_used.connect(_use_item)
	hud.weapon_equipped.connect(func(w):
		var pc := GameState.player
		pc.weapons.erase(w)
		pc.weapons.push_front(w)
		hud.open_inventory(pc))
	hud.end_screen_choice.connect(_on_end_choice)
	hud.level_up_chosen.connect(func(ch):
		var pc := GameState.player
		for l in Leveling.apply_level(pc, ch):
			GameState.add_log(l)
		Audio.sfx("level_up")
		hud.show_toast(Loc.t("Poziom %d!") % pc.level, UI.GOOD)
		_on_state_changed()
		if pc.pending_levels > 0:
			hud.open_level_up(pc)
		else:
			hud.close_window())


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if hud.dialogue_panel.visible:
			if ev.keycode >= KEY_1 and ev.keycode <= KEY_9:
				hud.dialogue_key(ev.keycode - KEY_0)
			return
		if hud.is_window_open():
			if ev.keycode == KEY_ESCAPE and mode != "ended":
				hud.close_window()
			return
		match ev.keycode:
			KEY_C: _on_menu("sheet")
			KEY_L: _on_menu("levelup")
			KEY_I: _on_menu("inventory")
			KEY_J: _on_menu("journal")
			KEY_R: _on_menu("rest")
			KEY_F5: _on_menu("save")
			KEY_F9: _on_menu("load")
			KEY_SPACE:
				if _player_can_act():
					_on_combat_action("end_turn", {})
			KEY_ESCAPE:
				if selected.kind != "":
					_set_selected("", {})
				else:
					_on_menu("menu")
	if hud.is_blocking():
		return
	if cam.handle_input(ev):
		return
	if ev is InputEventMouseMotion:
		_update_hover(ev.position)
	elif ev is InputEventMouseButton and ev.pressed:
		if hud.mouse_over_ui():
			return
		var cell := _cell_under(ev.position)
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if mode == "explore":
				_explore_click(cell)
			elif mode == "combat":
				_combat_click(cell)
		elif ev.button_index == MOUSE_BUTTON_RIGHT and mode == "combat":
			_set_selected("", {})


func _cell_under(screen: Vector2) -> Vector2i:
	var p = cam.ground_point(screen)
	if p == null:
		return Vector2i(-999, -999)
	return Vector2i(floori(p.x), floori(p.z))


func _on_menu(id_: String) -> void:
	if mode == "ended" and id_ != "menu":
		return
	match id_:
		"sheet": hud.open_sheet(GameState.player)
		"inventory": hud.open_inventory(GameState.player)
		"journal": hud.open_journal()
		"levelup":
			if mode == "combat":
				hud.show_toast(Loc.t("Awans po walce."), UI.BAD)
				return
			if GameState.player.pending_levels > 0:
				hud.open_level_up(GameState.player)
		"rest":
			if mode != "explore":
				hud.show_toast(Loc.t("Nie teraz!"), UI.BAD)
				return
			for l in Rest.short_rest(GameState.player):
				GameState.add_log(l)
			hud.show_toast(Loc.t("Krótki odpoczynek"))
			_on_state_changed()
		"save":
			if mode != "explore":
				hud.show_toast(Loc.t("Nie można zapisać w trakcie walki ani rozmowy."), UI.BAD)
				return
			GameState.player_pos = player_actor.cell
			if GameState.save_game("slot1"):
				hud.show_toast(Loc.t("Zapisano grę"))
		"load":
			if GameState.has_save("slot1"):
				reload_requested.emit("slot1")
		"menu":
			hud.open_end_screen(Loc.t("Pauza"), Loc.t("Zawias czeka."), [["continue", Loc.t("Wróć do gry")], ["settings", Loc.t("Ustawienia")], ["save_quit", Loc.t("Zapisz i wyjdź do menu")], ["menu", Loc.t("Wyjdź bez zapisu")]])


func _on_end_choice(id_: String) -> void:
	match id_:
		"continue":
			hud.close_window()
			if mode == "ended":
				mode = "explore"
		"settings":
			hud.open_settings()
		"save_quit":
			if mode == "explore":
				GameState.player_pos = player_actor.cell
				GameState.save_game("slot1")
			quit_to_menu.emit()
		"menu":
			quit_to_menu.emit()
		"load_auto":
			reload_requested.emit("auto")


func _use_item(item_id: String) -> void:
	var pc := GameState.player
	var d := DB.entry("items", item_id)
	if mode == "combat":
		if _player_can_act():
			_on_combat_action("action", {"id": "potion", "cost": "bonus"})
		hud.close_window()
		return
	if d.has("heal") and item_id in pc.inventory:
		pc.inventory.erase(item_id)
		var r := Dice.roll_expr(d.heal)
		var h := pc.heal(int(r.total))
		GameState.add_log(Loc.t("%s pije %s: +%d PW.") % [pc.name, d.name, h])
		player_actor.float_text("+%d" % h, UI.GOOD)
	hud.open_inventory(pc)
	_on_state_changed()


# ================================================================== eksploracja

func _explore_click(cell: Vector2i) -> void:
	if not grid.in_bounds(cell):
		return
	var target := _actor_at(cell)
	if target:
		if CombatGrid.distance(player_actor.cell, cell) <= 1 and not walking:
			_interact(target)
			return
		var best: Array[Vector2i] = []
		for n in grid.neighbors(cell) + [cell + Vector2i(1, 0), cell - Vector2i(1, 0), cell + Vector2i(0, 1), cell - Vector2i(0, 1)]:
			if n == player_actor.cell:
				best = [n]
				break
			if not grid.is_open(n) or _occupied().has(n):
				continue
			var p := grid.find_path(_walk_origin(), n, _occupied())
			if not p.is_empty() and (best.is_empty() or p.size() < best.size()):
				best = p
		if best.size() == 1 and best[0] == player_actor.cell and not walking:
			_interact(target)
			return
		if best.size() > 1:
			pending_interact = target
			_start_walk(best)
		return
	pending_interact = null
	var path := grid.find_path(_walk_origin(), cell, _occupied())
	if path.size() > 1:
		_start_walk(path)


func _walk_origin() -> Vector2i:
	return walk_queue[0] if walking and not walk_queue.is_empty() else player_actor.cell


var _walk_speed := Actor.WALK_SPEED


func _start_walk(path: Array) -> void:
	walk_queue = path.slice(1)
	_walk_speed = Actor.speed_for(walk_queue.size())
	if not walking:
		_step()


func _step() -> void:
	if walk_queue.is_empty() or mode != "explore":
		walking = false
		walk_queue.clear()
		player_actor.stop_walk()
		if pending_interact and mode == "explore":
			var t := pending_interact
			pending_interact = null
			if is_instance_valid(t) and CombatGrid.distance(player_actor.cell, t.cell) <= 1:
				_interact(t)
		return
	walking = true
	var next: Vector2i = walk_queue[0]
	if _occupied().has(next):
		walk_queue.clear()
		walking = false
		player_actor.stop_walk()
		return
	var first := not player_actor.is_walking()
	var last := walk_queue.size() == 1
	var tw := player_actor.walk_step(next, _walk_speed / grid.step_cost(next), first, last)
	tw.finished.connect(func():
		walk_queue.pop_front()
		GameState.player.grid_pos = player_actor.cell
		GameState.player_pos = player_actor.cell
		if _check_triggers(player_actor.cell):
			walking = false
			walk_queue.clear()
			pending_interact = null
			player_actor.stop_walk()
			return
		_step())


func _check_triggers(cell: Vector2i) -> bool:
	for t in map.get("triggers", []):
		for tc in t.cells:
			if Vector2i(int(tc[0]), int(tc[1])) == cell and GameState.check(t.get("if", {})):
				if t.has("encounter"):
					start_combat(t.encounter)
					return true
	return false


func _interact(a: Actor) -> void:
	var dlg: String = a.npc_data.get("dialogue", "")
	if a.is_object:
		Audio.sfx({"chest": "chest_open", "arch": "portal"}.get(a.actor_id, "ui_open"), -3.0)
	if dlg == "":
		GameState.add_log(Loc.t("%s nie zwraca na ciebie uwagi.") % a.display_name)
		return
	_open_dialogue(dlg)


## Dialog -> portret (assets/portraits/<id>.png); domyślnie id dialogu. Węzeł może nadpisać polem "portrait".
const DIALOGUE_PORTRAITS := {"backdoor": "door"}


func _open_dialogue(id_: String) -> void:
	dialogue = DialogueRunner.new(GameState)
	var pid: String = DIALOGUE_PORTRAITS.get(id_, id_)
	dialogue.node_shown.connect(func(node, choices):
		hud.show_dialogue(node.get("speaker", ""), node.get("text", ""), choices, node.get("portrait", pid)))
	dialogue.check_rolled.connect(func(text, ok):
		Audio.sfx("dice")
		GameState.add_log(text)
		hud.show_toast(Loc.t("SUKCES") if ok else Loc.t("PORAŻKA"), UI.GOOD if ok else UI.BAD))
	dialogue.finished.connect(_on_dialogue_finished)
	mode = "dialogue"
	Audio.sfx("dialogue", -6.0)
	_clear_layers()
	hud.show_tooltip("", Vector2.ZERO)
	if not dialogue.start(id_):
		_on_dialogue_finished()


func _on_dialogue_finished() -> void:
	hud.hide_dialogue()
	dialogue = null
	mode = "explore"
	_on_state_changed()
	var reqs := pending_requests.duplicate()
	pending_requests.clear()
	for r in reqs:
		_on_world_request(r)


func _on_world_request(e: Dictionary) -> void:
	if mode == "dialogue":
		pending_requests.append(e)
		return
	if e.has("start_combat"):
		start_combat(e.start_combat)
	elif e.has("end_game"):
		_show_ending(e.end_game)
	elif e.has("remove_npc"):
		if actors.has(e.remove_npc):
			actors[e.remove_npc].queue_free()
			actors.erase(e.remove_npc)


func _show_ending(kind: String) -> void:
	mode = "ended"
	Audio.play_music("ending", 2.5, false)
	Audio.set_ambient(["wind_planar"])
	if kind == "portal":
		Audio.sfx("portal")
	GameState.ending = kind
	var pc := GameState.player
	var title := Loc.t("Koniec rozdziału")
	var text := ""
	if kind == "portal":
		title = Loc.t("Drzwi, których nie było")
		text = Loc.t("Przekraczasz próg drzwi utkanych z własnej opowieści. Za twoimi plecami Rdzawy Targ cichnie, a gdzieś na pierścieniu ktoś, kogo nikt nigdy nie widział, odwraca głowę w twoją stronę.\n\nKustoszka wie.\n\n")
	else:
		title = Loc.t("Klucz wraca do domu")
		text = Loc.t("Mirela zamyka Klucz bez drzwi w gablocie, tym razem pod siedmioma zamkami. Rdzawy Targ wraca do swojego zgiełku, ale od czasu do czasu łapiesz się na tym, że patrzysz na Łuk bez drzwi i zastanawiasz się, co by było, gdyby…\n\n")
	var path := Loc.t("siłą")
	if GameState.has_flag("sever_convinced"):
		path = Loc.t("słowem")
	elif GameState.has_flag("key_stolen"):
		path = "cieniem"
	text += Loc.t("[color=#d9a85b]Klucz zdobyty %s.[/color]\n%s, poziom %d, %d PD, %d sztuk złota.\n\n[color=#a89584]Koniec wersji demonstracyjnej. Dziękujemy za grę.[/color]") % [path, pc.name, pc.level, pc.xp, pc.gold]
	hud.open_end_screen(title, text, [["continue", Loc.t("Zwiedzaj dalej")], ["menu", Loc.t("Menu główne")]])


func _update_hover(screen: Vector2) -> void:
	var cell := _cell_under(screen)
	if cell == hover_cell:
		if hud.tooltip.visible:
			hud.tooltip.position = screen + Vector2(18, 18)
		return
	hover_cell = cell
	if mode == "explore":
		var a := _actor_at(cell)
		if a:
			var title: String = a.npc_data.get("title", "")
			hud.show_tooltip(Loc.t("[b]%s[/b]%s\n[color=#a89584]Kliknij, aby porozmawiać[/color]") % [a.display_name, (", " + title) if title != "" else ""], screen)
		else:
			hud.show_tooltip("", screen)
		_draw_layer("hover", [cell] if grid.is_open(cell) else [])
	elif mode == "combat":
		_combat_hover(cell, screen)


# ================================================================== walka

func start_combat(enc_id: String) -> void:
	if mode == "combat":
		return
	var enc := DB.entry("encounters", enc_id)
	if not enc.is_empty():
		Audio.play_music("combat", 0.8)
	if enc.is_empty():
		push_error("Brak spotkania " + enc_id)
		return
	walking = false
	walk_queue.clear()
	pending_interact = null
	GameState.player_pos = player_actor.cell
	GameState.save_game("auto")
	encounter_id = enc_id
	for f in enc.get("unlock", []):
		GameState.flags[f] = true
	_on_state_changed()
	var pc := GameState.player
	pc.grid_pos = player_actor.cell
	var enemies: Array = []
	for s in enc.get("spawn", []):
		var m := CharacterBuilder.create_monster(s.monster, s.id, s.get("name", ""))
		m.grid_pos = Vector2i(int(s.pos[0]), int(s.pos[1]))
		var a := Actor.new()
		add_child(a)
		a.setup(m.id, m.name, Color("#b04a3a"), "mephit" if s.monster == "rust_mephit" else "humanoid")
		a.creature = m
		a.try_load_model([s.id, s.monster, "npc"])
		a.set_xray_color(Color(1.0, 0.35, 0.3, 0.55))
		a.place(m.grid_pos)
		actors[m.id] = a
		enemies.append(m)
	for id_ in actors.keys():
		var a: Actor = actors[id_]
		if not is_instance_valid(a) or a.npc_data.get("encounter", "") != enc_id:
			continue
		if a.npc_data.get("flees", false):
			GameState.add_log(Loc.t("%s cofa się w pęknięcie rzeczywistości i znika!") % a.display_name)
			a.die()
			actors.erase(id_)
			if not id_ in GameState.removed_npcs:
				GameState.removed_npcs.append(id_)
			continue
		if a.npc_data.has("monster"):
			var m := CharacterBuilder.create_monster(a.npc_data.monster, id_, a.display_name)
			m.grid_pos = a.cell
			a.creature = m
			enemies.append(m)
	# Postacie niebiorące udziału blokują pola
	var combatant_ids := enemies.map(func(e): return e.id)
	for a in actors.values():
		if is_instance_valid(a) and a.visible and not a.actor_id in combatant_ids:
			grid.set_dynamic_block(a.cell, true)
	for e in enemies:
		actors[e.id].show_hp(true)
		actors[e.id].set_highlight(true, UI.BAD)
	player_actor.show_hp(true)
	var surprised := enc.has("surprise_unless_flag") and not GameState.has_flag(enc.surprise_unless_flag)
	if enc.has("intro"):
		GameState.add_log(enc.intro)
	hud.show_toast(enc.get("name", Loc.t("Walka!")), UI.BAD)
	mode = "combat"
	_clear_layers()
	hud.show_tooltip("", Vector2.ZERO)
	hud.show_combat(true)
	combat = CombatManager.new(grid)
	combat.event.connect(_on_combat_event)
	combat.start([pc], enemies, surprised)


func _on_combat_event(e: Dictionary) -> void:
	event_queue.append(e)
	if not processing:
		_process_events()


func _process_events() -> void:
	processing = true
	while not event_queue.is_empty():
		var e: Dictionary = event_queue.pop_front()
		await _play_event(e)
		if not is_inside_tree():
			return
	processing = false
	_after_events()


func _actor_for(id_: String) -> Actor:
	if id_ == "player" or (GameState.player and id_ == GameState.player.id):
		return player_actor
	var a = actors.get(id_, null)
	return a if is_instance_valid(a) else null


func _play_event(e: Dictionary) -> void:
	match e.type:
		"log":
			GameState.add_log(e.text)
		"initiative":
			hud.set_turn_order(combat.order, "", combat.round_num)
		"turn":
			hud.set_turn_order(combat.order, e.id, int(e.round))
			var a := _actor_for(e.id)
			if a:
				cam.follow = a
			if not e.player:
				hud.build_combat_bar(combat, GameState.player, false)
				await get_tree().create_timer(0.35).timeout
		"move":
			var a := _actor_for(e.id)
			if a:
				var tw := a.walk(e.path, Actor.RUN_SPEED)
				await tw.finished
		"attack":
			var a := _actor_for(e.id)
			var t := _actor_for(e.target)
			if a and t:
				var hit: bool = e.get("hit", false)
				if e.get("ranged", false):
					Audio.sfx("miss", -6.0)
					await _projectile(a.position, t.position, Color("#e8d8b0"))
					Audio.sfx("hit_flesh" if hit else "miss", 0.0 if hit else -4.0)
				else:
					Audio.sfx("sword_swing", -3.0)
					await a.lunge(t.position).finished
					Audio.sfx("sword_hit" if hit else "miss", 0.0 if hit else -3.0)
		"spell":
			var a := _actor_for(e.id)
			var cell := Vector2i(int(e.cell[0]), int(e.cell[1]))
			var sp := Spellcasting.spell(e.spell)
			var col := UI.PLANAR
			match sp.get("damage_type", ""):
				"fire": col = Color("#ff7a2a")
				"cold": col = Color("#8ad8ff")
				"radiant": col = Color("#fff2a8")
				"force": col = Color("#c9a0ff")
				"necrotic": col = Color("#5a8a4a")
			if sp.type in ["heal", "buff"]:
				col = UI.GOOD
			if a:
				a.play_anim("cast", "attack")
				Audio.spell(sp)
				await _projectile(a.position, Actor.cell_to_world(cell), col)
		"hp":
			var a := _actor_for(e.id)
			if a:
				a.update_hp(int(e.hp), int(e.max))
				if int(e.amount) > 0:
					Audio.sfx("hit_flesh", -5.0)
					a.float_text("-%d" % int(e.amount), UI.BAD)
					a.flash(Color(1, 0.3, 0.2))
					await get_tree().create_timer(0.25).timeout
			if a == player_actor:
				hud.refresh_portrait(GameState.player)
		"heal":
			var a := _actor_for(e.id)
			if a:
				a.float_text("+%d" % int(e.amount), UI.GOOD)
		"death":
			Audio.sfx("death")
			var a := _actor_for(e.id)
			if a and a != player_actor:
				actors.erase(e.id)
				a.die()
				await get_tree().create_timer(0.3).timeout
			elif a:
				a.set_downed(true)
		"condition":
			var a := _actor_for(e.id)
			var c: Creature = a.creature if a else null
			if a and c and not c.dead:
				a.set_downed(not c.is_conscious() or c.has_condition("prone"))
			if a == player_actor:
				hud.refresh_portrait(GameState.player)
		"end":
			await get_tree().create_timer(0.6).timeout
			_finish_combat(e.victory, int(e.xp))


func _projectile(from: Vector3, to: Vector3, color: Color) -> Signal:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	sm.material = mat
	m.mesh = sm
	add_child(m)
	m.position = from + Vector3(0, 1.1, 0)
	var tw := create_tween()
	tw.tween_property(m, "position", to + Vector3(0, 0.9, 0), clampf(from.distance_to(to) * 0.04, 0.15, 0.45))
	tw.tween_callback(m.queue_free)
	return tw.finished


func _player_can_act() -> bool:
	return mode == "combat" and combat != null and combat.active and not processing \
		and combat.current() == GameState.player


func _after_events() -> void:
	if mode != "combat" or combat == null:
		return
	if _player_can_act():
		hud.build_combat_bar(combat, GameState.player, true)
		cam.follow = player_actor
		_refresh_combat_overlay()
	hud.refresh_portrait(GameState.player)


func _set_selected(kind: String, data: Dictionary) -> void:
	selected = {"kind": kind, "data": data}
	if kind == "":
		hud._select("")
	_refresh_combat_overlay()


func _refresh_combat_overlay() -> void:
	_clear_layers()
	if not _player_can_act():
		hud.set_hint("")
		return
	var pc := GameState.player
	match selected.kind:
		"":
			var reach := combat.reachable_for(pc)
			var cells := reach.keys().filter(func(k): return k is Vector2i and k != pc.grid_pos)
			_draw_layer("reach", cells)
			hud.set_hint(Loc.t("Kliknij pole, żeby się ruszyć, albo wroga, żeby zaatakować. Spacja kończy turę."))
		"attack":
			hud.set_hint(Loc.t("Wybierz cel ataku: %s (PPM anuluje)") % selected.data.name)
		"spell":
			var sp := Spellcasting.spell(selected.data.id)
			hud.set_hint(Loc.t("Wybierz cel czaru: %s, zasięg %s m (PPM anuluje)") % [sp.name, str(int(sp.get("range", 1)) * 1.5)])
		"target_action":
			hud.set_hint(Loc.t("Wybierz cel: %s") % selected.data.name)
	if hover_cell.x > -999:
		_combat_hover(hover_cell, get_viewport().get_mouse_position())


func _on_combat_action(kind: String, data: Dictionary) -> void:
	if not _player_can_act():
		return
	var pc := GameState.player
	match kind:
		"end_turn":
			_set_selected("", {})
			_clear_layers()
			hud.build_combat_bar(combat, pc, false)
			combat.end_turn()
		"attack":
			_set_selected("attack", data)
		"spell":
			var sp := Spellcasting.spell(data.id)
			if sp.get("target", "") == "self":
				_report(combat.cast(pc, data.id, pc.grid_pos))
			else:
				_set_selected("spell", data)
		"action":
			if data.id == "divine_spark":
				_set_selected("target_action", data)
				return
			_report(combat.do_action(pc, data.id))
			_set_selected("", {})


func _report(err: String) -> void:
	if err != "":
		hud.show_toast(err, UI.BAD)
	elif not processing:
		_after_events()


func _combat_click(cell: Vector2i) -> void:
	if not _player_can_act():
		return
	var pc := GameState.player
	var target := combat.creature_at(cell)
	match selected.kind:
		"attack":
			_report(combat.attack(pc, selected.data, target))
			_set_selected("", {})
		"spell":
			_report(combat.cast(pc, selected.data.id, cell))
			_set_selected("", {})
		"target_action":
			_report(combat.do_action(pc, selected.data.id, target))
			_set_selected("", {})
		_:
			if target and target.is_hostile_to(pc):
				var opt := _default_attack(pc, target)
				if opt.is_empty():
					hud.show_toast(Loc.t("Cel poza zasięgiem"), UI.BAD)
				else:
					_report(combat.attack(pc, opt, target))
			elif target == null:
				_report(combat.move(pc, cell))


func _default_attack(pc: Creature, target: Creature) -> Dictionary:
	var dist := CombatGrid.distance(pc.grid_pos, target.grid_pos)
	var best := {}
	for o in Attack.options(pc):
		if combat.can_attack(pc, o, target) != "":
			continue
		if best.is_empty() or (dist <= 1 and not o.ranged and best.ranged) or (dist > 1 and o.ranged):
			best = o
	return best


func _combat_hover(cell: Vector2i, screen: Vector2) -> void:
	if not _player_can_act():
		hud.show_tooltip("", screen)
		return
	var pc := GameState.player
	var target := combat.creature_at(cell)
	_draw_layer("path", [])
	_draw_layer("area", [])
	_draw_layer("hover", [cell] if grid.in_bounds(cell) else [])
	if selected.kind == "spell":
		var sp := Spellcasting.spell(selected.data.id)
		if sp.has("area"):
			var cells := []
			var area: Dictionary = sp.area
			for y in range(cell.y - 3, cell.y + 4):
				for x in range(cell.x - 3, cell.x + 4):
					var p := Vector2i(x, y)
					if not grid.is_open(p):
						continue
					if area.shape == "sphere" and CombatGrid.distance(p, cell) <= int(area.radius):
						cells.append(p)
			if area.shape == "cone":
				var dir := Vector2(cell - pc.grid_pos).normalized()
				for y in range(pc.grid_pos.y - 3, pc.grid_pos.y + 4):
					for x in range(pc.grid_pos.x - 3, pc.grid_pos.x + 4):
						var p := Vector2i(x, y)
						var d := CombatGrid.distance(pc.grid_pos, p)
						if d >= 1 and d <= int(area.length) and grid.is_open(p) and dir.dot(Vector2(p - pc.grid_pos).normalized()) >= 0.7:
							cells.append(p)
			_draw_layer("area", cells)
		var err := combat.can_cast(pc, selected.data.id, cell)
		var tgt_txt := ""
		for t in combat.spell_targets(pc, selected.data.id, cell):
			tgt_txt += Loc.t("\n• %s (%d/%d PW)") % [t.name, t.hp, t.max_hp]
		hud.show_tooltip("[b]%s[/b]%s%s" % [sp.name, ("\n[color=#e0634f]%s[/color]" % err) if err != "" else "", tgt_txt], screen)
		return
	if target and target != pc:
		var opt: Dictionary = selected.data if selected.kind == "attack" else _default_attack(pc, target)
		var s := Loc.t("[b]%s[/b]\nPW %d/%d   KP %d") % [target.name, target.hp, target.max_hp, target.ac()]
		var conds := target.conditions.keys().map(func(k): return DB.entry("conditions", k).get("name", k))
		if not conds.is_empty():
			s += "\n[color=#e0634f]%s[/color]" % ", ".join(conds)
		if target.is_hostile_to(pc):
			if opt.is_empty():
				s += Loc.t("\n[color=#e0634f]Poza zasięgiem[/color]")
			else:
				var err := combat.can_attack(pc, opt, target)
				if err != "":
					s += "\n[color=#e0634f]%s[/color]" % err
				else:
					s += Loc.t("\n%s: szansa trafienia [b]%d%%[/b]") % [opt.name, roundi(combat.hit_chance(pc, opt, target) * 100)]
		hud.show_tooltip(s, screen)
		return
	if selected.kind == "":
		var reach := combat.reachable_for(pc)
		if reach.has(cell) and cell != pc.grid_pos:
			var path := CombatGrid.path_to(reach, pc.grid_pos, cell)
			_draw_layer("path", path.slice(1))
			var warn := ""
			for h in combat.hostiles_of(pc):
				if h.can_act() and not combat.turn.get("disengaged", false):
					for i in range(path.size() - 1):
						if CombatGrid.distance(h.grid_pos, path[i]) <= 1 and CombatGrid.distance(h.grid_pos, path[i + 1]) > 1:
							warn = Loc.t("\n[color=#e0634f]Sprowokujesz atak okazyjny![/color]")
			hud.show_tooltip(Loc.t("Ruch: %s m%s") % [str(int(reach[cell].cost) * 1.5), warn], screen)
			return
	hud.show_tooltip("", screen)


func _finish_combat(victory: bool, xp: int) -> void:
	hud.show_combat(false)
	_clear_layers()
	player_actor.show_hp(false)
	var enc := DB.entry("encounters", encounter_id)
	var pc := GameState.player
	for e in combat.combatants:
		if e.team == "enemy":
			var a := _actor_for(e.id)
			if a and not e.dead:
				a.die()
			actors.erase(e.id)
			if not e.id in GameState.removed_npcs:
				GameState.removed_npcs.append(e.id)
	# Odblokuj pola po walce
	for a in actors.values():
		if is_instance_valid(a):
			grid.set_dynamic_block(a.cell, false)
	pc.effects.clear()
	pc.concentration = ""
	for k in ["prone", "blinded"]:
		pc.conditions.erase(k)
	combat = null
	Audio.play_music("explore", 2.5)
	if victory:
		mode = "explore"
		hud.show_toast(Loc.t("Zwycięstwo!"), UI.GOOD)
		var effects: Array = [{"xp": xp}]
		effects.append_array(enc.get("on_victory", []))
		GameState.apply_effects(effects)
		cam.follow = player_actor
	else:
		mode = "ended"
		player_actor.set_downed(true)
		hud.open_end_screen(Loc.t("Porażka"), Loc.t("Ciemność. Rdza. Cisza.\n\nZawias nie wybacza, ale pamięta, gdzie byłeś chwilę temu."),
			[["load_auto", Loc.t("Wczytaj autozapis")], ["menu", Loc.t("Menu główne")]])
	_on_state_changed()
