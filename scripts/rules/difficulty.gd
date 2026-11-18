class_name Difficulty
extends RefCounted
## Poziom trudności walk. Slice jest solowy, a spotkania SRD liczy się dla drużyny: „Opowieść” osłabia wrogów,
## żeby czarodziej czy kapłan mieli realne szanse. Ustawienie trzyma autoload Audio (user://settings.cfg).

const PRESETS := {
	"story": {"name": "Opowieść", "hp_mult": 0.5, "to_hit": -3, "desc": "Wrogowie mają mniej PW i rzadziej trafiają."},
	"normal": {"name": "Normalny", "hp_mult": 1.0, "to_hit": 0, "desc": "Wartości z SRD 5.2."},
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
