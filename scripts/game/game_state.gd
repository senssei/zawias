extends Node
## Globalny stan gry (autoload): postać, flagi, questy, dziennik, zapis/odczyt.

signal log_added(text: String)
signal state_changed
signal world_request(effect: Dictionary)   # efekty wymagające sceny (walka, zakończenie)

const SAVE_DIR := "user://saves"

var player: Creature
var flags := {}
var quests := {}             # id -> etap
var journal: Array = []
var removed_npcs: Array = []
var map_id := "rusty_market"
var player_pos := Vector2i(-1, -1)
var log_lines: Array = []
var ending := ""


func new_game(pc: Creature) -> void:
	player = pc
	flags = {}
	quests = {}
	journal = [Loc.t("Przybywasz do Zawiasu, miasta-pierścienia między planami. Brama wyrzuciła cię na Rdzawym Targu.")]
	removed_npcs = []
	map_id = "rusty_market"
	player_pos = Vector2i(-1, -1)
	log_lines = []
	ending = ""
	state_changed.emit()


func add_log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 300:
		log_lines = log_lines.slice(-300)
	log_added.emit(text)


func has_flag(f: String) -> bool:
	return flags.get(f, false)


func quest_stage(q: String) -> String:
	return quests.get(q, "")


# ------------------------------------------------------------------ warunki i efekty

## Warunek z dialogu/triggera. Wszystkie klucze muszą być spełnione.
func check(cond) -> bool:
	if cond == null or (cond is Dictionary and cond.is_empty()):
		return true
	var d: Dictionary = cond
	if d.has("flag") and not has_flag(d.flag):
		return false
	if d.has("not_flag") and has_flag(d.not_flag):
		return false
	if d.has("flags"):
		for f in d.flags:
			if not has_flag(f):
				return false
	if d.has("any_flag"):
		var ok := false
		for f in d.any_flag:
			ok = ok or has_flag(f)
		if not ok:
			return false
	if d.has("class") and player.class_id != d["class"]:
		return false
	if d.has("species") and player.species_id != d.species:
		return false
	if d.has("has_item") and not d.has_item in player.inventory:
		return false
	if d.has("not_item") and d.not_item in player.inventory:
		return false
	if d.has("gold") and player.gold < int(d.gold):
		return false
	if d.has("quest"):
		if quest_stage(d.quest[0]) != d.quest[1]:
			return false
	if d.has("quest_any"):
		if not quest_stage(d.quest_any[0]) in d.quest_any[1]:
			return false
	if d.has("not_quest") and quest_stage(d.not_quest) != "":
		return false
	if d.has("knows_spell") and not d.knows_spell in Spellcasting.known(player):
		return false
	if d.has("skill_prof") and not d.skill_prof in player.skill_profs:
		return false
	return true


const QUEST_NAMES := {"key": "Klucz bez drzwi"}
const QUEST_STAGES := {
	"key": {
		"started": "Mirela, kluczarka z Rdzawego Targu, straciła Klucz bez drzwi. Ktoś go ukradł. Rozpytaj na targu.",
		"lead_warehouse": "Ślady prowadzą do starego magazynu na wschodzie targu, gdzie siedzą Rozplatacze. Wejdź frontem, tyłem albo z ostrzem w dłoni.",
		"has_key": "Masz Klucz bez drzwi. Oddaj go Mireli albo sprawdź, co otwiera.",
		"done_returned": "Klucz wrócił do Mireli. Zawias ma o jedną tajemnicę mniej, a ty masz pełniejszą sakiewkę.",
		"done_portal": "Użyłeś klucza w Łuku bez drzwi. Gdzieś za nim czeka nowy plan.",
	}
}


func apply_effects(effects) -> void:
	if effects == null:
		return
	for e in effects:
		apply_effect(e)
	state_changed.emit()


func apply_effect(e: Dictionary) -> void:
	if e.has("set_flag"):
		flags[e.set_flag] = true
	if e.has("clear_flag"):
		flags.erase(e.clear_flag)
	if e.has("quest"):
		var q: String = e.quest[0]
		var stage: String = e.quest[1]
		if quests.get(q, "") != stage:
			quests[q] = stage
			add_log(Loc.t("[Zadanie]") + " %s: %s" % [Loc.t(str(QUEST_NAMES.get(q, q))), Loc.t(str(QUEST_STAGES.get(q, {}).get(stage, stage)))])
	if e.has("xp"):
		for l in Leveling.add_xp(player, int(e.xp), true):
			add_log(l)
	if e.has("gold"):
		player.gold = maxi(0, player.gold + int(e.gold))
		if int(e.gold) > 0:
			UI.play_sfx("coin")
		add_log((Loc.t("Otrzymujesz %d sz.") if int(e.gold) > 0 else Loc.t("Płacisz %d sz.")) % absi(int(e.gold)))
	if e.has("give_item"):
		player.inventory.append(e.give_item)
		add_log(Loc.t("Otrzymujesz: %s") % DB.entry("items", e.give_item).get("name", e.give_item))
	if e.has("take_item"):
		player.inventory.erase(e.take_item)
		add_log(Loc.t("Oddajesz: %s") % DB.entry("items", e.take_item).get("name", e.take_item))
	if e.has("journal"):
		journal.append(e.journal)
		add_log(Loc.t("[Dziennik]") + " " + e.journal)
	if e.has("long_rest"):
		for l in Rest.long_rest(player):
			add_log(l)
	if e.has("heal"):
		player.heal(int(e.heal))
	if e.has("remove_npc"):
		if not e.remove_npc in removed_npcs:
			removed_npcs.append(e.remove_npc)
	if e.has("inspiration"):
		player.heroic_inspiration = true
		add_log(Loc.t("Otrzymujesz Heroiczną inspirację."))
	for key in ["start_combat", "end_game", "remove_npc"]:
		if e.has(key):
			world_request.emit(e)
			break


# ------------------------------------------------------------------ zapis

func to_dict() -> Dictionary:
	return {
		"version": 1,
		"player": player.to_dict(),
		"flags": flags, "quests": quests, "journal": journal,
		"removed_npcs": removed_npcs, "map_id": map_id,
		"player_pos": [player_pos.x, player_pos.y],
		"log": log_lines.slice(-50), "ending": ending,
		"time": Time.get_datetime_string_from_system(),
	}


func from_dict(d: Dictionary) -> void:
	player = Creature.from_dict(d.player)
	flags = d.get("flags", {})
	quests = d.get("quests", {})
	journal = d.get("journal", [])
	removed_npcs = d.get("removed_npcs", [])
	map_id = d.get("map_id", "rusty_market")
	var pp: Array = d.get("player_pos", [-1, -1])
	player_pos = Vector2i(int(pp[0]), int(pp[1]))
	log_lines = d.get("log", [])
	ending = d.get("ending", "")
	state_changed.emit()


func save_game(slot: String = "slot1") -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open("%s/%s.json" % [SAVE_DIR, slot], FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	add_log(Loc.t("Zapisano grę (%s).") % slot)
	return true


func has_save(slot: String = "slot1") -> bool:
	return FileAccess.file_exists("%s/%s.json" % [SAVE_DIR, slot])


func load_game(slot: String = "slot1") -> bool:
	var f := FileAccess.open("%s/%s.json" % [SAVE_DIR, slot], FileAccess.READ)
	if f == null:
		return false
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return false
	from_dict(d)
	add_log(Loc.t("Wczytano grę (%s).") % slot)
	return true
