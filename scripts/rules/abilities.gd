# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name Abilities
extends RefCounted
## Cechy, umiejętności i stałe zasad SRD 5.2.

const LIST := ["str", "dex", "con", "int", "wis", "cha"]
const NAMES := {
	"str": "Siła", "dex": "Zręczność", "con": "Kondycja",
	"int": "Inteligencja", "wis": "Mądrość", "cha": "Charyzma",
}
const SHORT := {"str": "SIŁ", "dex": "ZRC", "con": "KON", "int": "INT", "wis": "MDR", "cha": "CHA"}

const SKILLS := {
	"athletics": "str",
	"acrobatics": "dex", "sleight_of_hand": "dex", "stealth": "dex",
	"arcana": "int", "history": "int", "investigation": "int", "nature": "int", "religion": "int",
	"animal_handling": "wis", "insight": "wis", "medicine": "wis", "perception": "wis", "survival": "wis",
	"deception": "cha", "intimidation": "cha", "performance": "cha", "persuasion": "cha",
}
const SKILL_NAMES := {
	"athletics": "Atletyka", "acrobatics": "Akrobatyka", "sleight_of_hand": "Zwinne Palce",
	"stealth": "Skradanie", "arcana": "Wiedza Tajemna", "history": "Historia",
	"investigation": "Śledztwo", "nature": "Przyroda", "religion": "Religia",
	"animal_handling": "Opieka nad Zwierzętami", "insight": "Intuicja", "medicine": "Medycyna",
	"perception": "Percepcja", "survival": "Sztuka Przetrwania", "deception": "Oszustwo",
	"intimidation": "Zastraszanie", "performance": "Występy", "persuasion": "Perswazja",
}

const STANDARD_ARRAY := [15, 14, 13, 12, 10, 8]
const POINT_BUY_BUDGET := 27
const POINT_BUY_COST := {8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9}

const XP_THRESHOLDS := [0, 300, 900, 2700, 6500]
const MAX_LEVEL := 3


static func modifier(score: int) -> int:
	return floori((score - 10) / 2.0)


static func proficiency_bonus(level: int) -> int:
	return 2 + floori((level - 1) / 4.0)


static func fmt_mod(m: int) -> String:
	return ("+%d" % m) if m >= 0 else str(m)


static func point_buy_cost(scores: Dictionary) -> int:
	var total := 0
	for ab in LIST:
		total += int(POINT_BUY_COST.get(int(scores.get(ab, 8)), 99))
	return total


static func level_for_xp(xp: int) -> int:
	var lvl := 1
	for i in XP_THRESHOLDS.size():
		if xp >= XP_THRESHOLDS[i]:
			lvl = i + 1
	return mini(lvl, MAX_LEVEL)
