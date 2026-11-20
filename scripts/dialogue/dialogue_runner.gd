# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
class_name DialogueRunner
extends RefCounted
## Graf dialogowy z JSON: węzły, wybory z warunkami, testy umiejętności i efekty.
##
## Format: {"start": "id", "nodes": {"id": {"speaker", "text", "effects": [], "choices": [
##   {"text", "next", "if": {...}, "effects": [], "once": bool,
##    "motivation": "kategoria:opcja" (widoczny tylko przy tej motywacji, daje inspirację; ADR 0009),
##    "check": {"skill"|"ability", "dc", "success", "fail", "success_effects", "fail_effects",
##              "boon_effects", "cost_effects", "gain_effects"}, "end": true}
## Stopień sukcesu (docs/decisions/0008): boon = sukces o 5+, cost = sukces o 0–4, gain = porażka o 1–4.
## ]}}}
## Węzeł może mieć "redirect": [{"if": {...}, "next": "id"}] i wtedy przekierowuje automatycznie.

signal node_shown(node: Dictionary, choices: Array)
signal check_rolled(text: String, success: bool, natural: int, band: String)   # band: "" gdy pas nic nie robi
signal finished

var data := {}
var dialogue_id := ""
var current_id := ""
var state: Node   # GameState
var used_once := {}


func _init(gs: Node = null) -> void:
	state = gs


func start(id: String, gs: Node = null) -> bool:
	if gs:
		state = gs
	dialogue_id = id
	data = DB.dialogue(id)
	if data.is_empty():
		return false
	var start_id: String = data.get("start", "start")
	for alt in data.get("starts", []):
		if state.check(alt.get("if", {})):
			start_id = alt.next
			break
	goto(start_id)
	return true


func goto(node_id: String) -> void:
	if node_id == "" or node_id == "end":
		finished.emit()
		return
	var node: Dictionary = data.nodes.get(node_id, {})
	if node.is_empty():
		push_error("Dialog %s: brak węzła %s" % [dialogue_id, node_id])
		finished.emit()
		return
	for r in node.get("redirect", []):
		if state.check(r.get("if", {})):
			goto(r.next)
			return
	current_id = node_id
	state.apply_effects(node.get("effects", []))
	node_shown.emit(node, visible_choices())


func current_node() -> Dictionary:
	return data.get("nodes", {}).get(current_id, {})


func _once_key(i: int) -> String:
	return "dlg_%s_%s_%d" % [dialogue_id, current_id, i]


## Lista widocznych wyborów: [{index, text, choice}]
func visible_choices() -> Array:
	var out := []
	var node := current_node()
	var choices: Array = node.get("choices", [])
	for i in choices.size():
		var ch: Dictionary = choices[i]
		if not state.check(ch.get("if", {})):
			continue
		if ch.has("motivation") and not state.has_motivation(ch.motivation):
			continue
		if ch.get("once", false) and state.has_flag(_once_key(i)):
			continue
		out.append({"index": i, "text": choice_label(ch), "choice": ch})
	if out.is_empty():
		out.append({"index": -1, "text": Loc.t("[Odejdź]"), "choice": {"end": true}})
	return out


func choice_label(ch: Dictionary) -> String:
	var t: String = ch.get("text", "...")
	if ch.has("motivation"):
		t = "[%s] %s" % [state.motivation_name(ch.motivation), t]
	if ch.has("check"):
		var chk: Dictionary = ch.check
		var name: String = Loc.t(str(Abilities.SKILL_NAMES.get(chk.get("skill", ""), Abilities.NAMES.get(chk.get("ability", ""), "?"))))
		t = Loc.t("[%s, ST %d] %s") % [name, int(chk.dc), t]
	return t


func choose(index: int) -> void:
	if index < 0:
		finished.emit()
		return
	var node := current_node()
	var ch: Dictionary = node.choices[index]
	if ch.get("once", false):
		state.flags[_once_key(index)] = true
	if ch.has("motivation"):
		_reward_motivation(index, ch.motivation)
	state.apply_effects(ch.get("effects", []))
	if ch.has("check"):
		var res := roll_check(ch.check)
		var band := check_band(res)
		var extra: Array = ch.check.get(band + "_effects", []) if band != "fail" else []
		check_rolled.emit(res.text, res.success, int(res.natural), band if not extra.is_empty() else "")
		state.apply_effects(ch.check.get("success_effects" if res.success else "fail_effects", []))
		state.apply_effects(extra)
		goto(ch.check.success if res.success else ch.check.fail)
		return
	if ch.get("end", false) or not ch.has("next"):
		finished.emit()
		return
	goto(ch.next)


## Test z automatycznym użyciem Heroicznej inspiracji przy porażce.
func roll_check(chk: Dictionary) -> Dictionary:
	var pc: Creature = state.player
	var dc := int(chk.dc)
	var adv := false
	if chk.has("adv_if") and state.check(chk.adv_if):
		adv = true
	var res: Dictionary
	if chk.has("skill"):
		res = Checks.skill_check(pc, chk.skill, dc, adv)
	else:
		res = Checks.ability_check(pc, chk.ability, dc, adv)
	var text: String = res.text
	if not res.success and pc.heroic_inspiration:
		pc.heroic_inspiration = false
		var res2: Dictionary
		if chk.has("skill"):
			res2 = Checks.skill_check(pc, chk.skill, dc, adv)
		else:
			res2 = Checks.ability_check(pc, chk.ability, dc, adv)
		text += Loc.t("\n  Heroiczna inspiracja, przerzut: ") + res2.text
		res = res2
	res.text = text
	return res


const BOON_MARGIN := 5   # sukces o tyle i więcej = korzyść; porażka o mniej = coś w zamian


## Pas wyniku testu według zapasu (suma − ST): "boon" | "cost" | "gain" | "fail".
static func check_band(res: Dictionary) -> String:
	var margin := int(res.total) - int(res.dc)
	if res.success:
		return "boon" if margin >= BOON_MARGIN else "cost"
	return "gain" if margin > -BOON_MARGIN else "fail"


## Naturalny wynik k20, który da w teście zapas `margin` (do wymuszania rzutów w narzędziach).
static func natural_for_margin(pc: Creature, chk: Dictionary, margin: int) -> int:
	var bonus := Checks.skill_bonus(pc, chk.skill) if chk.has("skill") else pc.mod(chk.ability)
	return clampi(int(chk.dc) + margin - bonus, 1, 20)


## Działanie zgodne z motywacją (także z wadą) daje Heroiczną inspirację, raz na opcję (ADR 0009).
func _reward_motivation(index: int, m: String) -> void:
	var key := "motiv_%s_%s_%d" % [dialogue_id, current_id, index]
	if state.has_flag(key):
		return
	state.flags[key] = true
	if state.player.heroic_inspiration:
		return
	state.player.heroic_inspiration = true
	state.add_log(Loc.t("Działasz zgodnie z sobą (%s): Heroiczna inspiracja.") % state.motivation_name(m))

