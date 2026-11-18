class_name IsoCamera
extends Node3D
## Kamera izometryczna (ortogonalna): obrót co 90° (Q/E), zoom kółkiem, przesuwanie WASD/strzałkami.

var cam: Camera3D
var target_pos := Vector3.ZERO
var follow: Node3D
var yaw_index := 0
var _yaw := deg_to_rad(45.0)
var zoom := 16.0
var yaw_locked := false
var yaw_offset := 0.0            # dodatkowy obrót w stopniach (debug/test)
# Tryb malowany: kadr nie może wyjechać poza malunek (środek projektora i połowa jego wymiarów w metrach).
var paint_center := Vector3.ZERO
var paint_half := Vector2.ZERO
const PITCH := -35.264
const DIST := 40.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = zoom
	cam.near = 0.1
	cam.far = 200.0
	add_child(cam)
	cam.current = true
	_apply()


func _apply() -> void:
	rotation = Vector3(deg_to_rad(PITCH), _yaw, 0)
	cam.position = Vector3(0, 0, DIST)
	cam.size = zoom


func snap_to(p: Vector3) -> void:
	target_pos = p
	position = p


func _process(delta: float) -> void:
	var pan := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1
	if pan != Vector3.ZERO:
		follow = null
		target_pos += pan.rotated(Vector3.UP, _yaw).normalized() * delta * zoom * 1.1
	elif follow and is_instance_valid(follow):
		target_pos = follow.global_position
	position = position.lerp(target_pos, clampf(delta * 6.0, 0.0, 1.0))
	var want_yaw := deg_to_rad(45.0 + 90.0 * yaw_index + yaw_offset)
	_yaw = lerp_angle(_yaw, want_yaw, clampf(delta * 8.0, 0.0, 1.0))
	rotation = Vector3(deg_to_rad(PITCH), _yaw, 0)
	cam.size = lerpf(cam.size, zoom, clampf(delta * 10.0, 0.0, 1.0))
	_clamp_to_painting()


func _clamp_to_painting() -> void:
	if paint_half == Vector2.ZERO:
		return
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	cam.size = minf(cam.size, minf(paint_half.y * 2.0, paint_half.x * 2.0 / aspect))
	zoom = minf(zoom, minf(paint_half.y * 2.0, paint_half.x * 2.0 / aspect))
	var b := global_transform.basis
	var off := position - paint_center
	var xc := off.dot(b.x)
	var yc := off.dot(b.y)
	var hx := maxf(paint_half.x - cam.size * aspect / 2.0, 0.0)
	var hy := maxf(paint_half.y - cam.size / 2.0, 0.0)
	var cx := clampf(xc, -hx, hx)
	var cy := clampf(yc, -hy, hy)
	if cx != xc or cy != yc:
		position += b.x * (cx - xc) + b.y * (cy - yc)


func handle_input(ev: InputEvent) -> bool:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom - 1.5, 7.0, 30.0)
			return true
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom + 1.5, 7.0, 30.0)
			return true
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if yaw_locked and ev.keycode in [KEY_Q, KEY_E]:
			return true
		if ev.keycode == KEY_Q:
			yaw_index -= 1
			return true
		if ev.keycode == KEY_E:
			yaw_index += 1
			return true
	return false


## Punkt na płaszczyźnie y=0 pod kursorem.
func ground_point(screen_pos: Vector2) -> Variant:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t := -from.y / dir.y
	if t < 0:
		return null
	return from + dir * t


## Ustawia widok od razu, bez płynnego przejścia (zrzuty testowe).
func set_view(yaw_extra_deg: float, zoom_: float) -> void:
	yaw_offset = yaw_extra_deg
	zoom = zoom_
	_yaw = deg_to_rad(45.0 + 90.0 * yaw_index + yaw_offset)
	rotation = Vector3(deg_to_rad(PITCH), _yaw, 0)
	cam.size = zoom
	position = target_pos
	_clamp_to_painting()
