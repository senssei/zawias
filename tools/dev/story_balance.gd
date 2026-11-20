# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
extends RefCounted
## story balance (docs/story-pipeline.md): macierz walk poziom trudności × klasa × skład (solo, z Lis) × spotkanie,
## N stałych ziaren, symulacja z tools/dev/combat_sim.gd. Poziom na wejściu jak na typowej drodze (story paths):
## pierwsze spotkanie na 1. poziomie, kolejne na 2. po odpoczynku.

const START_LEVEL := {"ambush": 1, "warehouse": 2}


## Pole startowe gracza w spotkaniu: pole wyzwalacza albo pole obok pierwszego NPC spotkania.
static func start_cell(map: Dictionary, enc_id: String) -> Vector2i:
	for t in map.get("triggers", []):
		if t.get("encounter", "") == enc_id:
			return Vector2i(int(t.cells[-1][0]), int(t.cells[-1][1]))
	for n in map.get("npcs", []):
		if n.get("encounter", "") == enc_id:
			return Vector2i(int(n.pos[0]), int(n.pos[1]) + 1)
	return Vector2i(int(map.player_start[0]), int(map.player_start[1]))


static func run(gs: Node, classes: Array, difficulties: Array, seeds: int, character: Callable) -> Array:
	var rows := []
	var map := DB.map(gs.map_id)
	var was: String = Difficulty.current
	for diff in difficulties:
		Difficulty.current = diff
		for enc_id in DB.table("encounters").keys():
			for cls in classes:
				for party in ["solo", "lis"]:
					var wins := 0
					for k in seeds:
						Dice.seed_rng(900 + k * 53)
						gs.new_game(character.call(cls))
						gs.apply_effects([{"quest": ["key", "started"]}, {"give_item": "potion_healing"}])
						if int(START_LEVEL.get(enc_id, 1)) >= 2:
							gs.apply_effects([{"xp": 300}])
							CombatSim.take_levels(gs.player)
							Rest.long_rest(gs.player)
						if party == "lis":
							gs.join_party("lis")
						if CombatSim.fight(gs, enc_id, start_cell(map, enc_id)):
							wins += 1
						gs.companions = []
					rows.append({"difficulty": diff, "encounter": enc_id, "class": cls, "party": party,
						"level": int(START_LEVEL.get(enc_id, 1)), "wins": wins, "n": seeds})
	Difficulty.current = was
	return rows
