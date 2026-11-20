# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name HUD
extends CanvasLayer
## Interfejs w grze: portret, log, pasek walki, kolejka inicjatywy, dialogi, okna.

signal action_selected(kind: String, data: Dictionary)   # attack/spell/action/end_turn
signal menu_pressed(id: String)                          # sheet/inventory/journal/rest/save/load/menu
signal dialogue_choice(index: int)
signal item_used(item_id: String)
signal weapon_equipped(weapon_id: String)
signal spellbook_cast(spell_id: String)
signal end_screen_choice(id: String)
signal level_up_chosen(choices: Dictionary)              # {"hp": "avg"|"roll", "subclass": id, "spells": [...]}
signal map_travel(cell: Vector2i)                        # klik na pełnej mapie: idź tam

var root: Control
var portrait: PanelContainer
var portrait_text: RichTextLabel
var hp_bar: ProgressBar
var level_up_button: Button
var log_box: RichTextLabel
var combat_bar: PanelContainer
var combat_buttons: VBoxContainer
var economy_label: RichTextLabel
var turn_label: RichTextLabel
var hint_label: Label
var tooltip: PanelContainer
var tooltip_text: RichTextLabel
var dialogue_panel: PanelContainer
var dlg_speaker: Label
var dlg_portrait: TextureRect
var player_portrait: TextureRect
const PORTRAIT_DIR := "res://assets/portraits/"
var dlg_text: RichTextLabel
var dlg_choices: VBoxContainer
const DIALOGUE_MARGIN := 10.0
var window: PanelContainer
var window_body: VBoxContainer
var window_title: Label
var toast: Label
var d20_badge: PanelContainer
var d20_number: Label
var d20_caption: Label
var d20_animation: Tween
var menu_box: HBoxContainer
var _dlg_choice_count := 0
# półcutscenka (ADR 0012): pełny ekran, malowany kadr z najazdem, mgła, pasy kinowe, napisy
var cutscene: Control
var cut_image: TextureRect
var cut_fog: ColorRect
var cut_text: RichTextLabel
var cut_choices: VBoxContainer
var _cut_tween: Tween
var _cut_reveal: Tween
var _fog_layers: Array = []
const CUTSCENE_DIR := "res://assets/cutscenes/"
var selected_key := ""
var minimap_panel: PanelContainer
var minimap: MapView
var minimap_title: Label
var map_markers: Callable                                # () -> Array znaczników (MapView)
var map_explored: Callable                               # (Vector2i) -> bool
var map_data: Dictionary


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	add_child(root)

	# Portret
	portrait = UI.panel(Color(UI.PANEL, 0.92))
	portrait.position = Vector2(12, 12)
	portrait.custom_minimum_size = Vector2(420, 0)
	root.add_child(portrait)
	var ph := UI.hbox(10)
	portrait.add_child(ph)
	player_portrait = TextureRect.new()
	player_portrait.custom_minimum_size = Vector2(80, 100)
	player_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	player_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	player_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ph.add_child(player_portrait)
	var pv := UI.vbox(4)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pv)
	portrait_text = RichTextLabel.new()
	portrait_text.bbcode_enabled = true
	portrait_text.fit_content = true
	portrait_text.scroll_active = false
	portrait_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(portrait_text)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size.y = 14
	hp_bar.show_percentage = false
	pv.add_child(hp_bar)
	level_up_button = UI.button(Loc.t("★ Awans! Wybierz, co zyskujesz"), func(): menu_pressed.emit("levelup"))
	level_up_button.add_theme_color_override("font_color", UI.BRASS)
	level_up_button.visible = false
	pv.add_child(level_up_button)

	# Menu po prawej
	var menu := UI.hbox(4)
	menu_box = menu
	menu.anchor_left = 1.0
	menu.anchor_right = 1.0
	menu.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu.offset_right = -12
	menu.offset_top = 12
	root.add_child(menu)
	for pair in [["sheet", Loc.t("Postać [C]")], ["inventory", Loc.t("Ekwipunek [I]")], ["journal", Loc.t("Dziennik [J]")],
			["spellbook", Loc.t("Księga czarów [K]")], ["map", Loc.t("Mapa [M]")],
			["rest", Loc.t("Odpoczynek [R]")], ["save", Loc.t("Zapisz [F5]")], ["load", Loc.t("Wczytaj [F9]")], ["menu", Loc.t("Menu")]]:
		var id_: String = pair[0]
		menu.add_child(UI.button(pair[1], func(): menu_pressed.emit(id_)))

	# Minimapa (prawy górny róg, pod przyciskami)
	minimap_panel = UI.panel(Color(UI.BG, 0.85))
	minimap_panel.anchor_left = 1.0
	minimap_panel.anchor_right = 1.0
	minimap_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	minimap_panel.offset_right = -12
	minimap_panel.offset_top = 60
	minimap_panel.tooltip_text = Loc.t("Kliknij, żeby otworzyć mapę [M]")
	root.add_child(minimap_panel)
	var mv := UI.vbox(4)
	minimap_panel.add_child(mv)
	minimap_title = UI.label("", 14, UI.BRASS)
	minimap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	minimap_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mv.add_child(minimap_title)
	minimap = MapView.new()
	minimap.rotate_with_camera = true
	minimap.cell_px = 9.0
	minimap.custom_minimum_size = Vector2(220, 180)
	minimap.cell_clicked.connect(func(_c): menu_pressed.emit("map"))
	mv.add_child(minimap)
	minimap_panel.visible = false

	# Log
	var log_panel := UI.panel(Color(UI.BG, 0.85))
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_panel.position = Vector2(12, -232)
	log_panel.custom_minimum_size = Vector2(520, 220)
	log_panel.size = Vector2(520, 220)
	root.add_child(log_panel)
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.add_theme_font_size_override("normal_font_size", 14)
	log_panel.add_child(log_box)

	# Kolejka tur
	turn_label = RichTextLabel.new()
	turn_label.bbcode_enabled = true
	turn_label.fit_content = true
	turn_label.scroll_active = false
	turn_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	turn_label.custom_minimum_size = Vector2(900, 0)
	turn_label.position = Vector2(-450, 64)
	turn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_label.add_theme_font_size_override("normal_font_size", 16)
	root.add_child(turn_label)

	# Pasek walki
	var bottom_box := UI.vbox(6)
	bottom_box.anchor_left = 0.5
	bottom_box.anchor_right = 0.5
	bottom_box.anchor_top = 1.0
	bottom_box.anchor_bottom = 1.0
	bottom_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom_box.offset_left = -180
	bottom_box.offset_right = 600
	bottom_box.offset_bottom = -12
	bottom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom_box)
	hint_label = UI.label("", 15, UI.BRASS)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_label.add_theme_constant_override("outline_size", 6)
	hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	bottom_box.add_child(hint_label)
	combat_bar = UI.panel(Color(UI.PANEL, 0.95))
	bottom_box.add_child(combat_bar)
	var cv := UI.vbox(4)
	combat_bar.add_child(cv)
	economy_label = RichTextLabel.new()
	economy_label.bbcode_enabled = true
	economy_label.fit_content = true
	economy_label.scroll_active = false
	cv.add_child(economy_label)
	combat_buttons = UI.vbox(4)
	cv.add_child(combat_buttons)
	combat_bar.visible = false

	d20_badge = PanelContainer.new()
	d20_badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
	d20_badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	d20_badge.offset_left = -124
	d20_badge.offset_right = 124
	d20_badge.offset_top = 78
	d20_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var roll_details := UI.vbox(2)
	roll_details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d20_badge.add_child(roll_details)
	d20_number = UI.label("", 48)
	d20_caption = UI.label("", 15)
	for label in [d20_number, d20_caption]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		roll_details.add_child(label)
	d20_badge.hide()
	root.add_child(d20_badge)


	# Podpowiedź pod kursorem
	tooltip = UI.panel(Color(UI.BG, 0.92))
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = RichTextLabel.new()
	tooltip_text.bbcode_enabled = true
	tooltip_text.fit_content = true
	tooltip_text.custom_minimum_size.x = 260
	tooltip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text.add_theme_font_size_override("normal_font_size", 14)
	tooltip.add_child(tooltip_text)
	tooltip.visible = false
	root.add_child(tooltip)

	# Dialog
	dialogue_panel = UI.panel(Color(UI.PANEL, 0.97))
	dialogue_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dialogue_panel.custom_minimum_size = Vector2(1040, 0)
	dialogue_panel.position = Vector2(-520, -420)
	root.add_child(dialogue_panel)
	var dh := UI.hbox(14)
	dialogue_panel.add_child(dh)
	dlg_portrait = TextureRect.new()
	dlg_portrait.custom_minimum_size = Vector2(200, 250)
	dlg_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dlg_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dlg_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dh.add_child(dlg_portrait)
	var dv := UI.vbox(8)
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dh.add_child(dv)
	dlg_speaker = UI.label("", 22, UI.BRASS)
	dv.add_child(dlg_speaker)
	dlg_text = RichTextLabel.new()
	dlg_text.bbcode_enabled = true
	dlg_text.fit_content = true
	dlg_text.scroll_active = false
	dlg_text.add_theme_font_size_override("normal_font_size", 18)
	dv.add_child(dlg_text)
	dv.add_child(HSeparator.new())
	dlg_choices = UI.vbox(4)
	dv.add_child(dlg_choices)
	dialogue_panel.visible = false
	_build_cutscene()

	# Okno (karta, ekwipunek, dziennik, zakończenie)
	window = UI.panel(Color(UI.PANEL, 0.98))
	window.set_anchors_preset(Control.PRESET_CENTER)
	window.custom_minimum_size = Vector2(760, 620)
	window.position = Vector2(-380, -330)
	root.add_child(window)
	var wv := UI.vbox(8)
	window.add_child(wv)
	var wh := UI.hbox()
	window_title = UI.label("", 26, UI.BRASS)
	window_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wh.add_child(window_title)
	wh.add_child(UI.button(Loc.t("Zamknij [Esc]"), close_window))
	wv.add_child(wh)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 540
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wv.add_child(scroll)
	window_body = UI.vbox(6)
	window_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(window_body)
	window.visible = false

	toast = UI.label_w("", 22, UI.BRASS)
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(-300, 112)   # pod paskiem przycisków i kolejnością tur; tło odcina go od podpisów postaci
	toast.custom_minimum_size.x = 600
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.08, 0.06, 0.09, 0.72)
	tsb.border_color = Color(UI.BRASS, 0.5)
	tsb.border_width_top = 1
	tsb.border_width_bottom = 1
	tsb.set_content_margin_all(6)
	tsb.set_corner_radius_all(4)
	toast.add_theme_stylebox_override("normal", tsb)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_constant_override("outline_size", 8)
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(toast)
	toast.modulate.a = 0.0   # puste tło niewidoczne do pierwszego komunikatu

	for l in GameState.log_lines.slice(-30):
		add_log(l)


# ------------------------------------------------------------------ portret i log

func refresh_portrait(c: Creature) -> void:
	if c == null:
		return
	var cls := DB.entry("classes", c.class_id)
	var conds := []
	for k in c.conditions.keys():
		conds.append(DB.entry("conditions", k).get("name", k))
	var slots := []
	for k in c.slots.keys():
		slots.append("%s:%d/%d" % [k, int(c.slots[k].cur), int(c.slots[k].max)])
	var res := []
	for k in c.resources.keys():
		res.append("%s %d" % [DB.entry("features", k).get("name", k), int(c.resources[k].cur)])
	var s := "[font_size=20][color=#d9a85b]%s[/color][/font_size]  %s %d\n" % [c.name, cls.get("name", ""), c.level]
	s += Loc.t("PW [b]%d/%d[/b]   KP [b]%d[/b]   Złoto %d   PD %d\n") % [c.hp, c.max_hp, c.ac(), c.gold, c.xp]
	if not slots.is_empty():
		s += Loc.t("[color=#9b7fd1]Miejsca na czary %s[/color]\n") % " ".join(slots)
	if not res.is_empty():
		s += "[color=#a89584]%s[/color]\n" % ", ".join(res)
	if c.heroic_inspiration:
		s += Loc.t("[color=#9b7fd1]★ Inspiracja[/color]  ")
	if not conds.is_empty():
		s += "[color=#e0634f]%s[/color]" % ", ".join(conds)
	portrait_text.text = s
	var ptex := portrait_texture("pc_" + c.class_id)
	player_portrait.texture = ptex
	player_portrait.visible = ptex != null
	level_up_button.visible = c.pending_levels > 0
	hp_bar.max_value = c.max_hp
	hp_bar.value = c.hp


func add_log(text: String) -> void:
	var t := text
	if t.begins_with(Loc.t("AWANS")) or t.begins_with(Loc.t("ZWYCIĘSTWO!")):
		t = "[color=#d9a85b][b]%s[/b][/color]" % t
	elif t.begins_with(Loc.t("[Zadanie]")) or t.begins_with(Loc.t("[Dziennik]")):
		t = "[color=#9b7fd1]%s[/color]" % t
	elif t.begins_with("—"):
		t = "[color=#d9a85b]%s[/color]" % t
	elif Loc.t("SUKCES") in t:
		t = t.replace(Loc.t("SUKCES"), "[color=#8fcf7a]%s[/color]" % Loc.t("SUKCES"))
	elif Loc.t("PORAŻKA") in t:
		t = t.replace(Loc.t("PORAŻKA"), "[color=#e0634f]%s[/color]" % Loc.t("PORAŻKA"))
	if Loc.t("TRAFIENIE KRYTYCZNE") in t or Loc.t("KRYTYK") in t:
		t = "[color=#ffcc66]%s[/color]" % t
	log_box.append_text(t + "\n")


func show_toast(text: String, color := UI.BRASS) -> void:
	toast.text = text
	toast.add_theme_color_override("font_color", color)
	toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(toast, "modulate:a", 0.0, 0.8)


func set_hint(text: String) -> void:
	hint_label.text = text


func show_d20(natural: int, roller: String) -> void:
	if natural != 1 and natural != 20:
		return
	if d20_animation and d20_animation.is_running():
		d20_animation.kill()
	var color := UI.BRASS if natural == 20 else UI.BAD
	var style := StyleBoxFlat.new()
	style.bg_color = UI.BG
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_bottom = 8
	d20_badge.add_theme_stylebox_override("panel", style)
	d20_number.text = str(natural)
	d20_number.add_theme_color_override("font_color", color)
	d20_caption.text = Loc.t("%s · naturalny rzut k20") % roller
	d20_badge.show()
	root.move_child(d20_badge, -1)
	d20_badge.reset_size()
	d20_badge.position.y = _d20_top()
	d20_badge.pivot_offset = d20_badge.size / 2
	d20_badge.modulate.a = 1
	d20_badge.scale = Vector2.ONE * 0.7
	d20_animation = create_tween()
	d20_animation.tween_property(d20_badge, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	d20_animation.tween_interval(0.9)
	d20_animation.tween_property(d20_badge, "modulate:a", 0.0, 0.25)
	d20_animation.tween_callback(d20_badge.hide)


## Górna krawędź odznaki k20: domyślnie pod paskiem menu; przy otwartym oknie (mapa, dziennik) pod nim albo
## nad nim, żeby nie zasłaniać nagłówka okna.
func _d20_top() -> float:
	const TOP := 78.0
	if not window.visible:
		return TOP
	var r := window.get_rect()          # okno i odznaka mają wspólnego rodzica (root)
	var h := d20_badge.size.y
	var vh := root.size.y
	if r.end.y + 8.0 + h <= vh - 4.0:
		return r.end.y + 8.0
	if r.position.y - 8.0 - h >= TOP:
		return r.position.y - 8.0 - h
	return TOP


func show_tooltip(text: String, at: Vector2) -> void:
	if text == "":
		tooltip.visible = false
		return
	tooltip_text.text = text
	tooltip.visible = true
	tooltip.reset_size()
	tooltip.position = at + Vector2(18, 18)


# ------------------------------------------------------------------ walka

func show_combat(on: bool) -> void:
	combat_bar.visible = on
	turn_label.visible = on
	if not on:
		set_hint("")
		selected_key = ""


func set_turn_order(order: Array, current_id: String, round_num: int) -> void:
	var parts := []
	for c in order:
		if c.dead:
			continue
		var col := "#8fcf7a" if c.team == "party" else "#e0634f"
		var nm: String = c.name
		if not c.is_conscious():
			nm = "[s]%s[/s]" % nm
		if c.id == current_id:
			parts.append("[bgcolor=#3b2a26][b][color=%s] ▶ %s [/color][/b][/bgcolor]" % [col, nm])
		else:
			parts.append("[color=%s]%s[/color]" % [col, nm])
	turn_label.text = Loc.t("[center][color=#d9a85b]Runda %d[/color]   %s[/center]") % [round_num, "  ·  ".join(parts)]


## Buduje przyciski akcji dla postaci gracza.
func build_combat_bar(mgr: CombatManager, c: Creature, my_turn: bool) -> void:
	UI.clear(combat_buttons)
	var t := mgr.turn
	if my_turn:
		var dot := func(n: int) -> String: return "[color=#8fcf7a]●[/color]" if n > 0 else "[color=#5b4a40]●[/color]"
		economy_label.text = Loc.t("Akcja %s   Akcja dodatkowa %s   Reakcja %s   Ruch [b]%d m[/b]%s") % [
			dot.call(int(t.action) + int(t.attacks_left)), dot.call(int(t.bonus)),
			dot.call(0 if c.effects.get("reaction_used", false) else 1), int(t.move) * 1.5,
			Loc.t("   [color=#9b7fd1]Odstąpienie[/color]") if t.get("disengaged", false) else ""]
		if not c.is_player:   # tura sterowanego towarzysza: czyja to tura, widać od razu
			economy_label.text = "[b][color=#d9b36c]%s[/color][/b]   " % c.name + economy_label.text
	else:
		economy_label.text = Loc.t("[color=#a89584]Tura przeciwnika…[/color]")
	if not my_turn:
		return
	var groups := {}
	for group in [["action", Loc.t("Akcje")], ["bonus", Loc.t("Akcje dodatkowe")], ["free", Loc.t("Bez kosztu akcji")]]:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := UI.hbox(8)
		var heading := UI.label_w(group[1], 14, UI.MUTED)
		heading.custom_minimum_size.x = 110
		heading.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		row.add_child(heading)
		row.add_child(flow)
		combat_buttons.add_child(row)
		groups[group[0]] = flow
	var has_attack := int(t.action) > 0 or int(t.attacks_left) > 0
	var i := 0
	for o in Attack.options(c):
		var key := "atk:%d" % i
		var b := _combat_button(groups.action, "⚔ " + o.name, key, not has_attack)
		b.tooltip_text = Loc.t("%s do trafienia, %s%s %s%s") % [Abilities.fmt_mod(int(o.bonus)), o.dice,
			Abilities.fmt_mod(int(o.dmg_bonus)), Loc.t(str(Attack.DAMAGE_NAMES.get(o.damage_type, ""))),
			(Loc.t("\nOpanowanie: ") + o.mastery) if o.mastery != "" else ""]
		var data: Dictionary = o
		b.pressed.connect(func(): _select(key); action_selected.emit("attack", data))
		i += 1
	for sid in Spellcasting.combat_spells(c):
		var sp := Spellcasting.spell(sid)
		var key: String = "spell:" + sid
		var group := "bonus" if sp.cast == "bonus" else "action"
		var b := _combat_button(groups[group], ("✦ " if int(sp.level) > 0 else "✧ ") + sp.name, key, mgr.spell_action_error(c, sid) != "")
		b.tooltip_text = "%s\n%s" % [Loc.t("Sztuczka") if int(sp.level) == 0 else Loc.t("Krąg %d") % int(sp.level), sp.desc]
		var sid_: String = sid
		b.pressed.connect(func(): _select(key); action_selected.emit("spell", {"id": sid_}))
	for a in mgr.available_actions(c):
		var ok := true
		match a.cost:
			"action": ok = int(t.action) > 0
			"bonus": ok = int(t.bonus) > 0
		if a.id == "second_wind" and c.resource("second_wind") <= 0:
			ok = false
		if a.id == "action_surge" and c.resource("action_surge") <= 0:
			ok = false
		if a.id == "divine_spark" and c.resource("channel_divinity") <= 0:
			ok = false
		var key: String = "act:" + a.id
		var b := _combat_button(groups[a.cost], a.name, key, not ok)
		match a.id:
			"help":
				b.tooltip_text = Loc.t("Wskaż sąsiedniego wroga. Pierwszy atak sojusznika przeciw niemu zyska przewagę do początku twojej następnej tury.")
			"search":
				b.tooltip_text = Loc.t("Wykonaj testy Percepcji, by wykryć ukrytych wrogów w linii wzroku.")
			"stabilize":
				b.tooltip_text = Loc.t("Wskaż sąsiedniego umierającego sojusznika. Udany test Medycyny ST 10 stabilizuje go.")
		var ad: Dictionary = a
		b.pressed.connect(func(): _select(key); action_selected.emit("action", ad))
	var end := UI.button(Loc.t("Koniec tury [Spacja]"), func(): action_selected.emit("end_turn", {}))
	end.add_theme_color_override("font_color", UI.BRASS)
	groups.free.add_child(end)
	for group in ["bonus", "free"]:
		groups[group].get_parent().visible = groups[group].get_child_count() > 0


func _combat_button(group: HFlowContainer, text: String, key: String, disabled: bool) -> Button:
	var b := UI.button(text)
	b.disabled = disabled
	b.toggle_mode = true
	b.button_pressed = key == selected_key
	b.set_meta("key", key)
	group.add_child(b)
	return b


func _select(key: String) -> void:
	selected_key = key
	for b in combat_buttons.find_children("*", "Button", true, false):
		if b.has_meta("key"):
			b.button_pressed = b.get_meta("key") == key


# ------------------------------------------------------------------ dialog

## Portret z assets/portraits/<id>.png (null, gdy brak).
static func portrait_texture(id_: String) -> Texture2D:
	var path := PORTRAIT_DIR + id_ + ".png"
	return load(path) if id_ != "" and ResourceLoader.exists(path) else null


func show_dialogue(speaker: String, text: String, choices: Array, portrait_id := "") -> void:
	dialogue_panel.visible = true
	var tex := portrait_texture(portrait_id)
	dlg_portrait.texture = tex
	dlg_portrait.visible = tex != null
	dlg_speaker.text = speaker
	dlg_text.text = text
	UI.clear(dlg_choices)
	_dlg_choice_count = choices.size()
	for i in choices.size():
		var ch: Dictionary = choices[i]
		var b := UI.button("%d. %s" % [i + 1, ch.text])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if ch.choice.has("check"):
			b.add_theme_color_override("font_color", UI.PLANAR.lightened(0.3))
		var idx: int = ch.index
		b.pressed.connect(func(): dialogue_choice.emit(idx))
		dlg_choices.add_child(b)
	_fit_dialogue.call_deferred()


func _build_cutscene() -> void:
	cutscene = Control.new()
	cutscene.set_anchors_preset(Control.PRESET_FULL_RECT)
	cutscene.mouse_filter = Control.MOUSE_FILTER_STOP
	cutscene.visible = false
	root.add_child(cutscene)
	var black := ColorRect.new()
	black.color = Color(0.02, 0.01, 0.03)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	cutscene.add_child(black)
	cut_image = TextureRect.new()
	cut_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	cut_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cut_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cutscene.add_child(cut_image)
	cut_fog = ColorRect.new()
	cut_fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	cut_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/rift_fog.gdshader")
	cut_fog.material = mat
	cutscene.add_child(cut_fog)
	for top in [true, false]:   # pasy kinowe
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.92)
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size.y = 64 if top else 180
		bar.offset_top = 0 if top else -180
		bar.offset_bottom = 64 if top else 0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cutscene.add_child(bar)
	var box := UI.vbox(10)
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.custom_minimum_size = Vector2(960, 0)
	box.position = Vector2(-480, -172)
	cutscene.add_child(box)
	cut_text = RichTextLabel.new()
	cut_text.bbcode_enabled = true
	cut_text.fit_content = true
	cut_text.scroll_active = false
	cut_text.add_theme_font_size_override("normal_font_size", 19)
	cut_text.add_theme_color_override("default_color", Color("#eadbc8"))
	cut_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cut_text)
	cut_choices = UI.vbox(4)
	cut_choices.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(cut_choices)
	cutscene.gui_input.connect(func(ev):   # klik w kadr dopisuje napis od razu
		if ev is InputEventMouseButton and ev.pressed and _cut_reveal and _cut_reveal.is_running():
			_cut_reveal.kill()
			cut_text.visible_ratio = 1.0
			cut_choices.modulate.a = 1.0)


## Węzeł z "scene": kadr assets/cutscenes/<scene>.png z wolnym najazdem, napis pisany w tempie głosu (secs),
## wybory pod spodem. Bez obrazu zostaje sama mgła.
func show_cutscene(scene_id: String, text: String, choices: Array, secs: float) -> void:
	dialogue_panel.visible = false
	var first := not cutscene.visible
	cutscene.visible = true
	cutscene.move_to_front()   # nad banerem lokacji i oknami
	for r in _fog_layers:      # przejście w mgłę zostaje na wierzchu, aż się rozwieje
		if is_instance_valid(r):
			r.move_to_front()
	var path := CUTSCENE_DIR + scene_id + ".png"
	var tex: Texture2D = load(path) if scene_id != "" and ResourceLoader.exists(path) else null
	if tex != cut_image.texture or first:
		cut_image.texture = tex
		cut_image.pivot_offset = get_viewport().get_visible_rect().size * 0.5
		if _cut_tween:
			_cut_tween.kill()
		cut_image.scale = Vector2.ONE * 1.02
		cut_image.position = Vector2.ZERO
		cut_image.modulate.a = 0.0
		_cut_tween = create_tween().set_parallel(true)
		_cut_tween.tween_property(cut_image, "modulate:a", 1.0, 1.6)
		_cut_tween.tween_property(cut_image, "scale", Vector2.ONE * 1.12, maxf(secs, 8.0) + 6.0).set_trans(Tween.TRANS_SINE)
		_cut_tween.tween_property(cut_image, "position", Vector2(-28, -12), maxf(secs, 8.0) + 6.0).set_trans(Tween.TRANS_SINE)
	(cut_fog.material as ShaderMaterial).set_shader_parameter("density", 0.42 if tex else 0.8)
	cut_text.text = "[center]%s[/center]" % text
	cut_text.visible_ratio = 0.0
	UI.clear(cut_choices)
	_dlg_choice_count = choices.size()
	for i in choices.size():
		var ch: Dictionary = choices[i]
		var b := UI.button(ch.text)
		b.custom_minimum_size.x = 320
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var idx: int = ch.index
		b.pressed.connect(func(): dialogue_choice.emit(idx))
		cut_choices.add_child(b)
	cut_choices.modulate.a = 0.0
	if _cut_reveal:
		_cut_reveal.kill()
	_cut_reveal = create_tween()
	_cut_reveal.tween_interval(0.8 if first else 0.2)
	_cut_reveal.tween_property(cut_text, "visible_ratio", 1.0, clampf(secs, 2.0, 30.0))
	_cut_reveal.tween_property(cut_choices, "modulate:a", 1.0, 0.5)


## Przejście w mgłę (fade_in) albo z mgły z błyskiem bramy (fade_out); secs = czas trwania.
func fog_transition(fade_in: bool, secs := 1.2) -> void:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = Color(0.38, 0.22, 0.55, 0.0) if fade_in else Color(0.95, 0.82, 0.55, 1.0)
	root.add_child(r)
	_fog_layers.append(r)
	_fog_layers = _fog_layers.filter(func(x): return is_instance_valid(x))
	var t := create_tween()
	if fade_in:
		t.tween_property(r, "color:a", 1.0, secs).set_trans(Tween.TRANS_SINE)
		t.tween_property(r, "color", Color(0.02, 0.01, 0.03, 1.0), 0.4)
		t.tween_property(r, "color:a", 0.0, 0.6)
	else:
		t.tween_property(r, "color:a", 0.0, secs).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_callback(r.queue_free)


func dialogue_append(text: String, success: bool) -> void:
	dlg_text.append_text("\n\n[color=%s]%s[/color]" % ["#8fcf7a" if success else "#e0634f", text])
	_fit_dialogue.call_deferred()


## Panel dialogu stoi dolną krawędzią nad dołem ekranu i rośnie w górę, gdy przybywa tekstu albo opcji.
func _fit_dialogue() -> void:
	await get_tree().process_frame   # RichTextLabel z fit_content zna wysokość dopiero po układzie
	var h := dialogue_panel.get_combined_minimum_size().y
	dialogue_panel.offset_bottom = -DIALOGUE_MARGIN
	dialogue_panel.offset_top = -DIALOGUE_MARGIN - h


func hide_dialogue() -> void:
	dialogue_panel.visible = false
	if cutscene and cutscene.visible:
		cutscene.visible = false
		if _cut_tween:
			_cut_tween.kill()
		if _cut_reveal:
			_cut_reveal.kill()
	set_voice_speaker("")


var _voice_who := ""


## Kto mówi na głos: portret rozmówcy ożywa przy jego kwestiach, przygasa przy narratorze.
func set_voice_speaker(who: String) -> void:
	_voice_who = who


# ------------------------------------------------------------------ dymki okrzyków

var _bubbles: Array = []             # [{target: Node3D, panel: PanelContainer, until: float}]


## Dymek nad postacią w świecie (podąża za nią na ekranie), znika po secs sekundach.
func bubble(target: Node3D, who: String, text: String, secs: float) -> void:
	for b in _bubbles:
		if b.target == target:
			b.panel.queue_free()
	_bubbles = _bubbles.filter(func(b): return b.target != target)
	var p := UI.panel(Color(UI.BG, 0.88))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size.x = 0
	var v := UI.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var n := UI.label(who, 13, UI.BRASS)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var l := UI.label_w(text, 16)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size.x = mini(320, 40 + text.length() * 8)
	v.add_child(l)
	p.modulate.a = 0.0
	root.add_child(p)
	root.move_child(p, 0)            # pod oknami i panelami
	create_tween().tween_property(p, "modulate:a", 1.0, 0.2)
	_bubbles.append({"target": target, "panel": p, "until": Time.get_ticks_msec() / 1000.0 + secs})


func clear_bubbles() -> void:
	for b in _bubbles:
		if is_instance_valid(b.panel):
			b.panel.queue_free()
	_bubbles.clear()


func _update_bubbles() -> void:
	if _bubbles.is_empty():
		return
	var cam := root.get_viewport().get_camera_3d()
	var now := Time.get_ticks_msec() / 1000.0
	var keep := []
	for b in _bubbles:
		var p: PanelContainer = b.panel
		if not is_instance_valid(b.target) or not is_instance_valid(p) or now > b.until + 0.4:
			if is_instance_valid(p):
				p.queue_free()
			continue
		if now > b.until:
			p.modulate.a = clampf((b.until + 0.4 - now) / 0.4, 0.0, 1.0)
		var head: Vector3 = (b.target as Node3D).global_position + Vector3(0, 2.3, 0)
		p.visible = cam != null and not cam.is_position_behind(head) and not dialogue_panel.visible
		if p.visible:
			var sp := cam.unproject_position(head)
			p.position = (sp - Vector2(p.size.x * 0.5, p.size.y)).round()
		keep.append(b)
	_bubbles = keep


func _process(delta: float) -> void:
	_update_bubbles()
	if dlg_portrait == null or not dialogue_panel.visible or not dlg_portrait.visible:
		return
	var lvl: float = Audio.voice_level() if _voice_who == "speaker" else 0.0
	var bright := 1.0 + lvl * 0.35
	if _voice_who == "narrator":
		bright = 0.62
	var want := Color(bright, bright, bright)
	dlg_portrait.modulate = dlg_portrait.modulate.lerp(want, 1.0 - exp(-delta * 14.0))
	dlg_portrait.pivot_offset = dlg_portrait.size * Vector2(0.5, 1.0)
	var sc := 1.0 + lvl * 0.035
	dlg_portrait.scale = dlg_portrait.scale.lerp(Vector2(sc, sc), 1.0 - exp(-delta * 18.0))


func dialogue_key(n: int) -> bool:
	var box := cut_choices if cutscene and cutscene.visible else dlg_choices
	if not (dialogue_panel.visible or cutscene.visible) or n < 1 or n > _dlg_choice_count:
		return false
	var b: Button = box.get_child(n - 1)
	b.pressed.emit()
	return true


# ------------------------------------------------------------------ okna

func is_window_open() -> bool:
	return window.visible


func close_window() -> void:
	if window.visible:
		UI.play_sfx("ui_close", -8.0)
	window.visible = false


func _open_window(title: String) -> void:
	window_title.text = title
	UI.clear(window_body)
	if not window.visible:
		UI.play_sfx("ui_open", -8.0)
	window.visible = true


func open_sheet(c: Creature) -> void:
	_open_window(Loc.t("Karta postaci"))
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.text = preload("res://scripts/ui/character_creation.gd").sheet_bbcode(c)
	window_body.add_child(r)


## Okno awansu: PW (średnia/rzut), podklasa, czary do wyboru, podgląd nowych cech i miejsc na czary.
func open_level_up(c: Creature) -> void:
	var o := Leveling.level_up_options(c)
	var cls := DB.entry("classes", c.class_id)
	_open_window(Loc.t("Awans: %s, poziom %d") % [cls.get("name", ""), int(o.level)])
	var choice := {"hp": "avg", "subclass": "", "spells": []}

	window_body.add_child(UI.label_w(Loc.t("Punkty wytrzymałości"), 18, UI.BRASS))
	var hp_row := UI.hbox()
	var grp := ButtonGroup.new()
	var avg := CheckBox.new()
	avg.text = Loc.t("Średnia: +%d") % int(o.hp_avg)
	avg.button_group = grp
	avg.button_pressed = true
	avg.toggled.connect(func(on): if on: choice.hp = "avg")
	var roll := CheckBox.new()
	roll.text = Loc.t("Rzut: k%d %s KON") % [int(o.hit_die), Abilities.fmt_mod(int(o.con))]
	roll.button_group = grp
	roll.toggled.connect(func(on): if on: choice.hp = "roll")
	hp_row.add_child(avg)
	hp_row.add_child(roll)
	window_body.add_child(hp_row)

	if not o.subclasses.is_empty():
		window_body.add_child(HSeparator.new())
		window_body.add_child(UI.label_w(Loc.t("Podklasa"), 18, UI.BRASS))
		var sgrp := ButtonGroup.new()
		for i in o.subclasses.size():
			var sid: String = o.subclasses[i]
			var sd := DB.entry("subclasses", sid)
			var cb := CheckBox.new()
			cb.text = sd.get("name", sid)
			cb.button_group = sgrp
			cb.toggled.connect(func(on): if on: choice.subclass = sid)
			window_body.add_child(cb)
			if sd.has("desc"):
				window_body.add_child(UI.label_w(sd.desc, 14, UI.MUTED))
			if i == 0:
				cb.button_pressed = true
				choice.subclass = sid

	if not o.features.is_empty():
		window_body.add_child(HSeparator.new())
		window_body.add_child(UI.label_w(Loc.t("Nowe cechy"), 18, UI.BRASS))
		for f in o.features:
			var fd := DB.entry("features", f)
			window_body.add_child(UI.label_w("• %s: %s" % [fd.get("name", f), fd.get("desc", "")], 15))

	if not o.slots.is_empty():
		var sl := []
		for k in o.slots.keys():
			sl.append(Loc.t("krąg %s: %d") % [k, int(o.slots[k])])
		window_body.add_child(UI.label_w(Loc.t("Miejsca na czary: ") + ", ".join(sl), 15, Color("#9b7fd1")))

	var confirm := UI.button(Loc.t("Zatwierdź awans"), func():
		level_up_chosen.emit(choice.duplicate(true)))
	var picks := int(o.spell_picks)
	if picks > 0:
		window_body.add_child(HSeparator.new())
		var head := UI.label_w(Loc.t("Nowe czary: wybierz %d") % picks, 18, UI.BRASS)
		window_body.add_child(head)
		var boxes := []
		for sid in o.spell_choices:
			var sp := DB.entry("spells", sid)
			var cb := CheckBox.new()
			cb.text = Loc.t("%s (krąg %d)") % [sp.get("name", sid), int(sp.get("level", 1))]
			cb.tooltip_text = sp.get("desc", "")
			boxes.append(cb)
			window_body.add_child(cb)
			window_body.add_child(UI.label_w(sp.get("desc", ""), 13, UI.MUTED))
		var update := func():
			choice.spells = []
			for i in boxes.size():
				if boxes[i].button_pressed:
					choice.spells.append(o.spell_choices[i])
			for b in boxes:
				b.disabled = not b.button_pressed and choice.spells.size() >= picks
			confirm.disabled = choice.spells.size() != picks
			head.text = Loc.t("Nowe czary: wybrano %d z %d") % [choice.spells.size(), picks]
		for b in boxes:
			b.toggled.connect(func(_on): update.call())
		update.call()
	window_body.add_child(HSeparator.new())
	window_body.add_child(confirm)


func open_settings() -> void:
	_open_window(Loc.t("Ustawienia"))
	window_body.add_child(UI.settings_panel())


func open_inventory(c: Creature, can_equip := true, can_use := true) -> void:
	_open_window(Loc.t("Ekwipunek"))
	window_body.add_child(UI.label_w(Loc.t("Złoto: %d sz.") % c.gold, 18, UI.BRASS))
	var armor := DB.entry("armor", c.armor_id)
	window_body.add_child(UI.label_w(Loc.t("Pancerz: %s · KP %d") % [
		armor.get("name", Loc.t("Bez pancerza")), c.ac()], 16))
	if c.shield:
		window_body.add_child(UI.label_w(Loc.t("Tarcza"), 16))
	window_body.add_child(HSeparator.new())
	window_body.add_child(UI.label_w(Loc.t("Broń (pierwsza to broń główna):"), 16, UI.MUTED))
	for w in c.weapons:
		var row := UI.hbox()
		var wd := DB.entry("weapons", w)
		var l := UI.label_w("%s%s, %s %s" % [wd.name, Loc.t(" (główna)") if w == c.main_weapon() else "", wd.damage, Loc.t(str(Attack.DAMAGE_NAMES.get(wd.type, "")))], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if w != c.main_weapon():
			var wid: String = w
			var equip := UI.button(Loc.t("Ustaw jako główną"), func(): weapon_equipped.emit(wid))
			equip.disabled = not can_equip
			row.add_child(equip)
		window_body.add_child(row)
	window_body.add_child(HSeparator.new())
	window_body.add_child(UI.label_w(Loc.t("Przedmioty:"), 16, UI.MUTED))
	var counts := {}
	for it in c.inventory:
		counts[it] = int(counts.get(it, 0)) + 1
	if counts.is_empty():
		window_body.add_child(UI.label_w(Loc.t("(pusto)"), 15, UI.MUTED))
	for it in counts.keys():
		var d := DB.entry("items", it)
		var row := UI.hbox()
		var details := UI.vbox(2)
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_child(UI.label_w("%s ×%d" % [d.get("name", it), counts[it]], 16))
		if d.has("desc"):
			details.add_child(UI.label_w(d.desc, 15, UI.MUTED))
		row.add_child(details)
		if d.get("type", "") == "consumable":
			var iid: String = it
			var use := UI.button(Loc.t("Użyj"), func(): item_used.emit(iid))
			use.disabled = not can_use
			row.add_child(use)
		window_body.add_child(row)


func open_spellbook(c: Creature, combat: CombatManager = null) -> void:
	_open_window(Loc.t("Księga czarów"))
	var known := Spellcasting.known(c)
	if known.is_empty():
		window_body.add_child(UI.label_w(Loc.t("Ta postać nie zna żadnych czarów."), 16, UI.MUTED))
		return
	if not c.slots.is_empty():
		window_body.add_child(UI.label_w(Loc.t("Miejsca na czary"), 18, UI.BRASS))
		for level in range(1, 10):
			var slot: Dictionary = c.slots.get(str(level), {})
			if not slot.is_empty():
				window_body.add_child(UI.label_w(Loc.t("Krąg %d: %d/%d") % [level, int(slot.cur), int(slot.max)], 15))
	if c.concentration != "":
		var spell := Spellcasting.spell(c.concentration)
		window_body.add_child(UI.label_w(Loc.t("Koncentracja: %s") % spell.get("name", c.concentration), 15, UI.BRASS))
	for level in range(10):
		var heading_added := false
		for id in known:
			var spell := Spellcasting.spell(id)
			if spell.is_empty() or int(spell.level) != level:
				continue
			if not heading_added:
				window_body.add_child(HSeparator.new())
				window_body.add_child(UI.label_w(Loc.t("Sztuczki") if level == 0 else Loc.t("Krąg %d") % level, 18, UI.BRASS))
				heading_added = true
			_add_spellbook_entry(c, str(id), spell, combat)


func _add_spellbook_entry(c: Creature, id: String, spell: Dictionary, combat: CombatManager) -> void:
	var row := UI.hbox()
	var details := UI.vbox(2)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(details)
	details.add_child(UI.label_w(spell.name, 17))
	var tags: Array[String] = []
	match spell.cast:
		"bonus": tags.append(Loc.t("Akcja dodatkowa"))
		"reaction": tags.append(Loc.t("Reakcja"))
		_: tags.append(Loc.t("Akcja"))
	if spell.type == "utility":
		tags.append(Loc.t("Czar użytkowy"))
	if spell.has("range"):
		tags.append(Loc.t("Zasięg: %s m") % str(int(spell.range) * 1.5))
	if spell.get("concentration", false):
		tags.append(Loc.t("Koncentracja"))
	details.add_child(UI.label_w(" · ".join(tags), 14, UI.MUTED))
	details.add_child(UI.label_w(spell.desc, 15))
	if combat != null and spell.type not in ["utility", "reaction"]:
		var button := UI.button(Loc.t("Rzuć czar"), func(): spellbook_cast.emit(id))
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.tooltip_text = combat.spell_action_error(c, id)
		button.disabled = button.tooltip_text != ""
		row.add_child(button)
	window_body.add_child(row)


func open_journal() -> void:
	_open_window(Loc.t("Dziennik"))
	for q in GameState.quests.keys():
		var stage: String = GameState.quests[q]
		var done := stage.begins_with("done")
		window_body.add_child(UI.label_w("%s %s" % ["✔" if done else "◆", Loc.t(str(GameState.QUEST_NAMES.get(q, q)))], 20, UI.GOOD if done else UI.BRASS))
		window_body.add_child(UI.label_w(Loc.t(str(GameState.QUEST_STAGES.get(q, {}).get(stage, stage))), 16))
		window_body.add_child(HSeparator.new())
	# frakcje: nastawienie, kim są i co to teraz zmienia (data/factions.json: desc, effects[nastawienie])
	window_body.add_child(UI.label_w(Loc.t("Frakcje"), 18, UI.BRASS))
	var factions := DB.table("factions")
	for faction in factions:
		var f: Dictionary = factions[faction]
		var att := GameState.faction_attitude(faction)
		var col: Color = {"friendly": UI.GOOD, "wary": UI.BAD}.get(att, UI.TEXT)
		window_body.add_child(UI.label_w("%s · %s" % [f.name, GameState.attitude_label(att)], 16, col))
		if f.has("desc"):
			window_body.add_child(UI.label_w(str(f.desc), 14, UI.MUTED))
		var eff := str(f.get("effects", {}).get(att, ""))
		if eff != "":
			window_body.add_child(UI.label_w("→ " + eff, 14))
	window_body.add_child(HSeparator.new())
	# rejestr słowa (ADR 0010): obietnice i kłamstwa w kolejności, w jakiej padły
	if not GameState.words.is_empty():
		window_body.add_child(UI.label_w(Loc.t("Dane słowo"), 18, UI.BRASS))
		for id_ in GameState.words:
			var line := word_line(id_, GameState.words[id_])
			window_body.add_child(UI.label_w(line[0], 15, line[1]))
		window_body.add_child(HSeparator.new())
	window_body.add_child(UI.label_w(Loc.t("Zapiski"), 18, UI.BRASS))
	for i in range(GameState.journal.size() - 1, -1, -1):
		window_body.add_child(UI.label_w("• " + GameState.journal[i], 15))


## Wiersz rejestru słowa: [tekst, kolor] (dziennik i ekran końca).
static func word_line(id_: String, state: String) -> Array:
	var text := str(DB.table("words").get(id_, {}).get("text", id_))
	match state:
		"kept":
			return ["✔ %s %s" % [text, Loc.t("Dotrzymane.")], UI.GOOD]
		"broken":
			return ["✘ %s %s" % [text, Loc.t("Złamane.")], UI.BAD]
		"hidden":
			return ["◇ %s %s" % [text, Loc.t("Nikt się nie dowiedział.")], UI.MUTED]
		"exposed":
			return ["✘ %s %s" % [text, Loc.t("Wyszło na jaw.")], UI.BAD]
		_:
			return ["◆ %s %s" % [text, Loc.t("Jeszcze niespłacone.")], UI.TEXT]


## Mapa: dane siatki, źródło znaczników i mgły (świat podaje funkcje, HUD nic nie wie o aktorach).
func setup_map(m: Dictionary, markers: Callable, explored_fn: Callable) -> void:
	map_data = m
	map_markers = markers
	map_explored = explored_fn
	minimap.set_map(m)
	minimap.markers_fn = markers
	minimap.explored = explored_fn
	minimap_title.text = Loc.t(str(m.get("name", ""))) + "   [M]"
	minimap_panel.visible = true


## Kąt kamery dla minimapy (rad).
func set_map_yaw(yaw: float) -> void:
	if minimap:
		minimap.yaw = yaw


func open_map() -> void:
	_open_window(Loc.t(str(map_data.get("name", Loc.t("Mapa")))))
	var mv := MapView.new()
	mv.show_names = true
	mv.custom_minimum_size = Vector2(720, 380)
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.set_map(map_data)
	mv.markers_fn = map_markers
	mv.explored = map_explored
	mv.cell_clicked.connect(func(c):
		close_window()
		map_travel.emit(c))
	window_body.add_child(mv)
	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.fit_content = true
	legend.scroll_active = false
	legend.add_theme_font_size_override("normal_font_size", 15)
	legend.text = "[color=#5fa8d3]●[/color] %s    [color=#e8c98a]●[/color] %s    [color=%s]◇[/color] %s    [color=#e0634f]✕[/color] %s    [color=#a39a8c]■[/color] %s    [color=#f2c14e]✦[/color] %s" % [
		Loc.t("Ty"), Loc.t("Postacie"), UI.BRASS.to_html(false), Loc.t("Cel zadania"), Loc.t("Zamknięte"), Loc.t("Obiekty"), Loc.t("Łupy")]
	window_body.add_child(legend)
	window_body.add_child(UI.label_w(Loc.t("Kliknij miejsce na mapie, żeby tam pójść. Ciemne pola skrywa mgła ze Szczeliny: rzednieje tam, gdzie spojrzysz."), 14, UI.MUTED))


func open_end_screen(title: String, text: String, buttons: Array) -> void:
	_open_window(title)
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.add_theme_font_size_override("normal_font_size", 19)
	r.text = text
	window_body.add_child(r)
	var h := UI.hbox(10)
	for b in buttons:
		var id_: String = b[0]
		h.add_child(UI.button(b[1], func(): end_screen_choice.emit(id_), 200))
	window_body.add_child(h)


func is_blocking() -> bool:
	return dialogue_panel.visible or window.visible


func mouse_over_ui() -> bool:
	var mp := root.get_viewport().get_mouse_position()
	for n in [portrait, combat_bar, dialogue_panel, window, log_box.get_parent(), menu_box, minimap_panel]:
		if n.visible and n.get_global_rect().has_point(mp):
			return true
	return false
