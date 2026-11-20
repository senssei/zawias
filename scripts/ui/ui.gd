# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name UI
extends RefCounted
## Pomocnicze konstruktory interfejsu i wspólny motyw (rdza, mosiądz, fiolet planów).

const BG := Color("#1a1214")
const PANEL := Color("#2a1d1c")
const PANEL_LIGHT := Color("#3b2a26")
const BRASS := Color("#d9a85b")
const RUST := Color("#b5532a")
const TEXT := Color("#eadbc8")
const MUTED := Color("#a89584")
const GOOD := Color("#8fcf7a")
const BAD := Color("#e0634f")
const PLANAR := Color("#9b7fd1")

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_style(PANEL))
	t.set_stylebox("panel", "Panel", panel_style(PANEL))
	var normal := panel_style(PANEL_LIGHT, BRASS.darkened(0.45), 1, 4)
	var hover := panel_style(PANEL_LIGHT.lightened(0.1), BRASS, 1, 4)
	var pressed := panel_style(RUST.darkened(0.3), BRASS, 1, 4)
	var disabled := panel_style(PANEL.darkened(0.2), Color(0.3, 0.25, 0.22), 1, 4)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, panel_style(Color(0, 0, 0, 0), BRASS, 1, 4))
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, BRASS.lightened(0.3))
		t.set_color("font_disabled_color", cls, MUTED.darkened(0.3))
	t.set_stylebox("normal", "LineEdit", panel_style(BG, BRASS.darkened(0.4), 1, 4))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_stylebox("background", "ProgressBar", panel_style(BG, Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("fill", "ProgressBar", panel_style(BAD.darkened(0.1), Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("panel", "TooltipPanel", panel_style(BG, BRASS, 1, 4))
	_theme = t
	return t


static func panel_style(color: Color, border: Color = Color("#5b3f2e"), bw := 2, radius := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func label(text: String, size := 17, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Etykieta z zawijaniem tekstu (do długich opisów w pionowych kontenerach).
static func label_w(text: String, size := 17, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func button(text: String, cb: Callable = Callable(), min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.pressed.connect(func(): play_sfx("ui_click", -6.0))
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## Ustawienia: głośność szyn i pełny ekran (zapis w user://settings.cfg przez Audio).
static func settings_panel() -> VBoxContainer:
	var v := vbox(10)
	var ml := Engine.get_main_loop() as SceneTree
	var au: Node = ml.root.get_node_or_null("Audio") if ml else null
	for pair in [["Master", Loc.t("Głośność ogólna")], ["Music", Loc.t("Muzyka")], ["Ambient", Loc.t("Otoczenie")], ["SFX", Loc.t("Efekty")], ["Voice", Loc.t("Głosy postaci")]]:
		var bus: String = pair[0]
		var row := hbox(12)
		var l := label(pair[1], 17)
		l.custom_minimum_size.x = 200
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.custom_minimum_size.x = 320
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value = au.get_volume(bus) if au else 0.8
		sl.value_changed.connect(func(val): if au: au.set_volume(bus, val))
		if bus == "SFX":
			sl.drag_ended.connect(func(_c): play_sfx("sword_hit"))
		row.add_child(sl)
		v.add_child(row)
	var drow := hbox(12)
	var dl := label(Loc.t("Poziom trudności"), 17)
	dl.custom_minimum_size.x = 200
	drow.add_child(dl)
	var dopt := OptionButton.new()
	for i in Difficulty.ORDER.size():
		var did: String = Difficulty.ORDER[i]
		dopt.add_item(Loc.t(Difficulty.PRESETS[did].name), i)
		dopt.set_item_tooltip(i, Loc.t(Difficulty.PRESETS[did].desc))
		if did == Difficulty.current:
			dopt.select(i)
	dopt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drow.add_child(dopt)
	v.add_child(drow)
	var ddesc := label(Loc.t(Difficulty.preset().desc) + Loc.t(" Zmiana działa od następnej walki."), 14, MUTED)
	v.add_child(ddesc)
	dopt.item_selected.connect(func(i):
		var did: String = Difficulty.ORDER[i]
		if au:
			au.set_difficulty(did)
		else:
			Difficulty.current = did
		ddesc.text = Loc.t(Difficulty.preset().desc) + Loc.t(" Zmiana działa od następnej walki."))
	var cc := CheckBox.new()
	cc.text = Loc.t("Steruj towarzyszami w walce")
	cc.tooltip_text = Loc.t("Wyłączone: towarzysze walczą sami. Zmiana działa od następnej walki.")
	cc.button_pressed = au.control_companions if au else true
	cc.toggled.connect(func(on): if au: au.set_control_companions(on))
	v.add_child(cc)
	var lrow := hbox(12)
	var ll := label(Loc.t("Język") + " / Language", 17)
	ll.custom_minimum_size.x = 200
	lrow.add_child(ll)
	var lopt := OptionButton.new()
	lopt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # nazwy języków zawsze we własnym języku
	var langs: Array = Loc.LANGS.keys()
	for i in langs.size():
		lopt.add_item(Loc.LANGS[langs[i]], i)
		if langs[i] == Loc.lang:
			lopt.select(i)
	lopt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lrow.add_child(lopt)
	v.add_child(lrow)
	var in_game: bool = ml != null and ml.root.get_node_or_null("GameState") != null and ml.root.get_node("GameState").player != null
	if in_game:
		v.add_child(label(Loc.t("Zmiana języka działa od razu w menu; w trakcie gry po powrocie do menu."), 14, MUTED))
	lopt.item_selected.connect(func(i):
		Loc.set_lang(langs[i])
		DB.clear_cache()
		if not in_game and ml:
			ml.reload_current_scene())
	var fs := CheckBox.new()
	fs.text = Loc.t("Pełny ekran")
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.toggled.connect(func(on): if au: au.set_fullscreen(on))
	v.add_child(fs)
	var vrow := hbox(12)
	var vl := label(Loc.t("Język głosów"), 17)
	vl.custom_minimum_size.x = 200
	vrow.add_child(vl)
	var vopt := OptionButton.new()
	vopt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var vlangs: Array = Loc.LANGS.keys()
	for i in vlangs.size():
		vopt.add_item(Loc.LANGS[vlangs[i]], i)
		vopt.set_item_disabled(i, not vlangs[i] in VoiceLines.voice_langs())
		if au and vlangs[i] == au.voice_lang:
			vopt.select(i)
	vopt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vopt.tooltip_text = Loc.t("Tekst dialogów zostaje w języku gry i służy za napisy.")
	vopt.item_selected.connect(func(i): if au: au.set_voice_lang(vlangs[i]))
	vrow.add_child(vopt)
	v.add_child(vrow)
	var nar := CheckBox.new()
	nar.text = Loc.t("Narrator czyta opisy w dialogach")
	nar.button_pressed = au.narrator if au else true
	nar.toggled.connect(func(on): if au: au.set_narrator(on))
	v.add_child(nar)
	var tts := CheckBox.new()
	tts.text = Loc.t("Synteza mowy systemu, gdy kwestia nie ma nagrania")
	tts.tooltip_text = Loc.t("Głos systemu operacyjnego czyta wypowiedzi postaci, dla których nie wygenerowano nagrań.")
	tts.button_pressed = au.tts_fallback if au else false
	tts.disabled = not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
	tts.toggled.connect(func(on): if au: au.set_tts_fallback(on))
	v.add_child(tts)
	return v


## Efekt dźwiękowy przez autoload Audio (bezpieczne poza drzewem sceny i w testach).
static func play_sfx(id_: String, volume_db := 0.0) -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var au: Node = (ml as SceneTree).root.get_node_or_null("Audio")
		if au:
			au.sfx(id_, volume_db)


static func vbox(sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func panel(color := PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(color))
	return p


static func clear(node: Node) -> void:
	for ch in node.get_children():
		node.remove_child(ch)
		ch.queue_free()


## Dopasowuje Control do rozmiaru okna (gdy rodzicem nie jest Control).
static func fit_to_viewport(c: Control) -> void:
	var vp := c.get_viewport()
	c.position = Vector2.ZERO
	c.size = vp.get_visible_rect().size
	vp.size_changed.connect(func():
		if is_instance_valid(c):
			c.size = vp.get_visible_rect().size)
