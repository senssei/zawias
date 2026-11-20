# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends GutTest
## Widoczne skutki frakcji (patrol Haska, Żeton Rdzy, nieufność), szepty i ślady Wędrowca w mgle,
## komentarze i opcja dialogowa Lis w drużynie, panel frakcji w dzienniku.

const OPTS := {
	"name": "T", "species": "human", "background": "criminal", "class": "rogue",
	"scores": {"str": 8, "dex": 15, "con": 14, "int": 12, "wis": 13, "cha": 10}, "bonus": {"dex": 2, "con": 1},
}

var gs


func before_each():
	Dice.clear_forced()
	gs = get_tree().root.get_node("GameState")
	gs.new_game(CharacterBuilder.build(OPTS))
	gs.companions = []


func after_each():
	gs.companions = []


func _talk(id: String, choices: Array, dice: Array = []) -> DialogueRunner:
	var r := DialogueRunner.new(gs)
	assert_true(r.start(id), id)
	if not dice.is_empty():
		Dice.force(dice)
	for c in choices:
		var found := false
		for ch in r.visible_choices():
			if c in ch.text:
				r.choose(ch.index)
				found = true
				break
		if not found:
			fail_test("brak wyboru „%s” w %s/%s" % [c, id, r.current_id])
			break
	return r


func _has_choice(r: DialogueRunner, fragment: String) -> bool:
	return r.visible_choices().any(func(ch): return fragment in ch.text)


func test_rust_token_makes_unravelers_spare_you():
	gs.quests["key"] = "lead_warehouse"
	gs.player.inventory.append("rust_token")
	_talk("odzwierny", ["Pokazuję Żeton Rdzy"], [20, 20])
	assert_eq(gs.faction_attitude("unravelers"), "friendly", "Żeton zjednuje Rozplataczy")
	assert_true(gs.has_flag("front_open"))
	var requests := []
	gs.world_request.connect(func(e): requests.append(e))
	var r := _talk("chest", ["po cichu"], [1, 1])
	assert_eq(r.current_id, "brother", "przyłapany swój nie walczy")
	assert_false(requests.any(func(e): return e.has("start_combat")), "bez walki")
	# bez Żetonu przyłapanie to walka
	gs.player.inventory.erase("rust_token")
	r = _talk("chest", ["po cichu"], [1, 1])
	assert_eq(r.current_id, "caught")


func test_inscribed_patrol_helps_or_hinders():
	gs.quests["key"] = "started"
	gs.flags["asked_about_key"] = true
	var r := _talk("hask", [])
	assert_false(_has_choice(r, "Wyślesz patrol"), "bez przychylności nie ma patrolu")
	gs.reputation["inscribed"] = "friendly"
	var xp: int = gs.player.xp
	_talk("hask", ["Wyślesz patrol"])
	assert_true(gs.has_flag("ambush_done"), "patrol oczyścił zaułek")
	assert_eq(gs.player.xp, xp, "bez PD za walkę, której nie było")
	# nieufni Zapisani: patrol chodzi za graczem, kłamstwo u Odźwiernego jest trudniejsze
	gs.reputation["inscribed"] = "wary"
	r = _talk("odzwierny", [])
	assert_false(r.visible_choices().any(func(ch): return ch.text == "Mam wiadomość dla Severa od kogoś z góry."))
	assert_true(_has_choice(r, "Patrol Zapisanych łazi za tobą"))
	# nieufni Rozplatacze: rozmowa nie wchodzi w grę
	gs.reputation["unravelers"] = "wary"
	r = _talk("odzwierny", [])
	assert_false(_has_choice(r, "rozmawiać z Severem"))


func test_reputation_sources():
	gs.quests["key"] = "lead_warehouse"
	_talk("lis", ["Chcesz opowieści"])
	assert_eq(gs.faction_attitude("echo"), "friendly", "opowieść dla Lis")
	_talk("sever", ["Oddaj klucz albo"], [20, 20])
	assert_eq(gs.faction_attitude("unravelers"), "wary", "zastraszony Sever")


func test_lis_option_with_sever_only_in_party():
	gs.quests["key"] = "lead_warehouse"
	var r := _talk("sever", [])
	assert_false(_has_choice(r, "[Lis]"))
	gs.join_party("lis")
	r = _talk("sever", ["[Lis]"], [18, 18])
	assert_eq(r.current_id, "convinced", "argument Lis z przewagą")
	assert_eq(gs.faction_attitude("unravelers"), "friendly")


func test_barks_companion_and_faction():
	var w: Node3D = load("res://scripts/world/world.gd").new()
	add_child_autofree(w)
	await wait_frames(3)
	var lis: Actor = w.actors["lis"]
	var barks: Array = DB.table("barks").lis
	# Lis na swoim miejscu nie mówi komentarzy towarzyszki
	w.player_actor.place(lis.cell + Vector2i(0, -1))
	gs.player_pos = w.player_actor.cell
	w._reveal_around(w.player_actor.cell)
	if w.fog:
		w.fog.update_actors(0.0, true)
	var pick: Dictionary = w.pick_bark(1000.0)
	if pick.get("npc", "") == "lis":
		assert_false(barks[pick.index].get("companion", false))
	# w drużynie: tylko komentarze, a ten zależny od miejsca tylko w pobliżu
	gs.quests["key"] = "started"
	gs.join_party("lis")
	w._sync_followers(true)
	if w.fog:
		w.fog.update_actors(0.0, true)
	w._bark_last.clear()
	gs.player_pos = Vector2i(10, 8)            # plac targowy: warunek komentarza „Każdy kamień…”
	pick = w.pick_bark(2000.0)
	assert_eq(pick.get("npc", ""), "lis", "towarzyszka komentuje")
	assert_true(barks[pick.index].get("companion", false))
	assert_false(gs.check({"near": [30, 13, 4]}), "daleko od magazynu")
	gs.player_pos = Vector2i(30, 12)
	assert_true(gs.check({"near": [30, 13, 4]}))


func test_memories_and_whispers_in_fog():
	var w: Node3D = load("res://scripts/world/world.gd").new()
	add_child_autofree(w)
	await wait_frames(3)
	var mem: Dictionary = w.map.memories[2]          # znak na murze zaułka
	var c := Vector2i(int(mem.cell[0]), int(mem.cell[1]))
	assert_false(gs.is_explored(gs.map_id, c, w.grid.width))
	# szept: gracz w pobliżu nieodkrytego zaułka
	w.player_actor.place(Vector2i(32, 8))
	assert_true(w._try_whisper(5000.0), "szept z mgły")
	assert_false(w._try_whisper(5001.0), "ten sam szept nie powtarza się od razu")
	# odkrycie śladu: wpis w dzienniku raz
	var n: int = gs.journal.size()
	w._reveal_around(Vector2i(36, 9))
	assert_true(gs.has_flag("memory_" + str(mem.id)))
	assert_eq(gs.journal.size(), n + 1 + int(gs.has_flag("memory_warehouse_dust")), "fragment w dzienniku")
	assert_true(gs.journal.has(str(mem.journal)))
	w._reveal_around(Vector2i(36, 9))
	assert_eq(gs.journal.filter(func(j): return j == str(mem.journal)).size(), 1, "raz na grę")


func test_journal_shows_faction_effects():
	var w: Node3D = load("res://scripts/world/world.gd").new()
	add_child_autofree(w)
	await wait_frames(3)
	gs.reputation["inscribed"] = "wary"
	w.hud.open_journal()
	var texts := []
	for ch in w.hud.window_body.get_children():
		if ch is Label:
			texts.append(ch.text)
	var want: String = DB.table("factions").inscribed.effects.wary
	assert_true(texts.any(func(t): return want in t), "skutek nieufności Zapisanych w dzienniku")
	w.hud.close_window()


## Klucz bez drzwi jako narzędzie: drzwi w murze pojawiają się, gdy klucz trafił do gracza; otwiera je tylko
## klucz w ręku (strażnica Wędrowca, księga przejść), bez klucza zostaje blada rysa.
func test_key_opens_door_that_isnt():
	var w: Node3D = load("res://scripts/world/world.gd").new()
	add_child_autofree(w)
	await wait_frames(3)
	var door: Actor = w.actors["hidden_door"]
	assert_false(door.visible, "drzwi nie istnieją przed odzyskaniem klucza")
	gs.apply_effects([{"give_item": "key_without_door"}, {"set_flag": "key_obtained"}])
	assert_true(door.visible, "klucz w grze: drzwi w murze")
	var r := _talk("hidden_door", ["Przyłóż klucz", "Zabierz księgę"])
	assert_true("crossings_ledger" in gs.player.inventory)
	assert_true(gs.journal.back().contains("Kustoszce"))
	assert_eq(_talk("hidden_door", []).current_id, "inside_again")
	# bez klucza (oddany Mireli), drzwi nieotwarte: blada rysa
	gs.flags.erase("hidden_door_opened")
	gs.player.inventory.erase("key_without_door")
	assert_eq(_talk("hidden_door", []).current_id, "faded")
