class_name Checks
extends RefCounted
## Testy cech i umiejętności oraz rzuty obronne.


static func check_mode(c: Creature, skill: String = "", adv := false, dis := false) -> int:
	if c.has_condition("poisoned") or c.has_condition("frightened"):
		dis = true
	if skill == "stealth" and c.armor_id != "" and DB.entry("armor", c.armor_id).get("stealth_disadvantage", false):
		dis = true
	if skill == "athletics" and c.has_feature("remarkable_athlete"):
		adv = true
	return Dice.combine_mode(adv, dis)


static func skill_bonus(c: Creature, skill: String) -> int:
	var b := c.skill_bonus(skill)
	if c.choices.get("divine_order", "") == "thaumaturge" and skill in ["arcana", "religion"]:
		b += maxi(1, c.mod("wis"))
	return b


static func skill_check(c: Creature, skill: String, dc: int, adv := false, dis := false) -> Dictionary:
	var mode := check_mode(c, skill, adv, dis)
	var r := Dice.d20(mode)
	var bonus := skill_bonus(c, skill)
	var total := int(r.natural) + bonus
	var res := {
		"success": total >= dc, "total": total, "natural": r.natural, "rolls": r.rolls,
		"bonus": bonus, "dc": dc, "mode": mode, "label": Loc.t(str(Abilities.SKILL_NAMES.get(skill, skill))),
	}
	res["text"] = format(res)
	return res


static func ability_check(c: Creature, ability: String, dc: int, adv := false, dis := false) -> Dictionary:
	var mode := check_mode(c, "", adv, dis)
	var r := Dice.d20(mode)
	var bonus := c.mod(ability)
	var total := int(r.natural) + bonus
	var res := {
		"success": total >= dc, "total": total, "natural": r.natural, "rolls": r.rolls,
		"bonus": bonus, "dc": dc, "mode": mode, "label": Loc.t(str(Abilities.NAMES.get(ability, ability))),
	}
	res["text"] = format(res)
	return res


## vs: stan, przed którym chroni rzut (np. "poisoned", "charmed") — daje przewagi rasowe.
static func saving_throw(c: Creature, ability: String, dc: int, vs: String = "", adv := false, dis := false) -> Dictionary:
	if ability in ["str", "dex"] and (c.has_condition("unconscious") or c.has_condition("paralyzed")):
		var auto := {"success": false, "total": 0, "natural": 0, "rolls": [], "bonus": 0, "dc": dc, "mode": 0,
			"label": Loc.t("Rzut obronny (%s)") % Loc.t(str(Abilities.SHORT[ability]))}
		auto["text"] = Loc.t("%s: automatyczna porażka") % auto.label
		return auto
	if vs == "poisoned" and c.has_feature("dwarven_resilience"):
		adv = true
	if vs == "charmed" and c.has_feature("fey_ancestry"):
		adv = true
	if ability == "dex" and c.effects.get("dodging", false):
		adv = true
	if ability == "dex" and c.has_condition("restrained"):
		dis = true
	var mode := Dice.combine_mode(adv, dis)
	var r := Dice.d20(mode)
	var bonus := c.save_bonus(ability)
	var extra := 0
	if c.effects.has("bless"):
		extra = Dice.roll_die(4)
	var total := int(r.natural) + bonus + extra
	var res := {
		"success": total >= dc, "total": total, "natural": r.natural, "rolls": r.rolls,
		"bonus": bonus + extra, "dc": dc, "mode": mode,
		"label": Loc.t("Rzut obronny (%s)") % Loc.t(str(Abilities.SHORT[ability])),
	}
	res["text"] = format(res)
	return res


static func format(res: Dictionary) -> String:
	var mode_txt := ""
	if int(res.mode) == 1:
		mode_txt = Loc.t(" przew. %s") % str(res.rolls)
	elif int(res.mode) == -1:
		mode_txt = Loc.t(" utrudn. %s") % str(res.rolls)
	return Loc.t("%s: %d (k20 %d%s %s) vs ST %d: %s") % [
		res.label, res.total, res.natural, mode_txt, Abilities.fmt_mod(int(res.bonus)), res.dc,
		Loc.t("SUKCES") if res.success else Loc.t("PORAŻKA"),
	]
