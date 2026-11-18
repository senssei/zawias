class_name CombatManager
extends RefCounted
## Turowa walka na siatce: inicjatywa, ekonomia akcji, ataki okazyjne, czary.
## Logika jest natychmiastowa; scena odtwarza wydarzenia z sygnału `event` po kolei.

signal event(e: Dictionary)

var grid: CombatGrid
var combatants: Array[Creature] = []
var order: Array[Creature] = []
var turn_index := -1
var round_num := 0
var active := false
var finished := false
var victory := false
var turn := {}
var max_loop := 200


func _init(g: CombatGrid) -> void:
	grid = g


# ------------------------------------------------------------------ start

func start(party: Array, enemies: Array, party_surprised := false) -> void:
	combatants.clear()
	for c in party + enemies:
		combatants.append(c)
		c.effects.clear()
	active = true
	finished = false
	round_num = 1
	var rolls := {}
	for c in combatants:
		var dis := party_surprised and c.team == "party"
		var adv := c.has_feature("remarkable_athlete")
		var r := Dice.d20(Dice.combine_mode(adv, dis))
		rolls[c.id] = int(r.natural) + c.initiative_bonus()
		_log(Loc.t("Inicjatywa %s: %d (k20 %s %s)%s") % [c.name, rolls[c.id], str(r.rolls),
			Abilities.fmt_mod(c.initiative_bonus()), Loc.t(" — zaskoczenie!") if dis else ""])
	order.assign(combatants.duplicate())
	order.sort_custom(func(a, b):
		if rolls[a.id] == rolls[b.id]:
			return a.mod("dex") > b.mod("dex")
		return rolls[a.id] > rolls[b.id])
	_emit({"type": "initiative", "order": order.map(func(c): return c.id)})
	turn_index = -1
	_advance()


func current() -> Creature:
	if turn_index < 0 or turn_index >= order.size():
		return null
	return order[turn_index]


func find(id: String) -> Creature:
	for c in combatants:
		if c.id == id:
			return c
	return null


func creature_at(p: Vector2i) -> Creature:
	for c in combatants:
		if c.is_alive() and c.grid_pos == p:
			return c
	return null


# ------------------------------------------------------------------ tury

func _advance() -> void:
	var guard := 0
	while active and guard < max_loop:
		guard += 1
		if _check_end():
			return
		turn_index += 1
		if turn_index >= order.size():
			turn_index = 0
			round_num += 1
			_log(Loc.t("— Runda %d —") % round_num)
		var c := current()
		if c.dead:
			continue
		_start_turn(c)
		if c.dead or _check_end():
			if not active:
				return
			continue
		if not c.can_act():
			_end_turn_cleanup(c)
			continue
		if c.is_player or c.team == "party":
			_emit({"type": "turn", "id": c.id, "round": round_num, "player": true})
			return
		_emit({"type": "turn", "id": c.id, "round": round_num, "player": false})
		AIBasic.take_turn(self, c)
		_end_turn_cleanup(c)


func _start_turn(c: Creature) -> void:
	c.effects.erase("dodging")
	c.effects.erase("shield_spell")
	c.effects.erase("reaction_used")
	turn = {"id": c.id, "action": 1, "bonus": 1, "move": c.movement_tiles(), "moved": false,
		"attacks_left": 0, "sneak_used": false, "savage_used": false, "disengaged": false}
	# Rzuty przeciw śmierci
	if c.kind == "pc" and c.hp <= 0 and not c.dead and not c.stable:
		var r := Dice.roll_die(20)
		if r == 20:
			c.heal(1)
			_log(Loc.t("%s: rzut przeciw śmierci 20 — odzyskuje przytomność!") % c.name)
		elif r == 1:
			c.death_saves.fail += 2
		elif r >= 10:
			c.death_saves.success += 1
		else:
			c.death_saves.fail += 1
		if r != 20:
			_log(Loc.t("%s: rzut przeciw śmierci %d (sukcesy %d, porażki %d)") % [c.name, r, c.death_saves.success, c.death_saves.fail])
		if c.death_saves.fail >= 3:
			c.dead = true
			_log(Loc.t("%s umiera.") % c.name)
			_emit({"type": "death", "id": c.id})
		elif c.death_saves.success >= 3:
			c.stable = true
			_log(Loc.t("%s stabilizuje się.") % c.name)
		_emit_hp(c)
	# Wstawanie: kosztuje połowę ruchu
	if c.is_conscious() and c.has_condition("prone") and not c.has_condition("unconscious"):
		c.remove_condition("prone")
		turn.move = int(turn.move) - c.movement_tiles() / 2
		_log(Loc.t("%s wstaje.") % c.name)
		_emit({"type": "condition", "id": c.id})
	# Odnowienie oddechu
	if c.effects.get("breath_used", false):
		if Dice.roll_die(6) >= 6:
			c.effects.erase("breath_used")


func _end_turn_cleanup(c: Creature) -> void:
	c.effects.erase("slowed")
	if c.effects.has("held") and c.is_alive():
		var h: Dictionary = c.effects.held
		var sv := Checks.saving_throw(c, h.save, int(h.dc))
		_log(Loc.t("%s próbuje się uwolnić: %s") % [c.name, sv.text])
		if sv.success:
			c.remove_condition(h.condition)
			c.effects.erase("held")
			c.effects.erase("held_by")
			_emit({"type": "condition", "id": c.id})
	for k in c.conditions.keys():
		var r := int(c.conditions[k])
		if r > 0:
			r -= 1
			if r == 0:
				c.conditions.erase(k)
				if k == "unconscious":
					c.effects.erase("magical_sleep")
				_log(Loc.t("%s: koniec stanu %s.") % [c.name, DB.entry("conditions", k).get("name", k)])
				_emit({"type": "condition", "id": c.id})
			else:
				c.conditions[k] = r


func end_turn() -> void:
	if not active:
		return
	var c := current()
	if c:
		_end_turn_cleanup(c)
	_advance()


func _check_end() -> bool:
	if not active:
		return true
	var party_up := false
	var enemies_up := false
	for c in combatants:
		if c.team == "party" and c.is_conscious():
			party_up = true
		if c.team == "enemy" and c.is_conscious():
			enemies_up = true
	if party_up and enemies_up:
		return false
	active = false
	finished = true
	victory = party_up
	var xp := 0
	if victory:
		for c in combatants:
			if c.team == "enemy":
				xp += c.xp_value
	_log(Loc.t("ZWYCIĘSTWO!") if victory else Loc.t("Twoja drużyna padła..."))
	_emit({"type": "end", "victory": victory, "xp": xp})
	return true


# ------------------------------------------------------------------ zapytania

func is_my_turn(c: Creature) -> bool:
	return active and current() == c


func hostiles_of(c: Creature) -> Array:
	return combatants.filter(func(o): return o.is_alive() and o.is_hostile_to(c))


func allies_of(c: Creature) -> Array:
	return combatants.filter(func(o): return o.is_alive() and o != c and o.team == c.team)


func _blocked_for(c: Creature) -> Dictionary:
	var b := {}
	for o in combatants:
		if o != c and o.is_alive() and o.is_hostile_to(c) and o.is_conscious():
			b[o.grid_pos] = true
	return b


func _no_stop_for(c: Creature) -> Dictionary:
	var b := {}
	for o in combatants:
		if o != c and o.is_alive():
			b[o.grid_pos] = true
	return b


func reachable_for(c: Creature) -> Dictionary:
	return grid.reachable(c.grid_pos, int(turn.get("move", 0)), _blocked_for(c), _no_stop_for(c))


func adjacent_hostile(c: Creature) -> bool:
	for o in hostiles_of(c):
		if o.can_act() and CombatGrid.distance(o.grid_pos, c.grid_pos) <= 1:
			return true
	return false


func attack_context(attacker: Creature, target: Creature, ranged: bool, range_n: int, long_range: int) -> Dictionary:
	var dist := CombatGrid.distance(attacker.grid_pos, target.grid_pos)
	var ctx := {"distance": dist, "adv": [], "dis": []}
	if ranged:
		if adjacent_hostile(attacker):
			ctx.dis.append(Loc.t("wróg obok"))
		if dist > range_n and long_range > 0:
			ctx.dis.append(Loc.t("daleki zasięg"))
	var ally_adj := false
	for a in allies_of(attacker):
		if a.can_act() and CombatGrid.distance(a.grid_pos, target.grid_pos) <= 1:
			ally_adj = true
	ctx["sneak_ally"] = ally_adj
	ctx["all"] = combatants
	return ctx


## Zwraca "" gdy atak możliwy, inaczej powód.
func can_attack(c: Creature, opt: Dictionary, target: Creature) -> String:
	if not is_my_turn(c):
		return Loc.t("To nie twoja tura")
	if int(turn.attacks_left) <= 0 and int(turn.action) <= 0:
		return Loc.t("Brak akcji")
	if target == null or not target.is_alive() or not target.is_hostile_to(c):
		return Loc.t("Niepoprawny cel")
	var dist := CombatGrid.distance(c.grid_pos, target.grid_pos)
	if opt.get("ranged", false):
		var maxr := int(opt.long_range) if int(opt.long_range) > 0 else int(opt.range)
		if dist > maxr:
			return Loc.t("Poza zasięgiem")
		if not grid.has_los(c.grid_pos, target.grid_pos):
			return Loc.t("Brak linii wzroku")
	elif dist > int(opt.reach):
		return Loc.t("Za daleko")
	return ""


func hit_chance(c: Creature, opt: Dictionary, target: Creature) -> float:
	var ctx := attack_context(c, target, opt.get("ranged", false), int(opt.range), int(opt.long_range))
	var m := Attack.compute_mode(c, target, opt.get("ranged", false), ctx)
	return Attack.hit_chance(int(opt.bonus), target.ac(), int(m.mode), Attack.crit_min(c, opt))


# ------------------------------------------------------------------ akcje

func move(c: Creature, dest: Vector2i) -> String:
	if not is_my_turn(c):
		return Loc.t("To nie twoja tura")
	var reach := reachable_for(c)
	if not reach.has(dest) or dest == c.grid_pos:
		return Loc.t("Poza zasięgiem ruchu")
	var path := CombatGrid.path_to(reach, c.grid_pos, dest)
	if path.size() < 2:
		return Loc.t("Brak ścieżki")
	_walk(c, path)
	_check_end()
	return ""


func _walk(c: Creature, path: Array[Vector2i]) -> void:
	var walked: Array[Vector2i] = [path[0]]
	for i in range(1, path.size()):
		var from := path[i - 1]
		var to := path[i]
		turn.move = int(turn.move) - grid.step_cost(to)
		# Ataki okazyjne przy opuszczaniu zasięgu
		if not turn.get("disengaged", false):
			for h in hostiles_of(c):
				if not h.can_act() or h.effects.get("reaction_used", false):
					continue
				if CombatGrid.distance(h.grid_pos, from) <= 1 and CombatGrid.distance(h.grid_pos, to) > 1:
					var melee := _melee_option(h)
					if melee.is_empty():
						continue
					if walked.size() > 1:
						_emit({"type": "move", "id": c.id, "path": walked.duplicate()})
						walked = [from]
					h.effects["reaction_used"] = true
					_log(Loc.t("Atak okazyjny!"))
					_do_attack_resolve(h, c, melee)
					if not c.is_conscious():
						return
		c.grid_pos = to
		walked.append(to)
	turn.moved = true
	if walked.size() > 1:
		_emit({"type": "move", "id": c.id, "path": walked})


func _melee_option(c: Creature) -> Dictionary:
	for o in Attack.options(c):
		if not o.get("ranged", false) and not o.has("special"):
			return o
	return {}


func attack(c: Creature, opt: Dictionary, target: Creature) -> String:
	var err := can_attack(c, opt, target)
	if err != "":
		return err
	if int(turn.attacks_left) <= 0:
		turn.action = int(turn.action) - 1
		turn.attacks_left = c.multiattack if c.kind == "monster" else 1
	turn.attacks_left = int(turn.attacks_left) - 1
	_do_attack_resolve(c, target, opt)
	_check_end()
	return ""


func _do_attack_resolve(c: Creature, target: Creature, opt: Dictionary) -> void:
	var ctx := attack_context(c, target, opt.get("ranged", false), int(opt.range), int(opt.long_range))
	var res := Attack.resolve(c, target, opt, ctx, turn if current() == c else {})
	_emit({"type": "attack", "id": c.id, "target": target.id, "hit": res.hit, "ranged": opt.get("ranged", false)})
	for l in res.lines:
		_log(l)
	_after_damage(target, int(res.damage), res.hit)
	if int(res.push) > 0 and target.is_alive():
		_push(c, target, int(res.push))


func _push(from: Creature, target: Creature, tiles: int) -> void:
	var dir := target.grid_pos - from.grid_pos
	dir = Vector2i(signi(dir.x), signi(dir.y))
	var path: Array[Vector2i] = [target.grid_pos]
	for i in tiles:
		var n := target.grid_pos + dir
		if not grid.is_open(n) or creature_at(n) != null:
			break
		target.grid_pos = n
		path.append(n)
	if path.size() > 1:
		_log(Loc.t("Push: %s zostaje odepchnięty.") % target.name)
		_emit({"type": "move", "id": target.id, "path": path})


func _after_damage(target: Creature, dealt: int, show := true) -> void:
	if dealt > 0 or show:
		_emit_hp(target, dealt)
	if dealt > 0:
		for l in Spellcasting.concentration_check(target, dealt, combatants):
			_log(l)
	if target.dead:
		_log(Loc.t("%s pada martwy.") % target.name)
		_emit({"type": "death", "id": target.id})
		if target.concentration != "":
			for l in Spellcasting.end_concentration(target, combatants):
				_log(l)
	elif not target.is_conscious():
		_emit({"type": "condition", "id": target.id})


func _emit_hp(c: Creature, dealt: int = 0) -> void:
	_emit({"type": "hp", "id": c.id, "hp": c.hp, "max": c.max_hp, "amount": dealt})


## Cele czaru dla wskazanego pola.
func spell_targets(c: Creature, spell_id: String, cell: Vector2i) -> Array:
	var sp := Spellcasting.spell(spell_id)
	var area: Dictionary = sp.get("area", {})
	var out := []
	if area.is_empty():
		var t := creature_at(cell)
		if t:
			out.append(t)
		return out
	if area.shape == "sphere":
		for o in combatants:
			if o.is_alive() and CombatGrid.distance(o.grid_pos, cell) <= int(area.radius):
				# „istoty według wyboru” (np. Uśpienie): rzucający pomija siebie i sojuszników
				if sp.get("choose", false) and not o.is_hostile_to(c):
					continue
				out.append(o)
	elif area.shape == "cone":
		var dir := Vector2(cell - c.grid_pos).normalized()
		for o in combatants:
			if o == c or not o.is_alive():
				continue
			var d := CombatGrid.distance(c.grid_pos, o.grid_pos)
			if d < 1 or d > int(area.length):
				continue
			var v := Vector2(o.grid_pos - c.grid_pos).normalized()
			if dir.dot(v) >= 0.7 and grid.has_los(c.grid_pos, o.grid_pos):
				out.append(o)
	return out


func can_cast(c: Creature, spell_id: String, cell: Vector2i) -> String:
	if not is_my_turn(c):
		return Loc.t("To nie twoja tura")
	var err := Spellcasting.can_cast(c, spell_id)
	if err != "":
		return err
	var sp := Spellcasting.spell(spell_id)
	if sp.cast == "bonus":
		if int(turn.bonus) <= 0:
			return Loc.t("Brak akcji dodatkowej")
	elif int(turn.action) <= 0 or int(turn.attacks_left) > 0 and int(turn.action) <= 0:
		return Loc.t("Brak akcji")
	var dist := CombatGrid.distance(c.grid_pos, cell)
	if dist > int(sp.get("range", 1)):
		return Loc.t("Poza zasięgiem")
	if dist > 0 and not grid.has_los(c.grid_pos, cell):
		return Loc.t("Brak linii wzroku")
	var targets := spell_targets(c, spell_id, cell)
	if sp.get("target", "") == "enemy" and (targets.is_empty() or not targets[0].is_hostile_to(c)):
		return Loc.t("Wskaż wroga")
	if sp.get("target", "") == "ally" and (targets.is_empty() or targets[0].is_hostile_to(c)):
		return Loc.t("Wskaż sojusznika")
	return ""


func cast(c: Creature, spell_id: String, cell: Vector2i, slot: int = 0) -> String:
	var err := can_cast(c, spell_id, cell)
	if err != "":
		return err
	var sp := Spellcasting.spell(spell_id)
	if sp.cast == "bonus":
		turn.bonus = int(turn.bonus) - 1
	else:
		turn.action = int(turn.action) - 1
	var targets := spell_targets(c, spell_id, cell)
	var ctx := {"all": combatants}
	if not targets.is_empty() and sp.type == "attack":
		ctx = attack_context(c, targets[0], true, int(sp.range), 0)
	if slot > 0:
		ctx["slot"] = slot
	_emit({"type": "spell", "id": c.id, "spell": spell_id, "cell": [cell.x, cell.y]})
	var res := Spellcasting.cast(c, spell_id, targets, ctx)
	for l in res.lines:
		_log(l)
	for pair in res.damaged:
		_after_damage(pair[0], int(pair[1]))
	for t in targets:
		_emit_hp(t)
		_emit({"type": "condition", "id": t.id})
	_check_end()
	return ""


## Akcje specjalne. Zwraca "" przy sukcesie.
func do_action(c: Creature, action_id: String, target: Creature = null) -> String:
	if not is_my_turn(c):
		return Loc.t("To nie twoja tura")
	var cost := action_cost(c, action_id)
	if cost == "":
		return Loc.t("Niedostępne")
	if cost == "action" and int(turn.action) <= 0:
		return Loc.t("Brak akcji")
	if cost == "bonus" and int(turn.bonus) <= 0:
		return Loc.t("Brak akcji dodatkowej")
	match action_id:
		"dash", "cunning_dash":
			turn.move = int(turn.move) + c.movement_tiles()
			_log(Loc.t("%s wykonuje Sprint.") % c.name)
		"disengage", "cunning_disengage":
			turn.disengaged = true
			_log(Loc.t("%s odstępuje (bez ataków okazyjnych).") % c.name)
		"dodge":
			c.effects["dodging"] = true
			_log(Loc.t("%s robi Unik.") % c.name)
		"hide", "cunning_hide":
			if adjacent_hostile(c):
				return Loc.t("Wróg stoi obok")
			var r := Checks.skill_check(c, "stealth", 15)
			_log(Loc.t("%s próbuje się ukryć. %s") % [c.name, r.text])
			if r.success:
				c.effects["hidden"] = true
		"second_wind":
			if not c.use_resource("second_wind"):
				return Loc.t("Brak użyć")
			var d := Dice.roll_expr("1d10+%d" % c.level)
			var h := c.heal(int(d.total))
			_log(Loc.t("%s łapie Drugi oddech: +%d PW %s.") % [c.name, h, str(d.rolls)])
			_emit({"type": "heal", "id": c.id, "amount": h})
			_emit_hp(c)
		"action_surge":
			if not c.use_resource("action_surge"):
				return Loc.t("Brak użyć")
			turn.action = int(turn.action) + 1
			_log(Loc.t("%s: Przypływ działania! Dodatkowa akcja.") % c.name)
		"steady_aim":
			if turn.moved:
				return Loc.t("Już się poruszyłeś")
			c.effects["steady_aim"] = true
			turn.move = 0
			_log(Loc.t("%s celuje spokojnie (przewaga w następnym ataku).") % c.name)
		"potion":
			if not "potion_healing" in c.inventory:
				return Loc.t("Brak mikstur")
			c.inventory.erase("potion_healing")
			var d2 := Dice.roll_expr("2d4+2")
			var h2 := c.heal(int(d2.total))
			_log(Loc.t("%s pije Miksturę leczenia: +%d PW.") % [c.name, h2])
			_emit({"type": "heal", "id": c.id, "amount": h2})
			_emit_hp(c)
		"divine_spark":
			if target == null:
				return Loc.t("Wskaż cel")
			if CombatGrid.distance(c.grid_pos, target.grid_pos) > 6:
				return Loc.t("Poza zasięgiem")
			if not c.use_resource("channel_divinity"):
				return Loc.t("Brak użyć")
			var d3 := Dice.roll_expr("1d8+%d" % c.mod("wis"))
			if target.is_hostile_to(c):
				var sv := Checks.saving_throw(target, "con", c.spell_save_dc())
				var amount: int = d3.total if not sv.success else floori(int(d3.total) / 2.0)
				_log(Loc.t("%s: Boska iskra! %s") % [c.name, sv.text])
				var dealt := target.take_damage(amount, "radiant")
				_log(Loc.t("  %d obrażeń od promieniowania.") % dealt)
				_after_damage(target, dealt)
			else:
				var h3 := target.heal(int(d3.total))
				_log(Loc.t("%s: Boska iskra leczy %s o %d PW.") % [c.name, target.name, h3])
				_emit_hp(target)
		_:
			return Loc.t("Nieznana akcja")
	if cost == "action":
		turn.action = int(turn.action) - 1
	elif cost == "bonus":
		turn.bonus = int(turn.bonus) - 1
	_emit({"type": "condition", "id": c.id})
	_check_end()
	return ""


## Lista akcji dostępnych dla postaci: [{id, name, cost}]
func available_actions(c: Creature) -> Array:
	var ids := ["dash", "disengage", "dodge", "hide"]
	if c.has_feature("cunning_action"):
		ids.append_array(["cunning_dash", "cunning_disengage", "cunning_hide"])
	for f in ["second_wind", "action_surge", "steady_aim", "divine_spark"]:
		if c.has_feature(f):
			ids.append(f)
	if "potion_healing" in c.inventory:
		ids.append("potion")
	var out := []
	for id_ in ids:
		out.append({"id": id_, "name": Loc.t(str(ACTION_NAMES.get(id_, id_))), "cost": action_cost(c, id_)})
	return out


const ACTION_NAMES := {
	"dash": "Sprint", "disengage": "Odstąpienie", "dodge": "Unik", "hide": "Ukrycie się",
	"cunning_dash": "Sprint (spryt)", "cunning_disengage": "Odstąpienie (spryt)", "cunning_hide": "Ukrycie (spryt)",
	"second_wind": "Drugi oddech", "action_surge": "Przypływ działania", "steady_aim": "Pewny cel",
	"divine_spark": "Boska iskra", "potion": "Mikstura leczenia",
}


func action_cost(c: Creature, action_id: String) -> String:
	match action_id:
		"dash", "disengage", "dodge", "hide", "divine_spark":
			return "action"
		"cunning_dash", "cunning_disengage", "cunning_hide", "second_wind", "steady_aim", "potion":
			return "bonus"
		"action_surge":
			return "free"
	return ""


# ------------------------------------------------------------------ pomocnicze

func _log(text: String) -> void:
	_emit({"type": "log", "text": text})


func _emit(e: Dictionary) -> void:
	event.emit(e)
