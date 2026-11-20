# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends GutTest

func before_each():
	Difficulty.current = "normal"
	Dice.clear_forced()
	Dice.seed_rng(42)


func _fighter() -> Creature:
	return CharacterBuilder.build({
		"name": "Test", "species": "human", "background": "soldier", "class": "fighter",
		"scores": {"str": 15, "dex": 13, "con": 14, "int": 8, "wis": 12, "cha": 10},
		"bonus": {"str": 2, "con": 1}, "skills": ["perception", "insight"], "choice": "defense",
	})


func test_modifiers():
	assert_eq(Abilities.modifier(10), 0)
	assert_eq(Abilities.modifier(8), -1)
	assert_eq(Abilities.modifier(17), 3)
	assert_eq(Abilities.modifier(1), -5)
	assert_eq(Abilities.proficiency_bonus(1), 2)
	assert_eq(Abilities.proficiency_bonus(5), 3)


func test_dice_parse_and_forced():
	var p := Dice.parse("2d6+3")
	assert_eq(int(p.count), 2)
	assert_eq(int(p.sides), 6)
	assert_eq(int(p.bonus), 3)
	Dice.force([4, 5])
	assert_eq(int(Dice.roll_expr("2d6+3").total), 12)
	Dice.force([3, 17])
	assert_eq(int(Dice.d20(1).natural), 17)
	Dice.force([3, 17])
	assert_eq(int(Dice.d20(-1).natural), 3)
	assert_eq(Dice.average("2d8+2"), 11)


func test_point_buy():
	assert_eq(Abilities.point_buy_cost({"str": 15, "dex": 15, "con": 15, "int": 8, "wis": 8, "cha": 8}), 27)


func test_fighter_build():
	var c := _fighter()
	assert_eq(c.scores.str, 17)
	assert_eq(c.max_hp, 10 + 2)  # k10 + KON(15 -> +2)
	assert_eq(c.ac(), 16 + 2 + 1)  # kolczuga + tarcza + Obrona
	assert_true(c.has_feature("second_wind"))
	assert_true(c.has_feature("savage_attacker"))
	assert_eq(c.resource("second_wind"), 2)
	assert_true("athletics" in c.skill_profs)
	assert_eq(c.skill_bonus("athletics"), 3 + 2)
	assert_eq(c.save_bonus("str"), 5)
	assert_eq(c.mastery.size(), 3)


func test_weapon_option_longsword_with_shield():
	var c := _fighter()
	var o := Attack.weapon_option(c, "longsword")
	assert_eq(o.bonus, 5)
	assert_eq(o.dice, "1d8")  # z tarczą bez wersji oburęcznej
	assert_eq(o.mastery, "sap")


func test_attack_hit_and_crit():
	var c := _fighter()
	var m := CharacterBuilder.create_monster("bandit", "b1")
	assert_eq(m.max_hp, 11)
	var o := Attack.weapon_option(c, "longsword")
	o.mastery = ""
	# trafienie: k20=10 (+5=15 vs KP12), obrażenia k8=6, savage attacker drugi rzut k8=2 -> 6+3=9
	Dice.force([10, 6, 2])
	var r := Attack.resolve(c, m, o, {}, {})
	assert_true(r.hit)
	assert_eq(m.hp, 11 - 9)
	# krytyk: 20, 2k8 = 1+1, savage nieużyty w nowej turze: 2k8 = 4+4 -> 8+3 = 11 -> martwy
	Dice.force([20, 1, 1, 4, 4])
	r = Attack.resolve(c, m, o, {}, {})
	assert_true(r.crit)
	assert_true(m.dead)


func test_nat1_always_misses():
	var c := _fighter()
	var m := CharacterBuilder.create_monster("bandit", "b1")
	Dice.force([1])
	var r := Attack.resolve(c, m, Attack.weapon_option(c, "longsword"), {}, {})
	assert_false(r.hit)


func test_sap_mastery():
	var c := _fighter()
	var m := CharacterBuilder.create_monster("guard", "g1")
	Dice.force([15, 3, 1])
	var r := Attack.resolve(c, m, Attack.weapon_option(c, "longsword"), {}, {})
	assert_true(r.hit)
	assert_true(m.effects.get("sapped", false))
	var mode := Attack.compute_mode(m, c, false)
	assert_eq(int(mode.mode), -1)


func test_sneak_attack_with_advantage():
	var c := CharacterBuilder.build({
		"name": "Łotr", "species": "elf", "background": "criminal", "class": "rogue",
		"scores": {"str": 8, "dex": 15, "con": 14, "int": 12, "wis": 13, "cha": 10},
		"bonus": {"dex": 2, "con": 1}, "skills": ["acrobatics", "deception", "insight", "investigation"],
	})
	assert_eq(c.initiative_bonus(), 3 + 2)  # Czujny
	var m := CharacterBuilder.create_monster("thug" if false else "cultist", "c1")
	m.add_condition("prone")
	var turn := {}
	# przewaga (cel leży, dystans 1): 5 i 12 -> 12+5=17, k6=4 (+3), sneak k6=6
	Dice.force([5, 12, 4, 6])
	var r := Attack.resolve(c, m, Attack.weapon_option(c, "shortsword"), {"distance": 1}, turn)
	assert_true(r.hit)
	assert_true(turn.sneak_used)
	assert_true(m.dead)


func test_resistance_and_vulnerability():
	var m := CharacterBuilder.create_monster("rust_mephit", "m1")
	var hp := m.hp
	assert_eq(m.take_damage(5, "fire"), 10)
	assert_eq(m.hp, hp - 10)
	assert_eq(m.take_damage(5, "poison"), 0)


func test_pc_drops_unconscious_and_death_saves():
	var c := _fighter()
	c.take_damage(c.max_hp, "slashing")
	assert_eq(c.hp, 0)
	assert_true(c.has_condition("unconscious"))
	assert_false(c.dead)
	c.take_damage(1, "slashing", true)
	assert_eq(int(c.death_saves.fail), 2)
	c.heal(5)
	assert_true(c.is_conscious())


func test_saving_throw_bless_and_dwarf():
	var c := CharacterBuilder.build({
		"name": "Krasnal", "species": "dwarf", "background": "acolyte", "class": "cleric",
		"scores": {"str": 14, "dex": 8, "con": 15, "int": 10, "wis": 15, "cha": 8},
		"bonus": {"wis": 2, "int": 1}, "skills": ["medicine", "persuasion"], "choice": "protector",
	})
	assert_eq(c.ac(), 16 + 2)
	assert_eq(c.max_hp, 8 + 2 + 1)
	Dice.force([2, 18])
	var sv := Checks.saving_throw(c, "con", 15, "poisoned")
	assert_true(sv.success)


func test_spells_wizard():
	var c := CharacterBuilder.build({
		"name": "Mag", "species": "tiefling", "background": "sage", "class": "wizard",
		"scores": {"str": 8, "dex": 14, "con": 14, "int": 15, "wis": 12, "cha": 10},
		"bonus": {"int": 2, "con": 1}, "skills": ["investigation", "medicine"],
	})
	assert_eq(c.spell_save_dc(), 8 + 2 + 3)
	assert_eq(int(c.slots["1"].max), 2)
	var m := CharacterBuilder.create_monster("cultist", "c1")
	Dice.force([2, 3, 4])
	var r := Spellcasting.cast(c, "magic_missile", [m], {})
	assert_true(r.ok)
	assert_eq(int(c.slots["1"].cur), 1)
	assert_true(m.dead)  # 3+4+5 = 12 >= 9
	# Uśpienie
	var m2 := CharacterBuilder.create_monster("cultist", "c2")
	Dice.force([1])
	Spellcasting.cast(c, "sleep", [m2], {"all": [c, m2]})
	assert_true(m2.has_condition("unconscious"))
	assert_eq(c.concentration, "sleep")
	m2.take_damage(1, "fire")
	assert_false(m2.has_condition("unconscious"))


func test_shield_reaction():
	var c := CharacterBuilder.build({
		"name": "Mag", "species": "human", "background": "sage", "class": "wizard",
		"scores": {"str": 8, "dex": 14, "con": 14, "int": 15, "wis": 12, "cha": 10}, "bonus": {"int": 2, "con": 1},
	})
	var m := CharacterBuilder.create_monster("bandit", "b1")
	Dice.force([10])  # 13 vs KP 12 -> trafienie; Tarcza -> 17
	var r := Attack.resolve(m, c, Attack.monster_option(m, m.monster_attacks[0]), {}, {})
	assert_false(r.hit)
	assert_true(c.effects.get("shield_spell", false))


func test_rest_and_level_up():
	var c := _fighter()
	c.take_damage(8)
	c.use_resource("second_wind")
	c.use_resource("second_wind")
	Rest.short_rest(c)
	assert_eq(c.resource("second_wind"), 1)
	Rest.long_rest(c)
	assert_eq(c.hp, c.max_hp)
	assert_eq(c.resource("second_wind"), 2)
	assert_true(c.heroic_inspiration)
	var hp1 := c.max_hp
	Leveling.add_xp(c, 900)
	assert_eq(c.level, 3)
	assert_eq(c.subclass_id, "champion")
	assert_true(c.has_feature("improved_critical"))
	assert_true(c.has_feature("action_surge"))
	assert_eq(c.max_hp, hp1 + 2 * (6 + 2))
	assert_eq(Attack.crit_min(c, {"kind": "weapon"}), 19)


func test_cleric_level3_life():
	var c := CharacterBuilder.build({
		"name": "K", "species": "human", "background": "acolyte", "class": "cleric",
		"scores": {"str": 14, "dex": 8, "con": 14, "int": 10, "wis": 15, "cha": 12}, "bonus": {"wis": 2, "cha": 1},
	})
	Leveling.add_xp(c, 900)
	assert_eq(int(c.slots["2"].max), 2)
	assert_eq(c.resource("channel_divinity"), 2)
	c.hp = 1
	Dice.force([1, 1])
	Spellcasting.cast(c, "cure_wounds", [c], {})
	assert_eq(c.hp, 1 + 2 + 3 + (2 + 1))  # 2k8=2, MDR +3, Uczeń życia 2+1


func test_serialization_roundtrip():
	var c := _fighter()
	c.add_condition("prone")
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	var c2 := Creature.from_dict(d)
	assert_eq(c2.ac(), c.ac())
	assert_eq(c2.max_hp, c.max_hp)
	assert_eq(c2.resource("second_wind"), 2)
	assert_true(c2.has_condition("prone"))
	assert_eq(typeof(c2.level), TYPE_INT)


func _wizard() -> Creature:
	return CharacterBuilder.build({
		"name": "W", "species": "elf", "background": "sage", "class": "wizard",
		"scores": {"str": 8, "dex": 14, "con": 13, "int": 15, "wis": 12, "cha": 10}, "bonus": {"int": 2, "con": 1},
	})


func test_deferred_level_up_with_spell_choice():
	var c := _wizard()
	var lines := Leveling.add_xp(c, 300, true)
	assert_eq(c.level, 1, "z defer awans czeka na okno")
	assert_eq(c.pending_levels, 1)
	assert_true(lines.any(func(l): return "AWANS" in l))
	var o := Leveling.level_up_options(c)
	assert_eq(int(o.level), 2)
	assert_eq(int(o.spell_picks), 2)
	assert_true("thunderwave" in o.spell_choices)
	assert_false("shatter" in o.spell_choices, "krąg 2 dopiero z miejscami 2. kręgu")
	var hp0 := c.max_hp
	Leveling.apply_level(c, {"hp": "avg", "spells": ["thunderwave", "chromatic_orb", "shatter"]})
	assert_eq(c.level, 2)
	assert_eq(c.pending_levels, 0)
	assert_true("thunderwave" in c.spells and "chromatic_orb" in c.spells)
	assert_false("shatter" in c.spells, "czar spoza listy wyborów jest ignorowany")
	assert_eq(c.max_hp, hp0 + int(o.hp_avg))


func test_level3_offers_second_circle_and_subclass():
	var c := _wizard()
	Leveling.add_xp(c, 900, true)
	assert_eq(c.pending_levels, 2)
	Leveling.apply_level(c, {"hp": "avg", "spells": []})
	var o := Leveling.level_up_options(c)
	assert_eq(int(o.level), 3)
	assert_true("evoker" in o.subclasses)
	assert_true("shatter" in o.spell_choices and "hold_person" in o.spell_choices)
	Dice.force([6])
	var hp0 := c.max_hp
	Leveling.apply_level(c, {"hp": "roll", "subclass": "evoker", "spells": ["shatter", "hold_person"]})
	assert_eq(c.subclass_id, "evoker")
	assert_eq(c.max_hp, hp0 + 6 + c.mod("con"))
	assert_true("hold_person" in c.spells)


func test_pending_levels_survive_save():
	var c := _wizard()
	Leveling.add_xp(c, 300, true)
	var c2 := Creature.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_eq(c2.pending_levels, 1)
	assert_eq(typeof(c2.pending_levels), TYPE_INT)


func test_hold_person_paralyzes_until_concentration_ends():
	var c := _wizard()
	Leveling.add_xp(c, 900)
	var foe := CharacterBuilder.create_monster("bandit", "b1")
	Dice.force([1])
	Spellcasting.cast(c, "hold_person", [foe], {})
	assert_true(foe.has_condition("paralyzed"))
	assert_eq(c.concentration, "hold_person")
	Spellcasting.end_concentration(c, [c, foe])
	assert_false(foe.has_condition("paralyzed"))
