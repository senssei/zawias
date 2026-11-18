class_name HUD
extends CanvasLayer
## Interfejs w grze: portret, log, pasek walki, kolejka inicjatywy, dialogi, okna.

signal action_selected(kind: String, data: Dictionary)   # attack/spell/action/end_turn
signal menu_pressed(id: String)                          # sheet/inventory/journal/rest/save/load/menu
signal dialogue_choice(index: int)
signal item_used(item_id: String)
signal weapon_equipped(weapon_id: String)
signal end_screen_choice(id: String)
signal level_up_chosen(choices: Dictionary)              # {"hp": "avg"|"roll", "subclass": id, "spells": [...]}

var root: Control
var portrait: PanelContainer
var portrait_text: RichTextLabel
var hp_bar: ProgressBar
var level_up_button: Button
var log_box: RichTextLabel
var combat_bar: PanelContainer
var combat_buttons: HFlowContainer
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
var window: PanelContainer
var window_body: VBoxContainer
var window_title: Label
var toast: Label
var menu_box: HBoxContainer
var _dlg_choice_count := 0
var selected_key := ""


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
			["rest", Loc.t("Odpoczynek [R]")], ["save", Loc.t("Zapisz [F5]")], ["load", Loc.t("Wczytaj [F9]")], ["menu", Loc.t("Menu")]]:
		var id_: String = pair[0]
		menu.add_child(UI.button(pair[1], func(): menu_pressed.emit(id_)))

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
	combat_buttons = HFlowContainer.new()
	combat_buttons.add_theme_constant_override("h_separation", 4)
	combat_buttons.add_theme_constant_override("v_separation", 4)
	cv.add_child(combat_buttons)
	combat_bar.visible = false


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
	else:
		economy_label.text = Loc.t("[color=#a89584]Tura przeciwnika…[/color]")
	if not my_turn:
		return
	var has_attack := int(t.action) > 0 or int(t.attacks_left) > 0
	var i := 0
	for o in Attack.options(c):
		var key := "atk:%d" % i
		var b := _combat_button("⚔ " + o.name, key, not has_attack)
		b.tooltip_text = Loc.t("%s do trafienia, %s%s %s%s") % [Abilities.fmt_mod(int(o.bonus)), o.dice,
			Abilities.fmt_mod(int(o.dmg_bonus)), Loc.t(str(Attack.DAMAGE_NAMES.get(o.damage_type, ""))),
			(Loc.t("\nOpanowanie: ") + o.mastery) if o.mastery != "" else ""]
		var data: Dictionary = o
		b.pressed.connect(func(): _select(key); action_selected.emit("attack", data))
		i += 1
	for sid in Spellcasting.combat_spells(c):
		var sp := Spellcasting.spell(sid)
		var key: String = "spell:" + sid
		var cost_ok := (int(t.bonus) > 0) if sp.cast == "bonus" else (int(t.action) > 0)
		var lvl_ok := int(sp.level) == 0 or c.lowest_slot(int(sp.level)) > 0
		var b := _combat_button(("✦ " if int(sp.level) > 0 else "✧ ") + sp.name, key, not (cost_ok and lvl_ok))
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
		var label: String = a.name + (Loc.t(" (dod.)") if a.cost == "bonus" else "")
		var key: String = "act:" + a.id
		var b := _combat_button(label, key, not ok)
		var ad: Dictionary = a
		b.pressed.connect(func(): _select(key); action_selected.emit("action", ad))
	var end := UI.button(Loc.t("Koniec tury [Spacja]"), func(): action_selected.emit("end_turn", {}))
	end.add_theme_color_override("font_color", UI.BRASS)
	combat_buttons.add_child(end)


func _combat_button(text: String, key: String, disabled: bool) -> Button:
	var b := UI.button(text)
	b.disabled = disabled
	b.toggle_mode = true
	b.button_pressed = key == selected_key
	b.set_meta("key", key)
	combat_buttons.add_child(b)
	return b


func _select(key: String) -> void:
	selected_key = key
	for b in combat_buttons.get_children():
		if b is Button and b.has_meta("key"):
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


func dialogue_append(text: String, success: bool) -> void:
	dlg_text.append_text("\n\n[color=%s]%s[/color]" % ["#8fcf7a" if success else "#e0634f", text])


func hide_dialogue() -> void:
	dialogue_panel.visible = false


func dialogue_key(n: int) -> bool:
	if not dialogue_panel.visible or n < 1 or n > _dlg_choice_count:
		return false
	var b: Button = dlg_choices.get_child(n - 1)
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


func open_inventory(c: Creature) -> void:
	_open_window(Loc.t("Ekwipunek"))
	window_body.add_child(UI.label_w(Loc.t("Złoto: %d sz.") % c.gold, 18, UI.BRASS))
	window_body.add_child(UI.label_w(Loc.t("Broń (pierwsza to broń główna):"), 16, UI.MUTED))
	for w in c.weapons:
		var row := UI.hbox()
		var wd := DB.entry("weapons", w)
		var l := UI.label_w("%s%s, %s %s" % [wd.name, Loc.t(" (główna)") if w == c.main_weapon() else "", wd.damage, Loc.t(str(Attack.DAMAGE_NAMES.get(wd.type, "")))], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if w != c.main_weapon():
			var wid: String = w
			row.add_child(UI.button(Loc.t("Ustaw jako główną"), func(): weapon_equipped.emit(wid)))
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
		var l := UI.label_w("%s ×%d: %s" % [d.get("name", it), counts[it], d.get("desc", "")], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if d.get("type", "") == "consumable":
			var iid: String = it
			row.add_child(UI.button(Loc.t("Użyj"), func(): item_used.emit(iid)))
		window_body.add_child(row)


func open_journal() -> void:
	_open_window(Loc.t("Dziennik"))
	for q in GameState.quests.keys():
		var stage: String = GameState.quests[q]
		var done := stage.begins_with("done")
		window_body.add_child(UI.label_w("%s %s" % ["✔" if done else "◆", Loc.t(str(GameState.QUEST_NAMES.get(q, q)))], 20, UI.GOOD if done else UI.BRASS))
		window_body.add_child(UI.label_w(Loc.t(str(GameState.QUEST_STAGES.get(q, {}).get(stage, stage))), 16))
		window_body.add_child(HSeparator.new())
	window_body.add_child(UI.label_w(Loc.t("Zapiski"), 18, UI.BRASS))
	for i in range(GameState.journal.size() - 1, -1, -1):
		window_body.add_child(UI.label_w("• " + GameState.journal[i], 15))


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
	for n in [portrait, combat_bar, dialogue_panel, window, log_box.get_parent(), menu_box]:
		if n.visible and n.get_global_rect().has_point(mp):
			return true
	return false
