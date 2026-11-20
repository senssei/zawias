# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name Spellcasting
extends RefCounted
## Rzucanie czarów: ataki czarem, rzuty obronne, leczenie, koncentracja.


static func spell(id: String) -> Dictionary:
	return DB.entry("spells", id)


static func known(c: Creature) -> Array:
	var out := []
	for s in c.cantrips + c.spells:
		if not s in out:
			out.append(s)
	return out


## Czary, które da się rzucić w walce (pomija użytkowe i reakcje).
static func combat_spells(c: Creature) -> Array:
	var out := []
	for s in known(c):
		var sp := spell(s)
		if sp.is_empty() or sp.type in ["utility", "reaction"]:
			continue
		out.append(s)
	return out


static func cantrip_dice_mult(c: Creature) -> int:
	var lvl := c.level
	return 1 + int(lvl >= 5) + int(lvl >= 11) + int(lvl >= 17)


static func can_cast(c: Creature, spell_id: String) -> String:
	var sp := spell(spell_id)
	if sp.is_empty():
		return Loc.t("Nieznany czar")
	if not c.can_act():
		return Loc.t("Nie możesz działać")
	if int(sp.level) > 0 and c.lowest_slot(int(sp.level)) == 0:
		return Loc.t("Brak miejsc na czary")
	return ""


static func _scaled_dice(c: Creature, sp: Dictionary, slot: int) -> String:
	var p := Dice.parse(sp.get("damage", sp.get("heal", "0")))
	var count := int(p.count)
	if int(sp.level) == 0 and sp.get("cantrip_scaling", false):
		count *= cantrip_dice_mult(c)
	if sp.has("upcast") and slot > int(sp.level):
		var up := Dice.parse(sp.upcast)
		count += int(up.count) * (slot - int(sp.level))
	return "%dd%d" % [count, int(p.sides)] if count > 0 else "0"


## Rzuca czar. targets: lista celów (po wyliczeniu obszaru przez wywołującego).
## ctx: "adv"/"dis"/"distance" dla ataków czarem, "all": wszyscy uczestnicy (do koncentracji).
static func cast(caster: Creature, spell_id: String, targets: Array, ctx: Dictionary = {}) -> Dictionary:
	var sp := spell(spell_id)
	var lines: Array[String] = []
	var lvl := int(sp.level)
	var slot := 0
	if lvl > 0:
		slot = int(ctx.get("slot", caster.lowest_slot(lvl)))
		if not caster.use_slot(slot):
			return {"ok": false, "lines": [Loc.t("Brak miejsc na czary.")], "damaged": []}
	lines.append(Loc.t("%s rzuca %s%s.") % [caster.name, sp.name, (Loc.t(" (krąg %d)") % slot) if slot > 0 else ""])
	if sp.get("concentration", false):
		if caster.concentration != "":
			lines.append_array(end_concentration(caster, ctx.get("all", [])))
		caster.concentration = spell_id
	var damaged := []  # [creature, dealt]
	var d20_rolls := []
	var attack_hit := false
	var potent := lvl == 0 and caster.has_feature("potent_cantrip")
	var dc := caster.spell_save_dc(spell_id)

	match sp.type:
		"attack":
			for t in targets:
				var m := Attack.compute_mode(caster, t, true, ctx.merged({"spell": true}))   # zacięta broń nie dotyczy czarów
				var r := Dice.d20(int(m.mode))
				d20_rolls.append({"id": caster.id, "natural": int(r.natural)})
				var bonus := caster.spell_attack_bonus(spell_id)
				var bless := Dice.roll_die(4) if caster.effects.has("bless") else 0
				var total := int(r.natural) + bonus + bless
				var ac: int = t.ac() + (5 if t.effects.get("shield_spell", false) else 0)
				var crit := int(r.natural) == 20
				var hit := int(r.natural) != 1 and (crit or total >= ac)
				attack_hit = attack_hit or hit
				caster.effects.erase("hidden")
				caster.effects.erase("hide_dc")
				t.effects.erase("guided")
				lines.append(Loc.t("  Atak czarem w %s: k20 %s %s = %d vs KP %d") % [t.name, str(r.rolls), Abilities.fmt_mod(bonus), total, ac])
				var dice := _scaled_dice(caster, sp, slot)
				if hit:
					var d := Attack.roll_damage(dice, 2 if crit else 1)
					var dealt: int = t.take_damage(int(d.total), sp.damage_type, crit)
					damaged.append([t, dealt])
					lines.append(Loc.t("  %s! %d obrażeń %s %s") % [Loc.t("KRYTYK") if crit else Loc.t("Trafienie"), dealt, Loc.t(str(Attack.DAMAGE_NAMES.get(sp.damage_type, ""))), str(d.rolls)])
					match sp.get("on_hit", ""):
						"slowed":
							t.effects["slowed"] = true
							lines.append(Loc.t("  Szybkość %s spada o 3 m.") % t.name)
						"guided":
							t.effects["guided"] = true
							lines.append(Loc.t("  %s lśni. Następny atak na niego ma przewagę.") % t.name)
				elif potent:
					var d2 := Attack.roll_damage(dice, 1)
					var dealt2: int = t.take_damage(floori(int(d2.total) / 2.0), sp.damage_type)
					damaged.append([t, dealt2])
					lines.append(Loc.t("  Pudło, ale Potężna sztuczka zadaje %d obrażeń.") % dealt2)
				else:
					lines.append(Loc.t("  Pudło."))
		"save":
			var dice := _scaled_dice(caster, sp, slot)
			var roll := Attack.roll_damage(dice, 1) if sp.has("damage") else {"total": 0, "rolls": []}
			for t in targets:
				if sp.get("condition", "") == "unconscious" and "no_sleep" in t.tags:
					lines.append(Loc.t("  %s jest odporny na magiczny sen.") % t.name)
					continue
				var sv := Checks.saving_throw(t, sp.save, dc)
				d20_rolls.append({"id": t.id, "natural": int(sv.natural)})
				lines.append("  %s %s" % [t.name, sv.text])
				if sp.has("damage"):
					var amount := int(roll.total)
					if sv.success:
						amount = floori(amount / 2.0) if (sp.get("half", false) or potent) else 0
					if amount > 0:
						var dealt: int = t.take_damage(amount, sp.damage_type)
						damaged.append([t, dealt])
						lines.append(Loc.t("    %d obrażeń %s %s") % [dealt, Loc.t(str(Attack.DAMAGE_NAMES.get(sp.damage_type, ""))), str(roll.rolls)])
				if not sv.success and sp.get("condition", "") != "":
					if t.add_condition(sp.condition, 10):
						if sp.condition == "unconscious":
							t.effects["magical_sleep"] = true
							t.effects["sleep_by"] = caster.id
						if sp.get("repeat_save", false):
							# np. Unieruchomienie osoby: rzut na końcu każdej tury celu, koniec z koncentracją
							t.effects["held_by"] = caster.id
							t.effects["held"] = {"condition": sp.condition, "save": sp.save, "dc": dc}
						lines.append("    %s: %s!" % [t.name, DB.entry("conditions", sp.condition).get("name", sp.condition)])
		"auto":
			var darts := int(sp.get("darts", 1)) + maxi(0, slot - lvl) * int(sp.get("upcast_darts", 0))
			for t in targets:
				if t.effects.get("shield_spell", false):
					lines.append(Loc.t("  Tarcza %s pochłania pociski.") % t.name)
					continue
				var total := 0
				var rolls := []
				for i in darts:
					var d := Dice.roll_expr(sp.damage)
					total += int(d.total)
					rolls.append(d.total)
				var dealt: int = t.take_damage(total, sp.damage_type)
				damaged.append([t, dealt])
				lines.append(Loc.t("  %d strzałek trafia %s: %d obrażeń od mocy %s") % [darts, t.name, dealt, str(rolls)])
		"heal":
			for t in targets:
				var d := Attack.roll_damage(_scaled_dice(caster, sp, slot), 1)
				var amount := int(d.total) + caster.spell_mod(spell_id)
				if caster.has_feature("disciple_of_life") and slot > 0:
					amount += 2 + slot
				var healed: int = t.heal(maxi(1, amount))
				lines.append(Loc.t("  %s odzyskuje %d PW %s.") % [t.name, healed, str(d.rolls)])
		"buff":
			for t in targets.slice(0, 3):
				t.effects[sp.effect] = caster.id
				lines.append(Loc.t("  %s jest pod wpływem: %s.") % [t.name, sp.name])
	return {"ok": true, "lines": lines, "damaged": damaged, "d20_rolls": d20_rolls, "attack_hit": attack_hit}


## Rzut na utrzymanie koncentracji po obrażeniach.
static func concentration_check(c: Creature, damage: int, all: Array) -> Array[String]:
	var lines: Array[String] = []
	if c.concentration == "" or damage <= 0:
		return lines
	if not c.is_conscious():
		lines.append_array(end_concentration(c, all))
		return lines
	var dc := mini(30, maxi(10, floori(damage / 2.0)))
	var sv := Checks.saving_throw(c, "con", dc)
	lines.append(Loc.t("  Koncentracja %s: %s") % [c.name, sv.text])
	if not sv.success:
		lines.append_array(end_concentration(c, all))
	return lines


static func end_concentration(c: Creature, all: Array) -> Array[String]:
	var lines: Array[String] = []
	if c.concentration == "":
		return lines
	var sp := spell(c.concentration)
	lines.append(Loc.t("  %s traci koncentrację na: %s.") % [c.name, sp.get("name", c.concentration)])
	for o in all:
		if o.effects.get("bless", "") == c.id:
			o.effects.erase("bless")
		if o.effects.get("held_by", "") == c.id:
			o.remove_condition(o.effects.get("held", {}).get("condition", "paralyzed"))
			o.effects.erase("held_by")
			o.effects.erase("held")
		if o.effects.get("sleep_by", "") == c.id:
			o.effects.erase("sleep_by")
			o.effects.erase("magical_sleep")
			o.remove_condition("unconscious")
			o.remove_condition("prone")
	c.concentration = ""
	return lines
