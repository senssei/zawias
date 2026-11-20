# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name AIBasic
extends RefCounted
## Prosta AI wrogów i towarzyszy: wybierz cel, podejdź, zaatakuj; użyj zdolności specjalnych.
## Postacie z klasą (towarzysze) rzucają ofensywne sztuczki (np. Fire Bolt), zanim sięgną po broń.


static func take_turn(mgr: CombatManager, c: Creature) -> void:
	var target := _pick_target(mgr, c)
	if target == null:
		return
	var opts := Attack.options(c)
	var melee := {}
	var ranged := {}
	var special := {}
	for o in opts:
		if o.has("special"):
			if not c.effects.get("breath_used", false):
				special = o
		elif o.get("ranged", false):
			ranged = o
		elif melee.is_empty():
			melee = o

	# Zdolność specjalna (oddech) gdy cel blisko
	if not special.is_empty():
		var dist := CombatGrid.distance(c.grid_pos, target.grid_pos)
		if dist > int(special.range):
			_approach(mgr, c, target, int(special.range))
			dist = CombatGrid.distance(c.grid_pos, target.grid_pos)
		if dist <= int(special.range) and mgr.grid.has_los(c.grid_pos, target.grid_pos) and int(mgr.turn.action) > 0:
			mgr.turn.action = 0
			c.effects["breath_used"] = true
			var res := Attack.resolve_special(c, target, special)
			for l in res.lines:
				mgr._log(l)
			mgr._after_damage(target, int(res.damage))
			mgr._emit({"type": "condition", "id": target.id})
			return

	var cantrip := _attack_cantrip(c)
	if cantrip != "":
		var sp := Spellcasting.spell(cantrip)
		# z dystansu: sztuczka; przy wrogu obok najpierw odsuń się, jeśli to bezpieczne (bez okazji do ataku)
		if mgr.can_cast(c, cantrip, target.grid_pos) != "":
			_approach(mgr, c, target, int(sp.get("range", 12)))
		if mgr.can_cast(c, cantrip, target.grid_pos) == "":
			mgr.cast(c, cantrip, target.grid_pos)
			return

	var dist := CombatGrid.distance(c.grid_pos, target.grid_pos)
	var use_ranged := false
	if not ranged.is_empty():
		# strzelaj, gdy cel jest daleko, a my nie stoimy obok wroga
		use_ranged = melee.is_empty() or (dist > int(mgr.turn.move) + 1 and not mgr.adjacent_hostile(c))
	if use_ranged and mgr.can_attack(c, ranged, target) == "":
		_attack_all(mgr, c, ranged, target)
		return
	if melee.is_empty():
		if not ranged.is_empty():
			_approach(mgr, c, target, int(ranged.range))
			if mgr.can_attack(c, ranged, target) == "":
				_attack_all(mgr, c, ranged, target)
		return
	if dist > int(melee.reach):
		_approach(mgr, c, target, int(melee.reach))
	if mgr.can_attack(c, melee, target) == "":
		_attack_all(mgr, c, melee, target)
	elif not ranged.is_empty() and mgr.can_attack(c, ranged, target) == "":
		_attack_all(mgr, c, ranged, target)
	elif int(mgr.turn.action) > 0 and int(mgr.turn.move) <= 0:
		mgr.do_action(c, "dash")
		var want := int(melee.reach)
		if not ranged.is_empty() and not mgr.grid.has_los(c.grid_pos, target.grid_pos):
			want = 1
		_approach(mgr, c, target, want)


## Najmocniejsza ofensywna sztuczka (rzut ataku albo rzut obronny przeciw wrogowi), "" gdy brak.
static func _attack_cantrip(c: Creature) -> String:
	if c.kind == "monster":
		return ""
	var best := ""
	var best_dmg := 0.0
	for sid in c.cantrips:
		var sp := Spellcasting.spell(sid)
		if sp.get("target", "") != "enemy" or not sp.get("type", "") in ["attack", "save"]:
			continue
		var dmg := Dice.average(str(sp.get("damage", "0")))
		if dmg > best_dmg:
			best_dmg = dmg
			best = sid
	return best


static func _attack_all(mgr: CombatManager, c: Creature, opt: Dictionary, target: Creature) -> void:
	var n := 0
	while n < 4 and mgr.active and target.is_conscious() and mgr.can_attack(c, opt, target) == "":
		mgr.attack(c, opt, target)
		n += 1
		if int(mgr.turn.attacks_left) <= 0:
			break


static func _pick_target(mgr: CombatManager, c: Creature) -> Creature:
	var best: Creature = null
	var best_score := 1e9
	for h in mgr.hostiles_of(c):
		if not h.is_conscious():
			continue
		var score: float = CombatGrid.distance(c.grid_pos, h.grid_pos) * 10.0 + h.hp
		if score < best_score:
			best_score = score
			best = h
	return best


## Podejdź do celu na odległość `want` (pola), wybierając najbliższe osiągalne pole.
static func _approach(mgr: CombatManager, c: Creature, target: Creature, want: int) -> void:
	var reach := mgr.reachable_for(c)
	var best := c.grid_pos
	var best_d := CombatGrid.distance(c.grid_pos, target.grid_pos)
	var best_cost := 0
	for p in reach.keys():
		if not p is Vector2i:
			continue
		var d := CombatGrid.distance(p, target.grid_pos)
		var cost := int(reach[p].cost)
		if d < want and want > 1:
			continue
		if d < best_d or (d == best_d and cost < best_cost):
			best = p
			best_d = d
			best_cost = cost
	if best != c.grid_pos:
		mgr.move(c, best)
