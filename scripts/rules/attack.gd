# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name Attack
extends RefCounted
## Ataki bronią i ataki potworów: trafienie, krytyki, obrażenia, Weapon Mastery (SRD 5.2).

const DAMAGE_NAMES := {
	"slashing": "cięte", "piercing": "kłute", "bludgeoning": "obuchowe", "fire": "od ognia",
	"cold": "od zimna", "radiant": "od promieniowania", "necrotic": "nekrotyczne", "force": "od mocy",
	"poison": "od trucizny", "lightning": "od błyskawic", "thunder": "od grzmotu", "psychic": "psychiczne",
}


static func is_proficient(c: Creature, w: Dictionary) -> bool:
	var cat: String = w.get("category", "simple")
	if cat in c.weapon_profs:
		return true
	var props: Array = w.get("properties", [])
	if cat == "martial" and "martial_finesse_light" in c.weapon_profs:
		return "finesse" in props or "light" in props
	return false


static func weapon_option(c: Creature, weapon_id: String) -> Dictionary:
	var w := DB.entry("weapons", weapon_id)
	if w.is_empty():
		return {}
	var props: Array = w.get("properties", [])
	var ranged := "ranged" in props
	var finesse := "finesse" in props
	var ability := "str"
	if ranged:
		ability = "dex"
	elif finesse and c.mod("dex") > c.mod("str"):
		ability = "dex"
	var amod := c.mod(ability)
	var bonus := amod + (c.prof_bonus() if is_proficient(c, w) else 0)
	var style: String = c.choices.get("fighting_style", "")
	if ranged and style == "archery":
		bonus += 2
	var dice: String = w.damage
	var two_handed := "two_handed" in props
	if "versatile" in props and not c.shield:
		dice = w.get("versatile", dice)
		two_handed = true
	var dmg_bonus := amod
	if style == "dueling" and not ranged and not two_handed:
		dmg_bonus += 2
	return {
		"kind": "weapon", "id": weapon_id, "name": w.name, "bonus": bonus,
		"dice": dice, "dmg_bonus": dmg_bonus, "damage_type": w.type, "ability_mod": amod,
		"reach": 1, "range": int(w.get("range", 1)) if ranged else 1,
		"long_range": int(w.get("long_range", 0)) if ranged else 0,
		"ranged": ranged, "finesse": finesse,
		"gwf": style == "great_weapon" and two_handed and not ranged,
		"mastery": w.get("mastery", "") if (weapon_id in c.mastery) else "",
	}


static func monster_option(c: Creature, atk: Dictionary) -> Dictionary:
	var dmg := str(atk.get("damage", "1"))
	var p := Dice.parse(dmg if dmg != "" else "0")   # zdolność bez obrażeń (np. oddech oślepiający)
	var ranged := atk.has("range")
	var opt := {
		"kind": "monster", "id": atk.name, "name": atk.name, "bonus": int(atk.get("bonus", 0)) + Difficulty.monster_to_hit(),
		"dice": "%dd%d" % [int(p.count), int(p.sides)] if int(p.count) > 0 else "0",
		"dmg_bonus": int(p.bonus), "damage_type": atk.get("type", "bludgeoning"), "ability_mod": 0,
		"reach": int(atk.get("reach", 1)), "range": int(atk.get("range", 1)),
		"long_range": int(atk.get("long_range", 0)), "ranged": ranged, "finesse": false, "gwf": false,
		"mastery": "", "extra": atk.get("extra", ""), "extra_type": atk.get("extra_type", ""),
	}
	if atk.get("special", "") != "":
		opt["special"] = atk.special
		opt["data"] = atk
	return opt


## Wszystkie opcje ataku stworzenia (bez specjalnych).
static func options(c: Creature) -> Array:
	var out := []
	if c.kind == "monster":
		for atk in c.monster_attacks:
			out.append(monster_option(c, atk))
	else:
		for wid in c.weapons:
			var o := weapon_option(c, wid)
			if not o.is_empty():
				out.append(o)
		if out.is_empty():
			out.append(weapon_option(c, "unarmed"))
	return out


## Przewaga i utrudnienie z warunków. ctx może zawierać: adv/dis (tablice opisów), distance.
static func compute_mode(attacker: Creature, target: Creature, ranged: bool, ctx: Dictionary = {}) -> Dictionary:
	var adv: Array = ctx.get("adv", []).duplicate()
	var dis: Array = ctx.get("dis", []).duplicate()
	var dist := int(ctx.get("distance", 1))
	if attacker.has_condition("prone"):
		dis.append(Loc.t("leżysz"))
	if attacker.has_condition("poisoned"):
		dis.append("zatrucie")
	if attacker.has_condition("frightened"):
		dis.append("strach")
	if attacker.has_condition("blinded"):
		dis.append(Loc.t("oślepienie"))
	if attacker.has_condition("restrained"):
		dis.append("unieruchomienie")
	if attacker.effects.get("sapped", false):
		dis.append("Sap")
	if attacker.effects.get("jammed", false) and not ctx.get("spell", false):
		dis.append(Loc.t("zacięta broń"))
	if attacker.effects.get("hidden", false):
		adv.append("ukryty")
	if attacker.effects.get("steady_aim", false):
		adv.append(Loc.t("Pewny cel"))
	if attacker.effects.get("vex_target", "") == target.id:
		adv.append("Vex")
	if target.has_condition("prone"):
		if dist <= 1 and not ranged:
			adv.append(Loc.t("cel leży"))
		else:
			dis.append(Loc.t("cel leży"))
	if target.has_condition("unconscious") or target.has_condition("paralyzed"):
		adv.append(Loc.t("cel bezbronny"))
	if target.has_condition("restrained") or target.has_condition("blinded"):
		adv.append(Loc.t("cel unieruchomiony/oślepiony"))
	if target.effects.get("guided", false):
		adv.append(Loc.t("Prowadzący pocisk"))
	if target.effects.get("dodging", false) and target.can_act():
		dis.append("unik")
	return {"mode": Dice.combine_mode(not adv.is_empty(), not dis.is_empty()), "adv": adv, "dis": dis}


static func crit_min(attacker: Creature, opt: Dictionary) -> int:
	if opt.get("kind", "") == "weapon" and attacker.has_feature("improved_critical"):
		return 19
	return 20


static func hit_chance(bonus: int, ac: int, mode: int, crit_from: int = 20) -> float:
	var faces := 0
	for f in range(1, 21):
		if f == 1:
			continue
		if f >= crit_from or f + bonus >= ac:
			faces += 1
	var p := faces / 20.0
	if mode > 0:
		return 1.0 - (1.0 - p) * (1.0 - p)
	if mode < 0:
		return p * p
	return p


static func roll_damage(dice: String, mult: int, gwf := false) -> Dictionary:
	if dice == "0" or dice == "":
		return {"total": 0, "rolls": []}
	var p := Dice.parse(dice)
	var rolls: Array[int] = Dice.roll(int(p.count) * mult, int(p.sides))
	var t := 0
	for i in rolls.size():
		if gwf and rolls[i] < 3:
			rolls[i] = 3
		t += rolls[i]
	return {"total": t + int(p.bonus), "rolls": rolls}


static func can_cast_shield(target: Creature) -> bool:
	return "shield" in target.spells and target.slot_available(1) and target.can_act() \
		and not target.effects.get("reaction_used", false) and not target.effects.get("shield_spell", false)


## Rozstrzyga atak. turn: słownik stanu tury napastnika (sneak_used, savage_used).
## ctx: adv, dis, distance, sneak_ally (sojusznik obok celu).
static func resolve(attacker: Creature, target: Creature, opt: Dictionary, ctx: Dictionary = {}, turn: Dictionary = {}) -> Dictionary:
	var lines: Array[String] = []
	var m := compute_mode(attacker, target, opt.get("ranged", false), ctx)
	var r := Dice.d20(int(m.mode))
	var nat := int(r.natural)
	var cmin := crit_min(attacker, opt)
	var bless := Dice.roll_die(4) if attacker.effects.has("bless") else 0
	var total := nat + int(opt.bonus) + bless
	var ac := target.ac() + (5 if target.effects.get("shield_spell", false) else 0)
	var crit := nat >= cmin
	var hit := nat != 1 and (crit or total >= ac)

	var mode_txt := ""
	if int(m.mode) == 1:
		mode_txt = Loc.t(" [przewaga: %s]") % ", ".join(m.adv)
	elif int(m.mode) == -1:
		mode_txt = Loc.t(" [utrudnienie: %s]") % ", ".join(m.dis)
	var bless_txt := Loc.t(" +%d (błog.)") % bless if bless > 0 else ""
	lines.append(Loc.t("%s atakuje %s (%s): k20 %s %s%s = %d vs KP %d%s") % [
		attacker.name, target.name, opt.name, str(r.rolls) if r.rolls.size() > 1 else str(nat),
		Abilities.fmt_mod(int(opt.bonus)), bless_txt, total, ac, mode_txt])

	# Reakcja: Tarcza
	if hit and nat < 20 and total < ac + 5 and can_cast_shield(target):
		target.use_slot(1)
		target.effects["shield_spell"] = true
		target.effects["reaction_used"] = true
		hit = false
		crit = false
		lines.append(Loc.t("%s rzuca Tarczę (+5 KP) i atak chybia!") % target.name)

	# Zużycie jednorazowych efektów
	if attacker.effects.get("vex_target", "") == target.id:
		attacker.effects.erase("vex_target")
	attacker.effects.erase("sapped")
	attacker.effects.erase("jammed")
	attacker.effects.erase("hidden")
	attacker.effects.erase("hide_dc")
	attacker.effects.erase("steady_aim")
	target.effects.erase("guided")

	var res := {"hit": hit, "crit": false, "natural": nat, "total": total, "damage": 0, "lines": lines, "push": 0}
	if not hit:
		lines.append(Loc.t("  Pudło%s.") % (Loc.t(" krytyczne (1)") if nat == 1 else ""))
		if opt.get("mastery", "") == "graze" and int(opt.ability_mod) > 0:
			var gd := target.take_damage(int(opt.ability_mod), opt.damage_type)
			res.damage = gd
			lines.append(Loc.t("  Graze: %s otrzymuje %d obrażeń.") % [target.name, gd])
		return res

	if not opt.get("ranged", false) and int(ctx.get("distance", 1)) <= 1 \
			and (target.has_condition("unconscious") or target.has_condition("paralyzed")):
		crit = true
	res.crit = crit
	var mult := 2 if crit else 1
	var dmg := roll_damage(opt.dice, mult, opt.get("gwf", false))
	if opt.kind == "weapon" and attacker.has_feature("savage_attacker") and not turn.get("savage_used", false):
		var alt := roll_damage(opt.dice, mult, opt.get("gwf", false))
		turn["savage_used"] = true
		if int(alt.total) > int(dmg.total):
			dmg = alt
	var amount := int(dmg.total) + int(opt.dmg_bonus)
	var parts: Array[String] = ["%s%s" % [str(dmg.rolls), Abilities.fmt_mod(int(opt.dmg_bonus))]]

	# Atak z zaskoczenia
	if attacker.has_feature("sneak_attack") and not turn.get("sneak_used", false) \
			and (opt.get("finesse", false) or opt.get("ranged", false)) \
			and (int(m.mode) == 1 or (ctx.get("sneak_ally", false) and int(m.mode) != -1)):
		var sd := ceili(attacker.level / 2.0)
		var sneak := roll_damage("%dd6" % sd, mult)
		amount += int(sneak.total)
		turn["sneak_used"] = true
		parts.append(Loc.t("atak z zaskoczenia %s") % str(sneak.rolls))
	amount = maxi(1, amount)
	var dealt := target.take_damage(amount, opt.damage_type, crit)
	var extra_dealt := 0
	if opt.get("extra", "") != "":
		var ex := roll_damage(opt.extra, mult)
		extra_dealt = target.take_damage(int(ex.total), opt.extra_type, crit)
	res.damage = dealt + extra_dealt
	lines.append(Loc.t("  %s! %d obrażeń %s%s (%s)") % [
		Loc.t("TRAFIENIE KRYTYCZNE") if crit else Loc.t("Trafienie"), dealt, Loc.t(str(DAMAGE_NAMES.get(opt.damage_type, opt.damage_type))),
		(" + %d %s" % [extra_dealt, Loc.t(str(DAMAGE_NAMES.get(opt.extra_type, "")))]) if extra_dealt > 0 else "",
		", ".join(parts)])

	# Weapon Mastery
	if target.is_alive():
		match opt.get("mastery", ""):
			"vex":
				attacker.effects["vex_target"] = target.id
				lines.append(Loc.t("  Vex: następny atak %s na ten cel ma przewagę.") % attacker.name)
			"sap":
				target.effects["sapped"] = true
				lines.append(Loc.t("  Sap: %s ma utrudnienie w następnym ataku.") % target.name)
			"slow":
				target.effects["slowed"] = true
				lines.append(Loc.t("  Slow: szybkość %s spada o 3 m.") % target.name)
			"topple":
				var dc := 8 + int(opt.ability_mod) + attacker.prof_bonus()
				var sv := Checks.saving_throw(target, "con", dc)
				lines.append(Loc.t("  Topple: ") + sv.text)
				if not sv.success:
					target.add_condition("prone")
					lines.append(Loc.t("  %s pada na ziemię!") % target.name)
			"push":
				res.push = 2
	return res


## Specjalne zdolności potworów (np. oddech).
static func resolve_special(attacker: Creature, target: Creature, opt: Dictionary) -> Dictionary:
	var data: Dictionary = opt.data
	var lines: Array[String] = [Loc.t("%s używa: %s!") % [attacker.name, data.name]]
	var sv := Checks.saving_throw(target, data.save, int(data.dc), data.get("condition", ""))
	lines.append("  " + target.name + " " + sv.text)
	var dealt := 0
	if data.get("damage", "") != "":
		var d := Dice.roll_expr(data.damage)
		var amount: int = d.total if not sv.success else floori(int(d.total) / 2.0)
		dealt = target.take_damage(amount, data.get("type", ""))
		lines.append(Loc.t("  %d obrażeń.") % dealt)
	if not sv.success and data.get("condition", "") != "":
		if target.add_condition(data.condition, int(data.get("rounds", 1))):
			lines.append("  %s: %s!" % [target.name, DB.entry("conditions", data.condition).get("name", data.condition)])
	return {"lines": lines, "damage": dealt}
