# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name Actor
extends Node3D
## Wizualna reprezentacja postaci na mapie: low-poly figura, podpis, pierścień zaznaczenia.

var actor_id := ""
var display_name := ""
var cell := Vector2i.ZERO
var creature: Creature
var npc_data := {}
var is_object := false
var base_color := Color.WHITE

var _body: MeshInstance3D
var _ring: MeshInstance3D
var _label: Label3D
var _hp_label: Label3D
var _mat: StandardMaterial3D
var _bob_t := randf() * TAU
var _idle_root: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _dead := false

const MODEL_DIR := "res://assets/actors/"
const MODEL_HEIGHT := 1.75
const LOOPING := ["idle", "walk", "run", "talk"]
## Ruch: prędkości w m/s (pole = 1 m). Naturalna prędkość animacji zmierzona narzędziem
## tools/dev/measure_gait.gd (stopa podporowa względem modelu 1,75 m) – tempo animacji dopasowujemy
## do prędkości ruchu, żeby stopy nie ślizgały się po ziemi.
const WALK_SPEED := 1.3
const RUN_SPEED := 4.0
const RUN_MIN_CELLS := 4          # krótsze przejścia spacerem, dłuższe truchtem
static var gait_natural := {"walk": 1.05, "run": 5.1}
const TURN_RATE := 14.0           # szybkość dochodzenia do kierunku (1/s)
var _yaw_target := NAN
var _gait := ""
var _last_pos := Vector3.ZERO
var _vel := 0.0                   # wygładzona rzeczywista prędkość (m/s)
var _step_phase := 0.0
## Fazy cyklu chodu, w których pięta uderza o ziemię (walk i run z UAL, zmierzone measure_gait.gd).
const FOOTFALLS := [0.0, 0.5]
const MEPHIT_HEIGHT := 0.8        # mefit: mały, lata (model bez szkieletu, animacja proceduralna)
const MEPHIT_HOVER := 0.5
var shape := "humanoid"
var _model_base_pos := Vector3.ZERO
var _model_base_scale := Vector3.ONE
const XRAY_SHADER := preload("res://shaders/xray.gdshader")
var _xray: ShaderMaterial              # sylwetka za przeszkodą (postacie, nie obiekty)


static func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, 0.0, c.y + 0.5)


func setup(id_: String, name_: String, color: Color, shape := "humanoid") -> void:
	actor_id = id_
	self.shape = shape
	display_name = name_
	base_color = color
	_idle_root = Node3D.new()
	add_child(_idle_root)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = color
	_mat.roughness = 0.75
	match shape:
		"arch":
			_build_arch()
		"door":
			_build_box(Vector3(0.9, 1.6, 0.25), Color("#4a3a2c"))
		"chest":
			_build_box(Vector3(0.7, 0.45, 0.5), Color("#6d4523"))
		"mephit":
			_build_mephit()
		_:
			_build_humanoid()
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.36
	tm.outer_radius = 0.42
	tm.rings = 24
	_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(1, 1, 1, 0.9)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = rm
	_ring.position.y = 0.03
	_ring.scale = Vector3(1, 0.2, 1)
	add_child(_ring)
	_ring.visible = false

	_label = Label3D.new()
	_label.text = name_
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.pixel_size = 0.006
	_label.outline_size = 10
	_label.modulate = Color("#eadbc8")
	_label.position.y = 2.0 if shape != "arch" else 3.3
	_label.no_depth_test = true
	add_child(_label)
	_hp_label = Label3D.new()
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.font_size = 34
	_hp_label.pixel_size = 0.006
	_hp_label.outline_size = 8
	_hp_label.position.y = 2.28
	_hp_label.no_depth_test = true
	_hp_label.visible = false
	add_child(_hp_label)
	if shape in ["humanoid", "mephit", "chest", "door"]:
		_xray = ShaderMaterial.new()
		_xray.shader = XRAY_SHADER
		if shape in ["chest", "door"]:
			_xray.set_shader_parameter("color", Color(0.85, 0.75, 0.6, 0.35))
		_apply_xray()


func _build_humanoid() -> void:
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.25
	cap.height = 1.1
	body.mesh = cap
	body.material_override = _mat
	body.position.y = 0.62
	_idle_root.add_child(body)
	_body = body
	# płaszcz (stożek)
	var cloak := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.18
	cone.bottom_radius = 0.36
	cone.height = 0.8
	cloak.mesh = cone
	var cm := StandardMaterial3D.new()
	cm.albedo_color = base_color.darkened(0.45)
	cloak.material_override = cm
	cloak.position.y = 0.42
	_idle_root.add_child(cloak)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.2
	sph.height = 0.4
	head.mesh = sph
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color("#d8b89a").lerp(base_color, 0.25)
	head.material_override = hm
	head.position.y = 1.38
	_idle_root.add_child(head)


func _build_mephit() -> void:
	var body := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.3
	sph.height = 0.55
	body.mesh = sph
	body.material_override = _mat
	body.position.y = 1.1
	_idle_root.add_child(body)
	_body = body
	for side in [-1, 1]:
		var wing := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.5, 0.35, 0.05)
		wing.mesh = pm
		var wm := StandardMaterial3D.new()
		wm.albedo_color = base_color.darkened(0.3)
		wing.material_override = wm
		wing.position = Vector3(0.35 * side, 1.2, 0)
		wing.rotation.z = -0.6 * side
		_idle_root.add_child(wing)


func _build_box(sz: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	m.position.y = sz.y / 2.0
	_idle_root.add_child(m)
	_body = m


func _build_arch() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#7c7469")
	stone.roughness = 0.95
	for side in [-1, 1]:
		var pillar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 2.6, 0.45)
		pillar.mesh = bm
		pillar.material_override = stone
		pillar.position = Vector3(0.75 * side, 1.3, 0)
		_idle_root.add_child(pillar)
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.9, 0.4, 0.5)
	top.mesh = tm
	top.material_override = stone
	top.position.y = 2.8
	_idle_root.add_child(top)
	# migotanie pod łukiem
	var veil := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.15, 2.5)
	veil.mesh = qm
	var vm := StandardMaterial3D.new()
	vm.albedo_color = Color(UI.PLANAR, 0.18)
	vm.emission_enabled = true
	vm.emission = UI.PLANAR
	vm.emission_energy_multiplier = 0.6
	vm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vm.cull_mode = BaseMaterial3D.CULL_DISABLED
	veil.material_override = vm
	veil.position.y = 1.3
	_idle_root.add_child(veil)
	_body = veil


# ------------------------------------------------------------------ modele GLB

## Szuka modelu wg listy id (np. ["mirela", "pc_wizard", "pc"]) i podmienia nim figurę zastępczą.
## dir: katalog modeli; height <= 0 zostawia rzeczywistą skalę modelu (rekwizyty).
## Pierwszy istniejący plik modelu z listy id ("" gdy żaden). Wspólne dla gry i testu assetów.
static func resolve_model(ids: Array, dir: String = MODEL_DIR) -> String:
	for id_ in ids:
		if id_ == null or str(id_) == "":
			continue
		var candidate := dir + str(id_) + ".glb"
		if ResourceLoader.exists(candidate):
			return candidate
	return ""


func try_load_model(ids: Array, dir: String = MODEL_DIR, height: float = MODEL_HEIGHT) -> bool:
	var path := resolve_model(ids, dir)
	if path == "":
		push_warning("Actor %s: brak modelu dla %s w %s, zostaje figura zastępcza" % [actor_id, ids, dir])
		return false
	if shape == "mephit" and height == MODEL_HEIGHT:
		height = MEPHIT_HEIGHT
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Actor %s: model %s istnieje, ale nie da się go wczytać (brakująca tekstura?)" % [actor_id, path])
		return false
	for ch in _idle_root.get_children():
		ch.queue_free()
	_model = scene.instantiate()
	_idle_root.add_child(_model)
	var aabb := _model_aabb(_model)
	if aabb.size.y > 0.01:
		var k := height / aabb.size.y if height > 0.0 else 1.0
		_model.scale = Vector3.ONE * k
		_model.position = Vector3(-aabb.get_center().x * k, -aabb.position.y * k, -aabb.get_center().z * k)
	_model_base_pos = _model.position
	_model_base_scale = _model.scale
	_anim = _find_anim_player(_model)
	if _anim:
		for lib_name in _anim.get_animation_library_list():
			var lib := _anim.get_animation_library(lib_name)
			for an in lib.get_animation_list():
				if an.to_lower() in LOOPING:
					lib.get_animation(an).loop_mode = Animation.LOOP_LINEAR
		_anim.animation_finished.connect(_on_anim_finished)
		play_anim("idle")
	_mat = null
	_apply_xray()
	return true


## Kolor sylwetki widocznej za ścianami (gracz/drużyna niebieski, wrogowie czerwony).
func set_xray_color(c: Color) -> void:
	if _xray:
		_xray.set_shader_parameter("color", c)


func _apply_xray() -> void:
	if _xray == null:
		return
	var stack: Array[Node] = [_idle_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_overlay = _xray
		stack.append_array(n.get_children())


func hide_labels() -> void:
	_label.visible = false
	_hp_label.visible = false
	if _ring:
		_ring.visible = false


func has_model() -> bool:
	return _model != null


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for ch in n.get_children():
		var r := _find_anim_player(ch)
		if r:
			return r
	return null


func _model_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh:
			var rel: Transform3D = root.global_transform.affine_inverse() * n.global_transform if root.is_inside_tree() else _rel_transform(root, n)
			var box: AABB = rel * n.get_aabb()
			out = box if first else out.merge(box)
			first = false
		stack.append_array(n.get_children())
	return out


func _rel_transform(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _anim_name(wanted: String) -> String:
	if _anim == null:
		return ""
	for an in _anim.get_animation_list():
		var short := String(an).get_slice("/", String(an).get_slice_count("/") - 1).to_lower()
		if short == wanted:
			return an
	return ""


## Odtwarza animację modelu, jeśli istnieje. Zwraca true przy sukcesie.
func play_anim(wanted: String, fallback := "") -> bool:
	if _anim == null or (_dead and wanted != "death"):
		return false
	var an := _anim_name(wanted)
	if an == "" and fallback != "":
		an = _anim_name(fallback)
	if an == "":
		return false
	_anim.play(an, 0.15)
	return true


func _on_anim_finished(an: StringName) -> void:
	var short := String(an).get_slice("/", String(an).get_slice_count("/") - 1).to_lower()
	if short == "death" or _dead:
		return
	if not short in LOOPING:
		play_anim("idle")


func _process(delta: float) -> void:
	# tempo chodu z rzeczywistej prędkości: łagodny start/stop i trudny teren bez ślizgania stóp
	if delta > 0.0:
		var inst := Vector2(position.x - _last_pos.x, position.z - _last_pos.z).length() / delta
		_vel = lerpf(_vel, inst, 1.0 - exp(-delta * 20.0))
	_last_pos = position
	if _anim and _gait != "":
		_anim.speed_scale = clampf(_vel / float(gait_natural[_gait]), 0.35, 2.5)
		_footsteps()
	if _idle_root and not is_nan(_yaw_target):
		_idle_root.rotation.y = lerp_angle(_idle_root.rotation.y, _yaw_target, 1.0 - exp(-delta * TURN_RATE))
	_bob_t += delta * 2.0
	if shape == "mephit" and _model and not _dead:
		# lot: unoszenie, kołysanie i trzepot skrzydeł (szybkie, drobne skalowanie)
		_model.position = _model_base_pos + Vector3(0, MEPHIT_HOVER + sin(_bob_t * 1.3) * 0.08, 0)
		_model.rotation.z = sin(_bob_t * 0.65) * 0.1
		_model.rotation.x = 0.15 + sin(_bob_t * 0.9) * 0.05
		_model.scale = _model_base_scale * Vector3(1.0 + sin(_bob_t * 11.0) * 0.035, 1.0 - sin(_bob_t * 11.0) * 0.02, 1.0)
	if _idle_root and not is_object and _model == null:
		_idle_root.position.y = sin(_bob_t) * 0.02
	if _ring and _ring.visible:
		_ring.rotation.y += delta


func place(c: Vector2i) -> void:
	cell = c
	position = cell_to_world(c)
	_last_pos = position


## Mgła wojny (FogOfWar): ukrywa model i podpis, aktor zostaje w świecie (klik, trasa, mapa).
var fogged := false


func set_fogged(on: bool) -> void:
	if on == fogged:
		return
	fogged = on
	_idle_root.visible = not on
	_label.visible = not on and not _dead


func set_highlight(on: bool, color := Color.WHITE) -> void:
	_ring.visible = on
	(_ring.material_override as StandardMaterial3D).albedo_color = color


func show_hp(on: bool) -> void:
	_hp_label.visible = on and creature != null
	update_hp()


func update_hp(hp := -1, max_hp := -1) -> void:
	if creature == null:
		return
	if hp < 0:
		hp = creature.hp
		max_hp = creature.max_hp
	_hp_label.text = "%d/%d" % [hp, max_hp]
	var ratio := float(hp) / maxf(1.0, max_hp)
	_hp_label.modulate = UI.GOOD.lerp(UI.BAD, 1.0 - ratio)


## Prędkość dla ścieżki o tylu polach (krótka: spacer, długa: trucht).
static func speed_for(cells: int) -> float:
	return RUN_SPEED if cells >= RUN_MIN_CELLS else WALK_SPEED


## Cała ścieżka jednym ciągłym ruchem (walka, NPC). speed < 0: dobór wg długości.
func walk(path: Array, speed := -1.0) -> Tween:
	var tw := create_tween()
	if path.size() < 2:
		tw.tween_interval(0.01)
		return tw
	if speed < 0.0:
		speed = speed_for(path.size() - 1)
	var prev := position
	for i in range(1, path.size()):
		var target := cell_to_world(path[i])
		_tween_segment(tw, prev, target, speed, i == 1, i == path.size() - 1)
		prev = target
	cell = path[path.size() - 1]
	tw.finished.connect(stop_walk)
	return tw


## Jeden krok (eksploracja: świat sprawdza pułapki i zajętość pole po polu). Animacja się nie urywa
## między krokami; first/last dają łagodny start i zatrzymanie, stop_walk() kończy chód.
func walk_step(c: Vector2i, speed: float, first := false, last := false) -> Tween:
	var tw := create_tween()
	_tween_segment(tw, position, cell_to_world(c), speed, first, last)
	cell = c
	return tw


func _tween_segment(tw: Tween, from: Vector3, target: Vector3, speed: float, first: bool, last: bool) -> void:
	var dist := from.distance_to(target)
	var dur := dist / maxf(speed, 0.1)
	tw.tween_callback(func():
		_face(target)
		_set_gait(speed))
	var pt := tw.tween_property(self, "position", target, dur * (1.25 if first or last else 1.0))
	if first and last:
		pt.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif first:
		pt.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	elif last:
		pt.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Chód/trucht z tempem animacji dopasowanym do prędkości ruchu.
func _set_gait(speed: float) -> void:
	if _anim == null or _dead:
		return
	var g := "run" if speed > (WALK_SPEED + RUN_SPEED) / 2.0 and _anim_name("run") != "" else "walk"
	var an := _anim_name(g)
	if an == "":
		return
	if _anim.current_animation != an:
		_anim.play(an, 0.2)
	_gait = g


## Dźwięk kroku przy przejściu fazy animacji przez moment kontaktu stopy.
func _footsteps() -> void:
	var length := _anim.current_animation_length
	if length <= 0.0 or _vel < 0.3:
		return
	var ph := fmod(_anim.current_animation_position / length, 1.0)
	var prev := _step_phase
	for f in FOOTFALLS:
		# przejście przez fazę f od poprzedniej klatki (z zawinięciem cyklu 1 -> 0)
		var crossed: bool = (prev < f and f <= ph) if ph >= prev else (f > prev or f <= ph)
		if crossed:
			UI.play_sfx("step_stone", -4.0 if creature and creature.is_player else -12.0)
	_step_phase = ph


func stop_walk() -> void:
	if _anim == null or _gait == "":
		return
	_gait = ""
	_anim.speed_scale = 1.0
	if not _dead:
		_anim.play(_anim_name("idle"), 0.25)


func is_walking() -> bool:
	return _gait != ""


var _voice3d: AudioStreamPlayer3D
var _bark_until := 0.0


## Okrzyk: głos z pozycji postaci (animacja mówienia na czas nagrania). Zwraca, jak długo pokazywać dymek (s);
## sam dymek rysuje HUD (HUD.bubble), żeby był czytelny na każdym tle.
func say(text: String, voice_path := "") -> float:
	var dur := 0.0
	if voice_path != "" and ResourceLoader.exists(voice_path):
		if _voice3d == null:
			_voice3d = AudioStreamPlayer3D.new()
			_voice3d.bus = "Voice"
			_voice3d.unit_size = 6.0
			_voice3d.max_distance = 30.0
			_voice3d.position.y = 1.5
			add_child(_voice3d)
		var st: AudioStream = load(voice_path)
		_voice3d.stream = st
		_voice3d.play()
		dur = st.get_length()
		set_talking(true)
		get_tree().create_timer(dur).timeout.connect(func(): if is_instance_valid(self): set_talking(false))
	var show := maxf(2.0 + text.length() * 0.05, dur + 0.6)
	_bark_until = Time.get_ticks_msec() / 1000.0 + show
	return show


## Przerywa okrzyk (np. kiedy zaczyna się rozmowa albo walka).
func hush() -> void:
	_bark_until = 0.0
	if _voice3d and _voice3d.playing:
		_voice3d.stop()
		set_talking(false)


func is_barking() -> bool:
	return (_voice3d != null and _voice3d.playing) or Time.get_ticks_msec() / 1000.0 < _bark_until


## Rozmowa: animacja „talk”, póki postać mówi (głos), potem powrót do bezczynności.
func set_talking(on: bool) -> void:
	if _anim == null or _dead or is_walking():
		return
	var cur := String(_anim.current_animation).get_slice("/", String(_anim.current_animation).get_slice_count("/") - 1).to_lower()
	if on and cur != "talk":
		play_anim("talk", "idle")
	elif not on and cur == "talk":
		play_anim("idle")


## Obraca postać twarzą do punktu (np. rozmówcy).
func face_toward(target: Vector3) -> void:
	_face(target)


## Ustawia kierunek, do którego postać płynnie się obraca (_process).
func _face(target: Vector3) -> void:
	var d := target - position
	if d.length() > 0.01:
		_yaw_target = atan2(d.x, d.z)


func lunge(toward: Vector3) -> Tween:
	var dir := (toward - position)
	dir.y = 0
	dir = dir.normalized() * 0.35
	_face(toward)
	if play_anim("attack"):
		var t2 := create_tween()
		t2.tween_interval(0.35)
		return t2
	var tw := create_tween()
	var base := _idle_root.position
	tw.tween_property(_idle_root, "position", base + dir, 0.09)
	tw.tween_property(_idle_root, "position", base, 0.14)
	return tw


func flash(color: Color) -> void:
	play_anim("hit")
	if _mat == null:
		return
	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color", color, 0.06)
	tw.tween_property(_mat, "albedo_color", base_color, 0.25)


func float_text(text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 64
	l.pixel_size = 0.006
	l.outline_size = 12
	l.modulate = color
	l.no_depth_test = true
	l.position = Vector3(randf_range(-0.2, 0.2), 1.8, 0)
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", 2.8, 1.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


func set_downed(down: bool) -> void:
	if _model:
		if down:
			_dead = false
			play_anim("death")
			_dead = true
		else:
			_dead = false
			play_anim("idle")
		return
	var tw := create_tween()
	tw.tween_property(_idle_root, "rotation:x", -PI / 2.2 if down else 0.0, 0.3)
	tw.parallel().tween_property(_idle_root, "position:y", 0.2 if down else 0.0, 0.3)


func die() -> Tween:
	set_downed(true)
	_label.visible = false
	_hp_label.visible = false
	var tw := create_tween()
	if _model:
		tw.tween_interval(2.5)
	tw.tween_interval(0.5)
	tw.tween_property(self, "scale", Vector3(1, 0.05, 1), 0.6)
	tw.tween_callback(queue_free)
	return tw
