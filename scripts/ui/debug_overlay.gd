# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name DebugOverlay
extends CanvasLayer
## Nakładka diagnostyczna (F3 albo flaga --debug): FPS, czas klatki, draw calle, pamięć wideo, karta graficzna,
## komórka gracza. Działa na każdym ekranie (menu, kreator, świat), nad całym interfejsem.

const REFRESH := 0.25                     # s między odświeżeniami tekstu

var label: Label
var panel: PanelContainer
var _t := 0.0
var _frames := 0
var _worst := 0.0                         # najdłuższa klatka w oknie odświeżania (ms)
var _gpu := ""


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = UI.panel(Color(0, 0, 0, 0.62))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.position.y = 290                # pod minimapą, nie zasłania portretu ani dziennika
	panel.offset_right = -14
	add_child(panel)
	label = UI.label("", 14, UI.GOOD)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	_gpu = "%s | %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()]
	print("GPU: %s | %s" % [_gpu, RenderingServer.get_video_adapter_api_version()])
	panel.visible = "--debug" in OS.get_cmdline_user_args()


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_F3:
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not panel.visible:
		return
	_frames += 1
	_t += delta
	_worst = maxf(_worst, delta * 1000.0)
	if _t < REFRESH:
		return
	var rs := RenderingServer
	var lines := [
		"FPS %d   klatka %.1f ms (max %.1f)" % [Engine.get_frames_per_second(), _t * 1000.0 / _frames, _worst],
		"draw calle %d   obiekty %d   trójkąty %dk" % [
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000],
		"VRAM %d MB   tekstury %d MB   RAM %d MB" % [
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) >> 20,
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) >> 20,
			OS.get_static_memory_usage() >> 20],
		"GPU %s" % _gpu,
		"%s   %dx%d   vsync %s" % [rs.get_current_rendering_method(), get_viewport().size.x, get_viewport().size.y,
			"tak" if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else "nie"],
	]
	var cell := _player_cell()
	if cell != "":
		lines.append(cell)
	label.text = "\n".join(lines)
	_t = 0.0
	_frames = 0
	_worst = 0.0


func _player_cell() -> String:
	var screen = get_parent().get("screen")
	if screen == null or not is_instance_valid(screen):
		return ""
	var pa = screen.get("player_actor")
	if pa == null or not is_instance_valid(pa):
		return ""
	return "gracz %s   tryb %s" % [str(pa.cell), str(screen.get("mode"))]
