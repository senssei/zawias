# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends Node
## Globalny stan gry (autoload): postać, flagi, questy, dziennik, zapis/odczyt.

signal log_added(text: String)
signal state_changed
signal world_request(effect: Dictionary)   # efekty wymagające sceny (walka, zakończenie)

const SAVE_DIR := "user://saves"

var player: Creature
var flags := {}
var quests := {}             # id -> etap
var reputation := {}         # id frakcji -> nastawienie, domyślnie neutralne
var journal: Array = []
var removed_npcs: Array = []
var map_id := "rusty_market"
var player_pos := Vector2i(-1, -1)
var log_lines: Array = []
var ending := ""
var explored := {}           # map_id -> String "0"/"1" na pole (wiersz po wierszu); mgła na mapie
var companions: Array = []   # towarzysze w drużynie (Creature, team "party", sterowani przez AI w walce)


func new_game(pc: Creature) -> void:
	player = pc
	flags = {}
	quests = {}
	reputation = {}
	journal = [Loc.t("Przybywasz do Zawiasu, miasta-pierścienia między planami. Brama wyrzuciła cię na Rdzawym Targu.")]
	removed_npcs = []
	map_id = "rusty_market"
	player_pos = Vector2i(-1, -1)
	log_lines = []
	ending = ""
	explored = {}
	companions = []
	state_changed.emit()


## Odkrywa pola mapy (mgła na mapce). w = szerokość siatki, h = wysokość.
func reveal(mid: String, cells: Array, w: int, h: int) -> void:
	var s: String = explored.get(mid, "")
	if s.length() != w * h:
		s = "0".repeat(w * h)
	for c in cells:
		var i: int = c.y * w + c.x
		if c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and s[i] != "1":
			s[i] = "1"
	explored[mid] = s


func is_explored(mid: String, c: Vector2i, w: int) -> bool:
	var s: String = explored.get(mid, "")
	var i := c.y * w + c.x
	return c.x >= 0 and c.x < w and i >= 0 and i < s.length() and s[i] == "1"


# ------------------------------------------------------------------ drużyna

func companion(id_: String) -> Creature:
	for c in companions:
		if c.id == id_:
			return c
	return null


## NPC z mapy z polem "companion" (klasa, gatunek, tło, cechy) dołącza do drużyny na poziomie gracza.
func join_party(npc_id: String) -> Creature:
	if companion(npc_id):
		return companion(npc_id)
	var def := {}
	for n in DB.map(map_id).get("npcs", []):
		if n.id == npc_id:
			def = n
	if not def.has("companion"):
		push_error("Brak definicji towarzysza dla %s" % npc_id)
		return null
	var opts: Dictionary = def.companion.duplicate(true)
	opts["name"] = def.name
	var c := CharacterBuilder.build(opts)
	c.id = npc_id
	c.is_player = false
	c.team = "party"
	catch_up(c)
	companions.append(c)
	flags["%s_joined" % npc_id] = true
	add_log(Loc.t("%s dołącza do drużyny.") % c.name)
	state_changed.emit()
	return c


func leave_party(npc_id: String) -> void:
	var c := companion(npc_id)
	if c == null:
		return
	companions.erase(c)
	flags.erase("%s_joined" % npc_id)
	add_log(Loc.t("%s odchodzi z drużyny.") % c.name)
	state_changed.emit()


## Towarzysz dochodzi do poziomu gracza (awanse z domyślnymi wyborami: średnie PW, pierwsza podklasa, czary z listy).
func catch_up(c: Creature) -> Array:
	var out := []
	if c.xp < player.xp:
		Leveling.add_xp(c, player.xp - c.xp, true)
	while c.pending_levels > 0:
		var o := Leveling.level_up_options(c)
		var sub: String = o.subclasses[0] if not o.subclasses.is_empty() else ""
		Leveling.apply_level(c, {"hp": "avg", "subclass": sub, "spells": o.spell_choices.slice(0, o.spell_picks)})
		out.append(Loc.t("%s osiąga poziom %d.") % [c.name, c.level])
	return out


func add_log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 300:
		log_lines = log_lines.slice(-300)
	log_added.emit(text)


func has_flag(f: String) -> bool:
	return flags.get(f, false)


func quest_stage(q: String) -> String:
	return quests.get(q, "")


const ATTITUDES := ["wary", "neutral", "friendly"]


func faction_attitude(faction: String) -> String:
	return reputation.get(faction, "neutral")


func attitude_label(attitude: String) -> String:
	match attitude:
		"wary":
			return Loc.t("Nieufni")
		"friendly":
			return Loc.t("Przychylni")
		_:
			return Loc.t("Neutralni")


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
	if d.has("in_party") and companion(d.in_party) == null:
		return false
	if d.has("not_quest") and quest_stage(d.not_quest) != "":
		return false
	if d.has("reputation") and faction_attitude(d.reputation[0]) != d.reputation[1]:
		return false
	if d.has("reputation_not") and faction_attitude(d.reputation_not[0]) == d.reputation_not[1]:
		return false
	# gracz w promieniu r pól od [x, y] (okrzyki towarzyszy zależne od miejsca)
	if d.has("near") and Vector2(player_pos - Vector2i(int(d.near[0]), int(d.near[1]))).length() > float(d.near[2]):
		return false
	if d.has("knows_spell") and not d.knows_spell in Spellcasting.known(player):
		return false
	if d.has("skill_prof") and not d.skill_prof in player.skill_profs:
		return false
	return true


const QUEST_NAMES := {"key": "Klucz bez drzwi", "wanderer": "Kim jest Wędrowiec?"}
const QUEST_STAGES := {
	"wanderer": {
		"trace": "Brama nosi ślad twojej dłoni. Lis w Archiwum Echa może pomóc ustalić, kto zostawił ten znak.",
		"record": "Wędrowiec wymazał swoje imię z rejestru. Sprawdź, co pamięta Klucz bez drzwi, gdy go odzyskasz.",
		"revealed": "To ty strzegłeś pierwszych przejść Zawiasu. Oddałeś imię bramie, żeby każde przejście należało do tych, którzy z niego korzystają.",
		"done_stayed": "Zostajesz na Targu pod swoim obecnym imieniem. Decyzję o otwarciu Łuku zostawiasz na później.",
		"done_crossed": "Przekraczasz Łuk pod swoim obecnym imieniem, żeby dowiedzieć się, kto przejął władzę nad przejściami.",
	},
	"key": {
		"started": "Odzyskaj skradziony Klucz bez drzwi. Popytaj Kwita przy Kancelarii, Pchłę we wschodnim zaułku albo Lis przy Archiwum Echa. M otwiera mapę.",
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
	if e.has("set_reputation"):
		var faction: String = e.set_reputation[0]
		var attitude: String = e.set_reputation[1]
		var factions := DB.table("factions")
		if factions.has(faction) and attitude in ATTITUDES and faction_attitude(faction) != attitude:
			reputation[faction] = attitude
			add_log(Loc.t("Reputacja: %s → %s") % [factions[faction].name, attitude_label(attitude)])
	if e.has("quest"):
		var q: String = e.quest[0]
		var stage: String = e.quest[1]
		if quests.get(q, "") != stage:
			quests[q] = stage
			add_log(Loc.t("[Zadanie]") + " %s: %s" % [Loc.t(str(QUEST_NAMES.get(q, q))), Loc.t(str(QUEST_STAGES.get(q, {}).get(stage, stage)))])
	if e.has("xp"):
		for l in Leveling.add_xp(player, int(e.xp), true):
			add_log(l)
		for c in companions:
			for l in catch_up(c):
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
	if e.has("journal") and not e.journal in journal:   # ta sama porażka drugi raz nie dubluje wpisu
		journal.append(e.journal)
		add_log(Loc.t("[Dziennik]") + " " + e.journal)
	if e.has("long_rest"):
		for l in Rest.long_rest(player):
			add_log(l)
		for c in companions:
			Rest.long_rest(c)
	if e.has("join_party"):
		join_party(e.join_party)
	if e.has("leave_party"):
		leave_party(e.leave_party)
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
		"flags": flags, "quests": quests, "journal": journal, "reputation": reputation,
		"removed_npcs": removed_npcs, "map_id": map_id,
		"player_pos": [player_pos.x, player_pos.y],
		"log": log_lines.slice(-50), "ending": ending, "explored": explored,
		"companions": companions.map(func(c): return c.to_dict()),
		"time": Time.get_datetime_string_from_system(),
	}


func from_dict(d: Dictionary) -> void:
	player = Creature.from_dict(d.player)
	flags = d.get("flags", {})
	quests = d.get("quests", {})
	reputation = d.get("reputation", {})
	journal = d.get("journal", [])
	removed_npcs = d.get("removed_npcs", [])
	map_id = d.get("map_id", "rusty_market")
	var pp: Array = d.get("player_pos", [-1, -1])
	player_pos = Vector2i(int(pp[0]), int(pp[1]))
	log_lines = d.get("log", [])
	ending = d.get("ending", "")
	explored = d.get("explored", {})
	companions = d.get("companions", []).map(func(cd): return Creature.from_dict(cd))
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
