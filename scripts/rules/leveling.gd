class_name Leveling
extends RefCounted
## Awans: PD, cechy klasowe, miejsca na czary, podklasa na 3. poziomie.


## Nadaje cechy danego poziomu. Na 1. poziomie PW = kość + KON, potem średnia.
static func grant_level(c: Creature, lvl: int, hp_gain := -1, subclass := "") -> Array[String]:
	var lines: Array[String] = []
	var cls := DB.entry("classes", c.class_id)
	c.level = lvl
	var con := c.mod("con")
	var gain := 0
	if lvl == 1:
		gain = c.hit_die + con
	elif hp_gain >= 0:
		gain = maxi(1, hp_gain + con)
	else:
		gain = maxi(1, c.hit_die / 2 + 1 + con)
	if c.has_feature("dwarven_toughness") or "dwarven_toughness" in DB.entry("species", c.species_id).get("features", []):
		gain += 1
	c.max_hp += gain if lvl > 1 else 0
	if lvl == 1:
		c.max_hp = gain
	c.hp = c.max_hp if lvl == 1 else c.hp + gain
	c.hit_dice = mini(c.hit_dice + (1 if lvl > 1 else 0), lvl)
	if lvl == 1:
		c.hit_dice = 1

	var new_feats: Array = cls.get("features_by_level", {}).get(str(lvl), []).duplicate()
	if lvl >= 3 and c.subclass_id == "":
		c.subclass_id = subclass if subclass != "" else cls.get("subclass", "")
		if c.subclass_id != "":
			lines.append(Loc.t("  Podklasa: %s") % DB.entry("subclasses", c.subclass_id).get("name", c.subclass_id))
	if c.subclass_id != "":
		new_feats.append_array(DB.entry("subclasses", c.subclass_id).get("features_by_level", {}).get(str(lvl), []))
	for f in new_feats:
		if not f in c.features:
			c.features.append(f)
			lines.append(Loc.t("  Nowa cecha: %s") % DB.entry("features", f).get("name", f))

	for rid in cls.get("resources", {}).keys():
		var rdef: Dictionary = cls.resources[rid]
		var mx := int(rdef.max[mini(lvl, rdef.max.size()) - 1])
		if mx <= 0:
			continue
		var old: Dictionary = c.resources.get(rid, {"cur": 0, "max": 0})
		c.resources[rid] = {"cur": int(old.cur) + (mx - int(old.max)), "max": mx, "recharge": rdef.recharge}

	var slot_table: Dictionary = cls.get("slots_by_level", {}).get(str(lvl), {})
	for sl in slot_table.keys():
		var mx := int(slot_table[sl])
		var old: Dictionary = c.slots.get(sl, {"cur": 0, "max": 0})
		c.slots[sl] = {"cur": int(old.cur) + (mx - int(old.max)), "max": mx}
	if c.subclass_id == "life":
		for s in DB.entry("subclasses", "life").get("domain_spells", []):
			if not s in c.spells:
				c.spells.append(s)
	return lines


## Dodaje PD. Bez defer awansuje od razu (NPC, testy); z defer odkłada awanse do okna awansu
## (pending_levels), w którym gracz wybiera PW, podklasę i czary.
static func add_xp(c: Creature, amount: int, defer := false) -> Array[String]:
	var lines: Array[String] = []
	if amount <= 0:
		return lines
	c.xp += amount
	lines.append(Loc.t("%s zdobywa %d PD (razem %d).") % [c.name, amount, c.xp])
	var target := Abilities.level_for_xp(c.xp)
	if defer:
		var avail := target - c.level
		if avail > c.pending_levels:
			c.pending_levels = avail
			lines.append(Loc.t("AWANS! %s może osiągnąć poziom %d (okno awansu: przycisk przy portrecie).") % [c.name, c.level + 1])
		return lines
	while c.level < target:
		lines.append(Loc.t("AWANS! %s osiąga poziom %d.") % [c.name, c.level + 1])
		lines.append_array(grant_level(c, c.level + 1))
	return lines


## Co daje następny poziom i z czego gracz wybiera (dla okna awansu).
static func level_up_options(c: Creature) -> Dictionary:
	var lvl := c.level + 1
	var cls := DB.entry("classes", c.class_id)
	var feats: Array = cls.get("features_by_level", {}).get(str(lvl), []).duplicate()
	var subclasses: Array = []
	if lvl >= 3 and c.subclass_id == "":
		for sid in DB.table("subclasses").keys():
			if sid == cls.get("subclass", "") or DB.entry("subclasses", sid).get("class", "") == c.class_id:
				subclasses.append(sid)
	var sub: String = c.subclass_id if c.subclass_id != "" else (String(subclasses[0]) if not subclasses.is_empty() else "")
	if sub != "":
		feats.append_array(DB.entry("subclasses", sub).get("features_by_level", {}).get(str(lvl), []))
	var slots_after: Dictionary = cls.get("slots_by_level", {}).get(str(lvl), {})
	var max_slot := 0
	for k in slots_after.keys():
		if int(slots_after[k]) > 0:
			max_slot = maxi(max_slot, int(k))
	var choices: Array = []
	for sid in cls.get("spell_list", []):
		var sp := DB.entry("spells", sid)
		if not sid in c.spells and int(sp.get("level", 1)) <= max_slot:
			choices.append(sid)
	var con := c.mod("con")
	return {
		"level": lvl, "hit_die": c.hit_die, "con": con,
		"hp_avg": maxi(1, c.hit_die / 2 + 1 + con),
		"features": feats, "subclasses": subclasses,
		"slots": slots_after,
		"spell_choices": choices,
		"spell_picks": mini(int(cls.get("spells_per_level", 0)), choices.size()),
	}


## Wykonuje jeden oczekujący awans z wyborami: {"hp": "avg"|"roll", "subclass": id, "spells": [id...]}.
static func apply_level(c: Creature, choices: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if c.pending_levels <= 0:
		return lines
	var opts := level_up_options(c)
	var hp_gain := -1
	if choices.get("hp", "avg") == "roll":
		hp_gain = Dice.roll_die(c.hit_die)
		lines.append(Loc.t("  Rzut na PW: k%d = %d") % [c.hit_die, hp_gain])
	var hp_before := c.max_hp
	lines.append(Loc.t("AWANS! %s osiąga poziom %d.") % [c.name, opts.level])
	lines.append_array(grant_level(c, int(opts.level), hp_gain, choices.get("subclass", "")))
	lines.append(Loc.t("  Maksymalne PW: %d → %d") % [hp_before, c.max_hp])
	var picked := 0
	for sid in choices.get("spells", []):
		if sid in opts.spell_choices and not sid in c.spells and picked < int(opts.spell_picks):
			c.spells.append(sid)
			picked += 1
			lines.append(Loc.t("  Nowy czar: %s") % DB.entry("spells", sid).get("name", sid))
	c.pending_levels -= 1
	return lines
