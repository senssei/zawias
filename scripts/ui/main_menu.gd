# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends Control
## Menu główne.

signal new_game
signal load_game


func _ready() -> void:
	Audio.play_music("title", 1.0)
	Audio.set_ambient(["wind_planar"])
	UI.fit_to_viewport(self)
	theme = UI.theme()
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Tło: malunek Rdzawego Targu, przyciemniony
	var art_path := "res://assets/backgrounds/rusty_market_paint.png"
	if ResourceLoader.exists(art_path):
		var art := TextureRect.new()
		art.texture = load(art_path)
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.modulate = Color(0.42, 0.36, 0.44)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)

	# Dekoracyjny pierścień miasta
	var ring := _RingDecor.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ring)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := UI.vbox(14)
	center.add_child(v)
	var title := UI.label("ZAWIAS", 84, UI.BRASS)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UI.label(Loc.t("Opowieść z Rdzawego Targu"), 26, UI.PLANAR)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(Control.new())
	var b1 := UI.button(Loc.t("Nowa gra"), func(): new_game.emit(), 320)
	b1.custom_minimum_size.y = 48
	v.add_child(b1)
	var b2 := UI.button(Loc.t("Wczytaj grę"), func(): load_game.emit(), 320)
	b2.custom_minimum_size.y = 48
	b2.disabled = not GameState.has_save("slot1")
	v.add_child(b2)
	var bs := UI.button(Loc.t("Ustawienia"), _open_settings, 320)
	bs.custom_minimum_size.y = 48
	v.add_child(bs)
	var bc := UI.button(Loc.t("Autorzy i licencje"), _open_credits, 320)
	bc.custom_minimum_size.y = 48
	v.add_child(bc)
	var b3 := UI.button(Loc.t("Wyjście"), func(): get_tree().quit(), 320)
	b3.custom_minimum_size.y = 48
	v.add_child(b3)
	b1.grab_focus()
	if "--credits" in OS.get_cmdline_user_args():   # debug: zrzut ekranu autorów
		_open_credits.call_deferred()

	var lic := UI.label_w(Loc.t("Zasady na podstawie System Reference Document 5.2 (Wizards of the Coast LLC), licencja CC-BY-4.0. Świat Zawiasu jest oryginalny."), 13, UI.MUTED)
	lic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lic.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	lic.position.y -= 40
	lic.custom_minimum_size.x = 900
	lic.position.x -= 450
	add_child(lic)

	var ver := UI.label(Loc.t("wersja %s") % ProjectSettings.get_setting("application/config/version", "?"), 13, UI.MUTED)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.position += Vector2(-16, -12)
	add_child(ver)


var _settings: PanelContainer


func _open_settings() -> void:
	if _settings:
		_settings.queue_free()
	_settings = UI.panel(Color(UI.PANEL, 0.98))
	_settings.set_anchors_preset(Control.PRESET_CENTER)
	_settings.custom_minimum_size = Vector2(620, 0)
	_settings.position = Vector2(-310, -170)
	add_child(_settings)
	var v := UI.vbox(10)
	_settings.add_child(v)
	v.add_child(UI.label(Loc.t("Ustawienia"), 24, UI.BRASS))
	v.add_child(UI.settings_panel())
	v.add_child(UI.button(Loc.t("Zamknij"), func(): _settings.queue_free(); _settings = null))


const CREDITS := """[b]Zawias: Opowieść z Rdzawego Targu[/b]  ·  vertical slice

[color=#d9a85b]Zasady[/color]
System Reference Document 5.2 © Wizards of the Coast LLC, licencja Creative Commons Attribution 4.0 (CC-BY-4.0). Świat, postacie i teksty Zawiasu są oryginalne.
Kod gry: licencja MIT. Assety i treść gry © 2026 Rafal Warzycha, licencja CC-BY-4.0 (mapa głębi malowanego tła: CC-BY-NC-4.0).

[color=#d9a85b]Silnik[/color]
Godot Engine (licencja MIT) © Godot Engine contributors, Juan Linietsky, Ariel Manzur. Pełne noty licencyjne poniżej.

[color=#d9a85b]Animacje postaci[/color]
Quaternius, Universal Animation Library (CC0).

[color=#d9a85b]Grafika wygenerowana lokalnie[/color]
Malowane tło, portrety i koncepty postaci: FLUX.2 [klein] 4B (Black Forest Labs, Apache 2.0).
Modele 3D postaci: TRELLIS.2 (Microsoft, MIT).
Głębia malowanego tła: Depth Anything V2 Large (CC-BY-NC-4.0, wyłącznie do użytku niekomercyjnego).

[color=#d9a85b]Dźwięk[/color]
Muzyka: wygenerowana lokalnie ACE-Step 1.5 (MIT).
Głosy postaci i narratora (angielskie): wygenerowane lokalnie OmniVoice (k2-fsa, Apache 2.0).
Efekty i ambient: synteza własna.
"""

const CREDITS_EN := """[b]Zawias: A Tale of the Rusty Market[/b]  ·  vertical slice

[color=#d9a85b]Rules[/color]
System Reference Document 5.2 © Wizards of the Coast LLC, licensed under Creative Commons Attribution 4.0 (CC-BY-4.0). The world, characters and texts of Zawias are original.
Game code: MIT license. Game assets and content © 2026 Rafal Warzycha, CC-BY-4.0 (backdrop depth map: CC-BY-NC-4.0).

[color=#d9a85b]Engine[/color]
Godot Engine (MIT license) © Godot Engine contributors, Juan Linietsky, Ariel Manzur. Full license notices below.

[color=#d9a85b]Character animation[/color]
Quaternius, Universal Animation Library (CC0).

[color=#d9a85b]Locally generated art[/color]
Painted backdrop, portraits and character concepts: FLUX.2 [klein] 4B (Black Forest Labs, Apache 2.0).
3D character models: TRELLIS.2 (Microsoft, MIT).
Depth of the painted backdrop: Depth Anything V2 Large (CC-BY-NC-4.0, non-commercial use only).

[color=#d9a85b]Sound[/color]
Music: generated locally with ACE-Step 1.5 (MIT).
Character and narrator voices (English): generated locally with OmniVoice (k2-fsa, Apache 2.0).
Effects and ambience: own synthesis.
"""


var _credits: PanelContainer


func _open_credits() -> void:
	if _credits:
		_credits.queue_free()
	_credits = UI.panel(Color(UI.PANEL, 0.98))
	_credits.set_anchors_preset(Control.PRESET_CENTER)
	_credits.custom_minimum_size = Vector2(860, 640)
	_credits.position = Vector2(-430, -320)
	add_child(_credits)
	var v := UI.vbox(10)
	_credits.add_child(v)
	v.add_child(UI.label(Loc.t("Autorzy i licencje"), 24, UI.BRASS))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_font_size_override("bold_font_size", 18)
	rt.text = (CREDITS if Loc.lang == "pl" else CREDITS_EN) + "\n[color=#a89584][font_size=12]" + Engine.get_license_text() + "[/font_size][/color]"
	v.add_child(rt)
	var close := UI.button(Loc.t("Zamknij"), func(): _credits.queue_free(); _credits = null)
	v.add_child(close)
	close.grab_focus()


class _RingDecor extends Control:
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.42
		for i in 3:
			var rr := r + i * 26.0
			var col := UI.PLANAR
			col.a = 0.10 + 0.05 * i
			draw_arc(c, rr, t * (0.1 + i * 0.05), t * (0.1 + i * 0.05) + TAU * 0.8, 96, col, 2.0 + i)
		for i in 12:
			var a := t * 0.07 + i * TAU / 12.0
			var p := c + Vector2(cos(a), sin(a)) * (r + 26.0)
			# drobne odrzwia (łuk + ościeża), obrócone wzdłuż pierścienia: drzwi Zawiasu
			var col2 := Color(UI.BRASS, 0.28)
			var up := Vector2(cos(a), sin(a))
			var side := Vector2(-up.y, up.x)
			var base := p - up * 8.0
			var top := p + up * 3.0
			draw_line(base - side * 5.0, top - side * 5.0, col2, 1.5)
			draw_line(base + side * 5.0, top + side * 5.0, col2, 1.5)
			draw_arc(top, 5.0, up.angle() - PI / 2.0, up.angle() + PI / 2.0, 10, col2, 1.5)
			draw_line(base - side * 7.0, base + side * 7.0, col2, 1.5)
