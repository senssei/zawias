# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name Difficulty
extends RefCounted
## Poziom trudności walk. Slice jest solowy, a spotkania SRD liczy się dla drużyny: „Opowieść” osłabia wrogów,
## żeby czarodziej czy kapłan mieli realne szanse. Ustawienie trzyma autoload Audio (user://settings.cfg).

const PRESETS := {
	"story": {"name": "Opowieść", "hp_mult": 0.5, "to_hit": -3, "solo_scaling": false, "desc": "Wrogowie mają mniej PW i rzadziej trafiają."},
	"normal": {"name": "Normalny", "hp_mult": 1.0, "to_hit": 0, "solo_scaling": true, "desc": "Wartości z SRD 5.2. Bez towarzysza najgroźniejsi wrogowie omijają walkę."},
}
const ORDER := ["story", "normal"]

const GAME_DEFAULT := "story"     # domyślne w grze (Audio._load_settings): slice jest solowy, patrz README
static var current := "normal"   # wartości SRD (testy zasad)


static func preset() -> Dictionary:
	return PRESETS.get(current, PRESETS.normal)


static func monster_hp(base: int) -> int:
	return maxi(1, roundi(base * float(preset().hp_mult)))


static func monster_to_hit() -> int:
	return int(preset().to_hit)


## Skalowanie solo: spotkanie może mieć "solo": {"skip": [id...], "difficulty": [poziomy]?} — tych wrogów
## (spawn albo NPC mapy) nie ma w walce, gdy gracz walczy bez towarzyszy. Bez "difficulty" decyduje
## "solo_scaling" poziomu (tylko Normalny: „Opowieść” osłabia wrogów sama). Lista "difficulty" włącza skalowanie
## na wskazanych poziomach, np. zasadzka na 1. poziomie jest za trudna solo także na „Opowieści”.
## Z drużyną walka jest zawsze pełna.
static func solo_skip(enc: Dictionary, party_size: int) -> Array:
	var solo: Dictionary = enc.get("solo", {})
	if party_size > 1 or solo.is_empty():
		return []
	var on: bool = current in solo.difficulty if solo.has("difficulty") else preset().get("solo_scaling", false)
	return solo.get("skip", []) if on else []
