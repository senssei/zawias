extends Control
## Kreator postaci zgodny z SRD 5.2: gatunek, tło (premie do cech i atut), klasa, point-buy, umiejętności.

signal done(pc: Creature)
signal back

var st := {
	"name": Loc.t("Wędrowiec"), "species": "human", "background": "soldier", "class": "fighter",
	"scores": {"str": 15, "dex": 14, "con": 13, "int": 10, "wis": 10, "cha": 8},
	"bonus_mode": "2-1", "plus2": "str", "plus1": "con",
	"skills": [], "extra_skill": "", "choice": "",
}

var _ability_box: VBoxContainer
var _bonus_box: VBoxContainer
var _skills_box: VBoxContainer
var _choice_box: VBoxContainer
var _summary: RichTextLabel
var _desc: RichTextLabel
var _points_label: Label
var _start_btn: Button
var _err_label: Label


func _ready() -> void:
	UI.fit_to_viewport(self)
	theme = UI.theme()
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var root := UI.vbox(10)
	margin.add_child(root)
	root.add_child(UI.label(Loc.t("Nowa postać"), 36, UI.BRASS))

	var cols := UI.hbox(16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# --- kolumna 1: tożsamość
	var c1 := _column(cols, 360)
	c1.add_child(UI.label(Loc.t("Imię"), 15, UI.MUTED))
	var name_edit := LineEdit.new()
	name_edit.text = st.name
	name_edit.text_changed.connect(func(t): st.name = t; _refresh())
	c1.add_child(name_edit)
	c1.add_child(_option_row(Loc.t("Gatunek"), "species", DB.table("species")))
	c1.add_child(_option_row(Loc.t("Tło"), "background", DB.table("backgrounds")))
	c1.add_child(_option_row(Loc.t("Klasa"), "class", DB.table("classes")))
	_choice_box = UI.vbox(4)
	c1.add_child(_choice_box)
	_desc = RichTextLabel.new()
	_desc.bbcode_enabled = true
	_desc.fit_content = true
	_desc.custom_minimum_size.y = 200
	c1.add_child(_desc)

	# --- kolumna 2: cechy i umiejętności
	var c2 := _column(cols, 420)
	_points_label = UI.label("", 16, UI.BRASS)
	c2.add_child(_points_label)
	_ability_box = UI.vbox(2)
	c2.add_child(_ability_box)
	var preset := UI.hbox()
	preset.add_child(UI.button(Loc.t("Tablica standardowa"), _apply_standard))
	preset.add_child(UI.button(Loc.t("Wyzeruj (8)"), func():
		for ab in Abilities.LIST:
			st.scores[ab] = 8
		_refresh()))
	c2.add_child(preset)
	c2.add_child(HSeparator.new())
	_bonus_box = UI.vbox(4)
	c2.add_child(_bonus_box)
	c2.add_child(HSeparator.new())
	_skills_box = UI.vbox(2)
	c2.add_child(_skills_box)

	# --- kolumna 3: podsumowanie
	var c3 := _column(cols, 0)
	c3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c3.add_child(_summary)

	var bottom := UI.hbox(12)
	root.add_child(bottom)
	bottom.add_child(UI.button(Loc.t("Wstecz"), func(): back.emit(), 140))
	_err_label = UI.label_w("", 15, UI.BAD)
	_err_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_err_label)
	_start_btn = UI.button(Loc.t("Rozpocznij przygodę"), _finish, 260)
	_start_btn.custom_minimum_size.y = 44
	bottom.add_child(_start_btn)
	_on_class_changed()


func _column(parent: Control, w: int) -> VBoxContainer:
	var p := UI.panel()
	if w > 0:
		p.custom_minimum_size.x = w
	else:
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var v := UI.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	return v


func _option_row(title: String, key: String, table: Dictionary) -> Control:
	var v := UI.vbox(2)
	v.add_child(UI.label(title, 15, UI.MUTED))
	var ob := OptionButton.new()
	var ids := table.keys()
	for i in ids.size():
		ob.add_item(table[ids[i]].name, i)
		if ids[i] == st[key]:
			ob.select(i)
	ob.item_selected.connect(func(i):
		st[key] = ids[i]
		if key == "class":
			_on_class_changed()
		elif key == "background":
			var abs_: Array = DB.entry("backgrounds", st.background).abilities
			st.plus2 = abs_[0]
			st.plus1 = abs_[1]
			_refresh()
		else:
			_refresh())
	v.add_child(ob)
	return v


func _on_class_changed() -> void:
	var cls := DB.entry("classes", st["class"])
	st.skills = []
	st.choice = cls.choice.options.keys()[0] if cls.has("choice") else ""
	_apply_standard()


func _apply_standard() -> void:
	var cls := DB.entry("classes", st["class"])
	var order: Array = cls.primary.duplicate()
	order.append("con")
	for ab in ["dex", "wis", "str", "cha", "int"]:
		if not ab in order:
			order.append(ab)
	for i in order.size():
		st.scores[order[i]] = Abilities.STANDARD_ARRAY[i]
	var bg_abs: Array = DB.entry("backgrounds", st.background).abilities
	st.plus2 = cls.primary[0] if cls.primary[0] in bg_abs else bg_abs[0]
	st.plus1 = "con" if "con" in bg_abs and st.plus2 != "con" else bg_abs[1] if bg_abs[1] != st.plus2 else bg_abs[2]
	_refresh()


func _granted_skills() -> Array:
	var out: Array = DB.entry("backgrounds", st.background).get("skills", []).duplicate()
	out.append_array(DB.entry("species", st.species).get("skills", []))
	return out


func _opts() -> Dictionary:
	var bonus := {}
	var bg_abs: Array = DB.entry("backgrounds", st.background).abilities
	if st.bonus_mode == "2-1":
		bonus[st.plus2] = 2
		bonus[st.plus1] = int(bonus.get(st.plus1, 0)) + 1
	else:
		for ab in bg_abs:
			bonus[ab] = 1
	return {
		"name": st.name if st.name.strip_edges() != "" else Loc.t("Bezimienny"),
		"species": st.species, "background": st.background, "class": st["class"],
		"scores": st.scores, "bonus": bonus, "skills": st.skills,
		"extra_skill": st.extra_skill, "choice": st.choice,
	}


func _refresh() -> void:
	var cls := DB.entry("classes", st["class"])
	var sp := DB.entry("species", st.species)
	var bg := DB.entry("backgrounds", st.background)

	# Opis
	_desc.text = "[color=#d9a85b]%s[/color]: %s\n\n[color=#d9a85b]%s[/color]: %s\n\n[color=#d9a85b]%s[/color]: %s" % [
		sp.name, sp.desc, bg.name, bg.desc, cls.name, cls.desc]

	# Wybór klasowy
	UI.clear(_choice_box)
	if cls.has("choice"):
		var ch: Dictionary = cls.choice
		_choice_box.add_child(UI.label(ch.label, 15, UI.MUTED))
		var ob := OptionButton.new()
		var keys: Array = ch.options.keys()
		for i in keys.size():
			ob.add_item(ch.options[keys[i]].name, i)
			ob.set_item_tooltip(i, ch.options[keys[i]].desc)
			if keys[i] == st.choice:
				ob.select(i)
		ob.item_selected.connect(func(i): st.choice = keys[i]; _refresh())
		_choice_box.add_child(ob)
		_choice_box.add_child(UI.label_w(ch.options[st.choice].desc, 14, UI.MUTED))

	# Cechy (point-buy)
	UI.clear(_ability_box)
	var cost := Abilities.point_buy_cost(st.scores)
	_points_label.text = Loc.t("Rozdział punktów: %d / %d") % [cost, Abilities.POINT_BUY_BUDGET]
	_points_label.add_theme_color_override("font_color", UI.BAD if cost > Abilities.POINT_BUY_BUDGET else UI.BRASS)
	var preview := CharacterBuilder.build(_opts())
	for ab in Abilities.LIST:
		var row := UI.hbox(8)
		var nm := UI.label(Loc.t(str(Abilities.NAMES[ab])), 16)
		nm.custom_minimum_size.x = 130
		row.add_child(nm)
		row.add_child(UI.button("−", func():
			st.scores[ab] = maxi(8, int(st.scores[ab]) - 1)
			_refresh(), 32))
		var base_l := UI.label(str(st.scores[ab]), 16, UI.TEXT)
		base_l.custom_minimum_size.x = 30
		base_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(base_l)
		row.add_child(UI.button("+", func():
			st.scores[ab] = mini(15, int(st.scores[ab]) + 1)
			_refresh(), 32))
		var fin := int(preview.scores[ab])
		var fl := UI.label("→ %d (%s)" % [fin, Abilities.fmt_mod(Abilities.modifier(fin))], 16,
			UI.BRASS if fin != int(st.scores[ab]) else UI.TEXT)
		row.add_child(fl)
		_ability_box.add_child(row)

	# Premie z tła
	UI.clear(_bonus_box)
	var bg_abs: Array = bg.abilities
	_bonus_box.add_child(UI.label_w(Loc.t("Premie z tła (%s): %s") % [bg.name, ", ".join(bg_abs.map(func(a): return Loc.t(str(Abilities.SHORT[a]))))], 15, UI.MUTED))
	var mode_row := UI.hbox()
	var m1 := CheckBox.new()
	m1.text = "+2 / +1"
	m1.button_pressed = st.bonus_mode == "2-1"
	m1.toggled.connect(func(on): if on: st.bonus_mode = "2-1"; _refresh())
	var m2 := CheckBox.new()
	m2.text = "+1 / +1 / +1"
	m2.button_pressed = st.bonus_mode == "1-1-1"
	m2.toggled.connect(func(on): if on: st.bonus_mode = "1-1-1"; _refresh())
	var grp := ButtonGroup.new()
	m1.button_group = grp
	m2.button_group = grp
	mode_row.add_child(m1)
	mode_row.add_child(m2)
	_bonus_box.add_child(mode_row)
	if st.bonus_mode == "2-1":
		var r := UI.hbox()
		r.add_child(UI.label("+2:", 15))
		r.add_child(_ability_picker(bg_abs, "plus2"))
		r.add_child(UI.label("+1:", 15))
		r.add_child(_ability_picker(bg_abs, "plus1"))
		_bonus_box.add_child(r)

	# Umiejętności
	UI.clear(_skills_box)
	var granted := _granted_skills()
	var sc: Dictionary = cls.skill_choices
	_skills_box.add_child(UI.label_w(Loc.t("Umiejętności klasowe: wybierz %d (%d/%d)") % [int(sc.count), st.skills.size(), int(sc.count)], 15, UI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	for sk in sc.from:
		var cb := CheckBox.new()
		cb.text = Loc.t(str(Abilities.SKILL_NAMES[sk]))
		if sk in granted:
			cb.button_pressed = true
			cb.disabled = true
			cb.tooltip_text = Loc.t("Już z tła lub gatunku")
		else:
			cb.button_pressed = sk in st.skills
			cb.disabled = not cb.button_pressed and st.skills.size() >= int(sc.count)
			cb.toggled.connect(func(on):
				if on and not sk in st.skills:
					st.skills.append(sk)
				elif not on:
					st.skills.erase(sk)
				_refresh())
		grid.add_child(cb)
	_skills_box.add_child(grid)
	if sp.has("extra_skill"):
		_skills_box.add_child(UI.label_w(Loc.t("Wszechstronność (człowiek): dodatkowa umiejętność"), 15, UI.MUTED))
		var ob := OptionButton.new()
		ob.add_item(Loc.t("(brak)"), 0)
		var all_sk := Abilities.SKILLS.keys()
		for i in all_sk.size():
			ob.add_item(Loc.t(str(Abilities.SKILL_NAMES[all_sk[i]])), i + 1)
			if all_sk[i] == st.extra_skill:
				ob.select(i + 1)
		ob.item_selected.connect(func(i): st.extra_skill = "" if i == 0 else all_sk[i - 1]; _refresh())
		_skills_box.add_child(ob)
	else:
		st.extra_skill = ""

	_summary.text = sheet_bbcode(preview)
	_validate(cost, int(sc.count))


func _ability_picker(options: Array, key: String) -> OptionButton:
	var ob := OptionButton.new()
	for i in options.size():
		ob.add_item(Loc.t(str(Abilities.SHORT[options[i]])), i)
		if options[i] == st[key]:
			ob.select(i)
	ob.item_selected.connect(func(i): st[key] = options[i]; _refresh())
	return ob


func _validate(cost: int, need_skills: int) -> void:
	var err := ""
	if cost > Abilities.POINT_BUY_BUDGET:
		err = Loc.t("Przekroczono budżet punktów (%d/27).") % cost
	elif st.skills.size() < need_skills:
		err = Loc.t("Wybierz jeszcze %d umiejętności.") % (need_skills - st.skills.size())
	elif st.bonus_mode == "2-1" and st.plus2 == st.plus1:
		err = Loc.t("Premie +2 i +1 muszą trafić do różnych cech.")
	_err_label.text = err
	_start_btn.disabled = err != ""


func _finish() -> void:
	done.emit(CharacterBuilder.build(_opts()))


## Karta postaci w BBCode (używana też w grze).
static func sheet_bbcode(c: Creature) -> String:
	var cls := DB.entry("classes", c.class_id)
	var s := ""
	s += "[font_size=26][color=#d9a85b]%s[/color][/font_size]\n" % c.name
	var sub := ""
	if c.subclass_id != "":
		sub = " (%s)" % DB.entry("subclasses", c.subclass_id).name
	s += Loc.t("%s, %s%s, poziom %d, %s\n") % [DB.entry("species", c.species_id).get("name", "?"), cls.get("name", "?"), sub, c.level, DB.entry("backgrounds", c.background_id).get("name", "?")]
	s += Loc.t("PD: %d / %d\n\n") % [c.xp, Abilities.XP_THRESHOLDS[mini(c.level, Abilities.XP_THRESHOLDS.size() - 1)]]
	s += Loc.t("[b]PW[/b] %d/%d    [b]KP[/b] %d    [b]Inicjatywa[/b] %s    [b]Szybkość[/b] %d stóp    [b]Biegłość[/b] +%d\n") % [
		c.hp, c.max_hp, c.ac(), Abilities.fmt_mod(c.initiative_bonus()), c.speed, c.prof_bonus()]
	if c.heroic_inspiration:
		s += Loc.t("[color=#9b7fd1]★ Heroiczna inspiracja[/color]\n")
	s += "\n"
	for ab in Abilities.LIST:
		var save_mark := "●" if ab in c.save_profs else "○"
		s += Loc.t("[b]%s[/b] %d (%s)   rzut obr. %s %s\n") % [Loc.t(str(Abilities.SHORT[ab])), c.scores[ab], Abilities.fmt_mod(c.mod(ab)), save_mark, Abilities.fmt_mod(c.save_bonus(ab))]
	s += Loc.t("\n[color=#d9a85b]Umiejętności[/color]\n")
	var sk_list := []
	for sk in Abilities.SKILLS.keys():
		if sk in c.skill_profs or sk in c.expertise:
			sk_list.append("%s %s%s" % [Loc.t(str(Abilities.SKILL_NAMES[sk])), Abilities.fmt_mod(Checks.skill_bonus(c, sk)), " ★" if sk in c.expertise else ""])
	s += ", ".join(sk_list) + "\n"
	s += Loc.t("Pasywna Percepcja: %d\n") % c.passive("perception")
	s += Loc.t("\n[color=#d9a85b]Ataki[/color]\n")
	for o in Attack.options(c):
		var rng := Loc.t(" zasięg %d/%d m") % [int(o.range) * 1.5, int(o.long_range) * 1.5] if o.ranged else ""
		s += Loc.t("%s: %s do trafienia, %s%s %s%s%s\n") % [o.name, Abilities.fmt_mod(int(o.bonus)), o.dice, Abilities.fmt_mod(int(o.dmg_bonus)),
			Loc.t(str(Attack.DAMAGE_NAMES.get(o.damage_type, ""))), rng, (Loc.t("  [color=#9b7fd1]opanowanie: %s[/color]") % o.mastery) if o.mastery != "" else ""]
	var known := Spellcasting.known(c)
	if not known.is_empty():
		s += Loc.t("\n[color=#d9a85b]Czary[/color] (ST %d, atak %s)\n") % [c.spell_save_dc(), Abilities.fmt_mod(c.spell_attack_bonus())]
		var cantrips := []
		var leveled := []
		for sid in known:
			var sp := DB.entry("spells", sid)
			if sp.is_empty():
				continue
			(cantrips if int(sp.level) == 0 else leveled).append(sp.name)
		s += Loc.t("Sztuczki: %s\n") % ", ".join(cantrips)
		if not leveled.is_empty():
			s += Loc.t("Krąg 1+: %s\n") % ", ".join(leveled)
		var sl := []
		for k in c.slots.keys():
			sl.append(Loc.t("krąg %s: %d/%d") % [k, int(c.slots[k].cur), int(c.slots[k].max)])
		if not sl.is_empty():
			s += Loc.t("Miejsca: %s\n") % ", ".join(sl)
	s += Loc.t("\n[color=#d9a85b]Cechy[/color]\n")
	for f in c.features:
		var fd := DB.entry("features", f)
		s += "[b]%s[/b]: [color=#a89584]%s[/color]\n" % [fd.get("name", f), fd.get("desc", "")]
	for k in c.resources.keys():
		s += "%s: %d/%d\n" % [DB.entry("features", k).get("name", k), int(c.resources[k].cur), int(c.resources[k].max)]
	s += Loc.t("\n[color=#d9a85b]Wyposażenie[/color]\n")
	var eq := []
	if c.armor_id != "":
		eq.append(DB.entry("armor", c.armor_id).name)
	if c.shield:
		eq.append(Loc.t("Tarcza"))
	for w in c.weapons:
		eq.append(DB.entry("weapons", w).name)
	s += ", ".join(eq) + "\n"
	return s
