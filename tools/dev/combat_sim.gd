# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name CombatSim
extends RefCounted
## Walka bez świata 3D, jak w World.start_combat: wrogowie ze spawnów spotkania i NPC przypisanych do spotkania
## (ze skalowaniem solo), entropia, zaskoczenie, AI wrogów i towarzyszy, prosta taktyka gracza. Używają jej testy
## dróg (tests/unit/test_slice.gd) i macierz balansu (pipeline.sh story balance).

## Taktyka gracza (bliższa człowiekowi niż AI wrogów): przy niskich PW leczenie, Drugi oddech albo mikstura;
## czar z listy, ale bez czarów dystansowych z rzutem na trafienie, gdy wróg stoi obok (utrudnienie), i bez
## zrywania koncentracji; inaczej to, co robi AI.
const SPELL_PRIORITY := ["sleep", "guiding_bolt", "magic_missile", "inflict_wounds", "burning_hands",
	"chromatic_orb", "fire_bolt", "sacred_flame", "ray_of_frost"]


## Rozgrywa spotkanie. Wygrana: PD za wrogów i on_victory jak w świecie, wrogowie usunięci. Zwraca wynik walki.
static func fight(gs: Node, enc_id: String, player_cell: Vector2i, log_cb: Callable = Callable()) -> bool:
	var map := DB.map(gs.map_id)
	var grid := CombatGrid.new(map)
	var enc := DB.entry("encounters", enc_id)
	for f in enc.get("unlock", []):
		gs.flags[f] = true
	var pc: Creature = gs.player
	pc.grid_pos = player_cell
	var party: Array = [pc]
	var near := [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0)]
	for i in gs.companions.size():
		var c: Creature = gs.companions[i]
		c.grid_pos = player_cell + near[i % near.size()]
		party.append(c)
	var enemies: Array = []
	var skip := Difficulty.solo_skip(enc, party.size())
	for s in enc.get("spawn", []):
		if s.id in skip:
			continue
		var m := CharacterBuilder.create_monster(s.monster, s.id, s.get("name", ""))
		m.grid_pos = Vector2i(int(s.pos[0]), int(s.pos[1]))
		enemies.append(m)
	for n in map.npcs:
		if n.get("encounter", "") == enc_id and n.has("monster") and not n.get("flees", false) and not n.id in skip:
			var m := CharacterBuilder.create_monster(n.monster, n.id, n.name)
			m.grid_pos = Vector2i(int(n.pos[0]), int(n.pos[1]))
			enemies.append(m)
	if enemies.is_empty():
		return true
	var mgr := CombatManager.new(grid)
	mgr.entropy = enc.get("entropy", false)
	if log_cb.is_valid():
		mgr.event.connect(func(e): if e.type in ["log", "turn"]: log_cb.call(str(e.get("text", e.get("id", "")))))
	var surprised: bool = enc.has("surprise_unless_flag") and not gs.has_flag(enc.surprise_unless_flag)
	mgr.start(party, enemies, surprised)
	var guard := 0
	while mgr.active and guard < 200:
		guard += 1
		var c := mgr.current()
		if c == pc:
			player_turn(mgr, pc, enemies)
		else:
			AIBasic.take_turn(mgr, c)
		if mgr.active:
			mgr.end_turn()
	if mgr.active:
		push_warning("CombatSim: walka %s nie skończyła się w 200 turach" % enc_id)
		return false
	if mgr.victory:
		var xp := 0
		for e in enemies:
			xp += int(DB.entry("monsters", e.template_id).get("xp", 0))
		gs.apply_effects([{"xp": xp}] + enc.get("on_victory", []))
		for e in enemies:
			if not e.id in gs.removed_npcs:
				gs.removed_npcs.append(e.id)
	for c in party:
		c.effects.clear()
		c.concentration = ""
	return mgr.victory and pc.is_alive()


static func player_turn(mgr: CombatManager, pc: Creature, enemies: Array) -> void:
	if pc.hp <= pc.max_hp * 0.4:
		var healed := false
		if pc.resource("second_wind") > 0:
			healed = mgr.do_action(pc, "second_wind") == ""
		for sp in ["healing_word", "cure_wounds"]:
			if not healed and sp in pc.spells and mgr.can_cast(pc, sp, pc.grid_pos) == "":
				mgr.cast(pc, sp, pc.grid_pos, 1)
				healed = true
		if not healed and "potion_healing" in pc.inventory:
			mgr.do_action(pc, "potion")
	var target: Creature = null
	var adjacent := false
	for e in enemies:
		if not e.is_conscious():
			continue
		var d := CombatGrid.distance(pc.grid_pos, e.grid_pos)
		adjacent = adjacent or d <= 1
		if target == null or d < CombatGrid.distance(pc.grid_pos, target.grid_pos):
			target = e
	if target == null or not mgr.active:
		return
	for sp in SPELL_PRIORITY:
		if not (sp in pc.spells or sp in pc.cantrips):
			continue
		var s := Spellcasting.spell(sp)
		if adjacent and s.get("type", "") == "attack" and int(s.get("range", 1)) > 1:
			continue
		if s.get("concentration", false) and pc.concentration != "":
			continue
		var lvl := int(s.get("level", 0))
		if mgr.can_cast(pc, sp, target.grid_pos) == "":
			mgr.cast(pc, sp, target.grid_pos, lvl)
			return
	AIBasic.take_turn(mgr, pc)


## Przyjmuje oczekujące awanse (średnie PW, pierwsza podklasa, pierwsze czary z listy).
static func take_levels(c: Creature) -> void:
	while c.pending_levels > 0:
		var o := Leveling.level_up_options(c)
		var spells: Array = o.spell_choices.slice(0, o.spell_picks)
		var sub: String = o.subclasses[0] if not o.subclasses.is_empty() else ""
		Leveling.apply_level(c, {"hp": "avg", "subclass": sub, "spells": spells})
