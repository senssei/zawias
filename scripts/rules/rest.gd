# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name Rest
extends RefCounted
## Krótki i długi odpoczynek (SRD 5.2).


static func short_rest(c: Creature) -> Array[String]:
	var lines: Array[String] = [Loc.t("%s odpoczywa krótko.") % c.name]
	var spent := 0
	var healed := 0
	while c.hp < c.max_hp and c.hit_dice > 0 and not c.dead:
		var r := Dice.roll_die(c.hit_die) + c.mod("con")
		c.hit_dice -= 1
		spent += 1
		healed += c.heal(maxi(0, r))
	if spent > 0:
		lines.append(Loc.t("  Wydano %d kości wytrzymałości i odzyskano %d PW.") % [spent, healed])
	for k in c.resources.keys():
		var res: Dictionary = c.resources[k]
		var cls_res: Dictionary = DB.entry("classes", c.class_id).get("resources", {}).get(k, {})
		if res.get("recharge", "long") == "short":
			res.cur = res.max
		elif cls_res.has("short_regain"):
			res.cur = mini(int(res.max), int(res.cur) + int(cls_res.short_regain))
	if c.has_feature("arcane_recovery") and c.resource("arcane_recovery") > 0:
		var budget := ceili(c.level / 2.0)
		var recovered := []
		for lvl in range(5, 0, -1):
			var key := str(lvl)
			while c.slots.has(key) and int(c.slots[key].cur) < int(c.slots[key].max) and budget >= lvl:
				c.slots[key].cur = int(c.slots[key].cur) + 1
				budget -= lvl
				recovered.append(lvl)
		if not recovered.is_empty():
			c.use_resource("arcane_recovery")
			lines.append(Loc.t("  Arkaniczne odnowienie: odzyskano miejsca na czary %s.") % str(recovered))
	c.effects.clear()
	return lines


static func long_rest(c: Creature) -> Array[String]:
	if c.dead:
		return []
	c.hp = c.max_hp
	c.temp_hp = 0
	c.hit_dice = c.level
	for k in c.resources.keys():
		c.resources[k].cur = c.resources[k].max
	for k in c.slots.keys():
		c.slots[k].cur = c.slots[k].max
	c.conditions.clear()
	c.effects.clear()
	c.concentration = ""
	c.death_saves = {"success": 0, "fail": 0}
	var lines: Array[String] = [Loc.t("%s odpoczywa długo. Odzyskuje wszystkie PW, zasoby i miejsca na czary.") % c.name]
	if c.has_feature("resourceful") and not c.heroic_inspiration:
		c.heroic_inspiration = true
		lines.append(Loc.t("  Zaradność: dostajesz Heroiczną inspirację."))
	return lines
