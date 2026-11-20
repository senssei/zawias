# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name Creature
extends RefCounted
## Postać gracza albo potwór. Wszystkie statystyki według SRD 5.2.

var id := ""
var name := ""
var kind := "pc"            # "pc" | "monster"
var team := "enemy"         # "party" | "enemy" | "neutral"
var is_player := false
var template_id := ""       # id potwora z monsters.json albo NPC
var tags: Array = []        # np. "no_sleep", "undead"

# Pochodzenie i klasa
var species_id := ""
var background_id := ""
var class_id := ""
var subclass_id := ""
var level := 1
var xp := 0
var xp_value := 0           # XP za pokonanie (potwory)
var pending_levels := 0     # awanse czekające na wybory gracza (okno awansu)

# Statystyki
var scores := {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10}
var save_profs: Array = []
var skill_profs: Array = []
var expertise: Array = []
var weapon_profs: Array = []    # "simple", "martial", "martial_finesse_light"
var armor_profs: Array = []
var features: Array = []
var resources := {}             # id -> {"cur": int, "max": int, "recharge": "short"|"long"}
var choices := {}               # wybory z kreacji, np. {"fighting_style": "defense"}
var motivations := {}           # {"strength": "loyalty", "flaw": "greed", ...} (data/motivations.json, ADR 0009)

var max_hp := 1
var hp := 1
var temp_hp := 0
var hit_die := 8
var hit_dice := 1
var speed := 30
var darkvision := 0
var resistances: Array = []
var vulnerabilities: Array = []
var immunities: Array = []
var condition_immunities: Array = []

# Ekwipunek
var armor_id := ""
var shield := false
var weapons: Array = []         # id broni; pierwsza to główna
var mastery: Array = []         # bronie z opanowaniem (Weapon Mastery)
var inventory: Array = []       # id przedmiotów
var gold := 0

# Magia
var spell_ability := ""
var spell_ability_overrides := {}   # spell_id -> cecha (np. czary z gatunku)
var cantrips: Array = []
var spells: Array = []
var slots := {}                 # "1" -> {"cur": int, "max": int}
var concentration := ""         # id czaru, na którym się koncentruje
var heroic_inspiration := false

# Potwory
var monster_ac := 0
var monster_attacks: Array = []
var multiattack := 1

# Stan
var conditions := {}            # id -> rundy (-1 = bez limitu)
var effects := {}               # efekty walki: vex_target, sapped, guided, dodging, bless, hidden...
var death_saves := {"success": 0, "fail": 0}
var stable := false
var dead := false
var grid_pos := Vector2i.ZERO


func mod(ability: String) -> int:
	return Abilities.modifier(int(scores.get(ability, 10)))


func prof_bonus() -> int:
	if kind == "monster" and choices.has("pb"):
		return int(choices.pb)
	return Abilities.proficiency_bonus(level)


func save_bonus(ability: String) -> int:
	var b := mod(ability)
	if ability in save_profs:
		b += prof_bonus()
	return b


func skill_bonus(skill: String) -> int:
	var ab: String = Abilities.SKILLS.get(skill, "str")
	var b := mod(ab)
	if skill in expertise:
		b += prof_bonus() * 2
	elif skill in skill_profs:
		b += prof_bonus()
	elif has_feature("remarkable_athlete") and skill == "athletics":
		b += prof_bonus()
	return b


func passive(skill: String) -> int:
	return 10 + skill_bonus(skill)


func initiative_bonus() -> int:
	var b := mod("dex")
	if has_feature("alert"):
		b += prof_bonus()
	return b


func has_feature(f: String) -> bool:
	return f in features


func ac() -> int:
	if monster_ac > 0:
		return monster_ac
	var base := 10 + mod("dex")
	var armor := DB.entry("armor", armor_id) if armor_id != "" else {}
	if not armor.is_empty():
		var dex_max := int(armor.get("dex_max", -1))
		var dex := mod("dex")
		if dex_max == 0:
			dex = 0  # ciężka zbroja ignoruje Zręczność (także ujemną)
		elif dex_max > 0:
			dex = mini(dex, dex_max)
		base = int(armor.base) + dex
		if choices.get("fighting_style", "") == "defense":
			base += 1
	if shield:
		base += 2
	return base


func spell_mod(spell_id: String = "") -> int:
	var ab: String = spell_ability_overrides.get(spell_id, spell_ability)
	if ab == "":
		ab = "int"
	return mod(ab)


func spell_save_dc(spell_id: String = "") -> int:
	return 8 + prof_bonus() + spell_mod(spell_id)


func spell_attack_bonus(spell_id: String = "") -> int:
	return prof_bonus() + spell_mod(spell_id)


func movement_tiles() -> int:
	var s := speed
	if effects.get("slowed", false):
		s -= 10
	if has_condition("grappled") or has_condition("restrained"):
		s = 0
	return maxi(0, s / 5)


# --- Stan zdrowia ---

func is_alive() -> bool:
	return not dead


func is_conscious() -> bool:
	return not dead and hp > 0 and not has_condition("unconscious")


func can_act() -> bool:
	return is_conscious() and not has_condition("incapacitated")


func is_hostile_to(other: Creature) -> bool:
	if team == "neutral" or other.team == "neutral":
		return false
	return team != other.team


## Zadaje obrażenia z uwzględnieniem odporności. Zwraca faktycznie odjęte PW.
func take_damage(amount: int, dmg_type: String = "", crit := false) -> int:
	if dead or amount <= 0:
		return 0
	if dmg_type in immunities:
		return 0
	if dmg_type in resistances:
		amount = floori(amount / 2.0)
	if dmg_type in vulnerabilities:
		amount *= 2
	var dealt := amount
	if temp_hp > 0:
		var absorbed := mini(temp_hp, amount)
		temp_hp -= absorbed
		amount -= absorbed
	var was_down := hp <= 0
	hp -= amount
	# Uśpienie mija po otrzymaniu obrażeń
	if conditions.has("unconscious") and effects.get("magical_sleep", false) and hp > 0:
		remove_condition("unconscious")
		effects.erase("magical_sleep")
	if hp <= 0:
		if kind == "monster":
			hp = 0
			dead = true
		else:
			# Natychmiastowa śmierć, gdy nadwyżka >= maks. PW
			if -hp >= max_hp:
				dead = true
			hp = 0
			if was_down and not dead:
				death_saves.fail += 2 if crit else 1
				if death_saves.fail >= 3:
					dead = true
			add_condition("unconscious")
			stable = false
	return dealt


func heal(amount: int) -> int:
	if dead or amount <= 0:
		return 0
	var before := hp
	hp = mini(max_hp, hp + amount)
	if before <= 0 and hp > 0:
		remove_condition("unconscious")
		death_saves = {"success": 0, "fail": 0}
		stable = false
	return hp - before


# --- Stany ---

func add_condition(c: String, rounds: int = -1) -> bool:
	if c in condition_immunities:
		return false
	conditions[c] = rounds
	if c == "unconscious":
		conditions["prone"] = -1
	return true


func remove_condition(c: String) -> void:
	conditions.erase(c)


func has_condition(c: String) -> bool:
	if conditions.has(c):
		return true
	# Stany zawierające inne stany
	if c == "incapacitated":
		return conditions.has("unconscious") or conditions.has("paralyzed") or conditions.has("stunned")
	return false


# --- Zasoby ---

func resource(id_: String) -> int:
	return int(resources.get(id_, {}).get("cur", 0))


func use_resource(id_: String) -> bool:
	if resource(id_) <= 0:
		return false
	resources[id_].cur = resource(id_) - 1
	return true


func slot_available(lvl: int) -> bool:
	return int(slots.get(str(lvl), {}).get("cur", 0)) > 0


func lowest_slot(min_level: int) -> int:
	for l in range(min_level, 10):
		if slot_available(l):
			return l
	return 0


func use_slot(lvl: int) -> bool:
	if not slot_available(lvl):
		return false
	slots[str(lvl)].cur = int(slots[str(lvl)].cur) - 1
	return true


func main_weapon() -> String:
	return weapons[0] if not weapons.is_empty() else ""


# --- Serializacja ---

const _FIELDS := [
	"id", "name", "kind", "team", "is_player", "template_id", "tags",
	"species_id", "background_id", "class_id", "subclass_id", "level", "xp", "xp_value", "pending_levels",
	"scores", "save_profs", "skill_profs", "expertise", "weapon_profs", "armor_profs",
	"features", "resources", "choices", "motivations", "max_hp", "hp", "temp_hp", "hit_die", "hit_dice",
	"speed", "darkvision", "resistances", "vulnerabilities", "immunities", "condition_immunities",
	"armor_id", "shield", "weapons", "mastery", "inventory", "gold",
	"spell_ability", "spell_ability_overrides", "cantrips", "spells", "slots", "concentration",
	"heroic_inspiration", "monster_ac", "monster_attacks", "multiattack",
	"conditions", "death_saves", "stable", "dead",
]
const _INT_FIELDS := [
	"pending_levels",
	"level", "xp", "xp_value", "max_hp", "hp", "temp_hp", "hit_die", "hit_dice",
	"speed", "darkvision", "gold", "monster_ac", "multiattack",
]


func to_dict() -> Dictionary:
	var d := {}
	for f in _FIELDS:
		d[f] = get(f)
	d["grid_pos"] = [grid_pos.x, grid_pos.y]
	return d.duplicate(true)


static func from_dict(d: Dictionary) -> Creature:
	var c := Creature.new()
	for f in _FIELDS:
		if d.has(f):
			var v = d[f]
			if f in _INT_FIELDS:
				v = int(v)
			elif v is Dictionary or v is Array:
				v = v.duplicate(true)
			c.set(f, v)
	for ab in c.scores.keys():
		c.scores[ab] = int(c.scores[ab])
	for k in c.resources.keys():
		c.resources[k].cur = int(c.resources[k].cur)
		c.resources[k].max = int(c.resources[k].max)
	for k in c.slots.keys():
		c.slots[k].cur = int(c.slots[k].cur)
		c.slots[k].max = int(c.slots[k].max)
	for k in c.conditions.keys():
		c.conditions[k] = int(c.conditions[k])
	c.death_saves = {"success": int(c.death_saves.get("success", 0)), "fail": int(c.death_saves.get("fail", 0))}
	if d.has("grid_pos"):
		c.grid_pos = Vector2i(int(d.grid_pos[0]), int(d.grid_pos[1]))
	return c
